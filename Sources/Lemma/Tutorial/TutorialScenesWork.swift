import SwiftUI
import AppKit
import LemmaCore

// Scenes about the reader's own work: the Lab, notes and marks, questions to ChatGPT, recall, research projects and
// search.

// MARK: - Lab

/// A notebook cell: its execution count, its code, and what it printed.
struct SceneCell<Output: View>: View {
    @Environment(\.theme) private var theme
    let count: String
    let code: [String]
    var selected = false
    var running = false
    @ViewBuilder var output: Output

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .top, spacing: 6) {
                Group {
                    if running { SpinnerArc().frame(width: 10, height: 10) } else { Text(count).font(.system(size: 9, design: .monospaced)).foregroundStyle(theme[.descriptionForeground]) }
                }
                .frame(width: 26, alignment: .trailing).padding(.top, 5)
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(code.enumerated()), id: \.offset) { _, line in SceneCode(line: line) }
                }
                .padding(6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 4).fill(theme[.notebookCellEditorBackground]))
                .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(selected ? theme[.notebookFocusedCellBorder] : theme.tourHairline, lineWidth: selected ? 1.5 : 1))
            }
            output.padding(.leading, 32)
        }
    }
}

extension SceneCell where Output == EmptyView {
    init(count: String, code: [String], selected: Bool = false, running: Bool = false) {
        self.init(count: count, code: code, selected: selected, running: running) { EmptyView() }
    }
}

/// A line of Python with keywords, numbers, strings and comments in the theme's token colours.
struct SceneCode: View {
    @Environment(\.theme) private var theme
    let line: String
    var body: some View {
        var text = Text("")
        for token in Self.tokens(line) {
            let color: Color = switch token.1 {
            case .keyword: Color(nsColor: theme.token(.keyword))
            case .number: Color(nsColor: theme.token(.number))
            case .string: Color(nsColor: theme.token(.string))
            case .comment: Color(nsColor: theme.token(.comment))
            case .function: Color(nsColor: theme.token(.function))
            default: theme[.editorForeground]
            }
            text = text + Text(token.0).foregroundColor(color)
        }
        return text.font(.system(size: 9.5, design: .monospaced)).lineLimit(1).fixedSize()
    }

    static func tokens(_ line: String) -> [(String, TokenRole)] {
        if let hash = line.firstIndex(of: "#") {
            return tokens(String(line[..<hash])) + [(String(line[hash...]), .comment)]
        }
        var result: [(String, TokenRole)] = []
        var word = ""
        func flush() {
            guard !word.isEmpty else { return }
            let keywords: Set<String> = ["import", "as", "for", "in", "def", "return", "from", "lambda", "print"]
            let role: TokenRole = keywords.contains(word) ? .keyword : Double(word) != nil ? .number : word.hasPrefix("\"") ? .string : .variable
            result.append((word, role)); word = ""
        }
        for character in line {
            if character.isLetter || character.isNumber || character == "_" || character == "." || character == "\"" { word.append(character) }
            else { flush(); result.append((String(character), .punctuation)) }
        }
        flush()
        return result
    }
}

/// The notebook's header: the flask, the title, the source page and the kernel.
struct SceneNotebookHeader: View {
    @Environment(\.theme) private var theme
    var title = "Equation (3.44)"
    var busy = false
    var body: some View {
        HStack(spacing: 6) {
            Codicon("notebook", size: 12).foregroundStyle(.orange)
            Text(title).font(.system(size: 11, weight: .semibold)).foregroundStyle(theme[.foreground])
            Text("p. 64").font(.system(size: 9.5)).foregroundStyle(theme[.descriptionForeground])
            Spacer()
            HStack(spacing: 4) {
                Circle().fill(busy ? Color.orange : theme[.testingIconPassed]).frame(width: 6, height: 6)
                Text(busy ? "Running" : "Python 3.13 · Ready").font(.system(size: 9))
            }
            .foregroundStyle(theme[.foreground])
            .padding(.horizontal, 7).frame(height: 17).background(Capsule().fill(theme.tourFill))
            Codicon("run-all", size: 12).foregroundStyle(theme[.iconForeground])
        }
        .padding(.horizontal, 10).frame(height: 28)
        .background(theme[.editorGroupHeaderTabsBackground])
    }
}

/// Coefficients shrinking as λ grows: the plot the Lab draws in the scenes.
struct SceneShrinkagePlot: View {
    var progress: Double = 1
    var body: some View {
        Canvas { context, size in
            let colors: [Color] = [Color(red: 0.12, green: 0.47, blue: 0.71), Color(red: 1, green: 0.5, blue: 0.05), Color(red: 0.17, green: 0.63, blue: 0.17),
                                   Color(red: 0.84, green: 0.15, blue: 0.16), Color(red: 0.58, green: 0.4, blue: 0.74)]
            let starts: [Double] = [0.15, 0.3, 0.75, 0.9, 0.55]
            for (index, color) in colors.enumerated() {
                var path = Path()
                let steps = 40
                for step in 0...Int(Double(steps) * progress) {
                    let t = Double(step) / Double(steps)
                    let y = 0.5 + (starts[index] - 0.5) * exp(-3.2 * t)
                    let point = CGPoint(x: t * size.width, y: y * size.height)
                    if step == 0 { path.move(to: point) } else { path.addLine(to: point) }
                }
                context.stroke(path, with: .color(color), lineWidth: 1.4)
            }
            var axis = Path()
            axis.move(to: CGPoint(x: 0, y: 0)); axis.addLine(to: CGPoint(x: 0, y: size.height)); axis.addLine(to: CGPoint(x: size.width, y: size.height))
            context.stroke(axis, with: .color(.black.opacity(0.5)), lineWidth: 0.8)
        }
    }
}

