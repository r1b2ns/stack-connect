import XCTest
@testable import StackConnect

final class NetworkAuditExporterTests: XCTestCase {

    private let sut = NetworkAuditExporter(appVersion: "2.4.0", timeZone: TimeZone(identifier: "UTC")!)
    private let token = NetworkAuditFixtures.ascJWT(expiresAt: NetworkAuditFixtures.now.addingTimeInterval(600))

    private var event: NetworkAuditEvent {
        NetworkAuditFixtures.event(NetworkAuditFixtures.exchange(
            authorization: "Bearer \(token)",
            requestHeaders: [.init(name: "User-Agent", value: "StackConnect/2.4.0"), .init(name: "Cookie", value: "myacinfo=SESSION")]
        ))
    }

    private var postEvent: NetworkAuditEvent {
        NetworkAuditFixtures.event(NetworkAuditFixtures.exchange(
            url: "https://api.appstoreconnect.apple.com/v1/users/7f3c",
            method: "PATCH",
            authorization: "Bearer \(token)",
            requestHeaders: [.init(name: "Content-Type", value: "application/json")],
            requestBody: Data(#"{"data":{"type":"users","attributes":{"note":"it's"}}}"#.utf8),
            status: 409
        ))
    }

    private var localEvent: NetworkAuditEvent {
        let recorder = NetworkAuditRecorder(store: MockNetworkAuditStore(), settings: MockNetworkAuditSettings(),
                                            vault: NetworkAuditSecretVault(keychain: MockKeyStorable()), now: { NetworkAuditFixtures.now })
        return recorder.makeExportEvent(NetworkAuditExportRecord(formatName: "cURL", subject: "GET /v1/apps", action: .copied, includesRealToken: false, byteCount: 1))
    }

    private func assertNoSecrets(_ output: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertFalse(output.contains(token), "real token leaked", file: file, line: line)
        XCTAssertFalse(output.contains("SESSION"), "cookie leaked", file: file, line: line)
    }

    // MARK: - JSON

    func testBatchJSONIsMaskedAndHonorsBodies() throws {
        let output = sut.batch([event], format: .json, includeBodies: true)

        assertNoSecrets(output)
        let array = try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(output.utf8)) as? [[String: Any]])
        XCTAssertEqual(array.count, 1)
        let first = array[0]
        XCTAssertEqual(first["method"] as? String, "GET")
        XCTAssertEqual(first["status"] as? Int, 200)
        XCTAssertEqual(first["time"] as? String, "2026-11-24T14:32:08.000Z")
        XCTAssertEqual((first["requestHeaders"] as? [String: String])?["Authorization"], "Bearer [MASKED]")
        XCTAssertNotNil(first["responseBody"])

