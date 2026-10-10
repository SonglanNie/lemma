import XCTest
@testable import LemmaCore

final class CleanCopyTests: XCTestCase {
    func testJoinsLinesAndHyphensAndRepairsLigatures() {
        let raw = "The meth-\nods of least squares are ef\u{FB01}cient\nfor a ﬁnite sample.\n\nA second para-\ngraph by B¨uhlmann."
        XCTAssertEqual(CleanCopy.text(raw), "The methods of least squares are efficient for a finite sample.\n\nA second paragraph by Bühlmann.")
    }

    func testKeepsDashesAndRanges() {
        XCTAssertEqual(CleanCopy.text("pages 499–\n501 and well-\nKnown"), "pages 499–501 and well-Known")
        XCTAssertEqual(CleanCopy.text("  single line  "), "single line")
        XCTAssertEqual(CleanCopy.text(""), "")
    }
}
