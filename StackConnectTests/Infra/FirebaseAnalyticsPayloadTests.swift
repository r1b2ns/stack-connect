import XCTest
import StackProtocols
@testable import StackConnect

/// Mapping and Firebase-limit enforcement, tested without a configured
/// `FirebaseApp` (the payload type has no Firebase dependency).
final class FirebaseAnalyticsPayloadTests: XCTestCase {

    // MARK: - Mapping

    func testScreenViewMapsToFirebaseScreenViewNames() throws {
        let payload = try XCTUnwrap(FirebaseAnalyticsPayload.make(from: .screenView(.settings)))

        // `AnalyticsEventScreenView` / `AnalyticsParameterScreenName`.
        XCTAssertEqual(payload.name, "screen_view")
        XCTAssertEqual(payload.parameters["screen_name"], "settings" as NSString)
    }

    func testOtherEventsPassThroughAsIs() throws {
        let payload = try XCTUnwrap(FirebaseAnalyticsPayload.make(from: .buttonTap(.license, on: .settings)))

        XCTAssertEqual(payload.name, "button_tap")
        XCTAssertEqual(payload.parameters, [
            "button_name": "license" as NSString,
            "screen_name": "settings" as NSString
        ])
    }

    func testValueConversion() throws {
        let event = AnalyticsEvent(name: "action", parameters: [
            "text": .string("value"),
            "count": .int(3),
            "ratio": .double(0.5),
            "enabled": .bool(true),
            "scoped": .bool(false)
        ])

        let payload = try XCTUnwrap(FirebaseAnalyticsPayload.make(from: event))

        XCTAssertEqual(payload.parameters["text"], "value" as NSString)
        XCTAssertEqual(payload.parameters["count"], NSNumber(value: Int64(3)))
        XCTAssertEqual(payload.parameters["ratio"], NSNumber(value: 0.5))
        XCTAssertEqual(payload.parameters["enabled"], "true" as NSString)
        XCTAssertEqual(payload.parameters["scoped"], "false" as NSString)
        XCTAssertTrue(payload.parameters["count"] is NSNumber)
        XCTAssertTrue(payload.parameters["text"] is NSString)
    }

    func testEventWithoutParametersHasEmptyPayloadParameters() throws {
        let payload = try XCTUnwrap(FirebaseAnalyticsPayload.make(from: AnalyticsEvent(name: "analytics_enabled")))

        XCTAssertEqual(payload.name, "analytics_enabled")
        XCTAssertTrue(payload.parameters.isEmpty)
    }

    func testEveryAppEventNameIsAcceptedUnchanged() {
        let names = ["screen_view", "button_tap", "action", "analytics_disabled", "analytics_enabled"]
        for name in names {
            XCTAssertEqual(FirebaseAnalyticsPayload.make(from: AnalyticsEvent(name: name))?.name, name)
        }
    }

    // MARK: - Event name limits

    func testLongEventNameIsTruncatedTo40() throws {
        let long = "e" + String(repeating: "x", count: 59)

        let payload = try XCTUnwrap(FirebaseAnalyticsPayload.make(from: AnalyticsEvent(name: long)))

        XCTAssertEqual(payload.name.count, 40)
        XCTAssertTrue(long.hasPrefix(payload.name))
    }

    func testReservedPrefixEventsAreDropped() {
        for name in ["firebase_custom", "google_thing", "ga_event", "Firebase_upper"] {
            XCTAssertNil(FirebaseAnalyticsPayload.make(from: AnalyticsEvent(name: name)), name)
        }
    }

    func testReservedEventNamesAreDropped() {
        for name in ["first_open", "session_start", "app_remove", "user_engagement", "error"] {
            XCTAssertNil(FirebaseAnalyticsPayload.make(from: AnalyticsEvent(name: name)), name)
        }
    }

    func testInvalidEventNamesAreDropped() {
        for name in ["", "1starts_with_digit", "_underscore", "has space", "has-dash", "acentuação"] {
            XCTAssertNil(FirebaseAnalyticsPayload.make(from: AnalyticsEvent(name: name)), name)
        }
    }

    // MARK: - Parameter limits

    func testLongParameterNameIsTruncatedTo40() throws {
        let long = "p" + String(repeating: "a", count: 49)

        let payload = try XCTUnwrap(FirebaseAnalyticsPayload.make(from: AnalyticsEvent(name: "action", parameters: [long: .int(1)])))

        XCTAssertEqual(Array(payload.parameters.keys), [String(long.prefix(40))])
    }

