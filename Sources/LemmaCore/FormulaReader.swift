//
//  FormulaReader.swift · the LaTeX of a formula, read back from the glyphs and rules a page draws.
//
//  A born-digital PDF keeps what typesetting a formula decided: which font each glyph is in (a 7 pt math
//  italic is a script), its exact baseline (raised: a superscript; lowered: a subscript), the rules that are
//  fraction bars and radical signs, and · in TeX's fonts · glyph names that tell a display sum from a text one
//  and the pieces of a tall parenthesis. Reading those back gives the formula's structure without recognising
//  images: a rule with glyphs above and below is a fraction; small glyphs centred under a big operator are its
//  limits; rows inside tall delimiters are a matrix.
//
//  This is a geometric transcription heuristic. Its result counts glyphs it could not name; recognizing
//  every glyph does not establish that the arrangement was read correctly. Callers keep the source image
//  beside the editable transcription.
//

import CoreGraphics
import Foundation

/// A formula read from a page.
public struct FormulaReading: Equatable, Sendable {
    /// The formula as LaTeX.
    public var latex: String
    /// The equation's number as printed beside it (“(3.44)”), when the region held one.
    public var tag: String?
    /// The number of lines of a multi-line display (1 otherwise).
    public var rows: Int
    /// Glyphs the reader could not name; they appear as “?” in the LaTeX.
    public var unknown: Int
    /// Glyphs read.
    public var glyphs: Int
    /// The formula's extent on the page.
    public var bounds: CGRect

    /// Whether every glyph was named.
    public var isComplete: Bool { unknown == 0 && !latex.isEmpty }
}

public enum FormulaReader {
    /// Reads the mathematics drawn in a rectangle of a page (the whole page's ink when `rect` is nil).
    /// - Parameters:
    ///   - label: where the equation's number is printed, when the caller knows it: the number is left out, and in a
    ///     display whose lines carry their own numbers only this one's lines are read.
    ///   - keepPunctuation: keep the comma or full stop that ends a displayed formula.
    public static func read(_ ink: PageInk, in rect: CGRect? = nil, label: CGRect? = nil, keepPunctuation: Bool = false) -> FormulaReading? {
        var clipped = rect.map { ink.clipped(to: $0) } ?? ink
        if let label {
            clipped.glyphs.removeAll { label.insetBy(dx: -0.5, dy: -1).contains(CGPoint(x: $0.midX, y: $0.y + $0.size * 0.2)) }
        }
        guard !clipped.glyphs.isEmpty else { return nil }
        // Lines of running text that the rectangle caught (the sentence before a display) are not the formula.
        if rect != nil {
            let prose = FormulaProseLines.proseBands(in: ink)
            if !prose.isEmpty {
                let kept = clipped.glyphs.filter { glyph in !prose.contains { glyph.y > $0.lowerBound && glyph.y < $0.upperBound } }
                if !kept.isEmpty { clipped.glyphs = kept }
            }
        }
        var unknown = 0
        var items: [InkItem] = []
        for glyph in clipped.glyphs {
            if let item = InkItem(glyph: glyph) { items.append(item) }
            else if !glyph.text.isEmpty || glyph.name != nil { unknown += 1; items.append(InkItem.unknown(glyph)) }
        }
        guard !items.isEmpty else { return nil }
        items = FormulaLayout.attachAccents(FormulaLayout.prepare(items))
        let rules = clipped.rules.filter(\.isHorizontal).map(\.rect).filter { $0.height <= 1.6 && $0.width >= 1.5 }
        // Rows, each without the number printed beside it.
        var rows = FormulaLayout.splitRows(items, rules: rules)
        var tags = [String?](repeating: nil, count: rows.count)
        for index in rows.indices { (rows[index], tags[index]) = FormulaLayout.extractTag(rows[index]) }
        var tag = tags.compactMap { $0 }.first
        if let label, rows.count > 1 {
            // Lines up to and including the one that carries this label, back to the previous numbered line.
            let bands = rows.map { row in (row.map(\.bottom).min() ?? 0, row.map(\.top).max() ?? 0) }
            if let own = bands.indices.min(by: { abs((bands[$0].0 + bands[$0].1) / 2 - label.midY) < abs((bands[$1].0 + bands[$1].1) / 2 - label.midY) }) {
                var first = own
                while first > 0, tags[first - 1] == nil { first -= 1 }
                var last = own
                // A label centred beside several lines (split) belongs to all of them: take following unnumbered lines when it sits between rows.
                if tags[own] == nil, label.midY < bands[own].0 - 1 { while last + 1 < rows.count, tags[last + 1] == nil { last += 1 } }
                if tags.contains(where: { $0 != nil }) { rows = Array(rows[first...last]); tag = nil }
            }
        }
        rows.removeAll { $0.isEmpty }
        guard !rows.isEmpty else { return nil }
        let kept = rows.flatMap { $0 }
        let bounds = kept.reduce(CGRect.null) { $0.union(CGRect(x: $1.x0, y: $1.bottom, width: max(0.1, $1.x1 - $1.x0), height: max(0.1, $1.top - $1.bottom))) }
        let laid = FormulaLayout.layoutRows(rows, rules: rules, context: .top, keepPunctuation: keepPunctuation)
        let latex = laid.latex.trimmingCharacters(in: .whitespaces)
        guard !latex.isEmpty else { return nil }
        return FormulaReading(latex: latex, tag: tag, rows: laid.rows, unknown: unknown, glyphs: clipped.glyphs.count, bounds: bounds)
    }
}

/// The lines of running text on a page, so a formula's rectangle can leave them out.
private enum FormulaProseLines {
    /// Vertical bands (baseline − descent … baseline + ascent) of the page's lines of prose: lines with many
    /// letters of text fonts that start at the text column's left edge.
    static func proseBands(in ink: PageInk) -> [ClosedRange<CGFloat>] {
        struct Line { var y: CGFloat; var minX: CGFloat; var letters: Int; var size: CGFloat }
        var lines: [Line] = []
        var index: [Int: Int] = [:]
        for glyph in ink.glyphs {
            let key = Int((glyph.y * 2).rounded())
            let position: Int
            if let found = index[key] ?? index[key - 1] ?? index[key + 1] { position = found }
            else { position = lines.count; lines.append(Line(y: glyph.y, minX: glyph.x, letters: 0, size: glyph.size)); index[key] = position }
            lines[position].minX = min(lines[position].minX, glyph.x)
            if isTextLetter(glyph) { lines[position].letters += 1; lines[position].size = max(lines[position].size, glyph.size) }
        }
        let wordy = lines.filter { $0.letters >= 30 }
        guard !wordy.isEmpty else { return [] }
        // The column's left edge: the most common start of a long line.
        var votes: [Int: Int] = [:]
        for line in wordy { votes[Int(line.minX.rounded()), default: 0] += 1 }
        let margins = votes.filter { $0.value >= max(2, wordy.count / 6) }.map { CGFloat($0.key) }
        return lines.compactMap { line in
            guard line.letters >= 18 else { return nil }
            let atMargin = margins.isEmpty || margins.contains { line.minX <= $0 + 2.6 * line.size && line.minX >= $0 - 3 }
            guard atMargin || line.letters >= 45 else { return nil }
            return (line.y - 0.32 * line.size)...(line.y + 0.78 * line.size)
        }
    }

    static func isTextLetter(_ glyph: InkGlyph) -> Bool {
        guard let first = glyph.text.unicodeScalars.first, first.properties.isAlphabetic, first.value < 0x250 || (0xFB00...0xFB06).contains(first.value) else { return false }
        let family = glyph.family
        if family.hasPrefix("CMMI") || family.hasPrefix("CMSY") || family.hasPrefix("CMEX") || family.hasPrefix("MSBM") || family.hasPrefix("MSAM") || family.hasPrefix("CMBSY") { return false }
        if family.hasPrefix("CM") || family.hasPrefix("SF") || family.hasPrefix("EC") || family.hasPrefix("LMR") || family.hasPrefix("LMS") { return true }
        let lower = glyph.font.lowercased()
        return !(lower.contains("math") || lower.contains("symbol") || lower.contains("mi") && lower.contains("px") || lower.hasPrefix("txmi") || lower.hasPrefix("pxmi"))
    }
}

