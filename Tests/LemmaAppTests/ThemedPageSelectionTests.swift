import XCTest
import PDFKit
@testable import Lemma
@testable import LemmaCore

/// The reader selects on the page in view as soon as it shows it, and a bad page ends Lemma: its pages must refuse
/// selections until the book's analysis has read them.
@MainActor
final class ThemedPageSelectionTests: XCTestCase {
    private func document() throws -> PDFDocument {
        let page = PDFDocument()
        for index in 0..<3 { page.insert(PDFPage(), at: index) }
        let data = try XCTUnwrap(page.dataRepresentation())
        let document = try XCTUnwrap(PDFDocument(data: data))
        document.delegate = ThemedPageProvider.shared
        return document
    }

    func testReaderPagesAreGuarded() throws {
        let document = try document()
        XCTAssertTrue(document.page(at: 0) is TextGuardedPage)
    }

    func testADocumentThatIsNotTrackedRefusesNothing() throws {
        let document = try document()
        let provider = ThemedPageProvider.shared
        XCTAssertTrue(provider.admitsSelection(on: try XCTUnwrap(document.page(at: 1)), in: document))
        XCTAssertTrue(provider.admitsEveryPage(in: document))
        XCTAssertFalse(provider.isWaitingForPages(in: document))
    }

    func testPagesFollowTheirOwnDocumentsClearance() throws {
        let document = try document(), other = try self.document()
        let provider = ThemedPageProvider.shared
        var clearance = PageTextClearance()
        clearance.read(pages: 1)
        provider.track(document, book: "book", clearance: clearance)

        XCTAssertTrue(provider.admitsSelection(on: try XCTUnwrap(document.page(at: 0)), in: document))
        XCTAssertFalse(provider.admitsSelection(on: try XCTUnwrap(document.page(at: 1)), in: document))
        XCTAssertTrue(provider.admitsSelection(on: try XCTUnwrap(other.page(at: 1)), in: other))
        XCTAssertFalse(provider.admitsEveryPage(in: document))
        XCTAssertTrue(provider.isWaitingForPages(in: document))
    }

    func testAnUpdateReachesTheDocument() throws {
        let document = try document()
        let provider = ThemedPageProvider.shared
        let page = try XCTUnwrap(document.page(at: 1))
        var clearance = PageTextClearance()
        provider.track(document, book: "book", clearance: clearance)
        XCTAssertFalse(provider.admitsSelection(on: page, in: document))

        clearance.readAllPages()
        provider.update(clearance, for: document)
        XCTAssertTrue(provider.admitsSelection(on: page, in: document))
        XCTAssertTrue(provider.admitsEveryPage(in: document))

        clearance.blockSelection([1])
        provider.update(clearance, for: document)
        XCTAssertFalse(provider.admitsSelection(on: page, in: document))
        XCTAssertFalse(provider.admitsEveryPage(in: document))
        XCTAssertFalse(provider.isWaitingForPages(in: document), "A blocked page is not waiting for anything.")

        clearance = PageTextClearance(textBlocked: [1])
        clearance.readAllPages()
        provider.update(clearance, for: document)
        XCTAssertFalse(provider.admitsText(on: page, in: document))
        XCTAssertFalse(provider.admitsSelection(on: page, in: document), "Selecting needs the text the page can't give.")
        XCTAssertFalse(document.admitsEveryPage)
        XCTAssertNil(page.string)
    }

    func testABookLeftUnanalysedStopsWaitingAndKeepsItsBlockedPages() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = DocumentIndexRepository(root: root)
        try repository.addSelectionBlockedPages([1], id: "book")
        let model = BookAnalysisModel(workspaceID: "book", repository: repository, waitsForAnalysis: true)
        XCTAssertFalse(model.clearance.admitsSelection(0))
        XCTAssertFalse(model.clearance.admitsSelection(1))

        var told = 0
        model.onClearanceChange = { told += 1 }
        model.skip("This PDF is protected by a password.")
        XCTAssertEqual(told, 1)
        XCTAssertTrue(model.clearance.admitsSelection(0), "No analysis will come, and waiting would leave the book without selections.")
        XCTAssertFalse(model.clearance.admitsSelection(1))
    }

    func testAPageWithUnreadableTextStaysRefusedWhateverHappensToTheAnalysis() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = DocumentIndexRepository(root: root)
        try repository.addTextBlockedPages([1], id: "book")
        let model = BookAnalysisModel(workspaceID: "book", repository: repository, waitsForAnalysis: true)
        XCTAssertFalse(model.clearance.admitsText(0), "An unread page's text may never return.")
        XCTAssertFalse(model.clearance.admitsText(1))

        model.skip("This PDF is protected by a password.")
        XCTAssertTrue(model.clearance.admitsText(0))
        XCTAssertFalse(model.clearance.admitsText(1))
        XCTAssertFalse(model.clearance.admitsSelection(1))
    }

    func testWithoutAHelperNoPageWaits() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = DocumentIndexRepository(root: root)
        try repository.addSelectionBlockedPages([1], id: "book")
        let model = BookAnalysisModel(workspaceID: "book", repository: repository, waitsForAnalysis: false)
        XCTAssertTrue(model.clearance.admitsSelection(0), "Only a helper can try a page safely: here waiting would protect nothing.")
        XCTAssertFalse(model.clearance.admitsSelection(1), "A page known to be bad stays refused.")
    }
}
