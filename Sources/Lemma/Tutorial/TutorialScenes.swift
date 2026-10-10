import SwiftUI
import AppKit
import LemmaCore

// The illustrations of the tour: small animated scenes drawn in the theme's colours, each played once when its step
// appears (Replay plays it again). They are drawn at a fixed size and scaled to the room the card gives them.

enum TutorialScene: Equatable {
    case workbench(MiniRegion), layouts
    case library, split
    case goTo, hover, peek, lookUp, ruler
    case results, fold, hierarchy, debugStep
    case derivation(DerivationDemo)
    case notebook, cells, console, marginFigure
    case selection, note, highlight, glossary, ink
    case ask, askContext, chrome
    case review, search, project
    case themes, interfaceStyle, settings, privacy
}

enum MiniRegion: Equatable { case titleBar, activityBar, sideBar, editor, page, secondarySideBar, panel, statusBar }
enum DerivationDemo: Equatable { case start, check, answer }

/// The canvas every scene is drawn on, before it is scaled to the card.
enum SceneCanvas { static let size = CGSize(width: 640, height: 320) }

/// A scene, scaled to fit the room it is given.
struct TutorialSceneView: View {
    let scene: TutorialScene
    let replay: Int
    let style: WorkbenchStyle

    var body: some View {
        GeometryReader { geometry in
            let scale = min(geometry.size.width / SceneCanvas.size.width, geometry.size.height / SceneCanvas.size.height)
            content
                .frame(width: SceneCanvas.size.width, height: SceneCanvas.size.height)
                .scaleEffect(scale)
                .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .allowsHitTesting(false)
    }

    @ViewBuilder private var content: some View {
        switch scene {
        case let .workbench(region): play([0.35, 0.6]) { WorkbenchScene(region: region, style: style, phase: $0) }
        case .layouts: play([0.4, 0.7, 0.7, 0.7, 0.8]) { LayoutsScene(phase: $0) }
        case .library: play([0.4, 0.8, 0.6]) { LibraryScene(phase: $0) }
        case .split: play([0.4, 0.8, 0.8]) { SplitScene(phase: $0) }
        case .goTo: play([0.4, 0.6, 1.0, 0.6, 1.0, 0.6]) { GoToScene(phase: $0) }
        case .hover: play([0.4, 0.8, 0.5]) { HoverScene(phase: $0) }
        case .peek: play([0.4, 0.8, 0.4, 0.6]) { PeekScene(phase: $0) }
        case .lookUp: play([0.4, 0.8, 0.4, 0.4, 0.4]) { LookUpScene(phase: $0) }
        case .ruler: play([0.5, 0.6, 0.6, 0.6, 0.8]) { RulerScene(phase: $0) }
        case .results: play([0.3, 0.3, 0.3, 0.7, 0.6]) { ResultsScene(phase: $0) }
        case .fold: play([0.4, 0.8, 0.6]) { FoldScene(phase: $0) }
        case .hierarchy: play([0.4, 0.5, 0.7, 0.6]) { HierarchyScene(phase: $0) }
        case .debugStep: play([0.3, 0.7, 0.7, 0.9, 0.9]) { DebugScene(phase: $0, stepping: true) }
        case let .derivation(demo): play(DerivationScene.delays(demo)) { DerivationScene(demo: demo, phase: $0) }
        case .notebook: play([0.4, 0.7, 0.6, 0.6]) { NotebookScene(phase: $0) }
        case .cells: play([0.4, 0.6, 0.6, 0.8, 0.6]) { CellsScene(phase: $0) }
        case .console: play([0.3, 0.6, 0.6, 0.6, 0.6]) { ConsoleScene(phase: $0) }
        case .marginFigure: play([0.4, 0.7, 1.0]) { MarginFigureScene(phase: $0) }
        case .selection: play([0.4, 0.8, 0.6]) { SelectionScene(phase: $0) }
        case .note: play([0.3, 0.5, 0.7, 0.9]) { NoteScene(phase: $0) }
        case .highlight: play([0.4, 0.7, 0.7, 0.7]) { HighlightScene(phase: $0) }
        case .glossary: play([0.3, 0.4, 0.4, 0.8]) { GlossaryScene(phase: $0) }
        case .ink: play([0.4, 0.8, 0.8, 0.8, 0.9, 0.9]) { InkScene(phase: $0) }
        case .ask: play([0.4, 0.6, 0.6, 0.5, 0.6]) { AskScene(phase: $0) }
        case .askContext: play([0.3, 0.3, 0.3, 0.3, 0.3, 0.6]) { AskContextScene(phase: $0) }
        case .chrome: play([0.4, 0.8, 0.9, 0.9]) { ChromeScene(phase: $0) }
        case .review: play([0.4, 0.9, 0.8, 0.7]) { ReviewScene(phase: $0) }
        case .search: play([0.3, 0.5, 0.5, 0.5, 0.6]) { SearchScene(phase: $0) }
        case .project: play([0.3, 0.5, 0.5, 0.7]) { ProjectScene(phase: $0) }
        case .themes: play([0.5, 0.9, 0.9, 0.9, 0.9]) { ThemesScene(phase: $0) }
        case .interfaceStyle: play([0.5, 1.2, 1.2]) { InterfaceStyleScene(phase: $0) }
        case .settings: play([0.3, 0.6, 0.6, 0.7]) { SettingsScene(phase: $0) }
        case .privacy: play([0.4, 0.5, 0.5, 0.5]) { PrivacyScene(phase: $0) }
        }
    }

    private func play<Scene: View>(_ delays: [Double], @ViewBuilder _ scene: @escaping (Int) -> Scene) -> some View {
        ScenePlayer(delays: delays, replay: replay) { phase in scene(phase) }
    }
}

// MARK: - Spots and the pointer

/// Named places in a scene, for the demonstration pointer and callouts.
struct SceneSpotKey: PreferenceKey {
    static var defaultValue: [String: Anchor<CGRect>] { [:] }
    static func reduce(value: inout [String: Anchor<CGRect>], nextValue: () -> [String: Anchor<CGRect>]) { value.merge(nextValue()) { $1 } }
}

extension View {
    func sceneSpot(_ id: String) -> some View { anchorPreference(key: SceneSpotKey.self, value: .bounds) { [id: $0] } }

