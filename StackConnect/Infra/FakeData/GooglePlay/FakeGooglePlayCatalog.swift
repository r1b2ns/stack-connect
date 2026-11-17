#if DEBUG
import Foundation
import StackCoreRust

/// The fake Google Play content: the "Northwind Labs" developer account with
/// four apps (matching the Play prototype), their tracks and releases, store
/// listings in several languages, app details and recent reviews. All names,
/// people, addresses and URLs are invented (`.example` domains only).
enum FakeGooglePlayCatalog {

    static let northwindClientEmail = "play-publisher@northwind-labs.iam.example"
    static let northwindProjectId = "northwind-labs-play"

    static func makeDevelopers(clock: FakeClock) -> [FakeGooglePlayDeveloper] {
        [FakeGooglePlayDeveloper(clientEmail: northwindClientEmail, clock: clock, state: northwind(clock: clock))]
    }

    // MARK: - Northwind Labs

    struct AppSeed: Sendable {
        let packageName: String
        let name: String
        let symbol: String
        let color: String
        let website: String
        let listings: [StoreListingInfo]
        let tracks: [TrackInfo]
        /// Review / publishing state (`RELEASE_LIFECYCLE_STATE_*`) per release,
        /// keyed by the release's first version code. Releases not listed are
        /// `DRAFT` when their status is `draft`, `PUBLISHED` otherwise.
        var lifecycles: [String: String] = [:]
        /// Version codes uploaded but not on any track yet (the bundle picker's
        /// candidates).
        var unreleasedBundles: [String] = []
        let reviews: [ReviewSeed]
    }

    struct ReviewSeed: Sendable {
        let rating: Int32
        let body: String
        let author: String
        let daysAgo: Double
        var reply: String? = nil
    }

    static let apps: [AppSeed] = [trailhead, ledger, mosaic, harbor]

    static func northwind(clock: FakeClock) -> FakeGooglePlayState {
        var state = FakeGooglePlayState()
        state.users = users(clock: clock)
        for app in apps {
            state.apps.append(AppInfo(id: app.packageName, name: app.name, bundleId: app.packageName, platform: "ANDROID"))
            state.iconUrls[app.packageName] = FakeMedia.iconURL(name: app.name, symbol: app.symbol, color: app.color)
            state.details[app.packageName] = AppDetailsInfo(
                appId: app.packageName, defaultLanguage: app.listings.first?.language,
                contactEmail: "android-support@northwind.example", contactPhone: "+1 415 555 0199",
                contactWebsite: app.website
            )
            state.listings[app.packageName] = app.listings
            state.tracks[app.packageName] = app.tracks
            state.lifecycles[app.packageName] = lifecycles(for: app)
            state.bundles[app.packageName] = bundles(for: app)
            state.reviews[app.packageName] = app.reviews.enumerated().map { index, review in
                let id = "\(app.packageName)/gp:AOqpTO\(FakeAppStoreConnectCatalog.slug(app.name).prefix(3).uppercased())\(index)x\(abs(FakeAppStoreConnectCatalog.hash(review.body)) % 100_000)"
                return CustomerReview(
                    id: id, rating: review.rating, title: nil, body: review.body, reviewerNickname: review.author,
                    createdDate: clock.iso(daysAgo: review.daysAgo), territory: nil,
                    response: review.reply.map { ReviewResponse(id: "\(id)/reply", body: $0, state: nil,
                                                                lastModifiedDate: clock.iso(daysAgo: max(review.daysAgo - 0.3, 0.05))) }
                )
            }
        }
        return state
    }

    /// Every release's lifecycle state, keyed by `FakeGooglePlayState.releaseKey`.
    private static func lifecycles(for app: AppSeed) -> [String: String] {
        var result: [String: String] = [:]
        for track in app.tracks {
            for release in track.releases {
                let seeded = release.versionCodes.first.flatMap { app.lifecycles[$0] }
                result[FakeGooglePlayState.releaseKey(track: track.track, versionCodes: release.versionCodes)] =
                    seeded ?? (release.status == "draft" ? FakeGooglePlayState.Lifecycle.draft : FakeGooglePlayState.Lifecycle.published)
            }
        }
        return result
    }

