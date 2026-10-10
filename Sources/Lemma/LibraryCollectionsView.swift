import SwiftUI
import AppKit
import LemmaCore

@MainActor
extension StudyStore {
    /// PDFs listed or studied, each once (kept until the libraries or the books' paths change).
    var libraryPDFCount: Int { libraries.pdfCount(bookPaths: library.map(\.sourcePath)) }
    var unfiledBooks: [StudyWorkspace] { LibraryTreeBuilder(libraryTreeInput()).unfiledBooks }
    func savedBook(for entry: LibraryPDF) -> StudyWorkspace? {
        library.first { libraries.key(of: $0.sourcePath) == entry.key }
    }
    func openLibraryPDF(_ entry: LibraryPDF) {
        if let book = savedBook(for: entry) { reopen(book) }
        else { open(URL(fileURLWithPath: entry.path)) }
    }
    func saveLibraryCollections(_ collections: [LibraryCollection]) {
        do { try libraries.replace(collections) } catch { self.error = "Could not save library sources: \(error.localizedDescription)" }
    }
    @discardableResult func renameLibrary(_ id: String, to title: String) -> Bool {
        do { return try libraries.rename(id, to: title) }
        catch { self.error = "Could not rename this library: \(error.localizedDescription)"; return false }
    }
    @discardableResult func renameLibrarySection(_ parent: String, to title: String) -> Bool {
        do {
            guard try libraries.renameSection(parent, to: title) else { return false }
            if let expanded = paneExpanded.removeValue(forKey: "collection-parent-" + parent) {
                paneExpanded["collection-parent-" + title.trimmingCharacters(in: .whitespacesAndNewlines)] = expanded
            }
            return true
        } catch { self.error = "Could not rename this section: \(error.localizedDescription)"; return false }
    }
    func attachLibrarySource(_ id: String, kind: LibrarySource.Kind) { chooseLibrarySources(id, folders: kind == .folder) }
}

/// Sizes and colours of the tree in each interface style: VS Code's 22 pt rows and codicons, or Classic's sidebar.
struct LibraryTreeStyle {
    let vscode: Bool

    /// Fixed hues per kind of library, as file icon themes use, a little deeper on light themes.
    static func kindColor(_ icon: String, dark: Bool) -> Color {
        switch icon {
        case "library": dark ? Color(red: 0.94, green: 0.62, blue: 0.29) : Color(red: 0.80, green: 0.45, blue: 0.10)
        case "file-text": dark ? Color(red: 0.36, green: 0.65, blue: 0.98) : Color(red: 0.12, green: 0.45, blue: 0.85)
        case "folder-library": dark ? Color(red: 0.88, green: 0.75, blue: 0.38) : Color(red: 0.68, green: 0.53, blue: 0.08)
        default: dark ? Color(red: 0.70, green: 0.54, blue: 0.97) : Color(red: 0.50, green: 0.33, blue: 0.80)
        }
    }
    var rowHeight: CGFloat { vscode ? VSMetrics.rowHeight : 24 }
    var indent: CGFloat { vscode ? 10 : 14 }
    var leading: CGFloat { vscode ? 6 : 8 }
    var font: Font { vscode ? .ui(13) : .system(size: 13) }
    var detailFont: Font { vscode ? .ui(12) : .system(size: 11.5) }
    var corner: CGFloat { vscode ? 0 : 5 }
    var inset: CGFloat { vscode ? 0 : 6 }

    @MainActor func iconColor(_ row: LibraryRow, theme: WorkbenchColors) -> Color {
        if !vscode {
            switch row.kind {
            case .library, .section: return theme.accent
            case .pdf: return Color(red: 0.86, green: 0.33, blue: 0.27)
            case .message(_, let warning): return warning ? .orange : .secondary
            default: return .secondary
            }
        }
        switch row.kind {
        case .library, .section: return Self.kindColor(row.icon, dark: theme.isDark)
        case .pdf: return Color(red: 0.89, green: 0.30, blue: 0.24)
        case let .message(_, warning): return warning ? theme[.editorWarningForeground] : theme[.descriptionForeground]
        default: return theme[.iconForeground]
        }
    }
}

/// The Library: libraries, sections, watched folders and PDFs as one tree. A click anywhere on a row opens it,
/// ↩ renames (in Lemma, on disk or both), and rows drag to other libraries, folders, the reader or Finder.
struct LibraryCollectionsView: View {
    @Bindable var store: StudyStore
    @Environment(\.theme) private var theme
    var showsSearch = true
    @FocusState private var treeFocused: Bool

