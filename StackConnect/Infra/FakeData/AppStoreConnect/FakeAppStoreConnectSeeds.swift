#if DEBUG
import Foundation

// The fake App Store Connect content: two teams, seven apps. Every company,
// person, address and URL here is invented (`.example` domains only).

extension FakeAppStoreConnectCatalog {

    // MARK: - Accounts

    static let northwindIssuerId = "3f6c1d52-8a4e-4b7f-9e21-6d0b5a9c4e17"
    static let personalIssuerId = "a92e4b10-7c3d-4f58-b6e1-0d8c2f5a7b93"

    static let teamSeeds: [FakeASCTeamSeed] = [northwind, personal]

    // MARK: - Northwind Labs (company team)

    static let northwind = FakeASCTeamSeed(
        issuerId: northwindIssuerId,
        name: "Northwind Labs",
        teamId: "NW7Q2K9L4M",
        apps: [trailhead, ledger, mosaic, lumen, orbit],
        people: [
            FakeASCPersonSeed(firstName: "Avery", lastName: "Chen", email: "avery.chen@northwind.example",
                              roles: ["ACCOUNT_HOLDER", "ADMIN"], provisioningAllowed: true),
            FakeASCPersonSeed(firstName: "Mateus", lastName: "Rocha", email: "mateus.rocha@northwind.example",
                              roles: ["ADMIN"], provisioningAllowed: true),
            FakeASCPersonSeed(firstName: "Priya", lastName: "Raman", email: "priya.raman@northwind.example",
                              roles: ["APP_MANAGER", "ACCESS_TO_REPORTS"], provisioningAllowed: true),
            FakeASCPersonSeed(firstName: "Lukas", lastName: "Brenner", email: "lukas.brenner@northwind.example",
                              roles: ["DEVELOPER"], allAppsVisible: false, provisioningAllowed: true,
                              visibleAppIds: ["6479201102", "6479201105"]),
            FakeASCPersonSeed(firstName: "Sofia", lastName: "Marquez", email: "sofia.marquez@northwind.example",
                              roles: ["MARKETING", "ACCESS_TO_REPORTS"]),
            FakeASCPersonSeed(firstName: "Hana", lastName: "Sato", email: "hana.sato@northwind.example",
                              roles: ["CUSTOMER_SUPPORT"], allAppsVisible: false,
                              visibleAppIds: ["6479201101", "6479201103"]),
            FakeASCPersonSeed(firstName: "Omar", lastName: "Haddad", email: "omar.haddad@northwind.example",
                              roles: ["FINANCE", "SALES"], isTester: false),
            FakeASCPersonSeed(firstName: "Elena", lastName: "Petrova", email: "elena.petrova@northwind.example",
                              roles: ["DEVELOPER"], isPending: true, isTester: false),
            FakeASCPersonSeed(firstName: "Noah", lastName: "Fischer", email: "noah.fischer@northwind.example",
                              roles: ["APP_MANAGER"], allAppsVisible: false, isPending: true,
                              visibleAppIds: ["6479201104"], isTester: false)
        ],
        devices: [
            FakeASCDeviceSeed(name: "Avery's iPhone 16 Pro", platform: "IOS", deviceClass: "IPHONE", model: "iPhone 16 Pro", addedDaysAgo: 310),
            FakeASCDeviceSeed(name: "QA iPhone 15", platform: "IOS", deviceClass: "IPHONE", model: "iPhone 15", addedDaysAgo: 402),
            FakeASCDeviceSeed(name: "QA iPhone SE (3rd generation)", platform: "IOS", deviceClass: "IPHONE", model: "iPhone SE (3rd generation)", addedDaysAgo: 520),
            FakeASCDeviceSeed(name: "Mateus' iPhone 17", platform: "IOS", deviceClass: "IPHONE", model: "iPhone 17", addedDaysAgo: 45),
            FakeASCDeviceSeed(name: "Design iPad Pro 13\"", platform: "IOS", deviceClass: "IPAD", model: "iPad Pro 13-inch (M4)", addedDaysAgo: 233),
            FakeASCDeviceSeed(name: "Support iPad mini", platform: "IOS", deviceClass: "IPAD", model: "iPad mini (A17 Pro)", addedDaysAgo: 140),
            FakeASCDeviceSeed(name: "Build Mac Studio", platform: "MAC_OS", deviceClass: "MAC", model: "Mac Studio (M2 Max)", addedDaysAgo: 610),
            FakeASCDeviceSeed(name: "Lukas' MacBook Pro", platform: "MAC_OS", deviceClass: "MAC", model: "MacBook Pro 14-inch (M4 Pro)", addedDaysAgo: 88),
            FakeASCDeviceSeed(name: "Lab Apple TV 4K", platform: "IOS", deviceClass: "APPLE_TV", model: "Apple TV 4K (3rd generation)", addedDaysAgo: 275),
            FakeASCDeviceSeed(name: "Studio Vision Pro", platform: "IOS", deviceClass: "APPLE_VISION_PRO", model: "Apple Vision Pro", addedDaysAgo: 190),
            FakeASCDeviceSeed(name: "Old QA iPhone 12", platform: "IOS", deviceClass: "IPHONE", model: "iPhone 12", status: "DISABLED", addedDaysAgo: 980)
        ],
        certificates: [
            FakeASCCertificateSeed(type: "DISTRIBUTION", owner: "Northwind Labs", expiresInDays: 214),
            FakeASCCertificateSeed(type: "DEVELOPMENT", owner: "Mateus Rocha", expiresInDays: 301),
            FakeASCCertificateSeed(type: "DEVELOPMENT", owner: "Lukas Brenner", expiresInDays: 18),
            FakeASCCertificateSeed(type: "DEVELOPER_ID_APPLICATION", owner: "Northwind Labs", expiresInDays: 1460),
            FakeASCCertificateSeed(type: "MAC_INSTALLER_DISTRIBUTION", owner: "Northwind Labs", expiresInDays: 322)
        ]
    )

