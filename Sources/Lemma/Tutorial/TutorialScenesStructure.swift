import SwiftUI
import AppKit
import LemmaCore

// Scenes about the structure of a mathematical text: results, proofs, dependencies, the reading ruler, the proof
// debugger and checked derivations.

/// A theorem and its proof, line by line, for the scenes that walk through a proof.
struct SceneProofPage: View {
    @Environment(\.theme) private var theme
    var current: Int? = nil
    var veiled = false
    var debugging = false
    var foldedProof = false
    var understood = false
    var marks: Set<Int> = []
    var breakpoints: Set<Int> = []
    static let lines: [(String, Bool)] = [
        ("Theorem 3.2 (Gauss-Markov).  The least squares", true),
        ("estimate of aᵀβ has the smallest variance among", true),
        ("all linear unbiased estimates.", true),
        ("Proof.  Let cᵀy be another unbiased estimate.", false),
        ("By Lemma 3.1, E(cᵀy) = aᵀβ for every β,", false),
        ("so cᵀX = aᵀ. Then by (3.12),", false),
        ("Var(cᵀy) = Var(aᵀβ̂) + σ²‖c − X(XᵀX)^{−1}a‖²,", false),
        ("which is at least Var(aᵀβ̂).  □", false)
    ]

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            VStack(spacing: 0) {
                ForEach(0..<Self.lines.count, id: \.self) { index in
                    ZStack {
                        if breakpoints.contains(index) { Circle().fill(theme[.debugIconBreakpointForeground]).frame(width: 8, height: 8) }
                        if marks.contains(index) { Codicon("question", size: 11).foregroundStyle(.orange) }
                        if debugging && current == index { Codicon("debug-stackframe", size: 12).foregroundStyle(theme[.debugIconBreakpointCurrentStackframeForeground]) }
                        if index == 0 && understood { Codicon("verified-filled", size: 12).foregroundStyle(theme[.testingIconPassed]) }
                        if index == 3 && !debugging && marks.isEmpty && breakpoints.isEmpty {
                            Codicon(foldedProof ? "chevron-right" : "chevron-down", size: 11).foregroundStyle(foldedProof ? theme.accent : theme.tourTertiary)
                        }
                    }
                    .frame(width: 18, height: 21)
                }
            }
            .padding(.top, 16)
            ScenePaper(padding: 16) {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(0..<Self.lines.count, id: \.self) { index in
                        let line = Self.lines[index]
                        SceneMath.text(line.0, size: 11, italic: line.1 && index > 0)
                            .fontWeight(index == 0 || index == 3 ? .semibold : .regular)
                            .foregroundStyle(Color(red: 0.08, green: 0.08, blue: 0.1))
                            .lineLimit(1).fixedSize()
                            .frame(height: 21, alignment: .leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background {
                                if current == index {
                                    Rectangle().fill(debugging ? Color(red: 1, green: 0.85, blue: 0.2).opacity(0.42) : theme.paperAccent.opacity(0.13))
                                        .padding(.horizontal, -6)
                                        .overlay(alignment: .leading) { if !debugging { Rectangle().fill(theme.paperAccent).frame(width: 3).offset(x: -6) } }
                                }
                            }
                            .opacity(veiled && current != index ? 0.32 : 1)
                            .sceneSpot("line\(index)")
                    }
                }
                .overlay(alignment: .topLeading) {
                    if foldedProof {
                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 5) {
                                Codicon("chevron-right", size: 11).foregroundStyle(Color(red: 0.42, green: 0.44, blue: 0.1))
                                Text("Proof of Theorem 3.2 · folded").font(.system(size: 10.5, weight: .semibold, design: .serif)).foregroundStyle(.black)
                            }
                            Text("5 lines, try it yourself, then click to unfold").font(.system(size: 9.5, design: .serif)).foregroundStyle(.gray)
                        }
                        .padding(.horizontal, 10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .frame(height: 21 * 5 - 4)
                        .background(RoundedRectangle(cornerRadius: 4).fill(Color(red: 0.984, green: 0.98, blue: 0.96)))
                        .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Color(red: 0.42, green: 0.44, blue: 0.1).opacity(0.6), style: StrokeStyle(lineWidth: 1, dash: [3, 2])))
                        .sceneSpot("fold")
                        .padding(.top, 21 * 3 + 2)
                        .transition(.move(edge: .top).combined(with: .opacity))
                    }
                }
            }
        }
    }
}

