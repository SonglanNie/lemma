import XCTest
import AppKit
import PDFKit
import LemmaCore
@testable import Lemma

final class EditorDropTests: XCTestCase {
    @MainActor private func secondaryView(in view: NSView) -> SecondaryPDFView? {
        if let view = view as? SecondaryPDFView { return view }
        for child in view.subviews { if let found = secondaryView(in: child) { return found } }
        return nil
    }

    @MainActor
    func testNativePDFDropCallbacksOpenBothGroupsAndClearTheirPreview() async throws {
        let fixture = try WorkbenchFixture(hosted: true)
        defer { fixture.close() }
        let store = fixture.store
        store.open(fixture.book)
        try await fixture.settle(300)
        let main = try XCTUnwrap(store.reader.view)
        let mainID = try XCTUnwrap(store.workspace?.id)
        XCTAssertTrue(main.registeredDraggedTypes.contains(.string))
        let drop = NativePDFDrop(value: "lemma-book:\(mainID)", view: main, x: main.bounds.width * 0.9)
        defer { drop.draggingPasteboard.releaseGlobally() }
        XCTAssertEqual(main.draggingEntered(drop), .copy)
        XCTAssertEqual(store.mainPDFDropDestination, .side)
        main.draggingExited(drop)
        XCTAssertNil(store.mainPDFDropDestination)
        XCTAssertEqual(main.draggingUpdated(drop), .copy)
        XCTAssertTrue(main.prepareForDragOperation(drop))
        XCTAssertTrue(main.performDragOperation(drop))
        try await fixture.settle(300)
        XCTAssertNil(store.mainPDFDropDestination)
        XCTAssertEqual(store.split?.bookID, mainID)
        let side = try XCTUnwrap(secondaryView(in: fixture.window.contentView!))
        XCTAssertTrue(side.registeredDraggedTypes.contains(.string))
        let other = NativePDFDrop(value: fixture.paper.absoluteString, view: side, x: side.bounds.width * 0.2)
        defer { other.draggingPasteboard.releaseGlobally() }
        XCTAssertEqual(side.draggingEntered(other), .copy)
        XCTAssertEqual(store.sidePDFDropDestination, .side, "All of an existing side PDF is a side-group drop target.")
        XCTAssertTrue(side.prepareForDragOperation(other))
        XCTAssertTrue(side.performDragOperation(other))
        try await fixture.settle(200)
        XCTAssertNil(store.sidePDFDropDestination)
        XCTAssertEqual(store.workspace?.id, mainID)
        XCTAssertEqual(store.split?.title, "Paper")
        XCTAssertEqual(store.sideEditors.count, 2)
    }

    @MainActor
    func testSameLibraryPDFHasIndependentPagesAndZoomInBothStyles() async throws {
        let previousStyle = ThemeManager.shared.style
        defer { ThemeManager.shared.style = previousStyle }
        for style in [WorkbenchStyle.vscode, .classic] {
            ThemeManager.shared.style = style
            let fixture = try WorkbenchFixture(hosted: true)
            defer { fixture.close() }
            let store = fixture.store
            store.mainWindow = fixture.window
            store.open(fixture.book)
            try await fixture.settle(300)
            store.reader.goToPage(3)
            try await fixture.settle(100)
            let bookID = try XCTUnwrap(store.workspace?.id)
            let noteID = store.selectedNoteID
            XCTAssertTrue(store.openEditorDrop("lemma-book:\(bookID)", toSide: true))
            try await fixture.settle(300)
            let main = try XCTUnwrap(store.reader.view)
            let side = try XCTUnwrap(secondaryView(in: fixture.window.contentView!))
            XCTAssertTrue(side.document === main.document)
            XCTAssertEqual(store.split?.bookID, bookID)
            XCTAssertEqual(store.selectedNoteID, noteID)
            XCTAssertFalse(store.showStudy, "The notebook steps aside to make room for two PDFs.")
            let mainPage = main.currentPage
            let mainScale = main.scaleFactor
            side.go(to: try XCTUnwrap(side.document?.page(at: 4)))
            side.scaleFactor = 0.73
            // The side editor writes its place once the scrolling stops (0.35 s).
            try await fixture.settle(600)
            XCTAssertTrue(main.currentPage === mainPage, "Navigating the second view must keep the first view's page.")
            XCTAssertEqual(main.scaleFactor, mainScale, accuracy: 0.001)
            XCTAssertEqual(store.split?.scale ?? 0, 0.73, accuracy: 0.001)
            XCTAssertGreaterThan(store.split?.pageIndex ?? 0, 2)
            let sideID = try XCTUnwrap(store.activeSideEditorID)
            store.openBookToTheSide(bookID)
            XCTAssertEqual(store.activeSideEditorID, sideID, "Dropping it again brings its existing side tab forward.")
            let savedPage = try XCTUnwrap(store.split?.pageIndex)
            XCTAssertTrue(store.openEditorDrop(fixture.paper.absoluteString, toSide: true))
            try await fixture.settle(150)
            let paperSideID = try XCTUnwrap(store.activeSideEditorID)
            store.activateSideEditor(sideID)
            try await fixture.settle(150)
            let returned = try XCTUnwrap(secondaryView(in: fixture.window.contentView!))
            XCTAssertEqual(returned.scaleFactor, 0.73, accuracy: 0.001)
            XCTAssertEqual(returned.document?.index(for: try XCTUnwrap(returned.currentDestination?.page)), savedPage)
            store.closeSideEditor(paperSideID)
            store.closeSideEditor(sideID)
            XCTAssertTrue(store.showStudy, "Closing the split restores the notebook.")
        }
    }

