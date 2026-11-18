import XCTest
@testable import StackConnect

final class LicenseTextFormatterTests: XCTestCase {

    func testSingleNewlinesBecomeSpacesAndBlankLinesStayParagraphs() {
        let raw = "MIT License\n\nPermission is hereby granted, to deal\nin the Software\nwithout restriction.\n\nTHE SOFTWARE IS PROVIDED\n\"AS IS\".\n"
        XCTAssertEqual(
            LicenseTextFormatter.reflow(raw),
            "MIT License\n\nPermission is hereby granted, to deal in the Software without restriction.\n\nTHE SOFTWARE IS PROVIDED \"AS IS\"."
        )
    }

    func testCollapsesMultipleBlankLinesAndHandlesCRLF() {
        let raw = "A\r\nB\r\n\r\n\r\n   \r\nC  \r\n"
        XCTAssertEqual(LicenseTextFormatter.reflow(raw), "A B\n\nC")
    }

    func testEmptyTextStaysEmpty() {
        XCTAssertEqual(LicenseTextFormatter.reflow(""), "")
        XCTAssertEqual(LicenseTextFormatter.reflow("\n\n"), "")
    }

    func testBundledLicenseHasNoHardWrapsInsideParagraphs() throws {
        let url = try XCTUnwrap(Bundle(for: LicenseViewModel.self).url(forResource: "LICENSE", withExtension: "txt")
            ?? Bundle.main.url(forResource: "LICENSE", withExtension: "txt"))
        let raw = try String(contentsOf: url, encoding: .utf8)
        let paragraphs = LicenseTextFormatter.reflow(raw).components(separatedBy: "\n\n")
        XCTAssertEqual(paragraphs.first, "MIT License")
        XCTAssertTrue(paragraphs.allSatisfy { !$0.contains("\n") })
        XCTAssertTrue(paragraphs.contains { $0.hasPrefix("Permission is hereby granted") && $0.contains("to deal in the Software") })
    }
}
