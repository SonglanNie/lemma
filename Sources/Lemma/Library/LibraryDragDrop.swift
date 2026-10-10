import SwiftUI
import AppKit
import UniformTypeIdentifiers
import LemmaCore

extension UTType {
    /// Rows dragged inside the Library tree (declared by the app bundle).
    static let lemmaLibraryItems = UTType(exportedAs: "com.lemma.library-items")
}

/// What dropping on the Library does. Dropping on a library changes what it lists and never moves a file;
/// dropping on a folder moves files on disk; libraries dropped on libraries nest or change order.
enum LibraryDropAction: Equatable {
    case moveToLibrary(items: [LibraryItemRef], collectionID: String, keep: Bool)
    case moveIntoFolder(paths: [String], folder: String)
    case moveLibraries(ids: [String], parent: String?, before: String?)
    /// Sections move as a whole, their libraries kept together in order.
    case moveSections(names: [String], before: String?)
    case addToLibrary(urls: [URL], collectionID: String)
    case copyIntoFolder(urls: [URL], folder: String)
    case newLibraries(folders: [URL], parent: String?)
    case none
}

/// Decides what a drop does and how to say it, from what is dragged and where. Pure, so it can be tested.
struct LibraryDropPlanner {
    let collections: [LibraryCollection]
    let rows: [LibraryRow]

    func row(_ id: String?) -> LibraryRow? { id.flatMap { id in rows.first { $0.id == id } } }
    func title(_ collectionID: String) -> String { collections.first { $0.id == collectionID }?.title ?? "the library" }

    /// Where items dropped on `target` land: the library or folder that holds it.
    func container(of target: LibraryRow) -> LibraryRow? {
        switch target.kind {
        case .library, .folder, .section, .unfiled: return target
        default: return row(target.parentID)
        }
    }

    func plan(dragged: [LibraryRow], urls: [URL], target: LibraryRow?, placement: LibraryDropFeedback.Placement,
              option: Bool) -> (action: LibraryDropAction, message: String) {
        if !dragged.isEmpty { return planInternal(dragged, target: target, placement: placement, option: option) }
        return planExternal(urls, target: target)
    }

    private func describe(_ rows: [LibraryRow]) -> String {
        if rows.count == 1 { return "“\(rows[0].title)”" }
        let pdfs = rows.filter(\.isPDF).count, folders = rows.filter(\.isFolder).count
        if folders == 0 { return "\(pdfs) PDFs" }
        if pdfs == 0 { return "\(folders) folders" }
        return "\(rows.count) items"
    }

    private func planInternal(_ dragged: [LibraryRow], target: LibraryRow?, placement: LibraryDropFeedback.Placement,
                              option: Bool) -> (LibraryDropAction, String) {
        let libraries = dragged.filter(\.isLibrary)
        let items = dragged.filter { $0.isPDF || $0.isFolder }
        let sections = dragged.compactMap { row -> String? in if case let .section(name) = row.kind { name } else { nil } }
        if !sections.isEmpty {
            guard libraries.isEmpty, items.isEmpty else { return (.none, "Drag sections on their own") }
            return planSections(sections, target: target, placement: placement)
        }
        if !libraries.isEmpty {
            guard items.isEmpty else { return (.none, "Drag libraries or PDFs, not both") }
            return planLibraries(libraries.compactMap(\.collectionID), target: target, placement: placement)
        }
        guard !items.isEmpty, let target, let container = container(of: target) else {
            return (.none, "Drop on a library to move it there, or on a folder to move the file")
        }
        switch container.kind {
        case let .library(id):
            let refs = items.compactMap { row -> LibraryItemRef? in
                switch row.kind {
                case let .pdf(collectionID, path, bookID): LibraryItemRef(path: path, collectionID: collectionID, bookID: bookID)
                case let .folder(collectionID, path, _): LibraryItemRef(path: path, collectionID: collectionID, isFolder: true)
                default: nil
                }
            }.filter { $0.collectionID != id }
            guard !refs.isEmpty else { return (.none, "Already in \(title(id))") }
            if option { return (.moveToLibrary(items: refs, collectionID: id, keep: true), "Also list \(describe(items)) in \(title(id))") }
            return (.moveToLibrary(items: refs, collectionID: id, keep: false),
                    "Move \(describe(items)) to \(title(id)) · files stay in place · ⌥ keeps \(items.count == 1 ? "it" : "them") here too")
        case let .folder(_, folder, _):
            let folderKey = LibraryPaths.key(folder)
            let paths = items.compactMap(\.path).filter { LibraryPaths.key(URL(fileURLWithPath: $0).deletingLastPathComponent().path) != folderKey }
            guard !paths.isEmpty else { return (.none, "Already in “\(URL(fileURLWithPath: folder).lastPathComponent)”") }
            if paths.contains(where: { LibraryPaths.key($0) == folderKey || LibraryEditing.contains(folder: $0, path: folder) }) {
                return (.none, "A folder cannot move into itself")
            }
            return (.moveIntoFolder(paths: paths, folder: folder), "Move \(describe(items)) into “\(URL(fileURLWithPath: folder).lastPathComponent)” on disk")
        default:
            return (.none, "Drop on a library to move it there, or on a folder to move the file")
        }
    }

