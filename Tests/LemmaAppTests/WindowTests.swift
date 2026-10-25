import XCTest
import PDFKit
@testable import Lemma

/// Tabs moving between the windows of one library.
final class WindowTests: XCTestCase {
    @MainActor
    func testMovingABookToAnotherWindowHandsOverItsDocumentAndShowsTheNeighbour() throws {
        let fixture = try WorkbenchFixture()
        defer { fixture.close() }
        let first = fixture.store
        first.open(fixture.book); let bookID = try XCTUnwrap(first.workspace?.id)
        first.open(fixture.paper); let paperID = try XCTUnwrap(first.workspace?.id)
        first.activateTab(bookID)
        first.workspace?.reading.pageIndex = 2
        let document = try XCTUnwrap(first.document)
        let second = StudyStore(app: first.app, windowID: UUID())
        XCTAssertTrue(second.dropBookTab(["lemma-tab:\(bookID)"], onto: nil))
        XCTAssertEqual(first.tabs.map(\.id), [paperID])
        XCTAssertEqual(first.workspace?.id, paperID, "The neighbouring tab takes the moved book's place.")
        XCTAssertEqual(second.tabs.map(\.id), [bookID])
        XCTAssertEqual(second.workspace?.id, bookID)
        XCTAssertTrue(second.document === document, "The document comes along rather than being read again.")
        XCTAssertEqual(second.workspace?.reading.pageIndex, 2, "The reading position comes along, though each window keeps its own.")
        XCTAssertTrue(first.app.owner(of: bookID) === second)
    }

    @MainActor
    func testMovingABookToAWindowThatShowsItKeepsThatWindowsPosition() throws {
        let fixture = try WorkbenchFixture()
        defer { fixture.close() }
        let first = fixture.store
        first.open(fixture.book); let bookID = try XCTUnwrap(first.workspace?.id)
        first.open(fixture.paper); let paperID = try XCTUnwrap(first.workspace?.id)
        first.activateTab(bookID)
        first.workspace?.reading.pageIndex = 2
        let second = StudyStore(app: first.app, windowID: UUID())
        second.open(fixture.book)
        XCTAssertEqual(second.tabs.map(\.id), [bookID])
        let document = try XCTUnwrap(second.document)
        second.workspace?.reading.pageIndex = 1
        first.app.moveBook(bookID, from: first, to: second)
        XCTAssertEqual(first.tabs.map(\.id), [paperID])
        XCTAssertEqual(second.tabs.map(\.id), [bookID], "The book has one tab here, not two.")
        XCTAssertTrue(second.document === document)
        XCTAssertEqual(second.workspace?.reading.pageIndex, 1)
    }

    @MainActor
    func testOpeningABookWithEveryWindowClosedAsksForItsWindow() throws {
        let fixture = try WorkbenchFixture()
        let app = fixture.store.app
        defer { app.prepareForTermination(); fixture.close() }
        let store = app.claimWindow(nil)
        var requested: [UUID] = []
        app.openWindow = { requested.append($0) }
        store.open(fixture.book)
        XCTAssertTrue(requested.isEmpty, "The book opens in the window that is there.")
        store.closeBook()
        store.hasWindow = false
        store.open(fixture.paper)
        XCTAssertEqual(requested, [store.windowID])
    }

    @MainActor
    func testANewWindowKeepsTheLayoutOfTheWindowItComesFrom() throws {
        let fixture = try WorkbenchFixture()
        let app = fixture.store.app
        defer { app.prepareForTermination(); fixture.close() }
        let first = app.claimWindow(nil)
        first.open(fixture.book)
        first.open(fixture.paper); let paperID = try XCTUnwrap(first.workspace?.id)
        first.showLibrary = false; first.showStudy = false; first.showPanel = true; first.panelTab = .console
        first.workbenchLayout.inspectorWidth = 412; first.workbenchLayout.activityBar = false

        func assertSameLayout(_ store: StudyStore, _ message: String) {
            XCTAssertEqual(store.showLibrary, first.showLibrary, message)
            XCTAssertEqual(store.showStudy, first.showStudy, message)
            XCTAssertEqual(store.showPanel, first.showPanel, message)
            XCTAssertEqual(store.panelTab, first.panelTab, message)
            XCTAssertEqual(store.workbenchLayout, first.workbenchLayout, message)
        }
        assertSameLayout(app.newWindow(), "File › New Window")
        app.moveBookToNewWindow(paperID, from: first)
        let moved = try XCTUnwrap(app.owner(of: paperID))
        assertSameLayout(moved, "A tab dragged out")
        XCTAssertTrue(moved.specialTabs.isEmpty, "The window has its book, so no Welcome page.")
    }

    @MainActor
    func testWindowsAndTheirTabsSurviveRestart() throws {
        let fixture = try WorkbenchFixture()
        let before = fixture.store.app
        defer { before.prepareForTermination(); fixture.close() }
        let first = before.claimWindow(nil)
        first.open(fixture.book); let bookID = try XCTUnwrap(first.workspace?.id)
        first.open(fixture.paper); let paperID = try XCTUnwrap(first.workspace?.id)
        before.moveBookToNewWindow(paperID, from: first)
        let second = try XCTUnwrap(before.owner(of: paperID))
        XCTAssertFalse(second === first)
        XCTAssertEqual(second.workspace?.id, paperID)
        XCTAssertEqual(first.tabs.map(\.id), [bookID])
        first.flush(); second.flush()

        let app = AppModel(root: first.repository.root)
        app.restoreWindows()
        defer { app.prepareForTermination() }
        XCTAssertEqual(app.window(first.windowID)?.tabs.map(\.id), [bookID])
        XCTAssertEqual(app.window(second.windowID)?.tabs.map(\.id), [paperID])
        XCTAssertEqual(app.window(second.windowID)?.workspace?.id, paperID)
    }
}