    /// A pointer resting on a named spot (hidden when nil), moving smoothly between spots, with a ripple per click.
    func scenePointer(at spot: String?, clicks: Int = 0, offset: CGPoint = .zero) -> some View {
        overlayPreferenceValue(SceneSpotKey.self) { spots in
            GeometryReader { proxy in
                if let spot, let anchor = spots[spot] {
                    let rect = proxy[anchor]
                    DemoPointer(clicks: clicks)
                        .position(x: rect.midX + offset.x + 7, y: rect.midY + offset.y + 11)
                        .transition(.opacity)
                }
            }
        }
    }
}

// MARK: - Primitives

/// The ring Results and the outline draw beside a chapter as it is read.
struct SceneRing: View {
    @Environment(\.theme) private var theme
    let value: Double
    var size: CGFloat = 18
    var line: CGFloat = 2.5
    var body: some View {
        ZStack {
            Circle().stroke(theme.tourText.opacity(0.14), lineWidth: line)
            Circle().trim(from: 0, to: max(0.001, min(1, value)))
                .stroke(theme.tourAccent, style: StrokeStyle(lineWidth: line, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .frame(width: size, height: size)
    }
}

/// A small application window: rounded, framed and shadowed, with traffic lights when it has a title bar.
struct SceneWindow<Content: View>: View {
    @Environment(\.theme) private var theme
    var title: String? = nil
    var titleBar = true
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 0) {
            if titleBar {
                ZStack {
                    theme[.titleBarActiveBackground]
                    HStack(spacing: 5) {
                        ForEach([Color(red: 1, green: 0.37, blue: 0.34), Color(red: 1, green: 0.74, blue: 0.18), Color(red: 0.16, green: 0.79, blue: 0.25)], id: \.self) { color in
                            Circle().fill(color).frame(width: 7, height: 7)
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 8)
                    if let title { Text(title).font(.system(size: 9.5, weight: .medium)).foregroundStyle(theme[.titleBarActiveForeground].opacity(0.8)).lineLimit(1) }
                }
                .frame(height: 20)
            }
            content.frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(theme[.editorBackground])
        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(theme.isDark ? Color.white.opacity(0.14) : Color.black.opacity(0.14), lineWidth: 1))
        .shadow(color: .black.opacity(theme.isDark ? 0.45 : 0.18), radius: 18, y: 10)
    }
}

/// A floating card in the theme's widget colours, as hovers and peeks are drawn.
struct SceneCard<Content: View>: View {
    @Environment(\.theme) private var theme
    var padding: CGFloat = 10
    var radius: CGFloat = 8
    @ViewBuilder var content: Content
    var body: some View {
        content
            .padding(padding)
            .background(RoundedRectangle(cornerRadius: radius, style: .continuous).fill(theme[.editorHoverWidgetBackground]))
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(theme.has(.editorHoverWidgetBorder) ? theme[.editorHoverWidgetBorder] : theme.tourHairline, lineWidth: 1))
            .shadow(color: .black.opacity(theme.isDark ? 0.45 : 0.16), radius: 12, y: 6)
    }
}

/// How the page is printed in a scene: the paper of a book, in its page theme.
enum ScenePaperStyle { case paper, sepia, night
    var background: Color {
        switch self { case .paper: .white; case .sepia: Color(red: 0.97, green: 0.93, blue: 0.84); case .night: Color(white: 0.13) }
    }
    var ink: Color { self == .night ? Color(white: 0.86) : Color(red: 0.08, green: 0.08, blue: 0.1) }
    var faint: Color { self == .night ? Color(white: 0.86).opacity(0.22) : Color.black.opacity(0.15) }
}

/// A sheet of a book.
struct ScenePaper<Content: View>: View {
    var style: ScenePaperStyle = .paper
    var padding: CGFloat = 16
    @ViewBuilder var content: Content
    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(RoundedRectangle(cornerRadius: 2).fill(style.background))
            .shadow(color: .black.opacity(0.22), radius: 4, y: 2)
    }
}

/// Lines of prose too small to read, as bars.
struct ProseLines: View {
    let widths: [CGFloat]
    var height: CGFloat = 4
    var spacing: CGFloat = 7
    var color = Color.black.opacity(0.15)
    var body: some View {
        VStack(alignment: .leading, spacing: spacing) {
            ForEach(Array(widths.enumerated()), id: \.offset) { _, width in
                Capsule().fill(color).frame(width: width, height: height)
            }
        }
    }
}

/// Book text, in a serif face.
struct PaperText: View {
    let text: String
    var size: CGFloat = 11
    var weight: Font.Weight = .regular
    var italic = false
    var color = Color(red: 0.08, green: 0.08, blue: 0.1)
    var body: some View {
        Text(text).font(.system(size: size, weight: weight, design: .serif)).italic(italic).foregroundStyle(color).lineLimit(1).fixedSize()
    }
}

/// Mathematics in a scene's serif face: `^{…}` is raised as a superscript and `_{…}` lowered as a subscript (the
/// Unicode superscript minus sets badly in the serif italic).
struct SceneMath: View {
    let source: String
    var size: CGFloat = 12
    var italic = true
    var body: some View { Self.text(source, size: size, italic: italic).lineLimit(1).fixedSize() }

