//
//  PageInk.swift · what a page draws: every glyph with its font, size and position, and every rule.
//
//  PDFKit's text layer flattens mathematics: “β̂ridge = (XT X + λI)−1XT y” says nothing of what is raised,
//  what is a fraction or which sum a limit belongs to. The page's content stream says all of it: glyph names
//  (“summationdisplay”, “parenleftbig”), the font of each glyph (CMMI7 is a script), its exact baseline, and
//  the rules that are fraction bars and radical signs. `PageInkScanner` reads them; `FormulaReader` turns a
//  region of them back into LaTeX.
//

import CoreGraphics
import Foundation
import PDFKit

/// One glyph as the page's content stream shows it.
public struct InkGlyph: Equatable, Sendable {
    /// The character code in the font.
    public var code: UInt32
    /// The glyph's name in the font's encoding (“beta”, “summationdisplay”), when the font names its glyphs.
    public var name: String?
    /// The glyph's Unicode text, when the font gives one (empty otherwise).
    public var text: String
    /// The font's name without its subset prefix (“CMMI10”).
    public var font: String
    /// The em size on the page, in points.
    public var size: CGFloat
    /// The glyph's origin on its baseline, in page space.
    public var x: CGFloat
    public var y: CGFloat
    /// The advance width on the page.
    public var width: CGFloat
    /// The glyph's position in the content stream.
    public var order: Int

    public init(code: UInt32 = 0, name: String? = nil, text: String = "", font: String, size: CGFloat, x: CGFloat, y: CGFloat, width: CGFloat, order: Int = 0) {
        self.code = code; self.name = name; self.text = text; self.font = font; self.size = size
        self.x = x; self.y = y; self.width = width; self.order = order
    }

    public var maxX: CGFloat { x + width }
    public var midX: CGFloat { x + width / 2 }
    /// The font's family: its name in capitals without the design size (“CMMI”).
    public var family: String { InkGlyph.family(of: font) }

    public static func family(of font: String) -> String {
        var name = font.uppercased()
        while let last = name.last, last.isNumber { name.removeLast() }
        return name
    }
}

/// A thin filled rectangle or stroked segment: a fraction bar, the bar of a radical, an overline, a table rule.
public struct InkRule: Equatable, Sendable {
    public var rect: CGRect
    public init(_ rect: CGRect) { self.rect = rect }
    public var isHorizontal: Bool { rect.width >= rect.height }
}

/// The glyphs and rules of one page, in page space.
public struct PageInk: Equatable, Sendable {
    public var glyphs: [InkGlyph] = []
    public var rules: [InkRule] = []
    public init(glyphs: [InkGlyph] = [], rules: [InkRule] = []) { self.glyphs = glyphs; self.rules = rules }

    /// The ink whose glyph origins (and rule centres) lie in a rectangle.
    public func clipped(to rect: CGRect) -> PageInk {
        PageInk(glyphs: glyphs.filter { rect.contains(CGPoint(x: $0.midX, y: $0.y + $0.size * 0.2)) },
                rules: rules.filter { rect.insetBy(dx: -1, dy: -1).contains(CGPoint(x: $0.rect.midX, y: $0.rect.midY)) })
    }
}

/// Fonts decoded once per document: a book's pages share their font dictionaries.
public final class InkFontCache {
    fileprivate var fonts: [Int: EmphasisFontInfo] = [:]
    public init() {}
}

public enum PageInkScanner {
    /// Every glyph and rule of a page. Pass one `cache` for all the pages of a document.
    public static func scan(_ page: PDFPage, cache: InkFontCache? = nil) -> PageInk {
        guard let cgPage = page.pageRef else { return PageInk() }
        return scan(cgPage, cache: cache)
    }

    public static func scan(_ page: CGPDFPage, cache: InkFontCache? = nil) -> PageInk {
        let context = InkScanContext(cache: cache ?? InkFontCache())
        context.scan(page)
        return PageInk(glyphs: context.glyphs, rules: context.rules)
    }
}

