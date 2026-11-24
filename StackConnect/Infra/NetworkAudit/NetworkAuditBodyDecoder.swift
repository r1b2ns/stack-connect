import Compression
import Foundation

// MARK: - Content decoding

/// Undoes the `Content-Encoding` of a body captured by the URLSession
/// recorder (the Firebase SDKs send gzip-compressed request bodies), so the
/// audit can show, mask and export the real payload.
///
/// - `gzip` / `x-gzip` (RFC 1952) and `deflate` (zlib RFC 1950, or raw RFC
///   1951 as some servers send it) are decoded with Apple's `Compression`.
/// - `br` (brotli) is not decoded.
/// - The output is capped (`maxOutputBytes`): a body that would inflate past
///   it is cut and reported truncated, so a decompression bomb never grows
///   past the cap.
/// - Data that doesn't carry the expected header (a response URLSession has
///   already decoded) is passed through untouched.
enum NetworkAuditBodyDecoder {

    enum Encoding: Equatable, Sendable {
        case gzip
        case deflate
        case brotli
        case unsupported(String)

        init?(header: String?) {
            guard let header else { return nil }
            // `Content-Encoding: gzip` (a list is applied in order; only the
            // single-coding case is handled).
            let value = header.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
            guard value.count == 1, let coding = value.first, !coding.isEmpty, coding != "identity" else { return nil }
            switch coding {
            case "gzip", "x-gzip": self = .gzip
            case "deflate": self = .deflate
            case "br": self = .brotli
            default: self = .unsupported(coding)
            }
        }

        var name: String {
            switch self {
            case .gzip: return "gzip"
            case .deflate: return "deflate"
            case .brotli: return "br"
            case .unsupported(let name): return name
            }
        }
    }

    enum Result: Equatable, Sendable {
        /// The data didn't look encoded (already decoded by URLSession).
        case passthrough
        case decoded(Data, isTruncated: Bool)
        /// An encoding this decoder doesn't handle (`br`, …).
        case unsupported(String)
        /// The data claimed the encoding but didn't decode.
        case failed
    }

    /// - Parameter allowsRawDeflate: try headerless deflate for `deflate`.
    ///   Off for responses: URLSession hands them over decoded, and plain
    ///   text could happen to inflate into garbage.
    static func decode(_ data: Data, encoding: Encoding, maxOutputBytes: Int, allowsRawDeflate: Bool = true) -> Result {
        switch encoding {
        case .brotli, .unsupported:
            return .unsupported(encoding.name)
        case .gzip:
            guard data.count >= 18, data[data.startIndex] == 0x1F, data[data.startIndex + 1] == 0x8B else {
                return .passthrough
            }
            guard let payload = gzipPayload(data) else { return .failed }
            return inflate(payload, maxOutputBytes: maxOutputBytes).map { .decoded($0.data, isTruncated: $0.isTruncated) } ?? .failed
        case .deflate:
            if let payload = zlibPayload(data),
               let inflated = inflate(payload, maxOutputBytes: maxOutputBytes) {
                return .decoded(inflated.data, isTruncated: inflated.isTruncated)
            }
            // Raw deflate, or already decoded text.
            if allowsRawDeflate, let inflated = inflate(data, maxOutputBytes: maxOutputBytes) {
                return .decoded(inflated.data, isTruncated: inflated.isTruncated)
            }
            return .passthrough
        }
    }

    // MARK: - Containers

    /// The deflate stream inside a gzip member (header and trailer removed).
    static func gzipPayload(_ data: Data) -> Data? {
        let bytes = [UInt8](data)
        guard bytes.count >= 18, bytes[0] == 0x1F, bytes[1] == 0x8B, bytes[2] == 8 else { return nil }
        let flags = bytes[3]
        var index = 10
        if flags & 0x04 != 0 { // FEXTRA
            guard index + 2 <= bytes.count else { return nil }
            let length = Int(bytes[index]) | (Int(bytes[index + 1]) << 8)
            index += 2 + length
        }
        if flags & 0x08 != 0 { // FNAME
            while index < bytes.count, bytes[index] != 0 { index += 1 }
            index += 1
        }
        if flags & 0x10 != 0 { // FCOMMENT
            while index < bytes.count, bytes[index] != 0 { index += 1 }
            index += 1
        }
        if flags & 0x02 != 0 { // FHCRC
            index += 2
        }
        let end = bytes.count - 8 // CRC32 + ISIZE
        guard index < end else { return nil }
        return Data(bytes[index..<end])
    }