// MARK: - Results

struct ResultsScene: View {
    @Environment(\.theme) private var theme
    let phase: Int
    private let rows: [(String, String, String, Int, Bool)] = [
        ("D", "Definition 3.1", "Ridge estimator", 5, true), ("T", "Theorem 3.2", "Gauss-Markov", 7, false), ("L", "Lemma 3.3", "Shrinkage of the eigenvalues", 2, true),
        ("P", "Proposition 3.4", "Effective degrees of freedom", 3, false), ("C", "Corollary 3.5", "Bias of the ridge fit", 1, false), ("E", "Example 3.6", "Prostate cancer data", 0, false)
    ]
    var body: some View {
        SceneSideBar(title: "Structure", width: 380) {
            HStack(spacing: 8) {
                SceneRing(value: phase >= 5 ? 13 / 48 : 12 / 48, size: 18, line: 2.5)
                Text(phase >= 5 ? "13 of 48 understood" : "12 of 48 understood").font(.system(size: 10.5, weight: .medium)).foregroundStyle(theme[.foreground])
                Spacer()
                HStack(spacing: 3) { Codicon("fold", size: 10); Text("Fold Proofs") }.font(.system(size: 9.5)).foregroundStyle(theme[.textLinkForeground])
            }
            .padding(.horizontal, 10).padding(.bottom, 6)
            HStack(spacing: 5) {
                ForEach(["All", "Definitions", "Results", "Examples"], id: \.self) { chip in
                    Text(chip).font(.system(size: 9)).foregroundStyle(chip == "All" ? theme[.buttonForeground] : theme[.foreground])
                        .padding(.horizontal, 7).frame(height: 15).background(Capsule().fill(chip == "All" ? theme[.buttonBackground] : theme.tourFill))
                }
            }
            .padding(.horizontal, 10).padding(.bottom, 6)
            SceneRow(icon: "chevron-down", title: "3  Linear Methods for Regression", height: 20)
            ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                HStack(spacing: 6) {
                    SceneKindBadge(letter: row.0, size: 14)
                    Text(row.1).font(.system(size: 10.5, weight: index == 1 ? .semibold : .regular)).foregroundStyle(theme[.sideBarForeground])
                    Text(row.2).font(.system(size: 9.5)).foregroundStyle(theme[.descriptionForeground]).lineLimit(1)
                    Spacer()
                    if row.3 > 0 { Text("used \(row.3)×").font(.system(size: 9)).foregroundStyle(theme[.descriptionForeground].opacity(0.8)) }
                    let done = row.4 || (index == 1 && phase >= 5)
                    Codicon(done ? "pass-filled" : "circle-large-outline", size: 12).foregroundStyle(done ? theme[.testingIconPassed] : theme[.descriptionForeground])
                        .modifier(SpotIf(id: index == 1 ? "understood" : nil))
                }
                .padding(.leading, 20).padding(.trailing, 10).frame(height: 21)
                .background(index == 1 && phase >= 4 ? theme[.listHoverBackground] : .clear)
                .opacity(phase >= 1 + index / 2 ? 1 : 0)
            }
        }
        .frame(height: 280)
        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        .shadow(color: .black.opacity(0.35), radius: 14, y: 8)
        .scenePointer(at: phase >= 4 ? "understood" : nil, clicks: phase >= 5 ? 1 : 0)
    }
}