// MARK: - Items

/// A symbol or a structure of a formula with its place on the page.
struct InkItem {
    var x0: CGFloat
    var x1: CGFloat
    /// The baseline. For a hanging item (an extension-font glyph, a fraction) the baseline its math axis implies.
    var y: CGFloat
    var top: CGFloat
    var bottom: CGFloat
    var size: CGFloat
    var kind: InkKind
    var latex: String
    var style: InkStyle = .italic
    /// The plain text of letters, digits and words.
    var plain: String?
    /// Centred on the math axis instead of sitting on a baseline: TeX's extension glyphs, fractions, matrices.
    var centred = false
    /// A delimiter taller than the line: from an extension font, or built from pieces.
    var big = false
    /// Set in a text font: its letters make words.
    var textFont = false
    var font = ""
    var order = 0
    /// An accent's base has been found; a word is prose.
    var isText = false

    var midX: CGFloat { (x0 + x1) / 2 }
    var midY: CGFloat { (top + bottom) / 2 }
    var width: CGFloat { x1 - x0 }
    var height: CGFloat { top - bottom }

    init(x0: CGFloat, x1: CGFloat, y: CGFloat, top: CGFloat, bottom: CGFloat, size: CGFloat, kind: InkKind, latex: String) {
        self.x0 = x0; self.x1 = x1; self.y = y; self.top = top; self.bottom = bottom; self.size = size; self.kind = kind; self.latex = latex
    }

    /// A structure built from other items, centred on the math axis at `axis`.
    static func structure(_ latex: String, covering items: [InkItem], axis: CGFloat? = nil, baseline: CGFloat? = nil, size: CGFloat, extra: CGRect = .null) -> InkItem {
        var x0 = extra.isNull ? CGFloat.infinity : extra.minX, x1 = extra.isNull ? -CGFloat.infinity : extra.maxX
        var top = extra.isNull ? -CGFloat.infinity : extra.maxY, bottom = extra.isNull ? CGFloat.infinity : extra.minY
        for item in items { x0 = min(x0, item.x0); x1 = max(x1, item.x1); top = max(top, item.top); bottom = min(bottom, item.bottom) }
        var result = InkItem(x0: x0, x1: x1, y: baseline ?? ((axis ?? (top + bottom) / 2) - FormulaLayout.axisHeight * size), top: top, bottom: bottom, size: size, kind: .structure, latex: latex)
        result.centred = baseline == nil
        result.order = items.map(\.order).min() ?? 0
        return result
    }

    init?(glyph: InkGlyph) {
        var symbol = glyph.name.flatMap(FormulaSymbols.symbol(named:))
        var style = FormulaSymbols.style(ofFont: glyph.font)
        if symbol == nil, glyph.text.count == 1, let character = glyph.text.first {
            symbol = FormulaSymbols.symbol(for: character)
            if let unicodeStyle = FormulaSymbols.style(ofUnicode: character) { style = unicodeStyle }
        }
        if symbol == nil, glyph.text.count > 1, glyph.text.allSatisfy({ $0.isLetter }) { symbol = InkSymbol(latex: glyph.text, kind: .letter, plain: glyph.text) }
        if symbol == nil, glyph.text.count > 1, let first = glyph.text.first { symbol = FormulaSymbols.symbol(for: first) }
        guard let symbol else { return nil }
        let s = glyph.size
        let hanging = FormulaSymbols.isExtensionFont(glyph.font) || glyph.name == "radical"
        var top: CGFloat, bottom: CGFloat
        if symbol.kind == .accent {
            // An accent floats above its letter: its extent reaches down to its own baseline, so the two stay on one row.
            top = glyph.y + 0.78 * s; bottom = glyph.y - (hanging ? 0.1 * s : 0)
        } else if hanging {
            top = glyph.y + 0.04 * s; bottom = glyph.y - InkItem.hangingDepth(glyph.name ?? "", kind: symbol.kind) * s
        } else {
            let (ascent, descent) = InkItem.extent(symbol: symbol, text: glyph.text)
            top = glyph.y + ascent * s; bottom = glyph.y - descent * s
        }
        self.init(x0: glyph.x, x1: glyph.maxX, y: glyph.y, top: top, bottom: bottom, size: s, kind: symbol.kind, latex: symbol.latex)
        self.style = style
        plain = symbol.plain
        centred = hanging && symbol.kind != .accent
        if centred { y = (top + bottom) / 2 - FormulaLayout.axisHeight * s }
        big = hanging && [.open, .close, .bar].contains(symbol.kind)
        font = glyph.font
        order = glyph.order
        let family = glyph.family
        textFont = family.hasPrefix("CMTI") || family.hasPrefix("CMSL") || family.hasPrefix("CMR") || family.hasPrefix("CMSS") || family.hasPrefix("CMTT")
            || family.hasPrefix("CMCSC") || (style == .roman && !family.hasPrefix("CMSY") && !family.hasPrefix("CMEX"))
        // In TeX's symbol font only the capitals are calligraphic letters.
        if style == .calligraphic, !(symbol.kind == .letter && (symbol.plain?.first?.isUppercase ?? false) && (symbol.plain?.first?.isASCII ?? false)) { self.style = .italic }
    }

    static func unknown(_ glyph: InkGlyph) -> InkItem {
        var item = InkItem(x0: glyph.x, x1: glyph.maxX, y: glyph.y, top: glyph.y + 0.6 * glyph.size, bottom: glyph.y, size: glyph.size, kind: .ordinary, latex: "\\text{?}")
        item.order = glyph.order; item.font = glyph.font
        return item
    }

    /// How far an extension-font glyph hangs below its origin, in ems (from Computer Modern's metrics).
    static func hangingDepth(_ name: String, kind: InkKind) -> CGFloat {
        if name.hasSuffix("Bigg") { return 3.0 }
        if name.hasSuffix("bigg") { return 2.4 }
        if name.hasSuffix("Big") { return 1.8 }
        if name.hasSuffix("big") { return 1.2 }
        if name.hasSuffix("display") { return name.contains("integral") ? 2.22 : 1.4 }
        if name.hasSuffix("text") { return name.contains("integral") ? 1.11 : 1.0 }
        if name == "radical" { return 0.96 }
        if name == "radicalbt" { return 1.82 }
        if name == "radicalvertex" || name == "radicaltp" { return 0.62 }
        if name.hasPrefix("brace"), name.hasSuffix("tp") || name.hasSuffix("bt") { return 0.9 }
        if name == "braceex" { return 0.3 }
        if name.hasSuffix("mid") || name.hasSuffix("tp") || name.hasSuffix("bt") { return 1.8 }
        if name.hasSuffix("ex") || name.hasPrefix("vextend") { return 0.6 }
        return kind == .bigOperator ? 1.0 : 1.2
    }

    /// The approximate ascent and descent of an ordinary glyph, in ems.
    static func extent(symbol: InkSymbol, text: String) -> (CGFloat, CGFloat) {
        switch symbol.kind {
        case .open, .close, .bar: return (0.75, 0.25)
        case .binary, .relation: return (0.58, 0.08)
        case .punctuation: return symbol.latex == "," || symbol.latex == ";" ? (0.11, 0.19) : (0.44, 0)
        case .digit: return (0.65, 0)
        case .bigOperator: return (0.75, 0.25)
        case .prime: return (0.56, -0.2)
        case .radical: return (0.8, 0.2)
        case .letter:
            let character = symbol.plain?.first ?? text.first ?? "x"
            let ascender = character.isUppercase || "bdfhijkltβδζθλξϑφψℓ".contains(character)
            let descender = "gjpqyfβγζημξρφχψςϱ".contains(character)
            return (ascender ? 0.7 : 0.45, descender ? 0.2 : 0)
        default: return (0.7, symbol.latex == "/" ? 0.25 : 0.05)
        }
    }
}

