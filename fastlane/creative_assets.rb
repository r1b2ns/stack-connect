# creative_assets.rb — uploads the App Store "Header and Search Results"
# creative assets (product page header + organic search results images).
#
# fastlane 2.232–2.242 `deliver` cannot upload these yet (fastlane/fastlane
# issue #30461, PR #30442 still open), so this talks to the App Store Connect
# API (App Asset Library, API 4.5) directly through spaceship's authenticated
# client. Remove it once `deliver(creative_assets: ...)` ships.
#
# Files (per locale, next to the rest of the metadata):
#   fastlane/metadata/<locale>/creative_assets/header.png          5244 × 2950 (or 3840 × 1646)
#   fastlane/metadata/<locale>/creative_assets/search_results.png  3840 × 2560 (3:2, or 5244 × 2950)
#
# Flow (mirrors Apple's documented workflow):
#   1. GET  /v1/appAssetLibraryRefData            → placement groups + image specs
#   2. GET  /v1/apps/{id}/assetLibrary            → the app's asset library
#   3. POST /v1/appAssetLibraryImages             → reserve, upload parts, PATCH uploaded
#   4. poll /v1/appAssetLibraryImages/{id}        → processed, read its specId
#   5. POST /v1/appAssetLibraryPlacements         → place it on the version localization
#      (placements are immutable: replacing = DELETE old + POST new)

require 'spaceship'

