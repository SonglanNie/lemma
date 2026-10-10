import Foundation
import Darwin

public enum LibraryKind: String, Codable, CaseIterable, Sendable {
    case books, studying, papers
    public var label: String {
        switch self { case .books: "Books"; case .studying: "Course"; case .papers: "Papers" }
    }
}

/// A reference to an original PDF or a recursively watched directory. Indexing never reads PDF contents.
public struct LibrarySource: Codable, Equatable, Sendable, Identifiable {
    public enum Kind: String, Codable, Sendable { case folder, file }
    public var path: String { didSet { if path != oldValue { id = LibraryPaths.key(path) } } }
    public var kind: Kind
    public var excludedPaths: [String]
    /// macOS tracks the source's identity when its name or containing folder changes.
    public var bookmark: Data?
    /// The path's key (`LibraryPaths.key`), worked out when the path is set rather than at every use: it resolves
    /// the path on disk.
    public private(set) var id: String
    public init(path: String, kind: Kind = .folder, excludedPaths: [String] = [], bookmark: Data? = nil) {
        self.path = path; self.kind = kind; self.excludedPaths = excludedPaths; self.bookmark = bookmark
        id = LibraryPaths.key(path)
    }
    private enum CodingKeys: String, CodingKey { case path, kind, excludedPaths, bookmark }
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        path = try container.decode(String.self, forKey: .path)
        kind = try container.decode(Kind.self, forKey: .kind)
        excludedPaths = try container.decode([String].self, forKey: .excludedPaths)
        bookmark = try container.decodeIfPresent(Data.self, forKey: .bookmark)
        id = LibraryPaths.key(path)
    }
}

public struct LibraryCollection: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var title: String
    public var kind: LibraryKind
    /// Libraries can share a parent (a section such as "School"), while keeping independently watched source folders.
    public var parent: String?
    public var sources: [LibrarySource]
    public var displayTitle: String { title }
    public init(id: String = UUID().uuidString, title: String, kind: LibraryKind, parent: String? = nil, sources: [LibrarySource]) {
        self.id = id; self.title = title; self.kind = kind; self.parent = parent; self.sources = sources
    }

    /// A new reader's libraries: Books (where the Catalog downloads free textbooks) and Papers (where arXiv papers go).
    /// Folders the reader adds become libraries of their own.
    public static func publicDefaults(support: URL) -> [LibraryCollection] {
        [LibraryCollection(id: "books", title: "Books", kind: .books, sources: [LibrarySource(path: support.appendingPathComponent("Books").path)]),
         papers(support: support)]
    }

    public static func papers(support: URL) -> LibraryCollection {
        LibraryCollection(id: "papers", title: "Papers", kind: .papers, sources: [LibrarySource(path: support.appendingPathComponent("Papers").path)])
    }
}

public enum LibraryPaths {
    static func resolve(_ path: String, bookmark: Data?) -> (url: URL, bookmark: Data?) {
        var url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
        var stale = false
        if let bookmark, let resolved = try? URL(resolvingBookmarkData: bookmark, options: [.withoutUI, .withoutMounting],
                                                 relativeTo: nil, bookmarkDataIsStale: &stale),
           FileManager.default.fileExists(atPath: resolved.path) { url = resolved }
        var refreshed = bookmark
        if FileManager.default.fileExists(atPath: url.path), bookmark == nil || stale || url.path != path {
            refreshed = (try? url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)) ?? bookmark
        }
        return (url, refreshed)
    }

    /// macOS filenames may use composed or decomposed accents (cloud folders such as OneDrive often decompose them).
    public static func key(_ path: String) -> String {
        var url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath).standardizedFileURL
        var suffix: [String] = []
        // A removal event names a file that no longer exists. Resolve its existing parent so its key
        // stays the same after deletion (Foundation handles /var and /private/var differently here).
        while true {
            if let resolved = realpath(url.path, nil) {
                defer { free(resolved) }
                var value = URL(fileURLWithPath: String(cString: resolved))
                for part in suffix.reversed() { value.appendPathComponent(part) }
                return value.path.precomposedStringWithCanonicalMapping
            }
            let parent = url.deletingLastPathComponent()
            if parent == url { return url.path.precomposedStringWithCanonicalMapping }
            suffix.append(url.lastPathComponent); url = parent
        }
    }

    /// The title a PDF's filename gives (“Linear_Algebra.pdf” → “Linear Algebra”), from the path's text alone:
    /// `title(of:)` builds a file URL, which asks the disk whether the path is a folder.
    public static func fileTitle(_ path: String) -> String {
        ((path as NSString).lastPathComponent as NSString).deletingPathExtension.replacingOccurrences(of: "_", with: " ")
    }
}

