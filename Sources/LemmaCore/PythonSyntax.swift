import Foundation

/// A small Python tokenizer for the Lab's code cells: enough to colour keywords, strings, comments, numbers,
/// decorators and definitions as an editor does. Ranges are UTF-16, for NSTextStorage.
public enum PythonSyntax {
    public enum Kind: String, Sendable { case keyword, constant, builtin, string, comment, number, decorator, definition }
    public struct Token: Equatable, Sendable {
        public var range: NSRange
        public var kind: Kind
        public init(range: NSRange, kind: Kind) { self.range = range; self.kind = kind }
    }

    static let keywords: Set<String> = ["and", "as", "assert", "async", "await", "break", "class", "continue", "def", "del", "elif", "else",
        "except", "finally", "for", "from", "global", "if", "import", "in", "is", "lambda", "nonlocal", "not", "or", "pass", "raise",
        "return", "try", "while", "with", "yield", "match", "case"]
    static let constants: Set<String> = ["True", "False", "None", "self", "cls"]
    static let builtins: Set<String> = ["print", "len", "range", "enumerate", "zip", "map", "filter", "sum", "min", "max", "abs", "round",
        "sorted", "reversed", "list", "dict", "set", "tuple", "int", "float", "str", "bool", "complex", "isinstance", "type", "open",
        "super", "any", "all", "iter", "next", "pow", "divmod", "repr", "format", "getattr", "setattr", "hasattr", "vars", "dir",
        "np", "plt", "pd", "sp", "scipy", "numpy", "matplotlib", "pandas", "sklearn", "math", "random", "Exception", "ValueError",
        "TypeError", "KeyError", "IndexError", "RuntimeError", "ZeroDivisionError", "StopIteration", "NotImplementedError"]
    static let stringPrefixes: Set<String> = ["r", "b", "f", "u", "rb", "br", "fr", "rf"]

    public static func tokens(in text: String) -> [Token] {
        let s = text as NSString
        let n = s.length
        var tokens: [Token] = []
        var i = 0
        var previousWord = ""
        var lineStart = true

        func char(_ k: Int) -> unichar { k >= 0 && k < n ? s.character(at: k) : 0 }
        func isIdentifierStart(_ c: unichar) -> Bool { (c >= 65 && c <= 90) || (c >= 97 && c <= 122) || c == 95 || c > 127 }
        func isIdentifier(_ c: unichar) -> Bool { isIdentifierStart(c) || (c >= 48 && c <= 57) }
        func isDigit(_ c: unichar) -> Bool { c >= 48 && c <= 57 }
        let quote1: unichar = 39, quote2: unichar = 34, hash: unichar = 35, newline: unichar = 10, backslash: unichar = 92

        /// Scans a string literal whose opening quote is at `q`, returning the index after it.
        func scanString(from q: Int) -> Int {
            let quote = char(q)
            let triple = char(q + 1) == quote && char(q + 2) == quote
            var k = q + (triple ? 3 : 1)
            while k < n {
                let c = char(k)
                if c == backslash { k += 2; continue }
                if triple {
                    if c == quote && char(k + 1) == quote && char(k + 2) == quote { return k + 3 }
                } else {
                    if c == quote { return k + 1 }
                    if c == newline { return k }
                }
                k += 1
            }
            return n
        }

        while i < n {
            let c = char(i)
            if c == newline { lineStart = true; i += 1; continue }
            if c == 32 || c == 9 { i += 1; continue }
            if c == hash {
                var k = i
                while k < n && char(k) != newline { k += 1 }
                tokens.append(Token(range: NSRange(location: i, length: k - i), kind: .comment))
                i = k; lineStart = false; continue
            }
            if c == quote1 || c == quote2 {
                let end = scanString(from: i)
                tokens.append(Token(range: NSRange(location: i, length: end - i), kind: .string))
                i = end; lineStart = false; previousWord = ""; continue
            }
            if c == 64, lineStart { // @decorator
                var k = i + 1
                while k < n && (isIdentifier(char(k)) || char(k) == 46) { k += 1 }
                tokens.append(Token(range: NSRange(location: i, length: k - i), kind: .decorator))
                i = k; lineStart = false; continue
            }
            if isDigit(c) || (c == 46 && isDigit(char(i + 1))) {
                var k = i
                while k < n {
                    let d = char(k)
                    if isIdentifier(d) || d == 46 { k += 1; continue }
                    if (d == 43 || d == 45), k > i, char(k - 1) == 101 || char(k - 1) == 69, isDigit(char(k + 1)) { k += 1; continue }
                    break
                }
                tokens.append(Token(range: NSRange(location: i, length: k - i), kind: .number))
                i = k; lineStart = false; previousWord = ""; continue
            }
            if isIdentifierStart(c) {
                var k = i
                while k < n && isIdentifier(char(k)) { k += 1 }
                let word = s.substring(with: NSRange(location: i, length: k - i))
                if (char(k) == quote1 || char(k) == quote2), stringPrefixes.contains(word.lowercased()) {
                    let end = scanString(from: k)
                    tokens.append(Token(range: NSRange(location: i, length: end - i), kind: .string))
                    i = end; lineStart = false; previousWord = ""; continue
                }
                let range = NSRange(location: i, length: k - i)
                if previousWord == "def" || previousWord == "class" { tokens.append(Token(range: range, kind: .definition)) }
                else if keywords.contains(word) { tokens.append(Token(range: range, kind: .keyword)) }
                else if constants.contains(word) { tokens.append(Token(range: range, kind: .constant)) }
                else if builtins.contains(word), char(i - 1) != 46 { tokens.append(Token(range: range, kind: .builtin)) }
                previousWord = word
                i = k; lineStart = false; continue
            }
            lineStart = false
            if c != 46 { previousWord = "" }
            i += 1
        }
        return tokens
    }

