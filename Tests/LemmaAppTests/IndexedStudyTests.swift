import XCTest
import AppKit
import PDFKit
import LemmaCore
@testable import Lemma

final class IndexedStudyTests: XCTestCase {
    @MainActor
    func testReviewCorrectsSearchWithoutCreatingNotesOrMovingTheReader() async throws {
        _ = NSApplication.shared
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let source = root.appendingPathComponent("scan.pdf")
        let image = NSImage(size: NSSize(width: 400, height: 300), flipped: false) { rect in
            NSColor.white.setFill(); rect.fill()
            ("Full column rank" as NSString).draw(at: CGPoint(x: 25, y: 190), withAttributes: [.font: NSFont.systemFont(ofSize: 24)])
            return true
        }
        let pdf = PDFDocument(); pdf.insert(try XCTUnwrap(PDFPage(image: image)), at: 0)
        XCTAssertTrue(pdf.write(to: source))
        let original = try Data(contentsOf: source)
        let store = StudyStore(app: AppModel(root: root.appendingPathComponent("support"))); store.open(source)
        let id = try XCTUnwrap(store.workspace?.id)
        let wrongText = "Full co1umn rank"
        let page = IndexedPage(pageIndex: 0, pageLabel: "1", origin: .ocr,
            passages: [.init(text: wrongText)], text: wrongText)
        try store.indexRepository.save(page, id: id)
        let hit = try XCTUnwrap(PassageSearch.find("co1umn", in: [(id, [page])], byMeaning: false).first)
        store.prepareIndexReview(hit)
        let capture = try XCTUnwrap(store.ocrCapture)
        XCTAssertEqual(capture.indexedPage?.text, wrongText)
        XCTAssertNotNil(NSBitmapImageRep(data: capture.pngData))
        let selectedNote = store.selectedNoteID, readingPage = store.reader.pageNumber
        store.pageSearchQuery = "column"
        store.saveIndexReview(capture, text: "Full column rank gives unique coefficients.")
        await store.pageSearchTask?.value
        let corrected = try XCTUnwrap(store.indexRepository.pages(id).first)
        XCTAssertNotNil(corrected.reviewedAt)
        XCTAssertEqual(corrected.origin, .ocr)
        XCTAssertEqual(store.pageSearchResults.first?.pageIndex, 0)
        XCTAssertTrue(PassageSearch.find("co1umn", in: [(id, [corrected])], byMeaning: false).isEmpty)
        XCTAssertNil(store.ocrCapture); XCTAssertTrue(store.workspace?.notes.isEmpty == true)
        XCTAssertEqual(store.selectedNoteID, selectedNote); XCTAssertEqual(store.reader.pageNumber, readingPage)
        XCTAssertEqual(try Data(contentsOf: source), original)
        XCTAssertNil(store.error)
    }
}