    // MARK: Trailhead

    static let trailhead = FakeASCAppSeed(
        id: "6479201101", name: "Trailhead", bundleId: "com.northwind.trailhead", sku: "NW-TRAILHEAD",
        symbol: "mountain.2.fill", color: "2E7D5B",
        primaryCategory: "NAVIGATION", secondaryCategory: "TRAVEL",
        versions: [
            FakeASCVersionSeed(platform: "IOS", version: "4.2.0", state: "READY_FOR_SALE", createdDaysAgo: 9, build: "4210", phasedDay: 3, submittedDaysAgo: 6),
            FakeASCVersionSeed(platform: "IOS", version: "4.1.2", state: "REPLACED_WITH_NEW_VERSION", createdDaysAgo: 34, build: "4122", submittedDaysAgo: 32),
            FakeASCVersionSeed(platform: "IOS", version: "4.1.0", state: "REPLACED_WITH_NEW_VERSION", createdDaysAgo: 61, build: "4100", submittedDaysAgo: 58),
            FakeASCVersionSeed(platform: "IOS", version: "4.0.0", state: "REPLACED_WITH_NEW_VERSION", createdDaysAgo: 118, build: "4000", submittedDaysAgo: 113)
        ],
        texts: [
            ("en-US", FakeASCLocalizedText(
                name: "Trailhead", subtitle: "Offline hiking maps & GPS",
                description: "Trailhead is the hiking companion that keeps working when the signal doesn't. Download topographic maps for whole regions, plan routes with live elevation profiles and follow them turn by turn — completely offline.\n\n• Detailed topo maps with contour lines, huts and water sources\n• Route planner with distance, ascent and time estimates\n• Live tracking with pace, splits and battery-friendly GPS\n• Trail conditions reported by the community\n• Apple Watch companion with haptic turn alerts",
                keywords: "hiking,trail,topo,offline maps,gps,backpacking,trekking,outdoor",
                promotionalText: "New: shade and sun exposure along every route — plan cooler summer hikes.",
                whatsNew: "• Shade forecast: see which parts of a route are in the sun at your start time\n• Faster offline map downloads (up to 2× on Wi-Fi)\n• Fixed elevation profile glitches on very long routes")),
            ("pt-BR", FakeASCLocalizedText(
                name: "Trailhead", subtitle: "Mapas de trilha offline e GPS",
                description: "O Trailhead é o companheiro de trilha que continua funcionando quando o sinal some. Baixe mapas topográficos de regiões inteiras, planeje rotas com perfil de elevação e siga cada curva — totalmente offline.\n\n• Mapas topográficos com curvas de nível, abrigos e fontes de água\n• Planejador de rotas com distância, subida e tempo estimado\n• Rastreamento ao vivo com ritmo e GPS econômico\n• Condições das trilhas relatadas pela comunidade",
                keywords: "trilha,caminhada,mapa offline,gps,montanha,trekking,aventura",
                promotionalText: "Novo: previsão de sombra ao longo de cada rota.",
                whatsNew: "• Previsão de sombra ao longo da rota\n• Downloads de mapas até 2× mais rápidos\n• Correções no perfil de elevação")),
            ("de-DE", FakeASCLocalizedText(
                name: "Trailhead", subtitle: "Offline-Wanderkarten & GPS",
                description: "Trailhead ist dein Wanderbegleiter, der auch ohne Netz funktioniert. Lade topografische Karten ganzer Regionen herunter, plane Touren mit Höhenprofil und folge ihnen Schritt für Schritt – komplett offline.",
                keywords: "wandern,karte,offline,gps,berge,trekking,outdoor",
                promotionalText: "Neu: Schattenprognose für jede Tour.",
                whatsNew: "• Schattenprognose entlang der Route\n• Schnellere Offline-Downloads\n• Fehlerbehebungen beim Höhenprofil")),
            ("ja", FakeASCLocalizedText(
                name: "Trailhead", subtitle: "オフライン登山地図とGPS",
                description: "Trailheadは電波が届かない場所でも使える登山アプリです。地域ごとの地形図をダウンロードし、標高グラフ付きでルートを計画、オフラインでナビゲーションできます。",
                keywords: "登山,ハイキング,地図,オフライン,GPS",
                promotionalText: "新機能：ルート上の日陰予報。",
                whatsNew: "• ルートの日陰予報\n• オフライン地図のダウンロードを高速化"))
        ],
        screenshotCaptions: ["Maps that work offline", "Plan every climb", "Track your pace", "Know the trail conditions"],
        reviews: [
            FakeASCReviewSeed(rating: 5, title: "Saved my weekend", body: "Lost signal halfway up the ridge and the offline map kept me on the right fork. The elevation profile is spot on.", nickname: "ridgewalker_88", territory: "USA", daysAgo: 0.4),
            FakeASCReviewSeed(rating: 4, title: "Great, but battery hungry", body: "Love the topo detail. Live tracking drains about 8% an hour on my iPhone 15 — a low power mode would be perfect.", nickname: "mkettle", territory: "GBR", daysAgo: 1.2, reply: "Thanks! A low-power tracking mode is in beta right now and lands in 4.3 — we'd love your feedback on it.", replyPending: true),
            FakeASCReviewSeed(rating: 5, title: "Melhor app de trilha", body: "Usei na Serra da Mantiqueira sem sinal nenhum e funcionou perfeitamente. Os pontos de água ajudam muito.", nickname: "carol.trilhas", territory: "BRA", daysAgo: 2),
            FakeASCReviewSeed(rating: 2, title: "Download keeps failing", body: "The Alps region download stops at 70% every time. Tried on two networks.", nickname: "hikerjoe", territory: "CHE", daysAgo: 3, reply: "Sorry about that! 4.2 fixes resumable downloads for large regions — please update and let us know at support@northwind.example if it still stalls."),
            FakeASCReviewSeed(rating: 5, title: "Endlich offline", body: "Die Karten sind genauer als alles, was ich bisher hatte. Das Höhenprofil ist super.", nickname: "bergfex_anna", territory: "DEU", daysAgo: 4.5),
            FakeASCReviewSeed(rating: 3, title: "Solid, needs Android sync", body: "Good maps, but my partner is on Android and we can't share routes easily.", nickname: "trailmix", territory: "CAN", daysAgo: 6),
            FakeASCReviewSeed(rating: 5, title: "素晴らしい", body: "山小屋や水場の情報が正確で、オフラインでも安心して使えます。", nickname: "yama_san", territory: "JPN", daysAgo: 8),
            FakeASCReviewSeed(rating: 1, title: "Subscription surprise", body: "Didn't realise the trial would convert. Please make the reminder clearer.", nickname: "annoyed_hiker", territory: "USA", daysAgo: 9, reply: "We're sorry for the confusion. We now send a reminder 2 days before a trial ends, and you can request a refund through Apple at any time."),
            FakeASCReviewSeed(rating: 4, title: "Muy completa", body: "Las rutas de la comunidad son muy útiles. Me gustaría ver el desnivel acumulado en el widget.", nickname: "montañera", territory: "ESP", daysAgo: 12),
            FakeASCReviewSeed(rating: 5, title: "Watch app is brilliant", body: "Haptic turn alerts mean I barely take my phone out. Perfect for trail running.", nickname: "fellrunner", territory: "AUS", daysAgo: 15),
            FakeASCReviewSeed(rating: 4, title: "Très bonne appli", body: "Cartes claires et précises. Un mode sombre pour la carte serait bienvenu.", nickname: "randonneur_lyon", territory: "FRA", daysAgo: 21, reply: "Merci ! Le mode sombre pour les cartes arrive bientôt."),
            FakeASCReviewSeed(rating: 5, title: "Worth every penny", body: "Planned a 5-day traverse with it. The time estimates were within 20 minutes every day.", nickname: "longtrail_li", territory: "USA", daysAgo: 27)
        ],
        testFlight: FakeASCTestFlightSeed(version: "4.3.0", builds: ["4301", "4302", "4303"],
                                          whatToTest: "Low-power tracking mode: start a long hike and check battery drain and track accuracy. Also try the new dark map style.",
                                          externalGroupName: "Trail Scouts"),
        capabilities: ["PUSH_NOTIFICATIONS", "ICLOUD", "APP_GROUPS", "MAPS", "HEALTHKIT", "SIGN_IN_WITH_APPLE"],
        storefrontRatings: ["us": (4.7, 18_420), "gb": (4.6, 3_210), "de": (4.7, 2_884), "br": (4.8, 1_942), "jp": (4.5, 1_120), "ca": (4.6, 1_760), "au": (4.7, 1_304), "fr": (4.5, 980)]
    )

