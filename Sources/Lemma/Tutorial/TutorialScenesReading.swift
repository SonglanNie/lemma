import SwiftUI
import AppKit
import LemmaCore

// Scenes about reading and navigating: Go to, the palette, references, citations, terms and symbols.

/// VS Code's quick input, in miniature: a field and its list.
struct ScenePalette: View {
    @Environment(\.theme) private var theme
    struct Item: Hashable { let icon: String; let title: String; var detail: String = ""; var keys: String? = nil }
    let query: String
    var placeholder = "Go to page, section, equation, term or note"
    let items: [Item]
    var selected = 0
    var caret = true

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Text(query.isEmpty ? placeholder : query).font(.system(size: 11.5))
                    .foregroundStyle(query.isEmpty ? theme[.inputPlaceholderForeground] : theme[.inputForeground])
                if caret { Rectangle().fill(theme[.editorCursorForeground]).frame(width: 1, height: 13) }
                Spacer()
            }
            .padding(.horizontal, 8).frame(height: 26)
            .background(RoundedRectangle(cornerRadius: 3).fill(theme[.inputBackground]))
            .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(theme[.focusBorder], lineWidth: 1))
            .padding(6)
            ForEach(Array(items.enumerated()), id: \.element) { index, item in
                HStack(spacing: 7) {
                    Codicon(item.icon, size: 12)
                    VSHighlightedText(text: item.title, matches: FuzzyMatch.ranges(of: query.replacingOccurrences(of: ">", with: ""), in: item.title))
                        .font(.system(size: 11)).lineLimit(1)
                    Text(item.detail).font(.system(size: 10)).foregroundStyle(index == selected ? theme[.quickInputListFocusForeground].opacity(0.75) : theme[.descriptionForeground]).lineLimit(1)
                    Spacer(minLength: 4)
                    if let keys = item.keys { TutorialKeys(shortcut: keys, size: 9) }
                }
                .foregroundStyle(index == selected ? theme[.quickInputListFocusForeground] : theme[.quickInputForeground])
                .padding(.horizontal, 10).frame(height: 22)
                .background(RoundedRectangle(cornerRadius: 3).fill(index == selected ? theme[.quickInputListFocusBackground] : .clear).padding(.horizontal, 4))
                .transition(.opacity)
            }
        }
        .padding(.bottom, 6)
        .frame(width: 430)
        .background(RoundedRectangle(cornerRadius: 6).fill(theme[.quickInputBackground]))
        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(theme.tourHairline, lineWidth: 1))
        .shadow(color: .black.opacity(0.4), radius: 14, y: 6)
    }
}

// MARK: - Go to and the palette

struct GoToScene: View {
    @Environment(\.theme) private var theme
    let phase: Int
    var body: some View {
        let stage = min(2, max(0, (phase - 1) / 2))
        let queries = ["(3.41)", "64:12", "deviance"]
        let typed = phase == 0 ? "" : queries[stage]
        let showing = phase >= 2 && phase % 2 == 0
        let items: [[ScenePalette.Item]] = [
            [.init(icon: "symbol-operator", title: "Equation (3.41)", detail: "Ridge regression · p. 61"), .init(icon: "references", title: "References to (3.41)", detail: "4 places")],
            [.init(icon: "list-ordered", title: "Page 64, line 12", detail: "3.4.1 Ridge Regression"), .init(icon: "file-pdf", title: "PDF page 64", detail: "printed p. 45")],
            [.init(icon: "symbol-key", title: "deviance", detail: "Defined in the book · p. 221"), .init(icon: "list-tree", title: "Index: deviance", detail: "221, 225, 247"),
             .init(icon: "note", title: "Note: Why is the deviance −2 log L?", detail: "p. 221")]
        ]
        VStack(spacing: 14) {
            ScenePalette(query: typed, items: showing ? items[stage] : [])
            HStack(spacing: 10) {
                ForEach(Array(["124", "pdf 143", "(3.41)", "fig 3.8", "ex 2.8", "3.4.1", "64:12"].enumerated()), id: \.offset) { _, example in
                    Text(example).font(.system(size: 11, design: .monospaced)).foregroundStyle(theme.tourText.opacity(0.85))
                        .padding(.horizontal, 8).frame(height: 22)
                        .background(Capsule().fill(theme.tourFill))
                }
            }
            .opacity(phase >= 1 ? 1 : 0)
        }
        .animation(.easeOut(duration: 0.2), value: phase)
    }
}

