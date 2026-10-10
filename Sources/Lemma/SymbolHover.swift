import SwiftUI
import AppKit
import PDFKit
import LemmaCore

/// What a symbol under the pointer stands for: the definition in force at that place in the book (“where λ ≥ 0 is
/// a complexity parameter”, p. 63), as an editor's hover shows a variable's declaration. Read from the text; it can
/// be wrong when the book reuses a letter, so every other meaning is listed too.
struct SymbolHit: Equatable {
    let symbol: String
    let pageIndex: Int
    let location: Int
    let rect: CGRect
}

@MainActor
final class SymbolHoverController {
    private weak var view: RegionPDFView?
    private var popover: NSPopover?
    private let panel = VSFloatingPanel()
    private var pending: DispatchWorkItem?
    private(set) var shown: SymbolHit?
    weak var store: StudyStore?

    init(view: RegionPDFView) { self.view = view }

    func update(_ hit: SymbolHit?) {
        if let shown, let hit, shown.symbol == hit.symbol, shown.location == hit.location, shown.pageIndex == hit.pageIndex { return }
        pending?.cancel(); pending = nil
        dismiss()
        guard let hit, LemmaPreferences.flag(LemmaPreferences.hoverPreviews) else { return }
        let work = DispatchWorkItem { [weak self] in MainActor.assumeIsolated { self?.show(hit) } }
        pending = work
        DispatchQueue.main.asyncAfter(deadline: .now() + HoverPreviewController.delay + 0.1, execute: work)
    }

    func dismiss() {
        pending?.cancel(); pending = nil
        if popover?.isShown == true { popover?.close() }
        panel.close(notify: false)
        popover = nil; shown = nil
    }

    /// Shows a hover without the pointer (visual review).
    func showNow(_ hit: SymbolHit) { show(hit, requirePointer: false) }

    private func show(_ hit: SymbolHit, requirePointer: Bool = true) {
        guard let view, let store, view.window?.isKeyWindow == true || !requirePointer, NSEvent.pressedMouseButtons == 0 || !requirePointer,
              view.hoveredSymbol == hit || !requirePointer,
              store.referencePeek == nil, store.definitionLookup == nil, store.quickAsk == nil, store.palette == nil,
              let notation = store.analysis?.notation,
              let found = notation.definition(of: hit.symbol, at: TextPoint(pageIndex: hit.pageIndex, location: hit.location)),
              let page = view.document?.page(at: hit.pageIndex) else { return }
        let anchor = view.convert(hit.rect, from: page).intersection(view.bounds)
        guard !anchor.isNull, !anchor.isEmpty else { return }
        let pane = SymbolHoverPane(store: store, symbol: hit.symbol, current: found.definition, later: found.later,
                                   others: notation.otherMeanings(of: hit.symbol, near: hit.pageIndex, excluding: found.definition),
                                   total: notation.meanings(of: hit.symbol).count)
        if ThemeManager.shared.style == .vscode {
            dismiss()
            panel.show(VSHoverChrome(status: "Read from the text · ⌘-click to see where") { pane.compact() }, anchor: anchor, in: view, placement: .above, interactive: false)
            shown = hit
            return
        }
        let popover = NSPopover()
        popover.behavior = .applicationDefined
        popover.animates = true
        let controller = NSHostingController(rootView: pane.tint(.lemmaOlive))
        controller.sizingOptions = [.preferredContentSize]
        popover.contentViewController = controller
        self.popover = popover
        shown = hit
        popover.show(relativeTo: anchor, of: view, preferredEdge: .maxY)
    }
}

struct SymbolHoverPane: View {
    @Bindable var store: StudyStore
    let symbol: String
    let current: SymbolDefinition
    let later: Bool
    let others: [SymbolDefinition]
    let total: Int
    var isCompact = false

    /// The pane inside VS Code's hover chrome, which supplies the padding and the hint row.
    func compact() -> SymbolHoverPane { var copy = self; copy.isCompact = true; return copy }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(symbol).font(.system(size: 20, weight: .regular, design: .serif)).italic()
                VStack(alignment: .leading, spacing: 2) {
                    Text(current.meaning).font(.system(size: 12.5, weight: .medium)).fixedSize(horizontal: false, vertical: true).lineLimit(4)
                    Text((later ? "Defined later · " : current.explicit ? "Defined · " : "Named · ") + store.shortPageText(current.pageIndex))
                        .font(.system(size: 10.5)).foregroundStyle(.secondary)
                }
            }
            if !others.isEmpty {
                Divider()
                Text("Other meanings in the book").font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
                ForEach(Array(others.prefix(4).enumerated()), id: \.offset) { _, other in
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(store.shortPageText(other.pageIndex)).font(.system(size: 10.5).monospacedDigit()).foregroundStyle(.secondary).frame(width: 44, alignment: .leading)
                        Text(other.meaning).font(.system(size: 11)).lineLimit(2)
                    }
                }
                if total - 1 > others.count { Text("and \(total - 1 - others.count) more in the book").font(.system(size: 10)).foregroundStyle(.tertiary) }
            }
            if !isCompact { Text("Read from the text · ⌘-click to see where").font(.system(size: 10)).foregroundStyle(.tertiary) }
        }
        .padding(isCompact ? 0 : 10)
        .frame(width: 320)
        .fixedSize(horizontal: false, vertical: true)
    }
}
