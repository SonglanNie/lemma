import Foundation

/// A colour with components in 0…1, as VS Code's `Color` (RGBA, sRGB).
public struct RGBA: Codable, Hashable, Sendable {
    public var r: Double, g: Double, b: Double, a: Double
    public init(_ r: Double, _ g: Double, _ b: Double, _ a: Double = 1) {
        self.r = min(1, max(0, r)); self.g = min(1, max(0, g)); self.b = min(1, max(0, b)); self.a = min(1, max(0, a))
    }

    /// “#RGB”, “#RGBA”, “#RRGGBB” or “#RRGGBBAA”, as theme files write colours.
    public init?(hex raw: String) {
        var text = raw.trimmingCharacters(in: .whitespaces)
        guard text.hasPrefix("#") else { return nil }
        text.removeFirst()
        guard text.allSatisfy(\.isHexDigit) else { return nil }
        if text.count == 3 || text.count == 4 { text = String(text.flatMap { [$0, $0] }) }
        guard text.count == 6 || text.count == 8, let value = UInt64(text, radix: 16) else { return nil }
        let hasAlpha = text.count == 8
        let shift: UInt64 = hasAlpha ? 8 : 0
        self.init(Double((value >> (16 + shift)) & 0xFF) / 255, Double((value >> (8 + shift)) & 0xFF) / 255,
                  Double((value >> shift) & 0xFF) / 255, hasAlpha ? Double(value & 0xFF) / 255 : 1)
    }

    public var hex: String {
        func byte(_ value: Double) -> String { String(format: "%02X", Int((value * 255).rounded())) }
        return "#" + byte(r) + byte(g) + byte(b) + (a < 0.999 ? byte(a) : "")
    }

    public var isOpaque: Bool { a >= 0.999 }

    /// VS Code's `transparent`: the alpha multiplied by `factor`.
    public func transparent(_ factor: Double) -> RGBA { RGBA(r, g, b, a * factor) }
    public func withAlpha(_ alpha: Double) -> RGBA { RGBA(r, g, b, alpha) }

    /// WCAG relative luminance, rounded to four places as VS Code does.
    public var relativeLuminance: Double {
        func component(_ c: Double) -> Double { c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
        let value = 0.2126 * component(r) + 0.7152 * component(g) + 0.0722 * component(b)
        return (value * 10_000).rounded() / 10_000
    }

    public var isDark: Bool { (r * 299 + g * 587 + b * 114) / 1000 < 0.5 }
    public func isLighter(than other: RGBA) -> Bool { relativeLuminance > other.relativeLuminance }
    public func isDarker(than other: RGBA) -> Bool { relativeLuminance < other.relativeLuminance }

    /// Contrast ratio between two opaque colours (1…21).
    public func contrast(with other: RGBA) -> Double {
        let l1 = relativeLuminance, l2 = other.relativeLuminance
        return (max(l1, l2) + 0.05) / (min(l1, l2) + 0.05)
    }

    // MARK: HSL, for lighten and darken

    struct HSL { var h: Double; var s: Double; var l: Double; var a: Double }

    var hsl: HSL {
        let maxValue = max(r, g, b), minValue = min(r, g, b)
        var h = 0.0, s = 0.0
        let l = (minValue + maxValue) / 2
        let chroma = maxValue - minValue
        if chroma > 0 {
            s = min(l <= 0.5 ? chroma / (2 * l) : chroma / (2 - 2 * l), 1)
            switch maxValue {
            case r: h = (g - b) / chroma + (g < b ? 6 : 0)
            case g: h = (b - r) / chroma + 2
            default: h = (r - g) / chroma + 4
            }
            h *= 60
        }
        return HSL(h: h, s: s, l: l, a: a)
    }

    init(hsl: HSL) {
        let h = hsl.h / 360, s = hsl.s, l = hsl.l
        func hue(_ p: Double, _ q: Double, _ t0: Double) -> Double {
            var t = t0
            if t < 0 { t += 1 }
            if t > 1 { t -= 1 }
            if t < 1 / 6 { return p + (q - p) * 6 * t }
            if t < 1 / 2 { return q }
            if t < 2 / 3 { return p + (q - p) * (2 / 3 - t) * 6 }
            return p
        }
        if s == 0 { self.init(l, l, l, hsl.a); return }
        let q = l < 0.5 ? l * (1 + s) : l + s - l * s
        let p = 2 * l - q
        self.init(hue(p, q, h + 1 / 3), hue(p, q, h), hue(p, q, h - 1 / 3), hsl.a)
    }

    /// VS Code's `lighten`: lightness raised by `factor` of itself.
    public func lighten(_ factor: Double) -> RGBA { var value = hsl; value.l = min(1, value.l + value.l * factor); return RGBA(hsl: value) }
    /// VS Code's `darken`: lightness lowered by `factor` of itself.
    public func darken(_ factor: Double) -> RGBA { var value = hsl; value.l = max(0, value.l - value.l * factor); return RGBA(hsl: value) }

    /// This colour composited over an opaque background.
    public func over(_ background: RGBA) -> RGBA {
        guard !isOpaque else { return self }
        let alpha = a + background.a * (1 - a)
        guard alpha > 0 else { return RGBA(0, 0, 0, 0) }
        func mix(_ top: Double, _ bottom: Double) -> Double { (top * a + bottom * background.a * (1 - a)) / alpha }
        return RGBA(mix(r, background.r), mix(g, background.g), mix(b, background.b), alpha)
    }

    /// The colour moved towards white or black until it differs from `relative` (VS Code's `getLighterColor`/`getDarkerColor`).
    public static func lighter(_ of: RGBA, than relative: RGBA, factor: Double = 0.5) -> RGBA {
        if of.isLighter(than: relative) { return of }
        let l1 = of.relativeLuminance, l2 = relative.relativeLuminance
        guard l2 > 0 else { return of }
        return of.lighten(factor * (l2 - l1) / l2)
    }
    public static func darker(_ of: RGBA, than relative: RGBA, factor: Double = 0.5) -> RGBA {
        if of.isDarker(than: relative) { return of }
        let l1 = of.relativeLuminance, l2 = relative.relativeLuminance
        guard l1 > 0 else { return of }
        return of.darken(factor * (l1 - l2) / l1)
    }

    /// Linear interpolation, for derived tints.
    public func mixed(with other: RGBA, _ amount: Double) -> RGBA {
        RGBA(r + (other.r - r) * amount, g + (other.g - g) * amount, b + (other.b - b) * amount, a + (other.a - a) * amount)
    }
}

/// Dark, light and the two high-contrast kinds, as VS Code's `uiTheme`.
public enum ThemeKind: String, Codable, CaseIterable, Sendable {
    case dark, light, hcDark, hcLight
    public var isDark: Bool { self == .dark || self == .hcDark }
    public var isHighContrast: Bool { self == .hcDark || self == .hcLight }
    public var label: String {
        switch self { case .dark: "Dark"; case .light: "Light"; case .hcDark: "High Contrast Dark"; case .hcLight: "High Contrast Light" }
    }

