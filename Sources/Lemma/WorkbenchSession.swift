import Foundation
import LemmaCore

enum SidebarPosition: String, Codable, CaseIterable, Identifiable {
    case left, right
    var id: String { rawValue }
    var label: String { rawValue.capitalized }
}

struct WorkbenchLayout: Codable, Equatable {
    var sidebarPosition: SidebarPosition = .left
    var activityBar = true
    var sidebarWidth: Double = 264
    var inspectorWidth: Double = 370
    /// Sizes by pane id throughout the workbench.
    var explorerHeights: [String: Double] = [:]
}

/// Editor state belongs to a book, rather than to whichever book happens to be in front; it moves with the book from
/// window to window.
struct BookEditorState: Codable {
    var editors: [SideEditor]
    var activeEditorID: String?
    var selectedNoteID: UUID?
    var studySection: StudySection
    var referencesQuery: ReferencesQuery?
    var hierarchyKey: ReferenceKey?
    var hierarchyDirection: HierarchyDirection
    var inspectorWasHidden: Bool
    /// Breakpoints and watch expressions of Run and Debug.
    var breakpoints: [LineBreakpoint]
    var watch: [String]
}

/// One window's workbench as it is saved: its tabs, the editors beside the page with no book open, its layout.
struct WindowSession: Codable, Equatable {
    var id: UUID
    var bookIDs: [String] = []
    var activeBookID: String?
    var homeEditors: [SideEditor] = []
    var activeHomeEditorID: String?
    var projectID: UUID?
    var layout = WorkbenchLayout()
    var showLibrary = true
    var showStudy = true
    var showPanel = false
    var panelTab: PanelTab = .references
    var navigator: NavigatorSection = .contents
    /// Welcome, Settings and other special editors open in the main group, and the one in front.
    var specialTabs: [SpecialEditor] = []
    var activeSpecial: SpecialEditor?
    /// The window's frame on the screen.
    var frame: CGRect?
}

/// Kept in the library's support folder, so isolated QA copies and other libraries have their own session.
struct WorkbenchSession: Codable {
    var windows: [WindowSession] = []
    var books: [String: BookEditorState] = [:]
    /// Boxes of pages floating above the windows, which outlive their books' tabs, and whether Hide All put them away.
    var floatingBoxes: [FloatingBox] = []
    var floatingBoxesHidden = false
}

extension WorkbenchSession {
    /// Sessions saved before floating boxes have none.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        windows = try container.decode([WindowSession].self, forKey: .windows)
        books = try container.decode([String: BookEditorState].self, forKey: .books)
        floatingBoxes = try container.decodeIfPresent([FloatingBox].self, forKey: .floatingBoxes) ?? []
        floatingBoxesHidden = try container.decodeIfPresent(Bool.self, forKey: .floatingBoxesHidden) ?? false
    }
}

@MainActor
extension StudyStore {
    func rememberBookEditors() {
        guard let id = workspace?.id else { return }
        app.session.books[id] = BookEditorState(editors: sideEditors, activeEditorID: activeSideEditorID,
            selectedNoteID: selectedNoteID, studySection: studySection, referencesQuery: referencesQuery,
            hierarchyKey: hierarchyKey, hierarchyDirection: hierarchyDirection, inspectorWasHidden: labHidInspector,
            breakpoints: breakpoints, watch: watchExpressions)
    }

    func restoreBookEditors(_ book: StudyWorkspace) {
        guard let saved = app.session.books[book.id] else { labHidInspector = false; breakpoints = []; watchExpressions = []; return }
        breakpoints = saved.breakpoints
        watchExpressions = saved.watch
        sideEditors = saved.editors.filter { editor in
            switch editor {
            case let .page(state):
                // Another book's page is checked against its recorded page count: its PDF is read when the tab is shown,
                // not while the book in front opens.
                guard state.pageIndex >= 0 else { return false }
                if let id = state.bookID, id != book.id {
                    guard let other = library.first(where: { $0.id == id }) else { return false }
                    let pages = (documents[id] ?? sideDocuments[id])?.pageCount ?? other.pageCount
                    return pages.map { state.pageIndex < $0 } ?? true
                }
                return state.pageIndex < (document?.pageCount ?? 0)
            case let .lab(id): return book.labs.contains { $0.id == id }
            case let .derivation(id): return book.derivations.contains { $0.id == id }
            case let .project(id): return projects.contains { $0.id == id && !$0.archived }
            case .map: return true
            }
        }
        activeSideEditorID = sideEditors.contains { $0.id == saved.activeEditorID } ? saved.activeEditorID : sideEditors.last?.id
        selectedNoteID = book.notes.contains { $0.id == saved.selectedNoteID } ? saved.selectedNoteID : book.notes.first?.id
        studySection = saved.studySection
        referencesQuery = saved.referencesQuery
        hierarchyKey = saved.hierarchyKey; hierarchyDirection = saved.hierarchyDirection
        labHidInspector = saved.inspectorWasHidden && sideEditors.contains(where: \.isWide)
        if labHidInspector { showStudy = false }
        // Restarting the app restores the editor, never the execution of a notebook.
        for editor in sideEditors {
            if case let .derivation(id) = editor { checkDerivation(id, delay: 0) }
        }
    }

    /// Writes the session when it changed: this window's workbench beside the others'.
    func saveWorkbench() { app.saveSession() }

