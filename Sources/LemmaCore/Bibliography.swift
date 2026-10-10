import Foundation

/// One work in a document's list of references.
public struct BibliographyEntry: Codable, Equatable, Identifiable, Sendable {
    public var id: Int
    /// The entry as printed, with hyphenation and ligatures repaired.
    public var text: String
    /// Author surnames in order, as printed: ["Hastie", "Tibshirani"].
    public var authors: [String]
    /// "1990" or "1994b".
    public var year: String?
    /// The bracketed or numbered label of numeric styles: "12" for "[12]".
    public var label: String?
    public var pageIndex: Int
    /// The entry's lines on its first page.
    public var region: PageRegion
    public init(id: Int, text: String, authors: [String], year: String?, label: String? = nil, pageIndex: Int, region: PageRegion) {
        self.id = id; self.text = text; self.authors = authors; self.year = year; self.label = label; self.pageIndex = pageIndex; self.region = region
    }

    /// How a citation names this work: "Hastie and Tibshirani (1990)", "Efron et al. (2004)" or "[12]".
    public var shortTitle: String {
        if let label, authors.isEmpty { return "[\(label)]" }
        let names: String
        switch authors.count {
        case 0: names = label.map { "[\($0)]" } ?? "Reference"
        case 1: names = authors[0]
        case 2: names = "\(authors[0]) and \(authors[1])"
        default: names = "\(authors[0]) et al."
        }
        return year.map { "\(names) (\($0))" } ?? names
    }

    /// The title-like part after the authors and year, for search links.
    public var searchQuery: String {
        var text = self.text
        if let range = text.range(of: #"^\[\d+\]\s*"#, options: .regularExpression) { text.removeSubrange(range) }
        if let year, let range = text.range(of: "(\(year))") { text = String(text[range.upperBound...]) }
        let title = text.trimmingCharacters(in: CharacterSet(charactersIn: " .,:")).components(separatedBy: ". ").first ?? text
        return ([authors.first].compactMap { $0 } + [String(title.prefix(160))]).joined(separator: " ")
    }
}

/// Reads a list of references from laid-out lines. Entries start at the column edge (hanging indent),
/// at a numeric label such as “[12]”, or after a gap. Authors and year are read from the start of the entry.
public enum BibliographyParser {
    public static func parse(_ lines: [PageLine], pageBounds: [Int: CGRect]) -> [BibliographyEntry] {
        let pages = Dictionary(grouping: lines, by: \.pageIndex)
        let laidOut = pages.keys.sorted().map { pageIndex in
            let box = pageBounds[pageIndex] ?? pages[pageIndex]!.map(\.bounds).reduce(CGRect.null) { $0.union($1) }.insetBy(dx: -100, dy: -100)
            let body = BookIndexParser.body(pages[pageIndex]!, in: box).filter { !isHeading($0.text) }
            return (pageIndex: pageIndex, columns: BookIndexParser.columns(of: body))
        }
        var ordered = laidOut.flatMap { page in page.columns.map { column in column.sorted { $0.bounds.maxY > $1.bounds.maxY } } }
        // A section may start partway down its first page: drop the text above the “References” heading.
        if let first = laidOut.first, let heading = pages[first.pageIndex]?.first(where: { isHeading($0.text) }) {
            ordered = ordered.map { column in column.filter { $0.pageIndex != first.pageIndex || $0.bounds.maxY <= heading.bounds.minY + 1 } }
        }
        let all = ordered.flatMap { $0 }
        guard !all.isEmpty else { return [] }
        let numbered = all.filter { numericLabel($0.text) != nil }.count
        let numeric = numbered >= max(3, all.count / 8)

        var groups: [[PageLine]] = []
        for column in ordered {
            let edge = column.map(\.bounds.minX).min() ?? 0
            let hanging = column.contains { $0.bounds.minX - edge > 6 && $0.bounds.minX - edge < 40 }
            var previous: PageLine?
            for line in column {
                let atEdge = line.bounds.minX - edge <= 3
                let gap = previous.map { $0.bounds.minY - line.bounds.maxY } ?? .infinity
                let starts: Bool
                if numeric { starts = numericLabel(line.text) != nil }
                else if hanging { starts = atEdge }
                else { starts = gap > line.bounds.height * 0.55 }
                if starts || groups.isEmpty { groups.append([line]) } else { groups[groups.count - 1].append(line) }
                previous = line
            }
        }
        var entries: [BibliographyEntry] = []
        for group in groups {
            let joined = group.dropFirst().reduce(group[0].text) { TextRepair.joinLines($0, $1.text) }
            let text = TextRepair.repaired(joined).split(whereSeparator: \.isWhitespace).joined(separator: " ")
            guard text.count >= 12, text.contains(where: \.isLetter) else { continue }
            let first = group[0].pageIndex
            let region = group.filter { $0.pageIndex == first }.map(\.bounds).reduce(CGRect.null) { $0.union($1) }.insetBy(dx: -3, dy: -1.5)
            let (authors, year) = authorsAndYear(text)
            entries.append(BibliographyEntry(id: entries.count, text: text, authors: authors, year: year, label: numericLabel(group[0].text),
                                             pageIndex: first, region: PageRegion(region)))
        }
        return entries
    }

