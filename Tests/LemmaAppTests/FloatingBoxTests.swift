import XCTest
import AppKit
import PDFKit
import LemmaCore
@testable import Lemma

/// Floating boxes: boxes of a page in windows of their own, kept when their book closes and across relaunches.
final class FloatingBoxTests: XCTestCase {
    @MainActor
    func testFloatingBoxesOutliveTheirBookAndAreRestored() throws {
        let fixture = try WorkbenchFixture()
        defer { fixture.close() }
        let store = fixture.store, floating = store.app.floatingBoxes
        store.open(fixture.book)
        let bookID = try XCTUnwrap(store.workspace?.id), page = try XCTUnwrap(store.document?.page(at: 1))
        let box = FloatingBox(bookID: bookID, pageIndex: 1, region: PageRegion(x: 40, y: 200, width: 220, height: 120),
                              title: "Figure 1.1", frame: CGRect(x: 200, y: 300, width: 440, height: 240))
        floating.add(box, page: page)
        XCTAssertEqual(floating.boxes, [box])

        store.closeBook()
        store.flush()
        XCTAssertEqual(floating.boxes.count, 1, "A box stays open when its book closes.")

        floating.setHidden(true)
        let restarted = AppModel(root: store.repository.root)
        restarted.restore()
        XCTAssertEqual(restarted.floatingBoxes.boxes, [box], "Relaunching brings the box back where it was.")
        XCTAssertTrue(restarted.floatingBoxes.hidden, "Hide All is remembered.")
        let restored = try XCTUnwrap(restarted.floatingBoxes.panels[box.id]?.boxView.document?.page(at: 0))
        XCTAssertEqual(restored.bounds(for: .cropBox), box.region.rect, "With its book closed, the box copied its page from the PDF.")
        restarted.floatingBoxes.closeAll()
        XCTAssertTrue(restarted.floatingBoxes.boxes.isEmpty)

        floating.closeAll()
        XCTAssertTrue(floating.boxes.isEmpty)
    }

    @MainActor
    func testANewBoxBringsBackHiddenBoxes() throws {
        let fixture = try WorkbenchFixture()
        defer { fixture.close() }
        let store = fixture.store, floating = store.app.floatingBoxes
        store.open(fixture.book)
        let bookID = try XCTUnwrap(store.workspace?.id), page = try XCTUnwrap(store.document?.page(at: 0))
        func box() -> FloatingBox {
            FloatingBox(bookID: bookID, pageIndex: 0, region: PageRegion(x: 40, y: 200, width: 220, height: 120), title: "Box", frame: CGRect(x: 200, y: 300, width: 220, height: 120))
        }
        floating.add(box(), page: page)
        floating.setHidden(true)
        XCTAssertEqual(store.floatMenuItems.map(\.title), ["Draw a Box…", "", "Show All", "Close All"])
        floating.add(box(), page: page)
        XCTAssertFalse(floating.hidden, "Drawing a box shows the others again.")
        XCTAssertEqual(floating.boxes.count, 2)
        floating.closeAll()
    }

    @MainActor
    func testTheBoxFillsItsWindowAndZoomsWithinIt() throws {
        let fixture = try WorkbenchFixture()
        defer { fixture.close() }
        fixture.store.open(fixture.book)
        let page = try XCTUnwrap(fixture.store.document?.page(at: 0))
        let box = FloatingBox(bookID: "book", pageIndex: 0, region: PageRegion(x: 40, y: 200, width: 220, height: 120), title: "Box", frame: .zero)
        let view = try XCTUnwrap(FloatingBoxView(box: box, page: page))
        view.frame = CGRect(x: 0, y: 0, width: 440, height: 240)
        view.layoutSubtreeIfNeeded()
        XCTAssertEqual(view.scaleFactor, 2, accuracy: 0.01, "The box fills the window: twice its size in a window twice as large.")
        view.frame = CGRect(x: 0, y: 0, width: 660, height: 360)
        view.layoutSubtreeIfNeeded()
        XCTAssertEqual(view.scaleFactor, 3, accuracy: 0.01, "Resizing the window scales the box.")
        view.zoom(by: 1.25)
        XCTAssertEqual(view.scaleFactor, 3.75, accuracy: 0.01)
        view.zoom(by: 0.1)
        XCTAssertEqual(view.zoom, 1, "The box is never smaller than its window.")
        view.zoom(by: 2); view.zoom(by: 0)
        XCTAssertEqual(view.scaleFactor, 3, accuracy: 0.01, "⌘0 returns to the whole box.")
    }

