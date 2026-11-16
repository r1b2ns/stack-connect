import XCTest
import StackProtocols
@testable import StackConnect

@MainActor
final class ManageLocalizationsViewModelTests: XCTestCase {

    private func makeSUT(_ analytics: MockAnalyticsTracker) -> ManageLocalizationsViewModel {
        ManageLocalizationsViewModel(
            appInfoId: "info-1",
            primaryLocale: "en-US",
            account: AccountModel(name: "Team", providerType: .apple),
            keychain: MockKeyStorable(),
            analytics: analytics
        )
    }

    func testLocalizationActionsTrackTapAndFailureWithoutCredentials() async {
        let analytics = MockAnalyticsTracker()
        let sut = makeSUT(analytics)
        let localization = AppInfoLocalizationModel(id: "loc-1", locale: "pt-BR", name: "Nome")

        await sut.update(localization: localization)
        await sut.delete(localization: localization)
        await sut.addLocalization(locale: "fr-FR", name: "Nom", subtitle: nil)

        XCTAssertEqual(analytics.trackedEvents, [
            .buttonTap(.save, on: .editLocalization),
            .action(.updateLocalization, on: .editLocalization, result: .failure),
            .buttonTap(.delete, on: .manageLocalizations),
            .action(.deleteLocalization, on: .manageLocalizations, result: .failure),
            .buttonTap(.add, on: .addLocalization),
            .action(.createLocalization, on: .addLocalization, result: .failure)
        ])
    }
}