// MARK: - Layout

enum FormulaLayout {
    /// The math axis above the baseline, in ems (Computer Modern: 2.5 pt at 10 pt).
    static let axisHeight: CGFloat = 0.25

    enum Context { case top, cell, script }

    struct Laid {
        var latex: String
        var baseline: CGFloat
        var size: CGFloat
        var rows = 1
    }

    // MARK: Preparation: pieces, negations, numbers and words

    /// Merges what several glyphs draw as one symbol: tall delimiters built from pieces, `\not` and its relation,
    /// digits of a number, letters of a word.
    static func prepare(_ source: [InkItem]) -> [InkItem] {
        var items = removeDuplicates(source)
        items = mergePieces(items)
        items = mergeNegations(items)
        items = mergeNumbersAndWords(items)
        return items
    }

    /// A glyph struck twice at the same place (a poor man's bold) counts once.
    private static func removeDuplicates(_ items: [InkItem]) -> [InkItem] {
        var result: [InkItem] = []
        for item in items {
            if let last = result.last(where: { $0.latex == item.latex && $0.font == item.font }), abs(last.x0 - item.x0) < 0.35, abs(last.y - item.y) < 0.35, abs(last.size - item.size) < 0.1 { continue }
            result.append(item)
        }
        return result
    }

    /// Stacks of top, extension and bottom pieces at one x become one tall delimiter or radical.
    private static func mergePieces(_ items: [InkItem]) -> [InkItem] {
        var result: [InkItem] = []
        var used = Set<Int>()
        for (index, item) in items.enumerated() where !used.contains(index) {
            let stackable = item.kind == .piece || (item.centred && item.kind == .bar)
            guard stackable else { result.append(item); continue }
            // Everything stacked in the same column, touching vertically.
            var group = [index]
            var grew = true
            var top = item.top, bottom = item.bottom
            while grew {
                grew = false
                for (other, candidate) in items.enumerated() where !used.contains(other) && !group.contains(other) {
                    guard candidate.kind == .piece || (candidate.centred && candidate.kind == .bar), abs(candidate.x0 - item.x0) < 0.25 * item.size + 0.6 else { continue }
                    if candidate.top >= bottom - 0.25 * item.size && candidate.bottom <= top + 0.25 * item.size {
                        group.append(other); top = max(top, candidate.top); bottom = min(bottom, candidate.bottom); grew = true
                    }
                }
            }
            used.formUnion(group)
            let members = group.map { items[$0] }
            if members.count == 1, item.kind == .bar { result.append(item); continue }
            let base = members.first { $0.kind == .piece && $0.latex != "brace" && $0.latex != "arrowvert" }?.latex ?? (item.kind == .bar ? "bar" : members[0].latex)
            let x0 = members.map(\.x0).min()!, x1 = members.map(\.x1).max()!
            var merged = InkItem(x0: x0, x1: x1, y: 0, top: top, bottom: bottom, size: item.size, kind: .ordinary, latex: "")
            merged.centred = true; merged.big = true; merged.order = members.map(\.order).min()!; merged.font = item.font
            merged.y = (top + bottom) / 2 - axisHeight * item.size
            switch base {
            case "radical": merged.kind = .radical; merged.latex = "\\sqrt"; merged.big = false
            case "bar": merged.kind = .bar; merged.latex = members.contains { $0.latex == "\\|" } ? "\\|" : "|"
            default:
                guard let symbol = FormulaSymbols.symbol(named: base), [.open, .close, .bar].contains(symbol.kind) else { continue }
                merged.kind = symbol.kind; merged.latex = symbol.latex
            }
            result.append(merged)
        }
        return result
    }

    /// `\not` is a slash of no width struck over the relation that follows.
    private static func mergeNegations(_ items: [InkItem]) -> [InkItem] {
        var result: [InkItem] = []
        var index = 0
        let sorted = items
        while index < sorted.count {
            let item = sorted[index]
            if item.latex == "\\not", index + 1 < sorted.count {
                var next = sorted[index + 1]
                if abs(next.y - item.y) < 0.2 * item.size, next.x0 - item.x0 < 0.9 * item.size {
                    switch next.latex {
                    case "=": next.latex = "\\ne"
                    case "\\in": next.latex = "\\notin"
                    case "\\equiv": next.latex = "\\not\\equiv"
                    case "\\subset": next.latex = "\\not\\subset"
                    case "\\subseteq": next.latex = "\\nsubseteq"
                    case "\\sim": next.latex = "\\nsim"
                    case "\\le": next.latex = "\\nleq"
                    case "\\ge": next.latex = "\\ngeq"
                    case "<": next.latex = "\\nless"
                    case ">": next.latex = "\\ngtr"
                    case "\\exists": next.latex = "\\nexists"
                    default: next.latex = "\\not" + (next.latex.hasPrefix("\\") ? "" : " ") + next.latex
                    }
                    next.x0 = min(next.x0, item.x0)
                    result.append(next); index += 2; continue
                }
            }
            result.append(item); index += 1
        }
        return result
    }

    private static func sameLine(_ a: InkItem, _ b: InkItem) -> Bool {
        abs(a.y - b.y) < 0.06 * a.size && abs(a.size - b.size) < 0.06 * a.size
    }

    /// Digits set tight together are a number; roman letters set tight together are a word.
    private static func mergeNumbersAndWords(_ source: [InkItem]) -> [InkItem] {
        // Work in reading order within each baseline: sort by baseline (top first), then x.
        let items = source
        var result: [InkItem] = []
        var consumed = Set<Int>()
        // Index items by position for neighbour lookups.
        let order = items.indices.sorted { a, b in
            if abs(items[a].y - items[b].y) > 0.05 { return items[a].y > items[b].y }
            return items[a].x0 < items[b].x0
        }
        var position = 0
        while position < order.count {
            let index = order[position]
            let item = items[index]
            if consumed.contains(index) { position += 1; continue }
            // A number: digits, with a decimal point between digits.
            if item.kind == .digit {
                var merged = item
                var text = item.plain ?? item.latex
                var next = position + 1
                while next < order.count {
                    let candidate = items[order[next]]
                    guard sameLine(merged, candidate), candidate.font == item.font, candidate.x0 - merged.x1 < 0.12 * item.size, candidate.x0 - merged.x1 > -0.2 * item.size else { break }
                    if candidate.kind == .digit {
                        text += candidate.plain ?? candidate.latex
                    } else if candidate.kind == .punctuation, candidate.latex == ".", next + 1 < order.count, items[order[next + 1]].kind == .digit,
                              sameLine(merged, items[order[next + 1]]), items[order[next + 1]].x0 - candidate.x1 < 0.12 * item.size {
                        text += "."
                    } else { break }
                    merged.x1 = candidate.x1; merged.top = max(merged.top, candidate.top); merged.bottom = min(merged.bottom, candidate.bottom)
                    consumed.insert(order[next]); next += 1
                }
                merged.plain = text
                merged.latex = item.style == .bold ? "\\mathbf{\(text)}" : item.style == .blackboard ? "\\mathbb{\(text)}" : text
                result.append(merged); position += 1; continue
            }
            // A word: letters of a text font.
            if item.kind == .letter, item.textFont, item.style != .italic || InkGlyph.family(of: item.font).hasPrefix("CMTI") || InkGlyph.family(of: item.font).hasPrefix("CMSL") {
                var merged = item
                var text = item.plain ?? item.latex
                var next = position + 1
                while next < order.count {
                    let candidate = items[order[next]]
                    guard candidate.kind == .letter, candidate.font == item.font, sameLine(merged, candidate),
                          candidate.x0 - merged.x1 < 0.13 * item.size, candidate.x0 - merged.x1 > -0.2 * item.size else { break }
                    text += candidate.plain ?? candidate.latex
                    merged.x1 = candidate.x1; merged.top = max(merged.top, candidate.top); merged.bottom = min(merged.bottom, candidate.bottom)
                    consumed.insert(order[next]); next += 1
                }
                if text.count > 1 || (item.plain?.count ?? 1) > 1 {
                    merged.kind = .word; merged.plain = text
                    let word = wordLatex(text, style: item.style, textItalic: item.style == .italic)
                    merged.latex = word.latex; merged.isText = word.isText
                } else {
                    merged.latex = styled(item)
                }
                result.append(merged); position += 1; continue
            }
            var plainItem = item
            if item.kind == .letter { plainItem.latex = styled(item) }
            result.append(plainItem); position += 1
        }
        // Back to stream order, which the rest of the layout does not depend on but keeps results stable.
        return result.sorted { $0.order < $1.order }
    }

