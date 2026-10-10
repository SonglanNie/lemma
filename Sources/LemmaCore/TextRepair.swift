import Foundation

/// Repairs common artefacts of TeX-produced PDF text layers, for matching and display.
/// Ranges found in the original page string must be computed before repairing it.
public enum TextRepair {
    private static let spacingAccents: [Character: Character] = [
        "\u{00A8}": "\u{0308}", // ¨ diaeresis: B¨uhlmann
        "\u{00B4}": "\u{0301}", // ´ acute
        "\u{0060}": "\u{0300}", // ` grave
        "\u{02C6}": "\u{0302}", // ˆ circumflex
        "\u{02DC}": "\u{0303}", // ˜ tilde
        "\u{02C7}": "\u{030C}", // ˇ caron
        "\u{00B8}": "\u{0327}"  // ¸ cedilla
    ]

    /// Ligatures become letters ("ﬀ" → "ff") and a spacing accent before a letter combines with it ("B¨uhlmann" → "Bühlmann").
    public static func repaired(_ text: String) -> String {
        var output = ""
        output.reserveCapacity(text.count)
        var pendingAccent: Character?
        for character in text {
            if let accent = spacingAccents[character] {
                if let pending = pendingAccent { output.append(pending) }
                pendingAccent = accent == "\u{0300}" ? nil : accent
                if accent == "\u{0300}" { output.append(character) }
                continue
            }
            if let accent = pendingAccent {
                if character.isLetter { output.append(String(character) + String(accent)) }
                else { output.append(Character(String(spacingAccent(for: accent)))); output.append(character) }
                pendingAccent = nil
                continue
            }
            switch character {
            case "ﬀ": output += "ff"
            case "ﬁ": output += "fi"
            case "ﬂ": output += "fl"
            case "ﬃ": output += "ffi"
            case "ﬄ": output += "ffl"
            case "ﬅ", "ﬆ": output += "st"
            default: output.append(character)
            }
        }
        if let accent = pendingAccent { output.append(Character(String(spacingAccent(for: accent)))) }
        return output.precomposedStringWithCanonicalMapping
    }

    private static func spacingAccent(for combining: Character) -> Character {
        spacingAccents.first { $0.value == combining }?.key ?? combining
    }

    /// A comparison form: repaired, case- and diacritic-folded, hyphens and dashes as spaces, single spaces.
    public static func folded(_ text: String) -> String {
        let repaired = repaired(text).folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
        let spaced = repaired.map { "-‐‑‒–\u{2014}/".contains($0) ? " " : $0 }
        return String(spaced).split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    /// Joins two lines of a hyphenated paragraph: "meth-" + "ods" → "methods", "499–" + "501" → "499–501".
    public static func joinLines(_ first: String, _ second: String) -> String {
        let head = first.trimmingCharacters(in: .whitespaces), tail = second.trimmingCharacters(in: .whitespaces)
        guard let last = head.last else { return tail }
        if last == "-" || last == "\u{00AD}", let next = tail.first, next.isLowercase { return String(head.dropLast()) + tail }
        if last == "–" || last == "-" || last == "/" { return head + tail }
        return head + " " + tail
    }
}
