import XCTest
@testable import LemmaCore

/// The colour-theme engine: VS Code's theme files, its colour arithmetic and its registered defaults.
final class ColorThemeTests: XCTestCase {
    private var defaultsURL: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/Lemma/Resources/Themes/defaults.json")
    }

    func testHexColoursParseAndPrintAsVSCodeWritesThem() throws {
        XCTAssertEqual(RGBA(hex: "#0078D4")?.hex, "#0078D4")
        XCTAssertEqual(RGBA(hex: "#fff")?.hex, "#FFFFFF")
        XCTAssertEqual(RGBA(hex: "#00000080")?.hex, "#00000080")
        XCTAssertEqual(try XCTUnwrap(RGBA(hex: "#1e1e1e80")).a, 128.0 / 255, accuracy: 0.001)
        XCTAssertNil(RGBA(hex: "red"))
        XCTAssertNil(RGBA(hex: "#12345"))
    }

    func testTransformsMatchVSCodesArithmetic() throws {
        // Dark+: button.hoverBackground is lighten(button.background, 0.2) = #1177BB in VS Code.
        XCTAssertEqual(try XCTUnwrap(RGBA(hex: "#0E639C")).lighten(0.2).hex, "#1177BB")
        XCTAssertEqual(try XCTUnwrap(RGBA(hex: "#CCCCCC")).transparent(0.7).hex, "#CCCCCCB3")
        let darker = try XCTUnwrap(RGBA(hex: "#3794FF")).darken(0.5)
        XCTAssertLessThan(darker.relativeLuminance, try XCTUnwrap(RGBA(hex: "#3794FF")).relativeLuminance)
        XCTAssertEqual(RGBA(1, 1, 1).contrast(with: RGBA(0, 0, 0)), 21, accuracy: 0.01)
    }

    func testThemeFilesWithCommentsTrailingCommasAndIncludesAreRead() throws {
        let parent = """
        {
          // VS Code accepts comments and trailing commas.
          "colors": { "editor.background": "#1E1E1E", "foreground": "#CCCCCC", },
          "tokenColors": [ { "scope": "keyword", "settings": { "foreground": "#569CD6" } }, ],
        }
        """
        let child = """
        { "name": "Child", "type": "dark", "include": "./parent.json",
          /* a block comment */
          "colors": { "editor.background": "#101010", "activityBar.background": "#202020" },
          "tokenColors": [ { "scope": ["keyword.control", "storage.type"], "settings": { "foreground": "#C586C0", "fontStyle": "italic" } },
                           { "scope": "string, string.quoted", "settings": { "foreground": "#CE9178" } } ] }
        """
        let theme = try ThemeFile.theme(data: Data(child.utf8), id: "child", fallbackName: "x", origin: "test") { include in
            XCTAssertEqual(include, "./parent.json")
            return Data(parent.utf8)
        }
        XCTAssertEqual(theme.name, "Child")
        XCTAssertEqual(theme.kind, .dark)
        XCTAssertEqual(theme.colors["editor.background"]?.hex, "#101010", "The child overrides its parent.")
        XCTAssertEqual(theme.colors["foreground"]?.hex, "#CCCCCC", "Colours come down from the parent.")
        XCTAssertEqual(theme.tokenRules.count, 3)
        XCTAssertEqual(theme.tokenStyle(for: "keyword.control.python")?.foreground?.hex, "#C586C0", "The most specific scope wins.")
        XCTAssertEqual(theme.tokenStyle(for: "keyword.operator")?.foreground?.hex, "#569CD6")
        XCTAssertEqual(theme.tokenColor(["string.quoted.double"])?.hex, "#CE9178")
        XCTAssertEqual(theme.tokenStyle(for: "storage.type")?.fontStyle, "italic")
    }

    func testAThemeWithoutATypeTakesItsKindFromItsBackground() throws {
        let light = try ThemeFile.theme(data: Data(##"{"colors":{"editor.background":"#FAFAFA"}}"##.utf8), id: "l", fallbackName: "Light", origin: "test")
        XCTAssertEqual(light.kind, .light)
        XCTAssertEqual(light.name, "Light")
        XCTAssertThrowsError(try ThemeFile.theme(data: Data("not json".utf8), id: "x", fallbackName: "x", origin: "test"))
    }

    func testDefaultExpressionsParse() {
        XCTAssertEqual(ColorExpression.parse("#1E1E1E"), .literal(RGBA(hex: "#1E1E1E")!))
        XCTAssertEqual(ColorExpression.parse("=editor.background"), .reference("editor.background"))
        XCTAssertEqual(ColorExpression.parse("transparent(=foreground, 0.6)"), .transparent(.reference("foreground"), 0.6))
        XCTAssertEqual(ColorExpression.parse("oneOf(=a, =b)"), .oneOf([.reference("a"), .reference("b")]))
        XCTAssertEqual(ColorExpression.parse("lighten(darken(#808080, 0.5), 0.1)"), .lighten(.darken(.literal(RGBA(hex: "#808080")!), 0.5), 0.1))
        XCTAssertEqual(ColorExpression.parse("null"), ColorExpression.none)
    }

    func testTheResolverPrefersTheThemeThenItsDefaults() throws {
        let json = """
        { "foreground": { "dark": "#CCCCCC", "light": "#616161" },
          "descriptionForeground": { "dark": "transparent(=foreground, 0.7)", "light": "#717171" },
          "loop.a": { "dark": "=loop.b" }, "loop.b": { "dark": "=loop.a" },
          "maybe": { "dark": "ifDefinedThenElse(=editor.foreground, #111111, #222222)" } }
        """
        let defaults = try ColorDefaults(json: Data(json.utf8))
        let plain = ColorResolver(theme: ColorTheme(id: "t", name: "t", kind: .dark, colors: [:]), defaults: defaults)
        XCTAssertEqual(plain.color("descriptionForeground")?.hex, "#CCCCCCB3")
        XCTAssertNil(plain.color("loop.a"), "A cycle resolves to nothing rather than hanging.")
        XCTAssertEqual(plain.color("maybe")?.hex, "#222222")
        let themed = ColorResolver(theme: ColorTheme(id: "t", name: "t", kind: .dark, colors: ["foreground": RGBA(hex: "#FFFFFF")!, "editor.foreground": RGBA(hex: "#EEEEEE")!]), defaults: defaults)
        XCTAssertEqual(themed.color("descriptionForeground")?.hex, "#FFFFFFB3", "Defaults follow the theme's own colours.")
        XCTAssertEqual(themed.color("maybe")?.hex, "#111111")
    }

    /// Every bundled default, resolved with no theme, agrees with VS Code's own arithmetic (vectors computed from
    /// microsoft/vscode's colour registry) to within one unit per channel.
    func testBundledDefaultsResolveAsVSCodeDoes() throws {
        let defaults = try ColorDefaults(json: Data(contentsOf: defaultsURL))
        let vectorsURL = try XCTUnwrap(Bundle.module.url(forResource: "vscode-color-vectors", withExtension: "json", subdirectory: "Fixtures"))
        let vectors = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: vectorsURL)) as? [String: Any])
        var compared = 0
        for kind in ThemeKind.allCases {
            let resolver = ColorResolver(theme: ColorTheme(id: "empty", name: "Empty", kind: kind, colors: [:]), defaults: defaults)
            let expected = try XCTUnwrap(vectors[kind.rawValue] as? [String: Any])
            for (key, value) in expected {
                let resolved = resolver.color(key)
                guard let hex = value as? String, let want = RGBA(hex: hex) else {
                    XCTAssertNil(resolved, "\(kind.rawValue) \(key) has no colour in VS Code")
                    continue
                }
                let got = try XCTUnwrap(resolved, "\(kind.rawValue) \(key) should be \(hex)")
                for (a, b) in [(got.r, want.r), (got.g, want.g), (got.b, want.b), (got.a, want.a)] {
                    XCTAssertEqual(a, b, accuracy: 1.5 / 255, "\(kind.rawValue) \(key): \(got.hex) vs \(hex)")
                }
                compared += 1
            }
        }
        XCTAssertGreaterThan(compared, 1500)
    }

    func testExtensionsDeclareTheirThemes() throws {
        let package = """
        { "name": "moonlight", "contributes": { "themes": [
            { "label": "Moonlight II", "uiTheme": "vs-dark", "path": "./themes/moonlight-ii.json" },
            { "label": "Day", "uiTheme": "vs", "path": "./themes/day.json" } ] } }
        """
        let themes = try ThemeFile.contributedThemes(packageJSON: Data(package.utf8))
        XCTAssertEqual(themes.map(\.label), ["Moonlight II", "Day"])
        XCTAssertEqual(themes.map(\.kind), [.dark, .light])
        XCTAssertEqual(ThemeKind(vscode: "hc-black"), .hcDark)
        XCTAssertEqual(ThemeKind(vscode: "hc-light"), .hcLight)
    }
}