    /// From a theme's `type` field or an extension's `uiTheme` (“vs-dark”, “vs”, “hc-black”, “hc-light”).
    public init?(vscode value: String) {
        switch value.lowercased() {
        case "dark", "vs-dark": self = .dark
        case "light", "vs": self = .light
        case "hc", "hcdark", "hc-dark", "hc-black", "highcontrast": self = .hcDark
        case "hclight", "hc-light": self = .hcLight
        default: return nil
        }
    }
}

/// One `tokenColors` rule: scopes and the style they get.
public struct TokenRule: Codable, Equatable, Sendable {
    public var scopes: [String]
    public var foreground: RGBA?
    public var background: RGBA?
    public var fontStyle: String?
    public init(scopes: [String], foreground: RGBA?, background: RGBA? = nil, fontStyle: String? = nil) {
        self.scopes = scopes; self.foreground = foreground; self.background = background; self.fontStyle = fontStyle
    }
}

/// A colour theme as VS Code reads it: workbench colours by id and TextMate token rules.
public struct ColorTheme: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var name: String
    public var kind: ThemeKind
    public var colors: [String: RGBA]
    public var tokenRules: [TokenRule]
    /// Where it came from: “builtin”, or the file a reader installed.
    public var origin: String
    public var author: String?

    public init(id: String, name: String, kind: ThemeKind, colors: [String: RGBA], tokenRules: [TokenRule] = [], origin: String = "builtin", author: String? = nil) {
        self.id = id; self.name = name; self.kind = kind; self.colors = colors; self.tokenRules = tokenRules; self.origin = origin; self.author = author
    }

    /// The style of the most specific rule matching a TextMate scope (“keyword.control.python” matches “keyword.control” before “keyword”).
    public func tokenStyle(for scope: String) -> TokenRule? {
        var best: (rule: TokenRule, score: Int)?
        for rule in tokenRules where rule.foreground != nil || rule.fontStyle != nil {
            for selector in rule.scopes {
                // A selector can be a descendant path (“meta.function variable”); its last part decides here.
                let last = selector.split(separator: " ").last.map(String.init) ?? selector
                guard last == scope || scope.hasPrefix(last + ".") else { continue }
                let score = last.split(separator: ".").count * 10 + (selector.contains(" ") ? 0 : 1)
                if score >= (best?.score ?? -1) { best = (rule, score) }
            }
        }
        return best?.rule
    }