    var body: some View {
        let tree = store.libraryTree
        let style = LibraryTreeStyle(vscode: ThemeManager.shared.style == .vscode)
        // Rows are kept until something they show changes; the book in front comes from the tree's own state, so
        // turning a page does not ask for them again.
        let rows = store.libraryRows(activeBookID: tree.activeBookID)
        VStack(spacing: 0) {
            if showsSearch { filterBar(style) }
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(rows) { row in
                            LibraryRowView(store: store, row: row, style: style, focused: treeFocused).id(row.id)
                        }
                        emptyState(rows: rows, style: style)
                        Color.clear.frame(height: 28)
                    }
                    .padding(.top, 2)
                }
                // The space around the rows: a click clears the selection; folders dropped from Finder become libraries,
                // and libraries dropped there move to the end.
                .background(Color.clear.contentShape(Rectangle()).onTapGesture { tree.selection = []; tree.focusRequest += 1 })
                .onDrop(of: [.lemmaLibraryItems, .fileURL], delegate: LibraryRowDropDelegate(store: store, row: nil))
                .onChange(of: tree.scrollTarget) { _, id in
                    guard let id else { return }
                    proxy.scrollTo(id)
                    tree.scrollTarget = nil
                }
            }
            .overlay(alignment: .bottom) { dropBanner(style) }
        }
        .focusable()
        .focused($treeFocused)
        .focusEffectDisabled()
        .onKeyPress(phases: [.down, .repeat]) { press in handle(press) ? .handled : .ignored }
        .onChange(of: treeFocused) { _, focused in if tree.focused != focused { tree.focused = focused } }
        .onChange(of: tree.focusRequest) { _, _ in treeFocused = true }
        .onHover { hovering in if tree.hovering != hovering { tree.hovering = hovering } }
        .background(LibraryActiveBookFollower(store: store))
        .onChange(of: store.libraries.updatedAt) { _, _ in
            // At launch the book reopens before its folders are scanned: show it once they are.
            guard let id = store.workspace?.id, id != tree.revealedBookID, tree.editor == nil else { return }
            store.revealInLibrary(bookID: id)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Library")
    }

    private func filterBar(_ style: LibraryTreeStyle) -> some View {
        HStack(spacing: 4) {
            searchField("Filter libraries and PDFs", text: $store.libraryQuery) {
                treeFocused = true
                store.handleLibraryKey(.down)
            }
            if style.vscode {
                VSIconButton(icon: "new-folder", help: "New Library…") { store.beginNewLibrary() }
                VSMenuButton(icon: "ellipsis", help: "Sort, Collapse and More…") { store.libraryViewMenu() }
            } else {
                Button { store.beginNewLibrary() } label: { Image(systemName: "folder.badge.plus") }
                    .buttonStyle(.borderless).help("New Library…")
                Menu { VSMenuItemsView(items: store.libraryViewMenu()) } label: { Image(systemName: "ellipsis.circle") }
                    .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().help("Sort, Collapse and More…")
            }
        }
        .padding(.horizontal, style.vscode ? 10 : 10).padding(.top, 6).padding(.bottom, 4)
    }

    @ViewBuilder private func emptyState(rows: [LibraryRow], style: LibraryTreeStyle) -> some View {
        if store.libraries.collections.isEmpty && store.library.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Make a library from a folder: Lemma lists its PDFs and new ones as they arrive.")
                    .font(style.detailFont).foregroundStyle(theme[.descriptionForeground]).fixedSize(horizontal: false, vertical: true)
                Button("New Library from Folder…") { store.chooseFolderForNewLibrary() }
            }.padding(12).frame(maxWidth: .infinity, alignment: .leading)
        } else if !store.libraryQuery.isEmpty && rows.isEmpty {
            Text("No library or PDF matches “\(store.libraryQuery)”").font(style.detailFont).foregroundStyle(theme[.descriptionForeground])
                .padding(12).frame(maxWidth: .infinity, alignment: .leading)
        }
        if let error = store.libraries.error {
            Text(error).font(.caption).foregroundStyle(theme[.errorForeground]).padding(10).frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// While dragging over the tree, what a drop would do.
    @ViewBuilder private func dropBanner(_ style: LibraryTreeStyle) -> some View {
        if let drop = store.libraryTree.drop, !drop.message.isEmpty {
            HStack(spacing: 6) {
                Codicon(drop.allowed ? "info" : "circle-slash", size: 14)
                Text(drop.message).lineLimit(2).fixedSize(horizontal: false, vertical: true)
            }
            .font(style.detailFont)
            .foregroundStyle(theme[.editorWidgetForeground])
            .padding(.horizontal, 8).padding(.vertical, 5)
            .background(RoundedRectangle(cornerRadius: 4).fill(theme[.editorWidgetBackground]))
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(drop.allowed ? theme[.focusBorder] : theme.border(.editorWidgetBorder), lineWidth: 1))
            .vsWidgetShadow(theme)
            .padding(8)
            .allowsHitTesting(false)
        }
    }

    private func handle(_ press: KeyPress) -> Bool {
        // Keys typed in the filter or a name field stay there (the filter hands ↓ to the tree itself).
        guard store.libraryTree.editor == nil, treeFocused else { return false }
        let command = press.modifiers.contains(.command), shift = press.modifiers.contains(.shift)
        let key: LibraryKey?
        switch press.key {
        case .upArrow: key = command ? .home : .up
        case .downArrow: key = command ? .openAndFocus : .down
        case .leftArrow: key = .left
        case .rightArrow: key = .right
        case .home: key = .home
        case .end: key = .end
        case .pageUp: key = .pageUp
        case .pageDown: key = .pageDown
        case .return: key = command ? .openAndFocus : .rename
        case .space: key = .open
        case .delete, .deleteForward: key = command ? .trash : nil
        case .escape: key = .escape
        case KeyEquivalent(Character(Unicode.Scalar(UInt32(NSF2FunctionKey))!)): key = .rename
        default:
            if command && press.characters == "a" { key = .selectAll }
            else if !command, !press.modifiers.contains(.control), let character = press.characters.first, character.isLetter || character.isNumber {
                key = .character(String(character))
            } else { key = nil }
        }
        guard let key else { return false }
        return store.handleLibraryKey(key, extend: shift)
    }
}