    // MARK: Ledger Pocket

    static let ledger = FakeASCAppSeed(
        id: "6479201102", name: "Ledger Pocket", bundleId: "com.northwind.ledger", sku: "NW-LEDGER",
        symbol: "chart.pie.fill", color: "3558C9",
        primaryCategory: "FINANCE", secondaryCategory: "PRODUCTIVITY",
        versions: [
            FakeASCVersionSeed(platform: "IOS", version: "2.7.0", state: "IN_REVIEW", createdDaysAgo: 6, build: "2704", submittedDaysAgo: 2),
            FakeASCVersionSeed(platform: "MAC_OS", version: "2.7.0", state: "WAITING_FOR_REVIEW", createdDaysAgo: 6, build: "2705", submittedDaysAgo: 1),
            FakeASCVersionSeed(platform: "IOS", version: "2.6.3", state: "READY_FOR_SALE", createdDaysAgo: 40, build: "2631", submittedDaysAgo: 38),
            FakeASCVersionSeed(platform: "MAC_OS", version: "2.6.3", state: "READY_FOR_SALE", createdDaysAgo: 40, build: "2632", submittedDaysAgo: 38),
            FakeASCVersionSeed(platform: "IOS", version: "2.6.0", state: "REPLACED_WITH_NEW_VERSION", createdDaysAgo: 82, build: "2600", submittedDaysAgo: 79)
        ],
        texts: [
            ("en-US", FakeASCLocalizedText(
                name: "Ledger Pocket", subtitle: "Budgets, bills & shared expenses",
                description: "Ledger Pocket turns your spending into a plan you can actually keep. Set envelope budgets, track bills before they're due and split shared expenses with housemates — all synced privately with iCloud.\n\n• Envelope budgets that roll over month to month\n• Bill calendar with reminders\n• Shared ledgers for trips and households\n• Import CSV statements from any bank\n• Mac app with keyboard-first entry",
                keywords: "budget,expenses,bills,money,finance,split,envelope,savings",
                promotionalText: "Plan the holidays: shared trip ledgers now settle up in one tap.",
                whatsNew: "• Settle up shared ledgers in one tap\n• New monthly report with category trends\n• Mac: quick entry from the menu bar")),
            ("pt-BR", FakeASCLocalizedText(
                name: "Ledger Pocket", subtitle: "Orçamento, contas e despesas",
                description: "O Ledger Pocket transforma seus gastos em um plano possível de cumprir. Crie orçamentos por envelope, acompanhe contas antes do vencimento e divida despesas com quem mora com você.",
                keywords: "orçamento,despesas,contas,finanças,dinheiro,economia",
                promotionalText: "Viagem em grupo? Acerte as contas com um toque.",
                whatsNew: "• Acerto de contas com um toque\n• Novo relatório mensal")),
            ("de-DE", FakeASCLocalizedText(
                name: "Ledger Pocket", subtitle: "Budget, Rechnungen & Ausgaben",
                description: "Ledger Pocket macht aus deinen Ausgaben einen Plan, den du einhalten kannst. Umschlag-Budgets, Rechnungskalender und geteilte Ausgaben – privat über iCloud synchronisiert.",
                keywords: "budget,ausgaben,haushaltsbuch,finanzen,geld",
                promotionalText: "Neu: Geteilte Ausgaben mit einem Tipp ausgleichen.",
                whatsNew: "• Ausgleichen mit einem Tipp\n• Neuer Monatsbericht")),
            ("fr-FR", FakeASCLocalizedText(
                name: "Ledger Pocket", subtitle: "Budget, factures et dépenses",
                description: "Ledger Pocket transforme vos dépenses en un plan que vous pouvez tenir : budgets par enveloppe, calendrier des factures et dépenses partagées.",
                keywords: "budget,dépenses,factures,finances,argent",
                promotionalText: "Nouveau : équilibrez les comptes partagés en un geste.",
                whatsNew: "• Équilibrage en un geste\n• Nouveau rapport mensuel"))
        ],
        screenshotCaptions: ["Budgets that roll over", "Never miss a bill", "Split with anyone", "Insights at a glance"],
        reviews: [
            FakeASCReviewSeed(rating: 5, title: "Finally a budget app I keep using", body: "Envelope budgeting clicked for me. The rollover makes the end of the month far less stressful.", nickname: "frugal_fern", territory: "USA", daysAgo: 0.8),
            FakeASCReviewSeed(rating: 3, title: "CSV import is picky", body: "My credit union's CSV needed manual cleanup before it would import. Otherwise good.", nickname: "dmitri_k", territory: "USA", daysAgo: 1.6, reply: "Thanks for the feedback! Could you send a sample (with amounts removed) to support@northwind.example? We'll add your bank's format."),
            FakeASCReviewSeed(rating: 5, title: "Perfeito para dividir contas", body: "Uso com meus colegas de apartamento e acabou a confusão de quem deve o quê.", nickname: "lu.martins", territory: "BRA", daysAgo: 3),
            FakeASCReviewSeed(rating: 4, title: "Gute Mac-App", body: "Die Schnelleingabe auf dem Mac ist genial. Auf dem iPhone fehlt mir noch ein Widget für das Restbudget.", nickname: "haushaltsheld", territory: "DEU", daysAgo: 5),
            FakeASCReviewSeed(rating: 1, title: "Lost my data after update", body: "After updating, last month's transactions disappeared.", nickname: "worried_user", territory: "GBR", daysAgo: 7, reply: "We're so sorry! Nothing is lost — iCloud was still syncing. Pull to refresh on the Ledger tab and the transactions return; we've also made the sync status clearer in 2.6.3."),
            FakeASCReviewSeed(rating: 5, title: "Excelente", body: "La mejor app de presupuestos que he probado. Los informes mensuales son muy claros.", nickname: "ahorradora", territory: "MEX", daysAgo: 10),
            FakeASCReviewSeed(rating: 4, title: "Très pratique", body: "Le calendrier des factures m'a évité deux frais de retard ce mois-ci.", nickname: "julien_b", territory: "FRA", daysAgo: 14),
            FakeASCReviewSeed(rating: 2, title: "Needs multi-currency", body: "I travel a lot and need EUR and USD in the same ledger.", nickname: "nomad_dev", territory: "NLD", daysAgo: 19),
            FakeASCReviewSeed(rating: 5, title: "Clean and private", body: "No bank login required and everything stays in iCloud. Exactly what I wanted.", nickname: "privacyfirst", territory: "CAN", daysAgo: 26)
        ],
        testFlight: FakeASCTestFlightSeed(version: "2.8.0", builds: ["2801", "2802"],
                                          whatToTest: "Multi-currency ledgers: add expenses in two currencies and check the converted totals and the settle-up flow.",
                                          externalGroupName: "Pocket Insiders"),
        capabilities: ["ICLOUD", "PUSH_NOTIFICATIONS", "APP_GROUPS", "DATA_PROTECTION"],
        storefrontRatings: ["us": (4.6, 9_870), "gb": (4.5, 1_402), "de": (4.6, 1_211), "br": (4.7, 860), "fr": (4.4, 512), "ca": (4.6, 744)]
    )

