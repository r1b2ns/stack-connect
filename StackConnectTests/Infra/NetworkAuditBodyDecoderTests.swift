import XCTest
import StackProtocols
@testable import StackConnect

final class NetworkAuditBodyDecoderTests: XCTestCase {

    // MARK: - Fixtures

    /// Raw deflate (RFC 1951): what `NSData.compressed(using: .zlib)` produces.
    private func rawDeflate(_ data: Data) throws -> Data {
        try (data as NSData).compressed(using: .zlib) as Data
    }

    private func gzip(_ data: Data) throws -> Data {
        var out = Data([0x1F, 0x8B, 0x08, 0x00, 0, 0, 0, 0, 0x00, 0x03])
        out.append(try rawDeflate(data))
        out.append(contentsOf: [0, 0, 0, 0]) // CRC32 (not checked)
        let size = UInt32(truncatingIfNeeded: data.count)
        out.append(contentsOf: [UInt8(size & 0xFF), UInt8((size >> 8) & 0xFF), UInt8((size >> 16) & 0xFF), UInt8(size >> 24)])
        return out
    }

    private func zlib(_ data: Data) throws -> Data {
        var out = Data([0x78, 0x9C])
        out.append(try rawDeflate(data))
        out.append(contentsOf: [0, 0, 0, 0]) // Adler-32 (not checked)
        return out
    }