    private func planLibraries(_ ids: [String], target: LibraryRow?, placement: LibraryDropFeedback.Placement) -> (LibraryDropAction, String) {
        let names = ids.count == 1 ? title(ids[0]) : "\(ids.count) libraries"
        guard let target else { return (.moveLibraries(ids: ids, parent: nil, before: nil), "Move \(names) to the end of the Library") }
        func after(_ id: String) -> String? {
            guard let index = collections.firstIndex(where: { $0.id == id }) else { return nil }
            return collections.dropFirst(index + 1).first { !ids.contains($0.id) }?.id
        }
        switch target.kind {
        case let .library(id):
            guard let collection = collections.first(where: { $0.id == id }) else { return (.none, "") }
            if ids.contains(id) { return (.none, "") }
            if placement == .into, collection.parent == nil {
                guard ids.allSatisfy({ LibraryEditing.canMove($0, toParent: collection.title, in: collections) }) else {
                    return (.none, "A library with libraries inside stays at the top level")
                }
                return (.moveLibraries(ids: ids, parent: collection.title, before: nil), "Move \(names) into \(collection.title)")
            }
            let anchor = placement == .after ? after(id) : id
            guard ids.allSatisfy({ LibraryEditing.canMove($0, toParent: collection.parent, in: collections) }) else {
                return (.none, "A library with libraries inside stays at the top level")
            }
            return (.moveLibraries(ids: ids, parent: collection.parent, before: anchor),
                    "Move \(names) \(placement == .after ? "after" : "before") \(collection.title)")
        case let .section(name):
            let members = collections.filter { $0.parent?.localizedCaseInsensitiveCompare(name) == .orderedSame }
            if placement == .into {
                guard ids.allSatisfy({ LibraryEditing.canMove($0, toParent: name, in: collections) }) else {
                    return (.none, "A library with libraries inside stays at the top level")
                }
                return (.moveLibraries(ids: ids, parent: name, before: nil), "Move \(names) into \(name)")
            }
            let anchor = placement == .before ? members.first?.id : members.last.flatMap { after($0.id) }
            return (.moveLibraries(ids: ids, parent: nil, before: anchor), "Move \(names) \(placement == .after ? "after" : "before") \(name)")
        case .unfiled:
            return (.moveLibraries(ids: ids, parent: nil, before: nil), "Move \(names) to the end of the Library")
        default:
            if let container = row(target.parentID), container.isLibrary || container.isSection {
                return planLibraries(ids, target: container, placement: .into)
            }
            return (.none, "")
        }
    }

