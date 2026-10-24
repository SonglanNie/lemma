import AppKit
import PDFKit
import SwiftUI
import LemmaCore
import Observation

/// What every window shares: the library of books and its files, the projects, the assistants, notebooks and helpers,
/// the reader's view preferences and the saved session. Each window has its own workbench (`StudyStore`): its tabs, the
/// book in front, its panels and layout.
///
/// A book is open in at most one window. Opening it from another window brings its window forward, and moving a tab
/// hands the book over, so two windows never edit the same book.
@MainActor @Observable
final class AppModel {
    let repository: WorkspaceRepository
    let mailbox: BrowserMailbox
    let questions: QuestionRuntime
    @ObservationIgnored let covers: LibraryCovers
    let libraries: DynamicLibraries
    /// Fingerprints of PDFs already read, by file, so opening a known and unchanged file reads none of its bytes.
    @ObservationIgnored let fingerprints: FingerprintCache
    /// Python notebooks: interpreters and one kernel per running notebook.
    @ObservationIgnored let lab = LabRuntime()
    /// Books, papers and cited works the reader asked to download.
    let downloads = PDFDownloads()
    /// Terms and index entries of the books in the library, for Look Up across books.
    @ObservationIgnored let libraryGlossary = LibraryGlossary()
    /// Boxes of pages floating above the windows.
    @ObservationIgnored lazy var floatingBoxes = FloatingBoxes(app: self)
    /// Full-text search across the library (the VS Code style's Search view).
    @ObservationIgnored lazy var librarySearch = LibraryTextSearch(cacheFolder: repository.root.appendingPathComponent("Indexes", isDirectory: true))

    /// Every studied book, the most recently opened first. A window's book in front may be ahead of its row here: the
    /// row is replaced when something the lists show changes, and when the book is left (`current(_:)` gives the newest).
    var library: [StudyWorkspace] = []
    /// Saved books that could not be read at launch: their files are kept, and their tabs stay in the saved session.
    @ObservationIgnored var unreadableWorkspaces: [WorkspaceLoadFailure] = []
    var projects: [ResearchProject] = []
    @ObservationIgnored var projectsWritable = true
    @ObservationIgnored var projectsDirty = false
    @ObservationIgnored var projectSaveTask: Task<Void, Never>?
    /// Passwords of locked PDFs opened in this session, by fingerprint; never written anywhere.
    @ObservationIgnored var passwords: [String: String] = [:]
    /// Books opened with a password: the analysis helper cannot read them, so they are not sent to it.
    @ObservationIgnored var lockedFingerprints: Set<String> = []

    /// Page miniatures beside the page, as an editor's minimap.
    var showMinimap = UserDefaults.standard.object(forKey: "editor.minimap.enabled") as? Bool ?? true {
        didSet { UserDefaults.standard.set(showMinimap, forKey: "editor.minimap.enabled") }
    }
    /// The minimap's slider all the time, or only under the pointer as VS Code does by default.
    var minimapSliderAlways = UserDefaults.standard.string(forKey: "editor.minimap.showSlider") == "always" {
        didSet { UserDefaults.standard.set(minimapSliderAlways ? "always" : "mouseover", forKey: "editor.minimap.showSlider") }
    }
    /// Which panes of the side bar views are open (“OUTLINE”, “TIMELINE”…).
    var paneExpanded: [String: Bool] = (UserDefaults.standard.dictionary(forKey: "workbench.panes") as? [String: Bool]) ?? [:] {
        didSet { UserDefaults.standard.set(paneExpanded, forKey: "workbench.panes") }
    }

    /// The windows' workbenches, in the order they were opened. Their windows own them, so a workbench whose window
    /// closed while others stay open is let go with it.
    var windows: [StudyStore] { registered.compactMap(\.store) }
    @ObservationIgnored private var registered: [WeakStore] = []
    /// Workbenches that no window shows: restored, or made for a dropped tab, before their window appears, and the
    /// last window's once it closed, which the next window shows. The window that shows one takes it over.
    @ObservationIgnored private var waiting: [StudyStore] = []
    /// The workbench of the window in front, which the menus act on and whose reading time is counted. There is always
    /// one: before any window appears, the first window's is made.
    var front: StudyStore {
        if let id = frontID, let store = window(id) { return store }
        return windows.first ?? waitingStore(StudyStore(app: self, id: session.windows.first?.id ?? UUID()))
    }
    private var frontID: UUID? {
        didSet { if oldValue != frontID { for store in windows { store.tracker?.frontChanged() } } }
    }