struct FoldScene: View {
    @Environment(\.theme) private var theme
    let phase: Int
    var body: some View {
        HStack(spacing: 26) {
            SceneProofPage(foldedProof: phase >= 2)
                .frame(width: 360, height: 230)
                .scenePointer(at: phase >= 3 ? "fold" : nil)
            VStack(alignment: .leading, spacing: 10) {
                ScenePressedKeys(keys: "⌥⌘[", pressed: phase == 1)
                Text(phase >= 3 ? "Try it yourself, then click the panel to unfold." : phase >= 2 ? "Folded: prove it first." : "Fold every proof").font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(theme.tourText).frame(width: 170, alignment: .leading).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

struct HierarchyScene: View {
    @Environment(\.theme) private var theme
    let phase: Int
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                SceneKindBadge(letter: "T", size: 15)
                Text("Theorem 3.2").font(.system(size: 11.5, weight: .semibold))
                Text("Gauss-Markov · p. 51").font(.system(size: 10)).foregroundStyle(theme[.descriptionForeground])
                Spacer()
                HStack(spacing: 0) {
                    segment("Uses 3", on: phase < 4)
                    segment("Used By 5", on: phase >= 4)
                }
                .padding(2).background(Capsule().fill(theme.tourFill))
            }
            .foregroundStyle(theme[.foreground])
            .padding(.horizontal, 10).frame(height: 32)
            if phase < 4 {
                row(depth: 0, badge: "L", title: "Lemma 3.1", detail: "unbiased linear estimates", tag: "in proof", count: 2, page: "50", expandable: true, expanded: phase >= 2)
                if phase >= 2 {
                    row(depth: 1, badge: "D", title: "Definition 2.4", detail: "linear estimate", tag: nil, count: 1, page: "30", expandable: false, expanded: false)
                    row(depth: 1, badge: "E", title: "(2.9)", detail: "expectation of Xβ", tag: nil, count: 1, page: "31", expandable: false, expanded: false)
                }
                row(depth: 0, badge: "E", title: "(3.12)", detail: "variance decomposition", tag: "in proof", count: 1, page: "47", expandable: true, expanded: false)
                row(depth: 0, badge: "D", title: "Definition 3.1", detail: "ridge estimator", tag: nil, count: 1, page: "61", expandable: true, expanded: false)
            } else {
                row(depth: 0, badge: "C", title: "Corollary 3.5", detail: "bias of the ridge fit", tag: nil, count: 2, page: "52", expandable: true, expanded: false)
                row(depth: 0, badge: "P", title: "Proposition 7.1", detail: "optimism of the training error", tag: "in proof", count: 1, page: "229", expandable: true, expanded: false)
                row(depth: 0, badge: "T", title: "Theorem 8.3", detail: "bootstrap variance", tag: nil, count: 1, page: "264", expandable: true, expanded: false)
            }
            Spacer(minLength: 0)
        }
        .frame(width: 480, height: 210)
        .background(theme[.panelBackground])
        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        .shadow(color: .black.opacity(0.35), radius: 14, y: 8)
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: phase)
        .overlay(alignment: .bottomTrailing) { ScenePressedKeys(keys: "⇧⌥⌘H", pressed: phase == 1).offset(x: 20, y: 24) }
    }

    private func segment(_ title: String, on: Bool) -> some View {
        Text(title).font(.system(size: 9.5, weight: on ? .semibold : .regular)).foregroundStyle(on ? theme[.buttonForeground] : theme[.foreground])
            .padding(.horizontal, 8).frame(height: 18).background(Capsule().fill(on ? theme[.buttonBackground] : .clear))
    }

