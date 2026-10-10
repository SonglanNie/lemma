import SwiftUI
import AppKit
import LemmaCore

/// A layered map of what rests on what, in the side slot beside the page: a chapter's statements (or, for a book
/// without numbered statements, its sections), or everything one statement rests on. Prerequisites sit above what
/// uses them; arrows follow the references read in the text, which are evidence of dependency, not a verified proof graph.
struct DependencyMapView: View {
    @Bindable var store: StudyStore
    let request: MapRequest
    @State private var hovered: ReferenceKey?
    @State private var graph = MapGraph()

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if store.analysis?.analysis == nil {
                PaneEmptyState(symbol: "point.3.filled.connected.trianglepath.dotted", title: "Reading the book…", message: "The map appears once Lemma has read the book's references.")
            } else if graph.nodes.isEmpty {
                PaneEmptyState(symbol: "point.3.filled.connected.trianglepath.dotted", title: "Nothing to map here",
                               message: "This chapter has no numbered statements or sections whose references Lemma could link.")
            } else {
                GeometryReader { geometry in
                    // The whole layer width fits the slot (down to 60 %); taller maps scroll.
                    let scale = max(0.6, min(1, (geometry.size.width - 16) / max(graph.size.width, 1)))
                    ScrollView([.horizontal, .vertical]) {
                        ZStack(alignment: .topLeading) {
                            Canvas { context, _ in draw(edges: context) }
                                .frame(width: graph.size.width, height: graph.size.height)
                            ForEach(graph.nodes) { node in
                                MapNodeView(store: store, node: node, highlighted: highlight(node.key), dimmed: dim(node.key))
                                    .frame(width: MapGraph.nodeSize.width, height: MapGraph.nodeSize.height)
                                    .position(x: node.center.x, y: node.center.y)
                                    .onHover { inside in hovered = inside ? node.key : (hovered == node.key ? nil : hovered) }
                            }
                        }
                        .frame(width: graph.size.width, height: graph.size.height)
                        .scaleEffect(scale, anchor: .topLeading)
                        .frame(width: graph.size.width * scale, height: graph.size.height * scale, alignment: .topLeading)
                        .padding(8)
                        .frame(minWidth: geometry.size.width, alignment: .center)
                    }
                }
                legend
            }
        }
        .background(Color(nsColor: .textBackgroundColor))
        .onAppear(perform: rebuild)
        .onChange(of: request) { _, _ in rebuild() }
        .onChange(of: store.analysis?.analysis?.analyzedAt) { _, _ in rebuild() }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "point.3.filled.connected.trianglepath.dotted").foregroundStyle(Color.lemmaOlive)
            Text(title).font(.system(size: 12, weight: .semibold)).lineLimit(1)
            Text(graph.granularity == .sections ? "sections" : "statements").font(.caption).foregroundStyle(.secondary)
            Spacer(minLength: 6)
            if case .prerequisites = request.scope {
                Button("Chapter") { store.showMap() }.buttonStyle(.borderless).font(.caption).help("Map the chapter in view")
            } else {
                Button { store.showMap() } label: { Image(systemName: "scope") }.buttonStyle(.borderless).help("Map the chapter in view")
            }
            Button { store.closeMap() } label: { Image(systemName: "xmark").font(.system(size: 10, weight: .semibold)) }
                .buttonStyle(.borderless).help("Close the map").accessibilityLabel("Close map")
        }
        .padding(.horizontal, 10).frame(height: 30)
        .background(Color.lemmaSidebar)
    }

    private var legend: some View {
        HStack(spacing: 12) {
            Label("rests on", systemImage: "arrow.up").font(.caption2)
            Label("understood", systemImage: "checkmark.circle.fill").font(.caption2).foregroundStyle(Color(nsColor: .systemGreen))
            Text("Click to go · double-click for what it rests on").font(.caption2)
            Spacer()
        }
        .foregroundStyle(.secondary).padding(.horizontal, 10).frame(height: 22)
        .background(Color.lemmaSidebar)
    }

    private var title: String {
        switch request.scope {
        case let .chapter(number): "Map · Chapter \(number)"
        case let .prerequisites(key): "What \(key.title) rests on"
        }
    }

    private func highlight(_ key: ReferenceKey) -> Bool {
        guard let hovered else { return false }
        return key == hovered || graph.edges.contains { ($0.from == hovered && $0.to == key) || ($0.to == hovered && $0.from == key) }
    }

    private func dim(_ key: ReferenceKey) -> Bool { hovered != nil && !highlight(key) }

    private func draw(edges context: GraphicsContext) {
        let positions = Dictionary(graph.nodes.map { ($0.key, $0.center) }, uniquingKeysWith: { first, _ in first })
        let half = MapGraph.nodeSize.height / 2
        for edge in graph.edges {
            // The arrow points from what is used (above) to what uses it (below).
            guard let user = positions[edge.from], let used = positions[edge.to] else { continue }
            let start = CGPoint(x: used.x, y: used.y + half), end = CGPoint(x: user.x, y: user.y - half - 3)
            var path = Path()
            path.move(to: start)
            let bend = max(24, abs(end.y - start.y) * 0.45)
            path.addCurve(to: end, control1: CGPoint(x: start.x, y: start.y + bend), control2: CGPoint(x: end.x, y: end.y - bend))
            let active = hovered.map { $0 == edge.from || $0 == edge.to } ?? false
            let color = active ? Color.lemmaOlive : Color.secondary.opacity(hovered == nil ? 0.45 : 0.15)
            context.stroke(path, with: .color(color), lineWidth: active ? 1.8 : 1 + min(1.5, Double(edge.count - 1) * 0.3))
            var head = Path()
            head.move(to: end)
            head.addLine(to: CGPoint(x: end.x - 4, y: end.y - 7))
            head.addLine(to: CGPoint(x: end.x + 4, y: end.y - 7))
            head.closeSubpath()
            context.fill(head, with: .color(color))
        }
    }

    private func rebuild() {
        graph = MapGraph.build(request: request, store: store)
    }
}