struct NotebookScene: View {
    @Environment(\.theme) private var theme
    let phase: Int
    var body: some View {
        HStack(spacing: 10) {
            ScenePaper(padding: 14) {
                VStack(alignment: .leading, spacing: 6) {
                    ProseLines(widths: [190, 170])
                    HStack {
                        Spacer()
                        SceneMath(source: "β̂ = (XᵀX + λI)^{−1}Xᵀy", size: 12).foregroundStyle(.black)
                            .background(Rectangle().fill(Color.accentColor.opacity(phase >= 1 ? 0.25 : 0)))
                        Spacer()
                        PaperText(text: "(3.44)", size: 10)
                    }
                    ProseLines(widths: [200, 150, 185, 170])
                }
            }
            .frame(width: 230, height: 200)
            .overlay(alignment: .top) {
                if phase >= 1 {
                    HStack(spacing: 8) {
                        ForEach(["Ask", "Note", "Lab", "Derive"], id: \.self) { item in
                            Text(item).font(.system(size: 9.5, weight: item == "Lab" ? .bold : .regular)).foregroundStyle(item == "Lab" ? theme.accent : theme[.foreground])
                                .modifier(SpotIf(id: item == "Lab" ? "lab" : nil))
                        }
                    }
                    .padding(.horizontal, 8).frame(height: 22)
                    .background(RoundedRectangle(cornerRadius: 5).fill(theme[.editorWidgetBackground]).shadow(radius: 4))
                    .offset(y: -26)
                }
            }
            if phase >= 2 {
                VStack(spacing: 0) {
                    SceneNotebookHeader()
                    VStack(alignment: .leading, spacing: 8) {
                        SceneMath(source: "β̂ = (XᵀX + λI)^{−1}Xᵀy   (3.44)", size: 11).foregroundStyle(.black)
                            .padding(6).frame(maxWidth: .infinity, alignment: .leading).background(RoundedRectangle(cornerRadius: 3).fill(.white))
                        SceneCell(count: "[ ]", code: ["import numpy as np", "beta = solve(X.T@X + lam*I, X.T@y)"], selected: phase >= 3)
                    }
                    .padding(10)
                    Spacer(minLength: 0)
                }
                .frame(width: 320, height: 220)
                .background(theme[.notebookEditorBackground])
                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                .shadow(color: .black.opacity(0.35), radius: 14, y: 8)
                .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .scenePointer(at: phase >= 1 && phase < 3 ? "lab" : nil, clicks: phase >= 2 ? 1 : 0)
    }
}

struct CellsScene: View {
    @Environment(\.theme) private var theme
    let phase: Int
    var body: some View {
        VStack(spacing: 0) {
            SceneNotebookHeader(busy: phase == 2 || phase == 4)
            VStack(alignment: .leading, spacing: 9) {
                SceneCell(count: phase >= 1 ? "[1]" : "[ ]", code: ["import numpy as np, matplotlib.pyplot as plt"], selected: phase == 1)
                SceneCell(count: phase >= 3 ? "[2]" : "[ ]", code: ["lams = np.logspace(-2, 4, 60)", "path = [ridge(X, y, l) for l in lams]", "plt.plot(lams, path); plt.xscale(\"log\")"],
                          selected: phase == 2 || phase == 3, running: phase == 2) {
                    if phase >= 3 {
                        SceneShrinkagePlot(progress: phase >= 3 ? 1 : 0).frame(width: 220, height: 70).padding(6).background(Color.white)
                            .transition(.opacity)
                    }
                }
                SceneCell(count: phase >= 5 ? "[3]" : "[ ]", code: ["np.linalg.norm(path[-1])"], selected: phase >= 4, running: phase == 4) {
                    if phase >= 5 {
                        HStack(spacing: 6) {
                            Text("Out[3]").font(.system(size: 9, design: .monospaced)).foregroundStyle(theme.accent)
                            Text("0.0127").font(.system(size: 9.5, design: .monospaced)).foregroundStyle(theme[.editorForeground])
                        }
                    }
                }
            }
            .padding(10)
            Spacer(minLength: 0)
        }
        .frame(width: 440, height: 290)
        .background(theme[.notebookEditorBackground])
        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        .shadow(color: .black.opacity(0.35), radius: 14, y: 8)
        .overlay(alignment: .trailing) {
            VStack(spacing: 8) {
                ScenePressedKeys(keys: "⇧↩", pressed: phase == 1 || phase == 2 || phase == 4)
                ScenePressedKeys(keys: "⌘↩", pressed: false)
                ScenePressedKeys(keys: "⌥↩", pressed: false)
            }
            .offset(x: 70)
        }
    }
}

struct ConsoleScene: View {
    @Environment(\.theme) private var theme
    let phase: Int
    private let entries: [(String, String)] = [("beta.shape", "(5,)"), ("np.trace(H)", "3.4172"), ("lam / (lam + d**2)", "array([0.12, 0.31, 0.58, 0.77, 0.9])")]
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Text("PROBLEMS").foregroundStyle(theme[.panelTitleInactiveForeground])
                Text("REFERENCES").foregroundStyle(theme[.panelTitleInactiveForeground])
                Text("CONSOLE").foregroundStyle(theme[.panelTitleActiveForeground]).overlay(alignment: .bottom) { Rectangle().fill(theme[.panelTitleActiveBorder]).frame(height: 1).offset(y: 4) }
                Spacer()
                Text("Notebook “Equation (3.44)” · shared variables").font(.system(size: 9)).foregroundStyle(theme[.descriptionForeground])
            }
            .font(.system(size: 9.5)).padding(.horizontal, 12).frame(height: 28)
            VStack(alignment: .leading, spacing: 3) {
                ForEach(Array(entries.enumerated()), id: \.offset) { index, entry in
                    if phase >= index + 1 {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text(">>>").font(.system(size: 9.5, design: .monospaced)).foregroundStyle(theme.accent)
                                SceneCode(line: entry.0)
                            }
                            if phase >= index + 2 || index == entries.count - 1 && phase >= 4 {
                                Text(entry.1).font(.system(size: 9.5, design: .monospaced)).foregroundStyle(theme[.terminalForeground])
                            }
                        }
                        .transition(.opacity)
                    }
                }
                HStack(spacing: 6) {
                    Text(">>>").font(.system(size: 9.5, design: .monospaced)).foregroundStyle(theme.accent)
                    Rectangle().fill(theme[.terminalCursorForeground]).frame(width: 6, height: 12)
                }
            }
            .padding(.horizontal, 14).padding(.top, 6)
            Spacer(minLength: 0)
        }
        .frame(width: 520, height: 200)
        .background(theme[.terminalBackground])
        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        .shadow(color: .black.opacity(0.35), radius: 14, y: 8)
        .overlay(alignment: .bottomTrailing) { ScenePressedKeys(keys: "⌃`", pressed: phase == 1).offset(x: 10, y: 26) }
    }
}