    private func row(depth: Int, badge: String, title: String, detail: String, tag: String?, count: Int, page: String, expandable: Bool, expanded: Bool) -> some View {
        HStack(spacing: 6) {
            Codicon(expandable ? (expanded ? "chevron-down" : "chevron-right") : "blank", size: 11).foregroundStyle(theme[.iconForeground]).frame(width: 12)
            SceneKindBadge(letter: badge, size: 13)
            Text(title).font(.system(size: 10.5, weight: .medium)).foregroundStyle(theme[.foreground])
            Text(detail).font(.system(size: 9.5)).foregroundStyle(theme[.descriptionForeground]).lineLimit(1)
            if let tag { Text(tag).font(.system(size: 8, weight: .semibold)).foregroundStyle(theme[.foreground]).padding(.horizontal, 5).frame(height: 13).background(Capsule().fill(theme.tourFill)) }
            Spacer()
            Text("×\(count)").font(.system(size: 9)).foregroundStyle(theme[.descriptionForeground])
            Text("p. \(page)").font(.system(size: 9)).monospacedDigit().foregroundStyle(theme[.descriptionForeground]).frame(width: 40, alignment: .trailing)
        }
        .padding(.leading, 10 + CGFloat(depth) * 16).padding(.trailing, 10).frame(height: 23)
        .transition(.move(edge: .top).combined(with: .opacity))
    }
}

// MARK: - Reading ruler, marks and problems

struct RulerScene: View {
    @Environment(\.theme) private var theme
    let phase: Int
    var body: some View {
        let line = 3 + min(phase, 4)
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Codicon("eye", size: 12).foregroundStyle(theme.accent)
                Text("Line \(line + 1) of 38 · p. 52").font(.system(size: 10.5, weight: .medium)).monospacedDigit()
                Text("Proof of Theorem 3.2").font(.system(size: 10.5)).foregroundStyle(theme[.descriptionForeground])
                Spacer()
                Text("Why?").font(.system(size: 10, weight: .medium)).foregroundStyle(theme[.textLinkForeground])
                Text("Uses").font(.system(size: 10, weight: .medium)).foregroundStyle(theme[.textLinkForeground])
            }
            .foregroundStyle(theme[.foreground])
            .padding(.horizontal, 10).frame(width: 400, height: 24)
            .background(RoundedRectangle(cornerRadius: 5).fill(theme.accent.opacity(0.14)))
            HStack(spacing: 20) {
                SceneProofPage(current: min(line, 7), veiled: true)
                    .frame(width: 380, height: 210)
                VStack(spacing: 6) {
                    ScenePressedKeys(keys: "↓", pressed: phase >= 1 && phase <= 3)
                    ScenePressedKeys(keys: "↑", pressed: false)
                    Text("J  K").font(.system(size: 11, weight: .semibold, design: .rounded)).foregroundStyle(theme.tourSecondary)
                }
            }
        }
    }
}

// MARK: - Run and Debug

/// The debugger's floating toolbar.
struct SceneDebugToolbar: View {
    @Environment(\.theme) private var theme
    var lit: String? = nil
    var body: some View {
        HStack(spacing: 6) {
            Codicon("gripper", size: 11).foregroundStyle(theme.tourTertiary)
            icon("debug-continue", .debugIconContinueForeground, "continue")
            icon("debug-step-back", .debugIconStepBackForeground, "back")
            icon("debug-step-over", .debugIconStepOverForeground, "over")
            icon("debug-step-into", .debugIconStepIntoForeground, "into")
            icon("debug-step-out", .debugIconStepOutForeground, "out")
            icon("debug-restart", .debugIconRestartForeground, "restart")
            icon("debug-stop", .debugIconStopForeground, "stop")
        }
        .padding(.horizontal, 7).frame(height: 24)
        .background(RoundedRectangle(cornerRadius: 5).fill(theme[.debugToolBarBackground]))
        .shadow(color: .black.opacity(0.35), radius: 6, y: 3)
    }

    private func icon(_ name: String, _ color: TC, _ id: String) -> some View {
        Codicon(name, size: 13).foregroundStyle(theme[color])
            .frame(width: 18, height: 18)
            .background(RoundedRectangle(cornerRadius: 3).fill(lit == id ? theme[.toolbarHoverBackground] : .clear))
            .scaleEffect(lit == id ? 1.15 : 1)
    }
}