    private let json = Data(#"{"appInstanceId":"FID123","appInstanceIdToken":"INSTANCETOKENSECRET","appId":"1:123456789012:ios:abcdef0123456789","sdkVersion":"11.0.0"}"#.utf8)

    private var identity: NetworkAuditAppIdentity {
        NetworkAuditAppIdentity(
            bundleIds: ["zeroSixteen.stackconnect"],
            firebaseValues: ["stack-connect-88e17", "1:123456789012:ios:abcdef0123456789", "AIzaSyD1234567890abcdefghijklmnopqrstuv"],
            oauthClientIds: []
        )
    }

    private var recorder: NetworkAuditRecorder {
        NetworkAuditRecorder(store: MockNetworkAuditStore(), settings: MockNetworkAuditSettings(),
                             vault: NetworkAuditSecretVault(keychain: MockKeyStorable()), appIdentity: identity,
                             now: { NetworkAuditFixtures.now })
    }

    // MARK: - Decompression

    func testGzipDeflateAndRawDeflateDecode() throws {
        for (encoding, encoded) in [
            (NetworkAuditBodyDecoder.Encoding.gzip, try gzip(json)),
            (.deflate, try zlib(json)),
            (.deflate, try rawDeflate(json))
        ] {
            XCTAssertEqual(NetworkAuditBodyDecoder.decode(encoded, encoding: encoding, maxOutputBytes: 1_000_000), .decoded(json, isTruncated: false))
        }
    }

    func testEncodingHeaderParsing() {
        XCTAssertEqual(NetworkAuditBodyDecoder.Encoding(header: "gzip"), .gzip)
        XCTAssertEqual(NetworkAuditBodyDecoder.Encoding(header: "X-GZIP"), .gzip)
        XCTAssertEqual(NetworkAuditBodyDecoder.Encoding(header: "deflate"), .deflate)
        XCTAssertEqual(NetworkAuditBodyDecoder.Encoding(header: "br"), .brotli)
        XCTAssertNil(NetworkAuditBodyDecoder.Encoding(header: "identity"))
        XCTAssertNil(NetworkAuditBodyDecoder.Encoding(header: nil))
    }

    func testOutputCapStopsADecompressionBomb() throws {
        let bomb = try gzip(Data(count: 20 * 1024 * 1024)) // 20 MB of zeros, ~20 KB compressed
        XCTAssertLessThan(bomb.count, 100_000)

        guard case let .decoded(output, isTruncated) = NetworkAuditBodyDecoder.decode(bomb, encoding: .gzip, maxOutputBytes: 1_000_000) else {
            return XCTFail("expected a truncated decode")
        }
        XCTAssertTrue(isTruncated)
        XCTAssertEqual(output.count, 1_000_000)
    }

    func testCorruptAndUnsupportedBodies() {
        var corrupt = Data([0x1F, 0x8B, 0x08, 0x00, 0, 0, 0, 0, 0x00, 0x03])
        corrupt.append(Data(repeating: 0xFF, count: 32))
        XCTAssertEqual(NetworkAuditBodyDecoder.decode(corrupt, encoding: .gzip, maxOutputBytes: 1_000), .failed)
        XCTAssertEqual(NetworkAuditBodyDecoder.decode(json, encoding: .brotli, maxOutputBytes: 1_000), .unsupported("br"))
        // Already decoded by URLSession (a response): passed through.
        XCTAssertEqual(NetworkAuditBodyDecoder.decode(json, encoding: .gzip, maxOutputBytes: 1_000), .passthrough)
        XCTAssertEqual(NetworkAuditBodyDecoder.decode(json, encoding: .deflate, maxOutputBytes: 1_000, allowsRawDeflate: false), .passthrough)
    }

    // MARK: - Recorder

    private func exchange(body: Data, encoding: String?, url: String = "https://firebaseremoteconfig.googleapis.com/v1/projects/stack-connect-88e17/namespaces/firebase:fetch", source: NetworkAuditExchange.Source = .urlSession, contentType: String = "application/json") -> NetworkAuditExchange {
        var headers: [NetworkAuditExchange.HeaderField] = [.init(name: "Content-Type", value: contentType)]
        if let encoding {
            headers.append(.init(name: "Content-Encoding", value: encoding))
        }
        var exchange = NetworkAuditFixtures.exchange(url: url, method: "POST", requestHeaders: headers, requestBody: body)
        exchange.source = source
        return exchange
    }

    func testDecompressedTelemetryBodyIsMaskedLikeAnyBody() throws {
        let compressed = try gzip(json)
        let event = recorder.makeEvent(from: exchange(body: compressed, encoding: "gzip"))

        let body = event.requestBody
        let text = try XCTUnwrap(body.text)
        XCTAssertEqual(body.encoding, "gzip")
        XCTAssertEqual(body.byteCount, Int64(compressed.count))
        XCTAssertEqual(body.decodedByteCount, Int64(json.count))
        XCTAssertEqual(body.format, .json)
        XCTAssertTrue(body.isDecoded)
        XCTAssertFalse(text.contains("INSTANCETOKENSECRET"))
        XCTAssertTrue(text.contains("\"appId\" : \"[APP]\""))
        XCTAssertTrue(text.contains("\"appInstanceId\" : \"FID123\""))
        XCTAssertTrue(text.contains("\"sdkVersion\" : \"11.0.0\""))
        XCTAssertTrue(text.contains("\n"), "pretty printed")
    }

    func testFailureFallsBackToBinary() {
        var corrupt = Data([0x1F, 0x8B, 0x08, 0x00, 0, 0, 0, 0, 0x00, 0x03])
        corrupt.append(Data(repeating: 0xFF, count: 32))

        let failed = recorder.makeEvent(from: exchange(body: corrupt, encoding: "gzip")).requestBody
        let brotli = recorder.makeEvent(from: exchange(body: Data([0x8B, 0x02, 0x80, 0xFF]), encoding: "br")).requestBody

        XCTAssertEqual(failed.content, .binary)
        XCTAssertEqual(failed.encoding, "gzip")
        XCTAssertNil(failed.decodedByteCount)
        XCTAssertEqual(brotli.content, .binary)
        XCTAssertEqual(brotli.encoding, "br")
    }

    func testAlreadyDecodedResponseStaysText() {
        var plain = exchange(body: Data(), encoding: nil)
        plain.responseHeaders = [.init(name: "Content-Type", value: "application/json"), .init(name: "Content-Encoding", value: "gzip")]
        plain.responseBody = Data(#"{"state":"UPDATE"}"#.utf8)
        plain.responseBodyLength = Int64(plain.responseBody?.count ?? 0)

        let body = recorder.makeEvent(from: plain).responseBody

        XCTAssertEqual(body.format, .json)
        XCTAssertNil(body.encoding)
        XCTAssertTrue(body.text?.contains("UPDATE") ?? false)
    }

    func testCoreBodiesAreLeftAlone() throws {
        let compressed = try gzip(json)
        let body = recorder.makeEvent(from: exchange(body: compressed, encoding: "gzip", source: .rustCore)).requestBody

        XCTAssertNil(body.encoding)
        XCTAssertNil(body.decodedByteCount)
    }

    func testTruncatedDecodeIsFlagged() throws {
        let big = Data(String(repeating: "a", count: NetworkAuditRecorder.maxMaskableBodyBytes + 100).utf8)
        let body = recorder.makeEvent(from: exchange(body: try gzip(big), encoding: "gzip", contentType: "text/plain")).requestBody

        XCTAssertTrue(body.isTruncated)
        XCTAssertEqual(body.decodedByteCount, Int64(NetworkAuditRecorder.maxMaskableBodyBytes))
    }

    // MARK: - Protobuf

    /// 1: 150, 2: "screen_view", 3 { 1: "x", 2: 5 }, 4: fixed32, 5: fixed64, 6: <bytes>
    private var protobuf: Data {
        var data = Data([0x08, 0x96, 0x01])
        data.append(contentsOf: [0x12, 0x0B]); data.append(Data("screen_view".utf8))
        data.append(contentsOf: [0x1A, 0x05, 0x0A, 0x01, 0x78, 0x10, 0x05])
        data.append(contentsOf: [0x25, 0x01, 0x00, 0x00, 0x00])
        data.append(contentsOf: [0x29, 0x02, 0, 0, 0, 0, 0, 0, 0])
        data.append(contentsOf: [0x32, 0x03, 0xFF, 0xFE, 0x00])
        return data
    }

    func testProtobufDecodesNestedFields() throws {
        let fields = try XCTUnwrap(NetworkAuditProtobufDecoder.decode(protobuf))

        XCTAssertEqual(fields.map(\.number), [1, 2, 3, 4, 5, 6])
        XCTAssertEqual(fields[0].value, .varint(150))
        XCTAssertEqual(fields[1].value, .string("screen_view"))
        XCTAssertEqual(fields[2].value, .message([.init(number: 1, value: .string("x")), .init(number: 2, value: .varint(5))]))
        XCTAssertEqual(fields[3].value, .fixed32(1))
        XCTAssertEqual(fields[4].value, .fixed64(2))
        XCTAssertEqual(fields[5].value, .bytes(3))

        let rendered = NetworkAuditProtobufDecoder.render(fields)
        XCTAssertTrue(rendered.contains("1: 150"))
        XCTAssertTrue(rendered.contains("2: \"screen_view\""))
        XCTAssertTrue(rendered.contains("3 {\n  1: \"x\"\n  2: 5\n}"))
        XCTAssertTrue(rendered.contains("6: <3 bytes>"), "raw bytes are never printed")
    }

    func testMalformedProtobufIsRejected() {
        XCTAssertNil(NetworkAuditProtobufDecoder.decode(Data([0x12, 0x10, 0x41])), "length past the end")
        XCTAssertNil(NetworkAuditProtobufDecoder.decode(Data([0x0B, 0x01])), "group wire type")
        XCTAssertNil(NetworkAuditProtobufDecoder.decode(Data([0x08])), "varint cut short")
        XCTAssertNil(NetworkAuditProtobufDecoder.decode(Data([0x00, 0x01])), "field number 0")
        XCTAssertNil(NetworkAuditProtobufDecoder.decode(Data()))
    }

    func testCompressedProtobufBecomesAMaskedTree() throws {
        var message = Data([0x08, 0x01])
        let strings = ["zeroSixteen.stackconnect", "AIzaSyD1234567890abcdefghijklmnopqrstuv", "screen_view"]
        for (index, string) in strings.enumerated() {
            message.append(UInt8(((index + 2) << 3) | 2))
            message.append(UInt8(string.utf8.count))
            message.append(Data(string.utf8))
        }
        let event = recorder.makeEvent(from: exchange(body: try gzip(message), encoding: "gzip", url: "https://app-analytics-services.com/a", contentType: "application/x-www-form-urlencoded"))

        let body = event.requestBody
        let text = try XCTUnwrap(body.text)
        XCTAssertEqual(body.format, .protobuf)
        XCTAssertTrue(text.contains("\"screen_view\""))
        XCTAssertFalse(text.contains("zeroSixteen.stackconnect"))
        XCTAssertFalse(text.contains("AIzaSyD"))
        XCTAssertTrue(text.contains("[APP]"))
    }

    func testUndecodableBinaryAfterDecompressionKeepsItsSize() throws {
        let binary = Data([0x0B, 0xFF, 0x00, 0x13])
        let body = recorder.makeEvent(from: exchange(body: try gzip(binary), encoding: "gzip", contentType: "application/octet-stream")).requestBody

        XCTAssertEqual(body.content, .binary)
        XCTAssertEqual(body.decodedByteCount, 4)
    }

    // MARK: - Export

    func testCurlOfADecompressedBodyDropsContentEncoding() throws {
        let event = recorder.makeEvent(from: exchange(body: try gzip(json), encoding: "gzip"))
        let exporter = NetworkAuditExporter(appVersion: "2.4.0", timeZone: TimeZone(identifier: "UTC")!)

        let withBody = exporter.curl(event, includeBody: true)
        XCTAssertTrue(withBody.hasPrefix("# The body was sent gzip-compressed"))
        XCTAssertFalse(withBody.contains("-H 'Content-Encoding"), "the header would lie about the body")
        XCTAssertTrue(withBody.contains("--data-raw"))
        XCTAssertTrue(withBody.contains("sdkVersion"))
        XCTAssertFalse(withBody.contains("INSTANCETOKENSECRET"))

        let withoutBody = exporter.curl(event, includeBody: false)
        XCTAssertTrue(withoutBody.contains("Content-Encoding: gzip"))
        XCTAssertFalse(withoutBody.hasPrefix("#"))

        let json = exporter.single(event, format: .json, includeBody: true)
        XCTAssertTrue(json.contains("sdkVersion"))
        XCTAssertFalse(json.contains("INSTANCETOKENSECRET"))
    }
}
