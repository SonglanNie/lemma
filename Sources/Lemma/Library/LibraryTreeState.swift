import AppKit
import SwiftUI
import LemmaCore

/// The Library tree's own state: the selection, the keyboard cursor, the name being edited and drag feedback.
@MainActor @Observable
final class LibraryTreeState {
    var selection: Set<String> = []
    /// The row the keyboard is on (VS Code's focused row).
    var cursor: String?
    /// Whether the tree has keyboard focus: selections are drawn in the active colours and the cursor outlined.
    var focused = false
    /// Bumped to ask the tree to take keyboard focus.
    var focusRequest = 0
    var editor: LibraryEditor?
    var drop: LibraryDropFeedback?
    /// A row to bring into view.
    var scrollTarget: String?
    /// Indent guides show while the pointer is over the tree, as in VS Code.
    var hovering = false
    /// Bumped when the order of PDFs changes (it is kept in the defaults).
    var sortRevision = 0
    /// A drag started in the tree is under way: rows keep their counts instead of showing hover actions.
    var dragging = false
    /// The book in front, as the tree shows it. The tree reads this rather than the store's workspace, which
    /// changes at every page turned.
    var activeBookID: String?
    /// The rows last built, with what they were built from.
    @ObservationIgnored var memo: LibraryTreeMemo?
    @ObservationIgnored var anchor: String?
    /// Screen frames of the visible rows (window coordinates), kept for QA only.
    @ObservationIgnored var frames: [String: CGRect] = [:]
    /// The rows being dragged out of the tree.
    @ObservationIgnored var dragged: [LibraryRow] = []
    @ObservationIgnored var typeahead = (text: "", time: Date.distantPast)
    /// Undo for library edits when there is no window (tests).
    @ObservationIgnored var undoManager: UndoManager?
    @ObservationIgnored var revealedBookID: String?

    /// SwiftUI does not say when a drag ends elsewhere: the drag state clears once the mouse button is up.
    func beginDrag() {
        dragging = true
        Task { @MainActor [weak self] in
            while NSEvent.pressedMouseButtons & 1 != 0 { try? await Task.sleep(for: .milliseconds(250)) }
            try? await Task.sleep(for: .milliseconds(300))
            guard let self else { return }
            self.dragging = false
            self.dragged = []
            if self.drop != nil { self.drop = nil }
        }
    }
}

/// The Library's rows are built again only when something they show changes: a scan, a name, the books' titles,
/// progress and due notes, what is open, the filter, the order or the book in front. A page turned or a save of the
/// book being read (which replaces it in the store's library) leaves them as they are unless its progress moved.
struct LibraryTreeMemo {
    struct Book: Equatable {
        let id: String
        let title: String
        let sourcePath: String
        let lastOpenedAt: Date
        let progress: Double?
        let due: Int
    }
    struct Signature: Equatable {
        var libraries: Int
        var books: [Book]
        var query: String
        var sort: LibrarySort
        var expanded: [String: Bool]
        var openTabs: [String]
        var activeBookID: String?
        var creatingIn: String?
    }
    let signature: Signature
    let rows: [LibraryRow]
}

/// A name being typed in the tree: a rename, or a new library.
struct LibraryEditor: Equatable {
    var rowID: String
    var kind: LibraryRow.Kind
    var text: String
    var mode: LibraryRenameMode
    /// The current name for each mode, so switching mode before typing shows the right one.
    var names: [LibraryRenameMode: String]
    var problem: String?
    /// File and Both need the file to be there.
    var fileAvailable = true

    var modes: [LibraryRenameMode] { if case .pdf = kind { LibraryRenameMode.allCases } else { [] } }
    var placeholder: String {
        switch kind {
        case .newLibrary: "Library name"
        case .section: "Section name"
        case .library: "Library name"
        case .folder: "Folder name"
        default: mode == .file ? "File name" : "Name in Lemma"
        }
    }
    /// What the field changes, under it.
    var caption: String? {
        switch kind {
        case .folder: "Renames the folder on disk"
        case .newLibrary: "Drop PDFs or folders on it next"
        default: nil
        }
    }
}

/// What a drop onto the tree would do, shown while dragging.
struct LibraryDropFeedback: Equatable {
    var rowID: String?
    enum Placement: Equatable { case into, before, after }
    var placement: Placement = .into
    var message: String
    var allowed = true
}

enum LibraryKey: Equatable {
    case up, down, left, right, home, end, pageUp, pageDown, rename, open, openAndFocus, trash, escape, selectAll
    case character(String)
}