    /// The session as saved: each window's workbench, and the side editors of every open book.
    @ObservationIgnored var session = WorkbenchSession()
    @ObservationIgnored var hasSavedSession = false
    @ObservationIgnored var sessionWritable = true
    /// The session as last written, so an unchanged session is not written again.
    @ObservationIgnored var lastSessionData: Data?
    /// session.json stays pretty-printed: it is small and people read it.
    @ObservationIgnored let sessionEncoder: JSONEncoder = { let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]; return encoder }()
    /// What could not be read at launch, said by the first window once it is restored.
    @ObservationIgnored var startupError: String?
    @ObservationIgnored private(set) var restored = false
    /// The saved windows are being restored: the session is written once they all are, or the windows not restored yet
    /// would be left out of it.
    @ObservationIgnored private var restoring = false
    /// Opens a window for a workbench; set by the first window, which has SwiftUI's action.
    @ObservationIgnored var openWindow: ((UUID) -> Void)?
    /// Lemma is quitting: windows closing now stay in the session.
    @ObservationIgnored var quitting = false
    @ObservationIgnored private var preparedForTermination = false

    var sessionURL: URL { repository.root.appendingPathComponent("session.json") }

    init(root supportRoot: URL? = nil) {
        let root = supportRoot ?? ProcessInfo.processInfo.environment["LEMMA_SUPPORT_DIR"].map { URL(fileURLWithPath: $0, isDirectory: true) }
            ?? WorkspaceRepository.defaultRoot
        repository = WorkspaceRepository(root: root)
        mailbox = BrowserMailbox(root: root)
        questions = QuestionRuntime(root: root.appendingPathComponent("Assistants", isDirectory: true))
        covers = LibraryCovers(root: root)
        fingerprints = FingerprintCache(root: root)
        let newLibrarySources = !FileManager.default.fileExists(atPath: root.appendingPathComponent("Libraries.json").path)
        libraries = DynamicLibraries(root: root, defaults: LibraryCollection.publicDefaults(support: root))
        do {
            // Each workspace is decoded once (the library sources above read the same, now cached, files).
            let listing = try repository.listing()
            library = listing.workspaces
            unreadableWorkspaces = listing.failures
            if !listing.failures.isEmpty { startupError = StudyStore.unreadableMessage(listing.failures) }
        } catch {
            // Without the library, saving the session would forget every open tab: keep the saved one as it is.
            sessionWritable = false
            startupError = "Could not read the study library: \(error.localizedDescription)"
        }
        do { projects = try ProjectRepository(root: root).load() }
        catch { projectsWritable = false; startupError = "Could not read the projects. Their saved file has been kept: \(error.localizedDescription)" }
        if FileManager.default.fileExists(atPath: sessionURL.path) {
            do {
                let data = try Data(contentsOf: sessionURL)
                session = try JSONDecoder().decode(WorkbenchSession.self, from: data); hasSavedSession = true
                lastSessionData = data
            }
            catch { sessionWritable = false; startupError = "Could not restore the editor session. Its saved file has been kept: \(error.localizedDescription)" }
        }
        // The earlier one-book list could be only one row tall. Make the new collection tree visible once, when its
        // sources are first installed; subsequent user resizing remains fully persistent.
        if newLibrarySources, libraries.collections.count > 1 {
            for index in session.windows.indices where (session.windows[index].layout.explorerHeights[ExplorerPane.library.id] ?? 220) < 120 {
                session.windows[index].layout.explorerHeights[ExplorerPane.library.id] = 220
            }
        }
        libraries.sourcesResolved = { [weak self] sources in self?.relinkSources(sources) }
        // Library scans take the studied books from memory rather than decoding every workspace again.
        libraries.workspaceReferences = { [weak self] in self?.library.map(LibraryWorkspaceRef.init) ?? [] }
    }

    // MARK: Windows

    func register(_ store: StudyStore) {
        registered.removeAll { $0.store == nil }
        registered.append(WeakStore(store: store))
    }

    /// Keeps a workbench that no window shows yet.
    private func waitingStore(_ store: StudyStore) -> StudyStore {
        waiting.append(store)
        return store
    }

    /// Forgets a workbench whose window closed while others stay open.
    private func remove(_ store: StudyStore) {
        registered.removeAll { $0.store === store || $0.store == nil }
        waiting.removeAll { $0 === store }
    }

    func window(_ id: UUID) -> StudyStore? { windows.first { $0.id == id } }

    /// The window whose tabs hold this book (or that shows it), if any.
    func owner(of bookID: String) -> StudyStore? {
        windows.first { $0.workspace?.id == bookID } ?? windows.first { $0.tabs.contains { $0.id == bookID } }
    }

    /// The newest version of a book: the one in front of its window, or its library row.
    func current(_ book: StudyWorkspace) -> StudyWorkspace {
        windows.lazy.compactMap(\.workspace).first { $0.id == book.id } ?? book
    }

    /// The workbench for a window SwiftUI shows: the one it names, else the first one without a window, else a new one.
    func claimWindow(_ id: UUID?) -> StudyStore {
        let store: StudyStore
        if !restored {
            // The first window shows the first saved workbench, restored into it now.
            store = front
            store.hasWindow = true
            restore()
        } else {
            store = id.flatMap(window) ?? windows.first { !$0.hasWindow } ?? StudyStore(app: self)
            store.hasWindow = true
        }
        store.windowRequested = false
        // The window owns its workbench from now on.
        waiting.removeAll { $0 === store }
        return store
    }

    /// Shows the saved windows that no window shows yet, once the first one is up.
    func openRestoredWindows() {
        for store in windows where !store.hasWindow { requestWindow(store) }
    }

    /// A new, empty window (File › New Window), with the Welcome page when that is the startup editor.
    @discardableResult
    func newWindow() -> StudyStore {
        // The last window closed kept its workbench for the next window; a new window starts empty instead.
        for store in windows where !store.hasWindow && !store.windowRequested && restored { store.discard(); remove(store) }
        let store = waitingStore(StudyStore(app: self))
        store.placement = WindowPlacement.beside(front.mainWindow)
        store.takeLayout(of: front)
        store.startEmpty()
        requestWindow(store)
        frontID = store.id
        return store
    }

    /// The window that came to the front: the menus act on its workbench from now on.
    func windowDidBecomeKey(_ window: NSWindow) {
        guard let store = windows.first(where: { $0.mainWindow === window }) else { return }
        frontID = store.id
    }

    /// A window closes: its workbench is saved, and let go unless it is the last one (which the next window shows).
    func windowWillClose(_ window: NSWindow) {
        guard let store = windows.first(where: { $0.mainWindow === window }) else { return }
        store.flush()
        store.windowClosed()
        // Quitting closes no window here, but a logout may: the session keeps every window then.
        guard !quitting, windows.contains(where: { $0 !== store && $0.hasWindow }) else {
            // Kept for the next window, now that its window no longer holds it.
            if !waiting.contains(where: { $0 === store }) { waiting.append(store) }
            return
        }
        store.discard()
        remove(store)
        if frontID == store.id { frontID = windows.first { $0.hasWindow }?.id }
        saveSession()
    }

    /// Brings a workbench's window to the front, opening it if it has none.
    func show(_ store: StudyStore) {
        if let window = store.mainWindow, store.hasWindow { window.makeKeyAndOrderFront(nil) } else { requestWindow(store) }
        frontID = store.id
    }

    /// Opens a window for a workbench that has none, once: SwiftUI could open two for two requests made before the
    /// first window appears.
    func requestWindow(_ store: StudyStore) {
        guard let openWindow, !store.hasWindow, !store.windowRequested else { return }
        store.windowRequested = true
        openWindow(store.id)
    }

    // MARK: Moving books between windows

    /// Moves a book's tab into another window, at a tab's place (or at the end), and shows it there. The source window
    /// hands over its loaded document and what was built from it, so nothing is read again; left with no tab, it
    /// closes, as a browser window does.
    func moveBook(_ id: String, to destination: StudyStore, onto targetID: String? = nil) {
        guard let source = owner(of: id), source !== destination, let handover = source.handOverBook(id) else { return }
        destination.receive(handover, onto: targetID)
        show(destination)
        if source.tabs.isEmpty, source.specialTabs.isEmpty, source.hasWindow, let window = source.mainWindow { window.close() }
        saveSession()
    }

    /// Moves a book into a window of its own, its top left corner at a point on the screen (where a tab was dropped).
    func moveBookToNewWindow(_ id: String, topLeft: NSPoint? = nil) {
        guard let source = owner(of: id) else { return }
        // A window's only tab dragged out takes its window along, as a browser's does.
        if source.tabs.count == 1, source.specialTabs.isEmpty, let window = source.mainWindow {
            if let topLeft { window.setFrameTopLeftPoint(topLeft) }
            return
        }
        guard let handover = source.handOverBook(id) else { return }
        let store = waitingStore(StudyStore(app: self))
        store.placement = topLeft.map { WindowPlacement.at($0, like: source.mainWindow) } ?? WindowPlacement.beside(source.mainWindow)
        store.takeLayout(of: source)
        store.receive(handover, onto: nil)
        requestWindow(store)
        frontID = store.id
        saveSession()
    }

    // MARK: Session

    /// Restores the saved windows, once: the first into the first window's workbench, the others into workbenches of
    /// their own, which `openRestoredWindows()` shows.
    func restore() {
        guard !restored else { return }
        restored = true; restoring = true
        // Quitting saves and stops helpers even once every window is closed, and works while a sheet is shown.
        AppLifecycle.shared.attach(self)
        PageThemeState.shared.theme = front.pageTheme
        // A book is open in one window: a later window's tab of a book already restored is dropped.
        var seen = Set<String>()
        var saved: [WindowSession] = []
        for var window in session.windows {
            window.bookIDs = window.bookIDs.filter { seen.insert($0).inserted }
            if let active = window.activeBookID, !window.bookIDs.contains(active) { window.activeBookID = nil }
            saved.append(window)
        }
        front.restore(saved.first, first: true)
        for window in saved.dropFirst() { waitingStore(StudyStore(app: self, id: window.id)).restore(window, first: false) }
        floatingBoxes.restore(session.floatingBoxes, hidden: session.floatingBoxesHidden)
        restoring = false
        saveSession()
        if let message = startupError { startupError = nil; front.notify(message, severity: .error) }
    }

    /// Writes the session when it changed (it is compared with what was last written, so the many calls made while
    /// working cost an encoding of a few kilobytes and no disk write).
    func saveSession() {
        guard sessionWritable, !restoring else { return }
        for store in windows { store.rememberBookEditors() }
        session.windows = windows.map(\.windowSession)
        // Editors of books no window holds are let go with the books.
        let open = Set(session.windows.flatMap(\.bookIDs))
        session.books = session.books.filter { open.contains($0.key) }
        session.floatingBoxes = floatingBoxes.boxes; session.floatingBoxesHidden = floatingBoxes.hidden
        do {
            let data = try sessionEncoder.encode(session)
            guard data != lastSessionData else { return }
            if lastSessionData == nil { try FileManager.default.createDirectory(at: repository.root, withIntermediateDirectories: true) }
            try data.write(to: sessionURL, options: .atomic)
            lastSessionData = data
        } catch { front.error = "Could not save the editor session: \(error.localizedDescription)" }
    }

    // MARK: Projects

    var projectRepository: ProjectRepository { ProjectRepository(root: repository.root) }

    func updateProject(_ id: UUID, _ edit: (inout ResearchProject) -> Void) {
        guard projectsWritable, let index = projects.firstIndex(where: { $0.id == id }) else { return }
        edit(&projects[index]); projects[index].updatedAt = .now
        projectsDirty = true
        projectSaveTask?.cancel()
        projectSaveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            self?.flushProjects()
        }
    }

    func flushProjects() {
        projectSaveTask?.cancel(); projectSaveTask = nil
        guard projectsWritable, projectsDirty else { return }
        do { try projectRepository.save(projects); projectsDirty = false }
        catch { front.error = "Could not save the project: \(error.localizedDescription)" }
    }

    // MARK: Library

    /// A library book's PDF read for a view beside the book in front (a side editor, a floating box): drawn in the page
    /// theme, and unlocked with the password given in this session, if any; a locked PDF otherwise shows no pages.
    func libraryDocument(_ book: StudyWorkspace) -> PDFDocument? {
        var url = URL(fileURLWithPath: book.sourcePath)
        if let bookmark = book.sourceBookmark {
            var stale = false
            if let resolved = try? URL(resolvingBookmarkData: bookmark, options: .withoutUI, relativeTo: nil, bookmarkDataIsStale: &stale) { url = resolved }
        }
        guard let loaded = PDFDocument(url: url) else { return nil }
        if loaded.isLocked, let password = passwords[book.fingerprint] { loaded.unlock(withPassword: password) }
        loaded.delegate = ThemedPageProvider.shared
        return loaded
    }

    /// Relinks just the source fields; the windows' PDFs, notes, selection and reading position stay in place.
    func relinkSources(_ sources: [String: LibrarySourceResolution]) {
        for (id, source) in sources {
            guard let index = library.firstIndex(where: { $0.id == id }) else { continue }
            let showing = windows.first { $0.workspace?.id == id }
            do {
                let loaded = try showing?.workspace ?? repository.load(id: id)
                guard var book = loaded, LibraryPaths.key(book.sourcePath) == LibraryPaths.key(source.originalPath) else { continue }
                book.sourcePath = source.path; book.sourceBookmark = source.bookmark
                try repository.save(book)
                showing?.workspace?.sourcePath = source.path; showing?.workspace?.sourceBookmark = source.bookmark
                library[index] = book
            } catch { front.error = "Could not save the PDF's updated location: \(error.localizedDescription)" }
        }
    }

    // MARK: Quitting

    /// Saves, stops notebooks, questions and analysis helpers, and waits for the last writes.
    func prepareForTermination() {
        guard !preparedForTermination else { return }
        preparedForTermination = true; quitting = true
        questions.shutdown()
        for store in windows { store.flush() }
        lab.shutdownAll()
        BookAnalysisModel.terminateHelpers()
        repository.writer.waitUntilIdle()
    }

    /// Closes every window's sheets, so quitting is not held up by one (AppKit does not quit under a sheet).
    func dismissSheets() { for store in windows { store.dismissSheets() } }
}