    @MainActor
    func testUnopenedLibraryPDFLoadsBesideShorterBookAndRestoresItsOwnViewport() async throws {
        let previousStyle = ThemeManager.shared.style
        defer { ThemeManager.shared.style = previousStyle }
        ThemeManager.shared.style = .vscode
        let fixture = try WorkbenchFixture(hosted: true)
        defer { fixture.close() }
        let store = fixture.store
        store.open(fixture.paper)
        try await fixture.settle(300)
        let mainID = try XCTUnwrap(store.workspace?.id)
        XCTAssertTrue(store.openEditorDrop(fixture.book.absoluteString, toSide: true))
        try await fixture.settle(300)
        XCTAssertEqual(store.workspace?.id, mainID)
        XCTAssertEqual(store.tabs.count, 1, "Opening to the side keeps the active main tab.")
        XCTAssertEqual(store.library.count, 2, "A discovered PDF gets its own durable workspace when opened.")
        let side = try XCTUnwrap(secondaryView(in: fixture.window.contentView!))
        side.scaleFactor = 0.64
        side.go(to: try XCTUnwrap(side.document?.page(at: 4)))
        // The side editor writes its place once the scrolling stops (0.35 s).
        try await fixture.settle(600)
        let saved = try XCTUnwrap(store.split)
        XCTAssertGreaterThan(saved.pageIndex, 1, "The side PDF is on a page the short main PDF does not have.")
        store.flush()
        let restarted = StudyStore(root: store.repository.root)
        restarted.restore()
        XCTAssertEqual(restarted.workspace?.id, mainID)
        XCTAssertEqual(restarted.split, saved, "Restoration validates the page against the side PDF's own page count.")
        let restored = SecondaryPDFView(frame: NSRect(x: 0, y: 0, width: 500, height: 650))
        restored.document = try XCTUnwrap(restarted.sideDocument(for: saved))
        restored.displayMode = .singlePageContinuous
        restored.show(saved)
        restored.layout()
        XCTAssertEqual(restored.scaleFactor, 0.64, accuracy: 0.001)
        XCTAssertEqual(restored.document?.index(for: try XCTUnwrap(restored.currentDestination?.page)), saved.pageIndex)
    }

    @MainActor
    func testMainDropsOpenTheRequestedPDFAndUnrelatedTextDoesNothing() throws {
        let fixture = try WorkbenchFixture()
        defer { fixture.close() }
        let store = fixture.store
        XCTAssertTrue(store.openEditorDrop(fixture.paper.absoluteString, toSide: true))
        XCTAssertEqual(store.workspace?.title, "Paper", "A first PDF opens in the main group when there is nothing to split.")
        XCTAssertTrue(store.sideEditors.isEmpty)
        let paperID = try XCTUnwrap(store.workspace?.id)
        XCTAssertTrue(store.openEditorDrop(fixture.book.absoluteString, toSide: false))
        XCTAssertEqual(store.workspace?.title, "Synthetic Book")
        XCTAssertTrue(store.openEditorDrop("lemma-tab:\(paperID)", toSide: false))
        XCTAssertEqual(store.workspace?.id, paperID)
        XCTAssertFalse(store.openEditorDrop("Unrelated text", toSide: true))
        XCTAssertFalse(store.openEditorDrop("lemma-side:map", toSide: true))
        XCTAssertEqual(store.workspace?.id, paperID)
        XCTAssertTrue(store.sideEditors.isEmpty)
    }
}

/// Drives PDFKit's real destination callbacks with a private pasteboard, without OS pointer injection.
@MainActor private final class NativePDFDrop: NSObject, NSDraggingInfo {
    let draggingPasteboard = NSPasteboard.withUniqueName()
    let draggingDestinationWindow: NSWindow?
    let draggingLocation: NSPoint
    let draggingSourceOperationMask: NSDragOperation = .copy
    var draggedImageLocation: NSPoint { draggingLocation }
    nonisolated var draggedImage: NSImage? { nil }
    var draggingSource: Any? { nil }
    let draggingSequenceNumber = 1
    var draggingFormation: NSDraggingFormation = .none
    var animatesToDestination = false
    var numberOfValidItemsForDrop = 1
    var springLoadingHighlight: NSSpringLoadingHighlight { .none }

    init(value: String, view: NSView, x: CGFloat) {
        draggingDestinationWindow = view.window
        draggingLocation = view.convert(CGPoint(x: x, y: view.bounds.midY), to: nil)
        super.init()
        draggingPasteboard.setString(value, forType: .string)
    }

    func slideDraggedImage(to screenPoint: NSPoint) {}
    nonisolated override func namesOfPromisedFilesDropped(atDestination dropDestination: URL) -> [String]? { nil }
    func resetSpringLoading() {}
    func enumerateDraggingItems(options: NSDraggingItemEnumerationOptions, for view: NSView?, classes: [AnyClass],
                                searchOptions: [NSPasteboard.ReadingOptionKey: Any],
                                using block: (NSDraggingItem, Int, UnsafeMutablePointer<ObjCBool>) -> Void) {}
}
