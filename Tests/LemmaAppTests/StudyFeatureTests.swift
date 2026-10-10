import XCTest
import AppKit
import PDFKit
import LemmaCore
@testable import Lemma

final class StudyFeatureTests: XCTestCase {
    @MainActor
    func testAsynchronousPDFSearchCollectsMatchesAndCancelsCleanly() async throws {
        _ = NSApplication.shared
        let bytes = NSMutableData()
        var box = CGRect(x: 0, y: 0, width: 300, height: 400)
        let context = try XCTUnwrap(CGContext(consumer: try XCTUnwrap(CGDataConsumer(data: bytes)), mediaBox: &box, nil))
        for line in ["matrix and matrix", "a response matrix"] {
            context.beginPDFPage(nil)
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
            (line as NSString).draw(at: CGPoint(x: 20, y: 80), withAttributes: [.font: NSFont.systemFont(ofSize: 15), .foregroundColor: NSColor.black])
            NSGraphicsContext.restoreGraphicsState(); context.endPDFPage()
        }
        context.closePDF()
        let document = try XCTUnwrap(PDFDocument(data: bytes as Data))
        let controller = ReaderController()
        let view = RegionPDFView(frame: CGRect(x: 0, y: 0, width: 600, height: 700))
        view.document = document; view.controller = controller; controller.view = view
        controller.searchText = "matrix"; controller.find()
        let deadline = Date.now.addingTimeInterval(3)
        while controller.isSearching && Date.now < deadline { try await Task.sleep(for: .milliseconds(20)) }
        XCTAssertFalse(controller.isSearching)
        XCTAssertEqual(controller.searchResults.count, 3)
        controller.nextMatch(); XCTAssertEqual(controller.searchIndex, 1)
        controller.previousMatch(); XCTAssertEqual(controller.searchIndex, 0)
        controller.searchText = "response"; controller.find(); controller.resetSearch()
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertFalse(controller.isSearching); XCTAssertFalse(document.isFinding)
        XCTAssertTrue(controller.searchResults.isEmpty); XCTAssertFalse(controller.hasSearched)
    }