@MainActor
extension StudyStore {
    var librarySort: LibrarySort {
        get { libraryTree.sortRevision >= 0 ? LibrarySort.current : .name }
        set { LibrarySort.current = newValue; libraryTree.sortRevision += 1 }
    }

    func libraryTreeInput(expandingAll: Bool = false) -> LibraryTreeInput { libraryTreeInput(expandingAll: expandingAll, activeBookID: workspace?.id) }

    /// The name field of a library being created, by its parent group (empty for the top level).
    private var libraryCreatingIn: String? {
        if case let .newLibrary(parent)? = libraryTree.editor?.kind { return parent ?? "" }
        return nil
    }

    func libraryTreeInput(expandingAll: Bool, activeBookID: String?) -> LibraryTreeInput {
        let creating = libraryCreatingIn
        var expanded = paneExpanded
        if expandingAll {
            // Every container open, to find where a book is.
            expanded = [:]
            for collection in libraries.collections {
                expanded["collection-" + collection.id] = true
                if let parent = collection.parent { expanded["collection-parent-" + parent] = true }
            }
            expanded["collection-unfiled"] = true
        }
        // Keys of the books' paths come from the libraries' scan (or are worked out once): the tree never asks the disk.
        var keys: [String: String] = [:]
        for book in library { keys[book.sourcePath] = libraries.key(of: book.sourcePath) }
        return LibraryTreeInput(collections: libraries.collections, entries: libraries.entries, books: library, titles: libraries.titles,
                                issues: libraries.issues, isScanning: libraries.isScanning, query: libraryQuery, sort: librarySort,
                                expanded: expanded, openTabs: Set(tabs.map(\.id)), activeBookID: activeBookID, creatingIn: creating,
                                expandFolders: expandingAll, keys: keys, missing: libraries.missingPaths)
    }

    /// The visible rows of the Library.
    func libraryRows() -> [LibraryRow] { libraryRows(activeBookID: workspace?.id) }

    /// The visible rows, built again only when something they show changed (`LibraryTreeMemo`).
    func libraryRows(activeBookID: String?) -> [LibraryRow] {
        let now = Date.now
        let books = library.map { book in
            LibraryTreeMemo.Book(id: book.id, title: book.title, sourcePath: book.sourcePath, lastOpenedAt: book.lastOpenedAt, progress: book.progress,
                                 due: book.notes.reduce(0) { count, note in note.isDue(at: now) ? count + 1 : count })
        }
        let signature = LibraryTreeMemo.Signature(libraries: libraries.revision, books: books, query: libraryQuery, sort: librarySort,
                                                  expanded: paneExpanded, openTabs: tabs.map(\.id), activeBookID: activeBookID, creatingIn: libraryCreatingIn)
        if let memo = libraryTree.memo, memo.signature == signature { return memo.rows }
        var input = libraryTreeInput(expandingAll: false, activeBookID: activeBookID)
        input.now = now
        let rows = LibraryTreeBuilder(input).rows()
        libraryTree.memo = LibraryTreeMemo(signature: signature, rows: rows)
        return rows
    }

    func libraryRow(_ id: String) -> LibraryRow? { libraryRows().first { $0.id == id } }

    // MARK: Expanding

    func setLibraryRow(_ row: LibraryRow, expanded: Bool) {
        guard libraryQuery.isEmpty, let key = LibraryTreeBuilder.expansionKey(row.kind) else { return }
        if (paneExpanded[key] ?? LibraryTreeBuilder.expandedByDefault(row.kind)) != expanded { paneExpanded[key] = expanded }
    }

    func toggleLibraryRow(_ row: LibraryRow) { setLibraryRow(row, expanded: !row.expanded) }

    /// Closes every library, section and folder (VS Code's Collapse Folders in Explorer).
    func collapseLibrary() {
        var panes = paneExpanded
        for key in panes.keys where key.hasPrefix("collection-") || key.hasPrefix("library-folder-") { panes[key] = false }
        for collection in libraries.collections where panes["collection-" + collection.id] == nil { panes["collection-" + collection.id] = false }
        panes["collection-unfiled"] = false
        paneExpanded = panes
    }

    // MARK: Clicking

