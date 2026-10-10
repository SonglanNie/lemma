import Foundation

/// Text copied from a PDF page, as a reader expects to paste it: TeX ligatures and spacing accents repaired
/// ("ﬁnite" → "finite", "B¨uhlmann" → "Bühlmann"), words hyphenated across lines joined ("meth-" + "ods"), the line
/// breaks inside a paragraph turned into spaces, and blank lines kept as paragraph breaks.
public enum CleanCopy {
    public static func text(_ raw: String) -> String {
        let lines = raw.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: "\n")
        var paragraphs: [String] = []
        var current = ""
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty {
                if !current.isEmpty { paragraphs.append(current); current = "" }
                continue
            }
            current = current.isEmpty ? trimmed : TextRepair.joinLines(current, trimmed)
        }
        if !current.isEmpty { paragraphs.append(current) }
        return TextRepair.repaired(paragraphs.joined(separator: "\n\n"))
    }
}