    // MARK: Mosaic Notes

    static let mosaic = FakeASCAppSeed(
        id: "6479201103", name: "Mosaic Notes", bundleId: "com.northwind.mosaic", sku: "NW-MOSAIC",
        symbol: "square.grid.2x2.fill", color: "8E44AD",
        primaryCategory: "PRODUCTIVITY", secondaryCategory: "EDUCATION",
        versions: [
            FakeASCVersionSeed(platform: "IOS", version: "5.1.0", state: "PENDING_DEVELOPER_RELEASE", createdDaysAgo: 12, build: "5106", releaseType: "MANUAL", submittedDaysAgo: 5),
            FakeASCVersionSeed(platform: "IOS", version: "5.0.2", state: "READY_FOR_SALE", createdDaysAgo: 45, build: "5021", submittedDaysAgo: 43),
            FakeASCVersionSeed(platform: "VISION_OS", version: "1.2.0", state: "REJECTED", createdDaysAgo: 10, build: "1203", submittedDaysAgo: 4),
            FakeASCVersionSeed(platform: "VISION_OS", version: "1.1.0", state: "READY_FOR_SALE", createdDaysAgo: 70, build: "1102", submittedDaysAgo: 66)
        ],
        texts: [
            ("en-US", FakeASCLocalizedText(
                name: "Mosaic Notes", subtitle: "Visual notes, boards & sketches",
                description: "Mosaic Notes is a canvas for thinking. Pin notes, photos, links and sketches onto boards, connect ideas with arrows and switch to an outline whenever you need structure.\n\n• Infinite boards with smart alignment\n• Handwriting and Apple Pencil sketches\n• Outline view for every board\n• Shared boards with live cursors\n• Spatial boards on Apple Vision Pro",
                keywords: "notes,whiteboard,mind map,sketch,canvas,moodboard,study,ideas",
                promotionalText: "Mosaic 5.1: templates for lesson plans, sprints and trip planning.",
                whatsNew: "• 24 new board templates\n• Link previews for videos and maps\n• Smoother Apple Pencil latency on iPad")),
            ("pt-BR", FakeASCLocalizedText(
                name: "Mosaic Notes", subtitle: "Notas visuais e quadros",
                description: "O Mosaic Notes é uma tela para pensar. Fixe notas, fotos, links e desenhos em quadros e conecte ideias com setas.",
                keywords: "notas,quadro,mapa mental,desenho,estudo,ideias",
                promotionalText: "Novos modelos para aulas, sprints e viagens.",
                whatsNew: "• 24 novos modelos de quadro\n• Prévia de links de vídeos e mapas")),
            ("es-ES", FakeASCLocalizedText(
                name: "Mosaic Notes", subtitle: "Notas visuales y tableros",
                description: "Mosaic Notes es un lienzo para pensar: notas, fotos, enlaces y bocetos conectados en tableros infinitos.",
                keywords: "notas,pizarra,mapa mental,bocetos,ideas",
                promotionalText: "Nuevas plantillas para clases y viajes.",
                whatsNew: "• 24 plantillas nuevas\n• Vista previa de enlaces"))
        ],
        screenshotCaptions: ["Think on a canvas", "Sketch with Pencil", "Outline anything", "Share boards live"],
        reviews: [
            FakeASCReviewSeed(rating: 5, title: "Replaced three apps", body: "Whiteboard, outliner and moodboard in one. The outline view is the killer feature.", nickname: "studio_ines", territory: "USA", daysAgo: 0.3),
            FakeASCReviewSeed(rating: 4, title: "Ótimo para estudar", body: "Monto meus resumos da faculdade em quadros. Só falta exportar em PDF com melhor qualidade.", nickname: "bia.estuda", territory: "BRA", daysAgo: 1.5, reply: "Oi Bia! A exportação em PDF em alta resolução chega na versão 5.1. Obrigado!"),
            FakeASCReviewSeed(rating: 5, title: "Vision Pro boards are magic", body: "Spreading a project board across the room changed how our team plans.", nickname: "spatial_sam", territory: "USA", daysAgo: 2.5),
            FakeASCReviewSeed(rating: 3, title: "Sync conflicts", body: "Editing the same board on iPad and Mac sometimes duplicates cards.", nickname: "kai_notes", territory: "AUS", daysAgo: 4),
            FakeASCReviewSeed(rating: 5, title: "Increíble", body: "Las plantillas de viaje me ahorraron horas. Muy intuitiva.", nickname: "viajera_ana", territory: "ESP", daysAgo: 6),
            FakeASCReviewSeed(rating: 2, title: "Pencil lag on older iPad", body: "On my iPad (9th gen) drawing feels laggy compared to Notes.", nickname: "sketchy", territory: "GBR", daysAgo: 9, reply: "Thanks for flagging this — 5.1 cuts Pencil latency by about 40% on older iPads. It's out next week."),
            FakeASCReviewSeed(rating: 5, title: "Super für Workshops", body: "Wir nutzen geteilte Boards in jedem Kunden-Workshop. Live-Cursor sind großartig.", nickname: "agentur_nord", territory: "DEU", daysAgo: 13),
            FakeASCReviewSeed(rating: 4, title: "Beautiful app", body: "Gorgeous design and fast. Would love tags across boards.", nickname: "minimalist_mo", territory: "CAN", daysAgo: 18),
            FakeASCReviewSeed(rating: 1, title: "Crashes on launch", body: "Since yesterday it crashes immediately on my iPhone.", nickname: "frustrated22", territory: "USA", daysAgo: 23, reply: "We fixed this crash in 5.0.2 — please update from the App Store. Sorry for the trouble!"),
            FakeASCReviewSeed(rating: 5, title: "Indispensable", body: "Je prépare tous mes cours avec Mosaic. Le mode plan est parfait.", nickname: "prof_claire", territory: "FRA", daysAgo: 29)
        ],
        testFlight: FakeASCTestFlightSeed(version: "5.2.0", builds: ["5201", "5202"],
                                          whatToTest: "Tags across boards: tag cards on two boards and use the tag browser. Report any sync duplicates.",
                                          externalGroupName: "Mosaic Early Access"),
        capabilities: ["ICLOUD", "PUSH_NOTIFICATIONS", "ASSOCIATED_DOMAINS", "APP_GROUPS"],
        storefrontRatings: ["us": (4.8, 12_310), "gb": (4.7, 2_045), "de": (4.8, 1_633), "br": (4.8, 1_208), "es": (4.7, 690), "fr": (4.7, 744), "jp": (4.6, 512)]
    )