    /// A letter in its alphabet: `\mathbf{X}`, `\mathcal{N}`, `\boldsymbol{\beta}`.
    static func styled(_ item: InkItem) -> String {
        let latex = item.latex
        let greek = latex.hasPrefix("\\")
        switch item.style {
        case .italic: return latex
        case .roman:
            if greek { return latex }
            return latex.count == 1 && latex.first!.isASCII ? "\\mathrm{\(latex)}" : latex
        case .bold: return greek ? "\\boldsymbol{\(latex)}" : "\\mathbf{\(latex)}"
        case .boldItalic: return "\\boldsymbol{\(latex)}"
        case .calligraphic: return "\\mathcal{\(latex)}"
        case .blackboard: return "\\mathbb{\(latex)}"
        case .fraktur: return "\\mathfrak{\(latex)}"
        case .script: return "\\mathscr{\(latex)}"
        case .sans: return "\\mathsf{\(latex)}"
        case .typewriter: return "\\mathtt{\(latex)}"
        }
    }

    private static let functionWords: Set<String> = ["tr", "df", "diag", "rank", "sign", "sgn", "span", "trace", "vec", "ave", "var", "cov", "corr", "logit", "prox", "supp", "card", "conv",
                                                     "dist", "erf", "softmax", "relu", "dom", "cl", "ess", "std", "se", "sd", "med", "median", "mean", "mode", "vol", "im", "re", "id",
                                                     "lcm", "bias", "mse", "err", "argmin", "argmax", "nnz", "epi", "aff", "relint", "int", "bd", "tanh", "sech", "erfc", "sinc", "var", "odds"]

    /// A roman word: an operator TeX knows (`\log`), a function's name (`\operatorname{tr}`) or text.
    static func wordLatex(_ text: String, style: InkStyle, textItalic: Bool = false) -> (latex: String, isText: Bool) {
        if textItalic { return ("\\textit{\(text)}", true) }
        if style == .bold { return ("\\mathbf{\(text)}", false) }
        if style == .typewriter { return ("\\mathtt{\(text)}", false) }
        if FormulaSymbols.operatorNames.contains(text) { return ("\\" + text, false) }
        if text == "argmax" || text == "argmin" { return ("\\operatorname*{\(text)}", false) }
        if text == "mod" { return ("\\bmod", false) }
        let lower = text.lowercased()
        if style == .sans { return ("\\mathsf{\(text)}", false) }
        if FormulaSymbols.proseWords.contains(lower) { return ("\\text{\(text)}", true) }
        if functionWords.contains(lower) || text != lower || text.count <= 2 { return ("\\operatorname{\(text)}", false) }
        return ("\\text{\(text)}", true)
    }

    // MARK: The equation's number

    /// “(3.44)” set apart at the right (or left) of the display is the equation's number, not part of it.
    static func extractTag(_ items: [InkItem]) -> ([InkItem], String?) {
        guard items.count >= 3 else { return (items, nil) }
        let size = items.map(\.size).max() ?? 10
        let sorted = items.sorted { $0.x0 < $1.x0 }
        // From the right: “)” … “(” with only digits, letters and points between, then a wide gap.
        func tag(from run: [InkItem]) -> String? {
            guard run.count >= 3, run.first?.latex == "(", run.last?.latex == ")" else { return nil }
            let inner = run.dropFirst().dropLast()
            guard inner.count <= 8, inner.allSatisfy({ [.digit, .letter, .word].contains($0.kind) || $0.latex == "." || $0.latex == "-" || $0.kind == .prime }) else { return nil }
            guard inner.contains(where: { $0.kind == .digit }) || inner.count == 1 else { return nil }
            return "(" + inner.map { $0.plain ?? ($0.kind == .prime ? "'" : $0.latex) }.joined() + ")"
        }
        // Right side.
        if let close = sorted.last, close.latex == ")", !close.big {
            var start = sorted.count - 1
            while start > 0, sorted[start].latex != "(" || sorted[start].big { start -= 1; if sorted.count - start > 11 { break } }
            if sorted[start].latex == "(", start > 0 {
                let run = Array(sorted[start...]).filter { abs($0.y - close.y) < 0.3 * size }
                let rest = sorted[..<start]
                let gap = sorted[start].x0 - (rest.map(\.x1).max() ?? sorted[start].x0)
                if let text = tag(from: run), gap > 1.8 * size, run.count == sorted.count - start {
                    return (Array(rest), text)
                }
            }
        }
        // Left side (leqno).
        if let open = sorted.first, open.latex == "(", !open.big {
            if let end = sorted.prefix(11).firstIndex(where: { $0.latex == ")" && !$0.big }), end + 1 < sorted.count {
                let run = Array(sorted[...end])
                let gap = sorted[(end + 1)...].map(\.x0).min()! - sorted[end].x1
                if let text = tag(from: run), gap > 1.8 * size { return (Array(sorted[(end + 1)...]), text) }
            }
        }
        return (items, nil)
    }

    // MARK: Rows

    /// The rows of a display or of what tall delimiters enclose: groups of items separated by clear horizontal bands.
    /// Fraction bars and big operators bridge what is set above and below them.
    static func splitRows(_ items: [InkItem], rules: [CGRect]) -> [[InkItem]] {
        guard items.count > 1 else { return items.isEmpty ? [] : [items] }
        let mainSize = items.map(\.size).max() ?? 10
        var spans: [(bottom: CGFloat, top: CGFloat)] = items.map { ($0.bottom, $0.top) }
        for rule in rules {
            let near = items.filter { $0.x1 > rule.minX - 1 && $0.x0 < rule.maxX + 1 && abs($0.midY - rule.midY) < 1.6 * $0.size }
            guard !near.isEmpty else { continue }
            let local = near.map(\.size).max() ?? mainSize
            spans.append((rule.midY - 0.62 * local, rule.midY + 0.62 * local))
        }
        for item in items {
            if item.kind == .bigOperator { spans.append((item.bottom - 0.5 * item.size, item.top + 0.5 * item.size)) }
            if item.kind == .word, let plain = item.plain, FormulaSymbols.limitOperators.contains(plain) { spans.append((item.bottom - 0.8 * item.size, item.top)) }
        }
        spans.sort { $0.top > $1.top }
        var bands: [(bottom: CGFloat, top: CGFloat)] = []
        for span in spans {
            if var last = bands.last, span.top >= last.bottom - 0.25 {
                last.bottom = min(last.bottom, span.bottom); bands[bands.count - 1] = last
            } else { bands.append(span) }
        }
        guard bands.count > 1 else { return [items] }
        var rows = [[InkItem]](repeating: [], count: bands.count)
        for item in items {
            let index = bands.firstIndex { item.midY <= $0.top + 0.01 && item.midY >= $0.bottom - 0.01 } ?? bands.indices.min { abs(bands[$0].top - item.midY) < abs(bands[$1].top - item.midY) }!
            rows[index].append(item)
        }
        // A row of small type alone is not a row: it is set under or over its neighbour (a limit, a label).
        var merged: [[InkItem]] = []
        var mergedBands: [(bottom: CGFloat, top: CGFloat)] = []
        for (index, row) in rows.enumerated() where !row.isEmpty {
            let small = (row.map(\.size).max() ?? mainSize) < 0.82 * mainSize
            if small, !merged.isEmpty {
                // Nearest neighbour: the row above, unless the next row is closer.
                let above = mergedBands[mergedBands.count - 1].bottom - bands[index].top
                let below = index + 1 < bands.count ? bands[index].bottom - bands[index + 1].top : CGFloat.infinity
                if above <= below || index + 1 >= rows.count {
                    merged[merged.count - 1] += row
                    mergedBands[mergedBands.count - 1].bottom = min(mergedBands[mergedBands.count - 1].bottom, bands[index].bottom)
                    continue
                }
                // Otherwise it joins the next row when that one is appended.
                rows[index + 1] += row
                bands[index + 1].top = max(bands[index + 1].top, bands[index].top)
                continue
            }
            if small, merged.isEmpty, index + 1 < rows.count {
                rows[index + 1] += row; bands[index + 1].top = max(bands[index + 1].top, bands[index].top); continue
            }
            merged.append(row); mergedBands.append(bands[index])
        }
        return merged
    }