    /// The first scope in `scopes` that the theme colours.
    public func tokenColor(_ scopes: [String]) -> RGBA? {
        for scope in scopes { if let colour = tokenStyle(for: scope)?.foreground { return colour } }
        return nil
    }

    /// The theme's default text colour for tokens (the scopeless rule of older themes), if any.
    public var defaultTokenForeground: RGBA? { tokenRules.first { $0.scopes.isEmpty }?.foreground }
}

// MARK: - Reading theme files

public enum ThemeFileError: LocalizedError {
    case notJSON, noColors, unreadable(String)
    public var errorDescription: String? {
        switch self {
        case .notJSON: "This file is not a VS Code colour theme (JSON)."
        case .noColors: "The theme defines no workbench colours."
        case let .unreadable(reason): reason
        }
    }
}

public enum ThemeFile {
    /// JSON with comments and trailing commas, as VS Code accepts, made strict.
    public static func strictJSON(_ text: String) -> String {
        var output = ""
        output.reserveCapacity(text.utf8.count)
        let characters = Array(text.unicodeScalars)
        var i = 0
        var inString = false
        while i < characters.count {
            let c = characters[i]
            if inString {
                output.unicodeScalars.append(c)
                if c == "\\", i + 1 < characters.count { output.unicodeScalars.append(characters[i + 1]); i += 2; continue }
                if c == "\"" { inString = false }
                i += 1; continue
            }
            if c == "\"" { inString = true; output.unicodeScalars.append(c); i += 1; continue }
            if c == "/", i + 1 < characters.count, characters[i + 1] == "/" {
                while i < characters.count, characters[i] != "\n" { i += 1 }
                continue
            }
            if c == "/", i + 1 < characters.count, characters[i + 1] == "*" {
                i += 2
                while i + 1 < characters.count, !(characters[i] == "*" && characters[i + 1] == "/") { i += 1 }
                i += 2; continue
            }
            if c == "," {
                // A trailing comma: only whitespace before the closing bracket.
                var k = i + 1
                while k < characters.count, characters[k].properties.isWhitespace { k += 1 }
                if k < characters.count, characters[k] == "}" || characters[k] == "]" { i += 1; continue }
            }
            output.unicodeScalars.append(c)
            i += 1
        }
        return output
    }

    public static func object(_ data: Data) throws -> [String: Any] {
        let text = String(decoding: data, as: UTF8.self)
        guard let json = try? JSONSerialization.jsonObject(with: Data(strictJSON(text).utf8)) as? [String: Any] else { throw ThemeFileError.notJSON }
        return json
    }

    /// Reads a theme file. `include`d parents are resolved through `parent` (a path relative to the file).
    public static func theme(data: Data, id: String, fallbackName: String, kind: ThemeKind? = nil, origin: String,
                             parent: ((String) throws -> Data)? = nil) throws -> ColorTheme {
        var merged = try mergedObject(data, parent: parent, depth: 0)
        let name = (merged["name"] as? String) ?? fallbackName
        var colors: [String: RGBA] = [:]
        for (key, value) in merged["colors"] as? [String: Any] ?? [:] {
            if let string = value as? String, let colour = RGBA(hex: string) { colors[key] = colour }
        }
        let rules = tokenRules(merged["tokenColors"])
        let resolvedKind = kind ?? (merged["type"] as? String).flatMap(ThemeKind.init(vscode:))
            ?? (colors["editor.background"].map { $0.isDark ? .dark : .light }) ?? .dark
        guard !colors.isEmpty || !rules.isEmpty else { throw ThemeFileError.noColors }
        merged["name"] = name
        return ColorTheme(id: id, name: name, kind: resolvedKind, colors: colors, tokenRules: rules, origin: origin,
                          author: merged["author"] as? String)
    }

    private static func mergedObject(_ data: Data, parent: ((String) throws -> Data)?, depth: Int) throws -> [String: Any] {
        var object = try self.object(data)
        guard let include = object["include"] as? String, let parent, depth < 6 else { return object }
        let base = try mergedObject(parent(include), parent: parent, depth: depth + 1)
        var colors = base["colors"] as? [String: Any] ?? [:]
        for (key, value) in object["colors"] as? [String: Any] ?? [:] { colors[key] = value }
        let tokens = (base["tokenColors"] as? [Any] ?? []) + (object["tokenColors"] as? [Any] ?? [])
        for (key, value) in base where object[key] == nil { object[key] = value }
        object["colors"] = colors
        object["tokenColors"] = tokens
        object.removeValue(forKey: "include")
        return object
    }

