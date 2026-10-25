import SwiftUI
import AppKit
import LemmaCore

/// The second editor group: tabs of pages, notebooks, maps and derivations beside the reader, as in an editor
/// split into two groups. Each tab keeps its own editor; the active one fills the group.
struct SideEditorGroup: View {
    @Bindable var store: StudyStore

    var body: some View {
        VStack(spacing: 0) {
            if ThemeManager.shared.style == .classic { ClassicSideTabStrip(store: store) } else { SideTabStrip(store: store) }
            switch store.activeSideEditor {
            case let .page(state)?: SecondaryEditor(store: store, state: state)
            case let .lab(id)?: LabEditor(store: store, notebookID: id)
            case let .map(request)?: DependencyMapView(store: store, request: request)
            case let .derivation(id)?: DerivationEditor(store: store, derivationID: id)
            case let .project(id)?: ProjectEditor(store: store, projectID: id)
            case nil: EmptyView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .modifier(EditorDropTarget(store: store, toSide: true))
    }
}

private struct SideTabStrip: View {
    @Bindable var store: StudyStore
    @Environment(\.theme) private var theme

    var body: some View {
        HStack(spacing: 0) {
            GeometryReader { geometry in
            ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                VSTabRow {
                    ForEach(store.sideEditors) { editor in
                        VSTab(icon: editor.codicon, title: store.sideTitle(editor), active: editor.id == store.activeSideEditor?.id,
                              badge: badge(editor), select: { store.activateSideEditor(editor.id) }, close: { store.closeSideEditor(editor.id) })
                            .contextMenu {
                                Button("Close") { store.closeSideEditor(editor.id) }
                                Button("Close All") { for editor in store.sideEditors { store.closeSideEditor(editor.id) } }
                                Divider()
                                Button("Move Tab Left") { store.shiftSideTab(editor.id, by: -1) }
                                Button("Move Tab Right") { store.shiftSideTab(editor.id, by: 1) }
                            }
                            .draggable("lemma-side:\(editor.id)")
                            .dropDestination(for: String.self) { values, _ in store.dropSideTab(values, onto: editor.id) }
                            .id(editor.id)
                    }
                }
                // As the main group's: the tabs take the whole bar before scrolling, and the active one stays in view.
                .frame(minWidth: geometry.size.width, maxHeight: .infinity, alignment: .leading)
                .background(alignment: .bottom) { Rectangle().fill(theme.border(.editorGroupHeaderTabsBorder)).frame(height: 1) }
            }
            .onChange(of: store.activeSideEditor?.id) { _, id in
                guard let id else { return }
                DispatchQueue.main.async { withAnimation(.easeOut(duration: 0.15)) { proxy.scrollTo(id) } }
            }
            }
            }
            HStack(spacing: 2) {
                VSMenuButton(icon: "add", help: "Open Another Editor Beside the Page") {
                    [.action("New Derivation") { store.newDerivation() },
                     .action("New Lab Notebook") { store.newLab() },
                     .action("Page Beside This One") { store.openToSide(page: store.reader.pageNumber - 1) },
                     .submenu("Another Book", store.library.filter { $0.id != store.workspace?.id }.map { book in .action(book.title) { store.openBookToTheSide(book.id) } })]
                        + store.activeProjects.map { project in .action("Project: \(project.title)") { store.openProject(project.id) } }
                }
                VSIconButton(icon: "close-all", help: "Close All Side Editors") { for editor in store.sideEditors { store.closeSideEditor(editor.id) } }
            }
            .padding(.horizontal, 6).frame(maxHeight: .infinity)
            .overlay(alignment: .bottom) { Rectangle().fill(theme.border(.editorGroupHeaderTabsBorder)).frame(height: 1) }
        }
        .frame(height: VSMetrics.tabHeight)
        .background(theme[.editorGroupHeaderTabsBackground])
    }

    /// A derivation's tab carries its count of failing steps, as an editor's tab carries its problems.
    private func badge(_ editor: SideEditor) -> Int? {
        guard case let .derivation(id) = editor, let report = store.derivationReports[id], report.fails > 0 else { return nil }
        return report.fails
    }
}

// MARK: - Classic (Lemma 1.1)

