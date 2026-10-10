import Foundation

/// A book's title for tabs and the library when it is first opened. Downloaded PDFs are often named "main.pdf",
/// "1706.03762v7.pdf" or "ESLII_print12.pdf"; their metadata usually knows better ("Attention Is All You Need"),
/// unless it holds a placeholder left by the typesetting tool, which this rejects.
public enum DocumentTitle {
    private static let placeholders: Set<String> = [
        "untitled", "untitled document", "title", "document", "main", "paper", "article", "book", "thesis", "manuscript",
        "slides", "draft", "pdf", "none", "unknown", "no title", "notitle", "report", "lecture notes", "notes", "preprint"
    ]
    private static let toolMarks = ["microsoft word", "microsoft powerpoint", "powerpoint presentation", ".tex", ".dvi", ".docx", ".doc",
                                    ".pdf", ".ps", ".indd", ".odt", "\\", "{", "}", "untitled-"]

    /// The metadata title when it reads like one, else nil (the caller keeps the file name).
    public static func fromMetadata(_ raw: String?, fileName: String) -> String? {
        guard let raw else { return nil }
        let title = raw.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "\"“”'")))
        guard (4...220).contains(title.count), title.contains(where: \.isLetter) else { return nil }
        let lower = title.lowercased()
        if placeholders.contains(lower) || toolMarks.contains(where: { lower.contains($0) }) { return nil }
        // An identifier rather than a title: one word with digits or underscores ("ESLII_print12", "1706.03762v7").
        if !title.contains(" "), title.contains(where: { $0.isNumber || $0 == "_" }) { return nil }
        let base = (fileName as NSString).deletingPathExtension
        if lower == base.lowercased() || lower == base.replacingOccurrences(of: "_", with: " ").lowercased() { return nil }
        // Titles written in capitals ("MATHEMATICS FOR MACHINE LEARNING") read better in title case.
        if title == title.uppercased(), title.count > 12 { return title.capitalized }
        return title
    }
}