    /// Bundles for every version code on a track plus the unreleased ones,
    /// newest first, with a deterministic fake SHA-256.
    private static func bundles(for app: AppSeed) -> [BundleInfo] {
        let codes = Set(app.tracks.flatMap { $0.releases.flatMap(\.versionCodes) } + app.unreleasedBundles)
        return codes.sorted { (Int64($0) ?? 0) > (Int64($1) ?? 0) }.map { code in
            var random = FakeRandom(seed: "\(app.packageName)/\(code)")
            let sha = (0..<8).map { _ in String(format: "%08x", UInt32(truncatingIfNeeded: random.next())) }.joined()
            return BundleInfo(versionCode: code, sha256: sha)
        }
    }

    /// The Play Console developer account ID of the fake account (set on the
    /// seeded `AccountModel`; the fake users capability accepts any number).
    static let northwindDeveloperId = "4829103756618820931"

    /// The account's users (`developers/{id}/users`): two admins (a person and
    /// this account's own service account, which needs Admin to manage users), a
    /// release manager, a release engineer and a support agent with per-app
    /// grants, finance, a pending invitation, an expired invitation, an access
    /// that ran out and the CI service account.
    static func users(clock: FakeClock = FakeClock()) -> [PlayUserInfo] {
        func user(
            _ email: String,
            _ state: String = "ACCESS_GRANTED",
            expires: String? = nil,
            account: [String] = [],
            grants: [PlayGrantInfo] = []
        ) -> PlayUserInfo {
            PlayUserInfo(email: email, name: "developers/0/users/\(email)", accessState: state, expirationTime: expires,
                         developerAccountPermissions: account, grants: grants, partial: false)
        }
        func grant(_ packageName: String, _ permissions: [String]) -> PlayGrantInfo {
            PlayGrantInfo(packageName: packageName, appLevelPermissions: ["CAN_VIEW_NON_FINANCIAL_DATA"] + permissions)
        }
        return [
            user("dana.whitfield@northwind.example", account: ["CAN_MANAGE_PERMISSIONS_GLOBAL"]),
            user("omar.haddad@northwind.example",
                 account: ["CAN_VIEW_NON_FINANCIAL_DATA_GLOBAL", "CAN_VIEW_APP_QUALITY_GLOBAL", "CAN_MANAGE_PUBLIC_APKS_GLOBAL",
                           "CAN_MANAGE_TRACK_APKS_GLOBAL", "CAN_MANAGE_TRACK_USERS_GLOBAL"]),
            user("aiko.kimura@northwind.example", grants: [
                grant("com.northwind.trailhead", ["CAN_MANAGE_PUBLIC_APKS", "CAN_MANAGE_TRACK_APKS", "CAN_MANAGE_PUBLIC_LISTING", "CAN_REPLY_TO_REVIEWS"]),
                grant("com.northwind.ledger", ["CAN_REPLY_TO_REVIEWS"])
            ]),
            user("support@northwind.example", grants: [
                grant("com.northwind.trailhead", ["CAN_REPLY_TO_REVIEWS"]),
                grant("com.northwind.mosaic", ["CAN_REPLY_TO_REVIEWS"]),
                grant("com.northwind.harbor", ["CAN_REPLY_TO_REVIEWS"])
            ]),
            user("priya.raman@northwind.example",
                 account: ["CAN_VIEW_NON_FINANCIAL_DATA_GLOBAL", "CAN_VIEW_FINANCIAL_DATA_GLOBAL", "CAN_MANAGE_ORDERS_GLOBAL"]),
            user("kai.nakamura@contractor.example", "INVITED", expires: clock.iso(daysFromNow: 45),
                 grants: [grant("com.northwind.harbor", ["CAN_MANAGE_TRACK_APKS"])]),
            user("joana.lima@freelance.example", "INVITATION_EXPIRED",
                 grants: [grant("com.northwind.mosaic", ["CAN_MANAGE_TRACK_APKS", "CAN_MANAGE_TRACK_USERS"])]),
            user("lena.fischer@agency.example", "ACCESS_EXPIRED", expires: clock.iso(daysAgo: 12),
                 account: ["CAN_VIEW_NON_FINANCIAL_DATA_GLOBAL", "CAN_MANAGE_PUBLIC_LISTING_GLOBAL"]),
            user(northwindClientEmail, account: ["CAN_MANAGE_PERMISSIONS_GLOBAL"]),
            user("ci-publisher@northwind-labs.iam.example",
                 account: ["CAN_VIEW_NON_FINANCIAL_DATA_GLOBAL", "CAN_MANAGE_TRACK_APKS_GLOBAL", "CAN_MANAGE_PUBLIC_APKS_GLOBAL"])
        ]
    }