        let withoutBodies = sut.batch([event], format: .json, includeBodies: false)
        XCTAssertFalse(withoutBodies.contains("responseBody"))
    }

    func testSingleJSONIsAnObject() throws {
        let output = sut.single(event, format: .json, includeBody: false)

        let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(output.utf8)) as? [String: Any])
        XCTAssertEqual(object["durationMs"] as? Int, 412)
        XCTAssertNil(object["responseBody"])
    }

    // MARK: - HAR

    func testHARIsVersion12AndSkipsLocalEvents() throws {
        let output = sut.batch([event, localEvent], format: .har, includeBodies: true)

        assertNoSecrets(output)
        let root = try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(output.utf8)) as? [String: Any])
        let log = try XCTUnwrap(root["log"] as? [String: Any])
        XCTAssertEqual(log["version"] as? String, "1.2")
        XCTAssertEqual((log["creator"] as? [String: Any])?["name"] as? String, "StackConnect")
        let entries = try XCTUnwrap(log["entries"] as? [[String: Any]])
        XCTAssertEqual(entries.count, 1)
        let request = try XCTUnwrap(entries[0]["request"] as? [String: Any])
        XCTAssertEqual(request["httpVersion"] as? String, "HTTP/2")
        let query = try XCTUnwrap(request["queryString"] as? [[String: String]])
        XCTAssertEqual(query.first?["name"], "limit")
        let response = try XCTUnwrap(entries[0]["response"] as? [String: Any])
        XCTAssertEqual(response["statusText"] as? String, "OK")
        XCTAssertNotNil((response["content"] as? [String: Any])?["text"])
    }

    func testHARWithoutBodiesHasNoContentText() throws {
        let output = sut.single(postEvent, format: .har, includeBody: false)

        XCTAssertFalse(output.contains("postData"))
        XCTAssertFalse(output.contains("\"text\""))
    }

    // MARK: - CSV

    func testCSVHasOneLinePerEventAndEscapes() {
        let tricky = NetworkAuditFixtures.event(NetworkAuditFixtures.exchange(url: "https://example.com/a,b"))

        let output = sut.batch([event, tricky, localEvent], format: .csv, includeBodies: true)
        let lines = output.split(separator: "\n").map(String.init)

        XCTAssertEqual(lines.first, NetworkAuditExporter.csvHeader)
        XCTAssertEqual(lines.count, 4)
        XCTAssertEqual(lines[1], "2026-11-24T14:32:08.000Z,outbound,GET,api.appstoreconnect.apple.com,/v1/apps?limit=200&include=appStoreVersions,200,0,35,apple")
        XCTAssertTrue(lines[2].contains("\"/a,b\""))
        XCTAssertTrue(lines[3].hasSuffix(",local"))
        assertNoSecrets(output)
    }

    func testCSVFieldEscaping() {
        XCTAssertEqual(NetworkAuditExporter.csvField("plain"), "plain")
        XCTAssertEqual(NetworkAuditExporter.csvField("a,b"), "\"a,b\"")
        XCTAssertEqual(NetworkAuditExporter.csvField("say \"hi\""), "\"say \"\"hi\"\"\"")
    }

    // MARK: - cURL

    func testCurlIsMaskedByDefault() {
        let output = sut.single(event, format: .curl, includeBody: true)

        assertNoSecrets(output)
        XCTAssertTrue(output.hasPrefix("curl 'https://api.appstoreconnect.apple.com/v1/apps?limit=200&include=appStoreVersions'"))
        XCTAssertTrue(output.contains("-H 'Authorization: Bearer [MASKED]'"), output)
        XCTAssertTrue(output.contains("-H 'Cookie: myacinfo=[MASKED]'"))
        XCTAssertFalse(output.contains("-X GET"))
    }

    func testCurlCarriesOnlyTheGivenRealAuthorization() {
        let output = sut.curl(event, includeBody: true, realAuthorization: "Bearer \(token)")

        XCTAssertTrue(output.contains("-H 'Authorization: Bearer \(token)'"))
        // Cookies stay masked even in a cURL with a token.
        XCTAssertFalse(output.contains("SESSION"))
    }

    func testCurlWithBodyAndMethod() {
        let output = sut.single(postEvent, format: .curl, includeBody: true)

        XCTAssertTrue(output.contains("-X PATCH"))
        XCTAssertTrue(output.contains("--data-raw '"))
        // The apostrophe of "it's" is shell-escaped.
        XCTAssertTrue(output.contains("it'\\''s"))

        let withoutBody = sut.single(postEvent, format: .curl, includeBody: false)
        XCTAssertFalse(withoutBody.contains("--data-raw"))
    }

    func testShellQuoting() {
        XCTAssertEqual(NetworkAuditExporter.shellQuoted("a'b"), "'a'\\''b'")
    }

    // MARK: - Text

    func testTextSummary() {
        let output = sut.single(postEvent, format: .text, includeBody: true)
        let lines = output.components(separatedBy: "\n")

        XCTAssertEqual(lines.first, "PATCH https://api.appstoreconnect.apple.com/v1/users/7f3c")
        XCTAssertEqual(lines[1], String(localized: "Status: \("409 Conflict · 412 ms")"))
        XCTAssertTrue(output.contains("Authorization: Bearer [MASKED]"))
        XCTAssertTrue(output.contains(String(localized: "Request:")))
        assertNoSecrets(output)

        XCTAssertFalse(sut.single(postEvent, format: .text, includeBody: false).contains(String(localized: "Request:")))
    }

    func testStatusTitles() {
        XCTAssertEqual(NetworkAuditStatus.title(for: event), "200 OK")
        XCTAssertEqual(NetworkAuditStatus.title(for: postEvent.summary), "409 Conflict")
        XCTAssertEqual(NetworkAuditStatus.title(for: event.summary), "200")
        XCTAssertEqual(NetworkAuditStatus.title(for: localEvent), String(localized: "Copied"))
    }
}
