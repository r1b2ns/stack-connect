#if DEBUG
import Foundation

/// The fake Firebase content: one service account ("Northwind Labs") with two
/// projects, their Android / iOS / web apps, Remote Config templates, linked
/// Google Analytics properties and FCM delivery stats. Everything is invented
/// (`.example` domains, placeholder keys).
enum FakeFirebaseCatalog {

    static let northwindClientEmail = "firebase-adminsdk-x7k2p@northwind-labs.iam.example"

    struct App: Sendable {
        enum Platform: String, Sendable { case ios, android, web }
        let appId: String
        let platform: Platform
        var displayName: String
        /// Bundle ID (iOS) or package name (Android); `nil` for web.
        let identifier: String?
        var appStoreId: String? = nil
        var sha1: [String] = []
        var appUrls: [String] = []
    }

    struct Project: Sendable {
        let projectId: String
        let projectNumber: String
        let displayName: String
        let locationId: String
        let analyticsPropertyId: String
        /// Daily-active-users baseline of the analytics series.
        let dailyUsers: Int
        var apps: [App]
    }

    static let projects: [Project] = [trailhead, mosaic]

    // MARK: - Projects

    static let trailhead = Project(
        projectId: "trailhead-prod-4f2a1", projectNumber: "483920175624", displayName: "Trailhead",
        locationId: "us-central", analyticsPropertyId: "412903871", dailyUsers: 21_400,
        apps: [
            App(appId: "1:483920175624:ios:8c1b2f3a4d5e6f70", platform: .ios, displayName: "Trailhead iOS",
                identifier: "com.northwind.trailhead", appStoreId: "6479201101"),
            App(appId: "1:483920175624:android:3e9d7c1b5a2f4e60", platform: .android, displayName: "Trailhead Android",
                identifier: "com.northwind.trailhead", sha1: ["5e:8f:16:06:2e:a3:cd:2c:4a:0d:54:78:76:ba:a6:f3:8c:ab:f6:25"]),
            App(appId: "1:483920175624:android:9a4c2e7f1d6b3a80", platform: .android, displayName: "Trailhead Wear OS",
                identifier: "com.northwind.trailhead.wear"),
            App(appId: "1:483920175624:web:b7e1d4c9a2f05e31", platform: .web, displayName: "Trailhead Planner (Web)",
                identifier: nil, appUrls: ["https://plan.trailhead.northwind.example"])
        ]
    )

    static let mosaic = Project(
        projectId: "mosaic-notes-91c0e", projectNumber: "719305846211", displayName: "Mosaic Notes",
        locationId: "europe-west", analyticsPropertyId: "398177420", dailyUsers: 35_800,
        apps: [
            App(appId: "1:719305846211:ios:1f6a9c3e7b2d4f05", platform: .ios, displayName: "Mosaic Notes iOS",
                identifier: "com.northwind.mosaic", appStoreId: "6479201103"),
            App(appId: "1:719305846211:ios:6d2b8e4a1c9f7e33", platform: .ios, displayName: "Mosaic Notes visionOS",
                identifier: "com.northwind.mosaic.vision"),
            App(appId: "1:719305846211:android:c4a7e2b9d1f63a58", platform: .android, displayName: "Mosaic Notes Android",
                identifier: "com.northwind.mosaic"),
            App(appId: "1:719305846211:web:2e8b5d1a7c4f9b62", platform: .web, displayName: "Mosaic Web",
                identifier: nil, appUrls: ["https://app.mosaic.northwind.example"])
        ]
    )

    // MARK: - Remote Config

    /// The published template of a project, as the Remote Config REST API returns it.
    static func remoteConfig(for projectId: String) -> [String: Any] {
        switch projectId {
        case trailhead.projectId: return trailheadRemoteConfig
        default:                  return mosaicRemoteConfig
        }
    }