// MARK: - Content-stream scanning

final class InkScanContext {
    private struct State {
        var ctm = CGAffineTransform.identity
        var font: EmphasisFontInfo?
        var fontSize: CGFloat = 0
        var charSpacing: CGFloat = 0
        var wordSpacing: CGFloat = 0
        var horizontalScale: CGFloat = 1
        var leading: CGFloat = 0
        var rise: CGFloat = 0
        var lineWidth: CGFloat = 1
    }

    private let cache: InkFontCache
    private var state = State()
    private var stack: [State] = []
    private var textMatrix = CGAffineTransform.identity
    private var lineMatrix = CGAffineTransform.identity
    private var table: CGPDFOperatorTableRef?
    private var formDepth = 0
    private var pendingRects: [CGRect] = []
    private var segments: [(CGPoint, CGPoint)] = []
    private var current: CGPoint?
    private(set) var glyphs: [InkGlyph] = []
    private(set) var rules: [InkRule] = []

    init(cache: InkFontCache) { self.cache = cache }

    func scan(_ page: CGPDFPage) {
        guard let table = Self.makeOperatorTable() else { return }
        self.table = table
        let stream = CGPDFContentStreamCreateWithPage(page)
        let scanner = CGPDFScannerCreate(stream, table, Unmanaged.passUnretained(self).toOpaque())
        CGPDFScannerScan(scanner)
        CGPDFScannerRelease(scanner)
        CGPDFContentStreamRelease(stream)
        CGPDFOperatorTableRelease(table)
        self.table = nil
    }

    private static func context(_ info: UnsafeMutableRawPointer?) -> InkScanContext? {
        info.map { Unmanaged<InkScanContext>.fromOpaque($0).takeUnretainedValue() }
    }

    private static func numbers(_ scanner: CGPDFScannerRef, _ count: Int) -> [CGFloat]? {
        var values = [CGPDFReal](repeating: 0, count: count)
        for i in stride(from: count - 1, through: 0, by: -1) { guard CGPDFScannerPopNumber(scanner, &values[i]) else { return nil } }
        return values
    }