    /// This window's workbench as the session saves it. The editors beside the page with no book open are kept while a
    /// book is open, and the panels shown before Zen Mode while it is on.
    var windowSession: WindowSession {
        // Tabs of books whose saved notes could not be read stay in the session, for when they can be read again.
        savedWindow.bookIDs = tabs.map(\.id) + preservedTabIDs.filter { id in !tabs.contains { $0.id == id } }
        savedWindow.activeBookID = workspace?.id
        if workspace == nil { savedWindow.homeEditors = sideEditors; savedWindow.activeHomeEditorID = activeSideEditorID }
        savedWindow.projectID = selectedProjectID; savedWindow.layout = workbenchLayout
        if !focusMode { savedWindow.showLibrary = showLibrary; savedWindow.showStudy = showStudy; savedWindow.showPanel = showPanel }
        savedWindow.panelTab = panelTab; savedWindow.navigator = navigatorSection
        savedWindow.specialTabs = specialTabs; savedWindow.activeSpecial = activeSpecial
        if let frame = mainWindow?.frame, hasWindow { savedWindow.frame = frame }
        return savedWindow
    }

    /// A new window lays out its workbench as the window it comes from does: the same side bars, panel and sizes (as
    /// they were before Zen Mode, if that window is in it).
    func takeLayout(of source: StudyStore) {
        let saved = source.windowSession
        workbenchLayout = saved.layout
        showLibrary = saved.showLibrary; showStudy = saved.showStudy; showPanel = saved.showPanel
        panelTab = saved.panelTab; navigatorSection = saved.navigator
    }

    /// A tab dropped on another takes that tab's place, so a drag to the right lands after the tab dropped on (it landed
    /// before it, and a tab dropped on its right-hand neighbour stayed where it was); dropped after the last tab, it goes last.
    func moveTab(_ id: String, onto targetID: String?) {
        if tabs.move(id, onto: targetID) { saveWorkbench() }
    }

    func moveSideEditor(_ id: String, onto targetID: String) {
        if sideEditors.move(id, onto: targetID) { saveWorkbench() }
    }

    /// A drop on the main group's tab bar, on a tab or after the last one (no target): a book's tab, dragged as
    /// `lemma-tab:<id>`, moves there. A tab from another window brings its book here.
    func dropBookTab(_ values: [String], onto targetID: String?) -> Bool {
        guard let value = values.first, value.hasPrefix("lemma-tab:") else { return false }
        let id = String(value.dropFirst("lemma-tab:".count))
        if tabs.contains(where: { $0.id == id }) { moveTab(id, onto: targetID) } else { app.moveBook(id, to: self, onto: targetID) }
        return true
    }

    /// A tab can go to a window of its own unless it is the window's only editor.
    var canMoveTabToNewWindow: Bool { tabs.count + specialTabs.count > 1 }

    /// A drop on a side editor's tab: another side editor's tab, dragged as `lemma-side:<id>`, takes its place.
    func dropSideTab(_ values: [String], onto targetID: String) -> Bool {
        guard let value = values.first, value.hasPrefix("lemma-side:") else { return false }
        moveSideEditor(String(value.dropFirst("lemma-side:".count)), onto: targetID); return true
    }

    /// Closes the other book tabs together: the kept book comes to the front, none of the others is opened on the way.
    func closeOtherTabs(keeping id: String) {
        closeTabs(Set(tabs.map(\.id) + (workspace.map { [$0.id] } ?? [])).subtracting([id]), preferring: id)
    }

    func shiftBookTab(_ id: String, by offset: Int) {
        guard let index = tabs.firstIndex(where: { $0.id == id }), tabs.indices.contains(index + offset) else { return }
        tabs.swapAt(index, index + offset); saveWorkbench()
    }

    func shiftSideTab(_ id: String, by offset: Int) {
        guard let index = sideEditors.firstIndex(where: { $0.id == id }), sideEditors.indices.contains(index + offset) else { return }
        sideEditors.swapAt(index, index + offset); saveWorkbench()
    }

    func applyLayout(_ preset: LayoutPreset) {
        if focusMode { toggleFocus() }
        workbenchLayout.activityBar = true
        switch preset {
        case .reading:
            showLibrary = true; navigatorSection = .contents; showStudy = false; showPanel = false
            workbenchLayout.sidebarWidth = 236
        case .study:
            showLibrary = true; navigatorSection = .results; showStudy = true; showPanel = false
            workbenchLayout.sidebarWidth = 244; workbenchLayout.inspectorWidth = 354
        case .research:
            showLibrary = true; navigatorSection = .projects; showStudy = false; showPanel = false
            workbenchLayout.sidebarWidth = 250
            if let id = selectedProjectID { openProject(id) }
        case .lab:
            showLibrary = false; showStudy = false; panelTab = .console; showPanel = true
            if openLabID == nil, let notebook = workspace?.labs.first { openLabNotebook(notebook.id) }
        }
        saveWorkbench()
    }
}

extension Array where Element: Identifiable, Element.ID == String {
    /// Moves the element `id` to the place of the element `targetID`, those in between shifting one place toward its old
    /// place, or to the end without a target. False when nothing moves.
    mutating func move(_ id: String, onto targetID: String?) -> Bool {
        guard let source = firstIndex(where: { $0.id == id }) else { return false }
        var target = endIndex - 1
        if let targetID { guard let index = firstIndex(where: { $0.id == targetID }) else { return false }; target = index }
        guard target != source else { return false }
        insert(remove(at: source), at: target)
        return true
    }
}

enum LayoutPreset: String, CaseIterable, Identifiable {
    case reading, study, research, lab
    var id: String { rawValue }
    var label: String { rawValue.capitalized }
    var symbol: String { switch self { case .reading: "book"; case .study: "pencil.and.outline"; case .research: "folder"; case .lab: "flask" } }
}