    static func tokenRules(_ value: Any?) -> [TokenRule] {
        guard let list = value as? [Any] else { return [] }
        return list.compactMap { entry in
            guard let entry = entry as? [String: Any], let settings = entry["settings"] as? [String: Any] else { return nil }
            var scopes: [String] = []
            if let scope = entry["scope"] as? String { scopes = scope.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) } }
            else if let list = entry["scope"] as? [String] { scopes = list.flatMap { $0.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) } } }
            return TokenRule(scopes: scopes.filter { !$0.isEmpty }, foreground: (settings["foreground"] as? String).flatMap(RGBA.init(hex:)),
                             background: (settings["background"] as? String).flatMap(RGBA.init(hex:)), fontStyle: settings["fontStyle"] as? String)
        }
    }

    /// The themes an extension contributes (`package.json` → `contributes.themes`), relative to the extension folder.
    public static func contributedThemes(packageJSON data: Data) throws -> [(label: String, kind: ThemeKind?, path: String)] {
        let package = try object(data)
        let contributes = package["contributes"] as? [String: Any]
        let themes = contributes?["themes"] as? [[String: Any]] ?? []
        return themes.compactMap { theme in
            guard let path = theme["path"] as? String else { return nil }
            let label = (theme["label"] as? String) ?? (theme["id"] as? String) ?? URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
            return (label, (theme["uiTheme"] as? String).flatMap(ThemeKind.init(vscode:)), path)
        }
    }
}

// MARK: - Defaults, as VS Code registers them

/// A default colour as VS Code's colour registry describes it: a literal, another colour, or a transform of one.
public indirect enum ColorExpression: Equatable, Sendable {
    case literal(RGBA)
    case reference(String)
    case transparent(ColorExpression, Double)
    case lighten(ColorExpression, Double)
    case darken(ColorExpression, Double)
    case opaque(ColorExpression, ColorExpression)
    case oneOf([ColorExpression])
    case lessProminent(ColorExpression, ColorExpression, Double, Double)
    case ifDefinedThenElse(String, ColorExpression, ColorExpression)
    case mix(ColorExpression, ColorExpression, Double)
    case none

    /// Parses “#1E1E1E”, “=editor.background”, “transparent(=foreground, 0.6)”, “oneOf(=a, =b)”, “null”.
    public static func parse(_ text: String) -> ColorExpression {
        var parser = ExpressionParser(Array(text.unicodeScalars))
        return parser.expression() ?? .none
    }
}

private struct ExpressionParser {
    let scalars: [Unicode.Scalar]
    var index = 0
    init(_ scalars: [Unicode.Scalar]) { self.scalars = scalars }

    mutating func skipSpace() { while index < scalars.count, scalars[index].properties.isWhitespace { index += 1 } }

    mutating func word() -> String {
        skipSpace()
        var text = ""
        while index < scalars.count, !"(),".unicodeScalars.contains(scalars[index]), !scalars[index].properties.isWhitespace {
            text.unicodeScalars.append(scalars[index]); index += 1
        }
        return text
    }

    mutating func expression() -> ColorExpression? {
        skipSpace()
        guard index < scalars.count else { return nil }
        let token = word()
        skipSpace()
        if index < scalars.count, scalars[index] == "(" {
            index += 1
            var arguments: [String] = []
            var expressions: [ColorExpression] = []
            while true {
                skipSpace()
                guard index < scalars.count else { break }
                if scalars[index] == ")" { index += 1; break }
                let start = index
                if let nested = expression() { expressions.append(nested) }
                arguments.append(String(String.UnicodeScalarView(scalars[start..<index])).trimmingCharacters(in: .whitespaces))
                skipSpace()
                if index < scalars.count, scalars[index] == "," { index += 1 }
            }
            func number(_ position: Int) -> Double { arguments.indices.contains(position) ? Double(arguments[position]) ?? 0 : 0 }
            switch token.lowercased() {
            case "transparent": return expressions.first.map { .transparent($0, number(1)) }
            case "lighten": return expressions.first.map { .lighten($0, number(1)) }
            case "darken": return expressions.first.map { .darken($0, number(1)) }
            case "opaque": return expressions.count >= 2 ? .opaque(expressions[0], expressions[1]) : expressions.first
            case "oneof": return .oneOf(expressions.filter { $0 != .none })
            case "lessprominent":
                guard expressions.count >= 2 else { return expressions.first }
                return .lessProminent(expressions[0], expressions[1], number(2), number(3))
            case "mix":
                guard expressions.count >= 2 else { return expressions.first }
                return .mix(expressions[0], expressions[1], arguments.count > 2 ? number(2) : 0.5)
            case "ifdefinedthenelse":
                guard expressions.count >= 3 else { return expressions.last }
                if case let .reference(id) = expressions[0] { return .ifDefinedThenElse(id, expressions[1], expressions[2]) }
                return expressions[1]
            default: return expressions.first
            }
        }
        if token == "null" || token.isEmpty { return ColorExpression.none }
        if let colour = RGBA(hex: token) { return .literal(colour) }
        if Double(token) != nil { return nil }
        return .reference(token.hasPrefix("=") ? String(token.dropFirst()) : token)
    }
}