    private static func makeOperatorTable() -> CGPDFOperatorTableRef? {
        guard let table = CGPDFOperatorTableCreate() else { return nil }
        CGPDFOperatorTableSetCallback(table, "q") { _, info in
            guard let c = InkScanContext.context(info) else { return }; c.stack.append(c.state)
        }
        CGPDFOperatorTableSetCallback(table, "Q") { _, info in
            guard let c = InkScanContext.context(info) else { return }; if let s = c.stack.popLast() { c.state = s }
        }
        CGPDFOperatorTableSetCallback(table, "cm") { scanner, info in
            guard let c = InkScanContext.context(info), let v = InkScanContext.numbers(scanner, 6) else { return }
            c.state.ctm = CGAffineTransform(a: v[0], b: v[1], c: v[2], d: v[3], tx: v[4], ty: v[5]).concatenating(c.state.ctm)
        }
        CGPDFOperatorTableSetCallback(table, "BT") { _, info in
            guard let c = InkScanContext.context(info) else { return }
            c.textMatrix = .identity; c.lineMatrix = .identity
        }
        CGPDFOperatorTableSetCallback(table, "Tf") { scanner, info in
            guard let c = InkScanContext.context(info) else { return }
            var size: CGPDFReal = 0
            var name: UnsafePointer<Int8>?
            guard CGPDFScannerPopNumber(scanner, &size), CGPDFScannerPopName(scanner, &name), let name else { return }
            c.state.fontSize = size
            c.state.font = c.font(named: name, scanner: scanner)
        }
        CGPDFOperatorTableSetCallback(table, "Tc") { scanner, info in
            guard let c = InkScanContext.context(info), let v = InkScanContext.numbers(scanner, 1) else { return }; c.state.charSpacing = v[0]
        }
        CGPDFOperatorTableSetCallback(table, "Tw") { scanner, info in
            guard let c = InkScanContext.context(info), let v = InkScanContext.numbers(scanner, 1) else { return }; c.state.wordSpacing = v[0]
        }
        CGPDFOperatorTableSetCallback(table, "Tz") { scanner, info in
            guard let c = InkScanContext.context(info), let v = InkScanContext.numbers(scanner, 1) else { return }; c.state.horizontalScale = v[0] / 100
        }
        CGPDFOperatorTableSetCallback(table, "TL") { scanner, info in
            guard let c = InkScanContext.context(info), let v = InkScanContext.numbers(scanner, 1) else { return }; c.state.leading = v[0]
        }
        CGPDFOperatorTableSetCallback(table, "Ts") { scanner, info in
            guard let c = InkScanContext.context(info), let v = InkScanContext.numbers(scanner, 1) else { return }; c.state.rise = v[0]
        }
        CGPDFOperatorTableSetCallback(table, "Td") { scanner, info in
            guard let c = InkScanContext.context(info), let v = InkScanContext.numbers(scanner, 2) else { return }; c.moveLine(v[0], v[1])
        }
        CGPDFOperatorTableSetCallback(table, "TD") { scanner, info in
            guard let c = InkScanContext.context(info), let v = InkScanContext.numbers(scanner, 2) else { return }
            c.state.leading = -v[1]; c.moveLine(v[0], v[1])
        }
        CGPDFOperatorTableSetCallback(table, "Tm") { scanner, info in
            guard let c = InkScanContext.context(info), let v = InkScanContext.numbers(scanner, 6) else { return }
            c.lineMatrix = CGAffineTransform(a: v[0], b: v[1], c: v[2], d: v[3], tx: v[4], ty: v[5])
            c.textMatrix = c.lineMatrix
        }
        CGPDFOperatorTableSetCallback(table, "T*") { _, info in
            guard let c = InkScanContext.context(info) else { return }; c.moveLine(0, -c.state.leading)
        }
        CGPDFOperatorTableSetCallback(table, "Tj") { scanner, info in
            guard let c = InkScanContext.context(info) else { return }
            var string: CGPDFStringRef?
            guard CGPDFScannerPopString(scanner, &string), let string else { return }
            c.show(string)
        }
        CGPDFOperatorTableSetCallback(table, "'") { scanner, info in
            guard let c = InkScanContext.context(info) else { return }
            var string: CGPDFStringRef?
            guard CGPDFScannerPopString(scanner, &string), let string else { return }
            c.moveLine(0, -c.state.leading); c.show(string)
        }
        CGPDFOperatorTableSetCallback(table, "\"") { scanner, info in
            guard let c = InkScanContext.context(info) else { return }
            var string: CGPDFStringRef?
            guard CGPDFScannerPopString(scanner, &string), let string, let v = InkScanContext.numbers(scanner, 2) else { return }
            c.state.wordSpacing = v[0]; c.state.charSpacing = v[1]
            c.moveLine(0, -c.state.leading); c.show(string)
        }
        CGPDFOperatorTableSetCallback(table, "TJ") { scanner, info in
            guard let c = InkScanContext.context(info) else { return }
            var array: CGPDFArrayRef?
            guard CGPDFScannerPopArray(scanner, &array), let array else { return }
            c.showArray(array)
        }
        CGPDFOperatorTableSetCallback(table, "Do") { scanner, info in
            guard let c = InkScanContext.context(info) else { return }
            var name: UnsafePointer<Int8>?
            guard CGPDFScannerPopName(scanner, &name), let name else { return }
            c.invokeXObject(named: name, scanner: scanner)
        }
        // Rules: filled rectangles (pdfTeX, dvips) and stroked segments (xdvipdfmx).
        CGPDFOperatorTableSetCallback(table, "w") { scanner, info in
            guard let c = InkScanContext.context(info), let v = InkScanContext.numbers(scanner, 1) else { return }; c.state.lineWidth = v[0]
        }
        CGPDFOperatorTableSetCallback(table, "re") { scanner, info in
            guard let c = InkScanContext.context(info), let v = InkScanContext.numbers(scanner, 4) else { return }
            let rect = CGRect(x: v[0], y: v[1], width: v[2], height: v[3]).standardized.applying(c.state.ctm)
            if rect.width.isFinite, rect.height.isFinite { c.pendingRects.append(rect) }
        }
        CGPDFOperatorTableSetCallback(table, "m") { scanner, info in
            guard let c = InkScanContext.context(info), let v = InkScanContext.numbers(scanner, 2) else { return }
            c.current = CGPoint(x: v[0], y: v[1]).applying(c.state.ctm)
        }
        CGPDFOperatorTableSetCallback(table, "l") { scanner, info in
            guard let c = InkScanContext.context(info), let v = InkScanContext.numbers(scanner, 2) else { return }
            let point = CGPoint(x: v[0], y: v[1]).applying(c.state.ctm)
            if let start = c.current { c.segments.append((start, point)) }
            c.current = point
        }
        for fill in ["f", "F", "f*"] {
            CGPDFOperatorTableSetCallback(table, fill) { _, info in InkScanContext.context(info)?.fill() }
        }
        for stroke in ["S", "s"] {
            CGPDFOperatorTableSetCallback(table, stroke) { _, info in InkScanContext.context(info)?.stroke() }
        }
        for both in ["B", "B*", "b", "b*"] {
            CGPDFOperatorTableSetCallback(table, both) { _, info in InkScanContext.context(info)?.fill() }
        }
        for other in ["n", "c", "v", "y"] {
            CGPDFOperatorTableSetCallback(table, other) { scanner, info in
                // A curve makes the path something other than a rule.
                guard let c = InkScanContext.context(info) else { return }
                c.pendingRects = []; c.segments = []; c.current = nil
            }
        }
        return table
    }

