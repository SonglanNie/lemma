import SwiftUI
import AppKit
import LemmaCore

/// The panel's Hierarchy view, an editor's call hierarchy for a book: what a statement's text and proof use, and
/// which statements and sections use it, each expandable in turn. Uses are read from the references in the text;
/// they are evidence of dependency, not a verified proof graph.
struct HierarchyPanel: View {
    @Bindable var store: StudyStore

    var body: some View {
        if let key = store.hierarchyKey, store.analysis?.analysis != nil {
            VStack(spacing: 0) {
                header(key)
                Divider()
                let edges = edges(of: key)
                if edges.isEmpty {
                    PaneEmptyState(symbol: store.hierarchyDirection.symbol,
                                   title: store.hierarchyDirection == .uses ? "No references found in its text" : "Nothing in the book refers to it",
                                   message: store.hierarchyDirection == .uses
                                    ? "Lemma reads the references a statement and its proof make (“by Lemma 2.1”, “(3.4)”). This one cites none it could link."
                                    : "No statement, proof or section mentions \(key.title) by its number.")
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            ForEach(edges, id: \.self) { edge in
                                HierarchyNode(store: store, key: other(edge), count: edge.count, inProof: edge.inProof, depth: 0, path: [key])
                            }
                        }.padding(.vertical, 4)
                    }
                }
            }
        } else if store.analysis?.analysis == nil {
            PaneEmptyState(symbol: "point.3.connected.trianglepath.dotted", title: "Reading the book…", message: "The hierarchy appears once Lemma has read the book's references.")
        } else {
            PaneEmptyState(symbol: "point.3.connected.trianglepath.dotted", title: "What uses what",
                           message: "Right-click a theorem, lemma or equation and choose Show What It Uses, or use the button below for the statement you are reading.",
                           action: ("Show the Statement in View", { store.showHierarchyAtFocus() }))
        }
    }

    private func header(_ key: ReferenceKey) -> some View {
        HStack(spacing: 8) {
            KindBadge(key: key)
            Text(key.title).font(.system(size: 12, weight: .semibold)).lineLimit(1)
            if let title = store.analysis?.structure.statement(key)?.title ?? MapGraph.sectionTitle(key, store: store) {
                Text(title).font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(1)
            }
            if let target = store.analysis?.target(for: key) {
                Text(store.shortPageText(target.pageIndex)).font(.caption.monospacedDigit()).foregroundStyle(.tertiary)
            }
            Spacer(minLength: 8)
            Picker("Direction", selection: $store.hierarchyDirection) {
                ForEach(HierarchyDirection.allCases) { direction in
                    Label("\(direction.title) \(count(key, direction))", systemImage: direction.symbol).tag(direction)
                }
            }.pickerStyle(.segmented).labelsHidden().fixedSize()
            Button { store.showMap(for: key) } label: { Image(systemName: "point.3.filled.connected.trianglepath.dotted") }
                .buttonStyle(.borderless).help("Map of what \(key.title) rests on").accessibilityLabel("Prerequisites map")
            Button { store.showHierarchyAtFocus() } label: { Image(systemName: "scope") }
                .buttonStyle(.borderless).help("Show the statement at the reading position").accessibilityLabel("Statement in view")
        }
        .padding(.horizontal, 12).frame(height: 30)
        .contextMenu { StatementMenu(store: store, key: key) }
    }

    private func count(_ key: ReferenceKey, _ direction: HierarchyDirection) -> Int {
        (direction == .uses ? store.analysis?.uses(key) : store.analysis?.usedBy(key))?.count ?? 0
    }

    private func edges(of key: ReferenceKey) -> [DependencyEdge] {
        (store.hierarchyDirection == .uses ? store.analysis?.uses(key) : store.analysis?.usedBy(key)) ?? []
    }

    private func other(_ edge: DependencyEdge) -> ReferenceKey { store.hierarchyDirection == .uses ? edge.to : edge.from }
}

/// One row of the hierarchy and, when expanded, the next level in the same direction.
private struct HierarchyNode: View {
    @Bindable var store: StudyStore
    let key: ReferenceKey
    let count: Int
    let inProof: Bool
    let depth: Int
    let path: [ReferenceKey]
    @State private var expanded = false
    @State private var hovering = false

    var body: some View {
        let children = childEdges
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Button { expanded.toggle() } label: {
                    Image(systemName: "chevron.right").font(.system(size: 9, weight: .semibold))
                        .rotationEffect(.degrees(expanded ? 90 : 0)).frame(width: 12)
                        .opacity(children.isEmpty || path.contains(key) ? 0 : 1)
                }
                .buttonStyle(.plain).disabled(children.isEmpty || path.contains(key))
                .accessibilityLabel(expanded ? "Collapse" : "Expand")
                KindBadge(key: key, size: 14)
                Text(key.title).font(.system(size: 12)).monospacedDigit().lineLimit(1)
                if let title = store.analysis?.structure.statement(key)?.title ?? MapGraph.sectionTitle(key, store: store) {
                    Text(title).font(.system(size: 11.5)).foregroundStyle(.secondary).lineLimit(1)
                }
                if inProof, depth == 0 {
                    Text("in proof").font(.system(size: 9.5, weight: .medium)).foregroundStyle(.secondary)
                        .padding(.horizontal, 4).padding(.vertical, 1).background(Color.primary.opacity(0.06), in: Capsule())
                }
                if store.isUnderstood(key) {
                    Image(systemName: "checkmark.circle.fill").font(.system(size: 10)).foregroundStyle(Color(nsColor: .systemGreen))
                }
                Spacer(minLength: 6)
                if count > 1 { Text("×\(count)").font(.caption2.monospacedDigit()).foregroundStyle(.tertiary) }
                if let target = store.analysis?.target(for: key) {
                    Text(store.shortPageText(target.pageIndex)).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                }
            }
            .padding(.leading, 12 + CGFloat(depth) * 16).padding(.trailing, 12)
            .frame(height: 24)
            .background(hovering ? Color.primary.opacity(0.05) : .clear)
            .contentShape(Rectangle())
            .onHover { hovering = $0 }
            .onTapGesture(count: 2) { store.showHierarchy(key) }
            .onTapGesture {
                if NSEvent.modifierFlags.contains(.option) { store.openKeyToTheSide(key) } else { store.goToKey(key) }
            }
            .contextMenu { StatementMenu(store: store, key: key) }
            .help("Click to go there, ⌥-click to open beside the page, double-click to centre the hierarchy here")
            if expanded {
                ForEach(children, id: \.self) { edge in
                    HierarchyNode(store: store, key: store.hierarchyDirection == .uses ? edge.to : edge.from, count: edge.count,
                                  inProof: edge.inProof, depth: depth + 1, path: path + [key])
                }
            }
        }
    }

    private var childEdges: [DependencyEdge] {
        guard depth < 8 else { return [] }
        return (store.hierarchyDirection == .uses ? store.analysis?.uses(key) : store.analysis?.usedBy(key)) ?? []
    }
}
