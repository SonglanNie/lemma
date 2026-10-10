import Foundation

/// PDF outlines often lose the spaces of their headings: “3.4.1Ridge Regression”, “Machines andFlexible Discriminants”,
/// “Ridge Regressionand the Lasso” (a manual line break in the heading). The heading printed on its page keeps them,
/// so the outline title is matched against the page's text ignoring whitespace and takes the page's spacing.
public enum OutlineTitle {
    /// The title with the page's spacing when the heading is found in `pageText`, otherwise with a space restored
    /// after a leading section number. Case and words are never changed.
    public static func repaired(_ title: String, pageText: String? = nil) -> String {
        var result = title
        // The page may itself lose spaces (“Aboutthisbook”): its spacing is taken only when it adds spaces, never removes them.
        if let pageText, let spaced = spacing(of: title, in: pageText), wordCount(spaced) >= wordCount(title) { result = spaced }
        if let range = result.range(of: #"^\d+(\.\d+)*(?=\p{L})"#, options: .regularExpression) {
            result.insert(" ", at: range.upperBound)
        }
        return result.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    static func wordCount(_ text: String) -> Int { text.split(whereSeparator: \.isWhitespace).count }

    /// The UTF-16 offset in `pageText` where `title` is printed, comparing without whitespace (“3.4.1Ridge Regression”).
    public static func location(of title: String, in pageText: String) -> Int? {
        let target = Array(TextRepair.repaired(title).unicodeScalars.filter { !CharacterSet.whitespacesAndNewlines.contains($0) })
        guard target.count >= 3 else { return nil }
        var compact: [Unicode.Scalar] = []
        var offsets: [Int] = []
        var utf16 = 0
        for scalar in pageText.unicodeScalars {
            if !CharacterSet.whitespacesAndNewlines.contains(scalar) { compact.append(scalar); offsets.append(utf16) }
            utf16 += scalar.utf16.count
        }
        guard compact.count >= target.count else { return nil }
        var start = 0
        while start + target.count <= compact.count {
            if compact[start] == target[0], Array(compact[start..<(start + target.count)]) == target { return offsets[start] }
            start += 1
        }
        return nil
    }

    /// Convenience for display sites without page text.
    public static func repaired(_ title: String) -> String { repaired(title, pageText: nil) }

    /// The words of `title` as spaced on the page, if the page contains them in order (whitespace ignored).
    static func spacing(of title: String, in text: String) -> String? {
        let target = Array(TextRepair.repaired(title).unicodeScalars.filter { !CharacterSet.whitespacesAndNewlines.contains($0) })
        guard target.count >= 5 else { return nil }
        let scalars = Array(TextRepair.repaired(text).unicodeScalars)
        var compact: [Unicode.Scalar] = []
        var positions: [Int] = []
        compact.reserveCapacity(scalars.count)
        for (index, scalar) in scalars.enumerated() where !CharacterSet.whitespacesAndNewlines.contains(scalar) {
            compact.append(scalar); positions.append(index)
        }
        guard compact.count >= target.count, let first = target.first else { return nil }
        var start = 0
        while start + target.count <= compact.count {
            if compact[start] == first, Array(compact[start..<(start + target.count)]) == target {
                let lower = positions[start], upper = positions[start + target.count - 1]
                var view = String.UnicodeScalarView()
                view.append(contentsOf: scalars[lower...upper])
                let spaced = String(view).split(whereSeparator: \.isWhitespace).joined(separator: " ")
                // Only spacing may differ; a match spanning a hyphenated line break is not used.
                return spaced.contains("- ") ? nil : spaced
            }
            start += 1
        }
        return nil
    }
}
