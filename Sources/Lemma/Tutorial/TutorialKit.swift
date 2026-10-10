import SwiftUI
import AppKit
import LemmaCore

// The tour's visual vocabulary: solid surfaces in the theme's widget colours, a callout with a beak that points at the
// part of the window it explains, VS Code's buttons, key caps, and a pointer that demonstrates. Colours come from the
// theme in force, so the tour looks at home in every colour theme and in the Classic interface. Motion is played
// once, never repeated forever.

extension WorkbenchColors {
    /// Text on the tour's surfaces: the theme's foreground at three strengths.
    var tourText: Color { self[.foreground] }
    var tourSecondary: Color { self[.foreground].opacity(isDark ? 0.80 : 0.78) }
    var tourTertiary: Color { self[.foreground].opacity(isDark ? 0.64 : 0.62) }
    var tourHairline: Color { self[.foreground].opacity(isDark ? 0.12 : 0.11) }
    var tourFill: Color { self[.foreground].opacity(isDark ? 0.06 : 0.045) }
    /// Some imported themes use a near-black focus border; the tour still needs visible progress and outlines.
    var tourAccent: Color { rgba(.buttonBackground).readable(on: rgba(.editorWidgetBackground), ratio: 3).color }
    /// The tour's surfaces: the theme's widget colour, its border when it has one, and its widget shadow.
    var tourSurface: Color { self[.editorWidgetBackground] }
    var tourBorder: Color { has(.editorWidgetBorder) ? self[.editorWidgetBorder] : tourHairline }
    var tourShadow: Color { has(.widgetShadow) ? self[.widgetShadow] : .black.opacity(isDark ? 0.45 : 0.18) }
}

/// How the tour's pages replace one another: the old one fades quickly, the new one rises in just after.
enum TutorialTransition {
    static var page: AnyTransition {
        .asymmetric(insertion: .opacity.combined(with: .scale(scale: 0.985)).animation(.easeOut(duration: 0.24).delay(0.06)),
                    removal: .opacity.animation(.easeIn(duration: 0.1)))
    }
}

// MARK: - Surfaces

extension View {
    /// A page of the tour (the welcome, the colours, the guides, the last page): the theme's widget surface, its
    /// border and a soft shadow, as VS Code draws its dialogs.
    func tutorialSurface(_ theme: WorkbenchColors, radius: CGFloat = 12, shadow: Bool = true) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        return self
            .background(shape.fill(theme.tourSurface))
            .clipShape(shape)
            .overlay(shape.strokeBorder(theme.tourBorder, lineWidth: 1))
            .shadow(color: shadow ? theme.tourShadow : .clear, radius: shadow ? 28 : 0, y: shadow ? 14 : 0)
    }
}

/// The step's callout: a rounded card with a beak on the edge that faces the part of the window it explains.
struct CoachBubble: Shape {
    /// The card's edge that carries the beak; none when the card sits inside the part or alone in the window.
    var edge: Edge?
    /// Where the beak's tip sits along that edge, from its top or leading end.
    var offset: CGFloat
    var radius: CGFloat = 10
    static let beakLength: CGFloat = 8
    static let beakWidth: CGFloat = 18

    var animatableData: CGFloat {
        get { offset }
        set { offset = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let r = min(radius, rect.width / 2, rect.height / 2)
        let half = Self.beakWidth / 2
        let length = Self.beakLength
        func along(_ extent: CGFloat) -> CGFloat { min(max(offset, r + half + 2), extent - r - half - 2) }
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + r, y: rect.minY))
        if edge == .top {
            let x = rect.minX + along(rect.width)
            path.addLine(to: CGPoint(x: x - half, y: rect.minY))
            path.addLine(to: CGPoint(x: x, y: rect.minY - length))
            path.addLine(to: CGPoint(x: x + half, y: rect.minY))
        }
        path.addLine(to: CGPoint(x: rect.maxX - r, y: rect.minY))
        path.addArc(center: CGPoint(x: rect.maxX - r, y: rect.minY + r), radius: r, startAngle: .degrees(-90), endAngle: .degrees(0), clockwise: false)
        if edge == .trailing {
            let y = rect.minY + along(rect.height)
            path.addLine(to: CGPoint(x: rect.maxX, y: y - half))
            path.addLine(to: CGPoint(x: rect.maxX + length, y: y))
            path.addLine(to: CGPoint(x: rect.maxX, y: y + half))
        }
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - r))
        path.addArc(center: CGPoint(x: rect.maxX - r, y: rect.maxY - r), radius: r, startAngle: .degrees(0), endAngle: .degrees(90), clockwise: false)
        if edge == .bottom {
            let x = rect.minX + along(rect.width)
            path.addLine(to: CGPoint(x: x + half, y: rect.maxY))
            path.addLine(to: CGPoint(x: x, y: rect.maxY + length))
            path.addLine(to: CGPoint(x: x - half, y: rect.maxY))
        }
        path.addLine(to: CGPoint(x: rect.minX + r, y: rect.maxY))
        path.addArc(center: CGPoint(x: rect.minX + r, y: rect.maxY - r), radius: r, startAngle: .degrees(90), endAngle: .degrees(180), clockwise: false)
        if edge == .leading {
            let y = rect.minY + along(rect.height)
            path.addLine(to: CGPoint(x: rect.minX, y: y + half))
            path.addLine(to: CGPoint(x: rect.minX - length, y: y))
            path.addLine(to: CGPoint(x: rect.minX, y: y - half))
        }
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + r))
        path.addArc(center: CGPoint(x: rect.minX + r, y: rect.minY + r), radius: r, startAngle: .degrees(180), endAngle: .degrees(270), clockwise: false)
        path.closeSubpath()
        return path
    }
}

