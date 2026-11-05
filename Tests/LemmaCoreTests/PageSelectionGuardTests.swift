import XCTest
import PDFKit
@testable import LemmaCore

/// The pages that trap are parts of real books, and a trap would end the test run, so these tests check the guard on a
/// healthy fixture: what matters is that a blocked page gives no selections and keeps everything else.
final class PageSelectionGuardTests: XCTestCase {
    private func fixture() throws -> PDFDocument {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "book-chapters", withExtension: "pdf", subdirectory: "Fixtures"))
        return try XCTUnwrap(PDFDocument(url: url))
    }

    func testPagesOfAWatchedDocumentAreGuarded() throws {
        let document = try fixture()
        let selectionGuard = PageSelectionGuard(blocked: [0])
        selectionGuard.watch(document)
        let page = try XCTUnwrap(document.page(at: 0))
        XCTAssertNil(page.selection(for: page.bounds(for: .cropBox)),
                     "PDFKit must make the guard's page class, or a blocked page would still reach CoreGraphics.")
    }

    func testABlockedPageKeepsItsTextAndLosesOnlyItsSelections() throws {
        let document = try fixture()
        let plain = try XCTUnwrap(fixture().page(at: 1)?.string)
        XCTAssertFalse(plain.isEmpty)
        let selectionGuard = PageSelectionGuard(blocked: [1])
        selectionGuard.watch(document)
        let blocked = try XCTUnwrap(document.page(at: 1)), open = try XCTUnwrap(document.page(at: 2))

        XCTAssertEqual(blocked.string, plain)
        XCTAssertNotNil(blocked.pageRef, "Emphasis is read from the page's content stream, which selections do not touch.")
        XCTAssertNil(blocked.selection(for: blocked.bounds(for: .cropBox)))
        XCTAssertNil(blocked.selection(for: NSRange(location: 0, length: 1)))
        let middle = CGPoint(x: blocked.bounds(for: .cropBox).midX, y: blocked.bounds(for: .cropBox).midY)
        XCTAssertNil(blocked.selection(from: middle, to: CGPoint(x: middle.x + 40, y: middle.y - 40)), "The reader's text tool selects by points.")
        XCTAssertNil(blocked.selectionForWord(at: middle))
        XCTAssertNil(blocked.selectionForLine(at: middle))
        XCTAssertNotNil(open.selection(for: open.bounds(for: .cropBox)))
        XCTAssertNotNil(open.selection(for: NSRange(location: 0, length: 1)))
    }

    func testSelectionsReportThePageInUseOnlyWhenItChanges() throws {
        let document = try fixture()
        final class Pages { var seen: [Int] = [] }
        let pages = Pages()
        let selectionGuard = PageSelectionGuard(blocked: [1]) { pages.seen.append($0) }
        selectionGuard.watch(document)
        let first = try XCTUnwrap(document.page(at: 0)), blocked = try XCTUnwrap(document.page(at: 1)), third = try XCTUnwrap(document.page(at: 2))

        _ = first.selection(for: first.bounds(for: .cropBox))
        _ = first.selection(for: NSRange(location: 0, length: 1))
        _ = blocked.selection(for: blocked.bounds(for: .cropBox))
        _ = third.selection(for: third.bounds(for: .cropBox))
        _ = first.selection(for: first.bounds(for: .cropBox))
        XCTAssertEqual(pages.seen, [0, 2, 0], "A blocked page is never in use, and the last report names the page that was.")
    }

    func testAnalysisFinishesWithABlockedPage() throws {
        let document = try fixture()
        let selectionGuard = PageSelectionGuard(blocked: [1])
        selectionGuard.watch(document)
        let analysis = BookAnalyzer.analyze(document: document, outline: [])
        XCTAssertEqual(analysis?.pageCount, document.pageCount)
    }

    func testAPageCanBeAskedWithoutCountingAsInUse() throws {
        let document = try fixture()
        final class Pages { var seen: [Int] = [] }
        let pages = Pages()
        let selectionGuard = PageSelectionGuard(blocked: [1]) { pages.seen.append($0) }
        selectionGuard.watch(document)
        XCTAssertTrue(try XCTUnwrap(document.page(at: 0)).admitsSelection)
        XCTAssertFalse(try XCTUnwrap(document.page(at: 1)).admitsSelection)
        XCTAssertEqual(pages.seen, [], "Only a selection can end the process.")
    }

    func testAPageOfAnUnguardedDocumentAdmitsSelections() throws {
        XCTAssertTrue(try XCTUnwrap(fixture().page(at: 0)).admitsSelection)
    }

    func testBlockedPagesAreKeptPerBook() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = DocumentIndexRepository(root: root)
        XCTAssertEqual(repository.selectionBlockedPages("book"), [])
        try repository.addSelectionBlockedPages([], id: "book")
        XCTAssertFalse(FileManager.default.fileExists(atPath: repository.directory("book").path), "A book with no bad page leaves nothing behind.")
        try repository.addSelectionBlockedPages([957], id: "book")
        try repository.addSelectionBlockedPages([19, 957], id: "book")
        XCTAssertEqual(repository.selectionBlockedPages("book"), [19, 957])
        XCTAssertEqual(repository.selectionBlockedPages("another"), [])
    }

    func testNoPageIsClearedUntilTheAnalysisHasReadIt() {
        var clearance = PageSelectionClearance()
        XCTAssertFalse(clearance.admits(0), "The reader selects on the page in view at once, and a trap there would end Lemma.")
        XCTAssertTrue(clearance.isWaitingForPages)

        clearance.read(pages: 4)
        XCTAssertTrue(clearance.admits(3))
        XCTAssertFalse(clearance.admits(4))
        XCTAssertFalse(clearance.admitsEveryPage)

        clearance.read(pages: 1)
        XCTAssertTrue(clearance.admits(3), "A run that starts over reports fewer pages, and what was read still stands.")

        clearance.block([2])
        XCTAssertFalse(clearance.admits(2))
        clearance.readAllPages()
        XCTAssertFalse(clearance.admits(2), "Nothing clears a blocked page.")
        XCTAssertTrue(clearance.admits(500))
        XCTAssertFalse(clearance.isWaitingForPages)
        XCTAssertFalse(clearance.admitsEveryPage, "PDFKit's own selections must stay out of a book with a blocked page.")
    }

    func testABookWithNoBadPageAdmitsEveryPageOnceRead() {
        var clearance = PageSelectionClearance()
        XCTAssertFalse(clearance.admitsEveryPage)
        clearance.readAllPages()
        XCTAssertTrue(clearance.admitsEveryPage)
    }

    private func recordURL() -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: folder) }
        return folder.appendingPathComponent("page.json")
    }

    func testANoteAloneBlamesNothing() {
        let url = recordURL()
        PageInUseRecord(url: url).note(.init(book: "book", pageIndex: 12))
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        XCTAssertNil(PageInUseRecord.take(at: url), "A force quit or a power cut leaves a note: it must not cost a healthy page its selections.")
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path), "What the last run left is removed.")
    }

    func testANoteMarkedByATrapNamesThePage() throws {
        let url = recordURL()
        PageInUseRecord(url: url).note(.init(book: "book", pageIndex: 12))
        try FileManager.default.moveItem(at: url, to: url.appendingPathExtension("trapped"))
        XCTAssertEqual(PageInUseRecord.take(at: url), .init(book: "book", pageIndex: 12))
        XCTAssertNil(PageInUseRecord.take(at: url), "A page is reported once.")
    }

    func testANoteEndsSoonAfterTheLastSelection() {
        let url = recordURL()
        let record = PageInUseRecord(url: url, holdTime: 0.05)
        record.note(.init(book: "book", pageIndex: 3))
        Thread.sleep(forTimeInterval: 0.5)
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path), "Losing power long after a selection must leave nothing to read.")
    }

    func testANoteOutlastsPDFKitsMouseTracking() {
        let url = recordURL()
        let record = PageInUseRecord(url: url, holdTime: 0.05)
        record.note(.init(book: "book", pageIndex: 12))
        record.hold { Thread.sleep(forTimeInterval: 0.3) }
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path), "PDFKit selects for as long as the button is down, without asking the page.")
    }

    func testQuittingRemovesTheNote() {
        let url = recordURL()
        let record = PageInUseRecord(url: url)
        record.note(.init(book: "book", pageIndex: 12))
        record.remove()
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }

    func testRecoveryBlocksEachPageOnceAndStopsWhenAnotherRunCannotHelp() {
        var recovery = PageSelectionRecovery()
        XCTAssertFalse(recovery.block(nil), "A crash before any selection is not a page's.")
        XCTAssertTrue(recovery.block(12))
        XCTAssertFalse(recovery.block(12), "A blocked page cannot have caused the next crash.")
        XCTAssertEqual(recovery.blocked, [12])

        var full = PageSelectionRecovery()
        for page in 0..<PageSelectionRecovery.pageLimit { XCTAssertTrue(full.block(page)) }
        XCTAssertFalse(full.block(PageSelectionRecovery.pageLimit))
    }

    func testMarkersAndTheBlockedPagesArgumentReadBack() {
        XCTAssertEqual(PageSelectionRecovery.pageIndex(inMarker: PageSelectionRecovery.marker(pageIndex: 957)), 957)
        XCTAssertNil(PageSelectionRecovery.pageIndex(inMarker: "progress 12 39"))
        XCTAssertNil(PageSelectionRecovery.pageIndex(inMarker: "done"))

        XCTAssertEqual(PageSelectionRecovery.pageIndex(inBlockedReport: PageSelectionRecovery.blockedReport(pageIndex: 957)), 957)
        XCTAssertNil(PageSelectionRecovery.pageIndex(inBlockedReport: "selecting 957"))

        XCTAssertEqual(PageSelectionRecovery.argument(for: [957, 19]), "19,957")
        XCTAssertEqual(PageSelectionRecovery.pages(inArgument: "19,957"), [19, 957])
        XCTAssertEqual(PageSelectionRecovery.pages(inArgument: ""), [])
        XCTAssertNil(PageSelectionRecovery.pages(inArgument: "19,x"))
    }
}