/// Follows the book in front for the tree. This small view reads the store's workspace (which changes at every page
/// turned) and hands the tree only the book's id, when it changes.
private struct LibraryActiveBookFollower: View {
    let store: StudyStore
    var body: some View {
        let id = store.workspace?.id
        Color.clear.frame(width: 0, height: 0)
            .accessibilityHidden(true)
            .onAppear {
                let tree = store.libraryTree
                tree.activeBookID = id
                if let id, tree.selection.isEmpty { store.revealInLibrary(bookID: id) }
            }
            .onChange(of: id) { _, id in
                let tree = store.libraryTree
                if tree.activeBookID != id { tree.activeBookID = id }
                // The Library follows the book in front, as VS Code's Explorer follows the active file.
                guard let id, id != tree.revealedBookID, tree.editor == nil else { return }
                store.revealInLibrary(bookID: id)
            }
    }
}

/// One row: indent guides, twistie, icon, name, then counts and progress, or actions under the pointer.
struct LibraryRowView: View {
    @Bindable var store: StudyStore
    let row: LibraryRow
    let style: LibraryTreeStyle
    let focused: Bool
    @Environment(\.theme) private var theme
    @State private var hovering = false

    var body: some View {
        let tree = store.libraryTree
        if tree.editor?.rowID == row.id, let editor = tree.editor {
            LibraryEditRow(store: store, row: row, editor: editor, style: style)
        } else if case .message = row.kind {
            content(selected: false).frame(minHeight: style.rowHeight)
                .help(row.help)
        } else {
            let selected = tree.selection.contains(row.id)
            let drop = tree.drop?.rowID == row.id ? tree.drop : nil
            content(selected: selected)
                .frame(maxWidth: .infinity, minHeight: style.rowHeight, alignment: .leading)
                .background(background(selected: selected, drop: drop))
                .overlay { outline(cursor: tree.cursor == row.id && focused && style.vscode) }
                .overlay(alignment: drop?.placement == .after ? .bottom : .top) { insertionLine(drop) }
                .contentShape(Rectangle())
                .onHover { hovering = $0 }
                .onTapGesture { store.clickLibraryRow(row, modifiers: Self.clickModifiers) }
                .contextMenu { VSMenuItemsView(items: store.libraryMenu(for: row)) }
                .modifier(LibraryRowDrag(store: store, row: row))
                .onDrop(of: [.lemmaLibraryItems, .fileURL], delegate: LibraryRowDropDelegate(store: store, row: row, height: style.rowHeight))
                .help(row.help)
                .modifier(LibraryRowFrameReporter(store: store, id: row.id))
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(accessibilityLabel)
                .accessibilityValue(row.expandable ? (row.expanded ? "expanded" : "collapsed") : row.progress.map { "\(Int(($0 * 100).rounded())) percent read" } ?? "")
                .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
                .accessibilityAction(.default) { store.clickLibraryRow(row) }
                .accessibilityAction(named: "Rename") { store.beginLibraryRename(row) }
                .accessibilityAction(named: "Open to the Side") { store.openLibraryRowToSide(row) }
        }
    }

