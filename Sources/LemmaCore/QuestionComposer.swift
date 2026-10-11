import Foundation

extension QuestionStyle {
    /// Used when the reader asks without typing: a short question in the reader's voice.
    public var defaultQuestion: String {
        switch self {
        case .explanation: "Explain this step."
        case .hint: "Give me a hint for this step."
        case .nextStep: "What is the next step here?"
        case .assumptions: "Why does this hold, and which assumptions does it need?"
        case .intuition: "What is the intuition behind this?"
        case .example: "Show me a small worked example of this."
        case .counterexample: "What breaks if one assumption is dropped?"
        case .recreateFigure: "How could I recreate this figure?"
        case .code: "Turn this into code I can run."
        }
    }

    /// A short label for compact controls.
    public var shortLabel: String {
        switch self {
        case .explanation: "Explain"; case .hint: "Hint"; case .nextStep: "Next step"; case .assumptions: "Why?"
        case .intuition: "Intuition"; case .example: "Example"; case .counterexample: "Counterexample"; case .recreateFigure: "Figure"
        case .code: "Code"
        }
    }
}

/// The reader's own glossary entries whose names occur in a passage, ordered by proximity to it.
/// Matching is literal, with the same whole-term and case rules as definition lookup.
public enum GlossaryMatcher {
    public static func entries(mentionedIn text: String, from notes: [StudyNote], near pageIndex: Int, excluding excluded: UUID? = nil, limit: Int = 6) -> [StudyNote] {
        let haystack = text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        guard !haystack.isEmpty else { return [] }
        let range = NSRange(haystack.startIndex..., in: haystack)
        let matches = notes.filter { note in
            guard note.kind.isGlossary, note.id != excluded else { return false }
            let names = ([note.question] + note.lookupTerms.split(whereSeparator: \.isNewline).map(String.init))
                .map { $0.split(whereSeparator: \.isWhitespace).joined(separator: " ") }
                .filter { !$0.isEmpty && $0.count <= 60 }
            return names.contains { name in
                let symbol = name.count == 1 || name.contains("\\") || name.contains("_") || name.contains("^")
                let pattern = "(?<![\\p{L}\\p{N}_])" + NSRegularExpression.escapedPattern(for: name) + "(?![\\p{L}\\p{N}_])"
                guard let expression = try? NSRegularExpression(pattern: pattern, options: symbol ? [] : [.caseInsensitive]) else { return false }
                return expression.firstMatch(in: haystack, range: range) != nil
            }
        }
        return Array(matches.sorted {
            let lhsEarlier = $0.anchor.pageIndex <= pageIndex, rhsEarlier = $1.anchor.pageIndex <= pageIndex
            if lhsEarlier != rhsEarlier { return lhsEarlier }
            let lhs = abs($0.anchor.pageIndex - pageIndex), rhs = abs($1.anchor.pageIndex - pageIndex)
            return lhs == rhs ? $0.id.uuidString < $1.id.uuidString : lhs < rhs
        }.prefix(limit))
    }
}

/// Builds the exact question text from the reader's chosen context. Every included item is named in the
/// text, and every attached image is listed in order, so the reader can check what the draft shares.
///
/// The book and the attached images come first, then the passage's text and the reader's own notes, and the question
/// and the kind of help last, where long prompts are read best. “Source A: PDF page” and the opening “I am studying”
/// also let the ChatGPT page recognise a question Lemma prepared earlier.
public struct QuestionComposition: Sendable {
    public struct Attachment: Equatable, Sendable {
        public var title: String
        public var pageIndex: Int
        /// The page number printed in the book, when the reader's PDF knows one that differs from its own numbering.
        public var pageLabel: String
        public var note: String
        public init(title: String, pageIndex: Int, pageLabel: String, note: String = "") {
            self.title = title; self.pageIndex = pageIndex; self.pageLabel = pageLabel; self.note = note
        }
        var place: String { QuestionComposition.place(pageIndex, pageLabel) }
    }

    public struct GlossaryEntry: Equatable, Sendable {
        public var title: String
        public var names: [String]
        public var notation: String
        public var scope: String
        public var pageIndex: Int
        public init(note: StudyNote) {
            title = note.title
            names = note.lookupTerms.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            notation = note.notation.trimmingCharacters(in: .whitespacesAndNewlines)
            scope = note.scope.trimmingCharacters(in: .whitespacesAndNewlines)
            pageIndex = note.anchor.pageIndex
        }
    }