    private static func notes(_ entries: [(String, String)]) -> [LocalizedTextInfo] {
        entries.map { LocalizedTextInfo(language: $0.0, text: $0.1) }
    }

    // MARK: Trailhead

    static let trailhead = AppSeed(
        packageName: "com.northwind.trailhead", name: "Trailhead", symbol: "mountain.2.fill", color: "2E7D5B",
        website: "https://trailhead.northwind.example",
        listings: [
            StoreListingInfo(language: "en-US", title: "Trailhead: Offline Hiking Maps",
                             shortDescription: "Offline topo maps, route planning and GPS tracking for every trail.",
                             fullDescription: "Trailhead is the hiking companion that keeps working when the signal doesn't.\n\n• Download topographic maps for whole regions\n• Plan routes with live elevation profiles\n• Track pace, splits and ascent with battery-friendly GPS\n• See trail conditions reported by the community\n• Wear OS companion with haptic turn alerts",
                             video: "https://video.fakedata.example/trailhead-trailer"),
            StoreListingInfo(language: "pt-BR", title: "Trailhead: Mapas de Trilha",
                             shortDescription: "Mapas topográficos offline, rotas e GPS para todas as trilhas.",
                             fullDescription: "O Trailhead continua funcionando quando o sinal some.\n\n• Baixe mapas topográficos de regiões inteiras\n• Planeje rotas com perfil de elevação\n• Acompanhe ritmo e subida com GPS econômico",
                             video: nil),
            StoreListingInfo(language: "de-DE", title: "Trailhead: Offline-Wanderkarten",
                             shortDescription: "Topografische Offline-Karten, Tourenplanung und GPS-Tracking.",
                             fullDescription: "Trailhead funktioniert auch ohne Netz.\n\n• Topografische Karten ganzer Regionen\n• Tourenplanung mit Höhenprofil\n• Akkuschonendes GPS-Tracking",
                             video: nil),
            StoreListingInfo(language: "es-419", title: "Trailhead: Mapas de Senderismo",
                             shortDescription: "Mapas topográficos sin conexión, rutas y GPS.",
                             fullDescription: "Trailhead sigue funcionando cuando no hay señal: mapas topográficos, planificador de rutas y seguimiento GPS.",
                             video: nil),
            StoreListingInfo(language: "ja-JP", title: "Trailhead：オフライン登山地図",
                             shortDescription: "オフライン地形図、ルート計画、GPS記録。",
                             fullDescription: "電波が届かない場所でも使える登山アプリ。地形図のダウンロード、標高グラフ付きのルート計画、GPS記録に対応。",
                             video: nil)
        ],
        tracks: [
            TrackInfo(track: "production", releases: [
                TrackReleaseInfo(name: "4.2.0 (4210)", status: "inProgress", versionCodes: ["4210"], userFraction: 0.2,
                                 releaseNotes: notes([
                                    ("en-US", "• Shade forecast along every route\n• Up to 2× faster offline map downloads\n• Fixed elevation profile glitches"),
                                    ("pt-BR", "• Previsão de sombra ao longo da rota\n• Downloads de mapas até 2× mais rápidos"),
                                    ("de-DE", "• Schattenprognose entlang der Route\n• Schnellere Offline-Downloads")
                                 ]), inAppUpdatePriority: 2, countryTargeting: nil),
                TrackReleaseInfo(name: "4.1.2 (4122)", status: "completed", versionCodes: ["4122"], userFraction: nil,
                                 releaseNotes: notes([("en-US", "Bug fixes and stability improvements."),
                                                      ("pt-BR", "Correções de bugs e melhorias de estabilidade.")]),
                                 inAppUpdatePriority: 0, countryTargeting: nil)
            ]),
            TrackInfo(track: "beta", releases: [
                TrackReleaseInfo(name: "4.3.0-beta2 (4302)", status: "completed", versionCodes: ["4302"], userFraction: nil,
                                 releaseNotes: notes([("en-US", "Beta: low-power tracking mode and dark map style. Tell us how the battery holds up!")]),
                                 inAppUpdatePriority: 1, countryTargeting: nil)
            ]),
            TrackInfo(track: "internal", releases: [
                TrackReleaseInfo(name: "4.3.0 (4305)", status: "draft", versionCodes: ["4305"], userFraction: nil,
                                 releaseNotes: notes([("en-US", "Internal build: offline search and the new trail cards.")]),
                                 inAppUpdatePriority: nil, countryTargeting: nil),
                TrackReleaseInfo(name: "4.3.0 (4303)", status: "completed", versionCodes: ["4303"], userFraction: nil,
                                 releaseNotes: notes([("en-US", "Internal build: release candidate for 4.3.0.")]),
                                 inAppUpdatePriority: nil, countryTargeting: nil)
            ])
        ],
        lifecycles: ["4302": "RELEASE_LIFECYCLE_STATE_IN_REVIEW"],
        unreleasedBundles: ["4306"],
        reviews: [
            ReviewSeed(rating: 5, body: "Funciona perfeitamente offline. Fiz a travessia da Serra Fina sem sinal e o mapa não falhou nenhuma vez.", author: "Camila Ferreira", daysAgo: 0.2),
            ReviewSeed(rating: 4, body: "Great maps and the Wear OS app is handy. Battery use is a bit high during long hikes.", author: "Marcus Bell", daysAgo: 0.9, reply: "Thanks Marcus! A low-power tracking mode is in our beta right now — join from the Play Store listing to try it."),
            ReviewSeed(rating: 5, body: "Die beste Wander-App, die ich kenne. Höhenprofil und Zeitangaben stimmen sehr genau.", author: "Jonas Keller", daysAgo: 1.4),
            ReviewSeed(rating: 2, body: "La descarga de mapas grandes se detiene en mi Pixel 7. Tuve que reintentar varias veces.", author: "Lucía Romero", daysAgo: 2.1, reply: "¡Lo sentimos! La versión 4.2.0 reanuda las descargas grandes automáticamente. ¿Puedes actualizar y contarnos?"),
            ReviewSeed(rating: 5, body: "Planned a whole week in the Dolomites with it. Water sources and huts are spot on.", author: "Priyanka Das", daysAgo: 3),
            ReviewSeed(rating: 3, body: "Bom app, mas sinto falta de compartilhar rotas com quem usa iPhone.", author: "Rafael Souza", daysAgo: 4.2),
            ReviewSeed(rating: 1, body: "App crashes when I open a downloaded region on my Galaxy A54.", author: "Tom Hughes", daysAgo: 5, reply: "Sorry Tom — this crash is fixed in 4.2.0, which is rolling out now. Please update when it reaches you."),
            ReviewSeed(rating: 5, body: "Super appli, cartes très lisibles même en plein soleil.", author: "Élise Moreau", daysAgo: 6.1)
        ]
    )