    // MARK: Rules

    /// Thin and axis-aligned: a rule. Thick rectangles are backgrounds, boxes and figure parts.
    private static let maximumThickness: CGFloat = 2.2

    private func fill() {
        for rect in pendingRects where min(rect.width, rect.height) <= Self.maximumThickness && max(rect.width, rect.height) >= 1 {
            rules.append(InkRule(rect))
        }
        pendingRects = []; segments = []; current = nil
    }

    private func stroke() {
        let width = max(state.lineWidth * max(abs(state.ctm.a), abs(state.ctm.d)), 0.2)
        if width <= Self.maximumThickness {
            for (a, b) in segments {
                let rect = CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(a.x - b.x), height: abs(a.y - b.y))
                guard rect.width < 0.3 || rect.height < 0.3, max(rect.width, rect.height) >= 1 else { continue }
                rules.append(InkRule(rect.insetBy(dx: rect.width < 0.3 ? -width / 2 : 0, dy: rect.height < 0.3 ? -width / 2 : 0)))
            }
        }
        pendingRects = []; segments = []; current = nil
    }

    // MARK: Text state

    private func moveLine(_ tx: CGFloat, _ ty: CGFloat) {
        lineMatrix = CGAffineTransform(translationX: tx, y: ty).concatenating(lineMatrix)
        textMatrix = lineMatrix
    }

    private func font(named name: UnsafePointer<Int8>, scanner: CGPDFScannerRef) -> EmphasisFontInfo? {
        let stream = CGPDFScannerGetContentStream(scanner)
        guard let object = CGPDFContentStreamGetResource(stream, "Font", name) else { return nil }
        var dict: CGPDFDictionaryRef?
        guard CGPDFObjectGetValue(object, .dictionary, &dict), let dict else { return nil }
        let key = unsafeBitCast(dict, to: Int.self)
        if let cached = cache.fonts[key] { return cached }
        let info = EmphasisFontInfo(dictionary: dict)
        cache.fonts[key] = info
        return info
    }

    private func invokeXObject(named name: UnsafePointer<Int8>, scanner: CGPDFScannerRef) {
        let parent = CGPDFScannerGetContentStream(scanner)
        guard let object = CGPDFContentStreamGetResource(parent, "XObject", name) else { return }
        var stream: CGPDFStreamRef?
        guard CGPDFObjectGetValue(object, .stream, &stream), let stream, let dict = CGPDFStreamGetDictionary(stream) else { return }
        guard EmphasisPDF.name(dict, "Subtype") == "Form", formDepth < 8, let table else { return }
        stack.append(state)
        if let m = EmphasisPDF.matrix(dict, "Matrix") { state.ctm = m.concatenating(state.ctm) }
        var resources: CGPDFDictionaryRef?
        let streamResources = CGPDFDictionaryGetDictionary(dict, "Resources", &resources) ? resources! : dict
        let formStream = CGPDFContentStreamCreateWithStream(stream, streamResources, parent)
        let formScanner = CGPDFScannerCreate(formStream, table, Unmanaged.passUnretained(self).toOpaque())
        formDepth += 1
        CGPDFScannerScan(formScanner)
        formDepth -= 1
        CGPDFScannerRelease(formScanner)
        CGPDFContentStreamRelease(formStream)
        if let s = stack.popLast() { state = s }
    }

    private func showArray(_ array: CGPDFArrayRef) {
        for i in 0..<CGPDFArrayGetCount(array) {
            var object: CGPDFObjectRef?
            guard CGPDFArrayGetObject(array, i, &object), let object else { continue }
            switch CGPDFObjectGetType(object) {
            case .string:
                var string: CGPDFStringRef?
                if CGPDFObjectGetValue(object, .string, &string), let string { show(string) }
            case .integer, .real:
                var v: CGPDFReal = 0
                if CGPDFObjectGetValue(object, .real, &v) {
                    let tx = -v / 1000 * state.fontSize * state.horizontalScale
                    textMatrix.tx += tx * textMatrix.a
                    textMatrix.ty += tx * textMatrix.b
                }
            default: continue
            }
        }
    }

    private func show(_ string: CGPDFStringRef) {
        guard let font = state.font, let bytes = CGPDFStringGetBytePtr(string) else { return }
        let length = CGPDFStringGetLength(string)
        guard length > 0 else { return }
        let fontSize = state.fontSize, hScale = state.horizontalScale
        let m = textMatrix.concatenating(state.ctm)
        let em = abs(fontSize) * font.emScale * hypot(m.c, m.d)
        // Upright text only: rotated labels of figures are not formulas.
        let upright = abs(m.b) <= 0.02 * max(abs(m.a), 1e-9) && m.a > 0 && em.isFinite && em > 0.5 && em < 400
        let codeBytes = font.codeBytes
        var advance: CGFloat = 0
        var i = 0
        while i + codeBytes <= length {
            let code = codeBytes == 1 ? UInt32(bytes[i]) : (UInt32(bytes[i]) << 8 | UInt32(bytes[i + 1]))
            i += codeBytes
            let w = font.width(code) * fontSize
            if upright {
                let origin = CGPoint(x: advance, y: state.rise).applying(m)
                let end = CGPoint(x: advance + w * hScale, y: state.rise).applying(m)
                let text = font.unicode(code) ?? ""
                let name = font.glyphName(code)
                // Spaces carry no ink; a font without names or Unicode for a glyph still shows it.
                if !(name == nil && text.unicodeScalars.allSatisfy { $0.properties.isWhitespace } && !text.isEmpty) && name != "space" && origin.x.isFinite && origin.y.isFinite {
                    glyphs.append(InkGlyph(code: code, name: name, text: text, font: font.name, size: em, x: origin.x, y: origin.y,
                                           width: max(0, end.x - origin.x), order: glyphs.count))
                }
            }
            advance += (w + state.charSpacing + (codeBytes == 1 && code == 32 ? state.wordSpacing : 0)) * hScale
        }
        textMatrix.tx += advance * textMatrix.a
        textMatrix.ty += advance * textMatrix.b
    }
}