/// The registry of defaults: one expression per colour id and theme kind.
public struct ColorDefaults: Sendable {
    public var expressions: [String: [ThemeKind: ColorExpression]]
    public init(expressions: [String: [ThemeKind: ColorExpression]] = [:]) { self.expressions = expressions }

    /// Reads `{ "id": { "dark": "...", "light": "...", "hcDark": "...", "hcLight": "..." } }`.
    public init(json data: Data) throws {
        let object = try ThemeFile.object(data)
        var expressions: [String: [ThemeKind: ColorExpression]] = [:]
        for (id, value) in object where !id.hasPrefix("_") {
            guard let kinds = value as? [String: Any] else { continue }
            var entry: [ThemeKind: ColorExpression] = [:]
            for kind in ThemeKind.allCases {
                if let text = kinds[kind.rawValue] as? String { entry[kind] = ColorExpression.parse(text) }
                else if kinds[kind.rawValue] is NSNull { entry[kind] = ColorExpression.none }
            }
            expressions[id] = entry
        }
        self.expressions = expressions
    }

    public mutating func merge(_ other: ColorDefaults) {
        for (id, entry) in other.expressions { expressions[id, default: [:]].merge(entry) { _, new in new } }
    }
}

/// Resolves a theme's colours as VS Code does: the theme's own value, else the registered default for its kind.
public final class ColorResolver: @unchecked Sendable {
    public let theme: ColorTheme
    let defaults: ColorDefaults
    private var cache: [String: RGBA?] = [:]
    private var resolving: Set<String> = []
    private let lock = NSLock()

    public init(theme: ColorTheme, defaults: ColorDefaults) { self.theme = theme; self.defaults = defaults }

    public func color(_ id: String) -> RGBA? {
        lock.lock(); defer { lock.unlock() }
        return resolve(id)
    }

    private func resolve(_ id: String) -> RGBA? {
        if let cached = cache[id] { return cached }
        if let own = theme.colors[id] { cache[id] = own; return own }
        guard !resolving.contains(id) else { return nil }
        resolving.insert(id)
        let value = defaults.expressions[id]?[theme.kind].flatMap(evaluate)
        resolving.remove(id)
        cache[id] = value
        return value
    }

    private func evaluate(_ expression: ColorExpression) -> RGBA? {
        switch expression {
        case let .literal(colour): return colour
        case let .reference(id): return resolve(id)
        case let .transparent(inner, factor): return evaluate(inner)?.transparent(factor)
        case let .lighten(inner, factor): return evaluate(inner)?.lighten(factor)
        case let .darken(inner, factor): return evaluate(inner)?.darken(factor)
        case let .opaque(inner, background):
            guard let colour = evaluate(inner) else { return nil }
            guard let background = evaluate(background) else { return colour }
            return colour.over(background)
        case let .oneOf(list):
            for item in list { if let colour = evaluate(item) { return colour } }
            return nil
        case let .lessProminent(inner, background, factor, transparency):
            guard let from = evaluate(inner) else { return nil }
            guard let background = evaluate(background) else { return from.transparent(factor * transparency) }
            let moved = from.isDarker(than: background) ? RGBA.lighter(from, than: background, factor: factor) : RGBA.darker(from, than: background, factor: factor)
            return moved.transparent(transparency)
        case let .ifDefinedThenElse(id, then, otherwise):
            return theme.colors[id] != nil ? evaluate(then) : evaluate(otherwise)
        case let .mix(first, second, ratio):
            let a = evaluate(first) ?? RGBA(0, 0, 0, 0), b = evaluate(second) ?? RGBA(0, 0, 0, 0)
            return a.mixed(with: b, min(1, max(0, ratio)))
        case .none: return nil
        }
    }
}
