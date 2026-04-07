import SwiftUI
import StoreKit
import UniformTypeIdentifiers

struct PaywallView: View {

    @EnvironmentObject private var subscriptionService: SubscriptionService

    @State private var selectedPlan: SubscriptionTier = .individual
    @State private var billingPeriod: BillingPeriod = .monthly
    @State private var isPurchasing = false

    // Import flow
    @State private var showImportPicker = false
    @State private var showImportPasswordAlert = false
    @State private var showImportError = false
    @State private var showImportNameAlert = false
    @State private var importPassword = ""
    @State private var importCustomName = ""
    @State private var importErrorMessage = ""
    @State private var selectedImportURL: URL?
    @State private var isImporting = false

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 24) {
                    buildHeader()
                    if let loadError = subscriptionService.loadError {
                        buildLoadErrorView(loadError)
                    }
                    if selectedPlan != .lifetime {
                        buildBillingToggle()
                    }
                    buildPlanCarousel()
                    buildFeaturesList()
                }
                .padding(.horizontal, 20)
                .padding(.top, 40)
                .padding(.bottom, 16)
            }

            buildFooter()
        }
        .background(Color(.systemGroupedBackground))
        .task { await subscriptionService.loadProducts() }
        .fileImporter(
            isPresented: $showImportPicker,
            allowedContentTypes: [.data],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first {
                    selectedImportURL = url
                    importPassword = ""
                    showImportPasswordAlert = true
                }
            case .failure(let error):
                Log.print.error("[Paywall] File picker error: \(error.localizedDescription)")
            }
        }
        .alert(
            String(localized: "Enter Password"),
            isPresented: $showImportPasswordAlert
        ) {
            SecureField(String(localized: "Password"), text: $importPassword)
            Button(String(localized: "Cancel"), role: .cancel) {
                selectedImportURL = nil
                importPassword = ""
            }
            Button(String(localized: "Decrypt")) {
                tryDecryptImport()
            }
        } message: {
            Text(String(localized: "Enter the password used to encrypt this file."))
        }
        .alert(
            String(localized: "Decryption Failed"),
            isPresented: $showImportError
        ) {
            Button(String(localized: "Try Again")) {
                importPassword = ""
                showImportPasswordAlert = true
            }
            Button(String(localized: "Cancel"), role: .cancel) {
                selectedImportURL = nil
                importPassword = ""
            }
        } message: {
            Text(importErrorMessage)
        }
        .alert(
            String(localized: "Import Account"),
            isPresented: $showImportNameAlert
        ) {
            TextField(String(localized: "Account Name"), text: $importCustomName)
            Button(String(localized: "Cancel"), role: .cancel) {
                selectedImportURL = nil
                importPassword = ""
            }
            Button(String(localized: "Import")) {
                Task { await performImport() }
            }
        } message: {
            Text(String(localized: "Choose a name for this account."))
        }
    }

    // MARK: - Load Error

    private func buildLoadErrorView(_ message: String) -> some View {
        VStack(spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 4) {
                    Text(String(localized: "Could not load plans"))
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Button {
                Task { await subscriptionService.loadProducts() }
            } label: {
                Label(String(localized: "Retry"), systemImage: "arrow.clockwise")
                    .font(.subheadline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .foregroundStyle(.white)
                    .background(.accent)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            .disabled(subscriptionService.isLoading)
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Header

    private func buildHeader() -> some View {
        VStack(spacing: 8) {
            Image(systemName: "apps.iphone")
                .font(.system(size: 50))
                .foregroundStyle(.accent)

            Text("StackConnect")
                .font(.largeTitle)
                .fontWeight(.bold)

            Text(String(localized: "Choose your plan to get started"))
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Plan Carousel

    private func buildPlanCarousel() -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                buildPlanCard(
                    tier: .individual,
                    icon: "person.fill",
                    color: .blue,
                    features: [
                        String(localized: "Manage all accounts"),
                        String(localized: "Offline-first sync"),
                        String(localized: "App analytics")
                    ]
                )

                buildPlanCard(
                    tier: .team,
                    icon: "person.3.fill",
                    color: .purple,
                    features: [
                        String(localized: "Everything in Individual"),
                        String(localized: "Export & share accounts"),
                        String(localized: "Import team accounts")
                    ]
                )

                buildPlanCard(
                    tier: .lifetime,
                    icon: "infinity",
                    color: .orange,
                    features: [
                        String(localized: "Everything in Team"),
                        String(localized: "One-time payment"),
                        String(localized: "Lifetime access")
                    ]
                )
            }
            .padding(.horizontal, 4)
        }
    }

    private func buildPlanCard(
        tier: SubscriptionTier,
        icon: String,
        color: Color,
        features: [String]
    ) -> some View {
        let isSelected = selectedPlan == tier
        let price = priceText(for: tier)

        return Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                selectedPlan = tier
            }
        } label: {
            VStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 28))
                    .foregroundStyle(color)

                VStack(spacing: 2) {
                    Text(tier.displayName)
                        .font(.headline)
                        .foregroundStyle(.primary)

                    Text(subtitleForTier(tier))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Text(price)
                    .font(.title3)
                    .fontWeight(.bold)
                    .foregroundStyle(color)

                VStack(alignment: .leading, spacing: 6) {
                    ForEach(features, id: \.self) { feature in
                        HStack(spacing: 6) {
                            Image(systemName: "checkmark")
                                .font(.caption2)
                                .foregroundStyle(color)
                            Text(feature)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .frame(width: 170)
            .padding(16)
            .background(isSelected ? color.opacity(0.1) : Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(isSelected ? color : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Billing Toggle

    private func buildBillingToggle() -> some View {
        Picker(String(localized: "Billing"), selection: $billingPeriod) {
            ForEach(BillingPeriod.allCases, id: \.self) { period in
                Text(period.displayName).tag(period)
            }
        }
        .pickerStyle(.segmented)
    }

    // MARK: - Features List

    private func buildFeaturesList() -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if selectedPlan == .individual {
                buildFeatureRow(icon: "xmark.circle.fill", color: .red, text: String(localized: "Export accounts not included"))
                Text(String(localized: "The Individual plan does not allow sharing accounts within the app."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.leading, 26)
            } else {
                buildFeatureRow(icon: "checkmark.circle.fill", color: .green, text: String(localized: "Export & import accounts included"))
                Text(String(localized: "Exporting an account is a convenient way to share app access with other users in your team."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.leading, 26)
            }

            if selectedPlan == .lifetime {
                buildFeatureRow(icon: "checkmark.circle.fill", color: .green, text: String(localized: "Pay once, use forever"))
            }
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func buildFeatureRow(icon: String, color: Color, text: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(color)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.primary)
        }
    }

    // MARK: - Footer

    private func buildFooter() -> some View {
        VStack(spacing: 20) {
            Divider()

            Button {
                Task { await performPurchase() }
            } label: {
                Group {
                    if isPurchasing || subscriptionService.isLoading {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Text(String(localized: "Subscribe Now"))
                            .fontWeight(.semibold)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .foregroundStyle(.white)
                .background(.accent)
                .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .disabled(isPurchasing || subscriptionService.isLoading || selectedProduct == nil)
            .padding(.horizontal, 20)

            HStack(spacing: 24) {
                Button {
                    Task {
                        await subscriptionService.restorePurchases()
                    }
                } label: {
                    Text(String(localized: "Restore Purchases"))
                        .font(.subheadline)
                        .foregroundStyle(.accent)
                }

                Button {
                    showImportPicker = true
                } label: {
                    Text(String(localized: "Import Account"))
                        .font(.subheadline)
                        .foregroundStyle(.accent)
                }
            }

            if let error = subscriptionService.purchaseError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 20)
            }

            HStack(spacing: 16) {
                Link(String(localized: "Terms of Use"), destination: URL(string: "https://apple.com/legal/internet-services/itunes/dev/stdeula/")!)
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                Link(String(localized: "Privacy Policy"), destination: URL(string: "https://apple.com/privacy/")!)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(.bottom, 8)
        }
        .background(.bar)
    }

    // MARK: - Helpers

    private var selectedProduct: Product? {
        switch selectedPlan {
        case .individual: return subscriptionService.individualProduct(period: billingPeriod)
        case .team:       return subscriptionService.teamProduct(period: billingPeriod)
        case .lifetime:   return subscriptionService.lifetimeProduct
        }
    }

    private func priceText(for tier: SubscriptionTier) -> String {
        switch tier {
        case .individual:
            if let product = subscriptionService.individualProduct(period: billingPeriod) {
                return product.displayPrice + (billingPeriod == .monthly ? "/mo" : "/yr")
            }
        case .team:
            if let product = subscriptionService.teamProduct(period: billingPeriod) {
                return product.displayPrice + (billingPeriod == .monthly ? "/mo" : "/yr")
            }
        case .lifetime:
            if let product = subscriptionService.lifetimeProduct {
                return product.displayPrice
            }
        }
        return "..."
    }

    private func subtitleForTier(_ tier: SubscriptionTier) -> String {
        switch tier {
        case .individual: return String(localized: "For solo developers")
        case .team:       return String(localized: "For teams & collaboration")
        case .lifetime:   return String(localized: "Pay once, own forever")
        }
    }

    private func performPurchase() async {
        guard let product = selectedProduct else { return }
        isPurchasing = true
        _ = await subscriptionService.purchase(product)
        isPurchasing = false
    }

    // MARK: - Import Flow

    private func tryDecryptImport() {
        guard let url = selectedImportURL else { return }

        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }

        guard let data = try? Data(contentsOf: url) else {
            importErrorMessage = String(localized: "Failed to read file.")
            showImportError = true
            return
        }

        do {
            let json = try AccountCrypto.decrypt(data: data, password: importPassword)
            if let jsonData = json.data(using: .utf8),
               let dict = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
               let name = dict["name"] as? String {
                importCustomName = name
            } else {
                importCustomName = ""
            }
            showImportNameAlert = true
        } catch {
            importErrorMessage = error.localizedDescription
            showImportError = true
        }
    }

    private func performImport() async {
        guard let url = selectedImportURL else { return }
        isImporting = true

        let importer = AccountImporter()
        let error = await importer.importAccount(
            from: url,
            password: importPassword,
            customName: importCustomName
        )

        if let error {
            importErrorMessage = error
            showImportError = true
        } else {
            // Grant access to the app
            subscriptionService.grantImportedAccess()
        }

        selectedImportURL = nil
        importPassword = ""
        isImporting = false
    }
}

// MARK: - Account Importer

@MainActor
private struct AccountImporter {

    private let storage: PersistentStorable
    private let keychain: KeyStorable

    init(
        storage: PersistentStorable? = nil,
        keychain: KeyStorable = KeychainStorable.shared
    ) {
        self.storage = storage ?? SwiftDataStorable.shared
        self.keychain = keychain
    }

    /// Imports an encrypted account file. Returns nil on success or error message.
    func importAccount(from url: URL, password: String, customName: String?) async -> String? {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }

        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            return String(localized: "Failed to read file.")
        }

        let jsonString: String
        do {
            jsonString = try AccountCrypto.decrypt(data: data, password: password)
        } catch {
            return error.localizedDescription
        }

        guard let jsonData = jsonString.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
            return String(localized: "Invalid JSON format.")
        }

        guard let name = dict["name"] as? String, !name.isEmpty else {
            return String(localized: "Missing or invalid 'name' field.")
        }
        guard let providerRaw = dict["providerType"] as? String,
              let providerType = ProviderType(rawValue: providerRaw) else {
            return String(localized: "Missing or invalid 'providerType' field.")
        }

        let emptyRules = AccountRules(apps: [], version: [], users: [], review: [], testFlight: [], analytics: [])
        var rules = emptyRules
        if let rulesDict = dict["rules"] as? [String: [String]] {
            rules = AccountRules(
                apps: rulesDict["apps"]?.compactMap { AccountPermission(rawValue: $0) } ?? [],
                version: rulesDict["version"]?.compactMap { AccountPermission(rawValue: $0) } ?? [],
                users: rulesDict["users"]?.compactMap { AccountPermission(rawValue: $0) } ?? [],
                review: rulesDict["review"]?.compactMap { AccountPermission(rawValue: $0) } ?? [],
                testFlight: rulesDict["testFlight"]?.compactMap { AccountPermission(rawValue: $0) } ?? [],
                analytics: rulesDict["analytics"]?.compactMap { AccountPermission(rawValue: $0) } ?? []
            )
        }

        guard let credsDict = dict["credentials"] as? [String: String] else {
            return String(localized: "Missing or invalid 'credentials' field.")
        }

        // Check duplicates
        let allAccounts = (try? await storage.fetchAll(AccountModel.self)) ?? []
        let sameTypeAccounts = allAccounts.filter { $0.providerType == providerType }
        let accountId = UUID().uuidString

        switch providerType {
        case .apple:
            guard let issuerID = credsDict["issuerID"], !issuerID.isEmpty,
                  let privateKeyID = credsDict["privateKeyID"], !privateKeyID.isEmpty,
                  let privateKey = credsDict["privateKey"], !privateKey.isEmpty else {
                return String(localized: "Invalid Apple credentials.")
            }
            for existing in sameTypeAccounts {
                if let creds: AppleCredentials = keychain.object(forKey: "credentials.\(existing.id)"),
                   creds.privateKey == privateKey {
                    return String(localized: "An account with these credentials already exists: \"\(existing.name)\".")
                }
            }
            keychain.setObject(AppleCredentials(issuerID: issuerID, privateKeyID: privateKeyID, privateKey: privateKey), forKey: "credentials.\(accountId)")
        case .firebase:
            guard let json = credsDict["serviceAccountJSON"], !json.isEmpty else {
                return String(localized: "Invalid Firebase credentials.")
            }
            for existing in sameTypeAccounts {
                if let creds: FirebaseCredentials = keychain.object(forKey: "credentials.\(existing.id)"),
                   creds.serviceAccountJSON == json {
                    return String(localized: "An account with these credentials already exists: \"\(existing.name)\".")
                }
            }
            keychain.setObject(FirebaseCredentials(serviceAccountJSON: json), forKey: "credentials.\(accountId)")
        case .googlePlay:
            guard let json = credsDict["serviceAccountJSON"], !json.isEmpty else {
                return String(localized: "Invalid Google Play credentials.")
            }
            for existing in sameTypeAccounts {
                if let creds: GooglePlayCredentials = keychain.object(forKey: "credentials.\(existing.id)"),
                   creds.serviceAccountJSON == json {
                    return String(localized: "An account with these credentials already exists: \"\(existing.name)\".")
                }
            }
            keychain.setObject(GooglePlayCredentials(serviceAccountJSON: json), forKey: "credentials.\(accountId)")
        }

        let accountName = (customName?.trimmingCharacters(in: .whitespaces).isEmpty == false)
            ? customName!.trimmingCharacters(in: .whitespaces)
            : name
        let account = AccountModel(
            id: accountId,
            name: accountName,
            providerType: providerType,
            rules: rules,
            origin: .imported
        )

        do {
            try await storage.save(account, id: account.id)
            Log.print.info("[Paywall] Imported account: \(accountName)")
            return nil
        } catch {
            return String(localized: "Failed to save imported account.")
        }
    }
}
