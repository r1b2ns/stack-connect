#if DEBUG
import Foundation
import APIProviderFirebase

/// `FirebaseProviderMaking` for fake data mode: the real `APIProviderFirebase`
/// (request building, decoding, error handling) wired to an in-process
/// `FakeFirebaseServer` instead of URLSession, and to an authenticator that
/// never contacts Google's token endpoint.
final class FakeFirebaseProviderFactory: FirebaseProviderMaking, @unchecked Sendable {

    let server: FakeFirebaseServer

    init(server: FakeFirebaseServer) {
        self.server = server
    }

    func makeProvider(configuration: FirebaseConfiguration) -> APIProviderFirebase {
        APIProviderFirebase(
            configuration: configuration,
            requestExecutor: FakeFirebaseRequestExecutor(server: server, clientEmail: configuration.serviceAccount.clientEmail),
            authenticator: FakeFirebaseAuthenticator()
        )
    }
}

/// Adds a placeholder bearer token: fake requests are answered in-process.
struct FakeFirebaseAuthenticator: RequestAuthenticating {
    func adapt(_ urlRequest: URLRequest) async throws -> URLRequest {
        var request = urlRequest
        request.setValue("Bearer fake-data-token", forHTTPHeaderField: "Authorization")
        return request
    }
}

/// Hands each request to the server on a background queue (like URLSession's
/// delegate queue) and reports the response.
struct FakeFirebaseRequestExecutor: RequestExecutor {

    let server: FakeFirebaseServer
    let clientEmail: String

    func execute(_ urlRequest: URLRequest, completion: @escaping (Result<Response<Data>, Error>) -> Void) {
        let server = self.server
        let clientEmail = self.clientEmail
        // The executor contract is callback-based; `APIProviderFirebase` resumes
        // a continuation from it, so handing the closure to another queue is safe.
        nonisolated(unsafe) let completion = completion
        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 0.15) {
            let reply = server.handle(urlRequest, clientEmail: clientEmail)
            completion(.success(Response(requestURL: urlRequest.url, statusCode: reply.status, data: reply.body, headers: reply.headers)))
        }
    }
}

/// An in-memory implementation of the Firebase REST endpoints the app uses:
/// Management (projects, apps, config files, analytics link), Remote Config,
/// Google Analytics Data (`runReport`), FCM `send` and FCM Data (delivery stats).
/// Writes (rename / add / remove apps, publish a template) change the state.
final class FakeFirebaseServer: @unchecked Sendable {

    struct Reply {
        let status: Int
        let body: Data
        var headers: [AnyHashable: Any] = ["Content-Type": "application/json"]
    }

    private struct ProjectState {
        var project: FakeFirebaseCatalog.Project
        var removedAppIds: Set<String> = []
        var template: [String: Any]
        var versions: [[String: Any]]
    }

    private let lock = NSLock()
    private let clock: FakeClock
    /// client e-mail → project id → state
    private var accounts: [String: [String: ProjectState]]

    init(clock: FakeClock) {
        self.clock = clock
        var projects: [String: ProjectState] = [:]
        for project in FakeFirebaseCatalog.projects {
            var template = FakeFirebaseCatalog.remoteConfig(for: project.projectId)
            var version = template["version"] as? [String: Any] ?? [:]
            version["updateTime"] = clock.iso(daysAgo: 2, hoursAgo: 5)
            template["version"] = version
            let number = Int(version["versionNumber"] as? String ?? "1") ?? 1
            let updateUser: Any = version["updateUser"] ?? [String: String]()
            let latestDescription: Any = version["description"] ?? ""
            var history: [[String: Any]] = []
            for offset in 0..<5 {
                var entry: [String: Any] = [:]
                entry["versionNumber"] = String(number - offset)
                entry["updateTime"] = clock.iso(daysAgo: 2 + Double(offset) * 6)
                entry["updateOrigin"] = offset.isMultiple(of: 2) ? "CONSOLE" : "REST_API"
                entry["updateType"] = offset == 4 ? "ROLLBACK" : "INCREMENTAL_UPDATE"
                entry["updateUser"] = updateUser
                entry["description"] = offset == 0 ? latestDescription : "Routine parameter update"
                history.append(entry)
            }
            projects[project.projectId] = ProjectState(project: project, template: template, versions: history)
        }
        accounts = [FakeFirebaseCatalog.northwindClientEmail: projects]
    }