struct MarginFigureScene: View {
    @Environment(\.theme) private var theme
    let phase: Int
    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            ScenePaper(padding: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    PaperText(text: "Figure 3.8", size: 11, weight: .bold)
                    PageThemesFigure().frame(width: 160, height: 80)
                    ProseLines(widths: [180, 170, 150, 175])
                }
            }
            .frame(width: 230, height: 230)
            .overlay(alignment: .topTrailing) {
                if phase >= 2 {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("My ridge path").font(.system(size: 9, weight: .semibold)).foregroundStyle(.black)
                        SceneShrinkagePlot().frame(width: 110, height: 60)
                    }
                    .padding(6)
                    .background(RoundedRectangle(cornerRadius: 4).fill(Color(red: 1, green: 0.97, blue: 0.86)))
                    .overlay(alignment: .leading) { Rectangle().fill(Color(red: 0.8, green: 0.6, blue: 0.2)).frame(width: 2.5) }
                    .shadow(radius: 3)
                    .offset(x: 120, y: 30)
                    .transition(.scale(scale: 0.6).combined(with: .opacity))
                }
            }
            Spacer().frame(width: 120)
            if phase < 2 {
                VStack(spacing: 0) {
                    SceneNotebookHeader(title: "Ridge path")
                    SceneShrinkagePlot().frame(width: 170, height: 90).padding(8).background(Color.white).padding(8)
                        .overlay(alignment: .topTrailing) {
                            if phase >= 1 {
                                Text("Pin beside the page").font(.system(size: 9, weight: .semibold)).foregroundStyle(theme[.buttonForeground])
                                    .padding(.horizontal, 6).frame(height: 17).background(RoundedRectangle(cornerRadius: 4).fill(theme[.buttonBackground])).padding(12)
                                    .sceneSpot("pin")
                            }
                        }
                }
                .frame(width: 210)
                .background(theme[.notebookEditorBackground])
                .clipShape(RoundedRectangle(cornerRadius: 9))
                .shadow(color: .black.opacity(0.35), radius: 12, y: 6)
                .transition(.opacity)
            }
        }
        .scenePointer(at: phase == 1 ? "pin" : nil, clicks: phase >= 2 ? 1 : 0)
    }
}

// MARK: - Notes, marks and the edition

/// The selection bar's actions, as on the page.
struct SceneSelectionBar: View {
    @Environment(\.theme) private var theme
    var visible = 11
    var lit: String? = nil
    private let actions: [(String, String)] = [("comment-discussion", "Ask"), ("note", "Note"), ("comment", "Comment"), ("symbol-color", "Mark"), ("pin", "Pin"),
                                               ("notebook", "Lab"), ("symbol-operator", "Derive"), ("bracket", "LaTeX"), ("book", "Look Up"), ("folder-library", "Collect"), ("eye", "OCR")]
    var body: some View {
        HStack(spacing: 2) {
            Codicon("selection", size: 12).foregroundStyle(theme.accent).padding(.trailing, 4)
            ForEach(Array(actions.enumerated()), id: \.offset) { index, action in
                HStack(spacing: 3) { Codicon(action.0, size: 11); Text(action.1).font(.system(size: 9.5)) }
                    .foregroundStyle(theme[.foreground])
                    .padding(.horizontal, 4).frame(height: 19)
                    .background(RoundedRectangle(cornerRadius: 4).fill(lit == action.1 ? theme[.toolbarHoverBackground] : .clear))
                    .opacity(index < visible ? 1 : 0)
                    .modifier(SpotIf(id: "bar.\(action.1)"))
            }
        }
        .padding(.horizontal, 8).frame(height: 26)
        .background(theme[.editorWidgetBackground])
        .clipShape(RoundedRectangle(cornerRadius: 5))
        .shadow(color: .black.opacity(0.25), radius: 5, y: 2)
    }
}

