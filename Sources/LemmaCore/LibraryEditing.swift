import Foundation

/// Edits to the library configuration that leave PDFs, folders and notes where they are: which library lists a PDF,
/// how libraries nest and are ordered, and the paths that follow a file or folder renamed or moved by Lemma.
/// Pure functions over the saved collections, so each edit can be tested and undone as a whole.
public enum LibraryEditing {
    /// Whether `path` lies inside the folder `folder`. Keys are compared, so composed accents and symlinks agree.
    public static func contains(folder: String, path: String) -> Bool {
        let folder = LibraryPaths.key(folder)
        return LibraryPaths.key(path).hasPrefix(folder.hasSuffix("/") ? folder : folder + "/")
    }

    /// Whether one of `exclusions` is `path` or a folder containing it.
    static func excludes(_ exclusions: [String], _ path: String) -> Bool {
        let key = LibraryPaths.key(path)
        return exclusions.contains { let excluded = LibraryPaths.key($0); return key == excluded || key.hasPrefix(excluded + "/") }
    }

    /// Whether a collection lists `path` (a PDF or a folder): as a source of its own, or inside one of its watched
    /// folders without an exclusion.
    public static func lists(_ path: String, in collection: LibraryCollection) -> Bool {
        let key = LibraryPaths.key(path)
        return collection.sources.contains { source in
            if LibraryPaths.key(source.path) == key { return true }
            return source.kind == .folder && contains(folder: source.path, path: path) && !excludes(source.excludedPaths, path)
        }
    }

    /// Lists `path` (a PDF or a folder) in a collection: lifts its exclusion from a watched folder, or adds it as a source.
    public static func adding(_ path: String, isFolder: Bool = false, to collectionID: String,
                              in collections: [LibraryCollection]) -> [LibraryCollection] {
        guard let index = collections.firstIndex(where: { $0.id == collectionID }) else { return collections }
        var result = collections
        let key = LibraryPaths.key(path)
        var listed = false
        for source in result[index].sources.indices {
            if LibraryPaths.key(result[index].sources[source].path) == key { listed = true; continue }
            guard result[index].sources[source].kind == .folder, contains(folder: result[index].sources[source].path, path: path) else { continue }
            result[index].sources[source].excludedPaths.removeAll { LibraryPaths.key($0) == key }
            // A folder excluded around it still hides it: the PDF or folder then becomes a source of its own.
            if !excludes(result[index].sources[source].excludedPaths, path) { listed = true }
        }
        if !listed {
            result[index].sources.append(LibrarySource(path: path, kind: isFolder ? .folder : .file, bookmark: LibraryPaths.bookmark(path)))
        }
        return result
    }

    /// Stops listing `path` (a PDF or a folder) in a collection; nothing changes on disk. Sources at or inside it are
    /// removed and the watched folders around it exclude it, so it does not come back at the next scan.
    public static func removing(_ path: String, from collectionID: String, in collections: [LibraryCollection]) -> [LibraryCollection] {
        guard let index = collections.firstIndex(where: { $0.id == collectionID }) else { return collections }
        var result = collections
        let key = LibraryPaths.key(path)
        result[index].sources.removeAll { source in
            let sourceKey = LibraryPaths.key(source.path)
            return sourceKey == key || sourceKey.hasPrefix(key + "/")
        }
        for source in result[index].sources.indices where result[index].sources[source].kind == .folder {
            guard contains(folder: result[index].sources[source].path, path: path),
                  !excludes(result[index].sources[source].excludedPaths, path) else { continue }
            // Exclusions inside a newly excluded folder are now redundant.
            result[index].sources[source].excludedPaths.removeAll { LibraryPaths.key($0).hasPrefix(key + "/") }
            result[index].sources[source].excludedPaths.append(path)
        }
        return result
    }

    /// Moves a PDF or folder from one collection to another (`from` is nil for a book outside every library).
    /// Keeping the source lists the PDF in both, as ⌥-dragging does.
    public static func moving(_ path: String, isFolder: Bool = false, from source: String?, to target: String, keepingSource: Bool = false,
                              in collections: [LibraryCollection]) -> [LibraryCollection] {
        guard source != target else { return collections }
        var result = adding(path, isFolder: isFolder, to: target, in: collections)
        if let source, !keepingSource { result = removing(path, from: source, in: result) }
        return result
    }

    /// Follows a file or folder that moved from `old` to `new`: individual sources, watched folders and exclusions
    /// inside `old` take the new path, and their macOS bookmarks are made again.
    public static func relocating(_ old: String, to new: String, in collections: [LibraryCollection]) -> [LibraryCollection] {
        let oldKey = LibraryPaths.key(old)
        func moved(_ path: String) -> String? {
            let key = LibraryPaths.key(path)
            if key == oldKey { return new }
            if key.hasPrefix(oldKey + "/") { return new + key.dropFirst(oldKey.count) }
            return nil
        }
        return collections.map { collection in
            var collection = collection
            for index in collection.sources.indices {
                if let path = moved(collection.sources[index].path) {
                    collection.sources[index].path = path
                    collection.sources[index].bookmark = LibraryPaths.bookmark(path)
                }
                collection.sources[index].excludedPaths = collection.sources[index].excludedPaths.map { moved($0) ?? $0 }
            }
            return collection
        }
    }

