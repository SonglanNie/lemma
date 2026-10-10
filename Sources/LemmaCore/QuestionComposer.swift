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
public struct QuestionComposition: Sendable {
    public struct Attachment: Equatable, Sendable {
        public var title: String
        public var pageIndex: Int
        public var pageLabel: String
        public var note: String
        public init(title: String, pageIndex: Int, pageLabel: String, note: String = "") {
            self.title = title; self.pageIndex = pageIndex; self.pageLabel = pageLabel; self.note = note
        }
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
    public var section: String?
    public var note: StudyNote
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

    public var prompt: String {
        var text = "I am studying \(bookTitle)"
        if let section = section?.trimmingCharacters(in: .whitespacesAndNewlines), !section.isEmpty { text += ", in the section “\(section)”" }
        text += ".\nSource A: PDF page \(note.anchor.pageIndex + 1), page label \(note.anchor.pageLabel), shown in attached image 1.\n"
        if let sourceText = sourceText?.trimmingCharacters(in: .whitespacesAndNewlines), !sourceText.isEmpty {
            text += "\nText layer of Source A (it can garble mathematics; the image is authoritative):\n\"\"\"\n\(sourceText)\n\"\"\"\n"
        }
        text += "\nQuestion:\n\(note.question)\n"
        if !note.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { text += "\nMy reasoning so far:\n\(note.body)\n" }
        if !note.notation.isEmpty { text += "\nMy notation / dimensions (reader supplied):\n\(note.notation)\n" }
        if !note.scope.isEmpty { text += "\nLocal scope (reader supplied):\n\(note.scope)\n" }
        if !note.assumptions.isEmpty { text += "\nAssumptions to check (reader supplied):\n\(note.assumptions)\n" }
        var image = 2
        if !cited.isEmpty {
            text += "\nCited in Source A and attached:\n"
            for item in cited { text += "- Image \(image): \(item.title), PDF page \(item.pageIndex + 1), label \(item.pageLabel).\n"; image += 1 }
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
        if !linked.isEmpty {
            text += "\nNotes I linked to this question:\n"
            for item in linked {
                text += "- Image \(image): \(item.title), PDF page \(item.pageIndex + 1)"
                if !item.note.isEmpty { text += " · \(item.note.replacingOccurrences(of: "\n", with: " "))" }
                text += ".\n"; image += 1
            }
        }
        for (index, pin) in pins.enumerated() {
            text += "\nReference \(index + 1) (image \(image)): \(pin.title), PDF page \(pin.pageIndex + 1), label \(pin.pageLabel).\n"; image += 1
        }
        text += "\nUse the attached source regions as evidence. \(style.instruction) Identify any assumptions needed. If context is insufficient, say what is missing."
        return text
    }
}
