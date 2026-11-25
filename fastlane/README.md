fastlane documentation
----

# Installation

Make sure you have the latest version of the Xcode command line tools installed:

```sh
xcode-select --install
```

For _fastlane_ installation instructions, see [Installing _fastlane_](https://docs.fastlane.tools/#installing-fastlane)

# Available Actions

## iOS

### ios test

```sh
[bundle exec] fastlane ios test
```

Run unit tests on the simulator.

    Usage:
      bundle exec fastlane test

### ios beta

```sh
[bundle exec] fastlane ios beta
```

Build and upload a new beta to TestFlight.

    Usage:
      bundle exec fastlane beta

### ios screenshots

```sh
[bundle exec] fastlane ios screenshots
```

Upload App Store screenshots without building.

    Only the locales present in the screenshots folder are touched. With overwrite:true the
    existing screenshots of those locales are deleted first (other locales keep theirs).

    Usage:
      bundle exec fastlane screenshots
      bundle exec fastlane screenshots path:/abs/folder overwrite:true

### ios metadata

```sh
[bundle exec] fastlane ios metadata
```

Upload App Store metadata (description, keywords, URLs) without building.

    Usage:
      bundle exec fastlane metadata

### ios creative_assets_catalog

```sh
[bundle exec] fastlane ios creative_assets_catalog
```

List the placement groups and image specs Apple accepts for the product page header and search results (read-only).

    Usage:
      bundle exec fastlane creative_assets_catalog

### ios creative_assets

```sh
[bundle exec] fastlane ios creative_assets
```

Upload the Header and Search Results images from metadata/<locale>/creative_assets/ to the editable version.

    Dry run by default (plans only, uploads nothing).

    Usage:
      bundle exec fastlane creative_assets
      bundle exec fastlane creative_assets dry_run:false
      bundle exec fastlane creative_assets dry_run:false overwrite:true locales:en-US,pt-BR

### ios release

```sh
[bundle exec] fastlane ios release
```

Build and submit a new version to the App Store.

    Usage:
      bundle exec fastlane release

----

This README.md is auto-generated and will be re-generated every time [_fastlane_](https://fastlane.tools) is run.

More information about _fastlane_ can be found on [fastlane.tools](https://fastlane.tools).

The documentation of _fastlane_ can be found on [docs.fastlane.tools](https://docs.fastlane.tools).