struct DebugScene: View {
    @Environment(\.theme) private var theme
    let phase: Int
    let stepping: Bool

    var body: some View {
        let state = stepping ? steppingState : startState
        HStack(alignment: .top, spacing: 16) {
            ZStack(alignment: .top) {
                if state.inLemma {
                    ScenePaper(padding: 16) {
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(Array(["Lemma 3.1.  If cᵀy is unbiased for aᵀβ,", "then cᵀX = aᵀ.", "Proof.  E(cᵀy) = cᵀXβ = aᵀβ for all β.  □"].enumerated()), id: \.offset) { index, text in
                                Text(text).font(.system(size: 11, design: .serif)).fontWeight(index == 0 ? .semibold : .regular).foregroundStyle(.black)
                                    .frame(height: 21, alignment: .leading).frame(maxWidth: .infinity, alignment: .leading)
                                    .background(index == 2 ? Rectangle().fill(Color(red: 1, green: 0.85, blue: 0.2).opacity(0.42)).padding(.horizontal, -6) : nil)
                            }
                            ProseLines(widths: [250, 230, 200]).padding(.top, 8)
                        }
                    }
                    .frame(width: 360, height: 210)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                } else {
                    SceneProofPage(current: state.line, debugging: state.line != nil)
                        .frame(width: 360, height: 210)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
                if state.line != nil || state.inLemma {
                    SceneDebugToolbar(lit: state.lit).offset(y: -14).transition(.opacity)
                }
            }
            VStack(alignment: .leading, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("CALL STACK").font(.system(size: 8.5, weight: .bold)).foregroundStyle(theme[.descriptionForeground])
                    if state.inLemma {
                        stackRow("Proof of Lemma 3.1", "line 3", current: true)
                    }
                    if state.line != nil || state.inLemma {
                        stackRow("Proof of Theorem 3.2", "line \((state.line ?? 4) + 1)", current: !state.inLemma)
                    }
                }
                .padding(10)
                .frame(width: 190, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 8).fill(theme[.sideBarBackground]))
                if let keys = state.keys {
                    HStack(spacing: 8) { ScenePressedKeys(keys: keys, pressed: true); Text(state.caption).font(.system(size: 11.5, weight: .semibold)).foregroundStyle(theme.tourText) }
                        .transition(.opacity)
                        .id(keys)
                }
            }
            .padding(.top, 10)
        }
        .overlay(alignment: .bottom) {
            SceneStatusBar(mode: state.line != nil || state.inLemma ? "Debugging" : "Read", debugging: state.line != nil || state.inLemma,
                           items: [state.line != nil || state.inLemma ? "Proof of Theorem 3.2 · line \((state.line ?? 4) + 1)" : "3.2 Gauss-Markov"])
                .frame(width: 570).clipShape(RoundedRectangle(cornerRadius: 4)).offset(y: 34)
        }
    }

    private struct State { var line: Int?; var inLemma = false; var lit: String? = nil; var keys: String? = nil; var caption = "" }

    private var startState: State {
        switch phase {
        case 0: State(line: nil)
        case 1: State(line: nil, keys: "F5", caption: "Start debugging")
        default: State(line: 3, lit: phase >= 3 ? "over" : nil, keys: "F5", caption: "The proof is the program")
        }
    }

    private var steppingState: State {
        switch phase {
        case 0: State(line: 3)
        case 1: State(line: 4, lit: "over", keys: "F10", caption: "Step over")
        case 2: State(line: 5, lit: "over", keys: "F10", caption: "Step over")
        case 3: State(line: 4, inLemma: true, lit: "into", keys: "F11", caption: "Step into Lemma 3.1")
        default: State(line: 4, inLemma: false, lit: "out", keys: "⇧F11", caption: "Step out")
        }
    }

    private func stackRow(_ title: String, _ detail: String, current: Bool) -> some View {
        HStack(spacing: 5) {
            Codicon(current ? "debug-stackframe" : "debug-stackframe-dot", size: 11).foregroundStyle(current ? theme[.debugIconBreakpointCurrentStackframeForeground] : theme.tourTertiary)
            Text(title).font(.system(size: 10.5, weight: current ? .semibold : .regular)).foregroundStyle(theme[.foreground]).lineLimit(1)
            Spacer(minLength: 2)
            Text(detail).font(.system(size: 9)).foregroundStyle(theme[.descriptionForeground])
        }
        .transition(.move(edge: .top).combined(with: .opacity))
    }
}