    static func text(_ source: String, size: CGFloat, italic: Bool = true) -> Text {
        var result = Text("")
        var remaining = source[...]
        while let marker = remaining.firstIndex(where: { $0 == "^" || $0 == "_" }) {
            let open = remaining.index(after: marker)
            guard open < remaining.endIndex, remaining[open] == "{", let close = remaining[open...].firstIndex(of: "}") else {
                result = result + run(String(remaining[...marker]), size, italic)
                remaining = remaining[remaining.index(after: marker)...]
                continue
            }
            result = result + run(String(remaining[..<marker]), size, italic)
            let raised = remaining[marker] == "^"
            result = result + Text(String(remaining[remaining.index(after: open)..<close]))
                .font(.system(size: size * 0.68, design: .serif)).italic(italic).baselineOffset(raised ? size * 0.42 : -size * 0.2)
            remaining = remaining[remaining.index(after: close)...]
        }
        return result + run(String(remaining), size, italic)
    }

    private static func run(_ text: String, _ size: CGFloat, _ italic: Bool) -> Text {
        Text(text).font(.system(size: size, design: .serif)).italic(italic)
    }
}

/// A reference on the page: dotted underline in the accent made readable on paper, solid when hovered.
struct PaperReference: View {
    @Environment(\.theme) private var theme
    let text: String
    var size: CGFloat = 11
    var active = false
    var linked = true
    var body: some View {
        let ink = Color(red: 0.08, green: 0.08, blue: 0.1)
        Text(text).font(.system(size: size, design: .serif)).foregroundStyle(linked ? theme.paperAccent : ink).lineLimit(1).fixedSize()
            .padding(.horizontal, 1)
            .background(RoundedRectangle(cornerRadius: 2).fill(theme.paperAccent.opacity(active ? 0.14 : 0)))
            .overlay(alignment: .bottom) {
                if linked {
                    Line().stroke(theme.paperAccent, style: StrokeStyle(lineWidth: 1, dash: active ? [] : [1.5, 1.8])).frame(height: 1).offset(y: 1)
                }
            }
    }