    static func isHeading(_ text: String) -> Bool {
        var folded = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if let range = folded.range(of: #"^\d+\.?\s+"#, options: .regularExpression) { folded.removeSubrange(range) }
        return ["references", "bibliography", "literature cited", "works cited", "further reading", "literature", "references and notes"].contains(folded)
    }

    /// “[12]”, “12.” or an alphabetic label such as “[CRT06]”, “[ABB+99]” or “[BS]”.
    private static let labelExpression = try! NSRegularExpression(pattern: #"^\s*(?:\[(\d{1,4})\]|(\d{1,4})\.\s|\[(\p{Lu}[\p{L}+\-]{0,9}\d{0,4}[a-z]?)\])"#)
    static func numericLabel(_ text: String) -> String? {
        guard let match = labelExpression.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else { return nil }
        let string = text as NSString
        for group in 1...3 where match.range(at: group).location != NSNotFound { return string.substring(with: match.range(at: group)) }
        return nil
    }

    /// Whether a list label is a number (“12”) rather than an alphabetic key (“CRT06”).
    public static func isNumericLabel(_ label: String) -> Bool { !label.isEmpty && label.allSatisfy(\.isNumber) }

    private static let parenthesizedYear = try! NSRegularExpression(pattern: #"\((1[5-9]\d{2}|20\d{2})([a-z]?)\)"#)
    private static let bareYear = try! NSRegularExpression(pattern: #"(?<![\d.])(1[5-9]\d{2}|20\d{2})([a-z]?)(?![\d])"#)
    private static let initials = try! NSRegularExpression(pattern: #"^(?:\p{Lu}\.(?:\s?-\s?|\s)?)+$"#)

    /// Surnames and year from the start of an entry: “Hastie, T., Tibshirani, R. and Friedman, J. (2009). …”
    /// or “T. Hastie and R. Tibshirani. Title… 1990.”
    public static func authorsAndYear(_ text: String) -> ([String], String?) {
        var body = text
        if let range = body.range(of: #"^\s*(?:\[\d{1,4}\]|\d{1,4}\.|\[\p{Lu}[\p{L}+\-]{0,9}\d{0,4}[a-z]?\])\s*"#, options: .regularExpression) { body.removeSubrange(range) }
        let string = body as NSString
        var authorsPart: String
        var year: String?
        if let match = parenthesizedYear.firstMatch(in: body, range: NSRange(location: 0, length: string.length)), match.range.location < 600 {
            authorsPart = string.substring(to: match.range.location)
            year = string.substring(with: match.range(at: 1)) + string.substring(with: match.range(at: 2))
        } else {
            authorsPart = leadingNames(body)
            if let match = bareYear.firstMatch(in: body, range: NSRange(location: 0, length: string.length)) {
                year = string.substring(with: match.range(at: 1)) + string.substring(with: match.range(at: 2))
            }
        }
        authorsPart = authorsPart.replacingOccurrences(of: #"\((?:eds?\.?|editors?)\)"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: "et al.", with: "")
        let tokens = authorsPart.replacingOccurrences(of: " and ", with: ",").replacingOccurrences(of: "&", with: ",")
            .components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: "."))) }
            .filter { !$0.isEmpty && $0.lowercased() != "and" }
        var authors: [String] = []
        for token in tokens {
            let dotted = token + "."
            if initials.firstMatch(in: dotted, range: NSRange(dotted.startIndex..., in: dotted)) != nil { continue }
            let words = token.split(separator: " ").map(String.init)
            guard let last = words.last, last.contains(where: \.isLetter), last.count >= 2 else { continue }
            // “T. Hastie” names its surname last; “Hastie” or “de Leeuw” is a surname already.
            let name = words.first.map { $0.hasSuffix(".") && $0.count <= 4 } == true ? last : words.filter { !$0.hasSuffix(".") }.joined(separator: " ")
            if !name.isEmpty { authors.append(name) }
            if authors.count >= 12 { break }
        }
        return (authors, year)
    }

    /// The names at the start of an entry whose year comes later: up to the first full stop after a word longer than an initial.
    static func leadingNames(_ text: String) -> String {
        var index = text.startIndex
        var word = ""
        while index < text.endIndex {
            let character = text[index]
            if character == "." && word.count > 2, text.index(after: index) == text.endIndex || text[text.index(after: index)] == " " {
                return String(text[..<index])
            }
            word = character.isLetter ? word + String(character) : ""
            index = text.index(after: index)
        }
        return String(text.prefix(160))
    }
}

/// A citation of a work in the running text: “Hastie and Tibshirani (1990)”, “(Efron et al., 2004)” or “[12]”.
public struct CitationMention: Equatable, Sendable {
    /// UTF-16 range in the scanned page string.
    public var range: NSRange
    public var text: String
    public var authors: [String]
    public var etAl: Bool
    public var year: String?
    public var label: String?
    public init(range: NSRange, text: String, authors: [String] = [], etAl: Bool = false, year: String? = nil, label: String? = nil) {
        self.range = range; self.text = text; self.authors = authors; self.etAl = etAl; self.year = year; self.label = label
    }
}

public enum CitationScanner {
    private static let name = #"(?<![\p{L}\p{N}])(?:(?:[Vv]an|[Vv]on|[Dd]e|[Dd]el|[Dd]ella|[Dd]i|[Dd]a|[Ll]e|[Ll]a|[Dd]u|[Dd]es|[Dd]er|[Tt]er|[Tt]en|d’|d')\s?)*\p{Lu}[\p{L}’'¨´ˆ˜\-]*\p{L}"#
    private static let group = "(\(name))(?:\\s+(?:and|&)\\s+(\(name))|\\s+(et\\s+al\\.?))?"
    private static let year = #"(?:1[5-9]\d{2}|20\d{2})[a-z]?"#
    private static let textual = try! NSRegularExpression(pattern: "\(group)\\s*\\(((?:\(year))(?:\\s*,\\s*\(year))*)(?:[,;][^()]{0,40})?\\)")
    private static let parenthetical = try! NSRegularExpression(pattern: #"\(([^()]{4,400})\)"#)
    private static let inner = try! NSRegularExpression(pattern: "\(group),?\\s+((?:\(year))(?:\\s*,\\s*\(year))*)")
    private static let yearExpression = try! NSRegularExpression(pattern: year)
    /// “[12]”, “[3, 5–7]”, and a numbered citation with a pointer into the work: “[72, Theorem 1.4]”.
    private static let numeric = try! NSRegularExpression(pattern: #"\[(\d{1,3}(?:\s*[,–-]\s*\d{1,3}){0,12})(?:,\s*[^\[\]\d][^\[\]]{0,40})?\]"#)
    /// “[CRT06]”, “[CDS98, CT05]”, “[BS, Theorem 2.3]”: alphabetic keys, matched against the list's own labels.
    private static let alphabetic = try! NSRegularExpression(pattern: #"\[(\p{Lu}[\p{L}+\-]{0,9}\d{0,4}[a-z]?(?:\s*[,;]\s*\p{Lu}[\p{L}+\-]{0,9}\d{0,4}[a-z]?)*)(?:,\s*[^\[\]]{1,40})?\]"#)

    /// Author–year citations, bracketed numeric ones when `numeric` is set (only for numbered reference lists), and
    /// bracketed alphabetic keys that are among `labels`. Words hyphenated across lines (“Fried-⏎man and Hall (2007)”)
    /// are read whole; ranges refer to the original text.
    public static func mentions(in raw: String, numeric includeNumeric: Bool = false, labels: Set<String> = []) -> [CitationMention] {
        let (text, map) = dehyphenated(raw)
        let string = text as NSString
        let whole = NSRange(location: 0, length: string.length)
        var found: [CitationMention] = []
        func original(_ range: NSRange) -> NSRange { NSRange(location: map[range.location], length: map[range.upperBound] - map[range.location]) }
        func names(_ match: NSTextCheckingResult) -> ([String], Bool) {
            var authors = [string.substring(with: match.range(at: 1))]
            if match.range(at: 2).location != NSNotFound { authors.append(string.substring(with: match.range(at: 2))) }
            return (authors.map { TextRepair.repaired($0).split(whereSeparator: \.isWhitespace).joined(separator: " ") }, match.range(at: 3).location != NSNotFound)
        }
        func add(_ range: NSRange, authors: [String], etAl: Bool, year: NSRange) {
            let text = string.substring(with: range).split(whereSeparator: \.isWhitespace).joined(separator: " ")
            found.append(CitationMention(range: original(range), text: text, authors: authors, etAl: etAl, year: string.substring(with: year)))
        }
        for match in textual.matches(in: text, range: whole) {
            let (authors, etAl) = names(match)
            let years = yearExpression.matches(in: text, range: match.range(at: 4)).map(\.range)
            // One year: the whole citation, parenthesis included. Several: the names with the first year, then each year alone.
            for (index, yearRange) in years.enumerated() {
                let range = years.count == 1 ? match.range
                    : index == 0 ? NSRange(location: match.range.location, length: yearRange.upperBound - match.range.location) : yearRange
                add(range, authors: authors, etAl: etAl, year: yearRange)
            }
        }
        let textualRanges = found.map(\.range)
        for match in parenthetical.matches(in: text, range: whole) {
            guard !textualRanges.contains(where: { NSIntersectionRange($0, original(match.range)).length > 0 }) else { continue }
            for item in inner.matches(in: text, range: match.range(at: 1)) {
                let (authors, etAl) = names(item)
                for (index, yearRange) in yearExpression.matches(in: text, range: item.range(at: 4)).map(\.range).enumerated() {
                    add(index == 0 ? NSRange(location: item.range.location, length: yearRange.upperBound - item.range.location) : yearRange,
                        authors: authors, etAl: etAl, year: yearRange)
                }
            }
        }
        if includeNumeric {
            for match in numeric.matches(in: text, range: whole) {
                for label in expand(string.substring(with: match.range(at: 1))) {
                    found.append(CitationMention(range: original(match.range), text: string.substring(with: match.range), label: label))
                }
            }
        }
        if !labels.isEmpty {
            for match in alphabetic.matches(in: text, range: whole) {
                let keys = string.substring(with: match.range(at: 1)).components(separatedBy: CharacterSet(charactersIn: ",;"))
                    .map { $0.trimmingCharacters(in: .whitespaces) }.filter(labels.contains)
                for key in keys {
                    found.append(CitationMention(range: original(match.range), text: string.substring(with: match.range), label: key))
                }
            }
        }
        return found.sorted { $0.range.location < $1.range.location }
    }

    /// Removes a hyphen and line break inside a word, returning the joined text and, for each of its UTF-16 offsets
    /// (plus the end), the offset in the original.
    static func dehyphenated(_ raw: String) -> (String, [Int]) {
        let units = Array(raw.utf16)
        var output: [UInt16] = []
        var map: [Int] = []
        output.reserveCapacity(units.count); map.reserveCapacity(units.count + 1)
        var index = 0
        func isLetter(_ unit: UInt16) -> Bool { Unicode.Scalar(unit).map { CharacterSet.letters.contains($0) } ?? false }
        func isLower(_ unit: UInt16) -> Bool { Unicode.Scalar(unit).map { CharacterSet.lowercaseLetters.contains($0) } ?? false }
        while index < units.count {
            if units[index] == 0x2D, index + 2 < units.count, units[index + 1] == 0x0A, index > 0, isLetter(units[index - 1]), isLower(units[index + 2]) {
                index += 2
                continue
            }
            output.append(units[index]); map.append(index)
            index += 1
        }
        map.append(units.count)
        return (String(decoding: output, as: UTF16.self), map)
    }

    /// “3, 5–7” → ["3", "5", "6", "7"].
    static func expand(_ list: String) -> [String] {
        list.components(separatedBy: ",").flatMap { part -> [String] in
            let bounds = part.components(separatedBy: CharacterSet(charactersIn: "–-")).compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
            if bounds.count == 2, bounds[0] <= bounds[1], bounds[1] - bounds[0] <= 30 { return (bounds[0]...bounds[1]).map(String.init) }
            return bounds.prefix(1).map(String.init)
        }
    }

    /// The reference-list entries a citation names. Surnames and years must agree; “et al.” needs three or more authors
    /// when such an entry exists. Several candidates remain when the list is ambiguous.
    public static func match(_ mention: CitationMention, in entries: [BibliographyEntry]) -> [BibliographyEntry] {
        if let label = mention.label { return entries.filter { $0.label == label } }
        guard let first = mention.authors.first.map(TextRepair.folded), let year = mention.year else { return [] }
        let candidates = entries.filter { entry in
            guard let entryYear = entry.year, entryYear == year || (entryYear.hasPrefix(year) && year.count == 4),
                  let entryFirst = entry.authors.first.map(TextRepair.folded), sameName(entryFirst, first) else { return false }
            if mention.authors.count == 2 { return entry.authors.count >= 2 && sameName(TextRepair.folded(entry.authors[1]), TextRepair.folded(mention.authors[1])) }
            if mention.etAl { return entry.authors.count >= 2 }
            return true
        }
        if mention.etAl, candidates.contains(where: { $0.authors.count >= 3 }) { return candidates.filter { $0.authors.count >= 3 } }
        if mention.authors.count == 1, !mention.etAl, candidates.contains(where: { $0.authors.count == 1 }) { return candidates.filter { $0.authors.count == 1 } }
        return candidates
    }

    /// Surnames agree when equal, or when one adds a particle to the other, as “de Leeuw” and “Leeuw”.
    static func sameName(_ lhs: String, _ rhs: String) -> Bool {
        lhs == rhs || lhs.hasSuffix(" " + rhs) || rhs.hasSuffix(" " + lhs)
    }
}