    // MARK: Ledger Pocket

    static let ledger = AppSeed(
        packageName: "com.northwind.ledger", name: "Ledger Pocket", symbol: "chart.pie.fill", color: "3558C9",
        website: "https://ledger.northwind.example",
        listings: [
            StoreListingInfo(language: "en-US", title: "Ledger Pocket: Budget & Bills",
                             shortDescription: "Envelope budgets, bill reminders and shared expenses in one place.",
                             fullDescription: "Ledger Pocket turns your spending into a plan you can keep.\n\n• Envelope budgets that roll over\n• Bill calendar with reminders\n• Shared ledgers for trips and households\n• Import CSV statements from any bank",
                             video: nil),
            StoreListingInfo(language: "pt-BR", title: "Ledger Pocket: Orçamento",
                             shortDescription: "Orçamentos por envelope, lembretes de contas e despesas divididas.",
                             fullDescription: "Transforme seus gastos em um plano possível de cumprir, com orçamentos por envelope e despesas compartilhadas.",
                             video: nil),
            StoreListingInfo(language: "fr-FR", title: "Ledger Pocket : Budget",
                             shortDescription: "Budgets par enveloppe, rappels de factures et dépenses partagées.",
                             fullDescription: "Ledger Pocket transforme vos dépenses en un plan que vous pouvez tenir.",
                             video: nil)
        ],
        tracks: [
            TrackInfo(track: "production", releases: [
                TrackReleaseInfo(name: "2.8.1 (2811)", status: "completed", versionCodes: ["2811"], userFraction: nil,
                                 releaseNotes: notes([("en-US", "• Multi-currency ledgers\n• Faster bank sync"),
                                                      ("pt-BR", "• Livros-caixa em várias moedas\n• Sincronização bancária mais rápida")]),
                                 inAppUpdatePriority: 2, countryTargeting: nil),
                TrackReleaseInfo(name: "2.7.0 (2704)", status: "halted", versionCodes: ["2704"], userFraction: 0.1,
                                 releaseNotes: notes([("en-US", "• Settle up shared ledgers in one tap\n• Monthly report with category trends"),
                                                      ("pt-BR", "• Acerto de contas com um toque\n• Novo relatório mensal")]),
                                 inAppUpdatePriority: 1, countryTargeting: nil),
                TrackReleaseInfo(name: "2.6.3 (2631)", status: "completed", versionCodes: ["2631"], userFraction: nil,
                                 releaseNotes: notes([("en-US", "Sync status is clearer and CSV import supports more banks.")]),
                                 inAppUpdatePriority: 0, countryTargeting: nil)
            ]),
            TrackInfo(track: "alpha", releases: [
                TrackReleaseInfo(name: "2.8.0 (2801)", status: "completed", versionCodes: ["2801"], userFraction: nil,
                                 releaseNotes: notes([("en-US", "Closed test: multi-currency ledgers.")]),
                                 inAppUpdatePriority: nil, countryTargeting: nil)
            ]),
            TrackInfo(track: "internal", releases: [
                TrackReleaseInfo(name: "2.8.0 (2802)", status: "completed", versionCodes: ["2802"], userFraction: nil,
                                 releaseNotes: notes([("en-US", "Internal: fixes rounding in converted totals.")]),
                                 inAppUpdatePriority: nil, countryTargeting: nil)
            ])
        ],
        lifecycles: ["2811": "RELEASE_LIFECYCLE_STATE_APPROVED_NOT_PUBLISHED"],
        unreleasedBundles: ["2812"],
        reviews: [
            ReviewSeed(rating: 5, body: "Finally an app that makes envelope budgeting easy. The rollover is genius.", author: "Hannah Price", daysAgo: 0.5),
            ReviewSeed(rating: 1, body: "Depois da atualização meus lançamentos sumiram! Já é a segunda vez.", author: "Patrícia Lima", daysAgo: 1.1, reply: "Oi Patrícia, seus dados estão seguros: pausamos a versão 2.7.0 enquanto corrigimos a sincronização. Puxe para atualizar na aba Lançamentos."),
            ReviewSeed(rating: 4, body: "Sehr übersichtlich. Ein Widget mit dem Restbudget wäre toll.", author: "Lena Hoffmann", daysAgo: 2.6),
            ReviewSeed(rating: 3, body: "CSV import didn't recognise my bank's date format.", author: "Kwame Mensah", daysAgo: 3.8),
            ReviewSeed(rating: 5, body: "On partage toutes les dépenses de la coloc avec, plus aucune dispute !", author: "Inès Laurent", daysAgo: 5.5)
        ]
    )