/// A node of the map: a statement or a section.
struct MapNode: Identifiable, Equatable {
    var id: ReferenceKey { key }
    let key: ReferenceKey
    let title: String?
    let pageIndex: Int
    var center: CGPoint = .zero
}

/// The map's nodes, arrows and layout.
struct MapGraph: Equatable {
    enum Granularity { case statements, sections }
    static let nodeSize = CGSize(width: 176, height: 42)
    var nodes: [MapNode] = []
    var edges: [DependencyEdge] = []
    var size: CGSize = .zero
    var granularity: Granularity = .statements

    @MainActor static func build(request: MapRequest, store: StudyStore) -> MapGraph {
        guard let model = store.analysis, let analysis = model.analysis else { return MapGraph() }
        let structure = analysis.structure
        let statementKeys = Set(structure.statements.map(\.key))
        var graph = MapGraph()
        var keys: [ReferenceKey] = []
        var edges: [DependencyEdge] = []

        switch request.scope {
        case let .chapter(number):
            let prefix = number + "."
            let inChapter = structure.statements.filter { $0.key.number.hasPrefix(prefix) || $0.key.number == number }
            if inChapter.count >= 3 {
                keys = inChapter.map(\.key)
                let members = Set(keys)
                edges = structure.edges.filter { members.contains($0.from) && members.contains($0.to) && $0.from != $0.to }
            } else {
                graph.granularity = .sections
                (keys, edges) = sectionGraph(chapter: number, store: store, analysis: analysis)
            }
        case let .prerequisites(root):
            // Everything the root rests on, breadth first, statements only (sections when the book has no statements).
            let start = statementKeys.contains(root) ? root : sectionKey(containing: root, store: store, analysis: analysis) ?? root
            if !statementKeys.contains(start) { graph.granularity = .sections }
            var frontier = [start], seen: Set<ReferenceKey> = [start]
            keys = [start]
            var depth = 0
            while !frontier.isEmpty, depth < 5, keys.count < 60 {
                var next: [ReferenceKey] = []
                for key in frontier {
                    for edge in model.uses(key) {
                        let target = statementKeys.contains(edge.to) ? edge.to
                            : graph.granularity == .sections ? sectionKey(containing: edge.to, store: store, analysis: analysis) : nil
                        guard let target, target != key else { continue }
                        edges.append(DependencyEdge(from: key, to: target, inProof: edge.inProof, count: edge.count))
                        if seen.insert(target).inserted { keys.append(target); next.append(target) }
                    }
                }
                frontier = next; depth += 1
            }
        }
        let order = Dictionary(keys.enumerated().map { ($1, $0) }, uniquingKeysWith: { first, _ in first })
        graph.nodes = keys.map { key in
            let target = model.target(for: key)
            return MapNode(key: key, title: structure.statement(key)?.title ?? sectionTitle(key, store: store), pageIndex: target?.pageIndex ?? 0)
        }
        var unique: [DependencyEdge: Int] = [:]
        for edge in edges where order[edge.from] != nil && order[edge.to] != nil {
            unique[DependencyEdge(from: edge.from, to: edge.to, inProof: false, count: 0), default: 0] += edge.count
        }
        graph.edges = unique.map { DependencyEdge(from: $0.key.from, to: $0.key.to, inProof: false, count: $0.value) }
        graph.layout()
        return graph
    }