/// Lemma's icon, drawn: the white serif λ on olive, as the app icon.
struct TutorialAppIcon: View {
    var size: CGFloat = 96
    var body: some View {
        let shape = RoundedRectangle(cornerRadius: size * 0.225, style: .continuous)
        ZStack {
            shape.fill(LinearGradient(colors: [Color(red: 0.42, green: 0.43, blue: 0.13), Color(red: 0.29, green: 0.30, blue: 0.07)],
                                      startPoint: .top, endPoint: .bottom))
            Text("λ").font(.system(size: size * 0.66, weight: .medium, design: .serif)).foregroundStyle(.white)
                .offset(y: -size * 0.02)
            shape.strokeBorder(.white.opacity(0.18), lineWidth: max(0.5, size * 0.01))
        }
        .frame(width: size, height: size)
        .shadow(color: .black.opacity(0.22), radius: size * 0.08, y: size * 0.04)
        .accessibilityHidden(true)
    }
}

// MARK: - Controls

/// The tour's buttons, drawn as the workbench's: VS Code's flat buttons in its button colours (rounder in the Classic
/// interface), a link-like quiet button, and a larger size for the pages.
struct TutorialButtonStyle: ButtonStyle {
    enum Kind { case primary, secondary, quiet }
    var kind: Kind = .primary
    var large = false
    @Environment(\.theme) private var theme
    @Environment(\.isEnabled) private var enabled

    func makeBody(configuration: Configuration) -> some View {
        StyledBody(configuration: configuration, kind: kind, large: large, theme: theme, enabled: enabled)
    }

    private struct StyledBody: View {
        let configuration: Configuration
        let kind: Kind
        let large: Bool
        let theme: WorkbenchColors
        let enabled: Bool
        @State private var hovering = false
        @State private var themes = ThemeManager.shared

        var body: some View {
            let shape = RoundedRectangle(cornerRadius: themes.style == .classic ? 6 : 4, style: .continuous)
            configuration.label
                .font(.system(size: large ? 13 : 12.5, weight: kind == .primary ? .semibold : .medium))
                .lineLimit(1)
                .foregroundStyle(foreground)
                .padding(.horizontal, kind == .quiet ? 8 : (large ? 16 : 12))
                .frame(minHeight: large ? 30 : 26)
                .background {
                    switch kind {
                    case .primary: shape.fill(theme[hovering ? .buttonHoverBackground : .buttonBackground])
                    case .secondary: shape.fill(theme[hovering ? .buttonSecondaryHoverBackground : .buttonSecondaryBackground])
                    case .quiet: shape.fill(theme.tourText.opacity(hovering ? 0.07 : 0))
                    }
                }
                .overlay { if kind != .quiet { shape.strokeBorder(theme.border(.buttonBorder), lineWidth: 1) } }
                .contentShape(shape)
                .opacity(enabled ? (configuration.isPressed ? 0.85 : 1) : 0.45)
                .onHover { hovering = $0 && enabled }
        }

        private var foreground: Color {
            switch kind {
            case .primary: theme[.buttonForeground]
            case .secondary: theme[.buttonSecondaryForeground]
            case .quiet: hovering ? theme.tourText : theme.tourSecondary
            }
        }
    }
}

/// The close button of the tour's cards.
struct TutorialCloseButton: View {
    @Environment(\.theme) private var theme
    var help = "Close (⎋)"
    let action: () -> Void
    @State private var hovering = false
    var body: some View {
        Button(action: action) {
            Codicon("close", size: 14).foregroundStyle(hovering ? theme.tourText : theme.tourTertiary)
                .frame(width: 22, height: 22)
                .background(RoundedRectangle(cornerRadius: 4, style: .continuous).fill(theme.tourText.opacity(hovering ? 0.08 : 0)))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(help)
        .accessibilityLabel("Close")
    }
}

/// A shortcut as key caps: “⇧⌘P” is three caps; groups separated by spaces (“⌥⌘← ⌥⌘→”) are spaced apart; “⌥-click”
/// is a cap and the word.
struct TutorialKeys: View {
    @Environment(\.theme) private var theme
    let shortcut: String
    var size: CGFloat = 12