    // MARK: Mosaic Notes

    static let mosaic = AppSeed(
        packageName: "com.northwind.mosaic", name: "Mosaic Notes", symbol: "square.grid.2x2.fill", color: "8E44AD",
        website: "https://mosaic.northwind.example",
        listings: [
            StoreListingInfo(language: "en-US", title: "Mosaic Notes: Boards & Sketches",
                             shortDescription: "Visual notes on infinite boards — sketch, link and outline your ideas.",
                             fullDescription: "Mosaic Notes is a canvas for thinking. Pin notes, photos, links and sketches onto boards, connect ideas with arrows and switch to an outline whenever you need structure.\n\n• Infinite boards with smart alignment\n• Stylus sketching\n• Outline view\n• Shared boards with live cursors",
                             video: "https://video.fakedata.example/mosaic-tour"),
            StoreListingInfo(language: "pt-BR", title: "Mosaic Notes: Quadros",
                             shortDescription: "Notas visuais em quadros infinitos.",
                             fullDescription: "Fixe notas, fotos, links e desenhos em quadros e conecte suas ideias.",
                             video: nil),
            StoreListingInfo(language: "es-ES", title: "Mosaic Notes: Tableros",
                             shortDescription: "Notas visuales en tableros infinitos.",
                             fullDescription: "Notas, fotos, enlaces y bocetos conectados en tableros infinitos.",
                             video: nil),
            StoreListingInfo(language: "hi-IN", title: "Mosaic Notes: बोर्ड और स्केच",
                             shortDescription: "अनंत बोर्ड पर विज़ुअल नोट्स।",
                             fullDescription: "नोट्स, फ़ोटो, लिंक और स्केच को बोर्ड पर जोड़ें और विचारों को जोड़ें।",
                             video: nil)
        ],
        tracks: [
            TrackInfo(track: "production", releases: [
                TrackReleaseInfo(name: "5.2.0 (5206)", status: "completed", versionCodes: ["5206"], userFraction: nil,
                                 releaseNotes: notes([("en-US", "• Tags across boards\n• Handwriting search")]),
                                 inAppUpdatePriority: 1, countryTargeting: nil),
                TrackReleaseInfo(name: "5.1.0 (5106)", status: "completed", versionCodes: ["5106"], userFraction: nil,
                                 releaseNotes: notes([("en-US", "• 24 new board templates\n• Link previews for videos and maps"),
                                                      ("es-ES", "• 24 plantillas nuevas\n• Vista previa de enlaces")]),
                                 inAppUpdatePriority: 0, countryTargeting: nil)
            ]),
            TrackInfo(track: "beta", releases: [
                TrackReleaseInfo(name: "5.2.0 (5201)", status: "draft", versionCodes: ["5201"], userFraction: nil,
                                 releaseNotes: notes([("en-US", "Open beta: tags across boards.")]),
                                 inAppUpdatePriority: nil, countryTargeting: nil)
            ]),
            TrackInfo(track: "internal", releases: [
                TrackReleaseInfo(name: "5.2.0 (5202)", status: "completed", versionCodes: ["5202"], userFraction: nil,
                                 releaseNotes: notes([("en-US", "Internal: tag browser and sync fixes.")]),
                                 inAppUpdatePriority: nil, countryTargeting: nil)
            ])
        ],
        lifecycles: ["5206": "RELEASE_LIFECYCLE_STATE_NOT_APPROVED"],
        unreleasedBundles: ["5207"],
        reviews: [
            ReviewSeed(rating: 5, body: "Best whiteboard app on Android, and the outline view is brilliant for studying.", author: "Aarav Sharma", daysAgo: 0.7, reply: "Thank you Aarav! Tags across boards are coming in 5.2."),
            ReviewSeed(rating: 4, body: "Uso com a caneta do meu tablet Samsung e funciona muito bem.", author: "Juliana Alves", daysAgo: 1.9),
            ReviewSeed(rating: 2, body: "Sync between my phone and tablet duplicates cards sometimes.", author: "Ben Carter", daysAgo: 3.3),
            ReviewSeed(rating: 5, body: "Ideal para preparar mis clases. Las plantillas son geniales.", author: "Marta Gil", daysAgo: 4.4),
            ReviewSeed(rating: 5, body: "Wunderbar für Workshops mit Kunden.", author: "Felix Braun", daysAgo: 6.3)
        ]
    )