    /// Layers by longest chain of prerequisites (what rests on nothing sits on top); book order within a layer.
    /// Only references back to earlier material count as prerequisites: a forward pointer (“see Section 3.7”) is not.
    mutating func layout() {
        let rank = Dictionary(nodes.sorted { $0.pageIndex == $1.pageIndex ? $0.key.title < $1.key.title : $0.pageIndex < $1.pageIndex }
            .enumerated().map { ($1.key, $0) }, uniquingKeysWith: { first, _ in first })
        edges = edges.filter { (rank[$0.to] ?? 0) < (rank[$0.from] ?? 0) }
        let uses = Dictionary(grouping: edges, by: \.from).mapValues { $0.map(\.to) }
        var layer: [ReferenceKey: Int] = [:]
        func depth(_ key: ReferenceKey, _ visiting: Set<ReferenceKey>) -> Int {
            if let known = layer[key] { return known }
            let below = (uses[key] ?? []).filter { !visiting.contains($0) }
            let value = below.isEmpty ? 0 : 1 + (below.map { depth($0, visiting.union([key])) }.max() ?? 0)
            layer[key] = value
            return value
        }
        for node in nodes { _ = depth(node.key, []) }
        let rows = Dictionary(grouping: nodes.indices, by: { layer[nodes[$0].key] ?? 0 })
        let spacing = CGSize(width: 20, height: 52)
        let widest = rows.values.map(\.count).max() ?? 1
        let width = CGFloat(widest) * (Self.nodeSize.width + spacing.width) + spacing.width
        for (row, indices) in rows {
            let ordered = indices.sorted { nodes[$0].pageIndex == nodes[$1].pageIndex ? nodes[$0].key.title < nodes[$1].key.title : nodes[$0].pageIndex < nodes[$1].pageIndex }
            let rowWidth = CGFloat(ordered.count) * (Self.nodeSize.width + spacing.width) - spacing.width
            let left = (width - rowWidth) / 2
            for (column, index) in ordered.enumerated() {
                nodes[index].center = CGPoint(x: left + CGFloat(column) * (Self.nodeSize.width + spacing.width) + Self.nodeSize.width / 2,
                                              y: spacing.height / 2 + CGFloat(row) * (Self.nodeSize.height + spacing.height) + Self.nodeSize.height / 2)
            }
        }
        let layers = (rows.keys.max() ?? 0) + 1
        size = CGSize(width: max(width, Self.nodeSize.width + 40), height: CGFloat(layers) * (Self.nodeSize.height + spacing.height) + spacing.height / 2)
    }

