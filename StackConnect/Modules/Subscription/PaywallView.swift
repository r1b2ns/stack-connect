import SwiftUI
import StoreKit

struct PaywallView: View {

    @EnvironmentObject private var subscriptionService: SubscriptionService

    @State private var selectedPlan: SubscriptionTier = .individual
    @State private var billingPeriod: BillingPeriod = .yearly
    @State private var isPurchasing = false

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 24) {
                    buildHeader()
                    buildPlanCarousel()
                    if selectedPlan != .lifetime {
                        buildBillingToggle()
                    }
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
    }

    // MARK: - Header

    private func buildHeader() -> some View {
        VStack(spacing: 8) {
            Image(systemName: "app.connected.to.app.below.fill")
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
            } else {
                buildFeatureRow(icon: "checkmark.circle.fill", color: .green, text: String(localized: "Export & import accounts included"))
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
        VStack(spacing: 12) {
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

            Button {
                Task {
                    await subscriptionService.restorePurchases()
                }
            } label: {
                Text(String(localized: "Restore Purchases"))
                    .font(.subheadline)
                    .foregroundStyle(.accent)
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
}