/// A PDF a library lists. Its key, id and title are worked out once, by the scan in the background: the Library tree,
/// the palette and the counts read them at every redraw.
public struct LibraryPDF: Identifiable, Equatable, Sendable {
    public let collectionID: String
    public let path: String
    public let folder: String
    /// The path's key (`LibraryPaths.key`).
    public let key: String
    public let id: String
    /// The title its filename gives.
    public let title: String
    public init(collectionID: String, path: String, folder: String, key: String? = nil) {
        self.collectionID = collectionID; self.path = path; self.folder = folder
        let key = key ?? LibraryPaths.key(path)
        self.key = key
        id = collectionID + ":" + key
        title = LibraryPaths.fileTitle(path)
    }
}

public struct LibraryScan: Sendable {
    public var collections: [LibraryCollection] = []
    public var entries: [LibraryPDF] = []
    public var issues: [String: String] = [:]
    public var workspaceSources: [String: LibrarySourceResolution] = [:]
    public var workspacePaths: [String] = []
    /// The key of every studied book's path (and of the places relocated books were found).
    public var workspaceKeys: [String: String] = [:]
    /// Studied books whose PDF is neither at its path nor where its bookmark leads.
    public var missingWorkspacePaths: Set<String> = []
}

/// What the scan needs of a studied book: where its PDF was, and the bookmark that follows it.
public struct LibraryWorkspaceRef: Sendable, Equatable {
    public let id: String
    public let title: String
    public let sourcePath: String
    public let sourceBookmark: Data?
    public init(id: String, title: String, sourcePath: String, sourceBookmark: Data?) {
        self.id = id; self.title = title; self.sourcePath = sourcePath; self.sourceBookmark = sourceBookmark
    }
    public init(_ workspace: StudyWorkspace) {
        self.init(id: workspace.id, title: workspace.title, sourcePath: workspace.sourcePath, sourceBookmark: workspace.sourceBookmark)
    }
}

public struct LibrarySourceResolution: Sendable {
    public let originalPath: String
    public let path: String
    public let bookmark: Data?
    public init(originalPath: String, path: String, bookmark: Data?) {
        self.originalPath = originalPath; self.path = path; self.bookmark = bookmark
    }
}

public enum LibraryScanner {
    public static func scan(_ collections: [LibraryCollection], workspaces: [StudyWorkspace] = []) -> LibraryScan {
        scan(collections, references: workspaces.map(LibraryWorkspaceRef.init))
    }