    @MainActor
    func testCommandScrollZoomsTheBoxWithinItsWindow() throws {
        let fixture = try WorkbenchFixture()
        defer { fixture.close() }
        fixture.store.open(fixture.book)
        let page = try XCTUnwrap(fixture.store.document?.page(at: 0))
        let box = FloatingBox(bookID: "book", pageIndex: 0, region: PageRegion(x: 40, y: 200, width: 220, height: 120), title: "Box", frame: .zero)
        let view = try XCTUnwrap(FloatingBoxView(box: box, page: page))
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 440, height: 240), styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = view
        defer { window.close() }
        view.layoutSubtreeIfNeeded()
        var saved: Double?
        view.onZoom = { saved = $0 }
        let middle = CGPoint(x: view.bounds.midX, y: view.bounds.midY)
        for _ in 0..<5 { view.scrollWheel(with: try scrollEvent(1, at: middle, in: view)) }
        XCTAssertEqual(view.zoom, pow(ScrollZoom.step, 5), accuracy: 0.01, "⌘-scroll zooms into the box.")
        XCTAssertNil(saved, "The box keeps its zoom once the wheel stops.")
        ScrollZoom.end()
        XCTAssertEqual(saved ?? 0, Double(view.zoom), accuracy: 0.001, "The zoom is kept with the box.")
        for _ in 0..<10 { view.scrollWheel(with: try scrollEvent(-1, at: middle, in: view)) }
        ScrollZoom.end()
        XCTAssertEqual(view.zoom, 1, "The box is never smaller than its window.")
        XCTAssertEqual(view.scaleFactor, 2, accuracy: 0.01)
    }

    @MainActor
    func testTheBoxHoldsOnlyItsPartOfThePage() throws {
        let fixture = try WorkbenchFixture()
        defer { fixture.close() }
        fixture.store.open(fixture.book)
        let page = try XCTUnwrap(fixture.store.document?.page(at: 0))
        let pageBox = page.bounds(for: .cropBox)
        let region = CGRect(x: 40, y: 200, width: 220, height: 120)
        let view = try XCTUnwrap(FloatingBoxView(box: FloatingBox(bookID: "book", pageIndex: 0, region: PageRegion(region), title: "Box", frame: .zero), page: page))
        let copy = try XCTUnwrap(view.document?.page(at: 0))
        XCTAssertEqual(view.document?.pageCount, 1)
        XCTAssertEqual(copy.bounds(for: .cropBox), region, "Nothing outside the box is there to scroll or zoom to.")
        XCTAssertTrue(copy is ThemedPage, "The box draws in the page theme.")
        XCTAssertEqual(page.bounds(for: .cropBox), pageBox, "The book's page is left whole.")
        XCTAssertTrue(page.document === fixture.store.document)
    }

    @MainActor
    func testShiftCommandDragFloatsABoxFromTheSideEditor() throws {
        let fixture = try WorkbenchFixture()
        defer { fixture.close() }
        fixture.store.open(fixture.book)
        let document = try XCTUnwrap(fixture.store.document), page = try XCTUnwrap(document.page(at: 0))
        let view = SecondaryPDFView(frame: CGRect(x: 0, y: 0, width: 600, height: 800))
        view.displayMode = .singlePage
        view.document = document
        view.autoScales = true
        let window = NSWindow(contentRect: view.frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = view
        defer { window.close() }
        view.layoutDocumentView()
        var floated: (Int, CGRect)?
        view.onFloatBox = { floated = ($0, $1) }
        func event(_ type: NSEvent.EventType, at pagePoint: CGPoint, _ modifiers: NSEvent.ModifierFlags) throws -> NSEvent {
            try XCTUnwrap(NSEvent.mouseEvent(with: type, location: view.convert(view.convert(pagePoint, from: page), to: nil), modifierFlags: modifiers,
                                             timestamp: 0, windowNumber: window.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 1))
        }
        func drag(_ modifiers: NSEvent.ModifierFlags) throws {
            view.mouseDown(with: try event(.leftMouseDown, at: CGPoint(x: 40, y: 200), modifiers))
            view.mouseDragged(with: try event(.leftMouseDragged, at: CGPoint(x: 260, y: 320), modifiers))
            XCTAssertNotNil(view.boxOutline.superview, "The box is outlined while it is dragged.")
            view.mouseUp(with: try event(.leftMouseUp, at: CGPoint(x: 260, y: 320), modifiers))
            XCTAssertNil(view.boxOutline.superview)
        }

        try drag(.command)
        XCTAssertNil(floated, "⌘-drag alone opens nothing from the side editor.")
        try drag([.command, .shift])
        XCTAssertEqual(floated?.0, 0)
        XCTAssertEqual(floated?.1.width ?? 0, 220, accuracy: 0.5)
        XCTAssertEqual(floated?.1.height ?? 0, 120, accuracy: 0.5)
    }

    func testSessionsSavedBeforeFloatingBoxesStillLoad() throws {
        let saved = Data(#"{"windows": [], "books": {}}"#.utf8)
        let session = try JSONDecoder().decode(WorkbenchSession.self, from: saved)
        XCTAssertTrue(session.floatingBoxes.isEmpty)
        XCTAssertFalse(session.floatingBoxesHidden)
    }

    @MainActor
    func testTheSplitButtonMenuShowsEachWayAndItsShortcut() throws {
        let fixture = try WorkbenchFixture()
        defer { fixture.close() }
        let store = fixture.store
        store.open(fixture.book)
        XCTAssertEqual(store.splitMenuItems.map(\.title), ["This Page", "Selection", "Draw a Box…"])
        XCTAssertEqual(store.splitMenuItems.map(\.shortcut), ["⌘\\", nil, "⌘-drag"])
        XCTAssertFalse(store.splitMenuItems[1].enabled, "Selection needs a selection.")
        store.toggleSplit()
        XCTAssertEqual(store.splitMenuItems.map(\.title), ["This Page", "Selection", "Draw a Box…", "", "Close Side Editor"])
        let menu = NativeMenu.make(store.splitMenuItems)
        XCTAssertEqual(menu.items[2].attributedTitle?.string, "Draw a Box…\t⌘-drag", "A gesture is written after the title.")
        XCTAssertEqual(menu.items[4].attributedTitle?.string, "Close Side Editor\t⌘\\", "Beside a gesture, keys are written in the same column.")
    }
}
