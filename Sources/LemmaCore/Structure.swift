import Foundation
import PDFKit

/// A place in a document's reading order: a page and a UTF-16 offset in its text layer. PDFKit orders a page's
/// text by reading order, columns included, so offsets compare the way a reader moves through the page.
public struct TextPoint: Codable, Hashable, Comparable, Sendable {
    public var pageIndex: Int
    public var location: Int
    public init(pageIndex: Int, location: Int) { self.pageIndex = pageIndex; self.location = location }
    public static func < (a: TextPoint, b: TextPoint) -> Bool {
        a.pageIndex == b.pageIndex ? a.location < b.location : a.pageIndex < b.pageIndex
    }
}

/// A rectangle on one page, in PDF page space.
public struct PageRect: Codable, Equatable, Sendable {
    public var pageIndex: Int
    public var region: PageRegion
    public init(pageIndex: Int, region: PageRegion) { self.pageIndex = pageIndex; self.region = region }
}

/// A proof, the statement it proves and the lines it covers, so a reader can fold it away and try first.
public struct ProofBlock: Codable, Equatable, Identifiable, Sendable {
    public var id: Int
    /// A name that survives a new analysis of the book: where the proof starts, as “page:offset”.
    public var stableID: String { "\(start.pageIndex):\(start.location)" }
    /// The statement proved: the one the heading names (“Proof of Theorem 2.3”) or the nearest one before it.
    public var statement: ReferenceKey?
    public var start: TextPoint
    public var end: TextPoint
    /// The proof ends at an end-of-proof mark (∎, □, “Q.E.D.”) rather than at the next statement or heading.
    public var endsWithMark: Bool
    /// The proof's lines, one rectangle per page and column.
    public var regions: [PageRect]
    public var lineCount: Int
    public init(id: Int, statement: ReferenceKey?, start: TextPoint, end: TextPoint, endsWithMark: Bool, regions: [PageRect], lineCount: Int) {
        self.id = id; self.statement = statement; self.start = start; self.end = end
        self.endsWithMark = endsWithMark; self.regions = regions; self.lineCount = lineCount
    }
}

/// A numbered statement: its title and where its own text runs.
public struct StatementInfo: Codable, Equatable, Sendable {
    public var key: ReferenceKey
    /// “Gauss–Markov” in “Theorem 3.2 (Gauss–Markov)”, or a short bold or italic name after the label.
    public var title: String?
    public var start: TextPoint
    /// Where the statement's own text ends: its proof, or the next statement or heading.
    public var end: TextPoint
    public var proof: Int?
    public init(key: ReferenceKey, title: String?, start: TextPoint, end: TextPoint, proof: Int?) {
        self.key = key; self.title = title; self.start = start; self.end = end; self.proof = proof
    }
}

/// “Theorem 3.2 uses Lemma 3.1”: the text of `from` (a statement, its proof or a section) mentions `to`.
/// A mention is not a proof of dependency; it is the best evidence a text gives without understanding it.
public struct DependencyEdge: Codable, Hashable, Sendable {
    public var from: ReferenceKey
    public var to: ReferenceKey
    /// The mention sits in the proof rather than in the statement.
    public var inProof: Bool
    public var count: Int
    public init(from: ReferenceKey, to: ReferenceKey, inProof: Bool, count: Int = 1) {
        self.from = from; self.to = to; self.inProof = inProof; self.count = count
    }
}

/// Statements, proofs and the uses between them, read from a whole book once.
public struct DocumentStructure: Codable, Equatable, Sendable {
    public var statements: [StatementInfo] = []
    public var proofs: [ProofBlock] = []
    public var edges: [DependencyEdge] = []
    public init() {}

    public func statement(_ key: ReferenceKey) -> StatementInfo? { statements.first { $0.key == key } }
    public func proof(of key: ReferenceKey) -> ProofBlock? { proofs.first { $0.statement == key } }
    /// What `key`'s text mentions, strongest first.
    public func uses(_ key: ReferenceKey) -> [DependencyEdge] {
        edges.filter { $0.from == key }.sorted { $0.count == $1.count ? $0.to.title < $1.to.title : $0.count > $1.count }
    }
    /// Which statements and sections mention `key`.
    public func usedBy(_ key: ReferenceKey) -> [DependencyEdge] {
        edges.filter { $0.to == key }.sorted { $0.count == $1.count ? $0.from.title < $1.from.title : $0.count > $1.count }
    }
}

