import Foundation
import LemmaCore

/// How PDFs are ordered inside a library or folder. Libraries keep the order the reader gives them by dragging.
enum LibrarySort: String, CaseIterable, Identifiable {
    case name, recent, progress
    var id: String { rawValue }
    var label: String {
        switch self { case .name: "Name"; case .recent: "Recently Opened"; case .progress: "Reading Progress" }
    }
    static var current: LibrarySort {
        get { UserDefaults.standard.string(forKey: "library.sort").flatMap(LibrarySort.init(rawValue:)) ?? .name }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: "library.sort") }
    }
}

/// One visible row of the Library tree. The tree is flattened into rows, as VS Code's lists are, so a click anywhere
/// on a row, the keyboard and drag and drop all work on the same list.
struct LibraryRow: Identifiable, Equatable {
    enum Kind: Equatable {
        /// A group of libraries that no library of the same name hosts.
        case section(String)
        case library(String)
        /// A directory inside a watched folder of a library.
        case folder(collectionID: String, path: String, relative: String)
        /// A PDF of a library, or a studied book outside every library (`collectionID` nil).
        case pdf(collectionID: String?, path: String, bookID: String?)
        /// Studied books outside every library.
        case unfiled
        /// A line of explanation under a library: empty, scanning, or a source problem.
        case message(collectionID: String, warning: Bool)
        /// The name field of a library being created.
        case newLibrary(parent: String?)
    }

    let id: String
    let kind: Kind
    let depth: Int
    /// The row this one is shown inside.
    let parentID: String?
    var title: String
    var icon = "file-pdf"
    var expandable = false
    var expanded = false
    var count: Int? = nil
    var progress: Double? = nil
    var due = 0
    /// The file is not where Lemma last saw it.
    var missing = false
    var isOpenInTab = false
    /// The book in front of the reader.
    var isActive = false
    /// The filename, shown beside a name given in Lemma.
    var detail: String? = nil
    var help = ""

    var path: String? {
        switch kind {
        case let .pdf(_, path, _), let .folder(_, path, _): path
        default: nil
        }
    }
    var collectionID: String? {
        switch kind {
        case let .library(id), let .folder(id, _, _), let .message(id, _): id
        case let .pdf(id, _, _): id
        default: nil
        }
    }
    var bookID: String? { if case let .pdf(_, _, id) = kind { id } else { nil } }
    var isPDF: Bool { if case .pdf = kind { true } else { false } }
    var isFolder: Bool { if case .folder = kind { true } else { false } }
    var isLibrary: Bool { if case .library = kind { true } else { false } }
    var isSection: Bool { if case .section = kind { true } else { false } }
    /// Rows the keyboard and the selection can stop on.
    var isSelectable: Bool {
        switch kind { case .message, .newLibrary: false; default: true }
    }
    /// Libraries, sections and folders can be renamed; PDFs in Lemma, on disk or both.
    var isRenamable: Bool {
        switch kind { case .section, .library, .folder, .pdf: true; default: false }
    }
}

/// What the tree is built from, so it can be built in tests without a window.
struct LibraryTreeInput {
    var collections: [LibraryCollection]
    var entries: [LibraryPDF]
    var books: [StudyWorkspace]
    var titles: [String: String] = [:]
    var issues: [String: String] = [:]
    var isScanning = false
    var query = ""
    var sort = LibrarySort.name
    var expanded: [String: Bool] = [:]
    var openTabs: Set<String> = []
    var activeBookID: String? = nil
    /// A library being created: the parent group of its name field (empty for the top level).
    var creatingIn: String? = nil
    /// Folders open too (to find where a book is).
    var expandFolders = false
    var now = Date.now
    /// Keys of the studied books' paths, known already (entries carry their own); others are worked out on disk.
    var keys: [String: String] = [:]
    /// Studied books' paths whose PDF is gone, as the last scan found; nil asks the disk.
    var missing: Set<String>? = nil
}

/// Builds the visible rows of the Library: libraries in the reader's order, a section where its first library stands,
/// sub-libraries inside the library whose name their group bears, then folders before PDFs, and Other PDFs last.
struct LibraryTreeBuilder {
    let input: LibraryTreeInput
    private let booksByKey: [String: StudyWorkspace]
    private let keyOfPath: [String: String]
    private let query: String

