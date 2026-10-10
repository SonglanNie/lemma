import XCTest
import AppKit
import PDFKit
import SwiftUI
import LemmaCore
@testable import Lemma

final class LibraryTests: XCTestCase {
    @MainActor
    func testProgressCoversAndClosingABookKeepTheLibrary() async throws {
        _ = NSApplication.shared
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let previous = UserDefaults.standard.object(forKey: "lastWorkspaceID")
        defer { UserDefaults.standard.set(previous, forKey: "lastWorkspaceID"); try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let source = root.appendingPathComponent("library.pdf")
        let document = PDFDocument()
        for index in 0..<4 {
            let image = NSImage(size: NSSize(width: 300, height: 400), flipped: false) { rect in
                NSColor.white.setFill(); rect.fill()
                ("Page \(index + 1)" as NSString).draw(at: CGPoint(x: 40, y: 200), withAttributes: [.font: NSFont.systemFont(ofSize: 30)])
                return true
            }
            document.insert(try XCTUnwrap(PDFPage(image: image)), at: index)
        }
        XCTAssertTrue(document.write(to: source))
        let store = StudyStore(root: root.appendingPathComponent("support"))
        store.open(source)
        store.workspace?.reading.pageIndex = 1
        store.reader.selection = (1, CGRect(x: 30, y: 180, width: 200, height: 60), "")
        store.addNote(); store.addToReview(id: try XCTUnwrap(store.currentNote?.id))
        store.flush()
        let book = try XCTUnwrap(store.library.first)
        XCTAssertEqual(book.pageCount, 4)
        XCTAssertEqual(try XCTUnwrap(book.progress), 0.5, accuracy: 0.0001)
        // Covers render off the main thread: asking starts it, and the views showing it are redrawn when it is ready.
        var cover = store.covers.cover(for: book)
        let deadline = Date.now.addingTimeInterval(10)
        while cover == nil, Date.now < deadline { try await Task.sleep(for: .milliseconds(50)); cover = store.covers.cover(for: book) }
        XCTAssertNotNil(cover)
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.repository.root.appendingPathComponent("Covers/\(book.id).png").path), "Covers are cached once.")

        store.closeBook()
        XCTAssertNil(store.workspace); XCTAssertNil(store.document); XCTAssertNil(store.references)
        XCTAssertNil(UserDefaults.standard.string(forKey: "lastWorkspaceID"), "A closed book is not reopened at launch.")
        XCTAssertEqual(store.library.map(\.id), [book.id])
        let home = NSHostingView(rootView: LibraryHome(store: store))
        home.frame = CGRect(x: 0, y: 0, width: 900, height: 700); home.layoutSubtreeIfNeeded()

        let reloaded = StudyStore(root: root.appendingPathComponent("support"))
        XCTAssertEqual(reloaded.library.first?.notes.filter { $0.isDue() }.count, 1)
        reloaded.reopen(try XCTUnwrap(reloaded.library.first))
        XCTAssertEqual(reloaded.workspace?.id, book.id)
        XCTAssertEqual(reloaded.workspace?.reading.pageIndex, 1)

        var moved = book; moved.id = "missing"; moved.sourcePath = root.appendingPathComponent("moved.pdf").path
        XCTAssertNil(LibraryCovers(root: root.appendingPathComponent("other")).cover(for: moved), "A moved source has no cover until it is opened again.")
    }
}