// MARK: - Encodings of TeX's fonts

/// The glyph names of TeX's own font encodings, for fonts embedded without an /Encoding: Computer Modern and
/// the AMS fonts keep TeX's slots, and their names say what a ToUnicode map cannot (“summationdisplay”).
enum TeXFontEncodings {
    enum Table { case mathItalic, symbols, extensible, text, typewriter, blackboard, amsA, letters }

    static func table(for fontName: String) -> Table? {
        let family = InkGlyph.family(of: fontName)
        switch family {
        case "CMMI", "CMMIB", "LMMI", "LMMIB": return .mathItalic
        case "CMSY", "CMBSY", "LMSY", "LMBSY": return .symbols
        case "CMEX", "LMEX": return .extensible
        case "CMTT", "CMITT", "CMSLTT", "CMTCSC", "CMVTT": return .typewriter
        case "MSBM": return .blackboard
        case "MSAM": return .amsA
        case "RSFS", "EUSM", "EUSB", "EUFM", "EUFB", "EURM", "EURB": return .letters
        default:
            return family.hasPrefix("CM") && !family.hasPrefix("CMU") ? .text : nil
        }
    }

    static func name(in table: Table, code: Int) -> String? {
        // The Type 1 Computer Modern fonts repeat slots 0–32 and 127 at 161–196, where no control code can hurt.
        var code = code
        switch code {
        case 161...170: code -= 161
        case 173...195: code -= 163
        case 196: code = 127
        default: break
        }
        guard code >= 0, code < 128 else { return nil }
        switch table {
        case .mathItalic: return mathItalic[code]
        case .symbols: return symbols[code]
        case .extensible: return extensionNames[code]
        case .text: return text[code]
        case .typewriter: return code >= 33 && code < 127 ? asciiNames[code] : nil
        case .blackboard:
            if (65...90).contains(code) { return String(UnicodeScalar(UInt8(code))) }
            return [0x3F: "emptyset", 0x7E: "hbar", 0x7D: "hslash", 0x2D: "notdivides", 0x40: "notexistential", 0x28: "subsetnoteql", 0x29: "supersetnoteql",
                    0x2A: "notsubseteql", 0x2B: "notsuperseteql", 0x0A: "notlessequal", 0x0B: "notgreaterequal", 0x6E: "multicloseleft", 0x6F: "multicloseright"][code]
        case .amsA:
            return [0x03: "square", 0x04: "squaresolid", 0x36: "lessorequalslant", 0x3E: "greaterorequalslant", 0x2E: "lessorsimilar", 0x26: "greaterorsimilar",
                    0x2C: "defines", 0x29: "therefore", 0x2A: "because", 0x4E: "trianglesolid", 0x4D: "triangle", 0x06: "lozenge", 0x58: "check"][code]
        case .letters:
            return (65...90).contains(code) || (97...122).contains(code) ? String(UnicodeScalar(UInt8(code))) : nil
        }
    }

