import XCTest
@testable import WindowsAppCore

// T-W18 — Unit tests for `ReviewExcerptFormatter` (TC-064, TC-065).
//
// Verifies the pure excerpt-truncation helper produces correct output at
// every boundary: empty, short, exact-length, over-length (word-boundary
// backtrack + hard truncate), and unicode safety (emoji, CJK).

final class ReviewExcerptFormatterTests: XCTestCase {

    // MARK: - TC-064: Excerpt truncation boundaries

    /// Empty body produces an empty string.
    func test_excerpt_emptyBody_returnsEmpty() {
        XCTAssertEqual(ReviewExcerptFormatter.excerpt(""), "")
    }

    /// Nil body produces an empty string.
    func test_excerpt_nilBody_returnsEmpty() {
        XCTAssertEqual(ReviewExcerptFormatter.excerpt(nil), "")
    }

    /// Whitespace-only body produces an empty string.
    func test_excerpt_whitespaceOnly_returnsEmpty() {
        XCTAssertEqual(ReviewExcerptFormatter.excerpt("   \n  "), "")
    }

    /// A body shorter than the limit is returned verbatim (no ellipsis).
    func test_excerpt_shortBody_returnsVerbatim() {
        let short = "Great app, love it!"
        let result = ReviewExcerptFormatter.excerpt(short, maxLength: 100)
        XCTAssertEqual(result, short)
        XCTAssertFalse(result.hasSuffix("\u{2026}"),
                       "Short body should not have trailing ellipsis")
    }

    /// A body exactly at the limit is returned verbatim (no ellipsis).
    func test_excerpt_exactLength_returnsVerbatim() {
        // Build a string of exactly 100 characters with spaces for word boundaries.
        let body = String(repeating: "abcde ", count: 16) + "abcd"
        XCTAssertEqual(body.count, 100, "Precondition: body is exactly 100 chars")

        let result = ReviewExcerptFormatter.excerpt(body, maxLength: 100)
        XCTAssertEqual(result, body)
        XCTAssertFalse(result.hasSuffix("\u{2026}"),
                       "Exact-length body should not have trailing ellipsis")
    }

    /// A body longer than the limit is truncated at a word boundary with "...".
    func test_excerpt_longBody_truncatesAtWordBoundary() {
        // 120 chars with spaces every 10 chars.
        let body = String(repeating: "abcdefghi ", count: 12)
        XCTAssertGreaterThan(body.count, 100, "Precondition: body exceeds 100 chars")

        let result = ReviewExcerptFormatter.excerpt(body, maxLength: 100)
        XCTAssertTrue(result.hasSuffix("\u{2026}"),
                      "Over-length body should end with ellipsis")
        // The text before the ellipsis should not exceed maxLength characters total
        // (text + ellipsis).
        let textBeforeEllipsis = String(result.dropLast())
        XCTAssertLessThanOrEqual(textBeforeEllipsis.count, 100,
                                 "Text before ellipsis should not exceed maxLength")
        // Should not end mid-word (last char before ellipsis should be preceded
        // by a space, meaning the word boundary was respected).
        XCTAssertFalse(textBeforeEllipsis.hasSuffix("abcdefgh"),
                       "Should not cut mid-word 'abcdefghi'")
    }

    /// A body with no spaces (single giant word) truncates at maxLength directly.
    func test_excerpt_noSpaces_hardTruncates() {
        let body = String(repeating: "x", count: 150)
        let result = ReviewExcerptFormatter.excerpt(body, maxLength: 100)
        XCTAssertTrue(result.hasSuffix("\u{2026}"))
        // 100 x's + ellipsis = 101 characters total
        XCTAssertEqual(result.count, 101)
    }

    /// Custom maxLength is respected.
    func test_excerpt_customMaxLength() {
        let body = "This is a short sentence that should be truncated at fifty characters."
        let result = ReviewExcerptFormatter.excerpt(body, maxLength: 50)
        XCTAssertTrue(result.hasSuffix("\u{2026}"))
        let textBeforeEllipsis = String(result.dropLast())
        XCTAssertLessThanOrEqual(textBeforeEllipsis.count, 50)
    }

    /// Leading/trailing whitespace in the body is trimmed before truncation.
    func test_excerpt_trimming() {
        let body = "  Hello world  "
        let result = ReviewExcerptFormatter.excerpt(body, maxLength: 100)
        XCTAssertEqual(result, "Hello world")
    }

    // MARK: - TC-065: Unicode / emoji safety

    /// Emoji characters are counted as single characters (grapheme clusters),
    /// not split across UTF-16 code units.
    func test_excerpt_emojiCounting() {
        // 5 emoji + 95 ASCII = 100 characters (should fit exactly).
        let emojis = "\u{1F44D}\u{1F602}\u{2764}\u{FE0F}\u{1F389}\u{1F680}"  // 6 emoji (heart is 2 scalars but 1 grapheme)
        // Actually, let's be precise: build exactly 100 Characters
        let padding = String(repeating: "a", count: 100 - emojis.count)
        let body = emojis + padding
        XCTAssertEqual(body.count, 100, "Precondition: body is exactly 100 grapheme clusters")

        let result = ReviewExcerptFormatter.excerpt(body, maxLength: 100)
        XCTAssertEqual(result, body, "Exact-length emoji body should be returned verbatim")
        XCTAssertFalse(result.hasSuffix("\u{2026}"))
    }

    /// CJK characters are counted correctly and do not break on truncation.
    func test_excerpt_cjkCharacters() {
        // 110 CJK characters — should truncate at 100 + ellipsis.
        let body = String(repeating: "\u{7528}\u{6237}", count: 55)
        XCTAssertEqual(body.count, 110, "Precondition: body is 110 CJK chars")

        let result = ReviewExcerptFormatter.excerpt(body, maxLength: 100)
        XCTAssertTrue(result.hasSuffix("\u{2026}"))
        // No spaces in CJK, so hard truncate: 100 chars + ellipsis
        XCTAssertEqual(result.count, 101)
    }

    /// A nickname with emoji/unicode is preserved verbatim when passed through
    /// the excerpt formatter (verifying no parsing errors or corruption).
    func test_excerpt_nicknameWithEmoji_preservedVerbatim() {
        let nickname = "User\u{1F44D}\u{1F602} / \u{7528}\u{6237}"
        let result = ReviewExcerptFormatter.excerpt(nickname, maxLength: 100)
        XCTAssertEqual(result, nickname,
                       "Short unicode nickname should be preserved verbatim")
    }

    /// The defaultMaxLength constant is 100.
    func test_defaultMaxLength_is100() {
        XCTAssertEqual(ReviewExcerptFormatter.defaultMaxLength, 100)
    }
}