    /// The deflate stream inside a zlib wrapper, or `nil` without one.
    static func zlibPayload(_ data: Data) -> Data? {
        let bytes = [UInt8](data)
        guard bytes.count >= 6 else { return nil }
        let cmf = bytes[0], flg = bytes[1]
        guard cmf & 0x0F == 8, cmf >> 4 <= 7, (UInt16(cmf) << 8 | UInt16(flg)) % 31 == 0 else { return nil }
        guard flg & 0x20 == 0 else { return nil } // preset dictionary: unsupported
        return Data(bytes[2..<(bytes.count - 4)])
    }

    // MARK: - Inflate

    /// Raw deflate (RFC 1951) with an output cap. `nil` when the stream is
    /// invalid or ends without its final block.
    static func inflate(_ input: Data, maxOutputBytes: Int) -> (data: Data, isTruncated: Bool)? {
        guard !input.isEmpty else { return nil }
        let bufferSize = 64 * 1024
        let destination = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer { destination.deallocate() }

        var stream = compression_stream(
            dst_ptr: destination, dst_size: 0,
            src_ptr: UnsafePointer<UInt8>(bitPattern: 1)!, src_size: 0,
            state: nil
        )
        guard compression_stream_init(&stream, COMPRESSION_STREAM_DECODE, COMPRESSION_ZLIB) == COMPRESSION_STATUS_OK else {
            return nil
        }
        defer { compression_stream_destroy(&stream) }

        var output = Data()
        let succeeded: Bool = input.withUnsafeBytes { raw -> Bool in
            guard let base = raw.bindMemory(to: UInt8.self).baseAddress else { return false }
            stream.src_ptr = base
            stream.src_size = input.count
            while true {
                stream.dst_ptr = destination
                stream.dst_size = bufferSize
                let status = compression_stream_process(&stream, Int32(COMPRESSION_STREAM_FINALIZE.rawValue))
                let produced = bufferSize - stream.dst_size
                if produced > 0 {
                    output.append(destination, count: produced)
                }
                if output.count > maxOutputBytes {
                    return true
                }
                switch status {
                case COMPRESSION_STATUS_END:
                    return true
                case COMPRESSION_STATUS_OK:
                    // No progress with input left means a stream that never ends.
                    if produced == 0, stream.src_size == 0 { return false }
                    continue
                default:
                    return false
                }
            }
        }
        guard succeeded else { return nil }
        if output.count > maxOutputBytes {
            return (output.prefix(maxOutputBytes), true)
        }
        return (output, false)
    }
}

// MARK: - Protobuf (schema-less)

/// Reads protocol buffers without their schema (Firebase Analytics sends its
/// batches as protobuf): field numbers, wire types, varints, fixed values,
/// nested messages when they parse cleanly and UTF-8 strings as text. Raw
/// bytes are never printed, only their length, so a field that carries a
/// secret can't leak through as hex.
enum NetworkAuditProtobufDecoder {

    indirect enum Value: Equatable, Sendable {
        case varint(UInt64)
        case fixed64(UInt64)
        case fixed32(UInt32)
        case string(String)
        case message([Field])
        case bytes(Int)
    }

    struct Field: Equatable, Sendable {
        let number: UInt64
        let value: Value
    }

    static let maxDepth = 12
    static let maxFields = 20_000

    /// The fields of `data`, or `nil` when it isn't a well-formed message.
    static func decode(_ data: Data) -> [Field]? {
        var budget = maxFields
        let fields = parse([UInt8](data)[...], depth: 0, budget: &budget)
        guard let fields, !fields.isEmpty else { return nil }
        return fields
    }