    var body: some View {
        HStack(spacing: size * 0.6) {
            ForEach(Array(Self.groups(shortcut).enumerated()), id: \.offset) { _, group in
                HStack(spacing: 3) {
                    ForEach(Array(group.enumerated()), id: \.offset) { _, key in
                        if key == "click" {
                            Text("click").font(.system(size: size, weight: .medium)).foregroundStyle(theme.tourSecondary)
                        } else {
                            cap(key)
                        }
                    }
                }
            }
        }
        .fixedSize()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(shortcut)
    }

    private func cap(_ key: String) -> some View {
        let shape = RoundedRectangle(cornerRadius: 4, style: .continuous)
        return Text(key)
            .font(.system(size: key.count > 1 ? size * 0.92 : size, weight: .medium, design: .rounded))
            .foregroundStyle(theme.tourText.opacity(0.9))
            .padding(.horizontal, key.count > 1 ? size * 0.45 : 0)
            .frame(minWidth: size * 1.75, minHeight: size * 1.75)
            .background(shape.fill(theme.tourText.opacity(0.08)))
            .overlay(shape.strokeBorder(theme.tourText.opacity(0.16), lineWidth: 0.75))
    }

    static func groups(_ shortcut: String) -> [[String]] {
        shortcut.split(separator: " ").map { part in
            var group = String(part)
            var keys: [String] = []
            let click = group.hasSuffix("-click")
            if click { group.removeLast("-click".count) }
            var current = ""
            for character in group {
                if "⌘⇧⌥⌃".contains(character) {
                    if !current.isEmpty { keys.append(current); current = "" }
                    keys.append(String(character))
                } else { current.append(character) }
            }
            if !current.isEmpty { keys.append(current) }
            if click { keys.append("click") }
            return keys
        }
    }
}

/// The tour's prose: `code` spans (what to type, LaTeX, file types) are set in the monospaced face.
enum TutorialProse {
    static func text(_ text: String, size: CGFloat) -> Text {
        var result = Text("")
        for (index, part) in text.split(separator: "`", omittingEmptySubsequences: false).enumerated() {
            result = result + Text(String(part)).font(index % 2 == 1 ? .system(size: size * 0.92, design: .monospaced) : .system(size: size))
        }
        return result
    }
}

// MARK: - Demonstrations

/// Plays a scene once: phase 0, then each later phase after its delay, and rests on the last (motion never repeats on
/// its own). A new `replay` value plays it again; Reduce Motion shows the last phase at once.
struct ScenePlayer<Content: View>: View {
    let delays: [Double]
    let replay: Int
    @ViewBuilder let content: (Int) -> Content
    @State private var phase = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        content(phase)
            .task(id: replay) {
                if reduceMotion { phase = delays.count; return }
                if phase != 0 {
                    withAnimation(.easeOut(duration: 0.18)) { phase = 0 }
                    try? await Task.sleep(for: .milliseconds(220))
                }
                for (index, delay) in delays.enumerated() {
                    try? await Task.sleep(for: .seconds(delay))
                    if Task.isCancelled { return }
                    withAnimation(.spring(response: 0.55, dampingFraction: 0.84)) { phase = index + 1 }
                }
            }
    }
}

/// The macOS arrow pointer, for demonstrations. Each new value of `clicks` shows a ripple under its tip.
struct DemoPointer: View {
    var clicks = 0

    private struct Ripple { var scale = 1.0; var opacity = 0.0 }

    var body: some View {
        ZStack(alignment: .topLeading) {
            ArrowShape().fill(.black).offset(x: 0.6, y: 1.2).blur(radius: 1.2).opacity(0.35)
            ArrowShape().fill(.white)
            ArrowShape().stroke(.black, lineWidth: 1.1)
        }
        .frame(width: 14, height: 22, alignment: .topLeading)
        .background(alignment: .topLeading) {
            Circle().stroke(Color.white, lineWidth: 2.5).background(Circle().fill(Color.white.opacity(0.25)))
                .frame(width: 34, height: 34)
                .keyframeAnimator(initialValue: Ripple(), trigger: clicks) { view, value in
                    view.scaleEffect(value.scale).opacity(value.opacity)
                } keyframes: { _ in
                    KeyframeTrack(\.scale) { LinearKeyframe(0.15, duration: 0.01); CubicKeyframe(1.0, duration: 0.5) }
                    KeyframeTrack(\.opacity) { LinearKeyframe(0.95, duration: 0.01); CubicKeyframe(0, duration: 0.5) }
                }
                .offset(x: -17, y: -17)
        }
        .accessibilityHidden(true)
    }

    private struct ArrowShape: Shape {
        func path(in rect: CGRect) -> Path {
            Path { path in
                path.move(to: CGPoint(x: 0, y: 0))
                path.addLine(to: CGPoint(x: 0, y: 17))
                path.addLine(to: CGPoint(x: 4.2, y: 13.2))
                path.addLine(to: CGPoint(x: 7.1, y: 20))
                path.addLine(to: CGPoint(x: 9.6, y: 18.9))
                path.addLine(to: CGPoint(x: 6.8, y: 12.3))
                path.addLine(to: CGPoint(x: 12.3, y: 12.3))
                path.closeSubpath()
            }
        }
    }
}