struct SelectionScene: View {
    @Environment(\.theme) private var theme
    let phase: Int
    var body: some View {
        VStack(spacing: 10) {
            SceneSelectionBar(visible: phase >= 2 ? 11 : 0)
                .opacity(phase >= 2 ? 1 : 0)
            ZStack(alignment: .topLeading) {
                SceneBookPage(linked: false)
                    .frame(width: 420, height: 220)
                if phase >= 1 {
                    RoundedRectangle(cornerRadius: 2)
                        .strokeBorder(theme.accent, style: StrokeStyle(lineWidth: 1.5, dash: [5, 3]))
                        .background(RoundedRectangle(cornerRadius: 2).fill(theme.accent.opacity(0.1)))
                        .frame(width: phase >= 2 ? 290 : 120, height: 30)
                        .offset(x: 54, y: 76)
                        .animation(.easeOut(duration: 0.7), value: phase)
                }
            }
        }
        .overlay(alignment: .bottomTrailing) { ScenePressedKeys(keys: "⇧⌘S", pressed: phase == 1).offset(x: 40, y: 10) }
    }
}

struct NoteScene: View {
    @Environment(\.theme) private var theme
    let phase: Int
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                ForEach(["Question", "Definition", "Notation", "Theorem"], id: \.self) { kind in
                    Text(kind).font(.system(size: 10, weight: kind == "Question" ? .semibold : .regular))
                        .foregroundStyle(kind == "Question" ? theme[.buttonForeground] : theme[.foreground])
                        .padding(.horizontal, 8).frame(height: 20)
                        .background(Capsule().fill(kind == "Question" ? theme[.buttonBackground] : theme.tourFill))
                }
                Spacer()
                HStack(spacing: 0) {
                    ForEach(["Write", "Preview"], id: \.self) { mode in
                        let on = (mode == "Preview") == (phase >= 4)
                        Text(mode).font(.system(size: 9.5, weight: on ? .semibold : .regular)).foregroundStyle(on ? theme[.buttonForeground] : theme[.foreground])
                            .padding(.horizontal, 7).frame(height: 18).background(Capsule().fill(on ? theme[.buttonBackground] : .clear))
                    }
                }
                .padding(2).background(Capsule().fill(theme.tourFill))
            }
            SceneMath(source: "β̂ = (XᵀX + λI)^{−1}Xᵀy   (3.44) · p. 64", size: 11.5).foregroundStyle(.black)
                .padding(8).frame(maxWidth: .infinity, alignment: .leading).background(RoundedRectangle(cornerRadius: 3).fill(.white))
                .opacity(phase >= 1 ? 1 : 0)
            Group {
                if phase >= 4 {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Why is XᵀX + λI invertible?").font(.system(size: 13, weight: .bold))
                        Text("Because XᵀX is positive semidefinite and λ > 0, every eigenvalue of XᵀX + λI is at least λ.").font(.system(size: 11))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .transition(.opacity)
                } else {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("# Why is $X^TX + \\lambda I$ invertible?").font(.system(size: 10, design: .monospaced))
                        Text(phase >= 3 ? "Because $X^TX \\succeq 0$ and $\\lambda > 0$, every…" : "").font(.system(size: 10, design: .monospaced))
                    }
                    .opacity(phase >= 2 ? 1 : 0)
                }
            }
            .foregroundStyle(theme[.foreground])
            HStack(spacing: 8) {
                Text("ASSUMPTIONS").font(.system(size: 8.5, weight: .bold)).foregroundStyle(theme[.descriptionForeground])
                Text("λ > 0").font(.system(size: 10)).padding(.horizontal, 6).frame(height: 17).background(Capsule().fill(theme.tourFill)).foregroundStyle(theme[.foreground])
            }
            .opacity(phase >= 3 ? 1 : 0)
        }
        .padding(14)
        .frame(width: 440)
        .background(RoundedRectangle(cornerRadius: 10).fill(theme[.sideBarBackground]).shadow(color: .black.opacity(0.35), radius: 14, y: 8))
        .overlay(alignment: .bottomTrailing) { ScenePressedKeys(keys: "⌘N", pressed: phase == 1).offset(x: 30, y: 20) }
    }
}

struct HighlightScene: View {
    @Environment(\.theme) private var theme
    let phase: Int
    var body: some View {
        HStack(spacing: 20) {
            ZStack(alignment: .topLeading) {
                SceneBookPage(linked: false).frame(width: 400, height: 240)
                Rectangle().fill(Color.yellow.opacity(0.45)).frame(width: phase >= 1 ? 250 : 0, height: 13).offset(x: 18, y: 50)
                    .animation(.easeOut(duration: 0.6), value: phase)
                Rectangle().fill(Color.blue.opacity(0.85)).frame(width: phase >= 2 ? 170 : 0, height: 1.5).offset(x: 18, y: 155)
                    .animation(.easeOut(duration: 0.6), value: phase)
                BookmarkRibbon().fill(theme.accent).frame(width: 16, height: phase >= 3 ? 30 : 0).offset(x: 360, y: 0)
            }
            VStack(alignment: .leading, spacing: 9) {
                row("⇧⌘H", "Highlight", phase >= 1)
                row("⇧⌘U", "Underline", phase >= 2)
                row("⌘D", "Bookmark", phase >= 3)
            }
        }
    }

    private func row(_ keys: String, _ title: String, _ lit: Bool) -> some View {
        HStack(spacing: 8) { ScenePressedKeys(keys: keys, pressed: lit); Text(title).font(.system(size: 12.5, weight: .semibold)).foregroundStyle(lit ? theme.tourText : theme.tourTertiary) }
    }
}