    private static func split(_ names: String) -> [String] { names.split(whereSeparator: { $0 == " " || $0 == "\n" }).map(String.init) }

    private static let capitals = "A B C D E F G H I J K L M N O P Q R S T U V W X Y Z"
    private static let smalls = "a b c d e f g h i j k l m n o p q r s t u v w x y z"

    /// OML: cmmi.
    static let mathItalic: [String] = split("""
        Gamma Delta Theta Lambda Xi Pi Sigma Upsilon Phi Psi Omega alpha beta gamma delta epsilon1 zeta eta theta iota kappa lambda mu nu xi pi rho sigma tau upsilon phi chi psi omega
        epsilon theta1 pi1 rho1 sigma1 phi1 arrowlefttophalf arrowleftbothalf arrowrighttophalf arrowrightbothalf arrowhookleft arrowhookright triangleright triangleleft
        zerooldstyle oneoldstyle twooldstyle threeoldstyle fouroldstyle fiveoldstyle sixoldstyle sevenoldstyle eightoldstyle nineoldstyle period comma less slash greater star partialdiff
        \(capitals) flat natural sharp slurbelow slurabove lscript \(smalls) dotlessi dotlessj weierstrass vector tie
        """)

    /// OMS: cmsy.
    static let symbols: [String] = split("""
        minus periodcentered multiply asteriskmath divide diamondmath plusminus minusplus circleplus circleminus circlemultiply circledivide circledot circlecopyrt openbullet bullet
        equivasymptotic equivalence reflexsubset reflexsuperset lessequal greaterequal precedesequal followsequal similar approxequal propersubset propersuperset lessmuch greatermuch precedes follows
        arrowleft arrowright arrowup arrowdown arrowboth arrownortheast arrowsoutheast similarequal arrowdblleft arrowdblright arrowdblup arrowdbldown arrowdblboth arrownorthwest arrowsouthwest proportional
        prime infinity element owner triangle triangleinv negationslash mapsto universal existential logicalnot emptyset Rfractur Ifractur latticetop perpendicular aleph
        \(capitals) union intersection unionmulti logicaland logicalor turnstileleft turnstileright floorleft floorright ceilingleft ceilingright braceleft braceright angbracketleft angbracketright
        bar bardbl arrowbothv arrowdblbothv backslash wreathproduct radical coproduct nabla integral unionsq intersectionsq subsetsqequal supersetsqequal section dagger daggerdbl paragraph club diamond heart spade
        """)

