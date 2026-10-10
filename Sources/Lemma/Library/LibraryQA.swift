import AppKit
import LemmaCore

/// QA actions for the Library tree (only with LEMMA_QA_DIR): rows with their screen frames, clicks, keys, renames,
/// drops planned and performed, without posting pointer events.
@MainActor
extension StudyStore {
    func performLibraryQA(_ action: String, info: [String: String]) async throws -> Bool {
        let tree = libraryTree
        func row(_ key: String = "id") throws -> LibraryRow {
            let wanted = info[key] ?? ""
            let rows = libraryRows()
            if let row = rows.first(where: { $0.id == wanted }) ?? rows.first(where: { $0.title == wanted }) { return row }
            throw QAHooks.QAError.missing("library row \(wanted)")
        }
        func write(_ object: Any, _ fallback: String) throws {
            guard let directory = QAHooks.shared?.directory else { return }
            let data = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
            try data.write(to: directory.appendingPathComponent("\(info["name"] ?? fallback).json"))
        }
        switch action {
        case "libraryRows":
            let rows: [[String: Any]] = libraryRows().map { row in
                var item: [String: Any] = ["id": row.id, "title": row.title, "depth": row.depth, "kind": "\(row.kind)".components(separatedBy: "(").first ?? "",
                                           "expanded": row.expanded, "selected": tree.selection.contains(row.id), "cursor": tree.cursor == row.id]
                if let count = row.count { item["count"] = count }
                if let progress = row.progress { item["progress"] = progress }
                if let detail = row.detail { item["detail"] = detail }
                if let path = row.path { item["path"] = path }
                if let frame = screenFrame(tree.frames[row.id]) { item["screen"] = [frame.minX, frame.minY, frame.width, frame.height] }
                return item
            }
            var state: [String: Any] = ["rows": rows, "focused": tree.focused, "editing": tree.editor?.rowID ?? "", "problem": tree.editor?.problem ?? "",
                                        "drop": tree.drop?.message ?? "", "sort": librarySort.rawValue, "titles": libraries.titles,
                                        "collections": libraries.collections.map { ["id": $0.id, "title": $0.title, "parent": $0.parent ?? "", "kind": $0.kind.rawValue,
                                                                                    "sources": $0.sources.map { "\($0.kind.rawValue):\($0.path) -\($0.excludedPaths.count)" }] }]
            state["firstResponder"] = mainWindow?.firstResponder.map { String(describing: type(of: $0)) } ?? ""
            state["selectionIDs"] = Array(tree.selection)
            state["revealedBookID"] = tree.revealedBookID ?? ""
            state["workspaceID"] = workspace?.id ?? ""
            state["scannedAt"] = libraries.updatedAt.map { $0.timeIntervalSince1970 } ?? 0
            state["undo"] = libraryUndoManager?.undoActionName ?? ""
            state["redo"] = libraryUndoManager?.redoActionName ?? ""
            try write(state, "library")
        case "libraryClick":
            var modifiers: NSEvent.ModifierFlags = []
            if info["mods"]?.contains("cmd") == true { modifiers.insert(.command) }
            if info["mods"]?.contains("shift") == true { modifiers.insert(.shift) }
            clickLibraryRow(try row(), modifiers: modifiers)
        case "libraryToggle": toggleLibraryRow(try row())
        case "libraryKey":
            let keys: [String: LibraryKey] = ["up": .up, "down": .down, "left": .left, "right": .right, "home": .home, "end": .end,
                                              "return": .rename, "space": .open, "open": .openAndFocus, "escape": .escape, "trash": .trash]
            let key = keys[info["key"] ?? ""] ?? .character(info["key"] ?? "")
            for _ in 0..<(Int(info["count"] ?? "1") ?? 1) { handleLibraryKey(key, extend: info["shift"] == "1") }
        case "libraryFocus": tree.focusRequest += 1
        case "libraryEdit":
            beginLibraryRename(try row(), mode: info["mode"].flatMap(LibraryRenameMode.init(rawValue:)))
            if let text = info["text"] { updateLibraryEditText(text) }
        case "libraryEditMode":
            if let mode = info["mode"].flatMap(LibraryRenameMode.init(rawValue:)) { setLibraryRenameMode(mode) }
        case "libraryEditText": updateLibraryEditText(info["text"] ?? "")
        case "libraryCommit": commitLibraryEdit()
        case "libraryCancel": cancelLibraryEdit()
        case "libraryRename":
            beginLibraryRename(try row(), mode: info["mode"].flatMap(LibraryRenameMode.init(rawValue:)))
            updateLibraryEditText(info["text"] ?? "")
            commitLibraryEdit()
        case "libraryNew":
            beginNewLibrary(in: info["parent"])
            if let text = info["text"] { updateLibraryEditText(text); if info["commit"] != "0" { commitLibraryEdit() } }
        case "libraryDrop":
            // ids=a|b to=<row> placement=into|before|after option=1 perform=1: plans the drop as dragging would, shows its banner,
            // and performs it (moves on disk without asking) unless perform=0.
            let rows = libraryRows()
            let dragged = (info["ids"] ?? "").split(separator: "|").compactMap { id in rows.first { $0.id == id } }
            let target = info["to"].flatMap { id in rows.first { $0.id == id } }
            let urls = (info["urls"] ?? "").split(separator: "|").map { URL(fileURLWithPath: String($0)) }
            let placement: LibraryDropFeedback.Placement = info["placement"] == "before" ? .before : info["placement"] == "after" ? .after : .into
            let plan = LibraryDropPlanner(collections: libraries.collections, rows: rows)
                .plan(dragged: dragged, urls: urls, target: target, placement: placement, option: info["option"] == "1")
            try write(["action": "\(plan.action)", "message": plan.message], "drop")
            if info["perform"] == "0" {
                tree.drop = LibraryDropFeedback(rowID: target?.id, placement: placement, message: plan.message, allowed: plan.action != .none)
            } else {
                tree.drop = nil
                performLibraryDrop(plan.action, confirmDiskMoves: false)
            }
        case "libraryDropClear": tree.drop = nil
        case "libraryMenu":
            func titles(_ items: [VSMenuItem]) -> [Any] {
                items.map { item -> Any in
                    switch item.kind {
                    case let .submenu(children): return [item.title: titles(children)]
                    case .separator: return "—"
                    default: return item.title + (item.enabled ? "" : " (disabled)") + (item.checked ? " ✓" : "")
                    }
                }
            }
            let items = info["id"] == "view" ? libraryViewMenu() : libraryMenu(for: try row())
            try write(titles(items), "menu")
            if let title = info["run"], let item = items.first(where: { $0.title == title }), case let .action(perform) = item.kind { perform() }
        case "libraryFilter": libraryQuery = info["value"] ?? ""
        case "librarySort": librarySort = LibrarySort(rawValue: info["value"] ?? "") ?? .name
        case "libraryCollapse": collapseLibrary()
        case "libraryReveal": revealInLibrary()
        case "librarySelect":
            tree.selection = Set((info["ids"] ?? "").split(separator: "|").map(String.init))
            tree.cursor = tree.selection.first
        case "libraryTrash": trashLibraryItems((info["paths"] ?? "").split(separator: "|").map(String.init))
        case "libraryUndo": libraryUndoManager?.undo()
        case "libraryRedo": libraryUndoManager?.redo()
        case "libraryHover": tree.hovering = info["value"] != "0"
        case "powerSimulate":
            // battery, lowPower, heat, none (nothing to wait for), or real: the Mac's own conditions again.
            let reasons: [String: IndexingPause] = ["battery": .battery, "lowPower": .lowPower, "heat": .heat]
            PowerConditions.simulated = info["value"] == "real" ? nil : .some(reasons[info["value"] ?? ""])
            PageIndexer.shared.conditionsChanged()
        case "pageIndexPane":
            // The page index's pane (Search › Pages in the Classic navigator), to check its progress and pause line.
            reveal(.search); searchNotes = false; searchIndexed = true
            try write(["progress": indexProgress.map { "\($0.status.rawValue) \($0.completedPages)/\($0.totalPages)" } ?? "",
                       "message": indexProgress?.message ?? "", "pause": PageIndexer.shared.pause?.label ?? "",
                       "running": workspace.map { PageIndexer.shared.isRunning($0.id, root: repository.root) } ?? false], "pageindex")
        case "windowKey":
            // Makes the window key inside Lemma without activating Lemma (clicks then reach views that do not accept a first click).
            mainWindow?.makeKey()
            try write(["isKey": mainWindow?.isKeyWindow ?? false, "active": NSApp.isActive], "window")
        case "libraryKeyEvent":
            // A key typed into the window (through NSApp, so menus and key equivalents see it first), without the keyboard.
            guard let window = mainWindow else { throw QAHooks.QAError.missing("window") }
            let keys: [String: (UInt16, String)] = ["return": (36, "\r"), "down": (125, "\u{F701}"), "up": (126, "\u{F700}"),
                                                    "left": (123, "\u{F702}"), "right": (124, "\u{F703}"), "space": (49, " "), "escape": (53, "\u{1B}")]
            let (code, characters) = keys[info["key"] ?? ""] ?? (0, info["key"] ?? "a")
            var modifiers: NSEvent.ModifierFlags = []
            if info["mods"]?.contains("cmd") == true { modifiers.insert(.command) }
            for type in [NSEvent.EventType.keyDown, .keyUp] {
                guard let event = NSEvent.keyEvent(with: type, location: .zero, modifierFlags: modifiers, timestamp: ProcessInfo.processInfo.systemUptime,
                                                   windowNumber: window.windowNumber, context: nil, characters: characters,
                                                   charactersIgnoringModifiers: characters, isARepeat: false, keyCode: code) else { continue }
                NSApp.sendEvent(event)
                try await Task.sleep(for: .milliseconds(40))
            }
        case "libraryPointerClick":
            // A mouse click sent to the window itself at a point of the row (fraction `x` of its width, 0.5 by default):
            // AppKit hit-tests it and SwiftUI's gestures handle it, without moving the pointer or activating Lemma.
            let target = try row()
            guard let frame = tree.frames[target.id], let window = mainWindow, let content = window.contentView else { throw QAHooks.QAError.missing("row frame") }
            let fraction = Double(info["x"] ?? "") ?? 0.5
            let point = CGPoint(x: frame.minX + frame.width * fraction, y: frame.midY)
            let local = content.isFlipped ? point : CGPoint(x: point.x, y: content.bounds.height - point.y)
            let location = content.convert(local, to: nil)
            var modifiers: NSEvent.ModifierFlags = []
            if info["mods"]?.contains("cmd") == true { modifiers.insert(.command) }
            let number = Int.random(in: 10_000...1_000_000)
            for (offset, type) in [NSEvent.EventType.leftMouseDown, .leftMouseUp].enumerated() {
                guard let event = NSEvent.mouseEvent(with: type, location: location, modifierFlags: modifiers, timestamp: ProcessInfo.processInfo.systemUptime,
                                                     windowNumber: window.windowNumber, context: nil, eventNumber: number + offset, clickCount: 1,
                                                     pressure: type == .leftMouseDown ? 1 : 0) else { continue }
                // deliver=post queues the release, so a tracking loop (a drag source waiting for it) sees it as a real one.
                if info["deliver"] == "post" && type == .leftMouseUp { NSApp.postEvent(event, atStart: false) } else { NSApp.sendEvent(event) }
                try await Task.sleep(for: .milliseconds(60))
            }
        default: return false
        }
        return true
    }

    /// A row's frame in screen coordinates with the origin at the top left of the main display, for real clicks.
    private func screenFrame(_ frame: CGRect?) -> CGRect? {
        guard let frame, let window = mainWindow, let content = window.contentView, let screen = NSScreen.screens.first else { return nil }
        let local = content.isFlipped ? frame : CGRect(x: frame.minX, y: content.bounds.height - frame.maxY, width: frame.width, height: frame.height)
        let rect = window.convertToScreen(content.convert(local, to: nil))
        return CGRect(x: rect.minX, y: screen.frame.maxY - rect.maxY, width: rect.width, height: rect.height)
    }
}