struct BookmarkRibbon: Shape {
    func path(in rect: CGRect) -> Path {
        Path { path in
            path.move(to: .zero); path.addLine(to: CGPoint(x: rect.maxX, y: 0)); path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY - min(6, rect.height * 0.25))); path.addLine(to: CGPoint(x: 0, y: rect.maxY)); path.closeSubpath()
        }
    }
}

struct GlossaryScene: View {
    @Environment(\.theme) private var theme
    let phase: Int
    var body: some View {
        HStack(alignment: .top, spacing: 18) {
            SceneSideBar(title: "Glossary", width: 280) {
                entry(1, "Design matrix", kind: "Definition", names: "X · design matrix", scope: "Chapter 3")
                entry(2, "Complexity parameter", kind: "Notation", names: "λ", scope: "Ridge, lasso")
                entry(3, "Gauss-Markov", kind: "Theorem", names: "BLUE", scope: "Linear models")
            }
            .frame(height: 220)
            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            .shadow(color: .black.opacity(0.35), radius: 14, y: 8)
            if phase >= 4 {
                SceneCard(padding: 10) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("YOUR GLOSSARY").font(.system(size: 8, weight: .bold)).foregroundStyle(theme[.descriptionForeground])
                        HStack(spacing: 6) {
                            Text("X").font(.system(size: 18, design: .serif)).italic()
                            VStack(alignment: .leading, spacing: 1) {
                                Text("Design matrix").font(.system(size: 11, weight: .semibold))
                                Text("Definition · Chapter 3").font(.system(size: 9.5)).foregroundStyle(theme[.descriptionForeground])
                            }
                        }
                    }
                    .foregroundStyle(theme[.editorHoverWidgetForeground])
                }
                .transition(.scale(scale: 0.9).combined(with: .opacity))
            }
        }
    }

    @ViewBuilder private func entry(_ index: Int, _ title: String, kind: String, names: String, scope: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(title).font(.system(size: 11, weight: .semibold)).foregroundStyle(theme[.foreground])
                Spacer()
                Text(kind).font(.system(size: 8.5, weight: .semibold)).foregroundStyle(theme[.foreground]).padding(.horizontal, 5).frame(height: 14).background(Capsule().fill(theme.tourFill))
            }
            Text("Lookup names: \(names)").font(.system(size: 9.5, design: .monospaced)).foregroundStyle(theme[.descriptionForeground])
            Text("Scope: \(scope)").font(.system(size: 9.5)).foregroundStyle(theme[.descriptionForeground])
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .opacity(phase >= index ? 1 : 0)
    }
}

struct InkScene: View {
    @Environment(\.theme) private var theme
    let phase: Int
    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                HStack(spacing: 0) {
                    Text("Pen").font(.system(size: 10, weight: .semibold)).padding(.horizontal, 8).frame(height: 18).background(Capsule().fill(theme[.buttonBackground])).foregroundStyle(theme[.buttonForeground])
                    Text("Eraser").font(.system(size: 10)).padding(.horizontal, 8).frame(height: 18).foregroundStyle(theme[.foreground])
                }
                .padding(2).background(Capsule().fill(theme.tourFill))
                ForEach([Color.red, .blue, Color(red: 0.2, green: 0.6, blue: 0.3), .black], id: \.self) { color in Circle().fill(color).frame(width: 12, height: 12) }
                Spacer()
                HStack(spacing: 0) {
                    ForEach(["Original", "My Edition"], id: \.self) { mode in
                        let on = (mode == "My Edition") == (phase != 4)
                        Text(mode).font(.system(size: 10, weight: on ? .semibold : .regular)).padding(.horizontal, 8).frame(height: 18)
                            .background(Capsule().fill(on ? theme[.buttonBackground] : .clear)).foregroundStyle(on ? theme[.buttonForeground] : theme[.foreground])
                    }
                }
                .padding(2).background(Capsule().fill(theme.tourFill))
            }
            .padding(.horizontal, 8).frame(width: 440, height: 28)
            .background(RoundedRectangle(cornerRadius: 6).fill(theme[.editorWidgetBackground]))
            ZStack(alignment: .topLeading) {
                SceneBookPage(linked: false).frame(width: 440, height: 230)
                if phase != 4 {
                    Ellipse().trim(from: 0, to: phase >= 1 ? 1 : 0).stroke(Color.red, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                        .frame(width: 230, height: 32).offset(x: 110, y: 74)
                        .animation(.easeInOut(duration: 0.7), value: phase)
                    Path { path in
                        path.move(to: CGPoint(x: 350, y: 120)); path.addQuadCurve(to: CGPoint(x: 300, y: 95), control: CGPoint(x: 345, y: 95))
                        path.move(to: CGPoint(x: 300, y: 95)); path.addLine(to: CGPoint(x: 310, y: 88)); path.move(to: CGPoint(x: 300, y: 95)); path.addLine(to: CGPoint(x: 311, y: 101))
                    }
                    .trim(from: 0, to: phase >= 2 ? 1 : 0).stroke(Color.blue, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                    .animation(.easeInOut(duration: 0.6), value: phase)
                    Text("check!").font(.custom("Bradley Hand", size: 18)).foregroundStyle(Color.blue).offset(x: 352, y: 112).opacity(phase >= 3 ? 1 : 0)
                }
            }
        }
    }
}

// MARK: - Asking