    public var bookTitle: String
    /// The authors, from the PDF's metadata when it names them.
    public var bookAuthors: String?
    public var section: String?
    public var note: StudyNote
    /// The printed page of the passage, when known and different from the PDF's numbering.
    public var printedPage: String?
    public var sourceText: String?
    /// Equations, figures and other objects cited in the source, attached as images.
    public var cited: [Attachment] = []
    public var glossary: [GlossaryEntry] = []
    /// Reader-linked notes; their crops are attached as images.
    public var linked: [Attachment] = []
    public var pins: [Attachment] = []
    public var style: QuestionStyle

    public init(bookTitle: String, section: String? = nil, note: StudyNote, sourceText: String? = nil, style: QuestionStyle) {
        self.bookTitle = bookTitle; self.section = section; self.note = note; self.sourceText = sourceText; self.style = style
    }

    /// Image labels in attachment order: Source A first.
    public var imageLabels: [String] {
        ["Source A"] + cited.map { "Cited: \($0.title)" } + linked.map { "Linked: \($0.title)" }
            + pins.enumerated().map { "Reference \($0.offset + 1): \($0.element.title)" }
    }

    /// “PDF page 157 (printed page 147)”, or “PDF page 157” when the book prints no other number.
    static func place(_ pageIndex: Int, _ printed: String?) -> String {
        let label = printed?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return label.isEmpty || label == String(pageIndex + 1) ? "PDF page \(pageIndex + 1)" : "PDF page \(pageIndex + 1) (printed page \(label))"
    }

    /// What every answer should respect, whatever the kind of help.
    public static let answerRules = "Base what you say about the book on the images and text above, and use standard mathematics freely; if something you need is not shown, say what is missing. State any assumption you add. Keep the book's notation and write mathematics in LaTeX."

    public var prompt: String {
        func clean(_ text: String) -> String { text.trimmingCharacters(in: .whitespacesAndNewlines) }
        var text = "I am studying \(clean(bookTitle))"
        if let authors = bookAuthors.map(clean), !authors.isEmpty { text += " by \(authors)" }
        if let section = section.map(clean), !section.isEmpty { text += ", in the section “\(section)”" }
        text += ".\nSource A: \(Self.place(note.anchor.pageIndex, printedPage ?? note.anchor.pageLabel)), the passage I am asking about, attached as image 1.\n"
        var image = 2
        if !cited.isEmpty {
            text += "\nCited in Source A and attached:\n"
            for item in cited { text += "- Image \(image): \(item.title), \(item.place).\n"; image += 1 }
        }
        if !linked.isEmpty {
            text += "\nNotes I linked to this question, attached:\n"
            for item in linked {
                text += "- Image \(image): \(item.title), \(item.place)"
                if !clean(item.note).isEmpty { text += " · \(item.note.replacingOccurrences(of: "\n", with: " "))" }
                text += ".\n"; image += 1
            }
        }
        if !pins.isEmpty {
            text += "\nReferences I pinned, attached:\n"
            for (index, pin) in pins.enumerated() { text += "- Image \(image): Reference \(index + 1), \(pin.title), \(pin.place).\n"; image += 1 }
        }
        if let sourceText = sourceText.map(clean), !sourceText.isEmpty {
            text += "\nText of Source A, extracted from the PDF (formulas often come out garbled there; image 1 is authoritative):\n<source_text>\n\(sourceText)\n</source_text>\n"
        }
        if !glossary.isEmpty {
            text += "\nMy glossary entries for terms in this passage (my own notes, not the book’s text):\n"
            for entry in glossary {
                var line = "- \(entry.title)"
                let names = entry.names.filter { $0.compare(entry.title, options: [.caseInsensitive, .diacriticInsensitive]) != .orderedSame }
                if !names.isEmpty { line += " (written \(names.joined(separator: ", ")))" }
                if !entry.notation.isEmpty { line += ": \(entry.notation.replacingOccurrences(of: "\n", with: "; "))" }
                if !entry.scope.isEmpty { line += ". Scope: \(entry.scope.replacingOccurrences(of: "\n", with: "; "))" }
                text += line + ". Defined near PDF page \(entry.pageIndex + 1).\n"
            }
        }
        if !clean(note.body).isEmpty { text += "\nMy reasoning so far:\n\(clean(note.body))\n" }
        if !clean(note.notation).isEmpty { text += "\nMy notation / dimensions:\n\(clean(note.notation))\n" }
        if !clean(note.scope).isEmpty { text += "\nLocal scope:\n\(clean(note.scope))\n" }
        if !clean(note.assumptions).isEmpty { text += "\nAssumptions to check:\n\(clean(note.assumptions))\n" }
        text += "\nQuestion:\n\(clean(note.question))\n"
        text += "\n\(style.instruction) \(Self.answerRules)"
        return text
    }
}