    /// A section goes before or after a top-level library or section; inside a library it would nest, which sections do not.
    private func planSections(_ names: [String], target: LibraryRow?, placement: LibraryDropFeedback.Placement) -> (LibraryDropAction, String) {
        let label = names.count == 1 ? names[0] : "\(names.count) sections"
        func members(_ name: String) -> [LibraryCollection] { collections.filter { $0.parent?.localizedCaseInsensitiveCompare(name) == .orderedSame } }
        let moving = Set(names.flatMap { members($0).map(\.id) })
        func firstAfter(_ id: String) -> String? {
            guard let index = collections.firstIndex(where: { $0.id == id }) else { return nil }
            return collections.dropFirst(index + 1).first { !moving.contains($0.id) }?.id
        }
        guard let target else { return (.moveSections(names: names, before: nil), "Move \(label) to the end of the Library") }
        var top = target
        while top.depth > 0, let parent = row(top.parentID) { top = parent }
        let after = placement == .after || (placement == .into && top.isLibrary)
        switch top.kind {
        case let .library(id):
            return (.moveSections(names: names, before: after ? firstAfter(id) : id), "Move \(label) \(after ? "after" : "before") \(title(id))")
        case let .section(name):
            if names.contains(where: { $0.localizedCaseInsensitiveCompare(name) == .orderedSame }) { return (.none, "") }
            let targetMembers = members(name)
            let anchor = after ? targetMembers.last.flatMap { firstAfter($0.id) } : targetMembers.first?.id
            return (.moveSections(names: names, before: anchor), "Move \(label) \(after ? "after" : "before") \(name)")
        case .unfiled:
            return (.moveSections(names: names, before: nil), "Move \(label) to the end of the Library")
        default:
            return (.none, "")
        }
    }

    private func planExternal(_ urls: [URL], target: LibraryRow?) -> (LibraryDropAction, String) {
        let pdfs = urls.filter { $0.pathExtension.lowercased() == "pdf" }
        let folders = urls.filter { LibraryFileSystem.isDirectory($0.path) }
        guard !pdfs.isEmpty || !folders.isEmpty else { return (.none, "Only PDFs and folders can go in the Library") }
        let what = urls.count == 1 ? "“\(urls[0].lastPathComponent)”" : "\(urls.count) items"
        guard let target, let container = container(of: target) else {
            guard !folders.isEmpty else { return (.none, "Drop PDFs on a library or a folder") }
            return (.newLibraries(folders: folders, parent: nil),
                    folders.count == 1 ? "New library from “\(folders[0].lastPathComponent)”" : "\(folders.count) new libraries from these folders")
        }
        switch container.kind {
        case let .library(id):
            return (.addToLibrary(urls: pdfs + folders, collectionID: id), "Add \(what) to \(title(id)) · files stay in place")
        case let .folder(_, folder, _):
            guard !pdfs.isEmpty else { return (.none, "Drop folders on a library to watch them") }
            return (.copyIntoFolder(urls: pdfs, folder: folder),
                    "Copy \(pdfs.count == 1 ? "“\(pdfs[0].lastPathComponent)”" : "\(pdfs.count) PDFs") into “\(URL(fileURLWithPath: folder).lastPathComponent)”")
        case let .section(name):
            guard !folders.isEmpty else { return (.none, "Drop PDFs on a library or a folder") }
            return (.newLibraries(folders: folders, parent: name), "New library in \(name) from \(folders.count == 1 ? "“\(folders[0].lastPathComponent)”" : "these folders")")
        default:
            return (.none, "Drop on a library or a folder")
        }
    }
}

