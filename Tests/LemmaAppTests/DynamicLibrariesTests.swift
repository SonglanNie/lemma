import XCTest
import AppKit
import PDFKit
import LemmaCore
@testable import Lemma

final class DynamicLibrariesTests: XCTestCase {
    @MainActor
    func testExplicitPDFRenameFollowsTheFileWithoutLosingStudyOrReadingContext() async throws {
        _ = NSApplication.shared
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let book = root.appendingPathComponent("Original.pdf"), support = root.appendingPathComponent("support")
        let previous = UserDefaults.standard.object(forKey: "lastWorkspaceID")
        let previousTabs = UserDefaults.standard.object(forKey: "openTabs")
        defer {
            UserDefaults.standard.set(previous, forKey: "lastWorkspaceID")
            UserDefaults.standard.set(previousTabs, forKey: "openTabs")
            try? FileManager.default.removeItem(at: root)
        }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try WorkbenchFixture.writeBook(to: book)
        let before: StudyWorkspace, savedBefore: StudyWorkspace
        let renamed = root.appendingPathComponent("Renamed.pdf")
        var firstStore: StudyStore? = StudyStore(root: support)
        weak var releasedStore = firstStore
        do {
            let store = try XCTUnwrap(firstStore)
            try store.libraries.replace([
                LibraryCollection(id: "stats", title: "Stats", kind: .studying,
                                  sources: [LibrarySource(path: book.path, kind: .file)])
            ])
            store.open(book)
            store.reader.selection = (0, CGRect(x: 20, y: 20, width: 60, height: 60), "source")
            store.addNote()
            store.workspace?.reading.pageIndex = 3
            store.workspace?.reading.scale = 1.75
            store.workspace?.reading.returnNote = "Keep my place"
            store.flush()
            before = try XCTUnwrap(store.workspace)
            let selected = store.selectedNoteID
            savedBefore = try XCTUnwrap(store.repository.load(id: before.id))
            let document = store.document
            store.libraries.start()
            try await eventually("initial explicit source") { store.libraries.entries.count == 1 }

            try FileManager.default.moveItem(at: book, to: renamed)
            try await eventually("explicit PDF rename") {
                store.libraries.entries.map { LibraryPaths.key($0.path) } == [LibraryPaths.key(renamed.path)]
            }
            XCTAssertTrue(store.libraries.issues.isEmpty)
            XCTAssertEqual(store.workspace.map { LibraryPaths.key($0.sourcePath) }, LibraryPaths.key(renamed.path))
            XCTAssertEqual(store.workspace?.id, before.id)
            XCTAssertEqual(store.workspace?.notes, before.notes)
            XCTAssertEqual(store.workspace?.reading, before.reading)
            XCTAssertEqual(store.selectedNoteID, selected)
            XCTAssertTrue(store.document === document, "Relinking keeps the PDF already on screen")
            XCTAssertTrue(store.unfiledBooks.isEmpty, "The book stays in its original collection")
            let saved = try XCTUnwrap(store.repository.load(id: before.id))
            XCTAssertEqual(LibraryPaths.key(saved.sourcePath), LibraryPaths.key(renamed.path))
            XCTAssertEqual(saved.notes, savedBefore.notes)
            XCTAssertEqual(saved.reading, before.reading)
        }
        firstStore = nil
        XCTAssertNil(releasedStore, "Restart releases the previous store and its file watchers")

        let restored = StudyStore(root: support)
        restored.reopen(try XCTUnwrap(restored.library.first))
        XCTAssertNil(restored.error)
        XCTAssertEqual(restored.workspace?.id, before.id)
        XCTAssertEqual(restored.workspace?.reading, before.reading)
        restored.libraries.start()
        try await eventually("restored explicit source") { restored.libraries.entries.count == 1 }
        let renamedAgain = root.appendingPathComponent("Renamed again.pdf")
        try FileManager.default.moveItem(at: renamed, to: renamedAgain)
        try await eventually("rename after restart") {
            restored.libraries.entries.first.map { LibraryPaths.key($0.path) } == LibraryPaths.key(renamedAgain.path)
                && restored.workspace.map { LibraryPaths.key($0.sourcePath) } == LibraryPaths.key(renamedAgain.path)
        }
        XCTAssertTrue(restored.libraries.issues.isEmpty)
        XCTAssertEqual(restored.workspace?.notes, savedBefore.notes)
        try restored.libraries.replace([])
        try await eventually("unfiled book") { restored.libraries.entries.isEmpty }
        let unfiledRename = root.appendingPathComponent("Unfiled renamed.pdf")
        try FileManager.default.moveItem(at: renamedAgain, to: unfiledRename)
        try await eventually("unfiled PDF rename") {
            restored.workspace.map { LibraryPaths.key($0.sourcePath) } == LibraryPaths.key(unfiledRename.path)
        }
        XCTAssertEqual(restored.workspace?.notes, savedBefore.notes)
        XCTAssertEqual(restored.workspace?.reading, before.reading)
    }