    /// OMX: cmex.
    static let extensionNames: [String] = split("""
        parenleftbig parenrightbig bracketleftbig bracketrightbig floorleftbig floorrightbig ceilingleftbig ceilingrightbig braceleftbig bracerightbig angbracketleftbig angbracketrightbig
        vextendsingle vextenddouble slashbig backslashbig parenleftBig parenrightBig parenleftbigg parenrightbigg bracketleftbigg bracketrightbigg floorleftbigg floorrightbigg
        ceilingleftbigg ceilingrightbigg braceleftbigg bracerightbigg angbracketleftbigg angbracketrightbigg slashbigg backslashbigg parenleftBigg parenrightBigg bracketleftBigg bracketrightBigg
        floorleftBigg floorrightBigg ceilingleftBigg ceilingrightBigg braceleftBigg bracerightBigg angbracketleftBigg angbracketrightBigg slashBigg backslashBigg slashBig backslashBig
        parenlefttp parenrighttp bracketlefttp bracketrighttp bracketleftbt bracketrightbt bracketleftex bracketrightex bracelefttp bracerighttp braceleftbt bracerightbt braceleftmid bracerightmid braceex arrowvertex
        parenleftbt parenrightbt parenleftex parenrightex angbracketleftBig angbracketrightBig unionsqtext unionsqdisplay contintegraltext contintegraldisplay circledottext circledotdisplay
        circleplustext circleplusdisplay circlemultiplytext circlemultiplydisplay summationtext producttext integraltext uniontext intersectiontext unionmultitext logicalandtext logicalortext
        summationdisplay productdisplay integraldisplay uniondisplay intersectiondisplay unionmultidisplay logicalanddisplay logicalordisplay coproducttext coproductdisplay
        hatwide hatwider hatwidest tildewide tildewider tildewidest bracketleftBig bracketrightBig floorleftBig floorrightBig ceilingleftBig ceilingrightBig braceleftBig bracerightBig
        radicalbig radicalBig radicalbigg radicalBigg radicalbt radicalvertex radicaltp arrowvertexdbl arrowtp arrowbt bracehtipdownleft bracehtipdownright bracehtipupleft bracehtipupright arrowdbltp arrowdblbt
        """)