    /// A click anywhere on a row: ⌘ adds it to the selection, ⇧ selects the range; otherwise it opens a PDF, or opens
    /// and closes a library, section or folder.
    func clickLibraryRow(_ row: LibraryRow, modifiers: NSEvent.ModifierFlags = []) {
        guard row.isSelectable else { return }
        let tree = libraryTree
        if tree.editor != nil, tree.editor?.rowID != row.id { commitLibraryEdit() }
        // A PDF opened by a click takes the keyboard to the page, as VS Code's editor does; other clicks keep it in the tree.
        if !row.isPDF || !modifiers.intersection([.command, .shift]).isEmpty { tree.focusRequest += 1 }
        if modifiers.contains(.command) {
            if tree.selection.contains(row.id) { tree.selection.remove(row.id) } else { tree.selection.insert(row.id) }
            tree.cursor = row.id; tree.anchor = row.id
            return
        }
        if modifiers.contains(.shift), let anchor = tree.anchor {
            let rows = libraryRows().filter(\.isSelectable)
            if let from = rows.firstIndex(where: { $0.id == anchor }), let to = rows.firstIndex(where: { $0.id == row.id }) {
                tree.selection = Set(rows[min(from, to)...max(from, to)].map(\.id))
                tree.cursor = row.id
                return
            }
        }
        tree.selection = [row.id]; tree.cursor = row.id; tree.anchor = row.id
        activateLibraryRow(row, preserveFocus: false)
    }

    /// Opens a PDF, or opens or closes a container.
    func activateLibraryRow(_ row: LibraryRow, preserveFocus: Bool) {
        switch row.kind {
        case .section, .library, .folder, .unfiled: toggleLibraryRow(row)
        case let .pdf(_, path, bookID):
            libraryTree.revealedBookID = bookID ?? libraryBook(atPath: path)?.id
            if let id = bookID, let book = library.first(where: { $0.id == id }) { reopen(book) } else { open(URL(fileURLWithPath: path)) }
            libraryTree.revealedBookID = workspace?.id
            if !preserveFocus, let view = reader.view { view.window?.makeFirstResponder(view) }
        default: break
        }
    }

    func openLibraryRowToSide(_ row: LibraryRow) {
        guard case let .pdf(_, path, bookID) = row.kind else { return }
        if let id = bookID ?? libraryBook(atPath: path)?.id { openBookToTheSide(id) } else { open(URL(fileURLWithPath: path), toSide: true) }
    }

    /// The rows an action applies to: the selection when the row is part of it, otherwise the row alone.
    func libraryTargets(for row: LibraryRow) -> [LibraryRow] {
        guard libraryTree.selection.contains(row.id), libraryTree.selection.count > 1 else { return [row] }
        return libraryRows().filter { libraryTree.selection.contains($0.id) }
    }

    func libraryItem(_ row: LibraryRow) -> LibraryItemRef? {
        switch row.kind {
        case let .pdf(collectionID, path, bookID): LibraryItemRef(path: path, collectionID: collectionID, bookID: bookID)
        case let .folder(collectionID, path, _): LibraryItemRef(path: path, collectionID: collectionID, isFolder: true)
        default: nil
        }
    }

    // MARK: Revealing

    /// Selects the book in front in the Library, opening the libraries and folders around it.
    @discardableResult
    func revealInLibrary(bookID: String? = nil, scroll: Bool = true) -> Bool {
        // Before the first scan every studied book looks unfiled: wait for the libraries to be listed.
        guard let id = bookID ?? workspace?.id, libraries.updatedAt != nil else { return false }
        let all = LibraryTreeBuilder(libraryTreeInput(expandingAll: true)).rows()
        guard let row = all.first(where: { $0.bookID == id }) else { return false }
        var ancestor = row.parentID
        while let current = ancestor, let parent = all.first(where: { $0.id == current }) {
            if libraryQuery.isEmpty, let key = LibraryTreeBuilder.expansionKey(parent.kind), paneExpanded[key] != true { paneExpanded[key] = true }
            ancestor = parent.parentID
        }
        // Only what changes is written: the tree redraws when its selection really moves.
        if libraryTree.selection != [row.id] { libraryTree.selection = [row.id] }
        if libraryTree.cursor != row.id { libraryTree.cursor = row.id }
        if libraryTree.anchor != row.id { libraryTree.anchor = row.id }
        if scroll { libraryTree.scrollTarget = row.id }
        if libraryTree.revealedBookID != id { libraryTree.revealedBookID = id }
        return true
    }

    // MARK: Editing names