    // MARK: Harbor Transit

    static let harbor = AppSeed(
        packageName: "com.northwind.harbor", name: "Harbor Transit", symbol: "tram.fill", color: "C0392B",
        website: "https://harbor.northwind.example",
        listings: [
            StoreListingInfo(language: "en-US", title: "Harbor Transit: Live Departures",
                             shortDescription: "Real-time buses, trams and ferries with offline timetables.",
                             fullDescription: "Harbor Transit shows live departures for buses, trams and ferries, plans door-to-door trips and keeps timetables offline for when you're underground.",
                             video: nil),
            StoreListingInfo(language: "pt-PT", title: "Harbor Transit: Partidas",
                             shortDescription: "Autocarros, elétricos e ferries em tempo real.",
                             fullDescription: "Partidas em tempo real e horários offline.",
                             video: nil),
            StoreListingInfo(language: "nl-NL", title: "Harbor Transit: Vertrektijden",
                             shortDescription: "Live vertrektijden van bus, tram en veerboot.",
                             fullDescription: "Live vertrektijden, reisplanner en offline dienstregelingen.",
                             video: nil)
        ],
        tracks: [
            TrackInfo(track: "production", releases: [
                TrackReleaseInfo(name: "1.9.0 (190)", status: "completed", versionCodes: ["190"], userFraction: nil,
                                 releaseNotes: notes([("en-US", "• Ferry departures with live positions\n• Offline timetables for 12 more cities")]),
                                 inAppUpdatePriority: 0, countryTargeting: nil)
            ]),
            TrackInfo(track: "city-partners", releases: [
                TrackReleaseInfo(name: "2.0.0 (200)", status: "completed", versionCodes: ["200"], userFraction: nil,
                                 releaseNotes: notes([("en-US", "Partner preview: accessibility routing and step-free stations.")]),
                                 inAppUpdatePriority: nil,
                                 countryTargeting: CountryTargetingInfo(countries: ["US", "CA"], includeRestOfWorld: false))
            ]),
            TrackInfo(track: "internal", releases: [
                TrackReleaseInfo(name: "2.0.0 (201)", status: "completed", versionCodes: ["201"], userFraction: nil,
                                 releaseNotes: notes([("en-US", "Internal: new map renderer.")]),
                                 inAppUpdatePriority: nil, countryTargeting: nil)
            ])
        ],
        lifecycles: ["201": "RELEASE_LIFECYCLE_STATE_NOT_SENT_FOR_REVIEW"],
        unreleasedBundles: ["202"],
        reviews: [
            ReviewSeed(rating: 4, body: "Live ferry positions are great. Wish it had a home-screen widget.", author: "Sanne de Vries", daysAgo: 1.3),
            ReviewSeed(rating: 5, body: "Os horários offline salvam-me no metro todos os dias.", author: "Tiago Mendes", daysAgo: 2.8, reply: "Obrigado, Tiago! Boas viagens."),
            ReviewSeed(rating: 3, body: "Departures are sometimes a minute or two off.", author: "Oliver Grant", daysAgo: 5.2)
        ]
    )
}
#endif