    /// The click's own modifiers (⌘ adds to the selection, ⇧ extends it), rather than the keyboard's state afterwards.
    static var clickModifiers: NSEvent.ModifierFlags {
        if let event = NSApp.currentEvent, [.leftMouseUp, .leftMouseDown].contains(event.type) { return event.modifierFlags }
        return NSEvent.modifierFlags
    }

    private var accessibilityLabel: String {
        switch row.kind {
        case .section: "Section \(row.title)"
        case .library: "Library \(row.title), \(row.count ?? 0) PDFs"
        case .folder: "Folder \(row.title), \(row.count ?? 0) PDFs"
        case .unfiled: "Other PDFs, \(row.count ?? 0)"
        default: row.missing ? "\(row.title), file missing" : row.title
        }
    }

    private func content(selected: Bool) -> some View {
        HStack(spacing: 0) {
            LibraryIndent(style: style, depth: row.depth, guides: store.libraryTree.hovering)
            LibraryTwistie(row: row, style: style) { store.toggleLibraryRow(row) }
            icon.padding(.trailing, 6)
            title(selected: selected)
            Spacer(minLength: 6)
            trailing(selected: selected)
        }
        .padding(.trailing, 8)
        .foregroundStyle(foreground(selected: selected))
    }

    @ViewBuilder private var icon: some View {
        if row.isPDF {
            if style.vscode { FileIcon(kind: "file-pdf").opacity(row.missing ? 0.5 : 1) }
            else { Image(systemName: "doc.richtext").font(.system(size: 13)).foregroundStyle(style.iconColor(row, theme: theme)).frame(width: 16) }
        } else {
            Codicon(row.icon, size: 16).foregroundStyle(style.iconColor(row, theme: theme))
        }
    }

    @ViewBuilder private func title(selected: Bool) -> some View {
        let weight: Font.Weight = row.isOpenInTab || row.isActive ? .medium : .regular
        let font = style.vscode ? Font.ui(13, weight: weight) : Font.system(size: 13, weight: weight)
        if case .message = row.kind {
            Text(row.title).font(style.detailFont).italic().foregroundStyle(theme[.descriptionForeground]).lineLimit(2)
                .fixedSize(horizontal: false, vertical: true).padding(.vertical, 3)
        } else {
            HStack(spacing: 6) {
                if store.libraryQuery.isEmpty { Text(row.title).font(font) }
                else {
                    VSHighlightedText(text: row.title, matches: FuzzyMatch.ranges(of: store.libraryQuery, in: row.title)).font(font)
                }
                if let detail = row.detail {
                    Text(detail).font(style.detailFont).foregroundStyle(descriptionColor(selected: selected)).layoutPriority(-1)
                }
            }
            .lineLimit(1).truncationMode(.tail)
            .strikethrough(row.missing)
        }
    }

    @ViewBuilder private func trailing(selected: Bool) -> some View {
        if hovering && !store.libraryTree.dragging {
            HStack(spacing: 1) { actions }
        } else {
            HStack(spacing: 5) {
                if row.due > 0 { VSBadge(count: row.due).help("\(row.due) note\(row.due == 1 ? "" : "s") due for recall") }
                if let progress = row.progress, progress > 0 {
                    if progress >= 0.995 {
                        Codicon("pass-filled", size: 14).foregroundStyle(theme[.testingIconPassed]).help("Finished")
                    } else {
                        LibraryProgressRing(value: progress, tint: theme.accent, track: descriptionColor(selected: selected).opacity(0.35))
                        Text("\(Int((progress * 100).rounded())) %").font(style.detailFont).monospacedDigit()
                            .foregroundStyle(descriptionColor(selected: selected))
                    }
                } else if let count = row.count, !row.isPDF {
                    Text("\(count)").font(style.detailFont).monospacedDigit().foregroundStyle(descriptionColor(selected: selected))
                }
            }
        }
    }