    func beginLibraryRename(_ row: LibraryRow, mode: LibraryRenameMode? = nil) {
        guard row.isRenamable else { return }
        var names: [LibraryRenameMode: String] = [:]
        var chosen = LibraryRenameMode.lemma
        var available = true
        switch row.kind {
        case let .section(name): names[.lemma] = name
        case let .library(id): names[.lemma] = libraries.collections.first { $0.id == id }?.title ?? row.title
        case let .folder(_, path, _):
            names[.file] = URL(fileURLWithPath: path).lastPathComponent; chosen = .file
        case let .pdf(_, path, _):
            let title = libraryTitle(forPath: path)
            names = [.lemma: title, .file: URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent, .both: title]
            available = FileManager.default.fileExists(atPath: path)
            chosen = available ? (mode ?? .remembered) : .lemma
        default: return
        }
        libraryTree.editor = LibraryEditor(rowID: row.id, kind: row.kind, text: names[chosen] ?? row.title, mode: chosen, names: names, fileAvailable: available)
        libraryTree.selection = [row.id]; libraryTree.cursor = row.id; libraryTree.scrollTarget = row.id
    }

    /// A name field for a new library, at the top level or inside a section or library.
    func beginNewLibrary(in parent: String? = nil) {
        reveal(.library)
        libraryQuery = ""
        if let parent {
            paneExpanded["collection-parent-" + parent] = true
            if let host = LibraryEditing.host(of: parent, in: libraries.collections) { paneExpanded["collection-" + host.id] = true }
        }
        let id = "new:" + (parent ?? "")
        libraryTree.editor = LibraryEditor(rowID: id, kind: .newLibrary(parent: parent), text: "", mode: .lemma, names: [:])
        libraryTree.scrollTarget = id
    }

    func setLibraryRenameMode(_ mode: LibraryRenameMode) {
        guard var editor = libraryTree.editor, editor.modes.contains(mode), mode == .lemma || editor.fileAvailable else { return }
        if editor.text == editor.names[editor.mode] { editor.text = editor.names[mode] ?? editor.text }
        editor.mode = mode
        editor.problem = libraryEditProblem(editor)
        libraryTree.editor = editor
        LibraryRenameMode.remembered = mode
    }

    func updateLibraryEditText(_ text: String) {
        guard var editor = libraryTree.editor else { return }
        editor.text = text
        editor.problem = libraryEditProblem(editor)
        libraryTree.editor = editor
    }

    /// Why the typed name cannot be used yet, checked as it is typed for names on disk.
    func libraryEditProblem(_ editor: LibraryEditor) -> String? {
        let text = editor.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        let path: String
        var name: String
        switch editor.kind {
        case let .folder(_, folder, _): path = folder; name = text
        case let .pdf(_, file, _) where editor.mode != .lemma:
            path = file
            name = editor.mode == .both ? LibraryFileSystem.fileName(fromTitle: text) : text
            if (name as NSString).pathExtension.lowercased() != "pdf" { name += ".pdf" }
        default: return nil
        }
        if let problem = LibraryEditing.problem(withFileName: editor.mode == .both ? LibraryFileSystem.fileName(fromTitle: text) : text) { return problem }
        let current = URL(fileURLWithPath: path)
        let destination = current.deletingLastPathComponent().appendingPathComponent(name)
        let sameFile = destination.path.precomposedStringWithCanonicalMapping.lowercased() == current.path.precomposedStringWithCanonicalMapping.lowercased()
        if !sameFile, FileManager.default.fileExists(atPath: destination.path) {
            return "“\(name)” already exists in “\(current.deletingLastPathComponent().lastPathComponent)”. Choose another name."
        }
        return nil
    }

    func cancelLibraryEdit() {
        guard libraryTree.editor != nil else { return }
        libraryTree.editor = nil
        libraryTree.focusRequest += 1
    }

