import Foundation

/// One visual line of a page in reading-order analysis, in PDF page coordinates.
public struct PageLine: Equatable, Sendable {
    public var pageIndex: Int
    public var text: String
    public var bounds: CGRect
    public init(pageIndex: Int, text: String, bounds: CGRect) { self.pageIndex = pageIndex; self.text = text; self.bounds = bounds }
}

/// A span of printed pages as an index writes it: "37" or "219–221".
public struct PageSpan: Codable, Equatable, Hashable, Sendable {
    public var first: String
    public var last: String?
    public init(first: String, last: String? = nil) { self.first = first; self.last = last }
    public var text: String { last.map { "\(first)–\($0)" } ?? first }
}

/// An entry of a book's back-of-book index. Subentries name their parent, as in "Boosting › shrinkage".
public struct BookIndexEntry: Codable, Equatable, Identifiable, Sendable {
    public var id: Int
    public var term: String
    public var parent: String?
    public var locators: [PageSpan]
    /// Cross references: “AIC, see Akaike information criterion”.
    public var see: [String]
    /// The physical page on which the index prints this entry.
    public var pageIndex: Int
    public init(id: Int, term: String, parent: String? = nil, locators: [PageSpan] = [], see: [String] = [], pageIndex: Int) {
        self.id = id; self.term = term; self.parent = parent; self.locators = locators; self.see = see; self.pageIndex = pageIndex
    }
    public var title: String { parent.map { "\($0) › \(term)" } ?? term }
}

/// Reads a book's index from laid-out lines. Main entries start at a column's edge, subentries are indented
/// one step and turned-over lines further; page numbers follow the last comma. The parser relies on that
/// geometry because a PDF's text layer drops indentation.
public enum BookIndexParser {
    public static func parse(_ lines: [PageLine], pageBounds: [Int: CGRect]) -> [BookIndexEntry] {
        var entries: [BookIndexEntry] = []
        var current: (text: String, level: Int, pageIndex: Int)?
        var parents: [Int: String] = [:]

        func finish() {
            guard let entry = current else { return }
            current = nil
            guard let parsed = parseEntry(entry.text) else { return }
            let path = (0..<entry.level).compactMap { parents[$0] }
            parents[entry.level] = parsed.term
            for deeper in (entry.level + 1)...3 { parents[deeper] = nil }
            entries.append(BookIndexEntry(id: entries.count, term: parsed.term, parent: path.isEmpty ? nil : path.joined(separator: " › "),
                                          locators: parsed.locators, see: parsed.see, pageIndex: entry.pageIndex))
        }

        let pages = Dictionary(grouping: lines, by: \.pageIndex)
        let laidOut = pages.keys.sorted().map { pageIndex in
            let box = pageBounds[pageIndex] ?? pages[pageIndex]!.map(\.bounds).reduce(CGRect.null) { $0.union($1) }.insetBy(dx: -100, dy: -100)
            return (pageIndex: pageIndex, columns: columns(of: body(pages[pageIndex]!, in: box)))
        }
        // Column edges agree across pages; a column holding only subentries would otherwise lose its first level.
        var edges: [Int: CGFloat] = [:]
        for ordinal in 0..<2 {
            let minima = laidOut.compactMap { $0.columns.indices.contains(ordinal) ? $0.columns[ordinal].map(\.bounds.minX).min() : nil }
            edges[ordinal] = mostCommon(minima)
        }
        func left(_ column: [PageLine], ordinal: Int) -> CGFloat {
            let own = column.map(\.bounds.minX).min() ?? 0
            return min(edges[ordinal] ?? own, own)
        }
        let step = indentStep(laidOut.flatMap { page in
            page.columns.enumerated().flatMap { ordinal, column in column.map { $0.bounds.minX - left(column, ordinal: ordinal) } }
        })
        for page in laidOut {
            for (ordinal, column) in page.columns.enumerated() {
                let edge = left(column, ordinal: ordinal)
                for line in column.sorted(by: { $0.bounds.maxY > $1.bounds.maxY }) {
                    let text = line.text.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !text.isEmpty else { continue }
                    let level = max(0, Int(((line.bounds.minX - edge) / step).rounded()))
                    // A turned-over line sits two steps in: it continues an unfinished entry or one still waiting for its pages.
                    if let open = current, level >= 2, open.level == 0 || isOpen(open.text) || !hasLocators(open.text) || hasCrossReference(open.text) {
                        current?.text = TextRepair.joinLines(open.text, text)
                        continue
                    }
                    finish()
                    current = (text, min(level, 2), line.pageIndex)
                }
            }
        }
        finish()
        return entries
    }