    @MainActor
    func testRenamePersistsWithoutChangingPDFsSourcesOrReadingContext() async throws {
        let fixture = try WorkbenchFixture()
        defer { fixture.close() }
        let store = fixture.store
        let sources = [LibrarySource(path: fixture.book.path, kind: .file, excludedPaths: [fixture.paper.path])]
        try store.libraries.replace([
            LibraryCollection(id: "course", title: "CSD", kind: .studying, parent: "School", sources: sources),
            LibraryCollection(id: "other", title: "Economics", kind: .studying, parent: "School", sources: [])
        ])
        store.libraries.start()
        try await eventually("initial scan") { !store.libraries.entries.isEmpty }
        let trackedSources = store.libraries.collections[0].sources
        store.open(fixture.book); store.workspace?.reading.returnNote = "Keep my place"; store.flush()
        let workspace = store.workspace, selected = store.selectedNoteID, entries = store.libraries.entries
        XCTAssertFalse(store.renameLibrary("course", to: " \n "))
        XCTAssertFalse(store.renameLibrary("missing", to: "Control"))
        XCTAssertTrue(store.renameLibrary("course", to: "  Control Systems \n"))
        XCTAssertTrue(store.renameLibrarySection("School", to: "Courses"))
        XCTAssertEqual(store.libraries.entries, entries)
        XCTAssertEqual(store.workspace, workspace); XCTAssertEqual(store.selectedNoteID, selected)
        let restored = try XCTUnwrap(LibraryCollectionRepository(root: store.repository.root).load())
        XCTAssertEqual(restored[0].id, "course"); XCTAssertEqual(restored[0].title, "Control Systems")
        XCTAssertEqual(restored[0].sources, trackedSources)
        XCTAssertEqual(restored.map(\.parent), ["Courses", "Courses"])
        XCTAssertEqual(store.libraries.collections, restored)
    }