/// Finds statements' extents, proofs and their end marks, and the mentions made inside each.
public enum StructureAnalyzer {
    /// Statement kinds whose proof follows them. Definitions, examples and remarks are not proved.
    public static let provedNames: Set<String> = ["Theorem", "Lemma", "Proposition", "Corollary", "Claim", "Fact", "Property", "Result", "Conjecture", "Observation"]

    private static let proofHead = try! NSRegularExpression(
        pattern: #"^[ \t]*((?:Proof|PROOF)(?:\s+of\s+[^.\n:]{1,80}|\s*\([^)\n]{1,60}\))?)(?:\s*[.:]|[ \t]*$|[ \t]{1,3}(?=\p{Lu}))"#, options: [.anchorsMatchLines])
    /// “Proof.” inside a text line: PDFKit can join a page's running head and its first line.
    private static let inlineProofHead = try! NSRegularExpression(pattern: #"(?<=\S[ \t])((?:Proof|PROOF)(?:\s+of\s+[^.\n:]{1,80})?)\s*[.:]"#)
    /// End-of-proof marks as text: ∎ □ ■ ◻ ◼ ▫ ▪ ⊓⊔ and Q.E.D.
    private static let endMark = try! NSRegularExpression(pattern: #"[∎□■◻◼▫▪]|⊓⊔|\bQ\.\s?E\.\s?D\.?|\bQED\b|\bq\.e\.d\."#)

    /// - Parameters:
    ///   - texts: each page's text layer, as PDFKit returns it.
    ///   - definitions: every numbered definition found, with `location` set for those read from the text.
    ///   - boundaries: further places where a proof cannot continue (section headings from the outline).
    ///   - sections: the outline's chapters and sections with where they start, so mentions outside statements belong to them.
    public static func analyze(document: PDFDocument, texts: [String], definitions: [ReferenceTarget], mentions: [MentionRecord],
                               sections outlineSections: [(key: ReferenceKey, point: TextPoint)] = [],
                               resolve: (ReferenceKey) -> ReferenceKey? = { $0 }) -> DocumentStructure {
        var structure = DocumentStructure()
        // Statement heads in reading order.
        let heads = definitions.filter { [.theorem, .exercise, .algorithm].contains($0.key.kind) && $0.origin == .text && $0.location != nil }
            .map { (target: $0, point: TextPoint(pageIndex: $0.pageIndex, location: $0.location!)) }
            .sorted { $0.point < $1.point }
        let sectionStarts = definitions.filter { $0.key.kind == .section && $0.location != nil }
            .map { TextPoint(pageIndex: $0.pageIndex, location: $0.location!) }
        // Proof heads and end marks.
        var proofStarts: [(point: TextPoint, named: ReferenceKey?, headLength: Int)] = []
        var marks: [TextPoint] = []
        for (pageIndex, text) in texts.enumerated() where !text.isEmpty {
            let string = text as NSString
            let whole = NSRange(location: 0, length: string.length)
            for match in proofHead.matches(in: text, range: whole) {
                let head = string.substring(with: match.range(at: 1))
                let named = ReferenceScanner.mentions(in: head).first { $0.key.kind == .theorem || $0.key.kind == .exercise }?.key
                proofStarts.append((TextPoint(pageIndex: pageIndex, location: match.range.location), named.flatMap(resolve) ?? named, match.range.length))
            }
            // A proof opening a page whose running head PDFKit joined to it: the word before sits on another line.
            if let page = document.page(at: pageIndex) {
                for match in inlineProofHead.matches(in: text, range: whole) {
                    let start = match.range(at: 1).location
                    guard start > 0, let head = PageTextMap.bounds(of: start, on: page), let before = PageTextMap.bounds(of: start - 2, on: page),
                          abs(head.midY - before.midY) > max(head.height, 4) * 0.7, head.minY > page.bounds(for: .cropBox).maxY * 0.6 else { continue }
                    let text = string.substring(with: match.range(at: 1))
                    let named = ReferenceScanner.mentions(in: text).first { $0.key.kind == .theorem || $0.key.kind == .exercise }?.key
                    proofStarts.append((TextPoint(pageIndex: pageIndex, location: start), named.flatMap(resolve) ?? named, match.range.length))
                }
            }
            for match in endMark.matches(in: text, range: whole) { marks.append(TextPoint(pageIndex: pageIndex, location: match.range.upperBound)) }
        }
        // Proof ends drawn as rules (amsthm's open box) rather than as a glyph.
        let proofPages = Set(proofStarts.flatMap { [$0.point.pageIndex, $0.point.pageIndex + 1, $0.point.pageIndex + 2] })
        for pageIndex in proofPages.sorted() where pageIndex < document.pageCount {
            guard let page = document.page(at: pageIndex) else { continue }
            for box in RuleMarks.endOfProofBoxes(on: page) {
                if let location = characterBefore(box, on: page) { marks.append(TextPoint(pageIndex: pageIndex, location: location + 1)) }
            }
        }
        marks.sort()
        proofStarts.sort { $0.point < $1.point }

        let stops = (heads.map(\.point) + sectionStarts + outlineSections.map(\.point) + proofStarts.map(\.point)).sorted()
        func nextStop(after point: TextPoint) -> TextPoint? { stops.first { $0 > point } }

        // Proofs: from the head to the first end mark, unless a statement, heading or another proof comes first.
        for (index, start) in proofStarts.enumerated() {
            let limit = TextPoint(pageIndex: start.point.pageIndex + 3, location: 0)
            let stop = nextStop(after: start.point).map { min($0, limit) } ?? limit
            let mark = marks.first { $0 > start.point && $0 <= stop }
            var end = mark ?? stop
            if end.pageIndex >= texts.count { end = TextPoint(pageIndex: texts.count - 1, location: (texts.last as NSString?)?.length ?? 0) }
            // The statement proved: named, or the nearest provable statement before the proof (within two pages).
            var statement = start.named
            if statement == nil, let previous = heads.last(where: { $0.point < start.point }),
               start.point.pageIndex - previous.point.pageIndex <= 2,
               previous.target.key.kind == .theorem, provedNames.contains(previous.target.key.name ?? "") {
                statement = previous.target.key
            }
            let (regions, lines) = self.regions(from: start.point, to: end, in: document, texts: texts)
            structure.proofs.append(ProofBlock(id: index, statement: statement, start: start.point, end: end, endsWithMark: mark != nil,
                                               regions: regions, lineCount: lines))
        }

        // Statements: from the label to their proof, or to the next statement or heading.
        var proofByStatement: [ReferenceKey: ProofBlock] = [:]
        for proof in structure.proofs { if let key = proof.statement, proofByStatement[key] == nil { proofByStatement[key] = proof } }
        for head in heads where head.target.key.kind == .theorem {
            var end = nextStop(after: head.point) ?? TextPoint(pageIndex: min(texts.count - 1, head.point.pageIndex + 1), location: 0)
            if let proof = proofByStatement[head.target.key], proof.start > head.point { end = min(end, proof.start) }
            let title = self.title(after: head.target, in: texts)
            structure.statements.append(StatementInfo(key: head.target.key, title: title, start: head.point, end: end,
                                                      proof: proofByStatement[head.target.key]?.id))
        }

        // Uses: each mention belongs to the innermost proof or statement around it, else to its section.
        let sections = (definitions.filter { $0.key.kind == .section && $0.location != nil }
            .map { (key: $0.key, point: TextPoint(pageIndex: $0.pageIndex, location: $0.location!)) } + outlineSections).sorted { $0.point < $1.point }
        var counts: [DependencyEdge: Int] = [:]
        for mention in mentions {
            guard let target = resolve(mention.key) else { continue }
            let point = TextPoint(pageIndex: mention.pageIndex, location: mention.location)
            var from: ReferenceKey?
            var inProof = false
            if let proof = structure.proofs.last(where: { $0.start <= point && point < $0.end }), let key = proof.statement {
                from = key; inProof = true
            } else if let statement = structure.statements.last(where: { $0.start <= point && point < $0.end }) {
                from = statement.key
            } else if let section = sections.last(where: { $0.point <= point }) {
                from = section.key
            }
            guard let from, from != target else { continue }
            counts[DependencyEdge(from: from, to: target, inProof: inProof, count: 0), default: 0] += 1
        }
        structure.edges = counts.map { DependencyEdge(from: $0.key.from, to: $0.key.to, inProof: $0.key.inProof, count: $0.value) }
            .sorted { ($0.from.title, $0.to.title) < ($1.from.title, $1.to.title) }
        return structure
    }

    /// “(Gauss–Markov)” after the label, or a short name ending in a full stop: “Theorem 1.5.1. Jensen’s inequality.”
    static func title(after target: ReferenceTarget, in texts: [String]) -> String? {
        guard texts.indices.contains(target.pageIndex), let location = target.location else { return nil }
        let string = texts[target.pageIndex] as NSString
        let head = ReferenceScanner.mentions(in: string.substring(with: NSRange(location: location, length: min(60, string.length - location)))).first
        let start = location + (head?.range.upperBound ?? 0)
        guard start < string.length else { return nil }
        var rest = string.substring(with: NSRange(location: start, length: min(140, string.length - start)))
        rest = rest.replacingOccurrences(of: "\n", with: " ")
        let trimmed = rest.drop { $0 == " " || $0 == "." || $0 == ":" }
        if trimmed.first == "(", let close = trimmed.firstIndex(of: ")") {
            let inside = trimmed[trimmed.index(after: trimmed.startIndex)..<close].trimmingCharacters(in: .whitespaces)
            // A citation (“(see [3])”) or a formula is not a title.
            if (2...70).contains(inside.count), inside.contains(where: \.isLetter), !inside.contains("["), !inside.hasPrefix("see") { return TextRepair.repaired(inside) }
            return nil
        }
        // “1.5.1. Jensen’s inequality. Suppose…”: a name of at most five words, then a full stop and a new sentence.
        if rest.hasPrefix(". ") || rest.hasPrefix(".") {
            let words = trimmed.split(separator: " ", maxSplits: 7, omittingEmptySubsequences: true)
            for count in 1...min(5, words.count) {
                let candidate = words.prefix(count).joined(separator: " ")
                guard candidate.hasSuffix("."), count < words.count, words[count].first?.isUppercase == true else { continue }
                let name = String(candidate.dropLast())
                let first = name.first
                if first?.isUppercase == true, !["Let", "Suppose", "Assume", "If", "For", "There", "The", "A", "An", "We", "In"].contains(String(name.split(separator: " ").first ?? "")) {
                    return TextRepair.repaired(name)
                }
                return nil
            }
        }
        return nil
    }

    /// One rectangle per page and column covering the text from `start` to `end`, and the number of lines.
    static func regions(from start: TextPoint, to end: TextPoint, in document: PDFDocument, texts: [String]) -> ([PageRect], Int) {
        var result: [PageRect] = []
        var lines = 0
        guard start.pageIndex <= end.pageIndex else { return ([], 0) }
        for pageIndex in start.pageIndex...end.pageIndex {
            guard let page = document.page(at: pageIndex), texts.indices.contains(pageIndex) else { continue }
            let length = (texts[pageIndex] as NSString).length
            let lower = pageIndex == start.pageIndex ? start.location : 0
            let upper = pageIndex == end.pageIndex ? min(end.location, length) : length
            guard upper > lower, let selection = page.selection(for: NSRange(location: lower, length: upper - lower)) else { continue }
            let box = page.bounds(for: .cropBox)
            // Running heads and footers can sit inside the range when a proof turns the page.
            let rects = selection.selectionsByLine().map { $0.bounds(for: page) }
                .filter { !$0.isNull && !$0.isEmpty && LayoutFragment.isSane($0) && $0.minY > box.minY + 36 && $0.maxY < box.maxY - 36 }
            guard !rects.isEmpty else { continue }
            lines += rects.count
            // Columns: rectangles whose horizontal centres sit on either side of a gap.
            let sorted = rects.sorted { $0.midX < $1.midX }
            var groups: [[CGRect]] = []
            var groupMaxX = -CGFloat.infinity
            for rect in sorted {
                if !groups.isEmpty, rect.minX < groupMaxX - 4 {
                    groups[groups.count - 1].append(rect)
                } else {
                    groups.append([rect])
                    groupMaxX = rect.maxX
                }
                groupMaxX = max(groupMaxX, rect.maxX)
            }
            for group in groups {
                let union = group.dropFirst().reduce(group[0]) { $0.union($1) }.insetBy(dx: -3, dy: -1.5)
                result.append(PageRect(pageIndex: pageIndex, region: PageRegion(union)))
            }
        }
        return (result, lines)
    }

    /// The text offset of the last character of the line that a mark ends (amsthm pushes the box to the right margin).
    static func characterBefore(_ box: CGRect, on page: PDFPage) -> Int? {
        let map = PageTextMap(page: page)
        let line = map.lines.filter { line in
            let overlap = min(line.rect.maxY, box.maxY) - max(line.rect.minY, box.minY)
            return overlap > box.height * 0.3 && line.rect.minX < box.minX
        }.max { $0.rect.maxX < $1.rect.maxX }
        return line.map { $0.range.upperBound - 1 }
    }
}

/// End-of-proof squares drawn with rules: amsthm's open box is four thin rules, a black box one filled square.
public enum RuleMarks {
    /// Squares of 4–10 pt at the right of a text line, built from filled rectangles in the page's content stream.
    public static func endOfProofBoxes(on page: PDFPage) -> [CGRect] {
        guard let cgPage = page.pageRef else { return [] }
        let rules = RuleScanContext.rules(on: cgPage)
        guard !rules.isEmpty else { return [] }
        var boxes: [CGRect] = []
        // A filled square.
        for rule in rules where (3.5...10).contains(rule.width) && (3.5...10).contains(rule.height) && abs(rule.width - rule.height) < 2.5 {
            boxes.append(rule)
        }
        // An open square: thin rules whose union is a square.
        let thin = rules.filter { min($0.width, $0.height) <= 1.2 && max($0.width, $0.height) >= 3 && max($0.width, $0.height) <= 10.5 }
        var used = Set<Int>()
        for (index, rule) in thin.enumerated() where !used.contains(index) {
            let near = thin.indices.filter { !used.contains($0) && thin[$0].insetBy(dx: -1.5, dy: -1.5).intersects(rule.insetBy(dx: -10, dy: -10)) }
            let union = near.map { thin[$0] }.reduce(CGRect.null) { $0.union($1) }
            let horizontal = near.filter { thin[$0].width > thin[$0].height }.count, vertical = near.count - horizontal
            if horizontal >= 2, vertical >= 2, (3.5...11).contains(union.width), (3.5...11).contains(union.height), abs(union.width - union.height) < 3 {
                boxes.append(union); used.formUnion(near)
            }
        }
        // A plot's square markers are not proof ends: keep squares at the right end of a line of text.
        let fragments = PageReferenceAnalyzer.fragments(on: page)
        return boxes.filter { box in
            fragments.contains { fragment in
                let overlap = min(fragment.bounds.maxY, box.maxY) - max(fragment.bounds.minY, box.minY)
                return overlap > box.height * 0.3 && fragment.bounds.maxX <= box.minX + 2 && box.minX - fragment.bounds.maxX < 380
            }
        }
    }
}

/// Collects rules from a page's content stream, in page space: filled rectangles (`re` … `f`, as pdfTeX draws
/// rules) and stroked axis-aligned segments (`m` … `l` … `S`, as xdvipdfmx draws them).
final class RuleScanContext {
    private struct State { var ctm = CGAffineTransform.identity; var lineWidth: CGFloat = 1 }
    private var state = State()
    private var stack: [State] = []
    private var pendingRects: [CGRect] = []
    private var segments: [(CGPoint, CGPoint)] = []
    private var current: CGPoint?
    private(set) var rules: [CGRect] = []

    private static func context(_ info: UnsafeMutableRawPointer?) -> RuleScanContext? {
        info.map { Unmanaged<RuleScanContext>.fromOpaque($0).takeUnretainedValue() }
    }

    private static func numbers(_ scanner: CGPDFScannerRef, _ count: Int) -> [CGFloat]? {
        var values = [CGPDFReal](repeating: 0, count: count)
        for i in stride(from: count - 1, through: 0, by: -1) { guard CGPDFScannerPopNumber(scanner, &values[i]) else { return nil } }
        return values
    }

    private func fill() { rules += pendingRects; clearPath() }
    private func stroke() {
        let width = max(state.lineWidth * max(abs(state.ctm.a), abs(state.ctm.d)), 0.2)
        for (a, b) in segments {
            let rect = CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(a.x - b.x), height: abs(a.y - b.y))
            if rect.width < 0.5 || rect.height < 0.5 { rules.append(rect.insetBy(dx: rect.width < 0.5 ? -width / 2 : 0, dy: rect.height < 0.5 ? -width / 2 : 0)) }
        }
        rules += pendingRects
        clearPath()
    }
    private func clearPath() { pendingRects = []; segments = []; current = nil }

    static func rules(on page: CGPDFPage) -> [CGRect] {
        let context = RuleScanContext()
        guard let table = CGPDFOperatorTableCreate() else { return [] }
        CGPDFOperatorTableSetCallback(table, "q") { _, info in
            guard let c = RuleScanContext.context(info) else { return }; c.stack.append(c.state)
        }
        CGPDFOperatorTableSetCallback(table, "Q") { _, info in
            guard let c = RuleScanContext.context(info) else { return }; if let s = c.stack.popLast() { c.state = s }
        }
        CGPDFOperatorTableSetCallback(table, "cm") { scanner, info in
            guard let c = RuleScanContext.context(info), let v = RuleScanContext.numbers(scanner, 6) else { return }
            c.state.ctm = CGAffineTransform(a: v[0], b: v[1], c: v[2], d: v[3], tx: v[4], ty: v[5]).concatenating(c.state.ctm)
        }
        CGPDFOperatorTableSetCallback(table, "w") { scanner, info in
            guard let c = RuleScanContext.context(info), let v = RuleScanContext.numbers(scanner, 1) else { return }
            c.state.lineWidth = v[0]
        }
        CGPDFOperatorTableSetCallback(table, "re") { scanner, info in
            guard let c = RuleScanContext.context(info), let v = RuleScanContext.numbers(scanner, 4) else { return }
            let rect = CGRect(x: v[0], y: v[1], width: v[2], height: v[3]).standardized.applying(c.state.ctm)
            if rect.width.isFinite, rect.height.isFinite, rect.width < 40, rect.height < 40 { c.pendingRects.append(rect) }
        }
        CGPDFOperatorTableSetCallback(table, "m") { scanner, info in
            guard let c = RuleScanContext.context(info), let v = RuleScanContext.numbers(scanner, 2) else { return }
            c.current = CGPoint(x: v[0], y: v[1]).applying(c.state.ctm)
        }
        CGPDFOperatorTableSetCallback(table, "l") { scanner, info in
            guard let c = RuleScanContext.context(info), let v = RuleScanContext.numbers(scanner, 2) else { return }
            let point = CGPoint(x: v[0], y: v[1]).applying(c.state.ctm)
            if let start = c.current, hypot(point.x - start.x, point.y - start.y) < 40 { c.segments.append((start, point)) }
            c.current = point
        }
        for fill in ["f", "F", "f*"] {
            CGPDFOperatorTableSetCallback(table, fill) { _, info in RuleScanContext.context(info)?.fill() }
        }
        for stroke in ["S", "s"] {
            CGPDFOperatorTableSetCallback(table, stroke) { _, info in RuleScanContext.context(info)?.stroke() }
        }
        for other in ["n", "B", "B*", "b", "b*", "W", "W*"] {
            CGPDFOperatorTableSetCallback(table, other) { _, info in RuleScanContext.context(info)?.clearPath() }
        }
        let stream = CGPDFContentStreamCreateWithPage(page)
        let scanner = CGPDFScannerCreate(stream, table, Unmanaged.passUnretained(context).toOpaque())
        CGPDFScannerScan(scanner)
        CGPDFScannerRelease(scanner)
        CGPDFContentStreamRelease(stream)
        CGPDFOperatorTableRelease(table)
        return context.rules
    }
}