    /// Drops running heads, page numbers and the large “Index” title: lines near the page edges or set larger than the entries.
    static func body(_ lines: [PageLine], in box: CGRect) -> [PageLine] {
        let heights = lines.map(\.bounds.height).sorted()
        let typical = heights.isEmpty ? 10 : heights[heights.count / 2]
        // The topmost and bottommost lines are a running head or footer when they look like one and sit in the margin,
        // set apart from the text block: an index column may well end with a turned-over “591”.
        let ordered = lines.sorted { $0.bounds.maxY > $1.bounds.maxY }
        var margins: [PageLine] = []
        let headZone = max(60, box.height * 0.13), footZone = max(50, box.height * 0.1)
        if ordered.count > 1, let top = ordered.first, top.bounds.minY > box.maxY - headZone,
           top.bounds.minY - ordered[1].bounds.maxY >= top.bounds.height * 0.8, isRunningHead(top.text) { margins.append(top) }
        if ordered.count > 1, let bottom = ordered.last, bottom.bounds.maxY < box.minY + footZone,
           ordered[ordered.count - 2].bounds.minY - bottom.bounds.maxY >= bottom.bounds.height * 1.2, isRunningHead(bottom.text) { margins.append(bottom) }
        return lines.filter { line in
            line.bounds.height <= typical * 1.45 && line.bounds.minY > box.minY + 30 && line.bounds.maxY < box.maxY - 18
                && !margins.contains(line) && !(line.bounds.minY > box.maxY - headZone && isRunningHead(line.text))
        }
    }

    /// “738 Index”, “Index 739” or a bare page number; never an entry such as “AdaBoost, 337”, whose number follows a comma.
    static func isRunningHead(_ text: String) -> Bool {
        let tokens = text.split(whereSeparator: \.isWhitespace).map(String.init)
        guard let first = tokens.first, let last = tokens.last else { return false }
        func isNumber(_ token: String) -> Bool { PageNumbering.candidateValue(inLine: token) != nil }
        if tokens.count == 1 { return isNumber(first) }
        if isNumber(first), !isNumber(last), !last.hasSuffix(",") { return true }
        return isNumber(last) && !tokens[tokens.count - 2].hasSuffix(",") && !tokens[tokens.count - 2].hasSuffix("–")
    }

    /// Splits a page into columns at an empty vertical gutter.
    static func columns(of lines: [PageLine]) -> [[PageLine]] {
        guard let minX = lines.map(\.bounds.minX).min(), let maxX = lines.map(\.bounds.maxX).max(), maxX - minX > 40 else { return lines.isEmpty ? [] : [lines] }
        var free: [CGFloat] = []
        for x in stride(from: minX + (maxX - minX) * 0.3, through: minX + (maxX - minX) * 0.7, by: 1) {
            if !lines.contains(where: { $0.bounds.minX < x - 1 && $0.bounds.maxX > x + 1 }),
               lines.contains(where: { $0.bounds.maxX <= x }), lines.contains(where: { $0.bounds.minX >= x }) { free.append(x) }
        }
        guard let first = free.first, let last = free.last else { return [lines] }
        let gutter = (first + last) / 2
        return [lines.filter { $0.bounds.midX < gutter }, lines.filter { $0.bounds.midX >= gutter }].filter { !$0.isEmpty }
    }

    /// The most frequent value, to the nearest point; the smallest of equally frequent ones.
    static func mostCommon(_ values: [CGFloat]) -> CGFloat? {
        let buckets = Dictionary(grouping: values) { Int($0.rounded()) }
        return buckets.max { $0.value.count == $1.value.count ? $0.key > $1.key : $0.value.count < $1.value.count }?.value.min()
    }

    /// The indentation unit: the smallest clearly positive offset, typically two ems.
    static func indentStep(_ offsets: [CGFloat]) -> CGFloat {
        let positive = offsets.filter { $0 > 4 }
        let buckets = Dictionary(grouping: positive) { Int(($0 / 2).rounded()) }
        let minimum = max(3, positive.count / 30)
        guard let key = buckets.filter({ $0.value.count >= minimum }).keys.min(), let values = buckets[key] else { return 20 }
        return max(8, values.reduce(0, +) / CGFloat(values.count))
    }