    private static func parse(_ bytes: ArraySlice<UInt8>, depth: Int, budget: inout Int) -> [Field]? {
        guard depth <= maxDepth else { return nil }
        var fields: [Field] = []
        var index = bytes.startIndex
        while index < bytes.endIndex {
            budget -= 1
            guard budget >= 0, let (key, afterKey) = varint(bytes, at: index) else { return nil }
            let number = key >> 3
            let wireType = key & 0x07
            guard number > 0, number < (1 << 29) else { return nil }
            index = afterKey
            switch wireType {
            case 0:
                guard let (value, next) = varint(bytes, at: index) else { return nil }
                fields.append(Field(number: number, value: .varint(value)))
                index = next
            case 1:
                guard bytes.endIndex - index >= 8 else { return nil }
                var value: UInt64 = 0
                for offset in 0..<8 { value |= UInt64(bytes[index + offset]) << (8 * UInt64(offset)) }
                fields.append(Field(number: number, value: .fixed64(value)))
                index += 8
            case 5:
                guard bytes.endIndex - index >= 4 else { return nil }
                var value: UInt32 = 0
                for offset in 0..<4 { value |= UInt32(bytes[index + offset]) << (8 * UInt32(offset)) }
                fields.append(Field(number: number, value: .fixed32(value)))
                index += 4
            case 2:
                guard let (length, start) = varint(bytes, at: index),
                      length <= UInt64(bytes.endIndex - start) else { return nil }
                let end = start + Int(length)
                let chunk = bytes[start..<end]
                fields.append(Field(number: number, value: lengthDelimited(chunk, depth: depth, budget: &budget)))
                index = end
            default:
                // Groups (3, 4) are deprecated and 6, 7 don't exist.
                return nil
            }
        }
        return fields
    }

    /// A string when the bytes are printable UTF-8, a nested message when
    /// they parse as one, otherwise opaque bytes (length only).
    private static func lengthDelimited(_ chunk: ArraySlice<UInt8>, depth: Int, budget: inout Int) -> Value {
        let text = String(bytes: chunk, encoding: .utf8)
        // Plain printable text (no control characters at all): a string.
        if let text, isPrintable(text, allowingLineBreaks: false) {
            return .string(text)
        }
        // Tags look like control characters (`0x0A` is field 1, length
        // delimited): try a nested message before multi-line text.
        var nestedBudget = budget
        if !chunk.isEmpty, let nested = parse(chunk, depth: depth + 1, budget: &nestedBudget), !nested.isEmpty {
            budget = nestedBudget
            return .message(nested)
        }
        if let text, isPrintable(text, allowingLineBreaks: true) {
            return .string(text)
        }
        return .bytes(chunk.count)
    }

    private static func isPrintable(_ text: String, allowingLineBreaks: Bool) -> Bool {
        text.unicodeScalars.allSatisfy { scalar in
            if allowingLineBreaks, scalar == "\n" || scalar == "\t" || scalar == "\r" { return true }
            switch scalar.properties.generalCategory {
            case .control, .format, .unassigned, .privateUse, .surrogate: return false
            default: return true
            }
        }
    }

    private static func varint(_ bytes: ArraySlice<UInt8>, at start: Int) -> (UInt64, Int)? {
        var value: UInt64 = 0
        var shift: UInt64 = 0
        var index = start
        while index < bytes.endIndex, shift < 64 {
            let byte = bytes[index]
            value |= UInt64(byte & 0x7F) << shift
            index += 1
            if byte & 0x80 == 0 { return (value, index) }
            shift += 7
        }
        return nil
    }

    // MARK: - Rendering

    /// An indented tree: `1 { … }`, `2: 1234`, `7: "screen_view"`.
    static func render(_ fields: [Field], indent: Int = 0) -> String {
        let pad = String(repeating: "  ", count: indent)
        return fields.map { field -> String in
            switch field.value {
            case .varint(let value):
                return "\(pad)\(field.number): \(value)"
            case .fixed64(let value):
                return "\(pad)\(field.number): \(value) (fixed64, \(Double(bitPattern: value)) as double)"
            case .fixed32(let value):
                return "\(pad)\(field.number): \(value) (fixed32, \(Float(bitPattern: value)) as float)"
            case .string(let text):
                return "\(pad)\(field.number): \"\(text.replacingOccurrences(of: "\"", with: "\\\""))\""
            case .bytes(let count):
                return "\(pad)\(field.number): <\(count) bytes>"
            case .message(let nested):
                return "\(pad)\(field.number) {\n\(render(nested, indent: indent + 1))\n\(pad)}"
            }
        }
        .joined(separator: "\n")
    }
}
