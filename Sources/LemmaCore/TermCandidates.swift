//
//  TermCandidates.swift · "Go to Definition" for words
//
//  Turns a page's emphasis runs (EmphasisExtractor) into plausible *defined-term*
//  candidates: short italic/bold phrases in running prose, with a context
//  snippet and a flag telling whether a definition cue ("called", "known as",
//  "we define", …) precedes or follows them.
//
//  Pure function of (runs, page.string); no PDFKit calls.
//

import Foundation

public struct TermCandidate: Equatable, Sendable {
    /// Lower-cased term (acronyms and inner-capital words such as "AdaBoost"
    /// keep their case), leading article removed, line-end hyphenation joined.
    public var term: String
    /// The candidate's words as they read on the page (same normalisation, original case).
    public var surface: String
    /// Range of `surface` in `page.string` (trimmed of punctuation and a leading article).
    public var range: NSRange
    public var style: EmphasisRun.Style
    /// About 80 characters before / after the term, cut at sentence boundaries when possible.
    public var contextBefore: String
    public var contextAfter: String
    /// A definition cue precedes (within ~40 characters) or immediately follows the term.
    public var definitional: Bool

    public var context: String { contextBefore + surface + contextAfter }

    public init(term: String, surface: String, range: NSRange, style: EmphasisRun.Style,
                contextBefore: String, contextAfter: String, definitional: Bool) {
        self.term = term
        self.surface = surface
        self.range = range
        self.style = style
        self.contextBefore = contextBefore
        self.contextAfter = contextAfter
        self.definitional = definitional
    }
}

public enum TermCandidates {
    /// Candidates for one page, sorted by position.
    /// - Parameters:
    ///   - runs: `EmphasisExtractor.runs(on: page)`.
    ///   - pageText: `page.string` (the string the run ranges refer to).
    public static func candidates(runs: [EmphasisRun], pageText: String) -> [TermCandidate] {
        let text = pageText as NSString
        guard text.length > 0 else { return [] }
        let layout = PageLines(text, runs: runs)
        if layout.isReferenceList(text) || layout.isIndex(text) { return [] }
        let hyphenated = EmphasisText.hyphenatedWords(in: pageText)
        let labelled = labelledDefinitions(in: text, hyphenated: hyphenated)
        var result = labelled
        for run in runs {
            if case .success(let candidate) = evaluate(run, text: text, layout: layout, hyphenated: hyphenated) {
                if !labelled.contains(where: { NSIntersectionRange($0.range, candidate.range).length > 0 }) { result.append(candidate) }
            }
        }
        return result.sorted { $0.range.location < $1.range.location }
    }

    /// Why a run was not kept (diagnostics).
    enum Rejection: String, Error, CaseIterable {
        case referencePage, size, empty, stoplist, wordCount, listOrTitle, boldCapitals, numberedLabel,
             functionWordEdge, adverb, formula, exerciseTitle, letters, heading, caption, sectionReference,
             sentence, statementBody
    }

    /// Per-run verdicts for a page, in run order (diagnostics; same rules as `candidates`).
    static func verdicts(runs: [EmphasisRun], pageText: String) -> [Result<TermCandidate, Rejection>] {
        let text = pageText as NSString
        let layout = PageLines(text, runs: runs)
        if layout.isReferenceList(text) || layout.isIndex(text) { return runs.map { _ in .failure(.referencePage) } }
        let hyphenated = EmphasisText.hyphenatedWords(in: pageText)
        return runs.map { evaluate($0, text: text, layout: layout, hyphenated: hyphenated) }
    }

    // MARK: - Tunables

    static let maxWords = 5
    static let minLetters = 3
    static let contextLength = 80
    static let cueWindow = 40
    /// Runs whose size differs from the body text by more than this are headings,
    /// captions, footnotes or figure labels.
    static let sizeTolerance = 0.06