    private static let asciiNames: [String] = {
        var names = [String](repeating: "", count: 128)
        let punctuation: [Int: String] = [33: "exclam", 34: "quotedbl", 35: "numbersign", 36: "dollar", 37: "percent", 38: "ampersand", 39: "quotesingle", 40: "parenleft", 41: "parenright",
                                          42: "asterisk", 43: "plus", 44: "comma", 45: "hyphen", 46: "period", 47: "slash", 58: "colon", 59: "semicolon", 60: "less", 61: "equal", 62: "greater",
                                          63: "question", 64: "at", 91: "bracketleft", 92: "backslash", 93: "bracketright", 94: "asciicircum", 95: "underscore", 96: "grave", 123: "braceleft",
                                          124: "bar", 125: "braceright", 126: "asciitilde"]
        let digits = ["zero", "one", "two", "three", "four", "five", "six", "seven", "eight", "nine"]
        for code in 0..<128 {
            if let name = punctuation[code] { names[code] = name }
            else if (48...57).contains(code) { names[code] = digits[code - 48] }
            else if (65...90).contains(code) || (97...122).contains(code) { names[code] = String(UnicodeScalar(UInt8(code))) }
        }
        return names
    }()

    /// OT1: cmr, cmbx, cmti, cmss…
    static let text: [String] = {
        var names = asciiNames
        let low = split("Gamma Delta Theta Lambda Xi Pi Sigma Upsilon Phi Psi Omega ff fi fl ffi ffl dotlessi dotlessj grave acute caron breve macron ring cedilla germandbls ae oe oslash AE OE Oslash suppress")
        for (code, name) in low.enumerated() { names[code] = name }
        for (code, name) in [34: "quotedblright", 39: "quoteright", 60: "exclamdown", 62: "questiondown", 92: "quotedblleft", 94: "circumflex", 95: "dotaccent", 96: "quoteleft",
                             123: "endash", 124: "emdash", 125: "hungarumlaut", 126: "tilde", 127: "dieresis"] { names[code] = name }
        return names
    }()
}

/// The encoding vector of an embedded Type 1 font program (“dup 12 /beta put”), read from its clear-text part.
enum Type1ProgramEncoding {
    private static let entry = try! NSRegularExpression(pattern: #"dup\s+(\d+)\s*/([^\s/]+)\s+put"#)

    static func names(in stream: CGPDFStreamRef) -> [String?]? {
        var format = CGPDFDataFormat.raw
        guard let data = CGPDFStreamCopyData(stream, &format) as Data?, format == .raw, data.count > 64 else { return nil }
        // The clear text ends at “eexec”; encodings sit well inside the first 24 KB.
        guard let text = String(data: data.prefix(24_576), encoding: .isoLatin1), let start = text.range(of: "/Encoding") else { return nil }
        let limit = text.range(of: "eexec", range: start.upperBound..<text.endIndex)?.lowerBound ?? text.endIndex
        var body = text[start.upperBound..<limit]
        if body.prefix(40).contains("StandardEncoding") { return nil }
        // The vector ends at its “readonly def”; what follows (FontBBox, …) has no “dup … put”.
        if let end = body.range(of: "readonly def") { body = body[..<end.lowerBound] }
        var names = [String?](repeating: nil, count: 256)
        var found = 0
        let string = String(body) as NSString
        for match in entry.matches(in: string as String, range: NSRange(location: 0, length: string.length)) {
            guard let code = Int(string.substring(with: match.range(at: 1))), code >= 0, code < 256 else { continue }
            let name = string.substring(with: match.range(at: 2))
            if name != ".notdef" { names[code] = name; found += 1 }
        }
        return found > 0 ? names : nil
    }
}