    // MARK: Lumen (tvOS)

    static let lumen = FakeASCAppSeed(
        id: "6479201104", name: "Lumen", bundleId: "com.northwind.lumen", sku: "NW-LUMEN",
        symbol: "sparkles.tv.fill", color: "E07A2D",
        primaryCategory: "ENTERTAINMENT", secondaryCategory: "PHOTO_AND_VIDEO",
        hasIPad: false,
        versions: [
            FakeASCVersionSeed(platform: "TV_OS", version: "1.4.0", state: "READY_FOR_SALE", createdDaysAgo: 20, build: "1401", submittedDaysAgo: 18),
            FakeASCVersionSeed(platform: "TV_OS", version: "1.3.1", state: "REPLACED_WITH_NEW_VERSION", createdDaysAgo: 66, build: "1311", submittedDaysAgo: 63)
        ],
        texts: [
            ("en-US", FakeASCLocalizedText(
                name: "Lumen", subtitle: "Ambient scenes for your TV",
                description: "Lumen turns your Apple TV into a calm window: slow aerial landscapes, rain on glass, fireplaces and generative light, with soundscapes that fade with the time of day.",
                keywords: "ambient,screensaver,relax,fireplace,rain,aerial,tv,focus",
                promotionalText: "New winter collection: northern lights and snowy cabins.",
                whatsNew: "• Winter collection with 12 new scenes\n• Sleep timer with gentle fade-out")),
            ("de-DE", FakeASCLocalizedText(
                name: "Lumen", subtitle: "Stimmungsvolle Szenen für den TV",
                description: "Lumen verwandelt dein Apple TV in ein ruhiges Fenster: Landschaften, Regen, Kaminfeuer und generatives Licht.",
                keywords: "ambient,entspannung,kamin,regen,tv",
                promotionalText: "Neue Winterkollektion.",
                whatsNew: "• Winterkollektion mit 12 Szenen\n• Schlaftimer"))
        ],
        screenshotCaptions: ["Calm on the big screen", "Soundscapes that fade", "Winter collection"],
        reviews: [
            FakeASCReviewSeed(rating: 5, title: "Our evening ritual", body: "The fireplace scene with the rain soundscape is on every night.", nickname: "cozy_couch", territory: "USA", daysAgo: 1),
            FakeASCReviewSeed(rating: 4, title: "Beautiful scenes", body: "Gorgeous in 4K HDR. Wish there were more city scenes.", nickname: "urban_loop", territory: "GBR", daysAgo: 5),
            FakeASCReviewSeed(rating: 5, title: "Wunderschön", body: "Die Nordlichter sind atemberaubend.", nickname: "lichtfreund", territory: "DEU", daysAgo: 11, reply: "Danke! Weitere Nordlicht-Szenen sind in Arbeit."),
            FakeASCReviewSeed(rating: 3, title: "Audio loops are short", body: "You can hear the loop point in the ocean soundscape.", nickname: "audiophile_t", territory: "CAN", daysAgo: 17)
        ],
        storefrontRatings: ["us": (4.6, 2_140), "gb": (4.5, 410), "de": (4.7, 388)]
    )