@MainActor
extension StudyStore {
    /// Carries out a planned drop; moves on disk ask first.
    func performLibraryDrop(_ action: LibraryDropAction, confirmDiskMoves: Bool = true) {
        switch action {
        case let .moveToLibrary(items, collectionID, keep): moveToLibrary(items, collectionID: collectionID, keep: keep)
        case let .moveIntoFolder(paths, folder):
            if confirmDiskMoves { confirmDiskMove(paths, into: folder) } else { moveLibraryItems(paths, intoFolder: folder) }
        case let .moveSections(names, before):
            editLibraryCollections(names.count == 1 ? "Move Section" : "Move Sections") { collections in
                let moving = collections.filter { collection in names.contains { collection.parent?.localizedCaseInsensitiveCompare($0) == .orderedSame } }
                var rest = collections.filter { collection in !moving.contains { $0.id == collection.id } }
                let index = before.flatMap { anchor in rest.firstIndex { $0.id == anchor } } ?? rest.endIndex
                rest.insert(contentsOf: moving, at: index)
                return rest
            }
        case let .moveLibraries(ids, parent, before):
            editLibraryCollections(ids.count == 1 ? "Move Library" : "Move Libraries") { collections in
                ids.reduce(collections) { LibraryEditing.moving(collection: $1, toParent: parent, before: before, in: $0) }
            }
            if let parent { paneExpanded["collection-parent-" + parent] = true
                if let host = LibraryEditing.host(of: parent, in: libraries.collections) { paneExpanded["collection-" + host.id] = true } }
        case let .addToLibrary(urls, collectionID):
            addToLibrary(urls, collectionID: collectionID)
            paneExpanded["collection-" + collectionID] = true
        case let .copyIntoFolder(urls, folder): copyIntoLibraryFolder(urls, folder: folder)
        case let .newLibraries(folders, parent):
            let created = folders.map { folder in
                LibraryCollection(title: folder.lastPathComponent, kind: .studying, parent: parent,
                                  sources: [LibrarySource(path: folder.path, kind: .folder, bookmark: LibraryPaths.bookmark(folder.path))])
            }
            editLibraryCollections(created.count == 1 ? "New Library" : "New Libraries") { $0 + created }
            for collection in created { paneExpanded["collection-" + collection.id] = true }
            if let first = created.first { libraryTree.selection = ["library:" + first.id]; libraryTree.cursor = "library:" + first.id; libraryTree.scrollTarget = "library:" + first.id }
        case .none: break
        }
    }

    /// The drag payload of a row: the reader opens `lemma-book:` and file URLs; Finder takes the file itself.
    func libraryDragProvider(for row: LibraryRow) -> NSItemProvider {
        if row.kind == .unfiled {
            // Other PDFs drags every book in it, to file them all in a library at once.
            var input = libraryTreeInput(); input.expanded["collection-unfiled"] = true; input.query = ""
            libraryTree.dragged = LibraryTreeBuilder(input).rows().filter { $0.parentID == "unfiled" }
        } else {
            let rows = libraryTargets(for: row).filter { $0.isPDF || $0.isFolder || $0.isLibrary || $0.isSection }
            libraryTree.dragged = rows.isEmpty ? [row] : rows
        }
        let provider = NSItemProvider()
        let ids = Data(libraryTree.dragged.map(\.id).joined(separator: "\n").utf8)
        provider.registerDataRepresentation(forTypeIdentifier: UTType.lemmaLibraryItems.identifier, visibility: .all) { completion in
            completion(ids, nil); return nil
        }
        // Finder and other apps receive a copy of the file, never the original to move.
        func copyForOtherApps(_ path: String, type: UTType) {
            guard FileManager.default.fileExists(atPath: path) else { return }
            let url = URL(fileURLWithPath: path)
            provider.registerFileRepresentation(forTypeIdentifier: type.identifier, fileOptions: [], visibility: .all) { completion in
                completion(url, false, nil); return nil
            }
            provider.suggestedName = url.lastPathComponent
        }
        switch row.kind {
        case let .pdf(_, path, bookID):
            let payload = (bookID ?? libraryBook(atPath: path)?.id).map { "lemma-book:" + $0 } ?? URL(fileURLWithPath: path).absoluteString
            provider.registerObject(payload as NSString, visibility: .all)
            copyForOtherApps(path, type: .pdf)
        case let .folder(_, path, _):
            copyForOtherApps(path, type: .folder)
        default:
            provider.registerObject(("lemma-library:" + (row.collectionID ?? "")) as NSString, visibility: .all)
        }
        return provider
    }
}

/// Feedback and drops on one row (or on the space under the rows, with `row` nil).
struct LibraryRowDropDelegate: DropDelegate {
    let store: StudyStore
    let row: LibraryRow?
    var height: CGFloat = VSMetrics.rowHeight

    private func placement(_ info: DropInfo) -> LibraryDropFeedback.Placement {
        guard let row, row.isLibrary || row.isSection || row.kind == .unfiled, !store.libraryTree.dragged.isEmpty,
              store.libraryTree.dragged.allSatisfy({ $0.isLibrary || $0.isSection }),
              info.hasItemsConforming(to: [.lemmaLibraryItems]) else { return .into }
        if info.location.y < height * 0.3 { return .before }
        if info.location.y > height * 0.7 { return .after }
        return .into
    }