    /// Names a cell can always complete without running Python: keywords and common built-ins.
    public static func staticCompletions(_ prefix: String) -> [String] {
        guard !prefix.isEmpty, !prefix.contains(".") else { return [] }
        let names = keywords.union(constants.subtracting(["self", "cls"])).union(builtins.subtracting(["np", "plt", "pd", "sp"]))
            .union(["import numpy as np", "import matplotlib.pyplot as plt", "import pandas as pd"])
        return names.filter { $0.hasPrefix(prefix) && $0 != prefix }.sorted()
    }

    /// Whether console input is ready to run, as an interactive interpreter decides: brackets and triple-quoted
    /// strings closed, no trailing colon or backslash, and a block ended by an empty line.
    public static func isComplete(_ code: String) -> Bool {
        let text = code as NSString
        guard !code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        var masked = Array(code.utf16)
        for token in tokens(in: code) where token.kind == .string || token.kind == .comment {
            if token.kind == .string {
                let literal = text.substring(with: token.range)
                let body = literal.drop { "rRbBfFuU".contains($0) }
                for quote in ["'''", "\"\"\""] where body.hasPrefix(quote) {
                    if body.count < 6 || !body.hasSuffix(quote) { return false }
                }
            }
            for index in token.range.location..<NSMaxRange(token.range) where index < masked.count { masked[index] = 32 }
        }
        var depth = 0
        for unit in masked {
            switch unit { case 40, 91, 123: depth += 1; case 41, 93, 125: depth -= 1; default: break }
        }
        if depth > 0 { return false }
        let lines = String(decoding: masked, as: UTF16.self).components(separatedBy: "\n")
        let meaningful = lines.map { $0.trimmingCharacters(in: .whitespaces) }
        if let last = meaningful.last(where: { !$0.isEmpty }), last.hasSuffix(":") || last.hasSuffix("\\") { return false }
        // A block (a line ending with a colon) runs once an empty line follows it.
        if meaningful.contains(where: { $0.hasSuffix(":") }) { return meaningful.last?.isEmpty == true }
        return true
    }

    /// The indentation for a new line after `line`: the same, plus four spaces after a colon.
    public static func indentation(after line: String) -> String {
        let leading = String(line.prefix { $0 == " " || $0 == "\t" })
        let code = line.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init) ?? line
        return code.trimmingCharacters(in: .whitespaces).hasSuffix(":") ? leading + "    " : leading
    }

    /// Comments or uncomments whole lines, as ⌘/ does in an editor. Returns the new text.
    public static func toggleComment(_ lines: [String]) -> [String] {
        let content = lines.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        let commented = !content.isEmpty && content.allSatisfy { $0.trimmingCharacters(in: .whitespaces).hasPrefix("#") }
        if commented {
            return lines.map { line in
                guard let range = line.range(of: "#") else { return line }
                var result = line
                result.removeSubrange(range)
                if result[range.lowerBound...].hasPrefix(" ") { result.remove(at: range.lowerBound) }
                return result
            }
        }
        let indent = content.map { $0.prefix { $0 == " " }.count }.min() ?? 0
        return lines.map { line in
            guard !line.trimmingCharacters(in: .whitespaces).isEmpty else { return line }
            let index = line.index(line.startIndex, offsetBy: min(indent, line.count))
            return String(line[..<index]) + "# " + String(line[index...])
        }
    }
}