    struct Line: Shape {
        func path(in rect: CGRect) -> Path { Path { $0.move(to: CGPoint(x: 0, y: rect.midY)); $0.addLine(to: CGPoint(x: rect.maxX, y: rect.midY)) } }
    }
}

extension WorkbenchColors {
    /// The accent, darkened until it reads on white paper.
    var paperAccent: Color {
        let accent = rgba(.focusBorder)
        let luminance = 0.2126 * accent.r + 0.7152 * accent.g + 0.0722 * accent.b
        return luminance > 0.42 ? accent.mixed(with: RGBA(0, 0, 0), 0.45).color : accent.color
    }
}

/// The badge of a statement's kind, as Results draws it: D, T, L, P, C, E; equations and figures too.
struct SceneKindBadge: View {
    let letter: String
    var size: CGFloat = 15
    var color: Color {
        switch letter {
        case "D": Color(red: 0.25, green: 0.52, blue: 0.95)
        case "T": Color(red: 0.62, green: 0.38, blue: 0.9)
        case "L": Color(red: 0.13, green: 0.62, blue: 0.62)
        case "P": Color(red: 0.36, green: 0.4, blue: 0.86)
        case "C": Color(red: 0.88, green: 0.35, blue: 0.6)
        case "E": Color(red: 0.95, green: 0.55, blue: 0.2)
        case "F": Color(red: 0.95, green: 0.55, blue: 0.2)
        case "§": Color.gray
        default: Color(red: 0.13, green: 0.62, blue: 0.62)
        }
    }
    var body: some View {
        Text(letter).font(.system(size: size * 0.62, weight: .bold, design: .rounded)).foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(RoundedRectangle(cornerRadius: size * 0.27, style: .continuous).fill(color))
    }
}

/// A row of a list, as the side bar draws them.
struct SceneRow<Trailing: View>: View {
    @Environment(\.theme) private var theme
    var icon: String? = nil
    var iconColor: Color? = nil
    let title: String
    var detail: String? = nil
    var depth = 0
    var selected = false
    var height: CGFloat = 20
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: 6) {
            if let icon { Codicon(icon, size: 12).foregroundStyle(iconColor ?? theme[.iconForeground]) }
            Text(title).font(.system(size: 10.5)).foregroundStyle(selected ? theme[.listActiveSelectionForeground] : theme[.sideBarForeground]).lineLimit(1)
            if let detail { Text(detail).font(.system(size: 9.5)).foregroundStyle(theme[.descriptionForeground]).lineLimit(1) }
            Spacer(minLength: 4)
            trailing
        }
        .padding(.leading, 8 + CGFloat(depth) * 12).padding(.trailing, 8)
        .frame(height: height)
        .background(selected ? theme[.listActiveSelectionBackground] : .clear)
    }
}

extension SceneRow where Trailing == EmptyView {
    init(icon: String? = nil, iconColor: Color? = nil, title: String, detail: String? = nil, depth: Int = 0, selected: Bool = false, height: CGFloat = 20) {
        self.init(icon: icon, iconColor: iconColor, title: title, detail: detail, depth: depth, selected: selected, height: height) { EmptyView() }
    }
}

/// A side bar or panel title: “EXPLORER”, “PROBLEMS”.
struct SceneHeader: View {
    @Environment(\.theme) private var theme
    let title: String
    var trailing: String? = nil
    var body: some View {
        HStack {
            Text(title.uppercased()).font(.system(size: 9, weight: .semibold)).tracking(0.4).foregroundStyle(theme[.sideBarTitleForeground])
            Spacer()
            if let trailing { Text(trailing).font(.system(size: 9)).foregroundStyle(theme[.descriptionForeground]) }
        }
        .padding(.horizontal, 10).frame(height: 22)
    }
}

/// A side bar in the theme's colours.
struct SceneSideBar<Content: View>: View {
    @Environment(\.theme) private var theme
    let title: String
    var width: CGFloat? = nil
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SceneHeader(title: title)
            content
            Spacer(minLength: 0)
        }
        .frame(width: width)
        .frame(maxHeight: .infinity)
        .background(theme[.sideBarBackground])
    }
}

