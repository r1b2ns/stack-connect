import Foundation
import APIProviderFirebase

// MARK: - Protocol

@MainActor
protocol MessagingViewModelProtocol: ObservableObject {
    var uiState: MessagingUiState { get set }
    func loadCampaigns() async
    func loadReports() async
    func loadApps() async
    func sendCampaign(_ draft: CampaignDraft) async
    func deleteCampaign(_ campaign: CampaignRecord) async
}

// MARK: - Tab

enum MessagingTab: String, CaseIterable, Identifiable {
    case campaigns = "Campaigns"
    case reports = "Reports"

    var id: String { rawValue }
}

// MARK: - Campaign Target

enum CampaignTarget: String, CaseIterable, Identifiable, Codable {
    case topic = "Topic"
    case condition = "Condition"
    case userSegment = "User Segment"

    var id: String { rawValue }
}

// MARK: - Selectable App

struct SelectableApp: Identifiable, Hashable {
    let id: String
    var appId: String
    var displayName: String
    var platform: FirebaseAppPlatform
    var bundleId: String?
    var packageName: String?
    var isSelected: Bool = false

    var platformIdentifier: String {
        bundleId ?? packageName ?? appId
    }

    /// A valid FCM topic name derived from the app's bundle ID or package name.
    /// FCM topics accept only `[a-zA-Z0-9-_.~%]`. We replace invalid chars with `_`.
    var topicName: String {
        let base = bundleId ?? packageName ?? appId
        let sanitized = base.map { c in
            c.isLetter || c.isNumber || c == "-" || c == "_" || c == "." || c == "~" || c == "%" ? String(c) : "_"
        }.joined()
        return sanitized
    }
}

// MARK: - Campaign Draft (for new campaign sheet)

struct CampaignDraft {
    var title: String = ""
    var body: String = ""
    var imageURL: String = ""
    var targetType: CampaignTarget = .topic
    var topic: String = ""
    var condition: String = ""
    var selectedApps: Set<String> = [] // appId set
    var analyticsLabel: String = ""
    var customData: [(key: String, value: String)] = []

    var isValid: Bool {
        let hasTitle = !title.trimmingCharacters(in: .whitespaces).isEmpty
        let hasBody = !body.trimmingCharacters(in: .whitespaces).isEmpty
        return hasTitle && hasBody && hasTarget
    }

    private var hasTarget: Bool {
        switch targetType {
        case .topic:
            return !topic.trimmingCharacters(in: .whitespaces).isEmpty
        case .condition:
            return !condition.trimmingCharacters(in: .whitespaces).isEmpty
        case .userSegment:
            return !selectedApps.isEmpty
        }
    }

    var targetDisplayValue: String {
        switch targetType {
        case .topic: return topic
        case .condition: return condition
        case .userSegment:
            let count = selectedApps.count
            return "\(count) app\(count == 1 ? "" : "s")"
        }
    }
}

// MARK: - Campaign Record (persisted locally)

struct CampaignRecord: Codable, Identifiable, Hashable {
    let id: String
    var title: String
    var body: String
    var imageURL: String?
    var targetType: CampaignTarget
    var targetValue: String
    var analyticsLabel: String?
    var messageIds: [String]
    var sentAt: Date
    var status: Status
    var sentCount: Int
    var failedCount: Int

    enum Status: String, Codable {
        case sent
        case partiallyFailed
        case failed
    }
}

// MARK: - Report Row

struct DeliveryReportRow: Identifiable {
    let id: String
    var date: String
    var appId: String?
    var messagesAccepted: Int
    var deliveredPercent: Float
    var collapsedPercent: Float
    var droppedPercent: Float
    var analyticsLabel: String?
}

// MARK: - UiState

struct MessagingUiState {
    var project: FirebaseProjectModel
    var account: AccountModel
    var selectedTab: MessagingTab = .campaigns