    // MARK: Orbit Focus (macOS)

    static let orbit = FakeASCAppSeed(
        id: "6479201105", name: "Orbit Focus", bundleId: "com.northwind.orbit", sku: "NW-ORBIT",
        symbol: "timer", color: "1F8A9E",
        primaryCategory: "PRODUCTIVITY", secondaryCategory: "DEVELOPER_TOOLS",
        hasIPad: false,
        versions: [
            FakeASCVersionSeed(platform: "MAC_OS", version: "3.0.0", state: "PREPARE_FOR_SUBMISSION", createdDaysAgo: 3, build: "3001"),
            FakeASCVersionSeed(platform: "MAC_OS", version: "2.9.4", state: "READY_FOR_SALE", createdDaysAgo: 52, build: "2940", submittedDaysAgo: 50)
        ],
        texts: [
            ("en-US", FakeASCLocalizedText(
                name: "Orbit Focus", subtitle: "Deep-work timer for your Mac",
                description: "Orbit lives in your menu bar and protects your focus: timed sessions, automatic Do Not Disturb, distraction-free app switching and a weekly report of where your hours went.",
                keywords: "focus,pomodoro,timer,productivity,menu bar,deep work",
                promotionalText: "Orbit 3 is coming with focus playlists and calendar blocking.",
                whatsNew: "• Calendar time-blocking\n• Focus playlists\n• Redesigned weekly report"))
        ],
        screenshotCaptions: ["Focus from the menu bar", "See where time goes"],
        reviews: [
            FakeASCReviewSeed(rating: 5, title: "Lives in my menu bar", body: "Simple, fast and the weekly report keeps me honest.", nickname: "deepworker", territory: "USA", daysAgo: 2),
            FakeASCReviewSeed(rating: 4, title: "Sehr gut", body: "Automatisches Nicht-Stören ist super. Shortcuts-Integration wäre toll.", nickname: "fokus_mensch", territory: "DEU", daysAgo: 8),
            FakeASCReviewSeed(rating: 5, title: "Pomodoro done right", body: "Love that it blocks Slack during sessions.", nickname: "maker_mia", territory: "GBR", daysAgo: 16)
        ],
        storefrontRatings: ["us": (4.7, 1_380), "gb": (4.6, 290), "de": (4.7, 240)]
    )

