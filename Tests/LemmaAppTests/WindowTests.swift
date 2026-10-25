import XCTest
import PDFKit
@testable import Lemma

/// Several windows, each with its own workbench, sharing one library; a book is open in one window at a time.
final class WindowTests: XCTestCase {
    @MainActor
    func testMovingABookToAnotherWindowHandsOverItsDocumentAndShowsTheNeighbour() throws {
        let fixture = try WorkbenchFixture()
        defer { fixture.close() }
        let first = fixture.store
        first.open(fixture.book); let bookID = try XCTUnwrap(first.workspace?.id)
        first.open(fixture.paper); let paperID = try XCTUnwrap(first.workspace?.id)
        first.activateTab(bookID)
        let document = try XCTUnwrap(first.document)
        let second = StudyStore(app: first.app)
        XCTAssertTrue(second.dropBookTab(["lemma-tab:\(bookID)"], onto: nil))
        XCTAssertEqual(first.tabs.map(\.id), [paperID])
        XCTAssertEqual(first.workspace?.id, paperID, "The neighbouring tab takes the moved book's place.")
        XCTAssertEqual(second.tabs.map(\.id), [bookID])
        XCTAssertEqual(second.workspace?.id, bookID)
        XCTAssertTrue(second.document === document, "The document comes along rather than being read again.")
        XCTAssertTrue(first.app.owner(of: bookID) === second)
    }

    @MainActor
    func testOpeningABookOpenInAnotherWindowShowsItThere() throws {
        let fixture = try WorkbenchFixture()
        defer { fixture.close() }
        let first = fixture.store
        first.open(fixture.book); let bookID = try XCTUnwrap(first.workspace?.id)
        let second = StudyStore(app: first.app)
        var shownIn: StudyStore?
        second.reopenBook(try XCTUnwrap(first.library.first { $0.id == bookID })) { shownIn = $0 }
        XCTAssertTrue(shownIn === first, "The book is shown in the window it is open in.")
        XCTAssertTrue(second.tabs.isEmpty, "No second copy of the book is opened.")
        XCTAssertTrue(first.app.front === first)
        second.open(fixture.book)
        XCTAssertTrue(second.tabs.isEmpty, "Opening its file again also goes to its window.")
    }

    @MainActor
    func testANewWindowKeepsTheLayoutOfTheWindowItComesFrom() throws {
        let fixture = try WorkbenchFixture()
        defer { fixture.close() }
        let first = fixture.store
        first.open(fixture.book)
        first.open(fixture.paper); let paperID = try XCTUnwrap(first.workspace?.id)
        first.showLibrary = false; first.showStudy = false; first.showPanel = true; first.panelTab = .console
        first.workbenchLayout.inspectorWidth = 412; first.workbenchLayout.activityBar = false
        let layout = first.windowSession

        func assertSameLayout(_ store: StudyStore, _ message: String) {
            XCTAssertEqual(store.showLibrary, layout.showLibrary, message)
            XCTAssertEqual(store.showStudy, layout.showStudy, message)
            XCTAssertEqual(store.showPanel, layout.showPanel, message)
            XCTAssertEqual(store.panelTab, layout.panelTab, message)
            XCTAssertEqual(store.workbenchLayout, layout.layout, message)
        }
        assertSameLayout(first.app.newWindow(), "File › New Window")
        first.app.moveBookToNewWindow(paperID)
        assertSameLayout(try XCTUnwrap(first.app.owner(of: paperID)), "A tab dragged out")
    }

    @MainActor
    func testWindowsAndTheirTabsSurviveRestart() throws {
        let fixture = try WorkbenchFixture()
        defer { fixture.close() }
        let first = fixture.store
        first.open(fixture.book); let bookID = try XCTUnwrap(first.workspace?.id)
        first.open(fixture.paper); let paperID = try XCTUnwrap(first.workspace?.id)
        first.app.moveBookToNewWindow(paperID)
        let second = try XCTUnwrap(first.app.windows.last)
        XCTAssertFalse(second === first)
        XCTAssertEqual(second.workspace?.id, paperID)
        XCTAssertEqual(first.tabs.map(\.id), [bookID])
        first.flush(); second.flush()

        let app = AppModel(root: first.repository.root)
        app.restore()
        XCTAssertEqual(app.windows.count, 2)
        XCTAssertEqual(app.windows.map(\.id), [first.id, second.id])
        XCTAssertEqual(app.windows[0].tabs.map(\.id), [bookID])
        XCTAssertEqual(app.windows[0].workspace?.id, bookID)
        XCTAssertEqual(app.windows[1].tabs.map(\.id), [paperID])
        XCTAssertEqual(app.windows[1].workspace?.id, paperID)
        app.windows.forEach { $0.flush() }
    }

    @MainActor
    func testABookSavedInTwoWindowsIsRestoredInTheFirstOnly() throws {
        let fixture = try WorkbenchFixture()
        defer { fixture.close() }
        let store = fixture.store
        store.open(fixture.book); let bookID = try XCTUnwrap(store.workspace?.id)
        store.flush()
        var session = try JSONDecoder().decode(WorkbenchSession.self, from: Data(contentsOf: store.app.sessionURL))
        var copy = try XCTUnwrap(session.windows.first); copy.id = UUID()
        session.windows.append(copy)
        try JSONEncoder().encode(session).write(to: store.app.sessionURL)

        let app = AppModel(root: store.repository.root)
        app.restore()
        XCTAssertEqual(app.windows.count, 2)
        XCTAssertEqual(app.windows[0].tabs.map(\.id), [bookID])
        XCTAssertTrue(app.windows[1].tabs.isEmpty, "A book is open in one window at a time.")
        app.windows.forEach { $0.flush() }
    }

    @MainActor
    func testBringingAWindowForwardMakesTheMenusActOnIt() throws {
        let fixture = try WorkbenchFixture()
        defer { fixture.close() }
        let first = fixture.store
        let second = StudyStore(app: first.app)
        XCTAssertTrue(first.app.front === first)
        first.app.show(second)
        XCTAssertTrue(first.app.front === second, "Bringing a window forward makes the menus act on it.")
    }
}