module CreativeAssets
  HEADER = 'PRODUCT_PAGE_HEADER_ASSET'.freeze
  SEARCH = 'APP_STORE_SEARCH_RESULTS_ASSET'.freeze
  CATEGORY = 'CREATIVE_ASSETS'.freeze
  FEATURE_ID = 'APP_STORE_VERSIONS'.freeze
  EDITABLE_STATES = %w[PREPARE_FOR_SUBMISSION DEVELOPER_REJECTED REJECTED METADATA_REJECTED INVALID_BINARY].freeze
  READY_STATES = %w[PREPARE_FOR_SUBMISSION READY_FOR_REVIEW WAITING_FOR_REVIEW IN_REVIEW ACCEPTED APPROVED].freeze
  FAILED_STATES = %w[FAILED REJECTED ARCHIVED].freeze

  # file name → placement type. The placement group is resolved from Apple's
  # reference data by matching the image's pixel size to an image spec.
  # Apple allows one image per placement type and locale (group
  # DEFAULT_PROFILE, maxCount 1). The header may be 16:9 (5244 × 2950) or
  # 21:9 (3840 × 1646); search results 16:9 or 3:2 (1920–3840 wide). No alpha.
  FILES = {
    'header.png' => HEADER,
    'search_results.png' => SEARCH
  }.freeze

  module_function

  def api
    Spaceship::ConnectAPI.client.tunes_request_client
  end

  def data(response)
    body = response.respond_to?(:body) ? response.body : response
    body['data']
  end

  # ── Reference data ──────────────────────────────────────────────────────────

  def reference
    @reference ||= begin
      list = data(api.get('v1/appAssetLibraryRefData'))
      raise 'Apple returned no asset library reference data' if list.nil? || list.empty?
      list.first['attributes']
    end
  end

  def image_specs
    reference['imageSpecs'] || []
  end

  # Prints what Apple currently accepts, so placement groups never have to be
  # hard-coded. Read-only.
  def print_catalog
    [HEADER, SEARCH].each do |type_id|
      type = (reference['placementTypes'] || []).find { |t| t['placementTypeId'] == type_id }
      puts "\n#{type_id}"
      unless type
        puts '  (not in reference data)'
        next
      end
      (type['specMappings'] || []).each do |mapping|
        puts "  group #{mapping['placementGroupId']}"
        (mapping['specs'] || []).each do |spec_id|
          spec = image_specs.find { |s| s['specId'] == spec_id || s['id'] == spec_id }
          puts "    spec #{spec_id}: #{spec ? spec.reject { |k, _| %w[specId id].include?(k) }.to_json : '(video or unknown)'}"
        end
      end
    end
    policies = (reference['features'] || []).find { |f| f['featureId'] == FEATURE_ID }
    puts "\n#{FEATURE_ID} placement policies:"
    puts JSON.pretty_generate(policies ? policies['placementPolicies'] : [])
  end

  # Groups of `type_id` that accept an image of this size, according to the
  # reference data. Spec dimension keys are read defensively because Apple's
  # schema is new; anything unrecognised falls back to "all groups".
  def groups_for(type_id, width, height, path = nil)
    type = (reference['placementTypes'] || []).find { |t| t['placementTypeId'] == type_id }
    raise "#{type_id} is not in Apple's reference data" unless type

    mappings = type['specMappings'] || []
    matching = mappings.select do |mapping|
      (mapping['specs'] || []).any? do |spec_id|
        spec = image_specs.find { |s| s['specId'] == spec_id || s['id'] == spec_id }
        spec && spec_accepts?(spec, width, height, path)
      end
    end
    matching.map { |m| m['placementGroupId'] }
  end

  # Image spec shape (from Apple's reference data):
  #   "dimensions": { "minWidth", "maxWidth", "minHeight", "maxHeight" },
  #   "aspectRatio": "16:9", "fileExtensions": [".png"], "alphaAllowed": false
  def spec_accepts?(spec, width, height, path = nil)
    dims = spec['dimensions']
    return false unless dims.kind_of?(Hash)
    return false unless width.between?(dims['minWidth'].to_i, dims['maxWidth'].to_i)
    return false unless height.between?(dims['minHeight'].to_i, dims['maxHeight'].to_i)

    # Apple's ratios are nominal (5244 × 2950 is "16:9" but not exact), so
    # allow 1% tolerance; the min/max dimensions above are the hard limit.
    if spec['aspectRatio'].to_s =~ /\A(\d+):(\d+)\z/
      expected = Regexp.last_match(1).to_f / Regexp.last_match(2).to_f
      return false unless ((width.to_f / height) - expected).abs / expected <= 0.01
    end
    if path && spec['fileExtensions'].kind_of?(Array)
      return false unless spec['fileExtensions'].include?(File.extname(path).downcase)
    end
    true
  end

  def has_alpha?(path)
    `sips -g hasAlpha "#{path}" 2>/dev/null`[/hasAlpha: (\w+)/, 1] == 'yes'
  end

  # ── Upload ──────────────────────────────────────────────────────────────────

  def pixel_size(path)
    out = `sips -g pixelWidth -g pixelHeight "#{path}" 2>/dev/null`
    w = out[/pixelWidth: (\d+)/, 1].to_i
    h = out[/pixelHeight: (\d+)/, 1].to_i
    raise "Could not read the size of #{path}" if w.zero? || h.zero?
    [w, h]
  end

  def editable_version(app)
    version = app.get_edit_app_store_version(platform: Spaceship::ConnectAPI::Platform::IOS)
    raise 'No editable iOS App Store version found' unless version
    unless EDITABLE_STATES.include?(version.app_version_state)
      raise "Version #{version.version_string} is #{version.app_version_state}; creative assets can only be placed on an editable version"
    end
    version
  end

  def placements(localization_id)
    data(api.get("v1/appStoreVersionLocalizations/#{localization_id}/placements")) || []
  end

  def upload_image(library_id, path)
    bytes = File.binread(path)
    body = {
      data: {
        type: 'appAssetLibraryImages',
        attributes: { fileName: File.basename(path), fileSize: bytes.bytesize, category: CATEGORY },
        relationships: { assetLibrary: { data: { type: 'appAssetLibraries', id: library_id } } }
      }
    }
    image = data(api.post('v1/appAssetLibraryImages', body, tries: 1))
    Spaceship::ConnectAPI::FileUploader.upload(image['attributes']['uploadOperations'], bytes)
    patch = { data: { type: 'appAssetLibraryImages', id: image['id'], attributes: { uploaded: true } } }
    image = data(api.patch("v1/appAssetLibraryImages/#{image['id']}", patch))

    deadline = Time.now + 300
    loop do
      state = image['attributes']['state']
      return image if READY_STATES.include?(state)
      raise "Apple failed to process #{File.basename(path)}: #{state} #{image['attributes']['stateDetails']}" if FAILED_STATES.include?(state)
      raise "Timed out waiting for #{File.basename(path)} (image #{image['id']}) to process" if Time.now > deadline

      sleep(2)
      image = data(api.get("v1/appAssetLibraryImages/#{image['id']}"))
    end
  end

  def create_placement(localization_id, image_id, type_id, group_id)
    body = {
      data: {
        type: 'appAssetLibraryPlacements',
        attributes: { placementType: type_id, placementGroup: group_id },
        relationships: {
          image: { data: { type: 'appAssetLibraryImages', id: image_id } },
          appStoreVersionLocalization: { data: { type: 'appStoreVersionLocalizations', id: localization_id } }
        }
      }
    }
    api.post('v1/appAssetLibraryPlacements', body, tries: 1)
  end

  # Plans every target first (read-only). With dry_run it stops there; otherwise
  # it uploads all images, then (only if every image matches its group) replaces
  # the placements. Existing placements are kept unless overwrite is true.
  def run(app_identifier:, metadata_path:, locales: nil, dry_run: true, overwrite: false)
    app = Spaceship::ConnectAPI::App.find(app_identifier)
    raise "App #{app_identifier} not found" unless app

    version = editable_version(app)
    localizations = version.get_app_store_version_localizations
    puts "App #{app.name} (#{app.id}) — version #{version.version_string} (#{version.app_version_state})"

    plans = []
    Dir.glob(File.join(metadata_path, '*', 'creative_assets')).sort.each do |dir|
      locale = File.basename(File.dirname(dir))
      next if locales && !locales.include?(locale)

      localization = localizations.find { |l| l.locale == locale }
      unless localization
        puts "  #{locale}: skipped (the version has no #{locale} localization)"
        next
      end
      existing = placements(localization.id)

      FILES.each do |file, type_id|
        path = File.join(dir, file)
        next unless File.file?(path)

        width, height = pixel_size(path)
        raise "#{locale}/#{file} has an alpha channel; Apple requires opaque images" if has_alpha?(path)

        groups = groups_for(type_id, width, height, path)
        raise "#{locale}/#{file} (#{width}×#{height}) matches no #{type_id} group in Apple's reference data — run `fastlane creative_assets_catalog`" if groups.empty?
        raise "#{locale}/#{file} matches several #{type_id} groups (#{groups.join(', ')}); pick one explicitly" if groups.size > 1

        group = groups.first
        occupied = existing.select do |p|
          p['attributes']['placementType'] == type_id && p['attributes']['placementGroup'] == group
        end
        if !occupied.empty? && !overwrite
          raise "#{locale}: #{type_id}/#{group} already has an image; rerun with overwrite:true to replace it"
        end

        plans << { locale: locale, file: file, path: path, type: type_id, group: group,
                   localization_id: localization.id, occupied: occupied }
        puts "  #{locale}: #{file} (#{width}×#{height}) → #{type_id} / #{group}#{occupied.empty? ? '' : ' (replaces current)'}"
      end
    end
    raise "No creative assets found under #{metadata_path}/<locale>/creative_assets" if plans.empty?
    if dry_run
      puts "\nDry run: nothing was uploaded. Rerun with dry_run:false to upload."
      return plans
    end

    library = data(api.get("v1/apps/#{app.id}/assetLibrary"))
    library = library.first if library.kind_of?(Array)
    raise 'Apple returned no asset library for this app' unless library

    allowed_specs = lambda do |plan|
      type = reference['placementTypes'].find { |t| t['placementTypeId'] == plan[:type] }
      type['specMappings'].find { |m| m['placementGroupId'] == plan[:group] }['specs']
    end

    # Upload everything first; stop before touching placements if any image
    # is rejected or lands on an unexpected spec.
    plans.each do |plan|
      puts "Uploading #{plan[:locale]}/#{plan[:file]}..."
      image = upload_image(library['id'], plan[:path])
      spec_id = image['attributes']['specId']
      unless allowed_specs.call(plan).include?(spec_id)
        raise "#{plan[:locale]}/#{plan[:file]} was processed as spec #{spec_id.inspect}, not accepted by #{plan[:type]}/#{plan[:group]}; no placements were changed"
      end
      plan[:image_id] = image['id']
    end

    plans.each do |plan|
      plan[:occupied].each { |p| api.delete("v1/appAssetLibraryPlacements/#{p['id']}") }
      create_placement(plan[:localization_id], plan[:image_id], plan[:type], plan[:group])
      puts "Placed #{plan[:locale]}/#{plan[:file]} → #{plan[:type]} / #{plan[:group]}"
    end
    plans
  end
end