    @ViewBuilder private var actions: some View {
        switch row.kind {
        case .pdf:
            action("split-horizontal", "Open to the Side") { store.openLibraryRowToSide(row) }
            action("edit", "Rename… (↩)") { store.beginLibraryRename(row) }
        case let .library(id):
            action("add", "Add PDFs…") { store.chooseLibrarySources(id, folders: false) }
            action("new-folder", "Add Watched Folder…") { store.chooseLibrarySources(id, folders: true) }
            menuAction
        case let .section(name):
            action("add", "New Library in \(name)") { store.beginNewLibrary(in: name) }
            menuAction
        case .folder:
            action("edit", "Rename Folder… (↩)") { store.beginLibraryRename(row) }
            menuAction
        default:
            if let count = row.count { Text("\(count)").font(style.detailFont).monospacedDigit().foregroundStyle(theme[.descriptionForeground]) }
        }
    }

    private func action(_ icon: String, _ help: String, perform: @escaping () -> Void) -> some View {
        Group {
            if style.vscode { VSIconButton(icon: icon, help: help, size: 14, action: perform) }
            else {
                Button(action: perform) { Image(systemName: Codicons.fallbackSymbol[icon] ?? "circle").font(.system(size: 11)) }
                    .buttonStyle(.borderless).help(help).accessibilityLabel(help)
            }
        }
    }

    private var menuAction: some View {
        VSMenuButton(icon: "ellipsis", help: "More Actions…", size: 14) { store.libraryMenu(for: row) }
    }

    private func foreground(selected: Bool) -> Color {
        if selected { return theme[store.libraryTree.focused ? .listActiveSelectionForeground : .listInactiveSelectionForeground] }
        if hovering { return theme[.listHoverForeground] }
        return row.missing ? theme[.descriptionForeground] : theme[.sideBarForeground]
    }

    private func descriptionColor(selected: Bool) -> Color {
        selected && store.libraryTree.focused ? theme[.listActiveSelectionForeground].opacity(0.75) : theme[.descriptionForeground]
    }

    @ViewBuilder private func background(selected: Bool, drop: LibraryDropFeedback?) -> some View {
        let shape = RoundedRectangle(cornerRadius: style.corner)
        Group {
            if let drop, drop.placement == .into, drop.allowed { shape.fill(theme.has(.listDropBackground) ? theme[.listDropBackground] : theme.accent.opacity(0.18)) }
            else if selected { shape.fill(theme[store.libraryTree.focused ? .listActiveSelectionBackground : .listInactiveSelectionBackground]) }
            else if hovering { shape.fill(theme[.listHoverBackground]) }
            else { Color.clear }
        }
        .padding(.horizontal, style.inset)
    }

    @ViewBuilder private func outline(cursor: Bool) -> some View {
        if cursor { Rectangle().strokeBorder(theme.has(.listFocusOutline) ? theme[.listFocusOutline] : theme[.focusBorder], lineWidth: 1) }
    }

    @ViewBuilder private func insertionLine(_ drop: LibraryDropFeedback?) -> some View {
        if let drop, drop.allowed, drop.placement != .into {
            Rectangle().fill(theme[.focusBorder]).frame(height: 2)
                .padding(.leading, style.leading + CGFloat(row.depth) * style.indent + 16)
        }
    }
}

/// Room for the levels above a row, with VS Code's indent guides while the pointer is over the tree.
struct LibraryIndent: View {
    let style: LibraryTreeStyle
    let depth: Int
    let guides: Bool
    @Environment(\.theme) private var theme
    var body: some View {
        HStack(spacing: 0) {
            ForEach(0..<depth, id: \.self) { _ in
                ZStack(alignment: .leading) {
                    Color.clear
                    if guides && style.vscode {
                        Rectangle().fill(theme.has(.treeIndentGuidesStroke) ? theme[.treeIndentGuidesStroke] : theme[.descriptionForeground].opacity(0.35))
                            .frame(width: 1).padding(.leading, 7)
                    }
                }.frame(width: style.indent)
            }
        }
        .padding(.leading, style.leading)
        .frame(maxHeight: .infinity)
    }
}