struct AskScene: View {
    @Environment(\.theme) private var theme
    let phase: Int
    private let styles = ["Explain", "Hint", "Next step", "Why?", "Intuition", "Example", "Counterexample", "Figure", "Code"]
    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            ScenePaper(padding: 14) {
                VStack(alignment: .leading, spacing: 6) {
                    ProseLines(widths: [180, 170])
                    SceneMath(source: "β̂ = (XᵀX + λI)^{−1}Xᵀy", size: 12).foregroundStyle(.black)
                        .background(Rectangle().fill(Color.accentColor.opacity(0.25)))
                    ProseLines(widths: [190, 160, 175])
                }
            }
            .frame(width: 210, height: 170)
            if phase >= 1 {
                SceneCard(padding: 12, radius: 10) {
                    VStack(alignment: .leading, spacing: 9) {
                        SceneMath(source: "β̂ = (XᵀX + λI)^{−1}Xᵀy", size: 11).foregroundStyle(.black)
                            .padding(6).frame(maxWidth: .infinity, alignment: .leading).background(RoundedRectangle(cornerRadius: 3).fill(.white))
                        Text(phase >= 2 ? "Why is this matrix always invertible?" : "What don't you understand? (optional)")
                            .font(.system(size: 10.5)).foregroundStyle(phase >= 2 ? theme[.inputForeground] : theme[.inputPlaceholderForeground])
                            .padding(6).frame(maxWidth: .infinity, alignment: .leading)
                            .background(RoundedRectangle(cornerRadius: 4).fill(theme[.inputBackground]))
                        FlowChips(items: styles, selected: phase >= 3 ? "Why?" : "Explain")
                        HStack {
                            Text("3 images · glossary: names, notation, scope").font(.system(size: 9)).foregroundStyle(theme[.descriptionForeground])
                            Spacer()
                            ScenePressedKeys(keys: "↩", pressed: phase >= 4)
                        }
                    }
                    .frame(width: 300)
                }
                .transition(.scale(scale: 0.92, anchor: .leading).combined(with: .opacity))
            }
        }
        .overlay(alignment: .bottomLeading) { ScenePressedKeys(keys: "⌘K", pressed: phase == 1).offset(x: 70, y: 30) }
    }
}

/// Capsules that wrap onto several lines.
struct FlowChips: View {
    @Environment(\.theme) private var theme
    let items: [String]
    var selected: String? = nil
    var body: some View {
        let rows = [Array(items.prefix(5)), Array(items.dropFirst(5))]
        VStack(alignment: .leading, spacing: 5) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(spacing: 5) {
                    ForEach(row, id: \.self) { item in
                        Text(item).font(.system(size: 9.5, weight: item == selected ? .semibold : .regular))
                            .foregroundStyle(item == selected ? theme[.buttonForeground] : theme[.foreground])
                            .padding(.horizontal, 7).frame(height: 18)
                            .background(Capsule().fill(item == selected ? theme[.buttonBackground] : theme.tourFill))
                    }
                }
            }
        }
    }
}

struct AskContextScene: View {
    @Environment(\.theme) private var theme
    let phase: Int
    private let items: [(String, String, Bool)] = [
        ("text.quote", "Passage text · p. 64", true), ("list.bullet.indent", "Section 3.4.1 Ridge Regression", true), ("photo", "Equation (3.41) · image", true),
        ("photo", "Figure 3.8 · image", true), ("character.book.closed", "Glossary: λ complexity parameter (names, notation and scope)", true), ("link", "Linked notes", false)
    ]
    var body: some View {
        SceneWindow(title: "Prepare Question") {
            VStack(alignment: .leading, spacing: 0) {
                Text("FROM THE BOOK · YOUR GLOSSARY · LINKED NOTES").font(.system(size: 8.5, weight: .bold)).foregroundStyle(theme[.descriptionForeground])
                    .padding(.horizontal, 14).padding(.top, 10).padding(.bottom, 6)
                ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                    HStack(spacing: 8) {
                        RoundedRectangle(cornerRadius: 3).fill(item.2 ? theme.accent : theme[.checkboxBackground]).frame(width: 13, height: 13)
                            .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(theme[.checkboxBorder], lineWidth: item.2 ? 0 : 1))
                            .overlay { if item.2 { Codicon("check", size: 10).foregroundStyle(.white) } }
                        Image(systemName: item.0).font(.system(size: 10)).foregroundStyle(theme[.descriptionForeground]).frame(width: 14)
                        Text(item.1).font(.system(size: 10.5)).foregroundStyle(theme[.foreground]).lineLimit(1)
                        Spacer()
                    }
                    .padding(.horizontal, 14).frame(height: 22)
                    .opacity(phase >= index + 1 ? 1 : 0)
                    .offset(x: phase >= index + 1 ? 0 : -8)
                }
                Spacer(minLength: 4)
                HStack {
                    Text("4 images").font(.system(size: 9.5)).foregroundStyle(theme[.descriptionForeground])
                    Spacer()
                    Text("Full draft…").font(.system(size: 10)).foregroundStyle(theme[.textLinkForeground])
                    Text("Ask").font(.system(size: 10, weight: .semibold)).foregroundStyle(theme[.buttonForeground])
                        .padding(.horizontal, 8).frame(height: 20).background(RoundedRectangle(cornerRadius: 4).fill(theme[.buttonBackground]))
                }
                .padding(.horizontal, 14).padding(.bottom, 10)
            }
        }
        .frame(width: 460, height: 250)
    }
}