/// A label pointing at something in a scene.
struct SceneCallout: View {
    @Environment(\.theme) private var theme
    let text: String
    var icon: String? = nil
    var size: CGFloat = 11
    var body: some View {
        HStack(spacing: size * 0.45) {
            if let icon { Codicon(icon, size: size) }
            Text(text).font(.system(size: size, weight: .semibold)).lineLimit(1)
        }
        .foregroundStyle(theme[.buttonForeground])
        .padding(.horizontal, size * 0.8).frame(height: size * 2)
        .background(RoundedRectangle(cornerRadius: size * 0.45).fill(theme[.buttonBackground]))
        .fixedSize()
    }
}

/// A status bar strip in the theme's colours, with a coloured mode block at its left.
struct SceneStatusBar: View {
    @Environment(\.theme) private var theme
    var mode: String = "Read"
    var debugging = false
    var items: [String] = []
    var trailing: [String] = []
    var body: some View {
        HStack(spacing: 10) {
            Text(mode).font(.system(size: 9, weight: .medium)).foregroundStyle(theme[.statusBarItemRemoteForeground])
                .padding(.horizontal, 7).frame(maxHeight: .infinity)
                .background(theme[.statusBarItemRemoteBackground])
            ForEach(items, id: \.self) { item in Text(item).font(.system(size: 9)).lineLimit(1) }
            Spacer(minLength: 4)
            ForEach(trailing, id: \.self) { item in Text(item).font(.system(size: 9)).lineLimit(1) }
            Codicon("bell", size: 10).padding(.trailing, 7)
        }
        .foregroundStyle(theme[debugging ? .statusBarDebuggingForeground : .statusBarForeground])
        .frame(height: 18)
        .background(theme[debugging ? .statusBarDebuggingBackground : .statusBarBackground])
    }
}

/// A key pressed in a demonstration: the key caps, lit when pressed.
struct ScenePressedKeys: View {
    @Environment(\.theme) private var theme
    let keys: String
    var pressed = false
    var body: some View {
        TutorialKeys(shortcut: keys, size: 13)
            .padding(6)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(theme.accent.opacity(pressed ? 0.35 : 0)))
            .scaleEffect(pressed ? 0.94 : 1)
    }
}

/// The page of a mathematics book most scenes share: a section on ridge regression, with references, an equation,
/// a theorem and its proof, at a size that reads.
struct SceneBookPage: View {
    var style: ScenePaperStyle = .paper
    var activeReference: String? = nil
    var linked = true
    var body: some View {
        let ink = style.ink
        ScenePaper(style: style, padding: 18) {
            VStack(alignment: .leading, spacing: 6) {
                PaperText(text: "3.4.1  Ridge Regression", size: 13, weight: .bold, color: ink).padding(.bottom, 2)
                HStack(spacing: 0) {
                    PaperText(text: "Ridge regression shrinks the coefficients by imposing a ", color: ink)
                }
                HStack(spacing: 0) {
                    PaperText(text: "penalty on their size, as in ", color: ink)
                    PaperReference(text: "Section 3.2", active: activeReference == "section", linked: linked).sceneSpot("ref.section")
                    PaperText(text: " and ", color: ink)
                    PaperReference(text: "Figure 3.8", active: activeReference == "figure", linked: linked).sceneSpot("ref.figure")
                    PaperText(text: ":", color: ink)
                }
                HStack {
                    Spacer()
                    PaperText(text: "β̂ = argmin { ‖y − Xβ‖² + λ‖β‖² }", size: 12.5, italic: true, color: ink).sceneSpot("equation")
                    Spacer()
                    PaperText(text: "(3.41)", size: 11, color: ink).sceneSpot("label")
                }
                .padding(.vertical, 4)
                HStack(spacing: 0) {
                    PaperText(text: "where ", color: ink)
                    PaperText(text: "λ", italic: true, color: ink).sceneSpot("lambda")
                    PaperText(text: " ≥ 0 is a complexity parameter. By ", color: ink)
                    PaperReference(text: "(3.41)", active: activeReference == "equation", linked: linked).sceneSpot("ref.equation")
                    PaperText(text: " and", color: ink)
                }
                HStack(spacing: 0) {
                    PaperReference(text: "Hoerl and Kennard (1970)", active: activeReference == "citation", linked: linked).sceneSpot("ref.citation")
                    PaperText(text: ", the solution is easily seen to be", color: ink)
                }
                ProseLines(widths: [300, 270, 310, 180], color: style.faint).padding(.top, 4)
            }
        }
    }
}