    @MainActor
    func testMarksGlossaryReviewAndChosenContextRemainLocalAndDurable() throws {
        _ = NSApplication.shared
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let oldLastWorkspace = UserDefaults.standard.object(forKey: "lastWorkspaceID")
        defer { UserDefaults.standard.set(oldLastWorkspace, forKey: "lastWorkspaceID") }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let source = root.appendingPathComponent("study.pdf")
        let bytes = NSMutableData()
        var box = CGRect(x: 0, y: 0, width: 300, height: 400)
        let context = try XCTUnwrap(CGContext(consumer: try XCTUnwrap(CGDataConsumer(data: bytes)), mediaBox: &box, nil))
        for line in ["X is the design matrix", "Y is the response"] {
            context.beginPDFPage(nil)
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
            NSColor.white.setFill(); box.fill()
            (line as NSString).draw(at: CGPoint(x: 20, y: 70), withAttributes: [.font: NSFont.systemFont(ofSize: 15), .foregroundColor: NSColor.black])
            NSGraphicsContext.restoreGraphicsState(); context.endPDFPage()
        }
        context.closePDF(); try (bytes as Data).write(to: source)
        let originalBytes = try Data(contentsOf: source)
        let store = StudyStore(root: root.appendingPathComponent("support"))
        store.open(source)
        let document = try XCTUnwrap(store.document)
        let view = RegionPDFView(frame: CGRect(x: 0, y: 0, width: 600, height: 700))
        view.controller = store.reader; store.reader.view = view; view.document = document
        view.displayMode = .singlePage; view.autoScales = true
        let window = NSWindow(contentRect: view.frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.contentView = view
        defer { window.close() }
        view.layoutDocumentView(); view.layoutSubtreeIfNeeded(); store.reader.updatePage()
        let coordinator = PDFReaderSurface.Coordinator(controller: store.reader)
        coordinator.observe(view)
        defer { coordinator.stop() }
        store.toggleBookmark()
        store.reader.goToPage(2); store.reader.updatePage(); store.toggleBookmark()
        XCTAssertEqual(store.workspace?.bookmarks.map(\.pageIndex), [0, 1])
        store.reader.regionMode = true
        store.reader.selection = (0, CGRect(x: 15, y: 60, width: 240, height: 45), "X is the design matrix")
        store.addNote(kind: .notation)
        let noteID = try XCTUnwrap(store.currentNote?.id)
        let anchor = try XCTUnwrap(store.currentNote?.anchor)
        store.updateNote { $0.question = "X"; $0.notation = "n × p design matrix"; $0.scope = "This chapter"; $0.assumptions = "Full column rank"; $0.body = "Each row is an observation."; $0.state = .revisit }
        let cleanCrop = try Data(contentsOf: store.repository.assetURL(workspaceID: documentURLID(store), name: anchor.imageName))
        store.highlightSelection(color: .green)
        store.reader.syncHighlights(try XCTUnwrap(store.workspace?.highlights), in: document)
        XCTAssertEqual(document.page(at: 0)?.annotations.count, 1)
        let afterHighlight = try store.capture()
        XCTAssertEqual(try Data(contentsOf: store.repository.assetURL(workspaceID: documentURLID(store), name: afterHighlight.imageName)), cleanCrop, "Source crops must exclude the personal overlay.")
        store.pinSelection()
        let excluded = try XCTUnwrap(store.workspace?.pins.first?.id)
        store.updatePin(id: excluded, label: "Exclude this reference")
        store.reader.selection = (1, CGRect(x: 15, y: 60, width: 240, height: 45), "Y is the response")
        store.pinSelection()
        let included = try XCTUnwrap(store.workspace?.pins.last?.id)
        store.updatePin(id: included, label: "Chosen response definition")
        let packetAssets = try store.questionAssets(pinIDs: [included])
        XCTAssertEqual(packetAssets.images.map(\.label), ["Source A", "Reference 1: Chosen response definition"])
        XCTAssertEqual(packetAssets.data.count, 2)
        let prompt = store.prompt(style: .hint, pinIDs: [included])
        XCTAssertTrue(prompt.contains("Do not reveal the full solution"))
        XCTAssertTrue(prompt.contains("Full column rank"))
        XCTAssertTrue(prompt.contains("Chosen response definition"))
        XCTAssertFalse(prompt.contains("Exclude this reference"))
        for style in [QuestionStyle.intuition, .example, .counterexample, .recreateFigure] {
            let draft = store.prompt(style: style, pinIDs: [included])
            XCTAssertTrue(draft.contains(style.instruction))
            XCTAssertTrue(draft.contains("Chosen response definition"))
            XCTAssertFalse(draft.contains("Exclude this reference"))
        }
        let note = try XCTUnwrap(store.currentNote)
        store.reader.notes = [note]; store.reader.selectedNoteID = noteID
        store.reader.goToPage(1); view.refreshCaptureOverlay()
        let overlay = try XCTUnwrap(view.subviews.compactMap { $0 as? RegionSelectionOverlay }.first)
        XCTAssertEqual(overlay.subviews.compactMap { $0 as? NSButton }.count, 1)
        store.reader.recallMask = anchor; view.refreshCaptureOverlay()
        XCTAssertNotNil(overlay.recallRectangle)
        view.autoScales = false; view.scaleFactor = 2; store.reader.updatePage()
        let clip = try XCTUnwrap(view.documentView?.enclosingScrollView?.contentView)
        let beforeScroll = try XCTUnwrap(overlay.recallRectangle)
        clip.scroll(to: CGPoint(x: clip.bounds.origin.x, y: clip.bounds.origin.y + 40))
        let passage = view.convert(anchor.region.rect, from: try XCTUnwrap(document.page(at: anchor.pageIndex)))
        XCTAssertNotEqual(passage.origin, beforeScroll.origin, "The page scrolled.")
        let shown = try XCTUnwrap(overlay.recallMasksOnScreen.first)
        XCTAssertEqual(shown.minX, passage.minX, accuracy: 1, "The recall mask must follow the source while scrolling.")
        XCTAssertEqual(shown.minY, passage.minY, accuracy: 1, "The recall mask must follow the source while scrolling.")
        store.reader.recallMask = nil; view.refreshCaptureOverlay()
        XCTAssertNil(overlay.recallRectangle)
        store.reader.showAnnotations = false
        store.reader.syncHighlights(try XCTUnwrap(store.workspace?.highlights), in: document)
        XCTAssertEqual(document.page(at: 0)?.annotations.count, 0)
        store.recordReview(id: noteID, understood: true)
        XCTAssertTrue(store.reviewNotes.isEmpty); XCTAssertEqual(store.currentNote?.reviewCount, 1)
        let undo = UndoManager()
        store.removeNote(id: noteID, undoManager: undo); XCTAssertNil(store.currentNote)
        undo.undo(); XCTAssertEqual(store.currentNote?.id, noteID)
        store.showLibrary = false; store.showStudy = true
        store.toggleFocus(); XCTAssertFalse(store.showStudy)
        store.toggleFocus(); XCTAssertFalse(store.showLibrary); XCTAssertTrue(store.showStudy)
        store.flush(); store.libraryNoteQuery = "design matrix"
        XCTAssertEqual(store.libraryNoteResults.count, 1)
        let restored = StudyStore(root: root.appendingPathComponent("support")); restored.open(source)
        XCTAssertEqual(restored.workspace?.bookmarks.count, 2); XCTAssertEqual(restored.workspace?.highlights.count, 1)
        XCTAssertEqual(restored.currentNote?.kind, .notation); XCTAssertEqual(restored.currentNote?.scope, "This chapter")
        XCTAssertEqual(try Data(contentsOf: source), originalBytes)
        XCTAssertNil(store.error); XCTAssertNil(restored.error)
    }
    @MainActor private func documentURLID(_ store: StudyStore) -> String { store.workspace!.id }
}