    // MARK: - Jordan Avery (personal team)

    static let personal = FakeASCTeamSeed(
        issuerId: personalIssuerId,
        name: "Jordan Avery",
        teamId: "JA4X8P2R6T",
        apps: [tideTables, haiku],
        people: [
            FakeASCPersonSeed(firstName: "Jordan", lastName: "Avery", email: "jordan.avery@mail.example",
                              roles: ["ACCOUNT_HOLDER", "ADMIN"], provisioningAllowed: true),
            FakeASCPersonSeed(firstName: "Riley", lastName: "Park", email: "riley.park@mail.example",
                              roles: ["DEVELOPER"], provisioningAllowed: true)
        ],
        devices: [
            FakeASCDeviceSeed(name: "Jordan's iPhone 17 Pro", platform: "IOS", deviceClass: "IPHONE", model: "iPhone 17 Pro", addedDaysAgo: 52),
            FakeASCDeviceSeed(name: "Jordan's iPad Air", platform: "IOS", deviceClass: "IPAD", model: "iPad Air 11-inch (M3)", addedDaysAgo: 260),
            FakeASCDeviceSeed(name: "Riley's iPhone 14", platform: "IOS", deviceClass: "IPHONE", model: "iPhone 14", addedDaysAgo: 400)
        ],
        certificates: [
            FakeASCCertificateSeed(type: "DISTRIBUTION", owner: "Jordan Avery", expiresInDays: 96),
            FakeASCCertificateSeed(type: "DEVELOPMENT", owner: "Jordan Avery", expiresInDays: 240)
        ]
    )