    // MARK: - Routing

    func handle(_ request: URLRequest, clientEmail: String) -> Reply {
        guard let url = request.url,
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return error(400, "Bad request")
        }
        let method = request.httpMethod ?? "GET"
        let host = components.host ?? ""
        let path = components.percentEncodedPath.removingPercentEncoding ?? components.path
        let segments = path.split(separator: "/").map(String.init)
        let body = request.httpBody.flatMap { try? JSONSerialization.jsonObject(with: $0) } as? [String: Any]

        return lock.withLock {
            var projects = accounts[clientEmail] ?? [:]
            defer { accounts[clientEmail] = projects }
            switch host {
            case "firebase.googleapis.com":
                return management(method: method, segments: segments, query: components.queryItems ?? [], body: body, projects: &projects)
            case "firebaseremoteconfig.googleapis.com":
                return remoteConfig(method: method, segments: segments, body: request.httpBody, clientEmail: clientEmail, projects: &projects)
            case "analyticsdata.googleapis.com":
                return analyticsReport(segments: segments, projects: projects)
            case "fcm.googleapis.com":
                return sendMessage(segments: segments, projects: projects)
            case "fcmdata.googleapis.com":
                return deliveryData(segments: segments, projects: projects)
            default:
                return error(404, "Unknown host \(host)")
            }
        }
    }

    // MARK: Management API

    private func management(
        method: String,
        segments: [String],
        query: [URLQueryItem],
        body: [String: Any]?,
        projects: inout [String: ProjectState]
    ) -> Reply {
        // /v1beta1/projects
        guard segments.count >= 2, segments[1] == "projects" else { return error(404, "Not found") }
        if segments.count == 2 {
            let results = projects.values.sorted { $0.project.displayName < $1.project.displayName }.map { projectJSON($0.project) }
            return json(["results": results])
        }
        let projectId = segments[2]
        guard var state = projects[projectId] else { return error(404, "Project \(projectId) not found") }
        defer { projects[projectId] = state }

        if segments.count == 3 { return json(projectJSON(state.project)) }

        let collection = segments[3]
        if collection == "analyticsDetails" {
            return json([
                "analyticsProperty": ["id": state.project.analyticsPropertyId, "displayName": "\(state.project.displayName) – GA4"],
                "streamId": "\(state.project.analyticsPropertyId)01"
            ])
        }
        guard let platform = platform(forCollection: collection) else { return error(404, "Not found") }

        // /projects/{id}/{platform}Apps
        if segments.count == 4 {
            if method == "POST" {
                let identifier = body?["bundleId"] as? String ?? body?["packageName"] as? String
                let suffix = String(UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(16)).lowercased()
                let app = FakeFirebaseCatalog.App(
                    appId: "1:\(state.project.projectNumber):\(platform.rawValue):\(suffix)", platform: platform,
                    displayName: body?["displayName"] as? String ?? identifier ?? "New app",
                    identifier: platform == .web ? nil : identifier, appStoreId: body?["appStoreId"] as? String
                )
                state.project.apps.append(app)
                return json(["name": "operations/create.\(suffix)", "done": true])
            }
            let apps = state.project.apps.filter { $0.platform == platform && !state.removedAppIds.contains($0.appId) }
            return json(["apps": apps.map { appJSON($0, project: state.project) }])
        }

        // /projects/{id}/{platform}Apps/{appId}[:remove | /config]
        // App ids contain colons themselves ("1:483920175624:ios:8c1b…"), so only
        // a known trailing custom method is split off — never the first colon.
        var appSegment = segments[4]
        var action: String?
        if appSegment.hasSuffix(":remove") {
            action = "remove"
            appSegment = String(appSegment.dropLast(":remove".count))
        }
        guard let index = state.project.apps.firstIndex(where: { $0.appId == appSegment }),
              !state.removedAppIds.contains(appSegment) else {
            return error(404, "App \(appSegment) not found")
        }
        if action == "remove" {
            state.removedAppIds.insert(appSegment)
            return json(["name": "operations/remove.\(appSegment)", "done": true])
        }
        if segments.count == 6, segments[5] == "config" {
            return json(configJSON(state.project.apps[index], project: state.project))
        }
        if method == "PATCH", let name = body?["displayName"] as? String {
            state.project.apps[index].displayName = name
            return json(["name": "projects/\(projectId)/\(collection)/\(appSegment)", "appId": appSegment, "displayName": name])
        }
        return json(appJSON(state.project.apps[index], project: state.project))
    }

    private func platform(forCollection collection: String) -> FakeFirebaseCatalog.App.Platform? {
        switch collection {
        case "iosApps":     return .ios
        case "androidApps": return .android
        case "webApps":     return .web
        default:            return nil
        }
    }

    private func projectJSON(_ project: FakeFirebaseCatalog.Project) -> [String: Any] {
        [
            "name": "projects/\(project.projectId)",
            "projectId": project.projectId,
            "projectNumber": project.projectNumber,
            "displayName": project.displayName,
            "state": "ACTIVE",
            "resources": [
                "hostingSite": project.projectId,
                "realtimeDatabaseInstance": "\(project.projectId)-default-rtdb",
                "storageBucket": "\(project.projectId).appspot.example",
                "locationId": project.locationId
            ]
        ]
    }

    private func appJSON(_ app: FakeFirebaseCatalog.App, project: FakeFirebaseCatalog.Project) -> [String: Any] {
        var result: [String: Any] = [
            "name": "projects/\(project.projectId)/\(app.platform.rawValue)Apps/\(app.appId)",
            "appId": app.appId,
            "displayName": app.displayName,
            "projectId": project.projectId,
            "apiKeyId": "fake-key-\(app.appId.suffix(8))",
            "state": "ACTIVE",
            "etag": "1_\(abs(FakeAppStoreConnectCatalog.hash(app.displayName)) % 1_000_000)"
        ]
        switch app.platform {
        case .ios:
            result["bundleId"] = app.identifier
            result["teamId"] = "NW7Q2K9L4M"
            if let appStoreId = app.appStoreId { result["appStoreId"] = appStoreId }
        case .android:
            result["packageName"] = app.identifier
            result["sha1Hashes"] = app.sha1
            result["sha256Hashes"] = [String]()
        case .web:
            result["appUrls"] = app.appUrls
        }
        return result
    }

    private func configJSON(_ app: FakeFirebaseCatalog.App, project: FakeFirebaseCatalog.Project) -> [String: Any] {
        let apiKey = "AIzaFAKE-\(project.projectId)-\(app.appId.suffix(6))"
        let storageBucket = "\(project.projectId).appspot.example"
        let clientPrefix = "\(project.projectNumber)-\(app.appId.suffix(16))"
        switch app.platform {
        case .ios:
            let bundleId = app.identifier ?? ""
            let plist = """
            <?xml version="1.0" encoding="UTF-8"?>
            <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
            <plist version="1.0">
            <dict>
            \t<key>CLIENT_ID</key>
            \t<string>\(clientPrefix).apps.googleusercontent.example</string>
            \t<key>REVERSED_CLIENT_ID</key>
            \t<string>example.googleusercontent.apps.\(clientPrefix)</string>
            \t<key>API_KEY</key>
            \t<string>\(apiKey)</string>
            \t<key>GCM_SENDER_ID</key>
            \t<string>\(project.projectNumber)</string>
            \t<key>PLIST_VERSION</key>
            \t<string>1</string>
            \t<key>BUNDLE_ID</key>
            \t<string>\(bundleId)</string>
            \t<key>PROJECT_ID</key>
            \t<string>\(project.projectId)</string>
            \t<key>STORAGE_BUCKET</key>
            \t<string>\(storageBucket)</string>
            \t<key>IS_ADS_ENABLED</key>
            \t<false/>
            \t<key>IS_ANALYTICS_ENABLED</key>
            \t<true/>
            \t<key>IS_APPINVITE_ENABLED</key>
            \t<true/>
            \t<key>IS_GCM_ENABLED</key>
            \t<true/>
            \t<key>IS_SIGNIN_ENABLED</key>
            \t<true/>
            \t<key>GOOGLE_APP_ID</key>
            \t<string>\(app.appId)</string>
            \t<key>DATABASE_URL</key>
            \t<string>https://\(project.projectId)-default-rtdb.database.example</string>
            </dict>
            </plist>
            """
            return ["configFilename": "GoogleService-Info.plist", "configFileContents": Data(plist.utf8).base64EncodedString()]
        case .android:
            let services: [String: Any] = [
                "project_info": [
                    "project_number": project.projectNumber,
                    "firebase_url": "https://\(project.projectId)-default-rtdb.database.example",
                    "project_id": project.projectId,
                    "storage_bucket": storageBucket
                ],
                "client": [[
                    "client_info": ["mobilesdk_app_id": app.appId,
                                    "android_client_info": ["package_name": app.identifier ?? ""]],
                    "oauth_client": [["client_id": "\(clientPrefix).apps.googleusercontent.example", "client_type": 3]],
                    "api_key": [["current_key": apiKey]],
                    "services": ["appinvite_service": ["other_platform_oauth_client": [
                        ["client_id": "\(clientPrefix).apps.googleusercontent.example", "client_type": 3]
                    ]]]
                ]],
                "configuration_version": "1"
            ]
            let data = (try? JSONSerialization.data(withJSONObject: services, options: [.prettyPrinted, .sortedKeys])) ?? Data()
            return ["configFilename": "google-services.json", "configFileContents": data.base64EncodedString()]
        case .web:
            // The web config endpoint returns the fields directly (no file).
            return [
                "projectId": project.projectId, "appId": app.appId, "apiKey": apiKey,
                "authDomain": "\(project.projectId).auth.example",
                "databaseURL": "https://\(project.projectId)-default-rtdb.database.example",
                "storageBucket": storageBucket,
                "messagingSenderId": project.projectNumber,
                "measurementId": "G-\(project.analyticsPropertyId.suffix(6))"
            ]
        }
    }

    // MARK: Remote Config

    private func remoteConfig(
        method: String,
        segments: [String],
        body: Data?,
        clientEmail: String,
        projects: inout [String: ProjectState]
    ) -> Reply {
        // /v1/projects/{id}/remoteConfig[:listVersions]
        guard segments.count >= 4, segments[1] == "projects", var state = projects[segments[2]] else {
            return error(404, "Not found")
        }
        defer { projects[segments[2]] = state }
        let last = segments[3]
        if last.hasSuffix(":listVersions") {
            return json(["versions": state.versions])
        }
        if method == "PUT", let body, var template = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any] {
            let current = state.template["version"] as? [String: Any]
            let number = (Int(current?["versionNumber"] as? String ?? "0") ?? 0) + 1
            let version: [String: Any] = [
                "versionNumber": String(number),
                "updateTime": FakeClock.iso(Date()),
                "updateOrigin": "REST_API",
                "updateType": "INCREMENTAL_UPDATE",
                "updateUser": ["email": clientEmail]
            ]
            template["version"] = version
            state.template = template
            state.versions.insert(version, at: 0)
        }
        var reply = json(state.template)
        let number = (state.template["version"] as? [String: Any])?["versionNumber"] as? String ?? "1"
        reply.headers["ETag"] = "etag-\(segments[2])-\(number)"
        return reply
    }

    // MARK: Analytics Data API

    private func analyticsReport(segments: [String], projects: [String: ProjectState]) -> Reply {
        // /v1beta/properties/{id}:runReport
        guard segments.count >= 3 else { return error(404, "Not found") }
        let propertyId = segments[2].components(separatedBy: ":").first ?? segments[2]
        guard let project = projects.values.first(where: { $0.project.analyticsPropertyId == propertyId })?.project else {
            return error(404, "Property \(propertyId) not found")
        }
        var random = FakeRandom(seed: project.projectId)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyyMMdd"
        let rows: [[String: Any]] = (0...30).reversed().map { daysAgo in
            let date = clock.date(daysAgo: Double(daysAgo))
            let weekday = Calendar(identifier: .gregorian).component(.weekday, from: date)
            let weekend = weekday == 1 || weekday == 7
            let growth = 1 + Double(30 - daysAgo) * 0.004
            let noise = 0.94 + random.unit() * 0.12
            let dau = Int(Double(project.dailyUsers) * growth * noise * (weekend ? 1.18 : 1))
            let wau = Int(Double(project.dailyUsers) * growth * 3.4)
            let mau = Int(Double(project.dailyUsers) * growth * 7.9)
            return [
                "dimensionValues": [["value": formatter.string(from: date)]],
                "metricValues": [["value": String(dau)], ["value": String(wau)], ["value": String(mau)]]
            ]
        }
        return json([
            "dimensionHeaders": [["name": "date"]],
            "metricHeaders": [["name": "activeUsers", "type": "TYPE_INTEGER"],
                              ["name": "active7DayUsers", "type": "TYPE_INTEGER"],
                              ["name": "active28DayUsers", "type": "TYPE_INTEGER"]],
            "rows": rows,
            "rowCount": rows.count
        ])
    }

    // MARK: Cloud Messaging

    private func sendMessage(segments: [String], projects: [String: ProjectState]) -> Reply {
        // /v1/projects/{id}/messages:send
        guard segments.count >= 3, projects[segments[2]] != nil else { return error(404, "Project not found") }
        let messageId = "0:\(Int(Date().timeIntervalSince1970 * 1000))%\(UUID().uuidString.prefix(8).lowercased())"
        return json(["name": "projects/\(segments[2])/messages/\(messageId)"])
    }

    private func deliveryData(segments: [String], projects: [String: ProjectState]) -> Reply {
        // /v1beta1/projects/{id}/androidApps/{appId}/deliveryData
        guard segments.count >= 5, let project = projects[segments[2]]?.project else { return error(404, "Not found") }
        let appId = segments[4]
        var random = FakeRandom(seed: appId)
        let calendar = Calendar(identifier: .gregorian)
        let items: [[String: Any]] = (1...7).flatMap { daysAgo -> [[String: Any]] in
            let date = clock.date(daysAgo: Double(daysAgo))
            let components = calendar.dateComponents(in: TimeZone(secondsFromGMT: 0) ?? .current, from: date)
            return ["weekly_digest", "trail_alerts"].map { label in
                let accepted = random.int(in: 4_000...38_000) * (project.dailyUsers > 30_000 ? 2 : 1)
                let delivered = 88 + random.unit() * 8
                let pending = 1 + random.unit() * 3
                let inactive = 100 - delivered - pending - 1.2
                return [
                    "appId": appId,
                    "date": ["year": components.year ?? 2026, "month": components.month ?? 1, "day": components.day ?? 1],
                    "analyticsLabel": label,
                    "data": [
                        "countMessagesAccepted": String(accepted),
                        "messageOutcomePercents": [
                            "delivered": delivered, "pending": pending, "droppedTooManyPendingMessages": 0.4,
                            "droppedDeviceInactive": max(inactive, 0), "droppedAppForceStopped": 0.8, "collapsed": 0.0
                        ],
                        "deliveryPerformancePercents": [
                            "deliveredNoDelay": 91.5 + random.unit() * 4, "delayedDeviceDoze": 4.1,
                            "delayedDeviceOffline": 2.3, "delayedMessageThrottled": 0.6
                        ]
                    ]
                ]
            }
        }
        return json(["androidDeliveryData": items])
    }

    // MARK: - Helpers

    private func json(_ object: Any) -> Reply {
        let data = (try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])) ?? Data("{}".utf8)
        return Reply(status: 200, body: data)
    }

    private func error(_ status: Int, _ message: String) -> Reply {
        let payload: [String: Any] = ["error": ["code": status, "message": "\(message) (fake data)", "status": status == 404 ? "NOT_FOUND" : "INVALID_ARGUMENT"]]
        let data = (try? JSONSerialization.data(withJSONObject: payload)) ?? Data()
        return Reply(status: status, body: data)
    }
}
#endif