    // MARK: Layout of a region

    /// Lays out everything in a region: one line, or several rows.
    static func layout(_ source: [InkItem], rules: [CGRect], context: Context, keepPunctuation: Bool = true) -> Laid {
        guard !source.isEmpty else { return Laid(latex: "", baseline: 0, size: 10) }
        let items = attachAccents(source)
        return layoutRows(splitRows(items, rules: rules), rules: rules, context: context, keepPunctuation: keepPunctuation)
    }

    /// Lays out rows already told apart.
    static func layoutRows(_ rows: [[InkItem]], rules: [CGRect], context: Context, keepPunctuation: Bool = true) -> Laid {
        guard !rows.isEmpty else { return Laid(latex: "", baseline: 0, size: 10) }
        func rowRules(_ row: [InkItem]) -> [CGRect] {
            let top = (row.map(\.top).max() ?? 0) + 3, bottom = (row.map(\.bottom).min() ?? 0) - 3
            return rules.filter { $0.midY < top && $0.midY > bottom }
        }
        if rows.count == 1 {
            var line = layoutLine(rows[0], rules: rowRules(rows[0]))
            if !keepPunctuation { line.latex = strippingFinalPunctuation(line.latex) }
            return line
        }
        var lines = rows.map { layoutLine($0, rules: rowRules($0)) }
        if !keepPunctuation, let last = lines.indices.last { lines[last].latex = strippingFinalPunctuation(lines[last].latex) }
        let size = lines.map(\.size).max() ?? 10
        let texts = lines.map { $0.latex.trimmingCharacters(in: .whitespaces) }
        switch context {
        case .script:
            return Laid(latex: "\\substack{" + texts.joined(separator: " \\\\ ") + "}", baseline: lines[0].baseline, size: size, rows: rows.count)
        case .top, .cell:
            // Align each row at its first relation, as a multi-line display does.
            let aligned = texts.map { alignedAtRelation($0) }
            return Laid(latex: "\\begin{aligned} " + aligned.joined(separator: " \\\\ ") + " \\end{aligned}", baseline: lines[0].baseline, size: size, rows: rows.count)
        }
    }