// MARK: - Derivations

/// A derivation's editor: the gutter's verdicts, the LaTeX, and the steps typeset beside them.
struct DerivationScene: View {
    @Environment(\.theme) private var theme
    let demo: DerivationDemo
    let phase: Int

    static func delays(_ demo: DerivationDemo) -> [Double] {
        switch demo {
        case .start: [0.4, 0.8, 0.8]
        case .check: [0.5, 0.6, 0.6, 0.8, 0.6]
        case .answer: [0.4, 0.8, 0.8, 0.6]
        }
    }

    struct Step: Hashable { let latex: String; let pretty: String; let verdict: Verdict; var message: String? = nil }
    enum Verdict { case given, pass, fail }

    var body: some View {
        switch demo {
        case .start: start
        case .check: editor(steps: Self.checkSteps, visible: phase)
        case .answer: answer
        }
    }

    static let checkSteps: [Step] = [
        Step(latex: "RSS(\\beta) := \\|y - X\\beta\\|^2 + \\lambda\\|\\beta\\|^2", pretty: "RSS(β) := ‖y − Xβ‖² + λ‖β‖²", verdict: .given),
        Step(latex: "\\nabla = -2X^T(y - X\\beta) + 2\\lambda\\beta", pretty: "∇ = −2Xᵀ(y − Xβ) + 2λβ", verdict: .pass),
        Step(latex: "X^Ty = (X^TX + \\lambda I)\\beta", pretty: "Xᵀy = (XᵀX + λI)β", verdict: .pass),
        Step(latex: "\\beta = (X^TX - \\lambda I)^{-1}X^Ty", pretty: "β = (XᵀX − λI)^{−1}Xᵀy", verdict: .fail, message: "sign error · X 5×3, λ = 0.62 → left 2.31, right 1.87"),
        Step(latex: "\\beta = (X^TX + \\lambda I)^{-1}X^Ty", pretty: "β = (XᵀX + λI)^{−1}Xᵀy", verdict: .pass)
    ]