/// The chevron that opens a row, with a larger target than its glyph.
struct LibraryTwistie: View {
    let row: LibraryRow
    let style: LibraryTreeStyle
    let toggle: () -> Void
    @Environment(\.theme) private var theme
    var body: some View {
        Group {
            if row.expandable {
                Codicon(row.expanded ? "chevron-down" : "chevron-right", size: 16).foregroundStyle(theme[.iconForeground])
                    .frame(width: 16, height: style.rowHeight).contentShape(Rectangle())
                    .onTapGesture(perform: toggle)
                    .accessibilityHidden(true)
            } else { Color.clear.frame(width: 16, height: 1) }
        }
        .padding(.trailing, 2)
    }
}

/// A small ring of reading progress, in the theme's accent.
struct LibraryProgressRing: View {
    let value: Double
    let tint: Color
    let track: Color
    var body: some View {
        ZStack {
            Circle().stroke(track, lineWidth: 1.6)
            Circle().trim(from: 0, to: max(0.001, min(1, value))).stroke(tint, style: StrokeStyle(lineWidth: 1.6, lineCap: .round)).rotationEffect(.degrees(-90))
        }
        .frame(width: 11, height: 11)
        .accessibilityHidden(true)
    }
}

/// Row frames for QA (LEMMA_QA_DIR) only; the reader's Lemma does not track them.
private struct LibraryRowFrameReporter: ViewModifier {
    let store: StudyStore
    let id: String
    func body(content: Content) -> some View {
        if QAHooks.shared != nil {
            content.onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { frame in store.libraryTree.frames[id] = frame }
        } else {
            content
        }
    }
}

/// Rows drag to other libraries, folders, the reader, projects and Finder (a copy); messages stay put.
private struct LibraryRowDrag: ViewModifier {
    let store: StudyStore
    let row: LibraryRow
    func body(content: Content) -> some View {
        if row.isPDF || row.isFolder || row.isLibrary || row.isSection || row.kind == .unfiled {
            content.onDrag {
                store.libraryTree.beginDrag()
                return store.libraryDragProvider(for: row)
            } preview: {
                LibraryDragPreview(title: store.libraryTree.dragged.count > 1 && !row.isSection ? "\(store.libraryTree.dragged.count) items" : row.title,
                                   icon: row.isPDF ? "file-pdf" : row.icon)
            }
        } else {
            content
        }
    }
}

struct LibraryDragPreview: View {
    let title: String
    let icon: String
    @Environment(\.theme) private var theme
    var body: some View {
        HStack(spacing: 6) {
            if icon == "file-pdf" { FileIcon(kind: "file-pdf") } else { Codicon(icon, size: 16) }
            Text(title).font(.ui(13)).lineLimit(1)
        }
        .padding(.horizontal, 8).padding(.vertical, 3)
        .foregroundStyle(theme[.listActiveSelectionForeground])
        .background(RoundedRectangle(cornerRadius: 4).fill(theme[.listActiveSelectionBackground]))
    }
}