    @MainActor
    func testFSEventsFindNewNestedPDFsAndKeepTheReadingContext() async throws {
        _ = NSApplication.shared
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let support = root.appendingPathComponent("support"), folder = root.appendingPathComponent("watch")
        let previous = UserDefaults.standard.object(forKey: "lastWorkspaceID")
        defer { UserDefaults.standard.set(previous, forKey: "lastWorkspaceID"); try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let config = [LibraryCollection(id: "course", title: "CSD", kind: .studying, parent: "School", sources: [LibrarySource(path: folder.path)])]
        try LibraryCollectionRepository(root: support).save(config)
        let source = root.appendingPathComponent("current.pdf")
        let pdf = try makePDF()
        XCTAssertTrue(pdf.write(to: source))
        let store = StudyStore(root: support)
        store.libraries.start()
        store.open(source)
        store.reader.selection = (0, CGRect(x: 20, y: 20, width: 60, height: 60), "source")
        store.addNote(); store.workspace?.reading.scale = 1.75
        store.workspace?.reading.returnNote = "Keep this place"; store.flush()
        let selected = store.selectedNoteID, before = try XCTUnwrap(store.workspace)
        let nested = folder.appendingPathComponent("New chapter/TD")
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        let newPDF = nested.appendingPathComponent("New.pdf")
        XCTAssertTrue(pdf.write(to: newPDF))
        try await eventually("discovery") { store.libraries.entries.contains { LibraryPaths.key($0.path) == LibraryPaths.key(newPDF.path) } }
        XCTAssertEqual(store.libraries.entries.first?.folder, "New chapter/TD")
        XCTAssertEqual(store.selectedNoteID, selected)
        XCTAssertEqual(store.workspace?.reading, before.reading)
        XCTAssertEqual(store.workspace?.notes, before.notes)
        XCTAssertEqual(store.library.count, 1, "Discovery does not create workspaces or replace the current book")
        let renamed = nested.appendingPathComponent("Renamed.pdf")
        try FileManager.default.moveItem(at: newPDF, to: renamed)
        try await eventually("rename") { store.libraries.entries.map { LibraryPaths.key($0.path) } == [LibraryPaths.key(renamed.path)] }
        let renamedFolder = root.appendingPathComponent("Renamed course")
        try FileManager.default.moveItem(at: folder, to: renamedFolder)
        let relocatedPDF = renamedFolder.appendingPathComponent("New chapter/TD/Renamed.pdf")
        try await eventually("watched folder rename") {
            store.libraries.entries.map { LibraryPaths.key($0.path) } == [LibraryPaths.key(relocatedPDF.path)]
        }
        XCTAssertTrue(store.libraries.issues.isEmpty)
        try FileManager.default.removeItem(at: relocatedPDF)
        try await eventually("removal") { store.libraries.entries.isEmpty }
        XCTAssertEqual(store.workspace?.id, before.id)
        XCTAssertEqual(store.workspace?.notes, before.notes)
        let loaded = StudyStore(root: support)
        XCTAssertEqual(loaded.libraries.collections, store.libraries.collections)
    }

    @MainActor
    func testArxivLinksOpenExactLocalCopiesWithoutASecondDownload() throws {
        _ = NSApplication.shared
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let previous = UserDefaults.standard.object(forKey: "lastWorkspaceID")
        defer { UserDefaults.standard.set(previous, forKey: "lastWorkspaceID"); try? FileManager.default.removeItem(at: root) }
        let folder = root.appendingPathComponent("Papers")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let pdf = try makePDF()
        let file = folder.appendingPathComponent("arXiv 1706.03762v7.pdf")
        XCTAssertTrue(pdf.write(to: file))
        let store = StudyStore(root: root)
        XCTAssertNil(store.localArxivFile("1706.03762"), "An unversioned identifier must not silently reuse a selected old version")
        store.openLink(try XCTUnwrap(ArxivIdentifier.link("1706.03762v7")))
        XCTAssertEqual(store.workspace.map { LibraryPaths.key($0.sourcePath) }, LibraryPaths.key(file.path))
        XCTAssertTrue(store.downloads.progress.isEmpty)
        store.workspace?.reading.returnNote = "Read the attention section"; store.flush()
        let id = store.workspace?.id
        store.openLink(try XCTUnwrap(ArxivIdentifier.link("1706.03762v7")))
        XCTAssertEqual(store.workspace?.id, id)
        XCTAssertEqual(store.workspace?.reading.returnNote, "Read the attention section")
        XCTAssertEqual(store.tabs.count, 1)
        store.openLink(URL(string: "lemma://arxiv?id=invalid")!)
        XCTAssertNotNil(store.error)
        XCTAssertEqual(store.workspace?.id, id)
    }

    /// A sync client or a download writing other files in a watched folder costs nothing: only PDFs and folders
    /// coming, going or renamed make the library be scanned again.
    @MainActor
    func testOtherFilesChangingInAWatchedFolderDoNotRescanIt() async throws {
        _ = NSApplication.shared
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let support = root.appendingPathComponent("support"), folder = root.appendingPathComponent("watch")
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: folder.appendingPathComponent("Part 1"), withIntermediateDirectories: true)
        XCTAssertTrue(try makePDF().write(to: folder.appendingPathComponent("Part 1/First.pdf")))
        try LibraryCollectionRepository(root: support).save([LibraryCollection(id: "course", title: "Course", kind: .studying, sources: [LibrarySource(path: folder.path)])])
        let store = StudyStore(root: support)
        store.libraries.start()
        try await eventually("first scan") { store.libraries.entries.count == 1 && !store.libraries.isScanning }
        try await Task.sleep(for: .milliseconds(1500))
        let scanned = try XCTUnwrap(store.libraries.updatedAt)
        for step in 0..<8 {
            try Data("\(step)".utf8).write(to: folder.appendingPathComponent("Part 1/notes-\(step % 3).txt"))
            try Data("\(step)".utf8).write(to: folder.appendingPathComponent(".sync-\(step).tmp"))
            try? FileManager.default.removeItem(at: folder.appendingPathComponent(".sync-\(step).tmp"))
            try await Task.sleep(for: .milliseconds(250))
        }
        try await Task.sleep(for: .milliseconds(2000))
        XCTAssertEqual(store.libraries.updatedAt, scanned, "Text and temporary files do not make the library be scanned again")
        XCTAssertTrue(try makePDF().write(to: folder.appendingPathComponent("Part 1/Second.pdf")))
        try await eventually("a new PDF") { store.libraries.entries.count == 2 }
    }

