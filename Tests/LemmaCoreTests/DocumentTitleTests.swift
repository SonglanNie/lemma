import XCTest
@testable import LemmaCore

final class DocumentTitleTests: XCTestCase {
    func testKeepsRealTitles() {
        XCTAssertEqual(DocumentTitle.fromMetadata("Attention Is All You Need", fileName: "1706.03762v7.pdf"), "Attention Is All You Need")
        XCTAssertEqual(DocumentTitle.fromMetadata("  The Elements of\nStatistical Learning ", fileName: "ESLII_print12.pdf"),
                       "The Elements of Statistical Learning")
        XCTAssertEqual(DocumentTitle.fromMetadata("“Book of Proof”", fileName: "Main.pdf"), "Book of Proof")
        XCTAssertEqual(DocumentTitle.fromMetadata("MATHEMATICS FOR MACHINE LEARNING", fileName: "mml.pdf"), "Mathematics For Machine Learning")
    }

    func testRejectsPlaceholdersAndToolNames() {
        for junk in [nil, "", "Untitled", "main", "Microsoft Word - thesis_final.docx", "paper.tex", "C:\\docs\\a.pdf", "ESLII_print12",
                     "1706.03762v7", "abc", "12345", "mml"] {
            XCTAssertNil(DocumentTitle.fromMetadata(junk, fileName: "mml.pdf"), "\(junk ?? "nil") should be rejected")
        }
        XCTAssertNil(DocumentTitle.fromMetadata("Lecture notes", fileName: "x.pdf"))
        XCTAssertNil(DocumentTitle.fromMetadata("notes on linear smoothers", fileName: "Notes_on_linear_smoothers.pdf"))
    }
}