    /// Path-keyed values (names given in Lemma, for instance) after a file or folder moved from `old` to `new`.
    public static func relocating<Value>(keys values: [String: Value], from old: String, to new: String) -> [String: Value] {
        let oldKey = LibraryPaths.key(old), newKey = LibraryPaths.key(new)
        var result: [String: Value] = [:]
        for (key, value) in values {
            if key == oldKey { result[newKey] = value }
            else if key.hasPrefix(oldKey + "/") { result[newKey + key.dropFirst(oldKey.count)] = value }
            else { result[key] = value }
        }
        return result
    }

    /// The top-level library that shows the group `name` inside it: a library named like the group gathers its sub-libraries.
    public static func host(of group: String, in collections: [LibraryCollection]) -> LibraryCollection? {
        collections.first { $0.parent == nil && $0.title.localizedCaseInsensitiveCompare(group) == .orderedSame }
    }

    /// The libraries shown inside `collection` when it hosts a group of the same name.
    public static func children(of collection: LibraryCollection, in collections: [LibraryCollection]) -> [LibraryCollection] {
        guard collection.parent == nil, host(of: collection.title, in: collections)?.id == collection.id else { return [] }
        return collections.filter { $0.id != collection.id && $0.parent.map { $0.localizedCaseInsensitiveCompare(collection.title) == .orderedSame } == true }
    }

    /// Whether a library may move into `parent`: not into itself, and a library with sub-libraries stays at the top level.
    public static func canMove(_ id: String, toParent parent: String?, in collections: [LibraryCollection]) -> Bool {
        guard let collection = collections.first(where: { $0.id == id }) else { return false }
        guard let parent else { return true }
        if collection.parent == nil, collection.title.localizedCaseInsensitiveCompare(parent) == .orderedSame { return false }
        return children(of: collection, in: collections).isEmpty
    }

    /// Moves a library into a group (a section, or the library of that name) or to the top level, before `anchor`
    /// (another library) or at the end.
    public static func moving(collection id: String, toParent parent: String?, before anchor: String?,
                              in collections: [LibraryCollection]) -> [LibraryCollection] {
        guard canMove(id, toParent: parent, in: collections), let index = collections.firstIndex(where: { $0.id == id }) else { return collections }
        var result = collections
        var collection = result.remove(at: index)
        collection.parent = parent?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        if let anchor, anchor != id, let target = result.firstIndex(where: { $0.id == anchor }) { result.insert(collection, at: target) }
        else { result.append(collection) }
        return result
    }

    /// Renames a library. Sub-libraries shown inside it keep following it.
    public static func renaming(collection id: String, to title: String, in collections: [LibraryCollection]) -> [LibraryCollection] {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, let index = collections.firstIndex(where: { $0.id == id }) else { return collections }
        var result = collections
        let children = Set(LibraryEditing.children(of: collections[index], in: collections).map(\.id))
        result[index].title = title
        for child in result.indices where children.contains(result[child].id) { result[child].parent = title }
        return result
    }

    /// A file or folder name typed by the reader, checked before anything is renamed on disk. Returns the reason it cannot be used.
    public static func problem(withFileName name: String) -> String? {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if name.isEmpty { return "A name is required." }
        if name.contains("/") || name.contains(":") { return "Names cannot contain “/” or “:”." }
        if name.hasPrefix(".") { return "A name starting with “.” would hide the file." }
        if name.utf8.count > 250 { return "This name is too long." }
        return nil
    }
}

extension LibraryPaths {
    /// A macOS bookmark that follows the file or folder when it is renamed or moved later.
    public static func bookmark(_ path: String) -> Data? {
        try? URL(fileURLWithPath: path).bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
    }

    /// The title Lemma derives from a PDF's filename.
    public static func title(of path: String) -> String {
        URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent.replacingOccurrences(of: "_", with: " ")
    }
}

/// Names the reader gave to PDFs in Lemma without renaming their files, by path key. A book already studied keeps
/// its name in its workspace instead; this file holds the names of PDFs not opened yet.
public struct LibraryTitleRepository: Sendable {
    public let root: URL
    public init(root: URL) { self.root = root }
    public var file: URL { root.appendingPathComponent("LibraryTitles.json") }
    public func load() -> [String: String] {
        guard let data = try? Data(contentsOf: file) else { return [:] }
        return (try? JSONDecoder().decode([String: String].self, from: data)) ?? [:]
    }
    public func save(_ titles: [String: String]) throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try WorkspaceRepository.encoder.encode(titles).write(to: file, options: .atomic)
    }
}

extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