    private func isInternal(_ info: DropInfo) -> Bool { info.hasItemsConforming(to: [.lemmaLibraryItems]) && !store.libraryTree.dragged.isEmpty }

    @MainActor private func plan(_ info: DropInfo, urls: [URL] = []) -> (action: LibraryDropAction, message: String, placement: LibraryDropFeedback.Placement) {
        let placement = placement(info)
        let planner = LibraryDropPlanner(collections: store.libraries.collections, rows: store.libraryRows())
        let option = NSEvent.modifierFlags.contains(.option)
        if isInternal(info) {
            let result = planner.plan(dragged: store.libraryTree.dragged, urls: [], target: row, placement: placement, option: option)
            return (result.action, result.message, placement)
        }
        // While hovering, Finder's files are not readable yet: describe them by what the drop allows.
        if urls.isEmpty {
            let target = row.flatMap { planner.container(of: $0) }
            let message: String = switch target?.kind {
            case let .library(id)?: "Add to \(planner.title(id)) · files stay in place"
            case let .folder(_, path, _)?: "Copy PDFs into “\(URL(fileURLWithPath: path).lastPathComponent)”"
            case let .section(name)?: "Drop folders to make libraries in \(name)"
            case nil: "Drop folders to make libraries"
            default: "Drop on a library or a folder"
            }
            let allowed = target == nil || target?.isLibrary == true || target?.isFolder == true || target?.isSection == true
            return (allowed ? .addToLibrary(urls: [], collectionID: "") : .none, message, .into)
        }
        let result = planner.plan(dragged: [], urls: urls, target: row, placement: .into, option: option)
        return (result.action, result.message, .into)
    }

    func validateDrop(info: DropInfo) -> Bool { info.hasItemsConforming(to: [.lemmaLibraryItems, .fileURL]) }

    func dropEntered(info: DropInfo) { update(info) }
    func dropUpdated(info: DropInfo) -> DropProposal? {
        update(info)
        let allowed = MainActor.assumeIsolated { store.libraryTree.drop?.allowed ?? false }
        if !allowed { return DropProposal(operation: .forbidden) }
        if isInternal(info) {
            let disk = MainActor.assumeIsolated { if case .moveIntoFolder = plan(info).action { true } else { false } }
            return DropProposal(operation: disk || !NSEvent.modifierFlags.contains(.option) ? .move : .copy)
        }
        return DropProposal(operation: .copy)
    }
    func dropExited(info: DropInfo) {
        MainActor.assumeIsolated { if store.libraryTree.drop?.rowID == row?.id { store.libraryTree.drop = nil } }
    }

    private func update(_ info: DropInfo) {
        MainActor.assumeIsolated {
            let result = plan(info)
            let feedback = LibraryDropFeedback(rowID: row?.id, placement: result.placement, message: result.message, allowed: result.action != .none)
            if store.libraryTree.drop != feedback { store.libraryTree.drop = feedback }
        }
    }

    func performDrop(info: DropInfo) -> Bool {
        MainActor.assumeIsolated { store.libraryTree.drop = nil }
        if isInternal(info) {
            let action = MainActor.assumeIsolated { plan(info).action }
            MainActor.assumeIsolated {
                store.libraryTree.dragged = []
                store.performLibraryDrop(action)
            }
            return action != .none
        }
        let providers = info.itemProviders(for: [.fileURL])
        guard !providers.isEmpty else { return false }
        let target = row, owner = store
        Task { @MainActor in
            var urls: [URL] = []
            for provider in providers {
                if let url = await Self.loadURL(provider) { urls.append(url) }
            }
            let planner = LibraryDropPlanner(collections: owner.libraries.collections, rows: owner.libraryRows())
            let action = planner.plan(dragged: [], urls: urls, target: target, placement: .into, option: false).action
            owner.performLibraryDrop(action)
        }
        return true
    }

    private static func loadURL(_ provider: NSItemProvider) async -> URL? {
        await withCheckedContinuation { continuation in
            _ = provider.loadObject(ofClass: URL.self) { url, _ in continuation.resume(returning: url) }
        }
    }
}