    // Campaigns
    var campaigns: [CampaignRecord] = []
    var isLoadingCampaigns = false
    var showNewCampaign = false
    var isSending = false

    // Apps (for user segment targeting)
    var availableApps: [SelectableApp] = []
    var isLoadingApps = false

    // Reports
    var reports: [DeliveryReportRow] = []
    var isLoadingReports = false
    var reportError: String?
    var reportApiActivationURL: String?

    var toastMessage: ToastMessage?
}

// MARK: - Implementation

@MainActor
final class MessagingViewModel: MessagingViewModelProtocol {

    @Published var uiState: MessagingUiState

    private let keychain: KeyStorable
    private let storage: PersistentStorable

    init(
        project: FirebaseProjectModel,
        account: AccountModel,
        keychain: KeyStorable = KeychainStorable.shared,
        storage: PersistentStorable? = nil
    ) {
        self.uiState = MessagingUiState(project: project, account: account)
        self.keychain = keychain
        self.storage = storage ?? SwiftDataStorable.shared
    }

    // MARK: - Load Apps

    func loadApps() async {
        guard uiState.availableApps.isEmpty else { return }
        uiState.isLoadingApps = true

        guard let provider = createProvider() else {
            uiState.isLoadingApps = false
            return
        }

        let projectId = uiState.project.projectId

        do {
            async let iosResponse = provider.request(
                FirebaseAPI.v1beta1.projects.id(projectId).iosApps.get()
            )
            async let androidResponse = provider.request(
                FirebaseAPI.v1beta1.projects.id(projectId).androidApps.get()
            )
            async let webResponse = provider.request(
                FirebaseAPI.v1beta1.projects.id(projectId).webApps.get()
            )

            let ios = try await iosResponse
            let android = try await androidResponse
            let web = try await webResponse

            var apps: [SelectableApp] = []

            for app in ios.apps ?? [] {
                guard let appId = app.appId else { continue }
                apps.append(SelectableApp(
                    id: appId,
                    appId: appId,
                    displayName: app.displayName ?? appId,
                    platform: .ios,
                    bundleId: app.bundleId
                ))
            }

            for app in android.apps ?? [] {
                guard let appId = app.appId else { continue }
                apps.append(SelectableApp(
                    id: appId,
                    appId: appId,
                    displayName: app.displayName ?? appId,
                    platform: .android,
                    packageName: app.packageName
                ))
            }

            for app in web.apps ?? [] {
                guard let appId = app.appId else { continue }
                apps.append(SelectableApp(
                    id: appId,
                    appId: appId,
                    displayName: app.displayName ?? appId,
                    platform: .web
                ))
            }

            uiState.availableApps = apps.sorted { $0.platform.sortOrder < $1.platform.sortOrder }
            Log.print.info("[Messaging] Loaded \(apps.count) apps")
        } catch {
            Log.print.error("[Messaging] Failed to load apps: \(error.localizedDescription)")
        }

        uiState.isLoadingApps = false
    }

    // MARK: - Campaigns

    func loadCampaigns() async {
        uiState.isLoadingCampaigns = true

        do {
            if let saved: [CampaignRecord] = try await storage.fetch(
                [CampaignRecord].self,
                id: campaignsStorageKey
            ) {
                uiState.campaigns = saved.sorted { $0.sentAt > $1.sentAt }
            }
        } catch {
            Log.print.error("[Messaging] Failed to load campaigns: \(error.localizedDescription)")
        }

        uiState.isLoadingCampaigns = false
    }