struct ChromeScene: View {
    @Environment(\.theme) private var theme
    let phase: Int
    var body: some View {
        HStack(spacing: 0) {
            SceneWindow(title: "Lemma") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Question note · p. 64").font(.system(size: 10.5, weight: .semibold))
                    Text("Why is XᵀX + λI invertible?").font(.system(size: 10.5))
                    if phase >= 4 {
                        Text("Answer saved · Check 2 steps").font(.system(size: 10, weight: .semibold)).foregroundStyle(theme[.testingIconPassed])
                            .transition(.opacity)
                    }
                    Spacer()
                }
                .foregroundStyle(theme[.foreground])
                .padding(10).frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(width: 200, height: 170)
            ZStack {
                VStack(spacing: 4) {
                    Codicon("arrow-right", size: 18).foregroundStyle(theme.accent).opacity(phase >= 1 ? 1 : 0.2)
                    Text(phase >= 3 ? "Answer saved" : "Send now").font(.system(size: 10, weight: .semibold)).foregroundStyle(theme.tourText)
                    Codicon("arrow-left", size: 18).foregroundStyle(theme.accent).opacity(phase >= 3 ? 1 : 0.2)
                }
                Circle().fill(theme.accent).frame(width: 9, height: 9).offset(x: phase >= 1 && phase < 3 ? 60 : phase >= 3 ? -60 : -60, y: phase >= 3 ? 24 : -24)
                    .opacity(phase >= 1 ? 1 : 0)
                    .animation(.easeInOut(duration: 0.7), value: phase)
            }
            .frame(width: 150)
            SceneWindow(title: "ChatGPT Web · inside Lemma") {
                VStack(alignment: .trailing, spacing: 8) {
                    if phase >= 2 {
                        Text("Why is XᵀX + λI invertible? [passage, (3.41), section…]").font(.system(size: 9.5)).foregroundStyle(theme[.foreground])
                            .padding(7).background(RoundedRectangle(cornerRadius: 10).fill(theme.tourFill))
                            .transition(.opacity)
                    }
                    if phase >= 3 {
                        Text("XᵀX is positive semidefinite, so adding λI with λ > 0 makes every eigenvalue positive…").font(.system(size: 9.5)).foregroundStyle(theme[.foreground])
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .transition(.opacity)
                    }
                    Spacer()
                }
                .padding(10)
            }
            .frame(width: 230, height: 170)
        }
    }
}

// MARK: - Recall

struct ReviewScene: View {
    @Environment(\.theme) private var theme
    let phase: Int
    var body: some View {
        HStack(spacing: 20) {
            ZStack {
                if phase < 2 {
                    card {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("RECALL").font(.system(size: 9, weight: .bold)).tracking(1).foregroundStyle(theme[.descriptionForeground])
                            Text("State Theorem 3.2 and its hypotheses.").font(.system(size: 14, weight: .semibold)).foregroundStyle(theme[.foreground])
                            HStack(spacing: 4) {
                                ForEach(0..<3) { _ in RoundedRectangle(cornerRadius: 2).fill(theme.accent.opacity(0.5)).frame(width: 52, height: 12) }
                            }
                            Text("The source is hidden on the page while you try.").font(.system(size: 10)).foregroundStyle(theme[.descriptionForeground])
                        }
                    }
                    .transition(.asymmetric(insertion: .opacity, removal: .scale(scale: 0.9).combined(with: .opacity)))
                } else {
                    card {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("THEOREM 3.2 · p. 51").font(.system(size: 9, weight: .bold)).tracking(1).foregroundStyle(theme[.descriptionForeground])
                            Text("Among linear unbiased estimates of aᵀβ, least squares has the smallest variance (errors uncorrelated, equal variance).")
                                .font(.system(size: 11.5, design: .serif)).foregroundStyle(theme[.foreground]).fixedSize(horizontal: false, vertical: true)
                            HStack(spacing: 6) {
                                grade("Again", "⌘1", lit: false); grade("Hard", "⌘2", lit: false); grade("Good", "⌘3", lit: phase >= 3); grade("Easy", "⌘4", lit: false)
                            }
                            if phase >= 4 { Text("Next recall in 4 days").font(.system(size: 10, weight: .semibold)).foregroundStyle(theme.accent).transition(.opacity) }
                        }
                    }
                    .transition(.scale(scale: 1.05).combined(with: .opacity))
                }
            }
            .frame(width: 340, height: 210)
            VStack(spacing: 8) {
                ScenePressedKeys(keys: "⇧⌘R", pressed: phase == 1)
                ScenePressedKeys(keys: "⌘↩", pressed: phase == 2)
            }
        }
    }

    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .padding(16)
            .frame(width: 340, height: 200, alignment: .topLeading)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(theme[.editorWidgetBackground]).shadow(color: .black.opacity(0.35), radius: 14, y: 8))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(theme.tourHairline, lineWidth: 1))
    }

    private func grade(_ title: String, _ keys: String, lit: Bool) -> some View {
        VStack(spacing: 2) {
            Text(title).font(.system(size: 10, weight: .semibold)).foregroundStyle(lit ? theme[.buttonForeground] : theme[.foreground])
            Text(keys).font(.system(size: 8)).foregroundStyle(lit ? theme[.buttonForeground].opacity(0.8) : theme[.descriptionForeground])
        }
        .frame(width: 62, height: 32)
        .background(RoundedRectangle(cornerRadius: 6).fill(lit ? theme[.buttonBackground] : theme.tourFill))
    }
}

// MARK: - Research projects