    /// Sections of a chapter and, between them, what one section's text uses from another.
    @MainActor static func sectionGraph(chapter: String, store: StudyStore, analysis: BookAnalysis) -> ([ReferenceKey], [DependencyEdge]) {
        let sections = sectionStarts(store: store).filter { $0.number.hasPrefix(chapter + ".") && $0.number.split(separator: ".").count == 2 }
        let keys = sections.map { ReferenceKey(kind: .section, number: $0.number) }
        let members = Set(keys)
        var edges: [DependencyEdge: Int] = [:]
        for edge in analysis.structure.edges {
            guard let from = sectionKey(containing: edge.from, store: store, analysis: analysis, depth: 2),
                  let to = sectionKey(containing: edge.to, store: store, analysis: analysis, depth: 2),
                  from != to, members.contains(from), members.contains(to) else { continue }
            edges[DependencyEdge(from: from, to: to, inProof: false, count: 0), default: 0] += edge.count
        }
        return (keys, edges.map { DependencyEdge(from: $0.key.from, to: $0.key.to, inProof: false, count: $0.value) })
    }

    /// Numbered outline sections with their first page, in book order.
    @MainActor static func sectionStarts(store: StudyStore) -> [(number: String, pageIndex: Int, title: String)] {
        store.outline.flatMap(\.flattened).compactMap { entry in
            guard let number = OutlineMap.numberPrefix(of: entry.title), number.contains("."), let page = entry.pageIndex else { return nil }
            return (number, page, entry.title)
        }
    }

    /// The section (at `depth` levels, “3.4”) where an object is defined or a section belongs.
    @MainActor static func sectionKey(containing key: ReferenceKey, store: StudyStore, analysis: BookAnalysis, depth: Int = 3) -> ReferenceKey? {
        func truncated(_ number: String) -> ReferenceKey {
            ReferenceKey(kind: .section, number: number.split(separator: ".").prefix(depth).joined(separator: "."))
        }
        if key.kind == .section { return truncated(key.number) }
        guard let target = store.analysis?.target(for: key) else { return nil }
        let starts = sectionStarts(store: store)
        guard let section = starts.last(where: { $0.pageIndex <= target.pageIndex }) else { return nil }
        return truncated(section.number)
    }

    @MainActor static func sectionTitle(_ key: ReferenceKey, store: StudyStore) -> String? {
        guard key.kind == .section || key.kind == .chapter else { return nil }
        let entry = store.outline.flatMap(\.flattened).first { OutlineMap.numberPrefix(of: $0.title) == key.number }
        return entry.map { title in
            var text = title.title
            if let range = text.range(of: #"^\d+(\.\d+)*\s*"#, options: .regularExpression) { text.removeSubrange(range) }
            return text
        }
    }
}

/// One box of the map.
private struct MapNodeView: View {
    @Bindable var store: StudyStore
    let node: MapNode
    let highlighted: Bool
    let dimmed: Bool

    var body: some View {
        let understood = store.isUnderstood(node.key)
        let here = node.pageIndex == store.reader.focusPageIndex
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 5) {
                KindBadge(key: node.key, size: 13)
                Text(node.key.kind == .section ? "§ \(node.key.number)" : node.key.title).font(.system(size: 11.5, weight: .semibold)).monospacedDigit().lineLimit(1)
                Spacer(minLength: 0)
                if understood { Image(systemName: "checkmark.circle.fill").font(.system(size: 10)).foregroundStyle(Color(nsColor: .systemGreen)) }
            }
            Text(node.title ?? store.shortPageText(node.pageIndex)).font(.system(size: 10.5)).foregroundStyle(.secondary).lineLimit(1)
        }
        .padding(.horizontal, 8).padding(.vertical, 5)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 7))
        .overlay(RoundedRectangle(cornerRadius: 7).stroke(understood ? Color(nsColor: .systemGreen).opacity(0.8)
                                                          : highlighted || here ? Color.lemmaOlive : Color(nsColor: .separatorColor),
                                                          lineWidth: highlighted || here ? 1.6 : 1))
        .shadow(color: .black.opacity(highlighted ? 0.12 : 0.04), radius: highlighted ? 4 : 1.5, y: 1)
        .opacity(dimmed ? 0.45 : 1)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { store.showMap(for: node.key) }
        .onTapGesture {
            if NSEvent.modifierFlags.contains(.option) { store.openKeyToTheSide(node.key) } else { store.goToKey(node.key) }
        }
        .contextMenu { StatementMenu(store: store, key: node.key) }
        .help([node.key.title, node.title].compactMap { $0 }.joined(separator: " · "))
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }
}