    func sendCampaign(_ draft: CampaignDraft) async {
        guard let provider = createProvider(), draft.isValid else { return }
        uiState.isSending = true

        let notification = FCMNotification(
            title: draft.title.trimmingCharacters(in: .whitespaces),
            body: draft.body.trimmingCharacters(in: .whitespaces),
            image: draft.imageURL.isEmpty ? nil : draft.imageURL
        )

        var dataPayload: [String: String]?
        if !draft.customData.isEmpty {
            var data: [String: String] = [:]
            for pair in draft.customData where !pair.key.isEmpty {
                data[pair.key] = pair.value
            }
            if !data.isEmpty { dataPayload = data }
        }

        var fcmOptions: FCMOptions?
        let label = draft.analyticsLabel.trimmingCharacters(in: .whitespaces)
        if !label.isEmpty {
            fcmOptions = FCMOptions(analyticsLabel: label)
        }

        var messageIds: [String] = []
        var sentCount = 0
        var failedCount = 0

        switch draft.targetType {
        case .topic:
            let message = FCMMessage(
                topic: draft.topic.trimmingCharacters(in: .whitespaces),
                notification: notification,
                data: dataPayload,
                fcmOptions: fcmOptions
            )
            let result = await sendSingleMessage(message, provider: provider)
            if let id = result { messageIds.append(id); sentCount += 1 } else { failedCount += 1 }

        case .condition:
            let message = FCMMessage(
                condition: draft.condition.trimmingCharacters(in: .whitespaces),
                notification: notification,
                data: dataPayload,
                fcmOptions: fcmOptions
            )
            let result = await sendSingleMessage(message, provider: provider)
            if let id = result { messageIds.append(id); sentCount += 1 } else { failedCount += 1 }

        case .userSegment:
            // Send one message per selected app using a topic derived from its bundle ID / package name.
            // Apps must subscribe their devices to the corresponding topic for delivery to work.
            // Topic convention: sanitized bundle ID or package name (e.g. "com.example.app").
            for appId in draft.selectedApps.sorted() {
                guard let app = uiState.availableApps.first(where: { $0.appId == appId }) else { continue }
                let message = FCMMessage(
                    topic: app.topicName,
                    notification: notification,
                    data: dataPayload,
                    fcmOptions: fcmOptions
                )
                let result = await sendSingleMessage(message, provider: provider)
                if let id = result { messageIds.append(id); sentCount += 1 } else { failedCount += 1 }
            }
        }

        let status: CampaignRecord.Status
        if failedCount == 0 {
            status = .sent
        } else if sentCount > 0 {
            status = .partiallyFailed
        } else {
            status = .failed
        }

        let record = CampaignRecord(
            id: UUID().uuidString,
            title: draft.title.trimmingCharacters(in: .whitespaces),
            body: draft.body.trimmingCharacters(in: .whitespaces),
            imageURL: draft.imageURL.isEmpty ? nil : draft.imageURL,
            targetType: draft.targetType,
            targetValue: draft.targetDisplayValue,
            analyticsLabel: label.isEmpty ? nil : label,
            messageIds: messageIds,
            sentAt: Date(),
            status: status,
            sentCount: sentCount,
            failedCount: failedCount
        )

        if status == .failed {
            uiState.toastMessage = ToastMessage(String(localized: "Failed to send"), icon: "exclamationmark.triangle.fill")
        } else if status == .partiallyFailed {
            uiState.toastMessage = ToastMessage(String(localized: "Partially sent (\(sentCount)/\(sentCount + failedCount))"), icon: "exclamationmark.circle.fill")
        } else {
            uiState.toastMessage = ToastMessage(String(localized: "Campaign sent"), icon: "checkmark.circle.fill")
        }

        uiState.campaigns.insert(record, at: 0)
        await saveCampaigns()

        uiState.isSending = false
        uiState.showNewCampaign = false
    }

    func deleteCampaign(_ campaign: CampaignRecord) async {
        uiState.campaigns.removeAll { $0.id == campaign.id }
        await saveCampaigns()
    }

    // MARK: - Reports