private struct ClassicSideTabStrip: View {
    @Bindable var store: StudyStore
    @Environment(\.workbenchDensity) private var density

    var body: some View {
        HStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 0) {
                    ForEach(store.sideEditors) { editor in
                        ClassicSideTab(title: store.sideTitle(editor), symbol: editor.symbol, badge: badge(editor),
                                selected: editor.id == store.activeSideEditor?.id,
                                select: { store.activateSideEditor(editor.id) }, close: { store.closeSideEditor(editor.id) },
                                move: { store.shiftSideTab(editor.id, by: $0) })
                            .draggable("lemma-side:\(editor.id)")
                            .dropDestination(for: String.self) { values, _ in store.dropSideTab(values, onto: editor.id) }
                        Divider().frame(height: 16)
                    }
                }
            }
            Spacer(minLength: 0)
            Menu {
                Button("New Derivation") { store.newDerivation() }
                Button("New Lab Notebook") { store.newLab() }
                Button("Page Beside This One") { store.openToSide(page: store.reader.pageNumber - 1) }
                ForEach(store.activeProjects) { project in Button("Project: \(project.title)") { store.openProject(project.id) } }
                Divider()
                Button("Close All Side Editors") { for editor in store.sideEditors { store.closeSideEditor(editor.id) } }
            } label: { Image(systemName: "plus").font(.system(size: 10.5, weight: .medium)) }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).frame(width: 26).help("Open another editor beside the page")
                .accessibilityLabel("Open a side editor")
        }
        .frame(height: density.sideTabHeight)
        .background(Color.lemmaChrome)
        .overlay(alignment: .bottom) { Divider() }
    }

    /// A derivation's tab carries its count of failing steps, as an editor's tab carries its problems.
    private func badge(_ editor: SideEditor) -> Int? {
        guard case let .derivation(id) = editor, let report = store.derivationReports[id], report.fails > 0 else { return nil }
        return report.fails
    }
}

private struct ClassicSideTab: View {
    @Environment(\.workbenchDensity) private var density
    let title: String
    let symbol: String
    let badge: Int?
    let selected: Bool
    let select: () -> Void
    let close: () -> Void
    let move: (Int) -> Void
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 6) {
            Button(action: select) {
                HStack(spacing: 6) {
                    Image(systemName: symbol).font(.system(size: 10)).foregroundStyle(selected ? Color.lemmaOlive : Color.secondary)
                    Text(title).font(.system(size: 11.5, weight: selected ? .medium : .regular)).lineLimit(1)
                        .foregroundStyle(selected ? Color.primary : Color.secondary)
                    if let badge {
                        Text("\(badge)").font(.system(size: 9, weight: .bold).monospacedDigit()).foregroundStyle(.white)
                            .padding(.horizontal, 4).frame(minWidth: 14, minHeight: 14).background(Color.red.opacity(0.85), in: Capsule())
                            .help("\(badge) failing \(badge == 1 ? "step" : "steps")")
                    }
                }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Button(action: close) {
                Image(systemName: "xmark").font(.system(size: 8, weight: .bold)).frame(width: 15, height: 15)
                    .background(hovering ? Color.primary.opacity(0.08) : .clear, in: RoundedRectangle(cornerRadius: 4))
            }
            .buttonStyle(.plain).foregroundStyle(.secondary).opacity(selected || hovering ? 1 : 0)
            .accessibilityLabel("Close \(title)")
        }
        .padding(.leading, 10).padding(.trailing, 5)
        .frame(height: density.sideTabHeight).frame(minWidth: 90, maxWidth: 200)
        .background(selected ? Color(nsColor: .windowBackgroundColor) : (hovering ? Color.primary.opacity(0.03) : .clear))
        .overlay(alignment: .top) { if selected { Rectangle().fill(Color.lemmaOlive).frame(height: 2) } }
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .contextMenu {
            Button("Close", action: close)
            Button("Move Tab Left") { move(-1) }
            Button("Move Tab Right") { move(1) }
        }
        .help(title)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(selected ? [.isSelected, .isButton] : .isButton)
        .accessibilityAction(.default, select)
        .accessibilityAction(named: "Close", close)
    }
}