/// A row being renamed or a library being named: VS Code's inline input, with what the rename changes under it.
struct LibraryEditRow: View {
    @Bindable var store: StudyStore
    let row: LibraryRow
    let editor: LibraryEditor
    let style: LibraryTreeStyle
    @Environment(\.theme) private var theme
    @FocusState private var fieldFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 0) {
                LibraryIndent(style: style, depth: row.depth, guides: false)
                Color.clear.frame(width: 18, height: 1)
                if row.isPDF { FileIcon(kind: "file-pdf").padding(.trailing, 6) }
                else { Codicon(row.icon, size: 16).foregroundStyle(style.iconColor(row, theme: theme)).padding(.trailing, 6) }
                field
                if editor.mode != .lemma, row.isPDF {
                    Text(".pdf").font(style.vscode ? .ui(13) : .system(size: 13)).foregroundStyle(theme[.descriptionForeground]).padding(.leading, 3)
                }
            }
            .padding(.trailing, 8)
            let indent = style.leading + CGFloat(row.depth) * style.indent + 40
            if !editor.modes.isEmpty {
                HStack(spacing: 4) {
                    Text("Rename").font(.ui(11)).foregroundStyle(theme[.descriptionForeground]).fixedSize()
                    ForEach(editor.modes) { mode in modeButton(mode).fixedSize() }
                }
                .padding(.leading, indent)
            }
            if let problem = editor.problem {
                Text(problem).font(.ui(12)).foregroundStyle(theme[.foreground])
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 6).padding(.vertical, 4)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(theme[.inputValidationErrorBackground])
                    .overlay(Rectangle().stroke(theme[.inputValidationErrorBorder], lineWidth: 1))
                    .padding(.leading, indent).padding(.trailing, 8)
            } else if let caption = editor.caption ?? modeCaption {
                Text(caption).font(.ui(11)).foregroundStyle(theme[.descriptionForeground]).padding(.leading, indent).padding(.trailing, 8)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 3)
        .background(theme[.listInactiveSelectionBackground].opacity(0.5))
        .onAppear { DispatchQueue.main.async { fieldFocused = true } }
        .onChange(of: fieldFocused) { _, focused in
            // Clicking elsewhere keeps the name, as in VS Code; a mode button keeps the field focused.
            guard !focused else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                guard store.libraryTree.editor?.rowID == row.id, !fieldFocused else { return }
                if store.libraryTree.editor?.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == true { store.cancelLibraryEdit() }
                else { store.commitLibraryEdit() }
            }
        }
    }

    private var modeCaption: String? {
        guard row.isPDF else { return nil }
        if !editor.fileAvailable { return "The file is not on disk: only the name in Lemma can change." }
        return editor.mode.help
    }

    private var field: some View {
        TextField("", text: Binding(get: { store.libraryTree.editor?.text ?? "" }, set: { store.updateLibraryEditText($0) }),
                  prompt: Text(editor.placeholder).foregroundColor(theme[.inputPlaceholderForeground]))
            .textFieldStyle(.plain)
            .font(style.vscode ? .ui(13) : .system(size: 13))
            .foregroundStyle(theme[.inputForeground])
            .focused($fieldFocused)
            .onSubmit { store.commitLibraryEdit() }
            .onExitCommand { store.cancelLibraryEdit() }
            .padding(.horizontal, 4)
            .frame(height: style.rowHeight - 2)
            .background(RoundedRectangle(cornerRadius: style.vscode ? 2 : 4).fill(theme[.inputBackground]))
            .overlay(RoundedRectangle(cornerRadius: style.vscode ? 2 : 4)
                .stroke(editor.problem != nil ? theme[.inputValidationErrorBorder] : theme[.focusBorder], lineWidth: 1))
            .accessibilityLabel(editor.placeholder)
    }

    private func modeButton(_ mode: LibraryRenameMode) -> some View {
        let on = editor.mode == mode
        let enabled = mode == .lemma || editor.fileAvailable
        return Button { store.setLibraryRenameMode(mode); fieldFocused = true } label: {
            Text(mode.label).font(.ui(11, weight: on ? .semibold : .regular))
                .foregroundStyle(on ? theme[.inputOptionActiveForeground] : theme[.foreground])
                .padding(.horizontal, 6).frame(height: 18)
                .background(RoundedRectangle(cornerRadius: 3).fill(on ? theme[.inputOptionActiveBackground] : theme[.inputBackground]))
                .overlay(RoundedRectangle(cornerRadius: 3).stroke(on ? theme[.inputOptionActiveBorder] : theme.border(.inputBorder), lineWidth: 1))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.45)
        .focusable(false)
        .help(mode.help)
        .accessibilityLabel("Rename \(mode.label)")
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}