    static let precedingCues = [
        "called", "known as", "termed", "referred to as", "refer to as", "we call", "define", "defined", "defines", "denote",
        "is said to be", "are said to be", "so-called", "so called", "dubbed", "the term", "named",
        "on appelle", "appelé", "appelée", "appelés", "appelées", "on nomme", "nommé", "nommée", "on parle de",
        "est dit", "est dite", "sont dits", "sont dites", "désigne", "désignent", "définit", "défini", "définie",
    ]
    static let followingCues = [
        "is defined", "are defined", "is called", "are called", "is known as", "are known as", "is termed",
        "refers to", "is said to be", "denotes", "is the name",
        "est défini", "est définie", "sont définis", "sont définies", "est appelé", "est appelée", "désigne", "se définit",
    ]

    static let stopwords: Set<String> = [
        "a", "an", "the", "not", "all", "none", "and", "or", "nor", "but", "if", "then", "else", "so", "than",
        "no", "never", "only", "any", "each", "every", "both", "either", "neither", "some", "many", "much",
        "more", "most", "less", "least", "few", "very", "also", "even", "just", "same", "is", "are", "was",
        "were", "be", "been", "being", "has", "have", "had", "do", "does", "did", "can", "cannot", "may",
        "might", "must", "will", "would", "should", "could", "shall", "this", "that", "these", "those", "it",
        "its", "we", "you", "they", "he", "she", "one", "two", "three", "of", "in", "on", "at", "to", "for",
        "by", "with", "from", "as", "into", "over", "under", "between", "within", "without", "about", "after",
        "before", "always", "often", "rarely", "exactly", "precisely", "itself", "independently", "not",
        "e.g.", "i.e.", "e.g", "i.e", "eg", "ie", "etc", "etc.", "cf", "cf.", "viz", "viz.", "vs", "vs.",
        "figure", "table", "section", "chapter", "page", "note", "example", "exercise", "see", "also",
        "left", "right", "top", "bottom", "panel", "upper", "lower", "middle", "above", "below", "hint",
        "hints", "proof", "solution", "remark", "note", "answer",
        "le", "la", "les", "un", "une", "des", "du", "de", "et", "ou", "ce", "ces", "est", "sont", "soit", "si", "alors",
    ]
    /// Function words that cannot start or end a multi-word term.
    static let functionWords: Set<String> = [
        "a", "an", "the", "of", "in", "on", "at", "to", "for", "by", "with", "from", "as", "into", "onto", "over",
        "under", "between", "within", "without", "about", "after", "before", "and", "or", "nor", "but", "if",
        "then", "else", "so", "than", "is", "are", "was", "were", "be", "been", "being", "has", "have", "had",
        "do", "does", "did", "can", "cannot", "may", "might", "must", "will", "would", "should", "could", "shall",
        "this", "that", "these", "those", "it", "its", "we", "you", "they", "he", "she", "not", "no", "any",
        "each", "every", "such", "which", "who", "whom", "whose", "what", "where", "when", "how", "there",
        "here", "also", "only", "very",
        "le", "la", "les", "un", "une", "des", "du", "de", "et", "ou", "ce", "ces", "est", "sont", "si", "alors", "pour",
    ]
    /// Words that open a mathematical statement or instruction, never a term: theorem statements are set in
    /// italic, and the math between their words splits them into short runs (“Assume that the function”, “Let x”).
    static let clauseStarters: Set<String> = [
        "let", "suppose", "assume", "if", "then", "for", "there", "every", "consider", "fix", "given", "define", "show",
        "prove", "recall", "note", "hence", "thus", "since", "when", "where", "while", "then", "moreover", "furthermore",
        "soit", "soient", "supposons", "considérons", "montrer", "montrons", "si", "alors", "tout", "toute",
    ]
    /// “Theorem 4.1.”, “Lemma 3 (Hoeffding).”, “Proposition 2.3:” just before a run: the run is the statement's italic body.
    static let statementHead = try! NSRegularExpression(
        pattern: #"(?i:theorem|lemma|proposition|corollary|claim|conjecture|assumption|hypothesis|fact)\s*[\d.]*\s*(?:\([^()]{0,60}\))?\s*[.:]\s*$"#)

    /// A run followed by one of these words names a part of the book ("the *Computational
    /// Considerations* section"), not a term.
    static let sectionWords: Set<String> = ["section", "sections", "chapter", "chapters", "appendix", "part"]
    /// Single words ending in "-ly" are almost always emphasised adverbs ("*relatively* far").
    static let lyNouns: Set<String> = ["anomaly", "family", "assembly", "monopoly", "oligopoly", "supply", "butterfly"]
    /// A run right next to one of these is part of a formula ("Ŷ = HYS").
    static let mathNeighbours = Set("=+<>≤≥∈∉⊂⊆∑∏∫^_|∼≈→←↦×·∗")
    static let exerciseLabel = try! NSRegularExpression(
        pattern: #"(?:Ex\.|Exercise|EXERCISE|Problem|PROBLEM)\s*\d+(?:\.\d+)*\s*$"#)
    /// "Definition 2.3 (*kernel*)", "Algorithm 3.2 *Least Angle Regression*": the emphasised
    /// words name what the labelled block defines.
    static let definitionLabel = try! NSRegularExpression(
        pattern: #"(?:Definition|DEFINITION|Def\.|Algorithm|ALGORITHM)\s*\d+(?:\.\d+)*\s*[(\[]?\s*$"#)

    static let phraseStoplist: Set<String> = [
        "et al", "et al.", "e.g.", "i.e.", "a priori", "a posteriori", "ad hoc", "per se", "de facto",
        "vice versa", "in situ", "status quo", "a fortiori", "inter alia", "mutatis mutandis",
        "ceteris paribus", "bona fide", "en masse", "et cetera", "and so on", "left panel", "right panel",
    ]

    // MARK: - Implementation

    /// Explicitly titled definition blocks also work without emphasis, including French course handouts.
    private static let labelledDefinition = try! NSRegularExpression(pattern:
        #"(?im)^[ \t]*(?:d[ée]finition|def\.)[ \t]+\d+(?:\.\d+)*[ \t]*(?:[–\u2014:][ \t]*([^\n.!?;]{3,120})[.!?]|\(([^()\n]{3,120})\))"#)

    private static func labelledDefinitions(in text: NSString, hyphenated: Set<String>) -> [TermCandidate] {
        labelledDefinition.matches(in: text as String, range: NSRange(location: 0, length: text.length)).compactMap { match in
            let title = match.range(at: match.range(at: 1).location == NSNotFound ? 2 : 1)
            guard let range = trimmed(title, in: text) else { return nil }
            let surface = normalise(text.substring(with: range), hyphenated: hyphenated)
            let words = surface.split(separator: " ")
            guard !words.isEmpty, words.count <= 12, surface.filter(\.isLetter).count >= minLetters,
                  !surface.contains(where: { "=<>∈∑∫".contains($0) }) else { return nil }
            let (before, after, _) = contexts(around: range, in: text, hyphenated: hyphenated)
            return TermCandidate(term: words.map { fold(String($0)) }.joined(separator: " "), surface: surface, range: range,
                                 style: .bold, contextBefore: before, contextAfter: after, definitional: true)
        }
    }

    private static func evaluate(_ run: EmphasisRun, text: NSString, layout: PageLines,
                                 hyphenated: Set<String>) -> Result<TermCandidate, Rejection> {
        if abs(run.relativeSize - 1) > sizeTolerance { return .failure(.size) }
        guard run.range.location != NSNotFound, NSMaxRange(run.range) <= text.length,
              var range = trimmed(run.range, in: text) else { return .failure(.empty) }

        // Whole-phrase stoplist ("e.g.", "et al.") before punctuation is stripped.
        let rawSurface = normalise(text.substring(with: run.range), hyphenated: hyphenated).trimmingCharacters(in: .whitespaces)
        let rawLower = rawSurface.lowercased()
        if phraseStoplist.contains(rawLower) || stopwords.contains(rawLower) { return .failure(.stoplist) }

        // "Learning Vector Quantization-LVQ": keep the part before an em dash.
        let dash = text.range(of: "\u{2014}", options: [], range: range)
        if dash.location != NSNotFound, dash.location > range.location,
           let cut = trimmed(NSRange(location: range.location, length: dash.location - range.location), in: text) {
            range = cut
        }
        var surface = normalise(text.substring(with: range), hyphenated: hyphenated)
        if phraseStoplist.contains(surface.lowercased()) { return .failure(.stoplist) }

        // Drop a leading article: "the lasso" -> "lasso".
        for article in ["the", "a", "an", "le", "la", "les", "un", "une", "des"] {
            let words = surface.split(separator: " ")
            guard words.count > 1, words[0].lowercased() == article else { continue }
            var cursor = range.location + (article as NSString).length
            while cursor < NSMaxRange(range), isSpace(text.character(at: cursor)) { cursor += 1 }
            range = NSRange(location: cursor, length: NSMaxRange(range) - cursor)
            surface = normalise(text.substring(with: range), hyphenated: hyphenated)
            break
        }

        let words = surface.split(separator: " ").map(String.init)
        guard (1...maxWords).contains(words.count) else { return .failure(.wordCount) }
        // Lists ("homemaker, student, unemployed"), titles with colons, etc.
        if surface.contains(where: { ",;:".contains($0) }) { return .failure(.listOrTitle) }
        // A run crossing a sentence end (“distribution. Proof”) joins two italic passages.
        if surface.range(of: #"\p{L}{3,}\.\s"#, options: .regularExpression) != nil { return .failure(.sentence) }
        if words.count > 1 || run.range.length > 12, clauseStarters.contains(words.first!.lowercased()) { return .failure(.statementBody) }
        let lead = text.substring(with: NSRange(location: max(0, range.location - 80), length: min(80, range.location)))
        if statementHead.firstMatch(in: lead, range: NSRange(location: 0, length: (lead as NSString).length)) != nil, words.count > 2 {
            return .failure(.statementBody)
        }
        // Bold capitals are matrices in formulas ("HYS"), not terms.
        if run.style == .bold && !surface.contains(where: { $0.isLowercase }) { return .failure(.boldCapitals) }
        if words.count > 1, words.last!.allSatisfy(\.isNumber) { return .failure(.numberedLabel) }  // "Item set 1"
        // Phrases starting or ending with a function word: "to transmit a random variable",
        // "effective degrees of" (the rest of the term is on the next page).
        if words.count > 1, functionWords.contains(words.first!.lowercased()) || functionWords.contains(words.last!.lowercased()) {
            return .failure(.functionWordEdge)
        }
        if words.count == 1, surface.count >= 6, surface.lowercased().hasSuffix("ly"),
           !lyNouns.contains(surface.lowercased()) { return .failure(.adverb) }
        if isNextToMath(range, in: text) { return .failure(.formula) }
        if isExerciseTitle(range, in: text) { return .failure(.exerciseTitle) }
        var letters = 0, digits = 0, wordish = 0, other = 0
        for scalar in surface.unicodeScalars where scalar != " " {
            if scalar.properties.isAlphabetic { letters += 1; wordish += 1 }
            else if ("0"..."9").contains(scalar) { digits += 1 }
            else if "-'\u{2019}\u{2010}".unicodeScalars.contains(scalar) { wordish += 1 }
            else { other += 1 }
        }
        let nonSpace = wordish + digits + other
        guard letters >= minLetters, digits <= 2, Double(wordish) >= 0.85 * Double(max(nonSpace, 1)) else {
            return .failure(.letters)
        }
        if words.allSatisfy({ stopwords.contains($0.lowercased()) }) { return .failure(.stoplist) }

        // Headings, running heads and captions (text-based; the size test above
        // already removes them in books where they use another font size).
        if layout.isHeading(range, in: text) { return .failure(.heading) }
        if layout.isCaption(range, in: text) { return .failure(.caption) }

        let term = words.map(fold).joined(separator: " ")
        let (before, after, cueBefore) = contexts(around: range, in: text, hyphenated: hyphenated)
        if let next = after.split(separator: " ").first, sectionWords.contains(next.lowercased()) {
            return .failure(.sectionReference)
        }
        let afterLower = after.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: " ,;:)"))
        let labelWindow = String(cueBefore.suffix(30))
        let definitionLabelled = definitionLabel.firstMatch(in: labelWindow,
                                                           range: NSRange(location: 0, length: (labelWindow as NSString).length)) != nil
        let definitional = definitionLabelled || hasPrecedingCue(cueBefore) || followingCues.contains { afterLower.hasPrefix($0) }
        return .success(TermCandidate(term: term, surface: surface, range: range, style: run.style,
                                      contextBefore: before, contextAfter: after, definitional: definitional))
    }

    /// Lower-cases ordinary words; keeps acronyms and words with inner capitals.
    static func fold(_ word: String) -> String {
        let scalars = Array(word.unicodeScalars)
        let innerCapital = scalars.dropFirst().contains { $0.properties.isUppercase }
        return innerCapital ? word : word.lowercased()
    }

    /// Strips leading/trailing whitespace and punctuation (keeping a closing ")" that
    /// balances an opening one inside the range).
    private static func trimmed(_ range: NSRange, in text: NSString) -> NSRange? {
        var lo = range.location, hi = NSMaxRange(range)
        func isWordChar(_ c: unichar) -> Bool {
            guard let s = Unicode.Scalar(c) else { return true }        // surrogate halves: keep
            return s.properties.isAlphabetic || ("0"..."9").contains(s)
        }
        while lo < hi, !isWordChar(text.character(at: lo)) { lo += 1 }
        while hi > lo, !isWordChar(text.character(at: hi - 1)) {
            if text.character(at: hi - 1) == 0x29,                       // ")"
               text.substring(with: NSRange(location: lo, length: hi - lo)).contains("(") { break }
            hi -= 1
        }
        return hi > lo ? NSRange(location: lo, length: hi - lo) : nil
    }

    /// Ligatures expanded, line-end hyphenation joined (unless `hyphenated` says the
    /// compound is written with a hyphen), whitespace collapsed, TeX accents composed.
    static func normalise(_ s: String, hyphenated: Set<String> = []) -> String {
        var out = String.UnicodeScalarView()
        var pendingSpace = false
        let scalars = Array(s.unicodeScalars)
        var i = 0
        while i < scalars.count {
            let c = scalars[i]
            // "regu-\nlarization" -> "regularization", but "degrees-\nof-freedom" keeps its hyphen.
            if (c == "-" || c == "\u{2010}" || c == "\u{AD}"), i + 1 < scalars.count, scalars[i + 1] == "\n" {
                var k = i + 2
                var after = String.UnicodeScalarView()
                while k < scalars.count, !scalars[k].properties.isWhitespace { after.append(scalars[k]); k += 1 }
                var before = String.UnicodeScalarView()
                for scalar in out.reversed() {
                    if scalar.properties.isWhitespace { break }
                    before.insert(scalar, at: before.startIndex)
                }
                before.append("-")
                if c == "\u{AD}" || EmphasisText.dropsLineBreakHyphen(before: Substring(String(before)), after: Substring(String(after)),
                                                                      hyphenated: hyphenated) {
                    i += 2
                } else {
                    out.append("-")
                    i += 2
                }
                pendingSpace = false
                continue
            }
            if c.properties.isWhitespace {
                pendingSpace = !out.isEmpty
                i += 1
                continue
            }
            // Spacing accents: TeX's "Fr´echet" becomes "Fréchet"; accents that PDFKit
            // interleaves from formulas ("ˆ", "˜" between words) are dropped.
            if let mark = Self.combiningMarks[c.value] {
                if i + 1 < scalars.count, scalars[i + 1].properties.isAlphabetic {
                    if pendingSpace { out.append(" "); pendingSpace = false }
                    out.append(scalars[i + 1])
                    out.append(mark)
                    i += 2
                    continue
                }
                if i + 1 >= scalars.count || scalars[i + 1].properties.isWhitespace,
                   out.isEmpty || pendingSpace || out.last!.properties.isWhitespace {
                    i += 1
                    continue
                }
            }
            if pendingSpace { out.append(" "); pendingSpace = false }
            switch c.value {
            case 0xFB00: out.append(contentsOf: "ff".unicodeScalars)
            case 0xFB01: out.append(contentsOf: "fi".unicodeScalars)
            case 0xFB02: out.append(contentsOf: "fl".unicodeScalars)
            case 0xFB03: out.append(contentsOf: "ffi".unicodeScalars)
            case 0xFB04: out.append(contentsOf: "ffl".unicodeScalars)
            case 0xFB05, 0xFB06: out.append(contentsOf: "st".unicodeScalars)
            default: out.append(c)
            }
            i += 1
        }
        return String(out).precomposedStringWithCanonicalMapping
    }

    private static let combiningMarks: [UInt32: Unicode.Scalar] = [
        0x2CB: "\u{300}", 0xB4: "\u{301}", 0x2C6: "\u{302}", 0x2DC: "\u{303}",
        0xAF: "\u{304}", 0x2D8: "\u{306}", 0x2D9: "\u{307}", 0xA8: "\u{308}", 0x2DA: "\u{30A}", 0x2DD: "\u{30B}",
        0x2C7: "\u{30C}", 0xB8: "\u{327}",
    ]

    private static func isNextToMath(_ range: NSRange, in text: NSString) -> Bool {
        var i = range.location - 1
        while i >= 0, isSpace(text.character(at: i)) { i -= 1 }
        if i >= 0, let s = Unicode.Scalar(text.character(at: i)), mathNeighbours.contains(Character(s)) { return true }
        var j = NSMaxRange(range)
        while j < text.length, isSpace(text.character(at: j)) { j += 1 }
        if j < text.length, let s = Unicode.Scalar(text.character(at: j)), mathNeighbours.contains(Character(s)) { return true }
        return false
    }

    /// "Ex. 14.11 *Classical multidimensional scaling*." · a run-in exercise title.
    private static func isExerciseTitle(_ range: NSRange, in text: NSString) -> Bool {
        let start = max(0, range.location - 24)
        let before = normalise(text.substring(with: NSRange(location: start, length: range.location - start)))
        return exerciseLabel.firstMatch(in: before, range: NSRange(location: 0, length: (before as NSString).length)) != nil
    }

    private static func isSpace(_ c: unichar) -> Bool {
        c == 0x20 || c == 0x0A || c == 0x0D || c == 0x09 || c == 0xA0
    }

    /// A cue ("called", "known as", "define"…) in `window` (the text just before the
    /// term) that is separated only by articles or connectors, with no sentence end or
    /// parenthesis in between: "is called the X", "referred to as categorical or X".
    static func hasPrecedingCue(_ window: String) -> Bool {
        let lower = window.lowercased()
        // A publication's title is a name, even when introduced by "a magazine called".
        if lower.range(of: #"(?:book|novel|magazine|newspaper|journal|film|movie|production|album|song|publication|livre|roman|revue|journal)\s+(?:(?:is|was|a|an|the|intitulé|intitulée)\s+)*(?:called|named|dubbed|known as|appelé|appelée|nommé|nommée)\s+(?:the\s+)?$"#,
                       options: .regularExpression) != nil { return false }
        if lower.range(of: #"\bdistribution of\b[^.!?]*\b(?:called|named)\s+(?:the\s+)?$"#,
                       options: .regularExpression) != nil { return false }
        var cueEnd: String.Index?
        for cue in precedingCues {
            var searchRange = lower.startIndex..<lower.endIndex
            while let r = lower.range(of: cue, range: searchRange) {
                if r.lowerBound == lower.startIndex || !lower[lower.index(before: r.lowerBound)].isLetter {
                    let end = r.upperBound
                    if end < lower.endIndex, lower[end].isLetter { searchRange = end..<lower.endIndex; continue }
                    if cueEnd == nil || end > cueEnd! { cueEnd = end }
                }
                searchRange = r.upperBound..<lower.endIndex
            }
        }
        guard let cueEnd else { return false }
        let gap = lower[cueEnd...]
        if gap.contains(where: { "().;!?[]".contains($0) }) { return false }
        let words = gap.split(whereSeparator: { $0.isWhitespace || ",:'’".contains($0) })
        let connectors: Set<Substring> = ["the", "a", "an", "this", "these", "that", "such", "as", "or", "and",
                                        "le", "la", "les", "un", "une", "des", "du", "de", "l", "d", "ce", "cette", "ces", "ou"]
        return words.count <= 4 && words.allSatisfy { connectors.contains($0) }
    }

    /// (before, after, cueWindowText)
    private static func contexts(around range: NSRange, in text: NSString,
                                 hyphenated: Set<String>) -> (String, String, String) {
        let beforeStart = max(0, range.location - contextLength - 20)
        var before = normalise(text.substring(with: NSRange(location: beforeStart, length: range.location - beforeStart)),
                               hyphenated: hyphenated)
        let afterEnd = min(text.length, NSMaxRange(range) + contextLength + 20)
        var after = normalise(text.substring(with: NSRange(location: NSMaxRange(range), length: afterEnd - NSMaxRange(range))),
                              hyphenated: hyphenated)
        // Keep the separating spaces that normalise() drops at the edges.
        if range.location > 0, isSpace(text.character(at: range.location - 1)), !before.isEmpty { before += " " }
        if NSMaxRange(range) < text.length, isSpace(text.character(at: NSMaxRange(range))), !after.isEmpty { after = " " + after }
        let cue = String(before.suffix(cueWindow))

        // Before: cut to ~80 chars at a word boundary, then at the last sentence start.
        if before.count > contextLength {
            before = String(before.suffix(contextLength))
            if let space = before.firstIndex(of: " ") { before = String(before[before.index(after: space)...]) }
            before = "…" + before
        }
        if let sentence = lastSentenceStart(in: before), before.distance(from: sentence, to: before.endIndex) >= 15 {
            before = String(before[sentence...])
        }
        // After: cut at the first sentence end past 15 chars, else ~80 chars at a word boundary.
        if let end = firstSentenceEnd(in: after, minimumOffset: 15) {
            after = String(after[..<end])
        } else if after.count > contextLength {
            after = String(after.prefix(contextLength))
            if let space = after.lastIndex(of: " ") { after = String(after[..<space]) }
            after += "…"
        }
        return (before, after, cue)
    }

    private static func lastSentenceStart(in s: String) -> String.Index? {
        var result: String.Index?
        var i = s.startIndex
        while i < s.endIndex {
            let c = s[i]
            if c == "." || c == "?" || c == "!" {
                let next = s.index(after: i)
                if next < s.endIndex, s[next] == " " {
                    let start = s.index(after: next)
                    if start < s.endIndex, s[start].isUppercase { result = start }
                }
            }
            i = s.index(after: i)
        }
        return result
    }

    private static func firstSentenceEnd(in s: String, minimumOffset: Int) -> String.Index? {
        var offset = 0
        var i = s.startIndex
        while i < s.endIndex {
            let c = s[i]
            let next = s.index(after: i)
            if offset >= minimumOffset, c == "." || c == "?" || c == "!",
               next == s.endIndex || s[next] == " " {
                return offset <= contextLength + 20 ? next : nil
            }
            offset += 1
            i = next
        }
        return nil
    }
}

// MARK: - Line-level heuristics (headings, running heads, captions)

private struct PageLines {
    var ranges: [NSRange] = []
    var maxLength = 0
    /// Lines holding emphasis set in a non-body size (e.g. a caption label "FIGURE 2.1.").
    var distinctSizeLines = Set<Int>()

    init(_ text: NSString, runs: [EmphasisRun]) {
        var location = 0
        while location < text.length {
            let line = text.lineRange(for: NSRange(location: location, length: 0))
            ranges.append(line)
            maxLength = max(maxLength, line.length)
            location = NSMaxRange(line)
        }
        for run in runs where abs(run.relativeSize - 1) > TermCandidates.sizeTolerance {
            if let index = lineIndex(containing: run.range.location) { distinctSizeLines.insert(index) }
        }
    }

    func lineIndex(containing location: Int) -> Int? {
        var lo = 0, hi = ranges.count - 1
        while lo <= hi {
            let mid = (lo + hi) / 2
            let r = ranges[mid]
            if location < r.location { hi = mid - 1 } else if location >= NSMaxRange(r) { lo = mid + 1 } else { return mid }
        }
        return nil
    }

    private static let sectionNumber = try! NSRegularExpression(
        pattern: #"^\s*(?:\d+(?:\.\d+)*\.?|[A-Z](?:\.\d+)+|(?:Chapter|CHAPTER|Section|SECTION|Part|PART)\s+[\dIVX]+)\s+"#)
    private static let captionStart = try! NSRegularExpression(
        pattern: #"^\s*(?:FIGURE|Figure|FIG\.|Fig\.|TABLE|Table|ALGORITHM|Algorithm|EXHIBIT|Exhibit|Listing)\s*[\dA-Z]+(?:[.\-]\d+)*[.:]\s+\S"#)

    private func letters(_ s: String) -> Int { s.unicodeScalars.filter { $0.properties.isAlphabetic }.count }

    private static let referenceYear = try! NSRegularExpression(pattern: #"\((?:1[89]|20)\d\d[a-z]?\)[.,]"#)
    private static let numberedReference = try! NSRegularExpression(pattern: #"(?m)^\s*\[\d+\]\s"#)
    private static let indexLine = try! NSRegularExpression(pattern: #"(?m)\d+(?:[–-]\d+)?,?\s*$"#)

    /// Bibliography pages: author–year entries "(1988)." or numbered "[12] …".
    func isReferenceList(_ text: NSString) -> Bool {
        let all = NSRange(location: 0, length: text.length)
        return Self.referenceYear.numberOfMatches(in: text as String, range: all) >= 5
            || Self.numberedReference.numberOfMatches(in: text as String, range: all) >= 5
    }

    /// Back-of-book index pages: most lines end in page numbers.
    func isIndex(_ text: NSString) -> Bool {
        guard ranges.count >= 15 else { return false }
        let matches = Self.indexLine.numberOfMatches(in: text as String, range: NSRange(location: 0, length: text.length))
        return Double(matches) >= 0.4 * Double(ranges.count)
    }

    /// A run that makes up (most of) a short line without closing punctuation, or
    /// the rest of a line that starts with a section/page number.
    func isHeading(_ range: NSRange, in text: NSString) -> Bool {
        guard let index = lineIndex(containing: range.location) else { return false }
        let line = text.substring(with: ranges[index]).trimmingCharacters(in: .whitespacesAndNewlines)
        let runEnd = min(NSMaxRange(range), NSMaxRange(ranges[index]))
        let runPart = text.substring(with: NSRange(location: range.location, length: runEnd - range.location))
        let lineLetters = letters(line), runLetters = letters(runPart)
        guard lineLetters > 0 else { return false }
        let ns = line as NSString
        if let m = Self.sectionNumber.firstMatch(in: line, range: NSRange(location: 0, length: ns.length)) {
            let rest = ns.substring(from: m.range.length)
            if Double(runLetters) >= 0.6 * Double(letters(rest)) { return true }
        }
        // A short Title Case line made of the run ("Missing Predictor Values"). PDFKit also
        // breaks lines around formulas ("The multiple regression coefficient" / "β̂j represents"),
        // which is why sentence-case lines do not count.
        let words = line.split(separator: " ")
        let long = words.filter { $0.count >= 4 }
        let titleCase = long.isEmpty || Double(long.filter { $0.first!.isUppercase }.count) >= 0.6 * Double(long.count)
        if Double(runLetters) >= 0.85 * Double(lineLetters), words.count <= 10, titleCase,
           let first = line.first, first.isUppercase || first.isNumber,
           let last = line.unicodeScalars.last, !".,;:)".unicodeScalars.contains(last) {
            return true
        }
        return false
    }

    /// The previous line does not continue into this one ("…as illustrated in" / "Figure 14.27.").
    private func isBlockStart(_ index: Int, in text: NSString) -> Bool {
        guard index > 0 else { return true }
        let previous = text.substring(with: ranges[index - 1]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard let last = previous.last else { return true }
        return ".!?:".contains(last) || !previous.contains(where: \.isLetter)
    }

    /// The run's line starts a caption, or follows a caption start without an
    /// intervening paragraph end (a short line ending in a period).
    func isCaption(_ range: NSRange, in text: NSString) -> Bool {
        guard let index = lineIndex(containing: range.location) else { return false }
        var i = index
        while i >= 0 && index - i <= 6 {
            let line = text.substring(with: ranges[i])
            if Self.captionStart.firstMatch(in: line, range: NSRange(location: 0, length: (line as NSString).length)) != nil,
               isBlockStart(i, in: text) || line.trimmingCharacters(in: .whitespaces).hasPrefix("FIG")
                || line.trimmingCharacters(in: .whitespaces).hasPrefix("TABLE") {
                // When the caption label is set in its own size, the size test already
                // handles captions; a body-size run below it is body text.
                return i == index || !distinctSizeLines.contains(i)
            }
            if i < index {
                let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmedLine.hasSuffix("."), Double(ranges[i].length) < 0.75 * Double(maxLength) { return false }
            }
            i -= 1
        }
        return false
    }
}
