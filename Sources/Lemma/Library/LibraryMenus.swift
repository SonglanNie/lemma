import SwiftUI
import AppKit
import LemmaCore

/// The Library's menus, written once: a row's context menu and its “…” button, and the view's “…” menu.
@MainActor
extension StudyStore {
    func libraryMenu(for row: LibraryRow) -> [VSMenuItem] {
        let targets = libraryTargets(for: row)
        let many = targets.count > 1
        switch row.kind {
        case .pdf, .folder:
            return itemMenu(row, targets: targets.filter { $0.isPDF || $0.isFolder }, many: many)
        case let .library(id):
            return libraryRowMenu(id, row: row)
        case let .section(name):
            return [
                .action("Rename Section…", shortcut: "↩") { [self] in beginLibraryRename(row) },
                .action("New Library in \(name)") { [self] in beginNewLibrary(in: name) },
                .separator,
                .action("Ungroup") { [self] in ungroupSection(name) }
            ]
        case .unfiled:
            return [.submenu("Sort PDFs By", sortItems())]
        default:
            return []
        }
    }

    private func itemMenu(_ row: LibraryRow, targets: [LibraryRow], many: Bool) -> [VSMenuItem] {
        let items = targets.compactMap(libraryItem)
        let paths = items.map(\.path)
        let pdfs = targets.filter(\.isPDF)
        let available = paths.allSatisfy { FileManager.default.fileExists(atPath: $0) }
        var menu: [VSMenuItem] = []
        if row.isPDF {
            if many {
                menu.append(.action("Open \(pdfs.count) PDFs", enabled: !pdfs.isEmpty) { [self] in for pdf in pdfs { activateLibraryRow(pdf, preserveFocus: true) } })
            } else {
                menu += [
                    .action("Open") { [self] in activateLibraryRow(row, preserveFocus: false) },
                    .action("Open to the Side") { [self] in openLibraryRowToSide(row) },
                    .action("Open in Preview", enabled: available) {
                        guard let path = row.path else { return }
                        let url = URL(fileURLWithPath: path)
                        if let preview = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Preview") {
                            NSWorkspace.shared.open([url], withApplicationAt: preview, configuration: NSWorkspace.OpenConfiguration())
                        } else { NSWorkspace.shared.open(url) }
                    }
                ]
            }
            menu.append(.separator)
        }
        if !many {
            if row.isPDF {
                menu += [
                    .action("Rename…", shortcut: "↩") { [self] in beginLibraryRename(row) },
                    .action("Rename File on Disk…", enabled: available) { [self] in beginLibraryRename(row, mode: .file) }
                ]
            } else {
                menu.append(.action("Rename Folder…", enabled: available, shortcut: "↩") { [self] in beginLibraryRename(row) })
            }
        }
        // Libraries a PDF or folder can move to, grouped as in the tree.
        let current = Set(items.compactMap(\.collectionID))
        let destinations = libraries.collections.map { collection in
            VSMenuItem.action(collection.parent.map { "\($0) › \(collection.title)" } ?? collection.title, checked: current == [collection.id],
                              enabled: !(current.count == 1 && current.contains(collection.id))) { [self] in
                moveToLibrary(items, collectionID: collection.id)
            }
        }
        let alsoIn = libraries.collections.filter { !current.contains($0.id) }.map { collection in
            VSMenuItem.action(collection.parent.map { "\($0) › \(collection.title)" } ?? collection.title) { [self] in
                moveToLibrary(items, collectionID: collection.id, keep: true)
            }
        }
        menu.append(.submenu("Move to Library", destinations))
        if !alsoIn.isEmpty { menu.append(.submenu("Also List In", alsoIn)) }
        if row.isFolder, !many, case let .folder(collectionID, path, _) = row.kind {
            menu.append(.action("New Library from This Folder") { [self] in
                if let id = libraryFromFolder(path, collectionID: collectionID) {
                    libraryTree.selection = ["library:" + id]; libraryTree.cursor = "library:" + id; libraryTree.scrollTarget = "library:" + id
                }
            })
        }
        if !many, row.isPDF, let book = row.bookID.flatMap({ id in library.first { $0.id == id } }) {
            let projects = activeProjects.map { project in VSMenuItem.action(project.title) { [self] in addBookToProject(book.id, projectID: project.id) } }
            menu.append(.submenu("Add to Project", projects + [.separator, .action("New Project…") { [self] in
                if let id = newProject() { addBookToProject(book.id, projectID: id) }
            }]))
        }
        if items.contains(where: { $0.collectionID != nil }) {
            menu.append(.action(many ? "Remove \(items.count) Items from Library" : "Remove from Library") { [self] in removeFromLibrary(items) })
        }
        menu += [
            .separator,
            .action(many ? "Reveal \(paths.count) Items in Finder" : "Reveal in Finder", enabled: available) {
                NSWorkspace.shared.activateFileViewerSelecting(paths.map { URL(fileURLWithPath: $0) })
            },
            .action(many ? "Copy Paths" : "Copy Path") {
                NSPasteboard.general.clearContents(); NSPasteboard.general.setString(paths.joined(separator: "\n"), forType: .string)
            },
            .separator,
            .action(many ? "Move \(paths.count) Items to Trash…" : "Move to Trash…", enabled: available, shortcut: "⌘⌫") { [self] in confirmTrash(paths) }
        ]
        return menu
    }

    private func libraryRowMenu(_ id: String, row: LibraryRow) -> [VSMenuItem] {
        guard let collection = libraries.collections.first(where: { $0.id == id }) else { return [] }
        let collections = libraries.collections
        var moveTo: [VSMenuItem] = []
        if collection.parent != nil { moveTo.append(.action("Top Level") { [self] in moveLibraryCollection(id, toParent: nil) }) }
        let groups = Array(Set(collections.compactMap(\.parent))).sorted { $0.localizedStandardCompare($1) == .orderedAscending }
        let hosts = collections.filter { $0.parent == nil && $0.id != id }.map(\.title)
        var destinations: [String] = []
        for name in groups + hosts where !destinations.contains(where: { $0.localizedCaseInsensitiveCompare(name) == .orderedSame }) {
            destinations.append(name)
        }
        for group in destinations where group.localizedCaseInsensitiveCompare(collection.parent ?? "") != .orderedSame {
            moveTo.append(.action(group, enabled: LibraryEditing.canMove(id, toParent: group, in: collections)) { [self] in moveLibraryCollection(id, toParent: group) })
        }
        moveTo += [.separator, .action("New Section…", enabled: LibraryEditing.children(of: collection, in: collections).isEmpty) { [self] in
            let name = uniqueSectionName()
            moveLibraryCollection(id, toParent: name)
            paneExpanded["collection-parent-" + name] = true
            if let section = libraryRows().first(where: { $0.id == "section:" + name }) { beginLibraryRename(section) }
        }]
        let kinds = LibraryKind.allCases.map { kind in
            VSMenuItem.action(kind.label, checked: collection.kind == kind) { [self] in setLibraryKind(id, kind) }
        }
        let excluded = collection.sources.reduce(0) { $0 + $1.excludedPaths.count }
        var menu: [VSMenuItem] = [
            .action("Rename…", shortcut: "↩") { [self] in beginLibraryRename(row) },
            .action("Add PDFs…") { [self] in chooseLibrarySources(id, folders: false) },
            .action("Add Watched Folder…") { [self] in chooseLibrarySources(id, folders: true) }
        ]
        if collection.parent == nil { menu.append(.action("New Library Inside") { [self] in beginNewLibrary(in: collection.title) }) }
        menu += [
            .separator,
            .submenu("Move To", moveTo),
            .submenu("Library Type", kinds),
            .separator,
            .action("Reveal Sources in Finder", enabled: !collection.sources.isEmpty) {
                NSWorkspace.shared.activateFileViewerSelecting(collection.sources.map { URL(fileURLWithPath: $0.path) })
            },
            .action("Refresh") { [self] in libraries.refresh() }
        ]
        if excluded > 0 {
            menu.append(.action("List \(excluded) Removed PDF\(excluded == 1 ? "" : "s") Again") { [self] in restoreLibraryExclusions(id) })
        }
        menu += [
            .action("Manage Sources…") { [self] in showLibrarySources = true },
            .separator,
            .action("Remove Library…", shortcut: "⌘⌫") { [self] in confirmRemoveLibrary(id) }
        ]
        return menu
    }

    private func uniqueSectionName() -> String {
        let used = Set(libraries.collections.compactMap { $0.parent?.lowercased() } + libraries.collections.map { $0.title.lowercased() })
        if !used.contains("new section") { return "New Section" }
        return (2...).lazy.map { "New Section \($0)" }.first { !used.contains($0.lowercased()) } ?? "New Section"
    }

    func sortItems() -> [VSMenuItem] {
        LibrarySort.allCases.map { sort in VSMenuItem.action(sort.label, checked: librarySort == sort) { [self] in librarySort = sort } }
    }

    /// The Library view's “…” menu.
    func libraryViewMenu() -> [VSMenuItem] {
        var items: [VSMenuItem] = [
            .action("New Library…") { [self] in beginNewLibrary() },
            .action("New Library from Folder…") { [self] in chooseFolderForNewLibrary() },
            .separator,
            .submenu("Sort PDFs By", sortItems()),
            .action("Collapse All") { [self] in collapseLibrary() }
        ]
        if workspace != nil { items.append(.action("Reveal Book in Library") { [self] in revealInLibrary() }) }
        items += [.separator, .action("Refresh Libraries") { [self] in libraries.refresh() }, .action("Manage Sources…") { [self] in showLibrarySources = true }]
        return items
    }

    func chooseFolderForNewLibrary() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.allowsMultipleSelection = true
        panel.message = "Each folder becomes a library. Lemma watches it, including its subfolders."
        guard panel.runModal() == .OK else { return }
        performLibraryDrop(.newLibraries(folders: panel.urls, parent: nil))
    }
}

/// VS Code-style menu items as SwiftUI menu content, for `.contextMenu`.
struct VSMenuItemsView: View {
    let items: [VSMenuItem]
    var body: some View {
        ForEach(Array(items.enumerated()), id: \.offset) { _, item in
            switch item.kind {
            case let .action(perform):
                if item.checked {
                    Toggle(item.title, isOn: Binding(get: { true }, set: { _ in perform() })).disabled(!item.enabled)
                } else if let shortcut = Self.shortcut(item.shortcut) {
                    Button(item.title) { perform() }.disabled(!item.enabled).keyboardShortcut(shortcut.key, modifiers: shortcut.modifiers)
                } else {
                    Button(item.title) { perform() }.disabled(!item.enabled)
                }
            case let .submenu(children):
                Menu(item.title) { VSMenuItemsView(items: children) }
            case .separator:
                Divider()
            case .header:
                Text(item.title)
            }
        }
    }

    /// The key hints the tree answers to, shown beside their commands.
    static func shortcut(_ text: String?) -> (key: KeyEquivalent, modifiers: EventModifiers)? {
        switch text {
        case "↩": (.return, [])
        case "⌘⌫": (.delete, .command)
        default: nil
        }
    }
}