private struct WeakStore {
    weak var store: StudyStore?
}

/// Where a window opens: where it was last time, at a tab dropped outside every window, or offset from the window in
/// front as macOS cascades windows, so a new window never hides the one it came from.
struct WindowPlacement {
    var topLeft: NSPoint?
    var size: NSSize?

    /// The cascade offset from the window in front.
    static let offset: CGFloat = 24
    /// The smallest window the workbench lays out in (the scene's minimum size).
    static let minimumSize = NSSize(width: 960, height: 640)

    /// Offset from a window, as large as it but no larger than fits on its screen there.
    @MainActor static func beside(_ window: NSWindow?) -> WindowPlacement? {
        guard let window else { return nil }
        return at(NSPoint(x: window.frame.minX + offset, y: window.frame.maxY - offset), like: window)
    }

    /// With its top left corner at a point, as large as a window but no larger than fits on the screen from there.
    @MainActor static func at(_ topLeft: NSPoint, like window: NSWindow?) -> WindowPlacement {
        let size = window?.frame.size ?? minimumSize
        guard let visible = (NSScreen.screens.first { $0.frame.contains(topLeft) } ?? window?.screen ?? NSScreen.main)?.visibleFrame else {
            return WindowPlacement(topLeft: topLeft, size: size)
        }
        return WindowPlacement(topLeft: topLeft, size: NSSize(width: max(minimumSize.width, min(size.width, visible.maxX - topLeft.x)),
                                                              height: max(minimumSize.height, min(size.height, topLeft.y - visible.minY))))
    }
}