final class MarginCardTests: XCTestCase {
    @MainActor
    func testNotesBecomeMarginCardsWhenTheMarginHasRoom() throws {
        _ = NSApplication.shared
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let previous = UserDefaults.standard.object(forKey: "lastWorkspaceID")
        defer { UserDefaults.standard.set(previous, forKey: "lastWorkspaceID"); try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let source = root.appendingPathComponent("margin.pdf")
        let document = PDFDocument()
        let image = NSImage(size: NSSize(width: 300, height: 400), flipped: false) { rect in
            NSColor.white.setFill(); rect.fill()
            ("A definition worth keeping" as NSString).draw(at: CGPoint(x: 30, y: 300), withAttributes: [.font: NSFont.systemFont(ofSize: 16)])
            return true
        }
        document.insert(try XCTUnwrap(PDFPage(image: image)), at: 0)
        XCTAssertTrue(document.write(to: source))
        let store = StudyStore(root: root.appendingPathComponent("support"))
        store.open(source)
        store.reader.selection = (0, CGRect(x: 25, y: 290, width: 240, height: 30), "")
        store.addNote(kind: .definition)
        let first = try XCTUnwrap(store.currentNote?.id)
        store.updateNote { $0.question = "Design matrix"; $0.body = "Rows are observations;\ncolumns are inputs." }
        store.reader.selection = (0, CGRect(x: 25, y: 100, width: 240, height: 30), "")
        store.addNote()
        let second = try XCTUnwrap(store.currentNote?.id)

        let view = RegionPDFView(frame: CGRect(x: 0, y: 0, width: 1400, height: 700))
        view.controller = store.reader; store.reader.view = view; view.document = store.document
        view.displayMode = .singlePage; view.autoScales = true
        let window = NSWindow(contentRect: view.frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.contentView = view
        defer { window.close() }
        view.layoutDocumentView(); view.layoutSubtreeIfNeeded()
        store.reader.notes = try XCTUnwrap(store.workspace?.notes); store.reader.selectedNoteID = second
        view.refreshCaptureOverlay()
        let overlay = try XCTUnwrap(view.subviews.compactMap { $0 as? RegionSelectionOverlay }.first)
        let cards = overlay.subviews.compactMap { $0 as? NoteCardView }
        XCTAssertEqual(Set(cards.map(\.noteID)), [first, second])
        let page = try XCTUnwrap(store.document?.page(at: 0))
        let pageRect = view.convert(page.bounds(for: .cropBox), from: page)
        XCTAssertTrue(cards.allSatisfy { $0.frame.minX > pageRect.maxX }, "Cards sit in the margin beside the page.")
        XCTAssertFalse(cards[0].frame.intersects(cards[1].frame))
        view.refreshCaptureOverlay()
        XCTAssertEqual(Set(overlay.subviews.compactMap { $0 as? NoteCardView }.map(ObjectIdentifier.init)), Set(cards.map(ObjectIdentifier.init)),
                       "Scrolling reuses margin cards instead of rebuilding them.")
        XCTAssertEqual(NoteCardView.snippet(for: try XCTUnwrap(store.workspace?.notes.first { $0.id == first })), "Rows are observations; columns are inputs.")
        let card = try XCTUnwrap(cards.first { $0.noteID == first })
        card.mouseDown(with: try XCTUnwrap(NSEvent.mouseEvent(with: .leftMouseDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 1)))
        XCTAssertEqual(store.selectedNoteID, first, "Clicking a card opens its note.")

        view.setFrameSize(CGSize(width: 560, height: 700)); view.layoutDocumentView(); view.refreshCaptureOverlay()
        XCTAssertTrue(overlay.subviews.compactMap { $0 as? NoteCardView }.isEmpty, "A narrow margin falls back to icons.")
        XCTAssertEqual(overlay.subviews.compactMap { $0 as? NSButton }.count, 2)
    }
}

final class NeighborsRecordTests: XCTestCase {
    @MainActor
    func testSimulationRecordPersistsAndExportsItsDataAndScript() throws {
        _ = NSApplication.shared
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let previous = UserDefaults.standard.object(forKey: "lastWorkspaceID")
        defer { UserDefaults.standard.set(previous, forKey: "lastWorkspaceID"); try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let source = root.appendingPathComponent("knn.pdf")
        let document = PDFDocument()
        document.insert(try XCTUnwrap(PDFPage(image: NSImage(size: NSSize(width: 200, height: 200), flipped: false) { rect in NSColor.white.setFill(); rect.fill(); return true })), at: 0)
        XCTAssertTrue(document.write(to: source))
        let store = StudyStore(root: root.appendingPathComponent("support"))
        store.open(source)
        store.reader.selection = (0, CGRect(x: 20, y: 20, width: 100, height: 60), "")
        store.addNote()
        let note = try XCTUnwrap(store.currentNote)
        let parameters = RidgeParameters(lambda: 0, correlation: 0, seed: NeighborsExperimentPane.bookLikeSeed, sampleCount: 200)
        var record = ExperimentRecord(kind: .nearestNeighbors, noteID: note.id, source: note.anchor, prediction: "Test error is U-shaped in k.",
                                      observation: "Best near k = 21; training error cannot choose it.", startingParameters: parameters,
                                      parameters: parameters, predictedAt: Date(timeIntervalSince1970: 1_800_000_000))
        record.neighbors = NeighborsSettings(classifier: .neighbors, k: 21, showBayes: true)
        record.startingNeighbors = NeighborsSettings()
        XCTAssertTrue(store.saveExperiment(record, workspaceID: try XCTUnwrap(store.workspace?.id)))

        let reopened = StudyStore(root: root.appendingPathComponent("support"))
        reopened.open(source)
        let saved = try XCTUnwrap(reopened.workspace?.notes.first?.experiments.first)
        XCTAssertEqual(saved.kind, .nearestNeighbors)
        XCTAssertEqual(saved.neighbors, NeighborsSettings(classifier: .neighbors, k: 21, showBayes: true))
        XCTAssertEqual(saved.parameters.seed, 77)
        let destination = root.appendingPathComponent("export")
        try reopened.repository.export(try XCTUnwrap(reopened.workspace), to: destination)
        let stem = ExperimentExport.stem(saved)
        let training = try String(contentsOf: destination.appendingPathComponent("experiments/\(stem)-training.csv"), encoding: .utf8)
        XCTAssertEqual(training.split(separator: "\n").count, 201)
        let errors = try String(contentsOf: destination.appendingPathComponent("experiments/\(stem)-errors.csv"), encoding: .utf8)
        XCTAssertEqual(errors.split(separator: "\n").count, 101)
        let script = try String(contentsOf: destination.appendingPathComponent("experiments/\(stem).py"), encoding: .utf8)
        XCTAssertTrue(script.contains("k = 21")); XCTAssertTrue(script.contains("\(stem)-errors.csv"))
        let markdown = try String(contentsOf: destination.appendingPathComponent("Study notes.md"), encoding: .utf8)
        for expected in ["Least squares vs nearest neighbours · ESL §2.3 simulation", "Saved view: 21-nearest neighbours, with the Bayes boundary",
                         "Best near k = 21", "Bayes rule test error", "experiments/\(stem).py"] {
            XCTAssertTrue(markdown.contains(expected), expected)
        }
        XCTAssertFalse(markdown.contains("Ridge experiment"), "A simulation is not described as a ridge experiment.")
    }
}

final class SourceLocationTests: XCTestCase {
    @MainActor
    func testReopeningFollowsTheMostRecentlyOpenedCopy() throws {
        _ = NSApplication.shared
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let previous = UserDefaults.standard.object(forKey: "lastWorkspaceID")
        defer { UserDefaults.standard.set(previous, forKey: "lastWorkspaceID"); try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root.appendingPathComponent("temporary"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("stable"), withIntermediateDirectories: true)
        let first = root.appendingPathComponent("temporary/book.pdf"), second = root.appendingPathComponent("stable/book.pdf")
        let document = PDFDocument()
        document.insert(try XCTUnwrap(PDFPage(image: NSImage(size: NSSize(width: 100, height: 100), flipped: false) { rect in NSColor.white.setFill(); rect.fill(); return true })), at: 0)
        XCTAssertTrue(document.write(to: first))
        try FileManager.default.copyItem(at: first, to: second)
        let store = StudyStore(root: root.appendingPathComponent("support"))
        store.open(first)
        store.open(second)
        let reopened = StudyStore(root: root.appendingPathComponent("support"))
        reopened.reopen(try XCTUnwrap(reopened.library.first))
        let opened = URL(fileURLWithPath: try XCTUnwrap(reopened.workspace?.sourcePath)).resolvingSymlinksInPath().path
        XCTAssertEqual(opened, second.resolvingSymlinksInPath().path, "Both copies exist; the one opened last wins.")
    }
}