    private func editor(steps: [Step], visible: Int) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Codicon("symbol-operator", size: 12).foregroundStyle(theme.accent)
                Text("Ridge solution").font(.system(size: 11, weight: .semibold)).foregroundStyle(theme[.foreground])
                Text("p. 64").font(.system(size: 9.5)).foregroundStyle(theme[.descriptionForeground])
                Spacer()
                let shown = steps.prefix(visible)
                let pass = shown.filter { $0.verdict == .pass }.count, fail = shown.filter { $0.verdict == .fail }.count
                HStack(spacing: 5) {
                    Text("✓ \(pass)").foregroundStyle(theme[.testingIconPassed])
                    Text("✗ \(fail)").foregroundStyle(theme[.testingIconFailed])
                }
                .font(.system(size: 10, weight: .semibold)).padding(.horizontal, 7).frame(height: 17).background(Capsule().fill(theme.tourFill))
            }
            .padding(.horizontal, 10).frame(height: 28)
            .background(theme[.editorGroupHeaderTabsBackground])
            HStack(alignment: .top, spacing: 0) {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                        HStack(spacing: 6) {
                            Text("\(index + 1)").font(.system(size: 9, design: .monospaced)).foregroundStyle(theme[.editorLineNumberForeground]).frame(width: 12, alignment: .trailing)
                            verdictIcon(step.verdict).frame(width: 14)
                            Text(step.latex).font(.system(size: 10, design: .monospaced)).foregroundStyle(theme[.editorForeground]).lineLimit(1)
                                .overlay(alignment: .bottom) {
                                    if step.verdict == .fail {
                                        Rectangle().stroke(theme[.editorErrorForeground], style: StrokeStyle(lineWidth: 1.5, dash: [1.5, 1.5])).frame(height: 1).offset(y: 2)
                                    }
                                }
                        }
                        .frame(height: 30, alignment: .leading)
                        .opacity(index < visible ? 1 : 0)
                    }
                }
                .padding(.horizontal, 8).padding(.top, 6)
                .frame(width: 300, alignment: .topLeading)
                Rectangle().fill(theme.tourHairline).frame(width: 1)
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                        VStack(alignment: .leading, spacing: 1) {
                            SceneMath(source: step.pretty, size: 11.5).foregroundStyle(theme[.editorForeground])
                            if let message = step.message {
                                Text(message).font(.system(size: 8.5, design: .monospaced))
                                    .foregroundStyle(step.verdict == .fail ? theme[.editorErrorForeground] : theme[.descriptionForeground]).lineLimit(1)
                            }
                        }
                        .padding(.horizontal, 6)
                        .frame(height: 30, alignment: .leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(step.verdict == .fail ? theme[.editorErrorForeground].opacity(0.1) : .clear)
                        .opacity(index < visible ? 1 : 0)
                    }
                }
                .padding(.top, 6)
            }
            Spacer(minLength: 0)
            Text("Tested on random values: evidence, not a proof.").font(.system(size: 9)).foregroundStyle(theme[.descriptionForeground])
                .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 10).padding(.bottom, 6)
        }
        .frame(width: 580, height: 230)
        .background(theme[.editorBackground])
        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(theme.tourHairline, lineWidth: 1))
        .shadow(color: .black.opacity(0.35), radius: 14, y: 8)
    }

    @ViewBuilder private func verdictIcon(_ verdict: Verdict) -> some View {
        switch verdict {
        case .given: Circle().fill(theme.accent).frame(width: 6, height: 6)
        case .pass: Codicon("check", size: 12).foregroundStyle(theme[.testingIconPassed])
        case .fail: Codicon("close", size: 12).foregroundStyle(theme[.testingIconFailed])
        }
    }

    private var start: some View {
        HStack(alignment: .top, spacing: 14) {
            ScenePaper(padding: 14) {
                VStack(alignment: .leading, spacing: 6) {
                    ProseLines(widths: [200, 180])
                    HStack(spacing: 0) {
                        PaperText(text: "the solutions are ", size: 10.5)
                        Text("easily seen to be (3.44)").font(.system(size: 10.5, design: .serif)).foregroundStyle(.black)
                            .background(Rectangle().fill(Color.accentColor.opacity(phase >= 1 ? 0.28 : 0)))
                    }
                    ProseLines(widths: [210, 160, 190])
                }
            }
            .frame(width: 230, height: 170)
            .overlay(alignment: .top) {
                if phase >= 1 {
                    HStack(spacing: 8) {
                        ForEach(["Ask", "Note", "Lab", "Derive"], id: \.self) { item in
                            Text(item).font(.system(size: 9.5, weight: item == "Derive" ? .bold : .regular))
                                .foregroundStyle(item == "Derive" ? theme.accent : theme[.foreground])
                                .modifier(SpotIf(id: item == "Derive" ? "derive" : nil))
                        }
                    }
                    .padding(.horizontal, 8).frame(height: 22)
                    .background(RoundedRectangle(cornerRadius: 5).fill(theme[.editorWidgetBackground]).shadow(radius: 4))
                    .offset(y: -26)
                }
            }
            if phase >= 2 {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 5) { Codicon("symbol-operator", size: 12).foregroundStyle(theme.accent); Text("Derivation · (3.44)").font(.system(size: 11, weight: .semibold)) }
                    Text("“easily seen to be (3.44)” · p. 64").font(.system(size: 9.5, design: .serif)).italic().foregroundStyle(theme[.descriptionForeground])
                        .padding(6).frame(maxWidth: .infinity, alignment: .leading).background(RoundedRectangle(cornerRadius: 4).fill(theme.tourFill))
                    HStack(spacing: 6) {
                        Text("1").font(.system(size: 9, design: .monospaced)).foregroundStyle(theme[.editorLineNumberForeground])
                        Text(phase >= 3 ? "X^Ty = (X^TX + \\lambda I)\\beta" : "").font(.system(size: 10, design: .monospaced))
                        Rectangle().fill(theme[.editorCursorForeground]).frame(width: 1, height: 12)
                    }
                    Spacer()
                }
                .foregroundStyle(theme[.foreground])
                .padding(10)
                .frame(width: 290, height: 190, alignment: .topLeading)
                .background(RoundedRectangle(cornerRadius: 9).fill(theme[.editorBackground]).shadow(color: .black.opacity(0.35), radius: 12, y: 6))
                .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .scenePointer(at: phase >= 1 && phase < 3 ? "derive" : nil, clicks: phase >= 2 ? 1 : 0)
    }

    private var answer: some View {
        HStack(alignment: .top, spacing: 16) {
            SceneCard(padding: 12, radius: 10) {
                VStack(alignment: .leading, spacing: 7) {
                    HStack(spacing: 5) { Codicon("comment-discussion", size: 12).foregroundStyle(theme.accent); Text("Answer · ChatGPT").font(.system(size: 11, weight: .semibold)) }
                    Text("Setting the gradient to zero,").font(.system(size: 10.5))
                    Text("Xᵀy = (XᵀX + λI)β,").font(.system(size: 12, design: .serif)).italic()
                    SceneMath(source: "so β̂ = (XᵀX + λI)^{−1}Xᵀy and", size: 12)
                    Text("tr H = Σ dⱼ²/(dⱼ² − λ).").font(.system(size: 12, design: .serif)).italic()
                    HStack(spacing: 4) { Codicon("checklist", size: 11); Text("Check 3 steps") }
                        .font(.system(size: 10, weight: .semibold)).foregroundStyle(theme[.buttonForeground])
                        .padding(.horizontal, 8).frame(height: 20).background(RoundedRectangle(cornerRadius: 4).fill(theme[.buttonBackground]))
                        .sceneSpot("check")
                }
                .foregroundStyle(theme[.editorHoverWidgetForeground])
                .frame(width: 220, alignment: .leading)
            }
            if phase >= 2 {
                VStack(alignment: .leading, spacing: 8) {
                    resultRow("Xᵀy = (XᵀX + λI)β", pass: true, visible: phase >= 2)
                    resultRow("β̂ = (XᵀX + λI)^{−1}Xᵀy", pass: true, visible: phase >= 3)
                    resultRow("tr H = Σ dⱼ²/(dⱼ² − λ)", pass: false, visible: phase >= 3)
                    if phase >= 4 {
                        Text("off by a sign: dⱼ² + λ, not dⱼ² − λ").font(.system(size: 9.5, design: .monospaced)).foregroundStyle(theme[.editorErrorForeground])
                    }
                }
                .padding(12)
                .frame(width: 260, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 9).fill(theme[.editorBackground]).shadow(color: .black.opacity(0.35), radius: 12, y: 6))
                .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .scenePointer(at: phase == 1 ? "check" : nil, clicks: phase >= 2 ? 1 : 0)
    }

    private func resultRow(_ text: String, pass: Bool, visible: Bool) -> some View {
        HStack(spacing: 7) {
            Codicon(pass ? "check" : "close", size: 12).foregroundStyle(pass ? theme[.testingIconPassed] : theme[.testingIconFailed])
            SceneMath(source: text, size: 12).foregroundStyle(theme[.editorForeground])
        }
        .opacity(visible ? 1 : 0)
    }
}