    private static let relationPattern = try! NSRegularExpression(pattern: #" (=|<|>|\\le|\\ge|\\ne|\\equiv|\\approx|\\sim|\\simeq|\\propto|\\to|\\Rightarrow|\\Leftrightarrow|\\subseteq|\\subset|\\in|\\leftarrow|\\triangleq) "#)

    /// “a = b” → “a &= b”; a row that starts with a relation gets the mark first.
    private static func alignedAtRelation(_ row: String) -> String {
        for prefix in ["= ", "\\le ", "\\ge ", "< ", "> ", "\\approx ", "\\equiv ", "\\sim ", "\\propto "] where row.hasPrefix(prefix) { return "&" + row }
        // Only a relation outside braces aligns.
        var depth = 0
        let characters = Array(row)
        var index = 0
        while index < characters.count {
            let character = characters[index]
            if character == "{" { depth += 1 } else if character == "}" { depth -= 1 }
            if depth == 0, character == " " {
                let rest = String(characters[index..<characters.count])
                if let match = relationPattern.firstMatch(in: rest, range: NSRange(location: 0, length: min((rest as NSString).length, 24))), match.range.location == 0 {
                    return String(characters[0..<index]) + " &" + String(characters[(index + 1)..<characters.count])
                }
            }
            index += 1
        }
        return row
    }

    private static func strippingFinalPunctuation(_ latex: String) -> String {
        var text = latex.trimmingCharacters(in: .whitespaces)
        if let last = text.last, ",.;".contains(last), !text.hasSuffix("\\right.") { text.removeLast() }
        return text.trimmingCharacters(in: .whitespaces)
    }

    // MARK: Accents

    /// `\hat{\beta}`: an accent glyph set over the letter that follows it in the stream.
    static func attachAccents(_ items: [InkItem]) -> [InkItem] {
        guard items.contains(where: { $0.kind == .accent && !$0.isText }) else { return items }
        var result = items
        var removed = Set<Int>()
        for (index, accent) in items.enumerated() where accent.kind == .accent && !accent.isText {
            let wide = accent.latex.hasPrefix("wide")
            // Bases: letters and structures under the accent's extent.
            let candidates = items.indices.filter { other in
                guard other != index, !removed.contains(other) else { return false }
                let item = result[other]
                guard item.kind != .accent, item.kind != .piece else { return false }
                guard item.midX > accent.x0 - 0.12 * accent.size, item.midX < accent.x1 + 0.12 * accent.size else { return false }
                // The base sits at or just below the accent's own baseline.
                return item.y <= accent.y + 0.12 * accent.size && item.y >= accent.y - 0.75 * accent.size && item.top <= accent.top + 0.2 * accent.size
            }
            guard !candidates.isEmpty else { continue }
            let chosen: [Int]
            if wide { chosen = candidates.sorted { result[$0].x0 < result[$1].x0 } }
            else {
                // The letter whose centre is nearest the accent's.
                chosen = [candidates.min { abs(result[$0].midX - accent.midX) < abs(result[$1].midX - accent.midX) }!]
            }
            let bases = chosen.map { result[$0] }
            let inner: String
            if bases.count == 1 {
                // Dotless i and j lose their name under an accent.
                inner = bases[0].latex == "\\imath" ? "i" : bases[0].latex == "\\jmath" ? "j" : bases[0].latex
            } else {
                inner = layoutLine(bases, rules: []).latex
            }
            var merged = bases[0]
            merged.latex = "\\\(accent.latex){\(inner)}"
            merged.x0 = min(bases.map(\.x0).min()!, accent.x0); merged.x1 = max(bases.map(\.x1).max()!, bases.count > 1 ? accent.x1 : bases[0].x1)
            merged.top = max(accent.top, bases.map(\.top).max()!); merged.bottom = bases.map(\.bottom).min()!
            merged.kind = bases.count == 1 && bases[0].kind == .letter ? .letter : .structure
            merged.plain = nil
            result[chosen[0]] = merged
            removed.insert(index)
            for other in chosen.dropFirst() { removed.insert(other) }
        }
        return result.enumerated().filter { !removed.contains($0.offset) }.map(\.element)
    }

    // MARK: One line

    /// Lays out the items of one row: tall delimiters and what they enclose, fractions and radicals, limits, scripts.
    static func layoutLine(_ source: [InkItem], rules: [CGRect]) -> Laid {
        guard !source.isEmpty else { return Laid(latex: "", baseline: 0, size: 10) }
        var items = source
        var rules = rules
        items = buildMatrices(items, rules: &rules)
        items = buildRuleStructures(items, rules: rules)
        items = buildLimits(items)
        return assemble(items)
    }

    // MARK: Matrices, cases and binomials

    /// Rows between tall delimiters are a matrix; rows after a tall left brace are cases.
    private static func buildMatrices(_ source: [InkItem], rules: inout [CGRect]) -> [InkItem] {
        var items = source.sorted { $0.x0 < $1.x0 }
        var changed = true
        var guardCount = 0
        while changed, guardCount < 12 {
            changed = false; guardCount += 1
            // Pair tall delimiters, innermost first.
            var stack: [Int] = []
            var pair: (Int, Int)?
            for (index, item) in items.enumerated() where item.big && item.height > 1.7 * item.size {
                if item.kind == .open { stack.append(index) }
                else if item.kind == .close, let open = stack.popLast() { pair = (open, index); break }
                else if item.kind == .bar {
                    if let open = stack.last, items[open].kind == .bar, abs(items[open].height - item.height) < 0.3 * item.size { stack.removeLast(); pair = (open, index); break }
                    stack.append(index)
                }
            }
            if let (openIndex, closeIndex) = pair {
                let open = items[openIndex], close = items[closeIndex]
                let inside = items.indices.filter { $0 != openIndex && $0 != closeIndex && items[$0].midX > open.x1 - 0.5 && items[$0].midX < close.x0 + 0.5
                    && items[$0].midY < max(open.top, close.top) + 0.3 * open.size && items[$0].midY > min(open.bottom, close.bottom) - 0.3 * open.size }
                let enclosed = inside.map { items[$0] }
                let innerRules = rules.filter { $0.midX > open.x1 && $0.midX < close.x0 && $0.midY < open.top + 2 && $0.midY > open.bottom - 2 }
                let rows = splitRows(enclosed, rules: innerRules)
                if rows.count >= 2 {
                    let body = grid(rows, rules: innerRules)
                    let latex: String
                    if open.latex == "(", close.latex == ")", body.columns == 1, rows.count == 2 {
                        latex = "\\binom{\(body.cells[0][0])}{\(body.cells[1][0])}"
                    } else {
                        let environment: String
                        switch (open.latex, close.latex) {
                        case ("(", ")"): environment = "pmatrix"
                        case ("[", "]"): environment = "bmatrix"
                        case ("\\{", "\\}"): environment = "Bmatrix"
                        case ("|", "|"): environment = "vmatrix"
                        case ("\\|", "\\|"): environment = "Vmatrix"
                        default: environment = "matrix"
                        }
                        let rowsText = body.cells.map { $0.joined(separator: " & ") }.joined(separator: " \\\\ ")
                        latex = environment == "matrix"
                            ? "\\left\(open.latex) \\begin{matrix} \(rowsText) \\end{matrix} \\right\(close.latex)"
                            : "\\begin{\(environment)} \(rowsText) \\end{\(environment)}"
                    }
                    let structure = InkItem.structure(latex, covering: enclosed + [open, close], axis: (open.top + open.bottom) / 2, size: open.size)
                    let removed = Set(inside + [openIndex, closeIndex])
                    items = items.enumerated().filter { !removed.contains($0.offset) }.map(\.element) + [structure]
                    items.sort { $0.x0 < $1.x0 }
                    rules.removeAll { innerRules.contains($0) }
                    changed = true
                    continue
                }
                // One row: an ordinary bracketed group. Mark the pair so it is not paired again.
                items[openIndex].big = false; items[closeIndex].big = false
                items[openIndex].latex = "\\left" + open.latex; items[closeIndex].latex = "\\right" + close.latex
                changed = true
                continue
            }
            // A tall left brace with nothing closing it: cases.
            if let braceIndex = items.firstIndex(where: { $0.big && $0.kind == .open && $0.latex == "\\{" && $0.height > 1.7 * $0.size }) {
                let brace = items[braceIndex]
                let inside = items.indices.filter { $0 != braceIndex && items[$0].x0 > brace.x1 - 0.5 && items[$0].midY < brace.top + 0.3 * brace.size && items[$0].midY > brace.bottom - 0.3 * brace.size }
                let enclosed = inside.map { items[$0] }
                let innerRules = rules.filter { $0.midX > brace.x1 && $0.midY < brace.top + 2 && $0.midY > brace.bottom - 2 }
                let rows = splitRows(enclosed, rules: innerRules)
                if rows.count >= 2 {
                    let body = grid(rows, rules: innerRules)
                    let rowsText = body.cells.map { $0.joined(separator: " & ") }.joined(separator: " \\\\ ")
                    let structure = InkItem.structure("\\begin{cases} \(rowsText) \\end{cases}", covering: enclosed + [brace], axis: (brace.top + brace.bottom) / 2, size: brace.size)
                    let removed = Set(inside + [braceIndex])
                    items = items.enumerated().filter { !removed.contains($0.offset) }.map(\.element) + [structure]
                    items.sort { $0.x0 < $1.x0 }
                    rules.removeAll { innerRules.contains($0) }
                    changed = true
                } else {
                    items[braceIndex].big = false; items[braceIndex].latex = "\\left\\{"
                    // A lone \left needs its \right.
                    var closer = InkItem(x0: (enclosed.map(\.x1).max() ?? brace.x1), x1: (enclosed.map(\.x1).max() ?? brace.x1), y: brace.y, top: brace.top, bottom: brace.bottom, size: brace.size, kind: .close, latex: "\\right.")
                    closer.centred = true; closer.order = Int.max
                    items.append(closer); items.sort { $0.x0 < $1.x0 }
                    changed = true
                }
            }
        }
        return items
    }

    /// The cells of rows: columns are separated by gaps clear in every row.
    private static func grid(_ rows: [[InkItem]], rules: [CGRect]) -> (cells: [[String]], columns: Int) {
        let all = rows.flatMap { $0 }
        let size = all.map(\.size).max() ?? 10
        // Project every item on the x axis and find the clear gaps.
        var intervals = all.map { ($0.x0, $0.x1) }.sorted { $0.0 < $1.0 }
        var blocks: [(CGFloat, CGFloat)] = []
        for interval in intervals {
            if var last = blocks.last, interval.0 <= last.1 + 0.55 * size { last.1 = max(last.1, interval.1); blocks[blocks.count - 1] = last }
            else { blocks.append(interval) }
        }
        intervals.removeAll()
        var cells: [[String]] = []
        for row in rows {
            var texts: [String] = []
            for block in blocks {
                let members = row.filter { $0.midX >= block.0 - 0.01 && $0.midX <= block.1 + 0.01 }
                let cellRules = rules.filter { $0.midX >= block.0 - 1 && $0.midX <= block.1 + 1 && members.contains { abs($0.midY - $0.midY) < 1 } }
                texts.append(members.isEmpty ? "" : layout(members, rules: cellRules.filter { rule in members.contains { $0.bottom - 12 < rule.midY && $0.top + 12 > rule.midY } }, context: .cell).latex.trimmingCharacters(in: .whitespaces))
            }
            cells.append(texts)
        }
        return (cells, blocks.count)
    }

    // MARK: Fractions, radicals, overlines

    /// A rule with glyphs above and below it is a fraction; one beside a radical sign covers its radicand;
    /// one above glyphs alone is an overline.
    private static func buildRuleStructures(_ source: [InkItem], rules: [CGRect]) -> [InkItem] {
        var items = source
        var remaining = rules.sorted { $0.width > $1.width }
        while !remaining.isEmpty {
            let rule = remaining.removeFirst()
            // Items in the rule's column.
            let column = items.indices.filter { items[$0].midX > rule.minX - 0.6 && items[$0].midX < rule.maxX + 0.6 && !(items[$0].kind == .radical) }
            guard !column.isEmpty else { continue }
            let above = column.filter { items[$0].midY > rule.midY }
            let below = column.filter { items[$0].midY <= rule.midY }
            let aboveItems = above.map { items[$0] }, belowItems = below.map { items[$0] }
            func inner(_ members: [InkItem]) -> [CGRect] {
                remaining.filter { other in other.minX >= rule.minX - 1 && other.maxX <= rule.maxX + 1 && members.contains { $0.bottom - 14 < other.midY && $0.top + 14 > other.midY } }
            }
            // A radical: its sign ends where the rule begins, at the rule's height.
            if let radicalIndex = items.firstIndex(where: { $0.kind == .radical && abs($0.x1 - rule.minX) < 0.2 * $0.size + 1.2 && abs($0.top - rule.midY) < 0.25 * $0.size + 1 }) {
                let radical = items[radicalIndex]
                let body = belowItems.filter { $0.midY > radical.bottom - 0.3 * radical.size }
                guard !body.isEmpty else { continue }
                let bodyRules = inner(body)
                let laid = layout(body, rules: bodyRules, context: .cell)
                remaining.removeAll { bodyRules.contains($0) }
                // An index sits small, raised, over the sign's left part.
                let indexItems = items.indices.filter { other in
                    let item = items[other]
                    return other != radicalIndex && item.size < 0.8 * laid.size && item.midX > radical.x0 - 0.5 * radical.size && item.midX < radical.x0 + 0.62 * radical.width
                        && item.y > laid.baseline + 0.15 * laid.size && item.kind != .radical
                }
                let indexText = indexItems.isEmpty ? "" : "[" + layout(indexItems.map { items[$0] }, rules: [], context: .script).latex + "]"
                let bodySet = Set(body.map(\.order))
                var structure = InkItem.structure("\\sqrt\(indexText){\(laid.latex)}", covering: body + [radical] + indexItems.map { items[$0] }, baseline: laid.baseline, size: laid.size, extra: rule)
                structure.centred = false
                let removed = Set(below.filter { bodySet.contains(items[$0].order) } + [radicalIndex] + indexItems)
                items = items.enumerated().filter { !removed.contains($0.offset) }.map(\.element) + [structure]
                continue
            }
            if !above.isEmpty, !below.isEmpty {
                let numeratorRules = inner(aboveItems), denominatorRules = inner(belowItems)
                let numerator = layout(aboveItems, rules: numeratorRules, context: .cell)
                let denominator = layout(belowItems, rules: denominatorRules, context: .cell)
                remaining.removeAll { numeratorRules.contains($0) || denominatorRules.contains($0) }
                let size = max(numerator.size, denominator.size)
                let structure = InkItem.structure("\\frac{\(numerator.latex)}{\(denominator.latex)}", covering: aboveItems + belowItems, axis: rule.midY, size: size, extra: rule)
                let removed = Set(above + below)
                items = items.enumerated().filter { !removed.contains($0.offset) }.map(\.element) + [structure]
                continue
            }
            if !below.isEmpty {
                // An overline: only what sits just under the rule.
                let near = belowItems.filter { $0.top > rule.midY - 1.5 * $0.size }
                guard !near.isEmpty else { continue }
                let nearRules = inner(near)
                let laid = layout(near, rules: nearRules, context: .cell)
                remaining.removeAll { nearRules.contains($0) }
                let nearSet = Set(near.map(\.order))
                var structure = InkItem.structure("\\overline{\(laid.latex)}", covering: near, baseline: laid.baseline, size: laid.size, extra: rule)
                structure.centred = false
                let removed = Set(below.filter { nearSet.contains(items[$0].order) })
                items = items.enumerated().filter { !removed.contains($0.offset) }.map(\.element) + [structure]
                continue
            }
            if !above.isEmpty {
                let near = aboveItems.filter { $0.bottom < rule.midY + 1.2 * $0.size }
                guard !near.isEmpty else { continue }
                let laid = layout(near, rules: inner(near), context: .cell)
                let nearSet = Set(near.map(\.order))
                var structure = InkItem.structure("\\underline{\(laid.latex)}", covering: near, baseline: laid.baseline, size: laid.size, extra: rule)
                structure.centred = false
                let removed = Set(above.filter { nearSet.contains(items[$0].order) })
                items = items.enumerated().filter { !removed.contains($0.offset) }.map(\.element) + [structure]
            }
        }
        return items
    }

    // MARK: Limits

    /// Small glyphs centred under or over a big operator (or a word such as “max”) are its limits.
    private static func buildLimits(_ source: [InkItem]) -> [InkItem] {
        var items = source
        var index = 0
        while index < items.count {
            let op = items[index]
            let isWord = op.kind == .word && op.plain.map(FormulaSymbols.limitOperators.contains) == true
            guard op.kind == .bigOperator || isWord else { index += 1; continue }
            func cluster(below: Bool) -> [Int] {
                // Seeds: small items centred in the operator's width, wholly below (or above) it.
                var members = items.indices.filter { other in
                    guard other != index else { return false }
                    let item = items[other]
                    guard item.size < 0.85 * op.size || item.kind == .structure && item.size <= op.size else { return false }
                    guard item.midX > op.x0 - 0.15 * op.size, item.midX < op.x1 + 0.15 * op.size else { return false }
                    return below ? item.top < op.bottom + 0.35 * op.size && item.top > op.bottom - 1.6 * op.size
                                 : item.bottom > op.top - 0.35 * op.size && item.bottom < op.top + 1.6 * op.size
                }
                guard !members.isEmpty else { return [] }
                // Grow sideways: a limit can be wider than its operator.
                var grew = true
                while grew {
                    grew = false
                    let x0 = members.map { items[$0].x0 }.min()!, x1 = members.map { items[$0].x1 }.max()!
                    let top = members.map { items[$0].top }.max()!, bottom = members.map { items[$0].bottom }.min()!
                    let scale = members.map { items[$0].size }.max()!
                    for other in items.indices where other != index && !members.contains(other) {
                        let item = items[other]
                        guard item.size < 0.85 * op.size, item.x1 > x0 - 0.45 * scale, item.x0 < x1 + 0.45 * scale else { continue }
                        guard item.midY < top + 0.5 * scale, item.midY > bottom - 0.5 * scale else { continue }
                        guard below ? item.top < op.bottom + 0.35 * op.size : item.bottom > op.top - 0.35 * op.size else { continue }
                        members.append(other); grew = true
                    }
                }
                return members
            }
            let lower = cluster(below: true)
            let upper = isWord ? [] : cluster(below: false).filter { !lower.contains($0) }
            guard !lower.isEmpty || !upper.isEmpty else { index += 1; continue }
            var latex = op.latex
            if !lower.isEmpty { latex += "_{" + layout(lower.map { items[$0] }, rules: [], context: .script).latex + "}" }
            if !upper.isEmpty { latex += "^{" + layout(upper.map { items[$0] }, rules: [], context: .script).latex + "}" }
            var structure = op
            structure.latex = latex
            let members = (lower + upper).map { items[$0] }
            structure.x0 = min(op.x0, members.map(\.x0).min() ?? op.x0); structure.x1 = max(op.x1, members.map(\.x1).max() ?? op.x1)
            structure.top = max(op.top, members.map(\.top).max() ?? op.top); structure.bottom = min(op.bottom, members.map(\.bottom).min() ?? op.bottom)
            structure.kind = .structure
            let removed = Set(lower + upper + [index])
            items = items.enumerated().filter { !removed.contains($0.offset) }.map(\.element) + [structure]
            index = 0
        }
        return items
    }

    // MARK: Scripts and assembly

    private struct Piece {
        var latex: String
        var kind: InkKind
        var x0: CGFloat
        var x1: CGFloat
        var isText: Bool
        var size: CGFloat
    }

    /// The items of one line in reading order, with raised and lowered items attached as scripts.
    static func assemble(_ source: [InkItem]) -> Laid {
        let items = source.sorted { $0.x0 == $1.x0 ? $0.order < $1.order : $0.x0 < $1.x0 }
        guard !items.isEmpty else { return Laid(latex: "", baseline: 0, size: 10) }
        // The line's size: its largest type. Tall delimiters and operators come in one size and do not say.
        let sized = items.filter { !$0.centred || $0.kind == .structure }
        let size = (sized.isEmpty ? items : sized).map(\.size).max() ?? 10
        // The line's baseline: that of its first full-size item that sits on a baseline.
        let full = items.filter { $0.size >= 0.9 * size && !$0.centred }
        var baseline: CGFloat
        if let first = full.first {
            baseline = first.y
            // Unless most of the line disagrees (the first item may be a stray).
            let agree = full.filter { abs($0.y - baseline) <= 0.1 * size }.count
            if agree * 3 < full.count, let common = mostCommonBaseline(full, size: size) { baseline = common }
        } else {
            let centred = items.filter { $0.size >= 0.9 * size }
            baseline = (centred.first ?? items[0]).y
        }
        func level(_ item: InkItem) -> Int {
            if item.centred {
                // Centred on the axis of this line?
                let axis = item.y + axisHeight * item.size
                let lineAxis = baseline + axisHeight * size
                if abs(axis - lineAxis) <= 0.3 * size || (item.top > lineAxis && item.bottom < lineAxis && item.height > 1.1 * size) { return 0 }
                return axis > lineAxis ? 1 : -1
            }
            let offset = item.y - baseline
            if abs(offset) <= 0.1 * size { return 0 }
            return offset > 0 ? 1 : -1
        }
        var pieces: [Piece] = []
        var sup: [InkItem] = [], sub: [InkItem] = []
        var baseX1: CGFloat = -.infinity
        func flush() {
            guard !sup.isEmpty || !sub.isEmpty else { return }
            var suffix = ""
            var over = "", under = ""
            let hasBase = !pieces.isEmpty
            let base = pieces.last
            if !sub.isEmpty {
                let laid = layout(sub, rules: [], context: .script)
                // Centred under its base rather than after it: an underset.
                let x0 = sub.map(\.x0).min()!, x1 = sub.map(\.x1).max()!
                if let base, base.kind != .structure, x0 < base.x1 - 0.3 * (x1 - x0) - 0.5, x1 - x0 > 0.2 * size, base.kind == .relation || base.kind == .word || base.kind == .letter { under = laid.latex }
                else { suffix += "_" + scriptArgument(laid.latex) }
            }
            if !sup.isEmpty {
                if sup.allSatisfy({ $0.kind == .prime }) {
                    suffix += String(repeating: "'", count: sup.reduce(0) { $0 + ($1.latex == "\\prime\\prime" ? 2 : 1) })
                } else {
                    let laid = layout(sup, rules: [], context: .script)
                    let x0 = sup.map(\.x0).min()!, x1 = sup.map(\.x1).max()!
                    if let base, base.kind != .structure, x0 < base.x1 - 0.3 * (x1 - x0) - 0.5, x1 - x0 > 0.2 * size, base.kind == .relation || base.kind == .word { over = laid.latex }
                    else { suffix += "^" + scriptArgument(laid.latex) }
                }
            }
            if !hasBase { pieces.append(Piece(latex: "{}", kind: .ordinary, x0: (sup + sub).map(\.x0).min()!, x1: (sup + sub).map(\.x0).min()!, isText: false, size: size)) }
            var last = pieces[pieces.count - 1]
            if !over.isEmpty { last.latex = "\\overset{\(over)}{\(last.latex)}" }
            if !under.isEmpty { last.latex = "\\underset{\(under)}{\(last.latex)}" }
            // A script on a text word binds to the whole word in braces.
            last.latex += suffix
            last.x1 = max(last.x1, (sup + sub).map(\.x1).max()!)
            pieces[pieces.count - 1] = last
            sup = []; sub = []
        }
        for item in items {
            switch level(item) {
            case 0:
                flush()
                pieces.append(Piece(latex: item.latex, kind: item.kind, x0: item.x0, x1: item.x1, isText: item.isText, size: item.size))
                baseX1 = item.x1
            case 1: sup.append(item)
            default: sub.append(item)
            }
        }
        flush()
        _ = baseX1
        return Laid(latex: join(pieces, size: size), baseline: baseline, size: size)
    }

    private static func mostCommonBaseline(_ items: [InkItem], size: CGFloat) -> CGFloat? {
        var best: (CGFloat, Int)?
        for item in items {
            let count = items.filter { abs($0.y - item.y) <= 0.1 * size }.count
            if best == nil || count > best!.1 { best = (item.y, count) }
        }
        return best?.0
    }

    /// `x^2`, `x_i`, `x^{-1}`, `x_{ij}`: braces unless the script is one letter or digit.
    private static func scriptArgument(_ latex: String) -> String {
        let text = latex.trimmingCharacters(in: .whitespaces)
        if text.count == 1, let c = text.first, c.isASCII, c.isLetter || c.isNumber { return text }
        return "{\(text)}"
    }

    private static let endsWithControlWord = try! NSRegularExpression(pattern: #"\\[A-Za-z]+$"#)

    /// Joins the pieces of a line with the spacing LaTeX source is written with.
    private static func join(_ pieces: [Piece], size: CGFloat) -> String {
        var out = ""
        var previous: Piece?
        var textRun: [Piece] = []
        func flushText() {
            guard !textRun.isEmpty else { return }
            // Consecutive words of prose become one \text{…}.
            var words: [String] = []
            for piece in textRun {
                let inner = piece.latex.hasPrefix("\\text{") && piece.latex.hasSuffix("}") ? String(piece.latex.dropFirst(6).dropLast()) : piece.latex
                words.append(inner)
            }
            let text = "\\text{" + words.joined(separator: " ") + "}"
            if !out.isEmpty, !out.hasSuffix(" ") { out += " " }
            out += text + " "
            textRun = []
        }
        for piece in pieces {
            let plainText = piece.isText && piece.latex.hasPrefix("\\text{") && piece.latex.hasSuffix("}") && !piece.latex.dropFirst(6).dropLast().contains("}")
            if plainText {
                if let last = textRun.last, piece.x0 - last.x1 > 1.2 * size { flushText() }
                else if textRun.isEmpty, let previous, piece.x0 - previous.x1 > 0.9 * size { out = out.trimmingCharacters(in: .whitespaces) + " \\quad " }
                textRun.append(piece); previous = piece; continue
            }
            let hadText = !textRun.isEmpty
            flushText()
            if let previous, !hadText || true {
                let gap = piece.x0 - previous.x1
                if gap > 1.9 * size { out = out.trimmingCharacters(in: .whitespaces) + " \\qquad " }
                else if gap > 0.9 * size { out = out.trimmingCharacters(in: .whitespaces) + " \\quad " }
            }
            switch piece.kind {
            case .relation:
                out = out.trimmingCharacters(in: .whitespaces) + (out.isEmpty ? "" : " ") + piece.latex + " "
            case .binary:
                let unary = previous == nil || [.relation, .binary, .open, .punctuation].contains(previous!.kind) || previous!.latex.hasSuffix("\\left(") || previous!.latex.hasSuffix("\\left[") || previous!.latex.hasSuffix("\\left\\{")
                if unary { out += piece.latex + (needsSpace(after: piece.latex) ? " " : "") }
                else { out = out.trimmingCharacters(in: .whitespaces) + " " + piece.latex + " " }
            case .punctuation:
                out = out.trimmingCharacters(in: .whitespaces) + piece.latex + " "
            default:
                if needsSeparator(out, piece.latex) { out += " " }
                out += piece.latex
            }
            previous = piece
        }
        flushText()
        return out.trimmingCharacters(in: .whitespaces)
    }

    private static func needsSpace(after latex: String) -> Bool {
        endsWithControlWord.firstMatch(in: latex, range: NSRange(location: 0, length: (latex as NSString).length)) != nil
    }

    /// A control word must not run into a following letter: `\lambda x`, not `\lambdax`.
    private static func needsSeparator(_ out: String, _ next: String) -> Bool {
        guard let first = next.first, first.isLetter, first.isASCII else { return false }
        return endsWithControlWord.firstMatch(in: out, range: NSRange(location: 0, length: (out as NSString).length)) != nil
    }
}