    /// Applies the typed name. A problem keeps the field open with the reason under it.
    @discardableResult
    func commitLibraryEdit() -> Bool {
        guard var editor = libraryTree.editor else { return false }
        let text = editor.text.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty { cancelLibraryEdit(); return false }
        if let problem = libraryEditProblem(editor) { editor.problem = problem; libraryTree.editor = editor; return false }
        do {
            var selected = editor.rowID
            switch editor.kind {
            case let .newLibrary(parent):
                libraryTree.editor = nil
                if let id = createLibrary(title: text, parent: parent) { selected = "library:" + id }
            case let .section(name):
                if text != name { renameLibraryGroup(name, to: text); selected = "section:" + text }
            case let .library(id):
                if text != editor.names[.lemma] { renameLibraryCollection(id, to: text) }
            case let .folder(collectionID, path, _):
                if text != editor.names[.file] { selected = "folder:\(collectionID):" + (try renameLibraryFolder(path, to: text)) }
            case let .pdf(collectionID, path, bookID):
                let unchanged = switch editor.mode {
                case .lemma: text == editor.names[.lemma]
                case .file: text == editor.names[.file]
                case .both: text == editor.names[.lemma] && LibraryFileSystem.fileName(fromTitle: text) == editor.names[.file]
                }
                if !unchanged {
                    let newPath = try renameLibraryPDF(path: path, bookID: bookID, to: text, mode: editor.mode)
                    selected = collectionID.map { "pdf:\($0):\(LibraryPaths.key(newPath))" } ?? editor.rowID
                }
            default: break
            }
            libraryTree.editor = nil
            libraryTree.selection = [selected]; libraryTree.cursor = selected; libraryTree.anchor = selected
            libraryTree.scrollTarget = selected
            libraryTree.focusRequest += 1
            return true
        } catch {
            editor.problem = error.localizedDescription
            libraryTree.editor = editor
            return false
        }
    }

    // MARK: Keyboard

    /// Arrows move and open, Return renames, Space opens and keeps the focus, ⌘↓ opens, ⌘⌫ moves to the Trash,
    /// letters jump to a name.
    @discardableResult
    func handleLibraryKey(_ key: LibraryKey, extend: Bool = false) -> Bool {
        let tree = libraryTree
        if tree.editor != nil { if key == .escape { cancelLibraryEdit(); return true }; return false }
        let rows = libraryRows().filter(\.isSelectable)
        guard !rows.isEmpty else { return false }
        let index = tree.cursor.flatMap { id in rows.firstIndex { $0.id == id } }
        func move(to target: Int) {
            let target = max(0, min(rows.count - 1, target))
            let row = rows[target]
            tree.cursor = row.id
            if extend, let anchor = tree.anchor, let from = rows.firstIndex(where: { $0.id == anchor }) {
                tree.selection = Set(rows[min(from, target)...max(from, target)].map(\.id))
            } else {
                tree.selection = [row.id]; tree.anchor = row.id
            }
            tree.scrollTarget = row.id
        }
        switch key {
        case .down: move(to: (index ?? -1) + 1)
        case .up: move(to: (index ?? rows.count) - 1)
        case .home: move(to: 0)
        case .end: move(to: rows.count - 1)
        case .pageDown: move(to: (index ?? 0) + 12)
        case .pageUp: move(to: (index ?? 0) - 12)
        case .right:
            guard let index else { move(to: 0); return true }
            let row = rows[index]
            if row.expandable && !row.expanded { setLibraryRow(row, expanded: true) }
            else if row.expandable, index + 1 < rows.count, rows[index + 1].parentID == row.id { move(to: index + 1) }
        case .left:
            guard let index else { move(to: 0); return true }
            let row = rows[index]
            if row.expandable && row.expanded { setLibraryRow(row, expanded: false) }
            else if let parent = row.parentID, let target = rows.firstIndex(where: { $0.id == parent }) { move(to: target) }
        case .rename:
            guard let index else { return false }
            beginLibraryRename(rows[index])
        case .open, .openAndFocus:
            guard let index else { return false }
            activateLibraryRow(rows[index], preserveFocus: key == .open)
        case .trash:
            let selected = rows.filter { tree.selection.contains($0.id) }
            let files = selected.compactMap { libraryItem($0)?.path }
            if !files.isEmpty { confirmTrash(files) }
            else if let library = selected.first(where: \.isLibrary), case let .library(id) = library.kind { confirmRemoveLibrary(id) }
            else { return false }
        case .escape:
            guard !tree.selection.isEmpty else { return false }
            tree.selection = []
        case .selectAll:
            tree.selection = Set(rows.map(\.id))
        case let .character(text):
            let now = Date.now
            tree.typeahead = (now.timeIntervalSince(tree.typeahead.time) < 0.9 ? tree.typeahead.text + text : text, now)
            let typed = tree.typeahead.text
            let start = (index ?? -1) + (typed.count == 1 ? 1 : 0)
            let ordered = Array(rows[max(0, start)...]) + Array(rows[..<max(0, start)])
            guard let match = ordered.first(where: { $0.title.lowercased().hasPrefix(typed.lowercased()) }),
                  let target = rows.firstIndex(where: { $0.id == match.id }) else { return true }
            move(to: target)
        }
        return true
    }
}