    func testParametersWithReservedPrefixOrInvalidNameAreDroppedButEventIsKept() throws {
        let event = AnalyticsEvent(name: "action", parameters: [
            "firebase_screen": .string("x"),
            "google_id": .string("x"),
            "ga_session": .string("x"),
            "bad key": .string("x"),
            "9lives": .string("x"),
            "kept": .string("ok")
        ])

        let payload = try XCTUnwrap(FirebaseAnalyticsPayload.make(from: event))

        XCTAssertEqual(payload.parameters, ["kept": "ok" as NSString])
    }

    func testLongStringValueIsTruncatedTo100() throws {
        let long = String(repeating: "v", count: 150)

        let payload = try XCTUnwrap(FirebaseAnalyticsPayload.make(from: AnalyticsEvent(name: "action", parameters: ["kind": .string(long)])))

        XCTAssertEqual((payload.parameters["kind"] as? String)?.count, 100)
    }

    func testStringValueAtTheLimitIsKeptIntact() throws {
        let exact = String(repeating: "v", count: 100)

        let payload = try XCTUnwrap(FirebaseAnalyticsPayload.make(from: AnalyticsEvent(name: "action", parameters: ["kind": .string(exact)])))

        XCTAssertEqual(payload.parameters["kind"], exact as NSString)
    }

    func testNonFiniteDoublesAreDropped() throws {
        let event = AnalyticsEvent(name: "action", parameters: [
            "nan": .double(.nan),
            "inf": .double(.infinity),
            "ok": .double(1.5)
        ])

        let payload = try XCTUnwrap(FirebaseAnalyticsPayload.make(from: event))

        XCTAssertEqual(payload.parameters, ["ok": NSNumber(value: 1.5)])
    }

    func testAtMost25ParametersAreKeptDeterministically() throws {
        var parameters: [String: AnalyticsValue] = [:]
        for index in 0..<30 {
            parameters[String(format: "p%02d", index)] = .int(index)
        }

        let payload = try XCTUnwrap(FirebaseAnalyticsPayload.make(from: AnalyticsEvent(name: "action", parameters: parameters)))

        XCTAssertEqual(payload.parameters.count, 25)
        XCTAssertEqual(Set(payload.parameters.keys), Set((0..<25).map { String(format: "p%02d", $0) }))
    }

    func testKeysCollidingAfterTruncationKeepTheFirstSortedOne() throws {
        let base = "k" + String(repeating: "a", count: 39) // exactly 40
        let event = AnalyticsEvent(name: "action", parameters: [
            base + "1": .int(1),
            base + "2": .int(2)
        ])

        let payload = try XCTUnwrap(FirebaseAnalyticsPayload.make(from: event))

        XCTAssertEqual(payload.parameters, [base: NSNumber(value: Int64(1))])
    }

    func testStandardParametersSurviveARealEnrichedEvent() throws {
        let event = AnalyticsEvent(name: "action", parameters: [
            "action_name": .string("delete_all_accounts"),
            "screen_name": .string("settings"),
            "result": .string("success"),
            "count": .int(2),
            "app_version": .string("1.0"),
            "build_number": .string("1"),
            "platform": .string("ios"),
            "os_version": .string("26.0.0")
        ])

        let payload = try XCTUnwrap(FirebaseAnalyticsPayload.make(from: event))

        XCTAssertEqual(payload.parameters.count, 8)
    }

    // MARK: - User properties

    func testEveryAppUserPropertyFitsFirebaseLimits() throws {
        for property in AnalyticsUserProperty.allCases {
            let mapped = try XCTUnwrap(FirebaseAnalyticsPayload.userProperty(name: property.rawValue, value: "3+"))
            XCTAssertEqual(mapped, .init(name: property.rawValue, value: "3+"), "\(property) must pass unchanged")
        }
    }

    func testUserPropertyNameIsTruncatedTo24Characters() throws {
        let mapped = try XCTUnwrap(FirebaseAnalyticsPayload.userProperty(name: String(repeating: "a", count: 30), value: "x"))

        XCTAssertEqual(mapped.name, String(repeating: "a", count: 24))
    }

    func testUserPropertyValueIsTruncatedTo36Characters() throws {
        let mapped = try XCTUnwrap(FirebaseAnalyticsPayload.userProperty(name: "segment", value: String(repeating: "v", count: 50)))

        XCTAssertEqual(mapped.value, String(repeating: "v", count: 36))
    }

    func testNilUserPropertyValueClearsIt() throws {
        let mapped = try XCTUnwrap(FirebaseAnalyticsPayload.userProperty(name: "segment", value: nil))

        XCTAssertNil(mapped.value)
    }

    func testReservedOrInvalidUserPropertyNamesAreDropped() {
        for name in ["firebase_x", "google_x", "ga_x", "Firebase_x", "user_id", "first_open_time", "1abc", "has-dash", "", "émoji"] {
            XCTAssertNil(FirebaseAnalyticsPayload.userProperty(name: name, value: "x"), name)
        }
    }
}