struct ProjectScene: View {
    @Environment(\.theme) private var theme
    let phase: Int
    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            SceneSideBar(title: "Projects", width: 190) {
                SceneRow(icon: "folder-library", iconColor: .yellow, title: "Ridge or lasso?", selected: true)
                ForEach(["ESL", "ISLR", "Bishop · PRML"], id: \.self) { book in
                    SceneRow(icon: "file-pdf", iconColor: Color(red: 0.9, green: 0.3, blue: 0.3), title: book, depth: 1)
                        .opacity(phase >= 2 ? 1 : 0)
                }
                SceneRow(icon: "folder-library", iconColor: .yellow, title: "Bootstrap intervals")
            }
            VStack(alignment: .leading, spacing: 8) {
                Text("When is ridge better than the lasso?").font(.system(size: 13, weight: .bold)).foregroundStyle(theme[.foreground])
                    .opacity(phase >= 1 ? 1 : 0)
                VStack(alignment: .leading, spacing: 4) {
                    Text("## Synthesis").font(.system(size: 10, design: .monospaced))
                    Text(phase >= 3 ? "Ridge keeps every predictor [S1]; the lasso sets some" : "").font(.system(size: 10, design: .monospaced))
                    Text(phase >= 3 ? "to zero [S2], which helps when few matter [S3]." : "").font(.system(size: 10, design: .monospaced))
                }
                .foregroundStyle(theme[.editorForeground])
                .padding(8).frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 5).fill(theme[.inputBackground]))
                Text("SOURCES").font(.system(size: 8.5, weight: .bold)).foregroundStyle(theme[.descriptionForeground])
                ForEach(Array([("S1", "ESL · p. 61"), ("S2", "ESL · p. 68"), ("S3", "ISLR · p. 242")].enumerated()), id: \.offset) { index, source in
                    HStack(spacing: 6) {
                        Text(source.0).font(.system(size: 9.5, weight: .bold)).foregroundStyle(theme[.buttonForeground]).padding(.horizontal, 5).frame(height: 15)
                            .background(Capsule().fill(theme[.buttonBackground]))
                        Text(source.1).font(.system(size: 10)).foregroundStyle(theme[.foreground])
                        RoundedRectangle(cornerRadius: 2).fill(.white).frame(width: 60, height: 12)
                    }
                    .opacity(phase >= 4 ? 1 : 0)
                    .animation(.spring(response: 0.5, dampingFraction: 0.8).delay(Double(index) * 0.1), value: phase)
                }
                Spacer(minLength: 0)
            }
            .padding(12)
            .frame(width: 330)
            .background(theme[.editorBackground])
        }
        .frame(height: 250)
        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        .shadow(color: .black.opacity(0.35), radius: 14, y: 8)
    }
}

// MARK: - Search

struct SearchScene: View {
    @Environment(\.theme) private var theme
    let phase: Int
    var body: some View {
        SceneSideBar(title: "Search", width: 400) {
            HStack(spacing: 6) {
                Text(phase >= 1 ? "ridge" : "Search").font(.system(size: 11)).foregroundStyle(phase >= 1 ? theme[.inputForeground] : theme[.inputPlaceholderForeground])
                Spacer()
                Text("Aa").font(.system(size: 9.5, weight: .semibold)).foregroundStyle(theme[.iconForeground])
                Text("ab").font(.system(size: 9.5, weight: .semibold)).underline().foregroundStyle(theme[.iconForeground])
            }
            .padding(.horizontal, 7).frame(height: 24)
            .background(RoundedRectangle(cornerRadius: 3).fill(theme[.inputBackground]))
            .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(theme[.focusBorder], lineWidth: 1))
            .padding(.horizontal, 8)
            HStack(spacing: 8) {
                Text("This book").font(.system(size: 9.5)).foregroundStyle(theme[.descriptionForeground])
                Text("Every book").font(.system(size: 9.5, weight: .semibold)).foregroundStyle(theme[.buttonForeground]).padding(.horizontal, 6).frame(height: 15).background(Capsule().fill(theme[.buttonBackground]))
                Spacer()
                Text(phase >= 2 ? "37 results in 3 books" : "").font(.system(size: 9.5)).foregroundStyle(theme[.descriptionForeground])
            }
            .padding(.horizontal, 10).padding(.vertical, 6)
            book("Elements of Statistical Learning", count: 24, index: 2, lines: ["…Ridge regression shrinks the coefficients…", "…the ridge solutions are linear in y…"])
            book("Introduction to Statistical Learning", count: 9, index: 3, lines: ["…ridge regression and the lasso…"])
            book("Pattern Recognition and Machine Learning", count: 4, index: 4, lines: ["…known as ridge regression in statistics…"])
        }
        .frame(height: 280)
        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        .shadow(color: .black.opacity(0.35), radius: 14, y: 8)
    }

    @ViewBuilder private func book(_ title: String, count: Int, index: Int, lines: [String]) -> some View {
        if phase >= index {
            VStack(alignment: .leading, spacing: 0) {
                SceneRow(icon: "file-pdf", iconColor: Color(red: 0.9, green: 0.3, blue: 0.3), title: title) { VSBadge(count: count).scaleEffect(0.8) }
                ForEach(lines, id: \.self) { line in
                    highlighted(line).padding(.leading, 30).frame(height: 18, alignment: .leading)
                }
            }
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }

    private func highlighted(_ line: String) -> some View {
        let parts = line.components(separatedBy: "idge")
        var text = Text("")
        for (index, part) in parts.enumerated() {
            text = text + Text(part)
            if index < parts.count - 1 { text = text + Text("idge").bold().foregroundColor(theme[.listHighlightForeground]) }
        }
        return text.font(.system(size: 10)).foregroundStyle(theme[.sideBarForeground]).lineLimit(1)
    }
}