    /// A line that cannot end an entry: a hyphenated or dash-split word, or a list still waiting for its pages.
    static func isOpen(_ text: String) -> Bool {
        guard let last = text.trimmingCharacters(in: .whitespaces).last else { return false }
        return last == "-" || last == "–" || last == "," || last == "/"
    }

    /// “ICA, see Independent component” may turn over its target onto the next line.
    static func hasCrossReference(_ text: String) -> Bool {
        text.range(of: #",\s*see\s"#, options: [.regularExpression, .caseInsensitive]) != nil
    }

    static func hasLocators(_ text: String) -> Bool {
        guard let parsed = parseEntry(text) else { return false }
        return !parsed.locators.isEmpty || !parsed.see.isEmpty
    }

    private static let locator = try! NSRegularExpression(pattern: "^((?:[0-9]{1,4}|[ivxlcdm]{1,7}))(?:[nf]|ff)?(?:\\s*[–\u{2014}-]\\s*((?:[0-9]{1,4}|[ivxlcdm]{1,7})))?(?:[nf]|ff)?$")

    /// Splits “Bias-variance tradeoff, 37, 219–221” into its term and page spans, and “AIC, see Akaike…” into a cross reference.
    public static func parseEntry(_ raw: String) -> (term: String, locators: [PageSpan], see: [String])? {
        let text = TextRepair.repaired(raw).split(whereSeparator: \.isWhitespace).joined(separator: " ")
        var parts = text.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        var see: [String] = []
        if let seeIndex = parts.firstIndex(where: { $0.lowercased().hasPrefix("see ") || $0.lowercased() == "see" }) {
            let target = parts[seeIndex...].joined(separator: ", ")
            let cleaned = target.replacingOccurrences(of: "^see\\s+(also\\s+)?", with: "", options: [.regularExpression, .caseInsensitive])
            see = cleaned.components(separatedBy: ";").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            parts.removeSubrange(seeIndex...)
        }
        var locators: [PageSpan] = []
        while let last = parts.last, parts.count > 1 || last.first?.isNumber == true,
              let match = locator.firstMatch(in: last, range: NSRange(last.startIndex..., in: last)) {
            let string = last as NSString
            let first = string.substring(with: match.range(at: 1))
            let end = match.range(at: 2).location == NSNotFound ? nil : string.substring(with: match.range(at: 2))
            locators.insert(PageSpan(first: first, last: end), at: 0)
            parts.removeLast()
        }
        let term = parts.joined(separator: ", ").trimmingCharacters(in: CharacterSet(charactersIn: " ,"))
            .replacingOccurrences(of: " ,", with: ",")
        guard !term.isEmpty, term.contains(where: \.isLetter) else { return nil }
        return (term, locators, see)
    }
}

/// Finds index entries for a term or phrase. Matching is literal after folding case, accents, ligatures and hyphens.
public enum BookIndexSearch {
    public struct Match: Equatable, Sendable {
        public var entry: BookIndexEntry
        public var rank: Int
    }

    /// Folds every entry for this one search; for searches as the reader types, fold once (`PreparedBookIndex`).
    public static func find(_ query: String, in entries: [BookIndexEntry], limit: Int = 60) -> [Match] {
        find(query, in: PreparedBookIndex(entries), limit: limit)
    }

    static func containsWord(_ word: String, in text: String) -> Bool {
        guard let range = text.range(of: word) else { return false }
        var search = range
        while true {
            let before = search.lowerBound == text.startIndex ? nil : text[text.index(before: search.lowerBound)]
            let after = search.upperBound == text.endIndex ? nil : text[search.upperBound]
            if !(before?.isLetter ?? false) && !(after?.isLetter ?? false) || after == "s" && !(text.index(after: search.upperBound) < text.endIndex && text[text.index(after: search.upperBound)].isLetter) && !(before?.isLetter ?? false) { return true }
            guard let next = text.range(of: word, range: search.upperBound..<text.endIndex) else { return false }
            search = next
        }
    }

    static func singularForm(_ text: String) -> String {
        guard text.count > 3, text.hasSuffix("s"), !text.hasSuffix("ss") else { return text }
        return String(text.dropLast())
    }
}
