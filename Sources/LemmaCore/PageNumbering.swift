import Foundation

/// The page numbers printed on a book's pages. Book indexes, citations and lecture notes use them,
/// while a PDF counts physical pages: ESL's printed page 12 is PDF page 31.
public struct PageNumbering: Codable, Equatable, Sendable {
    public enum Style: String, Codable, Sendable { case arabic, roman }
    public enum Source: String, Codable, Sendable { case runningHeads, pdfLabels }

    /// Consecutive physical pages sharing a style, where printed number = physical number − offset.
    public struct Run: Codable, Equatable, Sendable {
        public var firstPage: Int
        public var lastPage: Int
        public var offset: Int
        public var style: Style
        public init(firstPage: Int, lastPage: Int, offset: Int, style: Style) {
            self.firstPage = firstPage; self.lastPage = lastPage; self.offset = offset; self.style = style
        }
    }

    public var runs: [Run]
    public var source: Source
    /// The PDF's own labels by physical index, when the document provides meaningful ones.
    public var labels: [String]?

    public init(runs: [Run], source: Source = .runningHeads, labels: [String]? = nil) {
        self.runs = runs; self.source = source; self.labels = labels
    }

    /// The printed label of a physical page (0-based), if known: "12", "xiv".
    public func label(for pageIndex: Int) -> String? {
        if let labels { return labels.indices.contains(pageIndex) ? labels[pageIndex] : nil }
        guard let run = runs.first(where: { ($0.firstPage...$0.lastPage).contains(pageIndex) }) else { return nil }
        let value = pageIndex + 1 - run.offset
        guard value >= 1 else { return nil }
        return run.style == .roman ? Self.roman(value) : String(value)
    }

    /// The physical page (0-based) printed with `label`. Arabic labels are preferred over roman ones.
    public func pageIndex(forLabel label: String) -> Int? {
        let trimmed = label.trimmingCharacters(in: .whitespacesAndNewlines)
        if let labels { return labels.firstIndex { $0.compare(trimmed, options: .caseInsensitive) == .orderedSame } }
        if let value = Int(trimmed) {
            return runs.lazy.filter { $0.style == .arabic }.compactMap { run -> Int? in
                let index = value + run.offset - 1
                return (run.firstPage...run.lastPage).contains(index) ? index : nil
            }.first
        }
        if let value = Self.romanValue(trimmed.lowercased()) {
            return runs.lazy.filter { $0.style == .roman }.compactMap { run -> Int? in
                let index = value + run.offset - 1
                return (run.firstPage...run.lastPage).contains(index) ? index : nil
            }.first
        }
        return nil
    }

    /// Whether printed numbers differ from physical ones anywhere: otherwise showing both is noise.
    public var differsFromPhysical: Bool {
        if let labels { return labels.enumerated().contains { $0.element != String($0.offset + 1) } }
        return runs.contains { $0.offset != 0 || $0.style == .roman }
    }

    // MARK: Inference

    /// A number found in a page's running head or footer.
    public struct Candidate: Equatable, Sendable {
        public var pageIndex: Int
        public var value: Int
        public var style: Style
        public init(pageIndex: Int, value: Int, style: Style) { self.pageIndex = pageIndex; self.value = value; self.style = style }
    }

    /// Infers runs from header candidates. Pages without a running head (chapter openings, full-page figures)
    /// take the offset of the run around them; a run needs three agreeing pages.
    public static func infer(from candidates: [Candidate], pageCount: Int) -> PageNumbering? {
        let sorted = candidates.filter { $0.value >= 1 && $0.pageIndex >= 0 && $0.pageIndex < pageCount }.sorted { $0.pageIndex < $1.pageIndex }
        guard !sorted.isEmpty else { return nil }
        // Group consecutive agreeing candidates, ignoring isolated disagreements (a stray number in a heading).
        struct Group { var offset: Int; var style: Style; var pages: [Int] }
        var groups: [Group] = []
        for candidate in sorted {
            let offset = candidate.pageIndex + 1 - candidate.value
            if let last = groups.last, last.offset == offset, last.style == candidate.style {
                groups[groups.count - 1].pages.append(candidate.pageIndex)
            } else {
                groups.append(Group(offset: offset, style: candidate.style, pages: [candidate.pageIndex]))
            }
        }
        var strong = groups.filter { $0.pages.count >= 3 }
        guard !strong.isEmpty else { return nil }
        // Merge strong groups that agree once the noise between them is gone.
        var merged: [Group] = []
        for group in strong {
            if let last = merged.last, last.offset == group.offset, last.style == group.style { merged[merged.count - 1].pages += group.pages }
            else { merged.append(group) }
        }
        strong = merged
        var runs = strong.map { Run(firstPage: $0.pages.first!, lastPage: $0.pages.last!, offset: $0.offset, style: $0.style) }
        // Extend each run backwards over unnumbered pages while its numbers stay positive, then forwards to the next run.
        for index in runs.indices {
            let floor = index == 0 ? 0 : runs[index - 1].lastPage + 1
            var first = runs[index].firstPage
            while first - 1 >= floor, first - runs[index].offset >= 1 { first -= 1 }
            runs[index].firstPage = first
        }
        for index in runs.indices {
            let ceiling = index + 1 < runs.count ? runs[index + 1].firstPage - 1 : pageCount - 1
            runs[index].lastPage = max(runs[index].lastPage, ceiling)
        }
        return PageNumbering(runs: runs)
    }

    /// Reads a page number token at the start or end of a header or footer line: "12", "xiv", "700 References", "Contents vii".
    public static func candidateValue(inLine line: String) -> (value: Int, style: Style)? {
        let tokens = line.split(whereSeparator: \.isWhitespace).map(String.init)
        guard let first = tokens.first, let last = tokens.last else { return nil }
        for token in tokens.count == 1 ? [first] : [first, last] {
            if token.count <= 4, token.allSatisfy(\.isNumber), let value = Int(token), value > 0 { return (value, .arabic) }
            if token.count <= 7, let value = romanValue(token), value <= 200, token == token.lowercased() { return (value, .roman) }
        }
        return nil
    }

    static func roman(_ value: Int) -> String {
        let table: [(Int, String)] = [(1000, "m"), (900, "cm"), (500, "d"), (400, "cd"), (100, "c"), (90, "xc"), (50, "l"), (40, "xl"), (10, "x"), (9, "ix"), (5, "v"), (4, "iv"), (1, "i")]
        var remaining = value, output = ""
        for (amount, symbol) in table { while remaining >= amount { output += symbol; remaining -= amount } }
        return output
    }

    static func romanValue(_ text: String) -> Int? {
        let values: [Character: Int] = ["i": 1, "v": 5, "x": 10, "l": 50, "c": 100, "d": 500, "m": 1000]
        guard !text.isEmpty, text.allSatisfy({ values[$0] != nil }) else { return nil }
        var total = 0, previous = 0
        for character in text.reversed() {
            let value = values[character]!
            total += value < previous ? -value : value
            previous = max(previous, value)
        }
        // Reject non-canonical spellings such as "vix" or words like "mix" and "dim".
        return total > 0 && roman(total) == text ? total : nil
    }
}
