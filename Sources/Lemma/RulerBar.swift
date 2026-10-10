import SwiftUI
import AppKit
import PDFKit
import LemmaCore

/// The strip under the breadcrumbs while the reading ruler is on: where the ruler is and what the line offers.
struct RulerBar: View {
    @Bindable var store: StudyStore

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "text.line.first.and.arrowtriangle.forward").foregroundStyle(Color.lemmaOlive)
            if let line = store.reader.rulerLine {
                Text("Line \(line.index + 1) of \(line.count) · \(store.shortPageText(line.pageIndex))").font(.caption.monospacedDigit())
                if let statement = store.statementAtRuler() {
                    Text("in \(statement.key.title)\(statement.title.map { " (\($0))" } ?? "")").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            } else {
                Text("Click a line to start").font(.caption).foregroundStyle(.secondary)
            }
            Text("↓ ↑ or J K step · Space jumps · Return opens the line's reference").font(.caption).foregroundStyle(.tertiary).lineLimit(1).layoutPriority(-1)
            Spacer(minLength: 0)
            Button { store.askAboutRulerLine() } label: { Label("Why?", systemImage: "text.bubble") }
                .help("Ask about this line with its context · the step you do not follow")
                .disabled(store.reader.rulerLine == nil)
            Button { store.deriveSelection() } label: { Label("Derive", systemImage: "function") }
                .help("Work this line through yourself: each step you write is checked · ⌥⌘E")
                .disabled(store.reader.rulerLine == nil)
            Button { store.showHierarchyAtFocus() } label: { Label("Uses", systemImage: "point.3.connected.trianglepath.dotted") }
                .help("What the statement being read uses")
            Button { store.reader.rulerMode = false } label: { Image(systemName: "xmark") }.help("Put the ruler away · Escape")
        }
        .font(.system(size: 12))
        .buttonStyle(.borderless).padding(.horizontal, 12).frame(height: 30).background(Color.lemmaOlive.opacity(0.07))
    }
}

@MainActor
extension StudyStore {
    /// The statement whose text or proof holds the ruler's line.
    func statementAtRuler() -> StatementInfo? {
        guard let line = reader.rulerLine, let structure = analysis?.analysis?.structure,
              let location = pageTextMap(line.pageIndex)?.line(at: CGPoint(x: line.rect.midX, y: line.rect.midY))?.range.location else { return nil }
        let point = TextPoint(pageIndex: line.pageIndex, location: location)
        if let proof = structure.proofs.last(where: { $0.start <= point && point < $0.end }), let key = proof.statement { return structure.statement(key) }
        return structure.statements.last { $0.start <= point && point < $0.end }
    }

    /// Selects the ruler's line and opens a quick question about it, with the usual context.
    func askAboutRulerLine() {
        guard let line = reader.rulerLine, let page = document?.page(at: line.pageIndex) else { return }
        let region = line.rect.insetBy(dx: -4, dy: -3).intersection(page.bounds(for: .cropBox))
        reader.selection = (line.pageIndex, region, page.selection(for: region)?.string ?? "")
        reader.hasSelection = true
        prepareQuickAsk()
    }
}

/// Sticky scroll for mathematics: while a long statement or proof is read below its label, a slim header at the
/// top of the page names it (“Proof of Theorem 3.2 (Gauss–Markov)”), as an editor keeps a function's signature
/// in view. A click goes back to the label. It is drawn in the colour theme's sticky scroll colours, as VS Code draws
/// its own, and follows the statement the reader publishes, which changes only when the statement or its label's
/// visibility does (not on every scroll step).
struct StickyStatementBar: View {
    @Bindable var store: StudyStore

    /// A fixed strip, transparent and taking no clicks, with the header as its overlay: the header changes as the page
    /// scrolls, and as an overlay of the editor itself each change would measure the editor's whole stack again.
    var body: some View {
        Color.clear
            .frame(height: 24)
            .frame(maxWidth: .infinity)
            .overlay(alignment: .top) { StickyStatementHeader(store: store) }
    }
}

private struct StickyStatementHeader: View {
    @Bindable var store: StudyStore
    @Environment(\.theme) private var theme
    @State private var hovering = false

    var body: some View {
        let _ = QAPerf.tick("StickyStatementBar")
        if store.analysis?.analysis != nil, !store.reader.rulerMode, let reading = store.reader.focusStatement, !store.reader.focusLabelVisible {
            HStack(spacing: 6) {
                Codicon(reading.inProof ? "indent" : "chevron-down", size: 12).foregroundStyle(theme[.descriptionForeground])
                KindBadge(key: reading.statement.key, size: 13)
                Text(reading.label).font(.ui(12, weight: .semibold)).foregroundStyle(theme[.foreground]).lineLimit(1)
                if let title = reading.statement.title { Text(title).font(.ui(12)).foregroundStyle(theme[.descriptionForeground]).lineLimit(1) }
                Spacer(minLength: 8)
                if let target = store.analysis?.target(for: reading.statement.key) {
                    Text("from \(store.shortPageText(target.pageIndex))").font(.ui(11)).monospacedDigit().foregroundStyle(theme[.descriptionForeground])
                }
            }
            .padding(.horizontal, 10).frame(height: 24)
            .background(theme[hovering ? .editorStickyScrollHoverBackground : .editorStickyScrollBackground])
            .overlay(alignment: .bottom) { bottomEdge }
            .contentShape(Rectangle())
            .onHover { hovering = $0 }
            .onTapGesture { store.goToKey(reading.statement.key) }
            .contextMenu { StatementMenu(store: store, key: reading.statement.key) }
            .help("You are reading \(reading.label) · click to go back to its statement")
            .transition(.opacity)
        }
    }

    /// VS Code puts a short shadow under its sticky lines; themes without one get the widget border, or nothing.
    @ViewBuilder private var bottomEdge: some View {
        if theme.has(.editorStickyScrollShadow) {
            LinearGradient(colors: [theme[.editorStickyScrollShadow], theme[.editorStickyScrollShadow].opacity(0)], startPoint: .top, endPoint: .bottom)
                .frame(height: 3).offset(y: 3).allowsHitTesting(false)
        } else {
            Rectangle().fill(theme.border(.editorWidgetBorder)).frame(height: 1)
        }
    }
}