// MARK: - History

// MARK: - Outline

// MARK: - Line numbers

// MARK: - Page themes

// MARK: - Split editor

struct SplitScene: View {
    @Environment(\.theme) private var theme
    let phase: Int
    var body: some View {
        HStack(spacing: 10) {
            ScenePaper(padding: 14) {
                VStack(alignment: .leading, spacing: 6) {
                    PaperText(text: "Proof of Theorem 4.3.", size: 11, weight: .bold)
                    ProseLines(widths: [200, 180, 210])
                    HStack(spacing: 0) {
                        PaperText(text: "By ", size: 10.5)
                        PaperReference(text: "Theorem 4.2", size: 10.5, active: phase >= 1)
                        PaperText(text: ", the risk is bounded.", size: 10.5)
                    }
                    ProseLines(widths: [210, 170, 200, 120])
                }
            }
            .frame(width: 250, height: 230)
            if phase >= 1 {
                VStack(spacing: 0) {
                    HStack(spacing: 0) {
                        sideTab("file-pdf", "Theorem 4.2", active: true)
                        if phase >= 2 {
                            sideTab("notebook", "Equation (4.7)", active: false)
                            sideTab("symbol-operator", "Bound", active: false)
                            sideTab("graph", "Map", active: false)
                        }
                        Spacer(minLength: 0)
                    }
                    .frame(height: 22).background(theme[.editorGroupHeaderTabsBackground])
                    ZStack {
                        theme.pageCanvas.color
                        ScenePaper(padding: 14) {
                            VStack(alignment: .leading, spacing: 6) {
                                PaperText(text: "Theorem 4.2", size: 11, weight: .bold)
                                    .padding(.horizontal, 3).background(RoundedRectangle(cornerRadius: 2).fill(theme.paperAccent.opacity(0.15)))
                                PaperText(text: "If n ≥ d, the estimator is unbiased", size: 10.5, italic: true)
                                ProseLines(widths: [180, 200, 150])
                            }
                        }
                        .padding(8)
                    }
                }
                .frame(width: 270, height: 230)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .overlay(alignment: .bottom) { ScenePressedKeys(keys: "⌘\\", pressed: phase == 1).offset(y: 30) }
    }

    private func sideTab(_ icon: String, _ title: String, active: Bool) -> some View {
        HStack(spacing: 4) { Codicon(icon, size: 10); Text(title).font(.system(size: 9.5)).lineLimit(1) }
            .foregroundStyle(active ? theme[.tabActiveForeground] : theme[.tabInactiveForeground])
            .padding(.horizontal, 7).frame(height: 22)
            .background(active ? theme[.tabActiveBackground] : theme[.tabInactiveBackground])
            .overlay(alignment: .top) { if active { Rectangle().fill(theme[.tabActiveBorderTop]).frame(height: 1) } }
            .transition(.opacity)
    }
}

// MARK: - Reading time

// MARK: - Marks

// MARK: - References

struct HoverScene: View {
    @Environment(\.theme) private var theme
    let phase: Int
    var body: some View {
        SceneBookPage(activeReference: phase >= 1 ? "equation" : nil)
            .frame(width: 400, height: 250)
            .overlayPreferenceValue(SceneSpotKey.self) { spots in
                GeometryReader { proxy in
                    if phase >= 2, let anchor = spots["ref.equation"] {
                        let rect = proxy[anchor]
                        SceneCard(padding: 9) {
                            VStack(alignment: .leading, spacing: 6) {
                                HStack(spacing: 5) {
                                    SceneKindBadge(letter: "E", size: 13)
                                    Text("Equation (3.41)").font(.system(size: 10.5, weight: .semibold)).foregroundStyle(theme[.editorHoverWidgetForeground])
                                    Text("p. 61 · 4 refs").font(.system(size: 9.5)).foregroundStyle(theme[.descriptionForeground])
                                }
                                Text("β̂ = argmin { ‖y − Xβ‖² + λ‖β‖² }").font(.system(size: 13, design: .serif)).italic().foregroundStyle(.black)
                                    .padding(.horizontal, 10).padding(.vertical, 7)
                                    .background(RoundedRectangle(cornerRadius: 2).fill(Color.white))
                            }
                        }
                        .fixedSize()
                        .position(x: rect.midX + 40, y: rect.minY - 46)
                        .transition(.scale(scale: 0.92, anchor: .bottom).combined(with: .opacity))
                    }
                }
            }
            .scenePointer(at: phase >= 1 ? "ref.equation" : nil)
    }
}

struct PeekScene: View {
    @Environment(\.theme) private var theme
    let phase: Int
    var body: some View {
        VStack(spacing: 0) {
            SceneBookPage(activeReference: phase >= 1 ? "figure" : nil)
                .frame(width: 420, height: phase >= 2 ? 120 : 250, alignment: .top)
                .clipped()
            if phase >= 2 {
                VStack(spacing: 0) {
                    HStack(spacing: 6) {
                        SceneKindBadge(letter: "F", size: 13)
                        Text("Figure 3.8").font(.system(size: 10.5, weight: .semibold)).foregroundStyle(theme[.peekViewTitleLabelForeground])
                        Text("p. 65 · 2 refs").font(.system(size: 9.5)).foregroundStyle(theme[.peekViewTitleDescriptionForeground])
                        Spacer()
                        ForEach(Array(["Go to", "Pin", "Open to the Side", "Find All References"].enumerated()), id: \.offset) { index, action in
                            Text(action).font(.system(size: 9)).foregroundStyle(theme[.textLinkForeground])
                                .padding(.horizontal, 3)
                                .background(RoundedRectangle(cornerRadius: 3).fill(phase >= 4 && index == 0 ? theme.accent.opacity(0.2) : .clear))
                                .modifier(SpotIf(id: index == 0 ? "goto" : nil))
                        }
                        Codicon("close", size: 10).foregroundStyle(theme[.iconForeground])
                    }
                    .padding(.horizontal, 8).frame(height: 22)
                    .background(theme[.peekViewTitleBackground])
                    ZStack {
                        theme[.peekViewEditorBackground]
                        PageThemesFigure().frame(width: 200, height: 92).padding(6).background(Color.white)
                    }
                    .frame(height: 110)
                }
                .frame(width: 420)
                .overlay(RoundedRectangle(cornerRadius: 1).strokeBorder(theme[.peekViewBorder], lineWidth: 2))
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .scenePointer(at: phase >= 3 ? "goto" : phase >= 1 ? "ref.figure" : nil, clicks: phase >= 2 ? 1 : 0)
    }
}

/// The coefficient profiles drawn in several scenes.
struct PageThemesFigure: View {
    var body: some View {
        Canvas { context, size in
            let colors: [Color] = [.orange, .blue, Color(red: 0.2, green: 0.65, blue: 0.3), .purple, .red]
            for (index, color) in colors.enumerated() {
                var path = Path()
                let start = size.height * (0.1 + Double(index) * 0.13)
                path.move(to: CGPoint(x: 0, y: start))
                path.addCurve(to: CGPoint(x: size.width, y: size.height * 0.92), control1: CGPoint(x: size.width * 0.45, y: start),
                              control2: CGPoint(x: size.width * 0.6, y: size.height * (0.4 + Double(index) * 0.08)))
                context.stroke(path, with: .color(color), lineWidth: 1.5)
            }
            var axis = Path()
            axis.move(to: CGPoint(x: 0, y: size.height)); axis.addLine(to: CGPoint(x: size.width, y: size.height))
            context.stroke(axis, with: .color(.black.opacity(0.4)), lineWidth: 0.8)
        }
    }
}

/// A spinner for a scene: a quarter arc at rest (scenes do not spin forever).
struct SpinnerArc: View {
    @Environment(\.theme) private var theme
    @State private var angle = 0.0
    var body: some View {
        Circle().trim(from: 0, to: 0.7).stroke(theme.accent, style: StrokeStyle(lineWidth: 1.6, lineCap: .round))
            .rotationEffect(.degrees(angle))
            .onAppear { withAnimation(.linear(duration: 1.2)) { angle = 400 } }
    }
}

// MARK: - Terms and symbols

struct LookUpScene: View {
    @Environment(\.theme) private var theme
    let phase: Int
    var body: some View {
        HStack(alignment: .top, spacing: 18) {
            ScenePaper(padding: 14) {
                VStack(alignment: .leading, spacing: 6) {
                    ProseLines(widths: [180, 170])
                    HStack(spacing: 0) {
                        PaperText(text: "minimizing the ", size: 10.5)
                        Text("deviance").font(.system(size: 10.5, design: .serif)).foregroundStyle(.black)
                            .padding(.horizontal, 1).background(RoundedRectangle(cornerRadius: 2).fill(Color.accentColor.opacity(phase >= 1 ? 0.25 : 0)))
                            .sceneSpot("term")
                        PaperText(text: " of the fit", size: 10.5)
                    }
                    ProseLines(widths: [185, 160, 175, 120])
                }
            }
            .frame(width: 210, height: 180)
            if phase >= 2 {
                SceneCard(padding: 11, radius: 9) {
                    VStack(alignment: .leading, spacing: 9) {
                        section("DEFINED IN THE BOOK", 2) {
                            HStack(spacing: 4) {
                                Text("deviance").font(.system(size: 11, design: .serif)).italic()
                                Text("p. 221").font(.system(size: 9.5)).foregroundStyle(theme[.textLinkForeground])
                                Text("definition").font(.system(size: 8)).padding(.horizontal, 4).background(Capsule().fill(theme.tourFill))
                            }
                            Text("…is sometimes referred to as the **deviance**").font(.system(size: 9.5, design: .serif))
                        }
                        section("THE BOOK'S INDEX", 3) {
                            HStack(spacing: 4) {
                                Text("deviance").font(.system(size: 10.5))
                                ForEach(["221", "225", "247"], id: \.self) { page in
                                    Text(page).font(.system(size: 9)).padding(.horizontal, 4).background(Capsule().fill(theme.tourFill))
                                }
                            }
                        }
                        section("YOUR GLOSSARY", 4) { Text("Deviance · Definition · “−2 × log-likelihood”").font(.system(size: 10)) }
                        section("IN YOUR OTHER BOOKS", 5) {
                            HStack(spacing: 4) {
                                Codicon("library", size: 10)
                                Text("Bishop").font(.system(size: 10, weight: .semibold))
                                Text("deviance").font(.system(size: 10)).italic()
                                Text("definition").font(.system(size: 8)).padding(.horizontal, 4).background(Capsule().fill(theme.tourFill))
                            }
                        }
                    }
                    .foregroundStyle(theme[.editorHoverWidgetForeground])
                    .frame(width: 260, alignment: .leading)
                }
                .transition(.scale(scale: 0.95, anchor: .leading).combined(with: .opacity))
            }
        }
        .scenePointer(at: phase >= 1 && phase < 3 ? "term" : nil, clicks: phase >= 2 ? 1 : 0)
        .overlay(alignment: .bottomLeading) { ScenePressedKeys(keys: "⌘-click", pressed: phase == 1).offset(x: 40, y: 30) }
    }

    @ViewBuilder private func section<Content: View>(_ title: String, _ index: Int, @ViewBuilder content: () -> Content) -> some View {
        if phase >= index {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 8, weight: .bold)).tracking(0.5).foregroundStyle(theme[.descriptionForeground])
                content()
            }
            .transition(.opacity)
        }
    }
}

