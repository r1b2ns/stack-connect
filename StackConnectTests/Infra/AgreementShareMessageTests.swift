import XCTest
@testable import StackConnect

/// Assertions avoid full-sentence comparisons so they hold in any simulator
/// language: they check the dynamic parts (name, team, link) and the variant.
final class AgreementShareMessageTests: XCTestCase {

    private let teamName = "Acme Team"
    private let link = AppStoreConnectLinks.agreements.absoluteString

    private func makeUser(firstName: String?, lastName: String?, email: String?) -> UserModel {
        UserModel(
            id: "holder",
            firstName: firstName,
            lastName: lastName,
            email: email,
            roles: [UserRoleCatalog.accountHolder],
            allAppsVisible: true,
            provisioningAllowed: false,
            isPending: false,
            expirationDate: nil
        )
    }

    private var genericText: String {
        AgreementShareMessage.make(teamName: teamName, accountHolderName: nil, accountHolderEmail: nil).text
    }

    // MARK: - Named Account Holder

    func testNamedAccountHolderMessageContainsNameTeamAndLink() {
        let message = AgreementShareMessage.make(
            teamName: teamName,
            accountHolderName: "Jane Appleseed",
            accountHolderEmail: "jane@example.com"
        )

        XCTAssertTrue(message.text.contains("Jane Appleseed"))
        XCTAssertTrue(message.text.contains(teamName))
        XCTAssertTrue(message.text.hasSuffix(link), "The agreements link must close the message")
        XCTAssertFalse(message.text.contains("jane@example.com"), "The recipient's email must not be in the body")
        XCTAssertNotEqual(message.text, genericText)
        XCTAssertEqual(message.recipientTitle, "Jane Appleseed <jane@example.com>")
        XCTAssertFalse(message.subject.isEmpty)
        XCTAssertEqual(message.url, AppStoreConnectLinks.agreements)
    }

    func testNameIsTrimmed() {
        let message = AgreementShareMessage.make(
            teamName: teamName,
            accountHolderName: "  Jane Appleseed \n",
            accountHolderEmail: " jane@example.com "
        )

        XCTAssertEqual(message.recipientTitle, "Jane Appleseed <jane@example.com>")
        XCTAssertFalse(message.text.contains("  Jane"))
    }

    func testNameWithoutEmailUsesNameAsRecipientTitle() {
        let message = AgreementShareMessage.make(teamName: teamName, accountHolderName: "Jane Appleseed", accountHolderEmail: nil)

        XCTAssertEqual(message.recipientTitle, "Jane Appleseed")
        XCTAssertTrue(message.text.contains("Jane Appleseed"))
    }

    // MARK: - Fallbacks

    func testGenericMessageHasNoNameButKeepsTeamAndLink() {
        let message = AgreementShareMessage.make(teamName: teamName, accountHolderName: nil, accountHolderEmail: nil)

        XCTAssertTrue(message.text.contains(teamName))
        XCTAssertTrue(message.text.hasSuffix(link))
        XCTAssertTrue(message.recipientTitle.contains(teamName), "Generic title should still point at the team's Account Holder")
        XCTAssertFalse(message.recipientTitle.contains("<"))
        XCTAssertFalse(message.subject.isEmpty)
    }

    func testBlankNameFallsBackToGenericGreeting() {
        let message = AgreementShareMessage.make(teamName: teamName, accountHolderName: "   ", accountHolderEmail: "")

        XCTAssertEqual(message.text, genericText)
        XCTAssertEqual(
            message.recipientTitle,
            AgreementShareMessage.make(teamName: teamName, accountHolderName: nil, accountHolderEmail: nil).recipientTitle
        )
    }

    func testEmailOnlyKeepsGenericGreetingAndShowsEmailInTitle() {
        let message = AgreementShareMessage.make(teamName: teamName, accountHolderName: nil, accountHolderEmail: "jane@example.com")

        XCTAssertEqual(message.text, genericText, "Without a real name the greeting stays generic")
        XCTAssertFalse(message.text.contains("jane@example.com"))
        XCTAssertTrue(message.recipientTitle.hasSuffix("<jane@example.com>"))
    }

    func testSubjectIsTheSameForBothVariants() {
        let named = AgreementShareMessage.make(teamName: teamName, accountHolderName: "Jane", accountHolderEmail: nil)
        let generic = AgreementShareMessage.make(teamName: teamName, accountHolderName: nil, accountHolderEmail: nil)

        XCTAssertEqual(named.subject, generic.subject)
    }

    // MARK: - UserModel overload

    func testUserOverloadUsesFirstAndLastName() {
        let user = makeUser(firstName: "Jane", lastName: "Appleseed", email: "jane@example.com")

        let message = AgreementShareMessage.make(teamName: teamName, accountHolder: user)

        XCTAssertEqual(
            message,
            AgreementShareMessage.make(teamName: teamName, accountHolderName: "Jane Appleseed", accountHolderEmail: "jane@example.com")
        )
    }

    func testUserOverloadWithOnlyFirstName() {
        let user = makeUser(firstName: "Jane", lastName: nil, email: "jane@example.com")

        let message = AgreementShareMessage.make(teamName: teamName, accountHolder: user)

        XCTAssertEqual(message.recipientTitle, "Jane <jane@example.com>")
    }

    func testUserOverloadNeverGreetsWithTheEmail() {
        // `UserModel.displayName` falls back to the email — the builder must not.
        let user = makeUser(firstName: nil, lastName: nil, email: "jane@example.com")

        let message = AgreementShareMessage.make(teamName: teamName, accountHolder: user)

        XCTAssertEqual(message.text, genericText)
        XCTAssertFalse(message.text.contains("jane@example.com"))
        XCTAssertTrue(message.recipientTitle.hasSuffix("<jane@example.com>"))
    }

    func testNilUserProducesGenericMessage() {
        XCTAssertEqual(
            AgreementShareMessage.make(teamName: teamName, accountHolder: nil),
            AgreementShareMessage.make(teamName: teamName, accountHolderName: nil, accountHolderEmail: nil)
        )
    }

    // MARK: - Link

    func testCustomURLIsAppended() throws {
        let url = try XCTUnwrap(URL(string: "https://example.com/agreements"))

        let message = AgreementShareMessage.make(teamName: teamName, accountHolderName: nil, accountHolderEmail: nil, url: url)

        XCTAssertTrue(message.text.hasSuffix(url.absoluteString))
        XCTAssertEqual(message.url, url)
    }

    func testSharedAgreementsLinkPointsToAppStoreConnect() {
        XCTAssertEqual(AppStoreConnectLinks.agreements.absoluteString, "https://appstoreconnect.apple.com/agreements/")
    }
}
