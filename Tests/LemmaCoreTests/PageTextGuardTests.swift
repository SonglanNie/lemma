import XCTest
import PDFKit
@testable import LemmaCore

/// The bad pages are parts of real books, and a trap or a page whose text never returns would end the test run, so these
/// tests check the guard on a healthy fixture: what matters is what a blocked page gives, and that it keeps everything else.
final class PageTextGuardTests: XCTestCase {
    private func fixture() throws -> PDFDocument {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "book-chapters", withExtension: "pdf", subdirectory: "Fixtures"))
        return try XCTUnwrap(PDFDocument(url: url))
    }

    func testPagesOfAWatchedDocumentAreGuarded() throws {
        let document = try fixture()
        let textGuard = PageTextGuard(selectionBlocked: [0])
        textGuard.watch(document)
        let page = try XCTUnwrap(document.page(at: 0))
        XCTAssertNil(page.selection(for: page.bounds(for: .cropBox)),
                     "PDFKit must make the guard's page class, or a blocked page would still reach CoreGraphics.")
    }

    func testABlockedPageKeepsItsTextAndLosesOnlyItsSelections() throws {
        let document = try fixture()
        let plain = try XCTUnwrap(fixture().page(at: 1)?.string)
        XCTAssertFalse(plain.isEmpty)
        let textGuard = PageTextGuard(selectionBlocked: [1])
        textGuard.watch(document)
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
        let textGuard = PageTextGuard(selectionBlocked: [1]) { pages.seen.append($0) }
        textGuard.watch(document)
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
        let textGuard = PageTextGuard(selectionBlocked: [1])
        textGuard.watch(document)
        let analysis = BookAnalyzer.analyze(document: document, outline: [])
        XCTAssertEqual(analysis?.pageCount, document.pageCount)
    }

    func testAPageCanBeAskedWithoutCountingAsInUse() throws {
        let document = try fixture()
        final class Pages { var seen: [Int] = [] }
        let pages = Pages()
        let textGuard = PageTextGuard(selectionBlocked: [1]) { pages.seen.append($0) }
        textGuard.watch(document)
        XCTAssertTrue(try XCTUnwrap(document.page(at: 0)).admitsSelection)
        XCTAssertFalse(try XCTUnwrap(document.page(at: 1)).admitsSelection)
        XCTAssertEqual(pages.seen, [], "Only a selection can end the process.")
    }

    func testAPageOfAnUnguardedDocumentAdmitsSelections() throws {
        XCTAssertTrue(try XCTUnwrap(fixture().page(at: 0)).admitsSelection)
        XCTAssertTrue(try XCTUnwrap(fixture().page(at: 0)).admitsText)
    }

    func testATextBlockedPageGivesNothingButItsImage() throws {
        let document = try fixture()
        let textGuard = PageTextGuard(textBlocked: [1])
        textGuard.watch(document)
        let blocked = try XCTUnwrap(document.page(at: 1)), open = try XCTUnwrap(document.page(at: 2))
        let box = blocked.bounds(for: .cropBox), middle = CGPoint(x: box.midX, y: box.midY)

        XCTAssertFalse(blocked.admitsText)
        XCTAssertFalse(blocked.admitsSelection)
        XCTAssertNil(blocked.string)
        XCTAssertNil(blocked.attributedString)
        XCTAssertEqual(blocked.numberOfCharacters, 0)
        XCTAssertEqual(blocked.characterIndex(at: middle), -1)
        XCTAssertEqual(blocked.characterBounds(at: 0), .zero)
        XCTAssertNil(blocked.selection(for: box))
        XCTAssertNil(blocked.selectionForWord(at: middle))
        XCTAssertFalse(blocked.bounds(for: .cropBox).isEmpty)
        XCTAssertFalse(open.string?.isEmpty ?? true)
        XCTAssertGreaterThan(open.numberOfCharacters, 0)
        XCTAssertNotNil(open.selection(for: open.bounds(for: .cropBox)))
    }

    func testPDFKitAsksForATextLayoutByTheNameTheGuardReplaces() throws {
        // A mouse move and a right click reach a page's text only through this method. If this fails, macOS has renamed it, and
        // those paths run away on a page whose text never returns: see `TextGuardedPage.buildPageLayout`.
        XCTAssertTrue(PDFPage.instancesRespond(to: NSSelectorFromString("_buildPageLayout")))

        let document = try fixture()
        let textGuard = PageTextGuard(textBlocked: [1])
        textGuard.watch(document)
        let layout = NSSelectorFromString("pageLayout")
        XCTAssertNil(try XCTUnwrap(document.page(at: 1)).perform(layout))
        XCTAssertNotNil(try XCTUnwrap(document.page(at: 2)).perform(layout), "Other pages get PDFKit's own layout.")
    }

    func testPDFKitReadsATaggedStructureThroughTheMethodsTheGuardReplaces() throws {
        // PDFKit's accessibility code builds a page's text with no call on the page: see `PageAccessibilityGuard`.
        let rootNode = try XCTUnwrap(NSClassFromString(PageAccessibilityGuard.rootNode.type))
        XCTAssertNotNil(class_getClassMethod(rootNode, PageAccessibilityGuard.rootNode.selector))
        for method in [PageAccessibilityGuard.search, PageAccessibilityGuard.imageNode] {
            XCTAssertNotNil(class_getInstanceMethod(try XCTUnwrap(NSClassFromString(method.type)), method.selector))
        }

        PageAccessibilityGuard.install()
        PageAccessibilityGuard.install()
        let document = try fixture()
        let textGuard = PageTextGuard(textBlocked: [1])
        textGuard.watch(document)
        let builder = rootNode as AnyObject
        XCTAssertNil(builder.perform(PageAccessibilityGuard.rootNode.selector, with: try XCTUnwrap(document.page(at: 1))))
        XCTAssertNotNil(builder.perform(PageAccessibilityGuard.rootNode.selector, with: try XCTUnwrap(document.page(at: 2))), "Other pages keep their structure.")
    }

    func testReadingTextNamesThePageInUseWithoutReportingASelection() throws {
        let document = try fixture()
        final class Pages { var seen: [Int] = [] }
        let pages = Pages()
        let textGuard = PageTextGuard(textBlocked: [1]) { pages.seen.append($0) }
        textGuard.watch(document)
        XCTAssertNil(textGuard.pageInUse)

        _ = try XCTUnwrap(document.page(at: 2)).string
        XCTAssertEqual(textGuard.pageInUse, 2)
        _ = try XCTUnwrap(document.page(at: 1)).string
        XCTAssertEqual(textGuard.pageInUse, 2, "A refused page is never in use, so it can't be blamed again.")
        XCTAssertEqual(pages.seen, [], "A read can't trap: the supervisor's markers are for selections.")
    }

    func testAnalysisFinishesWithATextBlockedPage() throws {
        let document = try fixture()
        let textGuard = PageTextGuard(textBlocked: [1])
        textGuard.watch(document)
        let analysis = BookAnalyzer.analyze(document: document, outline: [])
        XCTAssertEqual(analysis?.pageCount, document.pageCount)
    }

    func testPageTextsOfATextBlockedPageReadAsEmpty() throws {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "book-chapters", withExtension: "pdf", subdirectory: "Fixtures"))
        // Two pages to a batch: each batch is a new document, and the guard must take each page's index from the document in hand.
        let pages = try XCTUnwrap(PageTextFile.extract(source: url, batch: 2, textGuard: PageTextGuard(textBlocked: [3])))
        XCTAssertEqual(pages.count, try fixture().pageCount)
        XCTAssertEqual(pages[3].text, "")
        XCTAssertFalse(pages[3].label.isEmpty)
        XCTAssertFalse(pages[2].text.isEmpty)
        XCTAssertFalse(pages[4].text.isEmpty)
    }

    func testAPageCopiedOutOfItsBookKeepsItsRefusal() throws {
        let document = try fixture()
        let textGuard = PageTextGuard(selectionBlocked: [2], textBlocked: [1])
        textGuard.watch(document)
        func copied(_ index: Int) throws -> (page: PDFPage, policy: CopiedPagePolicy, document: PDFDocument) {
            let source = try XCTUnwrap(document.page(at: index))
            let copy = try XCTUnwrap(source.copy() as? PDFPage)
            let policy = CopiedPagePolicy(copying: source), holder = PDFDocument()
            holder.delegate = policy
            holder.insert(copy, at: 0)
            return (copy, policy, holder)
        }

        let refused = try copied(1)
        XCTAssertNil(refused.page.string, "The copy keeps the page's class, and with it the refusal.")
        XCTAssertFalse(refused.document.admitsEveryPage)
        let trapping = try copied(2)
        XCTAssertNotNil(trapping.page.string)
        XCTAssertNil(trapping.page.selection(for: trapping.page.bounds(for: .cropBox)))
        let healthy = try copied(0)
        XCTAssertNotNil(healthy.page.selection(for: healthy.page.bounds(for: .cropBox)))
        XCTAssertTrue(healthy.document.admitsEveryPage)
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

    func testTextBlockedPagesAreKeptApartFromSelectionBlockedOnes() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = DocumentIndexRepository(root: root)
        try repository.addTextBlockedPages([440], id: "book")
        try repository.addSelectionBlockedPages([12], id: "book")
        XCTAssertEqual(repository.textBlockedPages("book"), [440])
        XCTAssertEqual(repository.selectionBlockedPages("book"), [12], "A page that traps keeps its text.")
        XCTAssertEqual(repository.textBlockedPages("another"), [])

        var clearance = repository.pageTextClearance("book")
        clearance.readAllPages()
        XCTAssertTrue(clearance.admitsText(12))
        XCTAssertFalse(clearance.admitsSelection(12))
        XCTAssertFalse(clearance.admitsText(440))
        XCTAssertFalse(clearance.admitsSelection(440))
    }

    func testAPagesTextWaitsForTheAnalysisAsItsSelectionsDo() {
        var clearance = PageTextClearance()
        XCTAssertFalse(clearance.admitsText(0), "The reader reads the page in view at once, and a page's text may never return.")
        clearance.read(pages: 4)
        XCTAssertTrue(clearance.admitsText(3))
        XCTAssertFalse(clearance.admitsText(4))

        clearance.blockText([440])
        clearance.readAllPages()
        XCTAssertFalse(clearance.admitsText(440), "Nothing clears a blocked page.")
        XCTAssertTrue(clearance.admitsText(441))
        XCTAssertFalse(clearance.admitsEveryPage, "PDFKit's own search must stay out of a book with such a page.")
    }

    func testNoPageIsClearedUntilTheAnalysisHasReadIt() {
        var clearance = PageTextClearance()
        XCTAssertFalse(clearance.admitsSelection(0), "The reader selects on the page in view at once, and a trap there would end Lemma.")
        XCTAssertTrue(clearance.isWaitingForPages)

        clearance.read(pages: 4)
        XCTAssertTrue(clearance.admitsSelection(3))
        XCTAssertFalse(clearance.admitsSelection(4))
        XCTAssertFalse(clearance.admitsEveryPage)

        clearance.read(pages: 1)
        XCTAssertTrue(clearance.admitsSelection(3), "A run that starts over reports fewer pages, and what was read still stands.")

        clearance.blockSelection([2])
        XCTAssertFalse(clearance.admitsSelection(2))
        clearance.readAllPages()
        XCTAssertFalse(clearance.admitsSelection(2), "Nothing clears a blocked page.")
        XCTAssertTrue(clearance.admitsSelection(500))
        XCTAssertFalse(clearance.isWaitingForPages)
        XCTAssertFalse(clearance.admitsEveryPage, "PDFKit's own selections must stay out of a book with a blocked page.")
    }

    func testABookWithNoBadPageAdmitsEveryPageOnceRead() {
        var clearance = PageTextClearance()
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
        PageInUseRecord(url: url).note(.init(book: "book", title: "Book", pageIndex: 12))
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        XCTAssertNil(PageInUseRecord.take(at: url), "A force quit or a power cut leaves a note: it must not cost a healthy page its selections.")
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path), "What the last run left is removed.")
    }

    func testANoteMarkedByATrapNamesThePage() throws {
        let url = recordURL()
        PageInUseRecord(url: url).note(.init(book: "book", title: "Book", pageIndex: 12))
        try FileManager.default.moveItem(at: url, to: url.appendingPathExtension("trapped"))
        XCTAssertEqual(PageInUseRecord.take(at: url), .init(book: "book", title: "Book", pageIndex: 12))
        XCTAssertNil(PageInUseRecord.take(at: url), "A page is reported once.")
    }

    func testAPageTheAppStoppedOnIsFoundAtTheNextLaunch() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let entry = PageInUseRecord.Entry(book: "book", title: "Book", pageIndex: 440)
        PageInUseRecord(url: url).markStopped(on: entry)
        XCTAssertEqual(PageInUseRecord.take(at: url), entry)
        XCTAssertNil(PageInUseRecord.take(at: url), "It is found once.")
    }

    func testTheStopNoticeNamesThePageAsTheReaderCountsIt() {
        let notice = PageInUseRecord.Entry(book: "book", title: "Elements", pageIndex: 440).stopNotice
        XCTAssertTrue(notice.contains("PDF page 441 of “Elements”"), notice)
    }

    func testBuildingAPagesTextTellsItsPolicyEitherSide() throws {
        final class Recorder: NSObject, PDFDocumentDelegate, PageTextPolicy {
            var calls: [String] = []
            func classForPage() -> AnyClass { TextGuardedPage.self }
            func admitsText(on page: PDFPage, in document: PDFDocument) -> Bool { true }
            func admitsSelection(on page: PDFPage, in document: PDFDocument) -> Bool { true }
            func admitsEveryPage(in document: PDFDocument) -> Bool { true }
            func willReadText(on page: PDFPage, in document: PDFDocument) {}
            func willSelect(on page: PDFPage, in document: PDFDocument) {}
            func willBuildText(on page: PDFPage, in document: PDFDocument) { calls.append("will") }
            func didBuildText(on page: PDFPage, in document: PDFDocument) { calls.append("did") }
        }
        let recorder = Recorder()
        let document = try XCTUnwrap(PDFDocument(url: try XCTUnwrap(Bundle.module.url(forResource: "article-numeric", withExtension: "pdf", subdirectory: "Fixtures"))))
        document.delegate = recorder
        _ = document.page(at: 0)?.string
        XCTAssertEqual(recorder.calls.first, "will")
        XCTAssertEqual(recorder.calls.last, "did")
        XCTAssertEqual(recorder.calls.filter { $0 == "will" }.count, recorder.calls.filter { $0 == "did" }.count)
    }

    func testANoteEndsSoonAfterTheLastSelection() {
        let url = recordURL()
        let record = PageInUseRecord(url: url, holdTime: 0.05)
        record.note(.init(book: "book", title: "Book", pageIndex: 3))
        Thread.sleep(forTimeInterval: 0.5)
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path), "Losing power long after a selection must leave nothing to read.")
    }

    func testANoteOutlastsPDFKitsMouseTracking() {
        let url = recordURL()
        let record = PageInUseRecord(url: url, holdTime: 0.05)
        record.note(.init(book: "book", title: "Book", pageIndex: 12))
        record.hold { Thread.sleep(forTimeInterval: 0.3) }
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path), "PDFKit selects for as long as the button is down, without asking the page.")
    }

    func testQuittingRemovesTheNote() {
        let url = recordURL()
        let record = PageInUseRecord(url: url)
        record.note(.init(book: "book", title: "Book", pageIndex: 12))
        record.remove()
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }

    func testRecoveryBlocksEachPageOnceAndStopsWhenAnotherRunCannotHelp() {
        var recovery = PageTextRecovery()
        XCTAssertFalse(recovery.blockSelection(nil), "A crash before any selection is not a page's.")
        XCTAssertTrue(recovery.blockSelection(12))
        XCTAssertFalse(recovery.blockSelection(12), "A blocked page cannot have caused the next crash.")
        XCTAssertEqual(recovery.selectionBlocked, [12])

        var full = PageTextRecovery()
        for page in 0..<PageTextRecovery.pageLimit { XCTAssertTrue(full.blockSelection(page)) }
        XCTAssertFalse(full.blockSelection(PageTextRecovery.pageLimit))
    }

    func testRecoveryBlamesThePageInUseOnlyWhenReadingAgainCanHelp() {
        XCTAssertEqual(PageTextRecovery.textPage(toBlock: 440, known: []), 440)
        XCTAssertNil(PageTextRecovery.textPage(toBlock: nil, known: []), "Memory taken before any text was read is not a page's.")
        XCTAssertNil(PageTextRecovery.textPage(toBlock: 440, known: [440]), "A refused page can't have taken it.")
        XCTAssertNil(PageTextRecovery.textPage(toBlock: 900, known: Set(0..<PageTextRecovery.pageLimit)))
    }

    func testMarkersAndTheBlockedPagesArgumentReadBack() {
        XCTAssertEqual(PageTextRecovery.pageIndex(inMarker: PageTextRecovery.marker(pageIndex: 957)), 957)
        XCTAssertNil(PageTextRecovery.pageIndex(inMarker: "progress 12 39"))
        XCTAssertNil(PageTextRecovery.pageIndex(inMarker: "done"))

        XCTAssertEqual(PageTextRecovery.pageIndex(inBlockedReport: PageTextRecovery.blockedReport(pageIndex: 957)), 957)
        XCTAssertNil(PageTextRecovery.pageIndex(inBlockedReport: "selecting 957"))
        XCTAssertEqual(PageTextRecovery.pageIndex(inTextBlockedReport: PageTextRecovery.textBlockedReport(pageIndex: 440)), 440)
        XCTAssertNil(PageTextRecovery.pageIndex(inTextBlockedReport: PageTextRecovery.blockedReport(pageIndex: 440)))
        XCTAssertNil(PageTextRecovery.pageIndex(inBlockedReport: PageTextRecovery.textBlockedReport(pageIndex: 440)))

        XCTAssertEqual(PageTextRecovery.argument(for: [957, 19]), "19,957")
        XCTAssertEqual(PageTextRecovery.pages(inArgument: "19,957"), [19, 957])
        XCTAssertEqual(PageTextRecovery.pages(inArgument: ""), [])
        XCTAssertNil(PageTextRecovery.pages(inArgument: "19,x"))
    }
}