    /// Books and Papers are made by the first download into them: the book then opened is listed in its library,
    /// though no folder was there to watch before.
    @MainActor
    func testAFolderMadeByTheFirstDownloadIsListed() async throws {
        _ = NSApplication.shared
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let support = root.appendingPathComponent("support"), books = support.appendingPathComponent("Books")
        let previous = UserDefaults.standard.object(forKey: "lastWorkspaceID")
        defer { UserDefaults.standard.set(previous, forKey: "lastWorkspaceID"); try? FileManager.default.removeItem(at: root) }
        let store = StudyStore(root: support)
        store.libraries.start()
        try await eventually("first scan") { store.libraries.updatedAt != nil && !store.libraries.isScanning }
        XCTAssertTrue(store.libraries.entries.isEmpty)
        try FileManager.default.createDirectory(at: books, withIntermediateDirectories: true)
        let book = books.appendingPathComponent("Downloaded.pdf")
        XCTAssertTrue(try makePDF().write(to: book))
        store.open(book)
        try await eventually("the new folder's PDF") { store.libraries.entries.map(\.key) == [LibraryPaths.key(book.path)] }
        XCTAssertTrue(store.unfiledBooks.isEmpty, "The book is in Books, not among Other PDFs")
    }

    /// A folder change reported as a PDF is dropped replaces the drop's scan before it starts, and waits first:
    /// the Library is scanning from the drop on, so nothing reads it as up to date in the meantime.
    @MainActor
    func testALibraryIsScanningFromTheMomentAScanIsAskedFor() async throws {
        _ = NSApplication.shared
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let support = root.appendingPathComponent("support"), pdf = root.appendingPathComponent("Downloads/Attention.pdf")
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: pdf.deletingLastPathComponent(), withIntermediateDirectories: true)
        XCTAssertTrue(try makePDF().write(to: pdf))
        let store = StudyStore(root: support)
        try store.libraries.replace([LibraryCollection(id: "csd", title: "CSD", kind: .studying, sources: [])])
        store.libraries.start()
        try await eventually("first scan") { store.libraries.updatedAt != nil && !store.libraries.isScanning }
        store.addToLibrary([pdf], collectionID: "csd")
        store.libraries.refresh(debounce: true)
        XCTAssertTrue(store.libraries.isScanning, "Scanning through the folder change's wait")
        try await eventually("the dropped PDF") { !store.libraries.isScanning }
        XCTAssertEqual(store.libraries.entries.filter { $0.collectionID == "csd" }.map(\.key), [LibraryPaths.key(pdf.path)])
    }

    @MainActor private func eventually(_ phase: String, _ condition: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(10)
        while !condition() && Date() < deadline { try await Task.sleep(for: .milliseconds(100)) }
        XCTAssertTrue(condition(), "FSEvents should update after \(phase) without a manual refresh")
    }
    @MainActor private func makePDF() throws -> PDFDocument {
        let image = NSImage(size: NSSize(width: 300, height: 400), flipped: false) { rect in
            NSColor.white.setFill(); rect.fill()
            ("A study page" as NSString).draw(at: CGPoint(x: 20, y: 300), withAttributes: [.font: NSFont.systemFont(ofSize: 16)])
            return true
        }
        let pdf = PDFDocument(); pdf.insert(try XCTUnwrap(PDFPage(image: image)), at: 0); return pdf
    }
}