struct LibrarySourcesSheet: View {
    @Bindable var store: StudyStore
    @State private var title = ""
    @State private var kind = LibraryKind.studying
    @State private var parent = ""
    @State private var renaming: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack { Text("Library Sources").font(.title2.weight(.semibold)); Spacer(); Button("Done") { store.showLibrarySources = false }.keyboardShortcut(.cancelAction) }
            Text("Folders are watched recursively. Lemma keeps the original files in place and opens a PDF only when you select it.")
                .font(.callout).foregroundStyle(.secondary)
            List {
                ForEach(store.libraries.collections) { collection in
                    VStack(alignment: .leading, spacing: 7) {
                        HStack {
                            Text(collection.parent.map { "\($0) › \(collection.title)" } ?? collection.title).font(.headline)
                            Text(collection.kind.label).font(.caption).foregroundStyle(.secondary)
                            Spacer()
                            Menu {
                                Button("Rename Library…") { renaming = collection.id }
                                Button("Add Folder…") { store.attachLibrarySource(collection.id, kind: .folder) }
                                Button("Add PDFs…") { store.attachLibrarySource(collection.id, kind: .file) }
                                Button("Remove Library") { store.confirmRemoveLibrary(collection.id) }
                            } label: { Image(systemName: "ellipsis").foregroundStyle(.primary) }
                                .menuStyle(.borderlessButton).frame(width: 24)
                                .accessibilityLabel("Library actions for " + collection.title)
                        }
                        ForEach(collection.sources) { source in
                            HStack(alignment: .top) {
                                Image(systemName: source.kind == .folder ? "folder" : "doc.richtext")
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(source.path).font(.caption).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                                    if !source.excludedPaths.isEmpty {
                                        Text("\(source.excludedPaths.count) item\(source.excludedPaths.count == 1 ? "" : "s") moved to other libraries or removed are not listed.")
                                            .font(.caption2).foregroundStyle(.secondary)
                                    }
                                }
                                Spacer(minLength: 4)
                                Button {
                                    store.editLibraryCollections("Stop Watching") { collections in
                                        collections.map { item in
                                            guard item.id == collection.id else { return item }
                                            var item = item; item.sources.removeAll { $0.id == source.id }; return item
                                        }
                                    }
                                } label: { Image(systemName: "minus.circle") }.buttonStyle(.borderless).help("Stop watching this source; keep its PDFs and notes")
                            }.foregroundStyle(.secondary)
                        }
                        if collection.sources.isEmpty { Text("No source yet: drop PDFs or folders on this library in the Library.").font(.caption).foregroundStyle(.secondary) }
                        if let issue = store.libraries.issues[collection.id] { Text(issue).font(.caption).foregroundStyle(.orange) }
                    }.padding(.vertical, 6).accessibilityElement(children: .contain)
                        .accessibilityAction(named: "Rename Library") { renaming = collection.id }
                }
            }.listStyle(.inset)
            Divider()
            Text("Add a Library").font(.headline)
            HStack {
                TextField("Library name", text: $title).textFieldStyle(.roundedBorder)
                Picker("Type", selection: $kind) { ForEach(LibraryKind.allCases, id: \.self) { Text($0.label).tag($0) } }.frame(width: 210)
            }
            TextField("Inside (optional): a section such as School, or the name of a library", text: $parent).textFieldStyle(.roundedBorder)
            HStack {
                Button("Choose Folder…", action: addFolder).disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                Button("Create Empty") {
                    let section = parent.trimmingCharacters(in: .whitespacesAndNewlines)
                    store.createLibrary(title: title, kind: kind, parent: section.isEmpty ? nil : section); title = ""; parent = ""
                }.disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                Spacer()
                Button("Refresh Now") { store.libraries.refresh() }.disabled(store.libraries.isScanning)
                Text("\(store.libraryPDFCount) PDFs").font(.caption).foregroundStyle(.secondary)
            }
            Text("Removing a source stops watching it. Original files, saved notes and reading positions remain on this Mac. Undo (⌘Z) restores library changes.")
                .font(.caption).foregroundStyle(.secondary)
        }.padding(22).frame(width: 670, height: 650)
            .sheet(isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
                if let id = renaming, let collection = store.libraries.collections.first(where: { $0.id == id }) {
                    LibraryRenameSheet(title: collection.title, save: { store.renameLibraryCollection(id, to: $0); return true }, done: { renaming = nil })
                }
            }
    }
    private func addFolder() {
        let panel = NSOpenPanel(); panel.canChooseFiles = false; panel.canChooseDirectories = true; panel.allowsMultipleSelection = true
        guard panel.runModal() == .OK else { return }
        let section = parent.trimmingCharacters(in: .whitespacesAndNewlines)
        store.createLibrary(title: title, kind: kind, parent: section.isEmpty ? nil : section,
                            sources: panel.urls.map { LibrarySource(path: $0.path, bookmark: LibraryPaths.bookmark($0.path)) })
        title = ""; parent = ""
    }
}

/// A separate text field keeps keyboard focus and accessible editing independent of disclosure/list rows.
private struct LibraryRenameSheet: View {
    let title: String
    var section = false
    let save: (String) -> Bool
    let done: () -> Void
    @State private var draft = ""
    @FocusState private var focused: Bool
    private var empty: Bool { draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    private func commit() { if !empty, save(draft) { done() } }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(section ? "Rename Section" : "Rename Library").font(.headline)
            TextField("Library name", text: $draft).textFieldStyle(.roundedBorder).focused($focused)
                .onSubmit(commit).onExitCommand(perform: done)
                .accessibilityLabel(section ? "Section name" : "Library name")
            HStack {
                Spacer()
                Button("Cancel", action: done).keyboardShortcut(.cancelAction)
                Button("Save", action: commit).disabled(empty).keyboardShortcut(.defaultAction)
            }
        }
        .padding(22).frame(width: 380)
        .onAppear { draft = title; focused = true }
    }
}
