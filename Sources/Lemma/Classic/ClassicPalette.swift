import SwiftUI
import AppKit
import LemmaCore

/// Lemma 1.1's command palette, for the Classic interface style.
/// The floating list itself, at the top of the window as in an editor. As in the VS Code style, the rows are worked
/// out when the text changes and kept: arrow keys only move the selection.
struct ClassicCommandPaletteView: View {
    @Bindable var store: StudyStore
    let request: PaletteRequest
    @State private var text: String
    @State private var selection = 0
    @State private var items: [PaletteItem] = []
    @State private var session: PaletteSession?

    init(store: StudyStore, request: PaletteRequest) {
        self.store = store; self.request = request
        _text = State(initialValue: request.text)
    }

    /// Ranks the candidates for the text; the session gathers and folds them once per opening.
    private func refresh() {
        let session = self.session ?? PaletteSession(store: store)
        if self.session == nil { self.session = session }
        items = session.items(mode: request.mode, query: text)
    }

    private var placeholder: String {
        switch request.mode {
        case .commands: "Run a command"
        case .symbols: "Go to an equation, figure, table, algorithm or exercise"
        case .goTo: store.document == nil ? "Open a book, or type > for commands" : "Page, section, (3.41), fig 3.8, a term or a note · > for commands"
        case .themes: "Select a colour theme (VS Code style)"
        }
    }

    var body: some View {
        let items = items
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: request.mode == .commands || text.hasPrefix(">") ? "chevron.right.2" : "magnifyingglass")
                    .foregroundStyle(.secondary).frame(width: 16)
                PaletteField(text: $text, placeholder: placeholder,
                             onMove: { delta in move(delta, count: items.count) },
                             onSubmit: { side in run(items, side: side) },
                             onCancel: { store.closePalette() })
            }.padding(.horizontal, 12).frame(height: 38)
            Divider()
            if items.isEmpty {
                Text(emptyMessage).font(.callout).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading).padding(14)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(Array(items.enumerated()), id: \.element.id) { offset, item in
                                row(item, selected: offset == selection).id(offset)
                                    .onTapGesture { selection = offset; run(items, side: NSEvent.modifierFlags.contains(.option)) }
                            }
                        }.padding(.vertical, 4)
                    }
                    .frame(maxHeight: min(CGFloat(items.count) * 34 + 8, 420))
                    .onChange(of: selection) { _, value in proxy.scrollTo(value) }
                }
            }
            Divider()
            HStack(spacing: 14) {
                Text("↩ Open").monospacedDigit()
                Text("⌥↩ Open to the side")
                Text("esc Close")
                Spacer()
                if request.mode == .goTo && !text.hasPrefix(">") { Text("> commands · @ symbols") }
            }.font(.caption).foregroundStyle(.secondary).padding(.horizontal, 12).frame(height: 26)
        }
        .frame(width: 640)
        .background(Color(nsColor: .windowBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color(nsColor: .separatorColor)))
        .shadow(color: .black.opacity(0.25), radius: 18, y: 8)
        .onChange(of: text) { _, _ in refresh(); selection = 0 }
        .onAppear { refresh() }
        .task {
            // Once the palette is on screen, gather what typing will search, so the first keystroke only ranks.
            try? await Task.sleep(for: .milliseconds(40))
            session?.prepare(mode: request.mode)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(request.mode == .commands ? "Command palette" : "Go to")
    }

    private var emptyMessage: String {
        if store.document == nil && request.mode != .commands { return "Open a book to go to its pages, sections and equations." }
        if request.mode == .symbols && store.analysis?.analysis == nil { return store.analysis?.isAnalyzing == true ? "Lemma is still reading this book…" : "No numbered objects found yet." }
        return "No matches. Try a page number, “(3.41)”, “fig 3.8” or a term from the index."
    }

    private func row(_ item: PaletteItem, selected: Bool) -> some View {
        HStack(spacing: 10) {
            Image(systemName: item.symbol).frame(width: 18).foregroundStyle(selected ? Color.white : Color.secondary)
            VStack(alignment: .leading, spacing: 1) {
                Text(item.title).font(.system(size: 13)).lineLimit(1)
                if !item.detail.isEmpty { Text(item.detail).font(.caption).foregroundStyle(selected ? Color.white.opacity(0.85) : .secondary).lineLimit(1) }
            }
            Spacer(minLength: 8)
            if let shortcut = item.shortcut { Text(shortcut).font(.caption.monospaced()).foregroundStyle(selected ? Color.white.opacity(0.85) : .secondary) }
            Text(item.category).font(.caption2).foregroundStyle(selected ? Color.white.opacity(0.85) : Color.secondary.opacity(0.8))
        }
        .foregroundStyle(selected ? Color.white : Color.primary)
        .padding(.horizontal, 10).frame(height: 34)
        .background(selected ? Color.lemmaOliveSelection : Color.clear, in: RoundedRectangle(cornerRadius: 6))
        .padding(.horizontal, 6)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(selected ? [.isSelected, .isButton] : .isButton)
    }

    private func move(_ delta: Int, count: Int) {
        guard count > 0 else { return }
        selection = (selection + delta + count) % count
    }

    private func run(_ items: [PaletteItem], side: Bool) {
        guard items.indices.contains(selection) else { return }
        let item = items[selection]
        store.palette = nil
        if side, let openToSide = item.openToSide { openToSide() } else { item.perform() }
    }
}