    init(_ input: LibraryTreeInput) {
        self.input = input
        var keys = input.keys
        for entry in input.entries where keys[entry.path] == nil { keys[entry.path] = entry.key }
        var books: [String: StudyWorkspace] = [:]
        for book in input.books {
            let key = keys[book.sourcePath] ?? LibraryPaths.key(book.sourcePath)
            keys[book.sourcePath] = key
            if books[key] == nil { books[key] = book }
        }
        keyOfPath = keys
        booksByKey = books
        query = input.query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: Expansion keys (shared with the 2.1 tree, so what the reader opened stays open)

    static func expansionKey(_ kind: LibraryRow.Kind) -> String? {
        switch kind {
        case let .library(id): "collection-" + id
        case let .section(name): "collection-parent-" + name
        case .unfiled: "collection-unfiled"
        case let .folder(collectionID, _, relative): "library-folder-" + collectionID + ":" + relative
        default: nil
        }
    }

    static func expandedByDefault(_ kind: LibraryRow.Kind) -> Bool {
        switch kind {
        case let .library(id): id == "books" || id == "study-stats"
        case .unfiled: true
        default: false
        }
    }

    private func isExpanded(_ kind: LibraryRow.Kind) -> Bool {
        if !query.isEmpty { return true }
        if input.expandFolders, case .folder = kind { return true }
        guard let key = Self.expansionKey(kind) else { return false }
        return input.expanded[key] ?? Self.expandedByDefault(kind)
    }

    // MARK: Names

    func key(_ path: String) -> String { keyOfPath[path] ?? LibraryPaths.key(path) }
    func book(at path: String) -> StudyWorkspace? { booksByKey[key(path)] }
    func book(for entry: LibraryPDF) -> StudyWorkspace? { booksByKey[entry.key] }

    /// The name a PDF has in Lemma: its book's title, a name given before opening it, or its filename.
    func title(of path: String) -> String {
        if let book = book(at: path) { return book.title }
        return input.titles[key(path)] ?? LibraryPaths.fileTitle(path)
    }

    func title(of entry: LibraryPDF) -> String {
        if let book = book(for: entry) { return book.title }
        return input.titles[entry.key] ?? entry.title
    }

    func matches(_ text: String) -> Bool { query.isEmpty || text.localizedStandardContains(query) }

    /// Studied books that no library lists, except files sent to the Trash.
    var unfiledBooks: [StudyWorkspace] {
        let listed = Set(input.entries.map(\.key))
        return input.books.filter { book in
            !listed.contains(key(book.sourcePath)) && !book.sourcePath.contains("/.Trash/") && !book.sourcePath.contains("/.Trashes/")
        }
    }

    // MARK: Rows

    func rows() -> [LibraryRow] {
        var rows: [LibraryRow] = []
        let entriesByCollection = Dictionary(grouping: input.entries, by: \.collectionID)
        var emittedSections = Set<String>()
        var hosted = Set<String>()
        for collection in input.collections where collection.parent == nil {
            for child in LibraryEditing.children(of: collection, in: input.collections) { hosted.insert(child.id) }
        }
        for collection in input.collections {
            if let parent = collection.parent {
                guard !hosted.contains(collection.id), !emittedSections.contains(parent.lowercased()) else { continue }
                emittedSections.insert(parent.lowercased())
                let members = input.collections.filter { $0.parent?.localizedCaseInsensitiveCompare(parent) == .orderedSame }
                rows += sectionRows(parent, members: members, entries: entriesByCollection)
            } else {
                rows += libraryRows(collection, depth: 0, parentID: nil, entries: entriesByCollection)
            }
        }
        // The name field stands where the new library will be: after the others.
        if input.creatingIn == "" { rows.append(newLibraryRow(parent: nil, depth: 0, parentID: nil)) }
        rows += unfiledRows()
        return rows
    }

    private func newLibraryRow(parent: String?, depth: Int, parentID: String?) -> LibraryRow {
        LibraryRow(id: "new:" + (parent ?? ""), kind: .newLibrary(parent: parent), depth: depth, parentID: parentID, title: "", icon: "mortar-board")
    }

    private func sectionRows(_ name: String, members: [LibraryCollection], entries: [String: [LibraryPDF]]) -> [LibraryRow] {
        let kind = LibraryRow.Kind.section(name)
        let id = "section:" + name
        let nameMatches = matches(name)
        // A closed section shows nothing below it (while filtering, every container is open).
        let expanded = isExpanded(kind)
        var children: [LibraryRow] = []
        if expanded {
            for member in members {
                children += libraryRows(member, depth: 1, parentID: id, entries: entries, forced: nameMatches)
            }
            if input.creatingIn.map({ $0.localizedCaseInsensitiveCompare(name) == .orderedSame }) == true {
                children.append(newLibraryRow(parent: name, depth: 1, parentID: id))
            }
        }
        guard query.isEmpty || nameMatches || children.contains(where: { !$0.isNewLibraryRow }) else { return [] }
        let count = Set(members.flatMap { entries[$0.id] ?? [] }.map(\.key)).count
        var row = LibraryRow(id: id, kind: kind, depth: 0, parentID: nil, title: name, icon: "folder-library", expandable: true, expanded: expanded, count: count)
        row.help = "\(name) · \(members.count) \(members.count == 1 ? "library" : "libraries") · \(count) PDF\(count == 1 ? "" : "s")"
        return [row] + (expanded ? children : [])
    }

    private func libraryRows(_ collection: LibraryCollection, depth: Int, parentID: String?, entries: [String: [LibraryPDF]],
                             forced: Bool = false) -> [LibraryRow] {
        let kind = LibraryRow.Kind.library(collection.id)
        let id = "library:" + collection.id
        let own = entries[collection.id] ?? []
        let titleMatches = forced || matches(collection.title) || matches(collection.displayTitle)
        let subLibraries = depth == 0 ? LibraryEditing.children(of: collection, in: input.collections) : []
        // A closed library shows nothing below it (while filtering, every container is open): its folders and PDFs
        // are not even sorted then.
        let expanded = isExpanded(kind)
        var children: [LibraryRow] = []
        if expanded {
            for sub in subLibraries {
                children += libraryRows(sub, depth: depth + 1, parentID: id, entries: entries, forced: titleMatches)
            }
            if depth == 0, input.creatingIn.map({ $0.localizedCaseInsensitiveCompare(collection.title) == .orderedSame }) == true {
                children.append(newLibraryRow(parent: collection.title, depth: depth + 1, parentID: id))
            }
            let visible = titleMatches ? own : own.filter { matches(title(of: $0)) || matches($0.folder) }
            children += contentRows(visible, collectionID: collection.id, depth: depth + 1, parentID: id)
        }
        guard query.isEmpty || titleMatches || children.contains(where: { !$0.isNewLibraryRow }) else { return [] }
        let count = Set((own + subLibraries.flatMap { entries[$0.id] ?? [] }).map(\.key)).count
        if expanded && query.isEmpty {
            if let issue = input.issues[collection.id] {
                children.insert(LibraryRow(id: "message:\(collection.id):issue", kind: .message(collectionID: collection.id, warning: true),
                                           depth: depth + 1, parentID: id, title: issue, icon: "warning", help: issue), at: 0)
            }
            if own.isEmpty && subLibraries.isEmpty {
                let text = input.isScanning ? "Looking for PDFs…"
                    : collection.kind == .papers ? "Add a paper from the arXiv Catalog, or drop PDFs here."
                    : collection.sources.isEmpty ? "Empty. Drop PDFs or folders here."
                    : "New PDFs in its folders will appear here."
                children.append(LibraryRow(id: "message:\(collection.id):empty", kind: .message(collectionID: collection.id, warning: false),
                                           depth: depth + 1, parentID: id, title: text, icon: "info", help: text))
            }
        }
        var row = LibraryRow(id: id, kind: kind, depth: depth, parentID: parentID, title: collection.title, icon: Self.icon(collection.kind),
                             expandable: true, expanded: expanded, count: count)
        let folders = collection.sources.filter { $0.kind == .folder }.count, files = collection.sources.count - folders
        var parts = ["\(collection.kind.label) · \(collection.title)", "\(count) PDF\(count == 1 ? "" : "s")"]
        if folders > 0 { parts.append("\(folders) watched folder\(folders == 1 ? "" : "s")") }
        if files > 0 { parts.append("\(files) PDF\(files == 1 ? "" : "s") added one by one") }
        row.help = parts.joined(separator: " · ")
        return [row] + (expanded ? children : [])
    }

    static func icon(_ kind: LibraryKind) -> String {
        switch kind { case .books: "library"; case .studying: "mortar-board"; case .papers: "file-text" }
    }

    /// Folders, then PDFs, under a library: the folders of its watched sources, nested as on disk.
    private func contentRows(_ entries: [LibraryPDF], collectionID: String, depth: Int, parentID: String) -> [LibraryRow] {
        final class Folder {
            let path: String, relative: String, title: String
            var folders: [String: Folder] = [:]
            var pdfs: [LibraryPDF] = []
            var count = 0
            init(path: String, relative: String, title: String) { self.path = path; self.relative = relative; self.title = title }
        }
        let root = Folder(path: "", relative: "", title: "")
        for entry in entries {
            let components = entry.folder.split(separator: "/").map(String.init)
            var directories: [String] = []
            // From the path's text: a file URL would ask the disk whether each path is a folder.
            var directory = (entry.path as NSString).deletingLastPathComponent
            for _ in components { directories.insert(directory, at: 0); directory = (directory as NSString).deletingLastPathComponent }
            var node = root
            node.count += 1
            for (index, name) in components.enumerated() {
                let path = directories[index]
                let next = node.folders[path] ?? Folder(path: path, relative: components[...index].joined(separator: "/"), title: name)
                node.folders[path] = next
                node = next
                node.count += 1
            }
            node.pdfs.append(entry)
        }
        var rows: [LibraryRow] = []
        func emit(_ folder: Folder, depth: Int, parentID: String) {
            for child in folder.folders.values.sorted(by: { $0.title.localizedStandardCompare($1.title) == .orderedAscending }) {
                let kind = LibraryRow.Kind.folder(collectionID: collectionID, path: child.path, relative: child.relative)
                let id = "folder:\(collectionID):\(child.path)"
                let expanded = isExpanded(kind)
                var row = LibraryRow(id: id, kind: kind, depth: depth, parentID: parentID, title: child.title,
                                     icon: expanded ? "folder-opened" : "folder", expandable: true, expanded: expanded, count: child.count)
                row.help = "\(child.path) · \(child.count) PDF\(child.count == 1 ? "" : "s")"
                rows.append(row)
                if expanded { emit(child, depth: depth + 1, parentID: id) }
            }
            for entry in sorted(folder.pdfs) {
                rows.append(pdfRow(path: entry.path, book: book(for: entry), title: title(of: entry), fileTitle: entry.title, collectionID: collectionID,
                                   id: "pdf:\(collectionID):\(entry.key)", depth: depth, parentID: parentID))
            }
        }
        emit(root, depth: depth, parentID: parentID)
        return rows
    }

    private func sorted(_ entries: [LibraryPDF]) -> [LibraryPDF] {
        let titled = entries.map { (entry: $0, title: title(of: $0), book: book(for: $0)) }
        let byName: ((LibraryPDF, String, StudyWorkspace?), (LibraryPDF, String, StudyWorkspace?)) -> Bool = {
            $0.1.localizedStandardCompare($1.1) == .orderedAscending
        }
        let ordered: [(entry: LibraryPDF, title: String, book: StudyWorkspace?)]
        switch input.sort {
        case .name: ordered = titled.sorted(by: byName)
        case .recent:
            ordered = titled.sorted { a, b in
                switch (a.book?.lastOpenedAt, b.book?.lastOpenedAt) {
                case let (x?, y?): x == y ? byName(a, b) : x > y
                case (_?, nil): true
                case (nil, _?): false
                default: byName(a, b)
                }
            }
        case .progress:
            ordered = titled.sorted { a, b in
                let x = a.book?.progress ?? -1, y = b.book?.progress ?? -1
                return x == y ? byName(a, b) : x > y
            }
        }
        return ordered.map(\.entry)
    }

    private func pdfRow(path: String, book: StudyWorkspace?, title: String, fileTitle: String, collectionID: String?, id: String,
                        depth: Int, parentID: String?) -> LibraryRow {
        var row = LibraryRow(id: id, kind: .pdf(collectionID: collectionID, path: path, bookID: book?.id), depth: depth, parentID: parentID, title: title)
        row.progress = book?.progress
        row.due = book.map { $0.notes.reduce(0) { count, note in note.isDue(at: input.now) ? count + 1 : count } } ?? 0
        row.isOpenInTab = book.map { input.openTabs.contains($0.id) } ?? false
        row.isActive = book != nil && book?.id == input.activeBookID
        if title != fileTitle { row.detail = (path as NSString).lastPathComponent }
        row.help = "\(title) · \(path)"
        return row
    }

    private func unfiledRows() -> [LibraryRow] {
        let unfiled = unfiledBooks
        let books = unfiled.filter { matches($0.title) }
        guard !books.isEmpty else { return [] }
        let expanded = isExpanded(.unfiled)
        var row = LibraryRow(id: "unfiled", kind: .unfiled, depth: 0, parentID: nil, title: "Other PDFs", icon: "inbox",
                             expandable: true, expanded: expanded, count: unfiled.count)
        row.help = "Books you studied that no library lists"
        guard expanded else { return [row] }
        let ordered = sortedBooks(books)
        return [row] + ordered.map { book in
            var pdf = pdfRow(path: book.sourcePath, book: book, title: book.title, fileTitle: LibraryPaths.fileTitle(book.sourcePath),
                             collectionID: nil, id: "book:" + book.id, depth: 1, parentID: "unfiled")
            pdf.missing = input.missing.map { $0.contains(book.sourcePath) } ?? !FileManager.default.fileExists(atPath: book.sourcePath)
            if pdf.missing { pdf.help = "\(book.title) · the file is no longer at \(book.sourcePath)" }
            return pdf
        }
    }

    private func sortedBooks(_ books: [StudyWorkspace]) -> [StudyWorkspace] {
        switch input.sort {
        case .name: books.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        case .recent: books.sorted { $0.lastOpenedAt > $1.lastOpenedAt }
        case .progress: books.sorted { ($0.progress ?? -1) > ($1.progress ?? -1) }
        }
    }
}

extension LibraryRow {
    var isNewLibraryRow: Bool { if case .newLibrary = kind { true } else { false } }
}
