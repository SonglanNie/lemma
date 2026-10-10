import XCTest
import AppKit
import PDFKit
import SwiftUI
import LemmaCore
@testable import Lemma

final class DefinitionLookupTests: XCTestCase {
    @MainActor
    func testHostedReaderPresentsAndDismissesDefinitionLookup() async throws {
        _ = NSApplication.shared
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let previous = UserDefaults.standard.object(forKey: "lastWorkspaceID")
        defer { UserDefaults.standard.set(previous, forKey: "lastWorkspaceID") }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let source = root.appendingPathComponent("source.pdf")
        try Self.sourcePDF().write(to: source)
        let store = StudyStore(root: root.appendingPathComponent("support")); store.open(source)
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 1100, height: 750), styleMask: .titled, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: ReaderWindow(store: store))
        defer { store.definitionLookup = nil; window.close() }
        window.orderFront(nil)
        window.contentView?.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(150))
        let previouslyVisible = Set(NSApp.windows.filter(\.isVisible).map(\.windowNumber))
        store.lookupSelection()
        try await Task.sleep(for: .milliseconds(300))
        let popup = NSApp.windows.first { $0.isVisible && !previouslyVisible.contains($0.windowNumber) }
        XCTAssertNotNil(store.definitionLookup)
        XCTAssertNotNil(popup, "The hosted reader must present an actual definition window, not only update lookup state.")
        store.definitionLookup = nil
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertFalse(popup?.isVisible == true)
        store.lookupDefinition("X", pageIndex: 0, region: CGRect(x: 20, y: 80, width: 18, height: 25))
        XCTAssertTrue(store.reader.view?.definitionPopover?.popover.isShown == true)
        store.reader.view?.definitionPopover?.popover.close()
        XCTAssertNil(store.definitionLookup, "Native dismissal must clear the request so the same term can reopen.")
    }

    @MainActor
    func testLookupInspectionPreservesNotebookAndReading() throws {
        _ = NSApplication.shared
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let oldLastWorkspace = UserDefaults.standard.object(forKey: "lastWorkspaceID")
        defer { UserDefaults.standard.set(oldLastWorkspace, forKey: "lastWorkspaceID") }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let source = root.appendingPathComponent("definitions.pdf")
        let originalBytes = try Self.sourcePDF()
        try originalBytes.write(to: source)
        let store = StudyStore(root: root.appendingPathComponent("support"))
        store.open(source)
        let document = try XCTUnwrap(store.document)
        let view = RegionPDFView(frame: CGRect(x: 0, y: 0, width: 600, height: 700))
        view.controller = store.reader; store.reader.view = view; view.document = document
        view.displayMode = .singlePage; view.autoScales = true
        let window = NSWindow(contentRect: view.frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.contentView = view
        defer { window.close() }
        view.layoutDocumentView(); view.layoutSubtreeIfNeeded()
        store.reader.selection = (0, CGRect(x: 15, y: 70, width: 250, height: 40), "X is the design matrix")
        store.reader.hasSelection = true
        store.addNote(kind: .notation)
        let definitionID = try XCTUnwrap(store.currentNote?.id)
        store.updateNote {
            $0.question = "Design matrix"; $0.lookupTerms = "X\ndesign matrix"
            $0.notation = "n × p"; $0.scope = "This chapter"; $0.body = "Rows are observations."
        }
        store.reader.selection = (1, CGRect(x: 20, y: 70, width: 230, height: 40), "X is used here")
        store.reader.hasSelection = true
        store.addNote()
        store.updateNote { $0.question = "My working question"; $0.body = "Keep this unfinished reasoning." }
        store.noteQuery = "working"; store.noteFilter = .open
        store.reader.goToPage(2); store.reader.updatePage()
        let selectedNote = store.currentNote
        let page = store.reader.pageNumber
        let scale = view.scaleFactor
        let destination = try XCTUnwrap(view.currentDestination)
        store.reader.selection = (1, CGRect(x: 20, y: 70, width: 20, height: 40), "X")

        store.lookupSelection()

        XCTAssertEqual(store.studySection, .notes, "Consulting a definition must keep the working notebook section.")
        XCTAssertEqual(store.noteQuery, "working", "Definition lookup needs its own query.")
        XCTAssertEqual(store.noteFilter, .open)
        XCTAssertEqual(store.currentNote, selectedNote)
        XCTAssertEqual(store.reader.pageNumber, page)
        XCTAssertEqual(view.scaleFactor, scale)
        XCTAssertEqual(view.currentDestination?.point, destination.point)
        let request = try XCTUnwrap(store.definitionLookup)
        XCTAssertEqual(request.query, "X"); XCTAssertEqual(request.pageIndex, 1)
        XCTAssertEqual(DefinitionLookup.find(request.query, in: try XCTUnwrap(store.workspace?.notes), near: request.pageIndex).map(\.id), [definitionID])
        XCTAssertFalse(store.preparedPrompt.contains("Rows are observations."), "Looking up an entry must not add it to a provider packet.")

        store.definitionLookup = nil
        store.reader.hasSelection = false; store.reader.selection = nil
        store.toggleFocus()
        let sourcePage = try XCTUnwrap(document.page(at: 1))
        let wordBounds = try XCTUnwrap(sourcePage.selection(for: NSRange(location: 0, length: 1))).bounds(for: sourcePage)
        let point = view.convert(CGPoint(x: wordBounds.midX, y: wordBounds.midY), from: sourcePage)
        let commandClick = try XCTUnwrap(NSEvent.mouseEvent(with: .leftMouseDown, location: view.convert(point, to: nil),
            modifierFlags: .command, timestamp: 0, windowNumber: window.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 1))
        view.mouseDown(with: commandClick)
        XCTAssertEqual(store.definitionLookup?.query, "X")
        XCTAssertEqual(store.definitionLookup?.pageIndex, 1)
        XCTAssertTrue(store.focusMode); XCTAssertFalse(store.showStudy); XCTAssertFalse(store.showLibrary)
        XCTAssertEqual(store.currentNote, selectedNote); XCTAssertEqual(store.noteQuery, "working")
        XCTAssertEqual(store.reader.pageNumber, page); XCTAssertEqual(view.currentDestination?.point, destination.point)
        XCTAssertFalse(store.reader.hasSelection, "Command lookup must leave ordinary PDF selection alone.")

        store.definitionLookup = nil
        store.lookupSelection()
        XCTAssertEqual(store.definitionLookup?.query, "", "Keyboard lookup without selectable text must allow a typed term for a scan.")
        XCTAssertNil(store.definitionLookup?.region)
        store.open(source)
        XCTAssertNil(store.definitionLookup, "A lookup must close when another document is opened.")
        XCTAssertEqual(store.workspace?.notes.first { $0.id == definitionID }?.lookupTerms, "X\ndesign matrix")
        XCTAssertEqual(try Data(contentsOf: source), originalBytes)
    }

    @MainActor
    private static func sourcePDF() throws -> Data {
        let bytes = NSMutableData()
        var box = CGRect(x: 0, y: 0, width: 300, height: 400)
        let context = try XCTUnwrap(CGContext(consumer: try XCTUnwrap(CGDataConsumer(data: bytes)), mediaBox: &box, nil))
        for line in ["X is the design matrix", "X is used here"] {
            context.beginPDFPage(nil)
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
            NSColor.white.setFill(); box.fill()
            (line as NSString).draw(at: CGPoint(x: 20, y: 80), withAttributes: [.font: NSFont.systemFont(ofSize: 18), .foregroundColor: NSColor.black])
            NSGraphicsContext.restoreGraphicsState(); context.endPDFPage()
        }
        context.closePDF()
        return bytes as Data
    }
}
