import XCTest
import AppKit
import PDFKit
import SwiftUI
import os
import LemmaCore
@testable import Lemma

/// Opening, saving and closing books never loses notes: a PDF whose bytes changed keeps its notes, an unreadable workspace
/// hides nothing else, closing tabs opens no other book on the way, and saves land in order.
final class DataIntegrityTests: XCTestCase {
    private var root: URL!
    private var support: URL { root.appendingPathComponent("support") }
    private let keys = ["lastWorkspaceID", "openTabs"]
    private var saved: [String: Any] = [:]

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        for key in keys { saved[key] = UserDefaults.standard.object(forKey: key) }
    }

    override func tearDownWithError() throws {
        for key in keys { UserDefaults.standard.set(saved[key], forKey: key) }
        try? FileManager.default.removeItem(at: root)
    }

    /// A PDF of `pages` pages whose text names `label`, so different labels give different bytes.
    @MainActor @discardableResult
    private func pdf(_ name: String, pages: Int = 3, label: String? = nil, password: String? = nil) throws -> URL {
        let url = root.appendingPathComponent(name)
        let document = PDFDocument()
        for index in 0..<pages {
            let image = NSImage(size: NSSize(width: 300, height: 400), flipped: false) { rect in
                NSColor.white.setFill(); rect.fill()
                ("\(label ?? name) · page \(index + 1)" as NSString).draw(at: CGPoint(x: 30, y: 200), withAttributes: [.font: NSFont.systemFont(ofSize: 16)])
                return true
            }
            document.insert(try XCTUnwrap(PDFPage(image: image)), at: index)
        }
        if let password {
            XCTAssertTrue(document.write(to: url, withOptions: [.userPasswordOption: password, .ownerPasswordOption: password + "-owner"]))
        } else {
            XCTAssertTrue(document.write(to: url))
        }
        return url
    }

    @MainActor private func store() -> StudyStore {
        _ = NSApplication.shared
        let store = StudyStore(root: support)
        store.urlOpener = { _ in }
        return store
    }

    @MainActor private func addNote(_ store: StudyStore, page: Int = 1, body: String = "My reasoning") throws -> UUID {
        store.reader.selection = (page, CGRect(x: 20, y: 150, width: 200, height: 80), "Passage")
        store.addNote()
        let id = try XCTUnwrap(store.currentNote?.id)
        store.updateNote(id: id) { $0.body = body }
        return id
    }

    // MARK: A PDF whose bytes change

    @MainActor
    func testNotesFollowAPDFWhoseBytesChangedOnDisk() throws {
        let source = try pdf("Book.pdf", label: "First printing")
        let store = store()
        store.open(source)
        let id = try XCTUnwrap(store.workspace?.id)
        let noteID = try addNote(store)
        store.flush()
        let projectID = try XCTUnwrap(store.newProject(title: "Project", question: ""))
        XCTAssertEqual(store.project(projectID)?.bookIDs, [id])
        try FileManager.default.createDirectory(at: support.appendingPathComponent("Indexes/\(id)"), withIntermediateDirectories: true)
        try Data("{}".utf8).write(to: support.appendingPathComponent("Indexes/\(id)/analysis.json"))
        store.closeBook()

        // Annotated in another app: the same path and page count, other bytes.
        try pdf("Book.pdf", label: "Annotated in Preview")
        let newFingerprint = try WorkspaceRepository.fingerprint(of: source)
        XCTAssertNotEqual(newFingerprint, id)
        store.open(source)
        XCTAssertEqual(store.workspace?.id, id, "The notes' workspace follows the file under its id, which projects and tabs name.")
        XCTAssertEqual(store.workspace?.fingerprint, newFingerprint)
        XCTAssertEqual(store.workspace?.notes.map(\.id), [noteID])
        XCTAssertEqual(store.library.count, 1, "No second, empty workspace.")
        XCTAssertEqual(store.project(projectID)?.bookIDs, [id])
        XCTAssertTrue(store.notifications.contains { $0.severity == .info && $0.message.contains("changed on disk; your notes moved with it") })
        XCTAssertFalse(FileManager.default.fileExists(atPath: support.appendingPathComponent("Indexes/\(id)/analysis.json").path),
                       "The analysis of the old bytes is made again.")
        store.flush()

        // After a restart the new bytes find their workspace again, without another notice.
        let restarted = self.store()
        restarted.open(source)
        XCTAssertEqual(restarted.workspace?.id, id)
        XCTAssertEqual(restarted.workspace?.notes.first?.body, "My reasoning")
        XCTAssertFalse(restarted.notifications.contains { $0.message.contains("changed on disk") })

        // A new edition with more pages, while the book is open: carried over too, with a warning to check the notes.
        try pdf("Book.pdf", pages: 5, label: "Second edition")
        restarted.open(source)
        XCTAssertEqual(restarted.workspace?.id, id)
        XCTAssertEqual(restarted.workspace?.pageCount, 5)
        XCTAssertEqual(restarted.document?.pageCount, 5)
        XCTAssertEqual(restarted.workspace?.notes.map(\.id), [noteID])
        XCTAssertTrue(restarted.notifications.contains { $0.severity == .warning && $0.message.contains("now has 5 pages instead of 3") })
        restarted.flush()
        XCTAssertEqual(try restarted.repository.load(id: id)?.fingerprint, try WorkspaceRepository.fingerprint(of: source))
        XCTAssertNil(restarted.error)
    }

    @MainActor
    func testAnUnknownLargeFileIsReadOffTheMainThreadAndALaterChoiceWins() async throws {
        let large = try pdf("Large.pdf"), other = try pdf("Other.pdf")
        let store = store()
        store.immediateHashLimit = 0
        var outcome: Bool?
        XCTAssertEqual(store.openFile(large) { outcome = $0 }, .pending)
        XCTAssertNil(store.workspace, "Nothing is shown before the fingerprint is known.")
        XCTAssertTrue(store.status.hasPrefix("Opening “Large”"))
        let deadline = Date.now.addingTimeInterval(10)
        while store.workspace == nil, Date.now < deadline { try await Task.sleep(for: .milliseconds(20)) }
        XCTAssertEqual(store.workspace?.title, "Large")
        XCTAssertEqual(outcome, true)
        XCTAssertNil(store.openingFile)
        XCTAssertEqual(store.status, "")
        // Known now: opened at once, from the fingerprint cache.
        store.closeBook()
        XCTAssertEqual(store.openFile(large), .opened)

        // A book chosen while another is still being read takes its place; the earlier one does not open over it.
        store.closeBook()
        try pdf("Large.pdf", label: "Large, second printing")
        XCTAssertEqual(store.openFile(large), .pending, "Its bytes changed, so it is read again.")
        store.immediateHashLimit = SourceFingerprint.immediateLimit
        store.open(other)
        XCTAssertEqual(store.workspace?.title, "Other")
        try await Task.sleep(for: .milliseconds(500))
        XCTAssertEqual(store.workspace?.title, "Other")
        XCTAssertEqual(store.tabs.map(\.title), ["Other"])
    }

    @MainActor
    func testTheSamePDFFromAnotherPathSharesItsDocumentAndKeepsReferenceLinks() throws {
        let original = try pdf("Book.pdf")
        let copy = root.appendingPathComponent("Copy of Book.pdf")
        try FileManager.default.copyItem(at: original, to: copy)
        let store = store()
        store.open(original)
        let document = try XCTUnwrap(store.document)
        store.open(copy)
        XCTAssertTrue(store.document === document, "The same bytes are one document.")
        XCTAssertTrue(store.references?.document === store.document, "The reference index reads the document shown.")
        store.closeBook()
        store.open(copy)
        XCTAssertTrue(store.references?.document === store.document)
        XCTAssertEqual(store.workspace?.sourcePath, copy.path)
    }

    // MARK: Unreadable workspaces

    @MainActor
    func testAnUnreadableWorkspaceIsReportedKeptAndKeepsItsTab() throws {
        let first = try pdf("First.pdf"), second = try pdf("Second.pdf")
        let store = store()
        store.open(first); let firstID = try XCTUnwrap(store.workspace?.id)
        store.open(second); let secondID = try XCTUnwrap(store.workspace?.id)
        store.activateTab(firstID)
        store.flush()
        let manifest = support.appendingPathComponent("Workspaces/\(secondID)/workspace.json")
        let broken = Data(#"{"title": "Second book", "id": 3}"#.utf8)
        try broken.write(to: manifest)

        let restarted = self.store()
        XCTAssertEqual(restarted.library.map(\.id), [firstID], "One unreadable file does not empty the library.")
        XCTAssertEqual(restarted.unreadableWorkspaces.map(\.id), [secondID])
        restarted.restore()
        XCTAssertTrue(restarted.notifications.contains { $0.severity == .error && $0.message.contains("“Second book”") })
        XCTAssertEqual(restarted.tabs.map(\.id), [firstID])
        restarted.flush()
        let session = try JSONDecoder().decode(WorkbenchSession.self, from: Data(contentsOf: restarted.sessionURL))
        XCTAssertEqual(session.bookIDs, [firstID, secondID], "The unreadable book keeps its place in the saved session.")
        restarted.open(second)
        XCTAssertNotEqual(restarted.workspace?.id, secondID, "Its PDF is not opened over the unreadable notes.")
        XCTAssertEqual(try Data(contentsOf: manifest), broken, "The unreadable file is left as it was.")
    }

    // MARK: Closing tabs

    @MainActor
    func testClosingAllBooksOrTheOthersOpensNoneOfTheClosedBooks() throws {
        let urls = try ["A.pdf", "B.pdf", "C.pdf"].map { try pdf($0) }
        let store = store()
        var ids: [String] = []
        for url in urls { store.open(url); ids.append(try XCTUnwrap(store.workspace?.id)) }
        store.flush()
        let opened = { (id: String) in store.library.first { $0.id == id }?.lastOpenedAt }
        let before = ids.map(opened)
        store.closeOtherTabs(keeping: ids[0])
        XCTAssertEqual(store.tabs.map(\.id), [ids[0]])
        XCTAssertEqual(store.workspace?.id, ids[0])
        XCTAssertEqual(opened(ids[1]), before[1], "B was closed without being opened on the way.")
        XCTAssertEqual(opened(ids[2]), before[2])
        XCTAssertNil(store.analyses[ids[1]]); XCTAssertNil(store.documents[ids[1]])

        for url in urls.dropFirst() { store.open(url) }
        store.flush()
        let reopened = ids.map(opened)
        store.closeAllBooks()
        XCTAssertNil(store.workspace)
        XCTAssertTrue(store.tabs.isEmpty)
        XCTAssertEqual(ids.map(opened), reopened, "Close All Books opens none of the books it closes.")
        XCTAssertTrue(store.documents.isEmpty)
        XCTAssertNil(store.error)
    }

    @MainActor
    func testClosingABookSkipsTabsWhosePDFIsGoneAndNeverSticks() throws {
        let urls = try ["A.pdf", "B.pdf", "C.pdf"].map { try pdf($0) }
        let first = store()
        var ids: [String] = []
        for url in urls { first.open(url); ids.append(try XCTUnwrap(first.workspace?.id)) }
        first.activateTab(ids[0])
        first.flush()

        // After a restart only A is read; B's file has gone since.
        let store = self.store()
        store.restore()
        XCTAssertEqual(store.workspace?.id, ids[0])
        XCTAssertEqual(store.tabs.map(\.id), ids)
        try FileManager.default.removeItem(at: urls[1])
        store.closeBook()
        XCTAssertEqual(store.workspace?.id, ids[2], "⌘W skips the tab whose PDF cannot be opened.")
        XCTAssertEqual(store.tabs.map(\.id), [ids[2]])
        let warnings = store.notifications.filter { $0.severity == .warning }
        XCTAssertEqual(warnings.count, 1)
        XCTAssertTrue(warnings.first?.message.contains("“B”") == true, warnings.first?.message ?? "")
        XCTAssertNil(store.error, "One notification, not an error per tab.")
        XCTAssertTrue(store.library.contains { $0.id == ids[1] }, "Its notes stay in the library.")
        store.closeBook()
        XCTAssertNil(store.workspace)
        XCTAssertTrue(store.tabs.isEmpty)
    }

    // MARK: Saving

    @MainActor
    func testDebouncedSavesLandInOrderAndFlushIsComplete() async throws {
        let source = try pdf("Book.pdf")
        let store = store()
        store.open(source)
        let id = try XCTUnwrap(store.workspace?.id)
        let noteID = try addNote(store)
        let manifest = store.repository.directory(for: id).appendingPathComponent("workspace.json")
        for index in 0..<40 { store.updateNote(id: noteID) { $0.body = "Draft \(index)" } }
        XCTAssertTrue(store.isSaving)
        store.flush()
        XCTAssertFalse(store.isSaving)
        let written = try WorkspaceRepository.decoder.decode(StudyWorkspace.self, from: Data(contentsOf: manifest))
        XCTAssertEqual(written.notes.first?.body, "Draft 39", "flush returns once the latest version is on disk.")
        XCTAssertEqual(written.schemaVersion, 10)

        // Scrolling saves the position beside the workspace: notes and ink are not written again.
        let stamp = FileStamp(manifest)
        store.reader.onReadingChanged?(2, 1.5)
        try await Task.sleep(for: .milliseconds(700))
        XCTAssertEqual(FileStamp(manifest), stamp, "A scroll does not rewrite workspace.json.")
        XCTAssertEqual(try store.repository.load(id: id)?.reading.pageIndex, 2)
        XCTAssertEqual(try store.repository.load(id: id)?.reading.scale, 1.5)
        XCTAssertFalse(store.isSaving)

        // A position, then a note, queued without waiting: both land, in order.
        store.workspace?.reading.pageIndex = 1
        store.save(wait: false)
        store.updateNote(id: noteID) { $0.body = "Final" }
        store.save(wait: false)
        let restarted = self.store()
        let reread = try XCTUnwrap(restarted.library.first { $0.id == id })
        XCTAssertEqual(reread.reading.pageIndex, 1)
        XCTAssertEqual(reread.notes.first?.body, "Final")
        XCTAssertNil(store.error)
    }

    @MainActor
    func testRestoringTwiceKeepsTheBooksSideTabs() throws {
        let source = try pdf("Book.pdf")
        let store = store()
        store.open(source)
        store.openToSide(page: 2)
        XCTAssertEqual(store.sideEditors.count, 1)
        store.flush()
        let restarted = self.store()
        restarted.restore()
        XCTAssertEqual(restarted.sideEditors.count, 1)
        // Reopening the window from the Dock runs its onAppear again.
        restarted.restore()
        XCTAssertEqual(restarted.sideEditors.count, 1, "The second restore must not replace the book's side tabs.")
        restarted.flush()
        let session = try JSONDecoder().decode(WorkbenchSession.self, from: Data(contentsOf: restarted.sessionURL))
        XCTAssertEqual(session.books[try XCTUnwrap(restarted.workspace?.id)]?.editors.count, 1)
    }

    // MARK: Passwords

    @MainActor
    func testALockedPDFAsksForItsPasswordAndIsNotAnalysed() async throws {
        let source = try pdf("Locked.pdf", password: "secret")
        XCTAssertEqual(PDFDocument(url: source)?.isLocked, true)
        let store = store()
        var asked: [(String, Bool)] = []
        store.passwordPrompt = { name, refused in asked.append((name, refused)); return nil }
        store.open(source)
        XCTAssertNil(store.workspace, "Cancelling the password opens nothing.")
        XCTAssertNil(store.error, "Cancelling is not an error.")
        XCTAssertEqual(asked.count, 1)

        asked = []
        var answers = ["wrong", "secret"]
        store.passwordPrompt = { name, refused in asked.append((name, refused)); return answers.isEmpty ? nil : answers.removeFirst() }
        store.open(source)
        XCTAssertEqual(asked.map(\.1), [false, true], "A refused password asks again, saying so.")
        XCTAssertEqual(store.document?.isLocked, false)
        XCTAssertEqual(store.workspace?.pageCount, 3)
        XCTAssertEqual(store.analysis?.failed, true, "A locked PDF is not sent to the analysis helper.")
        XCTAssertTrue(store.analysis?.failure?.contains("password") == true)
        let id = try XCTUnwrap(store.workspace?.id)
        store.flush()
        let manifest = try String(contentsOf: store.repository.directory(for: id).appendingPathComponent("workspace.json"), encoding: .utf8)
        XCTAssertFalse(manifest.contains("secret"), "The password is never written.")

        // Shown again in this session: no second question.
        store.closeBook()
        asked = []
        store.open(source)
        XCTAssertEqual(store.workspace?.id, id)
        XCTAssertTrue(asked.isEmpty)
    }

    // MARK: Navigation

    @MainActor
    func testALinkToABookThatCannotOpenDoesNotMoveTheBookInFront() async throws {
        let fixture = try WorkbenchFixture(hosted: true)
        defer { fixture.close() }
        let store = fixture.store
        store.open(fixture.paper)
        let paperID = try XCTUnwrap(store.workspace?.id)
        store.open(fixture.book)
        let bookID = try XCTUnwrap(store.workspace?.id)
        store.closeTab(paperID)
        try FileManager.default.removeItem(at: fixture.paper)
        try await fixture.settle(400)
        store.reader.goToPage(1)
        try await fixture.settle()
        let page = store.reader.pageNumber
        store.openLink(try XCTUnwrap(URL(string: "lemma://open?book=\(paperID)&page=4")))
        try await fixture.settle(1000)
        XCTAssertEqual(store.workspace?.id, bookID)
        XCTAssertEqual(store.reader.pageNumber, page, "The link's page is not applied to the wrong book.")
    }

    @MainActor
    func testANoteFoundInAnotherBookOpensThatBookAtTheNote() async throws {
        let fixture = try WorkbenchFixture(hosted: true)
        defer { fixture.close() }
        let store = fixture.store
        store.open(fixture.book)
        let bookID = try XCTUnwrap(store.workspace?.id)
        store.reader.selection = (3, CGRect(x: 72, y: 600, width: 300, height: 40), "Exercises")
        store.addNote()
        let note = try XCTUnwrap(store.currentNote)
        store.flush()
        store.open(fixture.paper)
        store.closeTab(bookID)
        try await fixture.settle(300)
        let book = try XCTUnwrap(store.library.first { $0.id == bookID })
        store.openSearchResult(workspace: book, note: note)
        XCTAssertEqual(store.workspace?.id, bookID)
        XCTAssertEqual(store.selectedNoteID, note.id)
        try await fixture.settle(600)
        XCTAssertEqual(store.reader.pageNumber, 4, "The page view moves to the note once it shows its book.")
    }

    // MARK: Projects

    @MainActor
    func testRemovingACollectedPassageCanBeUndoneAndRedone() throws {
        let source = try pdf("Book.pdf")
        let store = store()
        store.open(source)
        let projectID = try XCTUnwrap(store.newProject(title: "Project", question: ""))
        store.reader.selection = (0, CGRect(x: 20, y: 150, width: 200, height: 80), "Passage"); store.reader.hasSelection = true
        store.collectSelection(projectID: projectID)
        let passage = try XCTUnwrap(store.project(projectID)?.passages.first)
        let undo = UndoManager(); undo.groupsByEvent = false
        undo.beginUndoGrouping()
        store.removeProjectPassage(passage.id, projectID: projectID, undoManager: undo)
        undo.endUndoGrouping()
        XCTAssertTrue(store.project(projectID)?.passages.isEmpty == true)
        undo.undo()
        XCTAssertEqual(store.project(projectID)?.passages.map(\.id), [passage.id])
        XCTAssertTrue(undo.canRedo)
        undo.redo()
        XCTAssertTrue(store.project(projectID)?.passages.isEmpty == true, "Redo removes the passage again.")
        undo.undo()
        XCTAssertEqual(store.project(projectID)?.passages.map(\.id), [passage.id])
    }

    // MARK: Covers and helpers

    func testAnAnalysisHelperThatLogsALotStillFinishes() async throws {
        let script = root.appendingPathComponent("noisy-helper.sh")
        // More than a pipe holds (64 KB) on standard error, then a progress line and success.
        try "#!/bin/sh\nyes x | head -c 300000 >&2\necho \"progress 1 1\"\nexit 0\n".write(to: script, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)
        let folder: URL = root
        let result = OSAllocatedUnfairLock<BookAnalysisModel.HelperOutcome?>(initialState: nil)
        Task.detached {
            let outcome = await BookAnalysisModel.runHelper(script, source: script, id: "x", root: folder, flag: CancellationFlag(), reporter: ProgressRelay { _, _ in })
            result.withLock { $0 = outcome }
        }
        let deadline = Date.now.addingTimeInterval(20)
        while result.withLock({ $0 }) == nil, Date.now < deadline { try await Task.sleep(for: .milliseconds(100)) }
        guard case .finished? = result.withLock({ $0 }) else { return XCTFail("The helper blocked on its error output.") }
    }
}