    func loadReports() async {
        uiState.isLoadingReports = true
        uiState.reportError = nil
        uiState.reportApiActivationURL = nil

        guard let provider = createProvider() else {
            uiState.reportError = String(localized: "No credentials found.")
            uiState.isLoadingReports = false
            return
        }

        do {
            let apps = try await provider.request(
                FirebaseAPI.v1beta1.projects.id(uiState.project.projectId).androidApps.get()
            )

            guard let androidApps = apps.apps, !androidApps.isEmpty else {
                uiState.reportError = String(localized: "No Android apps found. Delivery reports are only available for Android.")
                uiState.isLoadingReports = false
                return
            }

            var allRows: [DeliveryReportRow] = []

            for app in androidApps {
                guard let appId = app.appId else { continue }
                do {
                    let data = try await provider.request(
                        FirebaseAPI.deliveryData(
                            projectId: uiState.project.projectId,
                            appId: appId
                        ).list(pageSize: 30)
                    )

                    for entry in data.androidDeliveryData ?? [] {
                        let row = buildReportRow(from: entry, appId: appId)
                        allRows.append(row)
                    }
                } catch let apiError as APIProviderFirebase.Error {
                    if case .requestFailure(_, let errorResponse, _) = apiError,
                       let errorResponse, errorResponse.isServiceDisabled {
                        uiState.reportApiActivationURL = errorResponse.activationURL
                        uiState.reportError = String(localized: "The FCM Data API is not enabled for this project.")
                    } else {
                        uiState.reportError = apiError.localizedDescription
                    }
                }
            }

            uiState.reports = allRows.sorted { $0.date > $1.date }
            Log.print.info("[Messaging] Loaded \(allRows.count) delivery reports")
        } catch {
            uiState.reportError = error.localizedDescription
            Log.print.error("[Messaging] Reports failed: \(error.localizedDescription)")
        }

        uiState.isLoadingReports = false
    }

    // MARK: - Private

    private func sendSingleMessage(_ message: FCMMessage, provider: APIProviderFirebase) async -> String? {
        let request = FCMSendRequest(message: message)
        do {
            let response = try await provider.request(
                FirebaseAPI.messaging(projectId: uiState.project.projectId).send(request)
            )
            Log.print.info("[Messaging] Sent: \(response.name ?? "")")
            return response.name
        } catch {
            Log.print.error("[Messaging] Send failed: \(error.localizedDescription)")
            return nil
        }
    }

    private var campaignsStorageKey: String {
        "fcm-campaigns.\(uiState.project.projectId)"
    }

    private func saveCampaigns() async {
        do {
            try await storage.save(uiState.campaigns, id: campaignsStorageKey)
        } catch {
            Log.print.error("[Messaging] Failed to save campaigns: \(error.localizedDescription)")
        }
    }

    private func buildReportRow(from entry: AndroidDeliveryData, appId: String) -> DeliveryReportRow {
        let accepted = Int(entry.data?.countMessagesAccepted ?? "0") ?? 0
        let outcome = entry.data?.messageOutcomePercents

        let d1: Float = outcome?.droppedTooManyPendingMessages ?? 0
        let d2: Float = outcome?.droppedDeviceInactive ?? 0
        let d3: Float = outcome?.droppedAppForceStopped ?? 0
        let droppedTotal: Float = d1 + d2 + d3

        return DeliveryReportRow(
            id: entry.id,
            date: entry.date?.formatted ?? "–",
            appId: appId,
            messagesAccepted: accepted,
            deliveredPercent: outcome?.delivered ?? 0,
            collapsedPercent: outcome?.collapsed ?? 0,
            droppedPercent: droppedTotal,
            analyticsLabel: entry.analyticsLabel
        )
    }

    private func createProvider() -> APIProviderFirebase? {
        guard let credentials: FirebaseCredentials = keychain.object(forKey: "credentials.\(uiState.account.id)") else { return nil }
        guard let jsonData = credentials.serviceAccountJSON.data(using: .utf8) else { return nil }
        guard let config = try? FirebaseConfiguration(serviceAccountJSON: jsonData) else { return nil }
        return APIProviderFirebase(configuration: config)
    }
}