    // JSON literals are read-only after launch.
    nonisolated(unsafe) private static let trailheadRemoteConfig: [String: Any] = [
        "conditions": [
            ["name": "iOS users", "expression": "device.os == 'ios'", "tagColor": "BLUE"],
            ["name": "Beta testers", "expression": "app.userProperty['beta_tester'].exactlyMatches(['true'])", "tagColor": "PURPLE"],
            ["name": "Brazil", "expression": "device.country in ['BR']", "tagColor": "GREEN"],
            ["name": "Premium", "expression": "app.userProperty['plan'].exactlyMatches(['premium'])", "tagColor": "DEEP_ORANGE"]
        ],
        "parameters": [
            "welcome_message": [
                "defaultValue": ["value": "Find your next trail"],
                "conditionalValues": ["Brazil": ["value": "Encontre sua próxima trilha"]],
                "description": "Headline on the Explore tab",
                "valueType": "STRING"
            ],
            "shade_forecast_enabled": [
                "defaultValue": ["value": "false"],
                "conditionalValues": ["Beta testers": ["value": "true"], "iOS users": ["value": "true"]],
                "description": "Shows the shade forecast layer on routes",
                "valueType": "BOOLEAN"
            ],
            "min_supported_version": [
                "defaultValue": ["value": "4.0.0"],
                "description": "Older versions are asked to update",
                "valueType": "STRING"
            ],
            "paywall_variant": [
                "defaultValue": ["value": "annual_first"],
                "conditionalValues": ["Brazil": ["value": "monthly_first"]],
                "description": "Order of plans on the paywall (A/B test)",
                "valueType": "STRING"
            ]
        ],
        "parameterGroups": [
            "Maps": [
                "description": "Offline maps and rendering",
                "parameters": [
                    "max_offline_regions": [
                        "defaultValue": ["value": "5"],
                        "conditionalValues": ["Premium": ["value": "50"]],
                        "description": "Regions a user can keep offline",
                        "valueType": "NUMBER"
                    ],
                    "map_style_config": [
                        "defaultValue": ["value": "{\"contourInterval\":20,\"hillshade\":true,\"darkMode\":\"auto\"}"],
                        "description": "Default map style",
                        "valueType": "JSON"
                    ]
                ]
            ],
            "Tracking": [
                "description": "Live GPS tracking",
                "parameters": [
                    "gps_interval_seconds": [
                        "defaultValue": ["value": "5"],
                        "conditionalValues": ["Beta testers": ["value": "10"]],
                        "description": "Sampling interval while tracking",
                        "valueType": "NUMBER"
                    ],
                    "low_power_mode_enabled": [
                        "defaultValue": ["useInAppDefault": true],
                        "conditionalValues": ["Beta testers": ["value": "true"]],
                        "description": "Battery-saving tracking (beta)",
                        "valueType": "BOOLEAN"
                    ]
                ]
            ]
        ],
        "version": [
            "versionNumber": "47",
            "updateOrigin": "CONSOLE",
            "updateType": "INCREMENTAL_UPDATE",
            "updateUser": ["email": "mateus.rocha@northwind.example", "name": "Mateus Rocha"],
            "description": "Enable the shade forecast for iOS"
        ]
    ]

    nonisolated(unsafe) private static let mosaicRemoteConfig: [String: Any] = [
        "conditions": [
            ["name": "Android", "expression": "device.os == 'android'", "tagColor": "GREEN"],
            ["name": "Vision Pro", "expression": "app.id == '1:719305846211:ios:6d2b8e4a1c9f7e33'", "tagColor": "INDIGO"],
            ["name": "10% rollout", "expression": "percent <= 10", "tagColor": "ORANGE"]
        ],
        "parameters": [
            "templates_catalog_version": [
                "defaultValue": ["value": "2026.11"],
                "description": "Board templates catalog to download",
                "valueType": "STRING"
            ],
            "tags_enabled": [
                "defaultValue": ["value": "false"],
                "conditionalValues": ["10% rollout": ["value": "true"]],
                "description": "Tags across boards",
                "valueType": "BOOLEAN"
            ],
            "max_board_collaborators": [
                "defaultValue": ["value": "10"],
                "conditionalValues": ["Vision Pro": ["value": "6"]],
                "description": "Live collaborators per board",
                "valueType": "NUMBER"
            ],
            "onboarding_steps": [
                "defaultValue": ["value": "[\"canvas\",\"pencil\",\"outline\",\"share\"]"],
                "conditionalValues": ["Android": ["value": "[\"canvas\",\"stylus\",\"outline\",\"share\"]"]],
                "description": "Order of onboarding cards",
                "valueType": "JSON"
            ]
        ],
        "version": [
            "versionNumber": "112",
            "updateOrigin": "REST_API",
            "updateType": "INCREMENTAL_UPDATE",
            "updateUser": ["email": "priya.raman@northwind.example", "name": "Priya Raman"],
            "description": "Roll out tags to 10%"
        ]
    ]
}
#endif