    static let tideTables = FakeASCAppSeed(
        id: "6479301201", name: "Tide Tables", bundleId: "dev.javery.tidetables", sku: "JA-TIDES",
        symbol: "water.waves", color: "1565C0",
        primaryCategory: "WEATHER", secondaryCategory: "TRAVEL",
        versions: [
            FakeASCVersionSeed(platform: "IOS", version: "1.6.0", state: "READY_FOR_SALE", createdDaysAgo: 4, build: "160", phasedDay: 2, submittedDaysAgo: 3),
            FakeASCVersionSeed(platform: "IOS", version: "1.5.2", state: "REPLACED_WITH_NEW_VERSION", createdDaysAgo: 38, build: "152", submittedDaysAgo: 36)
        ],
        texts: [
            ("en-US", FakeASCLocalizedText(
                name: "Tide Tables", subtitle: "Tides, swell & moon phases",
                description: "Accurate tide predictions for 4,000 coastal stations, with swell, wind and moon phases in one glanceable chart. Widgets for your Home Screen and Lock Screen.",
                keywords: "tides,surf,fishing,swell,moon,beach,sailing",
                promotionalText: "Lock Screen widgets now show the next high tide.",
                whatsNew: "• Lock Screen widget with next high and low tide\n• Swell direction arrows")),
            ("pt-BR", FakeASCLocalizedText(
                name: "Tábua de Marés", subtitle: "Marés, ondulação e lua",
                description: "Previsão de marés para 4.000 estações costeiras, com ondulação, vento e fases da lua.",
                keywords: "maré,surf,pesca,ondas,lua,praia",
                promotionalText: "Widget na Tela Bloqueada com a próxima maré alta.",
                whatsNew: "• Widget na Tela Bloqueada\n• Direção da ondulação"))
        ],
        screenshotCaptions: ["Tides at a glance", "Plan your session", "Widgets everywhere"],
        reviews: [
            FakeASCReviewSeed(rating: 5, title: "Every surfer needs this", body: "The swell + tide chart is exactly what I check before paddling out.", nickname: "dawnpatrol", territory: "AUS", daysAgo: 0.6),
            FakeASCReviewSeed(rating: 5, title: "Perfeito para pescar", body: "Uso toda semana para planejar a pescaria. Muito preciso.", nickname: "pescador_sc", territory: "BRA", daysAgo: 3, reply: "Valeu! Boas pescarias!"),
            FakeASCReviewSeed(rating: 4, title: "Great widgets", body: "Would love tide alerts as notifications.", nickname: "kayak_kate", territory: "USA", daysAgo: 7),
            FakeASCReviewSeed(rating: 2, title: "Missing my harbour", body: "My local station isn't listed yet.", nickname: "harbour_master", territory: "IRL", daysAgo: 12, reply: "Thanks! Send the station name to tides@mail.example and we'll add it in the next update.")
        ],
        storefrontRatings: ["us": (4.8, 640), "au": (4.9, 512), "br": (4.8, 230)]
    )

    static let haiku = FakeASCAppSeed(
        id: "6479301202", name: "Pocket Haiku", bundleId: "dev.javery.haiku", sku: "JA-HAIKU",
        symbol: "leaf.fill", color: "6D8B3A",
        primaryCategory: "BOOKS", secondaryCategory: "LIFESTYLE",
        hasIPad: false,
        versions: [
            FakeASCVersionSeed(platform: "IOS", version: "2.0.1", state: "READY_FOR_SALE", createdDaysAgo: 15, build: "201", submittedDaysAgo: 13),
            FakeASCVersionSeed(platform: "IOS", version: "2.0.0", state: "REPLACED_WITH_NEW_VERSION", createdDaysAgo: 31, build: "200", submittedDaysAgo: 29)
        ],
        texts: [
            ("en-US", FakeASCLocalizedText(
                name: "Pocket Haiku", subtitle: "A daily poem, three lines long",
                description: "One haiku every morning, a gentle writing prompt every evening. Keep a private journal of your own poems and share the ones you love as beautiful cards.",
                keywords: "haiku,poetry,journal,writing,mindfulness,daily",
                promotionalText: "Autumn prompts are here.",
                whatsNew: "• Autumn prompt collection\n• Share cards in new paper textures"))
        ],
        screenshotCaptions: ["A poem every morning", "Write your own"],
        reviews: [
            FakeASCReviewSeed(rating: 5, title: "Tiny moment of calm", body: "I read the morning haiku before checking email. Lovely ritual.", nickname: "quiet_reader", territory: "USA", daysAgo: 2),
            FakeASCReviewSeed(rating: 5, title: "美しいアプリ", body: "毎朝の俳句が楽しみです。", nickname: "hana_k", territory: "JPN", daysAgo: 9),
            FakeASCReviewSeed(rating: 4, title: "Sweet app", body: "Would love a widget with today's haiku.", nickname: "leafy", territory: "GBR", daysAgo: 20)
        ],
        storefrontRatings: ["us": (4.9, 310), "jp": (4.8, 120)]
    )

    /// TestFlight testers outside the team (fictional).
    static let externalTesters: [(first: String, last: String, email: String)] = [
        ("Maya", "Lindqvist", "maya.lindqvist@mail.example"),
        ("Diego", "Santos", "diego.santos@mail.example"),
        ("Chloé", "Martin", "chloe.martin@mail.example"),
        ("Kenji", "Watanabe", "kenji.watanabe@mail.example"),
        ("Amara", "Okafor", "amara.okafor@mail.example"),
        ("Felix", "Wagner", "felix.wagner@mail.example"),
        ("Isabela", "Costa", "isabela.costa@mail.example"),
        ("Theo", "Novak", "theo.novak@mail.example"),
        ("Grace", "Kim", "grace.kim@mail.example"),
        ("Ravi", "Menon", "ravi.menon@mail.example")
    ]
}
#endif