    /// Lists the libraries' PDFs, following sources and studied books that moved. Runs in the background and stops
    /// early when its task is cancelled (the caller then ignores the partial result). Each path is resolved on disk
    /// once: a studied book's bookmark only when its PDF is no longer at its path, a folder's key once per folder.
    public static func scan(_ collections: [LibraryCollection], references workspaces: [LibraryWorkspaceRef]) -> LibraryScan {
        let fm = FileManager.default
        var result = LibraryScan()
        result.collections = collections
        var relocations: [String: String] = [:]
        for workspace in workspaces {
            guard !Task.isCancelled else { return result }
            let key = LibraryPaths.key(workspace.sourcePath)
            result.workspaceKeys[workspace.sourcePath] = key
            guard !fm.fileExists(atPath: workspace.sourcePath) else { result.workspacePaths.append(workspace.sourcePath); continue }
            let resolved = LibraryPaths.resolve(workspace.sourcePath, bookmark: workspace.sourceBookmark)
            result.workspacePaths.append(resolved.url.path)
            if resolved.url.path != workspace.sourcePath, fm.fileExists(atPath: resolved.url.path) {
                result.workspaceSources[workspace.id] = LibrarySourceResolution(originalPath: workspace.sourcePath,
                    path: resolved.url.path, bookmark: resolved.bookmark)
                relocations[key] = resolved.url.path
                result.workspaceKeys[resolved.url.path] = LibraryPaths.key(resolved.url.path)
            } else {
                result.missingWorkspacePaths.insert(workspace.sourcePath)
            }
        }
        func key(_ path: String) -> String { result.workspaceKeys[path] ?? LibraryPaths.key(path) }
        for collectionIndex in result.collections.indices {
            for sourceIndex in result.collections[collectionIndex].sources.indices {
                var source = result.collections[collectionIndex].sources[sourceIndex]
                if source.bookmark == nil, source.kind == .file {
                    let original = URL(fileURLWithPath: source.path)
                    let missing = !fm.fileExists(atPath: original.path)
                    let matches = workspaces.filter { workspace in
                        if key(workspace.sourcePath) == source.id { return true }
                        // Earlier collections stored only paths. A book already reopened after a rename
                        // retains its original filename-derived title. Recover only a unique sibling match.
                        let path = result.workspaceSources[workspace.id]?.path ?? workspace.sourcePath
                        return missing && workspace.title == original.deletingPathExtension().lastPathComponent.replacingOccurrences(of: "_", with: " ")
                            && LibraryPaths.key(URL(fileURLWithPath: path).deletingLastPathComponent().path) == LibraryPaths.key(original.deletingLastPathComponent().path)
                    }
                    if matches.count == 1 { source.bookmark = matches[0].sourceBookmark }
                }
                let resolved = LibraryPaths.resolve(source.path, bookmark: source.bookmark)
                if fm.fileExists(atPath: resolved.url.path) {
                    if resolved.url.path != source.path { relocations[source.id] = resolved.url.path }
                    source.path = resolved.url.path; source.bookmark = resolved.bookmark
                }
                result.collections[collectionIndex].sources[sourceIndex] = source
            }
        }
        // Follow explicit Stats PDFs and renamed source folders in other collections' exclusions too.
        let movedPaths = relocations.keys.sorted { $0.count > $1.count }
        if !movedPaths.isEmpty {
            for collectionIndex in result.collections.indices {
                for sourceIndex in result.collections[collectionIndex].sources.indices {
                    result.collections[collectionIndex].sources[sourceIndex].excludedPaths = result.collections[collectionIndex].sources[sourceIndex].excludedPaths.map { path in
                        let key = LibraryPaths.key(path)
                        guard let original = movedPaths.first(where: { key == $0 || key.hasPrefix($0 + "/") }), let moved = relocations[original] else { return path }
                        return moved + key.dropFirst(original.count)
                    }
                }
            }
        }
        for collection in result.collections {
            var seen = Set<String>()
            for source in collection.sources {
                guard !Task.isCancelled else { return result }
                let url = URL(fileURLWithPath: (source.path as NSString).expandingTildeInPath)
                // An excluded path is a PDF, or a folder whose PDFs all left this library.
                let excluded = Set(source.excludedPaths.map(LibraryPaths.key))
                func isExcluded(_ key: String) -> Bool {
                    guard !excluded.isEmpty else { return false }
                    var path = key
                    while true {
                        if excluded.contains(path) { return true }
                        let parent = (path as NSString).deletingLastPathComponent
                        if parent == path || parent.isEmpty { return false }
                        path = parent
                    }
                }
                func append(_ file: URL, key: String, folder: String) {
                    guard file.pathExtension.lowercased() == "pdf", !isExcluded(key), seen.insert(key).inserted else { return }
                    result.entries.append(LibraryPDF(collectionID: collection.id, path: file.path, folder: folder, key: key))
                }
                guard fm.fileExists(atPath: url.path) else {
                    // The Books and Papers folders are created by the first explicit download.
                    if collection.id != "papers", collection.id != "books" { result.issues[collection.id] = "Source unavailable: \(source.path)" }
                    continue
                }
                if source.kind == .file { append(url, key: source.id, folder: ""); continue }
                let keys: Set<URLResourceKey> = [.isRegularFileKey, .isDirectoryKey]
                guard let enumerator = fm.enumerator(at: url, includingPropertiesForKeys: Array(keys), options: [.skipsHiddenFiles, .skipsPackageDescendants], errorHandler: { file, error in
                    result.issues[collection.id] = "Could not list \(file.lastPathComponent): \(error.localizedDescription)"
                    return true
                }) else { result.issues[collection.id] = "Could not list \(source.path)"; continue }
                // The folder shown for a PDF is its directory relative to the watched folder: resolved once per directory.
                let rootComponents = (source.id as NSString).pathComponents.count
                var folders: [String: String] = [:]
                for case let file as URL in enumerator {
                    guard !Task.isCancelled else { return result }
                    let values = try? file.resourceValues(forKeys: keys)
                    if values?.isDirectory == true {
                        if !excluded.isEmpty, excluded.contains(LibraryPaths.key(file.path)) { enumerator.skipDescendants() }
                        continue
                    }
                    guard values?.isRegularFile == true, file.pathExtension.lowercased() == "pdf" else { continue }
                    let directory = file.deletingLastPathComponent().path
                    let folder: String
                    if let known = folders[directory] { folder = known } else {
                        folder = (LibraryPaths.key(directory) as NSString).pathComponents.dropFirst(rootComponents).joined(separator: "/")
                        folders[directory] = folder
                    }
                    append(file, key: LibraryPaths.key(file.path), folder: folder)
                }
            }
        }
        result.entries.sort { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
        return result
    }
}

/// Kept beside the existing workspaces; adding a library never migrates or edits a study workspace.
public struct LibraryCollectionRepository: Sendable {
    public let root: URL
    public init(root: URL) { self.root = root }
    public var file: URL { root.appendingPathComponent("Libraries.json") }
    public func load() throws -> [LibraryCollection]? {
        guard FileManager.default.fileExists(atPath: file.path) else { return nil }
        return try JSONDecoder().decode([LibraryCollection].self, from: Data(contentsOf: file))
    }
    public func save(_ collections: [LibraryCollection]) throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try WorkspaceRepository.encoder.encode(collections).write(to: file, options: .atomic)
    }
}
