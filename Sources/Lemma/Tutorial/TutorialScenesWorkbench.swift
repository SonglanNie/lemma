import SwiftUI
import AppKit
import LemmaCore

// Scenes about the window itself: its parts, layouts, themes, the library and what leaves the Mac.

// MARK: - The window in miniature

/// Lemma's window in miniature, in either interface and any theme, with one part lit.
struct MiniWorkbench: View {
    let style: WorkbenchStyle
    let colors: WorkbenchColors
    var lit: MiniRegion? = nil
    var phase = 1
    var showsPanel = true
    var showsSecondary = true
    var sideOnRight = false
    var hidden: Set<MiniRegion> = []

    var body: some View {
        GeometryReader { geometry in
            let frames = Self.frames(in: geometry.size, style: style, panel: showsPanel, secondary: showsSecondary, sideOnRight: sideOnRight, hidden: hidden)
            ZStack(alignment: .topLeading) {
                colors[.editorBackground]
                ForEach(Self.order, id: \.self) { region in
                    if let frame = frames[region], frame.width > 0, frame.height > 0 {
                        part(region, size: frame.size)
                            .frame(width: frame.width, height: frame.height)
                            .clipped()
                            .offset(x: frame.minX, y: frame.minY)
                    }
                }
                if let lit, let frame = frames[lit] {
                    MiniSpotlight(frame: frame, size: geometry.size, label: Self.label(lit, style: style), on: phase >= 1)
                }
            }
        }
        .environment(\.theme, colors)
    }

    static let order: [MiniRegion] = [.titleBar, .activityBar, .sideBar, .editor, .page, .secondarySideBar, .panel, .statusBar]

    static func label(_ region: MiniRegion, style: WorkbenchStyle) -> String {
        switch region {
        case .titleBar: style == .vscode ? "Title bar · command center" : "Toolbar · command center"
        case .activityBar: "Activity bar"
        case .sideBar: style == .vscode ? "Side bar · Explorer" : "Sidebar"
        case .editor: "Tabs · breadcrumbs"
        case .page: style == .vscode ? "Page · minimap · overview" : "Page · overview"
        case .secondarySideBar: style == .vscode ? "Secondary side bar" : "Notebook"
        case .panel: "Panel"
        case .statusBar: "Status bar"
        }
    }

    static func frames(in size: CGSize, style: WorkbenchStyle, panel: Bool, secondary: Bool, sideOnRight: Bool, hidden: Set<MiniRegion>) -> [MiniRegion: CGRect] {
        let w = size.width, h = size.height
        let title = style == .vscode ? max(10, h * 0.075) : max(14, h * 0.12)
        let status = max(7, h * 0.05)
        let activity = hidden.contains(.activityBar) ? 0 : max(10, w * 0.052)
        let side = hidden.contains(.sideBar) ? 0 : w * 0.2
        let second = secondary && !hidden.contains(.secondarySideBar) ? w * 0.19 : 0
        let bodyTop = title, bodyHeight = h - title - status
        let editorX = sideOnRight ? second : activity + side
        let editorWidth = w - activity - side - second
        let header = hidden.contains(.editor) ? 0 : max(9, h * 0.1)
        let panelHeight = panel && !hidden.contains(.panel) ? bodyHeight * 0.27 : 0
        var frames: [MiniRegion: CGRect] = [:]
        frames[.titleBar] = CGRect(x: 0, y: 0, width: w, height: title)
        frames[.statusBar] = CGRect(x: 0, y: h - status, width: w, height: status)
        if sideOnRight {
            frames[.secondarySideBar] = CGRect(x: 0, y: bodyTop, width: second, height: bodyHeight)
            frames[.sideBar] = CGRect(x: w - activity - side, y: bodyTop, width: side, height: bodyHeight)
            frames[.activityBar] = CGRect(x: w - activity, y: bodyTop, width: activity, height: bodyHeight)
        } else {
            frames[.activityBar] = CGRect(x: 0, y: bodyTop, width: activity, height: bodyHeight)
            frames[.sideBar] = CGRect(x: activity, y: bodyTop, width: side, height: bodyHeight)
            frames[.secondarySideBar] = CGRect(x: w - second, y: bodyTop, width: second, height: bodyHeight)
        }
        frames[.editor] = CGRect(x: editorX, y: bodyTop, width: editorWidth, height: header)
        frames[.page] = CGRect(x: editorX, y: bodyTop + header, width: editorWidth, height: bodyHeight - header - panelHeight)
        frames[.panel] = CGRect(x: editorX, y: bodyTop + bodyHeight - panelHeight, width: editorWidth, height: panelHeight)
        return frames
    }

    @ViewBuilder private func part(_ region: MiniRegion, size: CGSize) -> some View {
        switch region {
        case .titleBar: titleBar(size)
        case .activityBar: activityBar(size)
        case .sideBar: sideBar(size)
        case .editor: editorHeader(size)
        case .page: page(size)
        case .secondarySideBar: secondaryBar(size)
        case .panel: panelPart(size)
        case .statusBar: statusBar(size)
        }
    }

    private var line: Color { colors[.foreground].opacity(colors.isDark ? 0.22 : 0.2) }
    private var border: Color { colors.isDark ? Color.white.opacity(0.07) : Color.black.opacity(0.08) }

    private func titleBar(_ size: CGSize) -> some View {
        let h = size.height
        return ZStack {
            colors[.titleBarActiveBackground]
            HStack(spacing: h * 0.22) {
                ForEach([Color(red: 1, green: 0.37, blue: 0.34), Color(red: 1, green: 0.74, blue: 0.18), Color(red: 0.16, green: 0.79, blue: 0.25)], id: \.self) { color in
                    Circle().fill(color).frame(width: h * 0.36, height: h * 0.36)
                }
                if style == .vscode {
                    Text("λ").font(.system(size: h * 0.55, weight: .semibold, design: .serif)).foregroundStyle(colors[.titleBarActiveForeground]).padding(.leading, h * 0.2)
                } else {
                    Image(systemName: "sidebar.left").font(.system(size: h * 0.36)).foregroundStyle(colors[.titleBarActiveForeground].opacity(0.7)).padding(.leading, h * 0.3)
                }
                Spacer()
                if style == .classic {
                    ForEach(["viewfinder", "pencil.tip", "text.bubble"], id: \.self) { symbol in
                        Image(systemName: symbol).font(.system(size: h * 0.32)).foregroundStyle(colors[.titleBarActiveForeground].opacity(0.65))
                    }
                } else {
                    ForEach(0..<3) { _ in RoundedRectangle(cornerRadius: 1).stroke(colors[.titleBarActiveForeground].opacity(0.6), lineWidth: 0.8).frame(width: h * 0.4, height: h * 0.32) }
                }
            }
            .padding(.horizontal, h * 0.35)
            HStack(spacing: h * 0.2) {
                Image(systemName: "magnifyingglass").font(.system(size: h * 0.3))
                Text("Elements of Statistical Learning").font(.system(size: max(5, h * 0.3))).lineLimit(1)
            }
            .foregroundStyle(colors[.commandCenterForeground].opacity(0.85))
            .padding(.horizontal, h * 0.4)
            .frame(width: size.width * 0.32, height: h * (style == .vscode ? 0.62 : 0.5))
            .background(RoundedRectangle(cornerRadius: h * 0.18).fill(colors[.commandCenterBackground]))
            .overlay(RoundedRectangle(cornerRadius: h * 0.18).stroke(colors.border(.commandCenterBorder), lineWidth: 0.6))
        }
        .overlay(alignment: .bottom) { Rectangle().fill(border).frame(height: 0.6) }
    }

    private func activityBar(_ size: CGSize) -> some View {
        let w = size.width
        let icons = style == .vscode ? ["files", "search", "symbol-structure", "debug-alt", "beaker", "notebook", "folder-library", "extensions"]
                                     : ["books.vertical", "list.bullet.indent", "checkmark.seal", "function", "flask", "magnifyingglass", "bookmark"]
        return VStack(spacing: w * 0.32) {
            ForEach(Array(icons.enumerated()), id: \.offset) { index, icon in
                Group {
                    if style == .vscode { Codicon(icon, size: w * 0.5) } else { Image(systemName: icon).font(.system(size: w * 0.4)) }
                }
                .foregroundStyle(index == 0 ? colors[.activityBarForeground] : colors[.activityBarInactiveForeground])
                .frame(width: w, height: w * 0.62)
                .overlay(alignment: .leading) {
                    if index == 0 && style == .vscode { Rectangle().fill(colors[.activityBarActiveBorder]).frame(width: max(1, w * 0.05)) }
                }
                .background(index == 0 && style == .classic ? RoundedRectangle(cornerRadius: 3).fill(colors.accent.opacity(0.22)).padding(.horizontal, w * 0.12) : nil)
            }
            Spacer(minLength: 0)
        }
        .padding(.top, w * 0.3)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(colors[.activityBarBackground])
        .overlay(alignment: .trailing) { Rectangle().fill(border).frame(width: 0.6) }
    }

    private func sideBar(_ size: CGSize) -> some View {
        let unit = size.height / 24
        let widths: [CGFloat] = [0.7, 0.55, 0.62, 0.48, 0.66, 0.4, 0.58, 0.5, 0.64, 0.45, 0.6, 0.52]
        return VStack(alignment: .leading, spacing: unit * 0.75) {
            Text(style == .vscode ? "EXPLORER" : "Outline").font(.system(size: max(4.5, unit * 0.8), weight: .semibold))
                .foregroundStyle(colors[.sideBarTitleForeground]).padding(.bottom, unit * 0.2)
            ForEach(Array(widths.enumerated()), id: \.offset) { index, width in
                HStack(spacing: unit * 0.5) {
                    RoundedRectangle(cornerRadius: 1).fill(index % 4 == 0 ? colors.accent.opacity(0.75) : line).frame(width: unit * 0.9, height: unit * 0.9)
                    Capsule().fill(line).frame(width: size.width * width * 0.75, height: max(1.5, unit * 0.42))
                }
                .padding(.leading, CGFloat(index % 3) * unit * 0.8)
                .padding(.vertical, unit * 0.15)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(index == 3 ? (style == .classic ? RoundedRectangle(cornerRadius: 3).fill(colors.accent.opacity(0.28)) : RoundedRectangle(cornerRadius: 0).fill(colors[.listActiveSelectionBackground])) : nil)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, unit * 0.9).padding(.top, unit * 0.9)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(colors[.sideBarBackground])
        .overlay(alignment: .trailing) { Rectangle().fill(border).frame(width: 0.6) }
    }

    private func editorHeader(_ size: CGSize) -> some View {
        let h = size.height
        return VStack(spacing: 0) {
            HStack(spacing: 0) {
                tab(title: "ESL", active: true, height: h * 0.62)
                tab(title: "Bishop", active: false, height: h * 0.62)
                tab(title: "Welcome", active: false, height: h * 0.62)
                Spacer(minLength: 0)
            }
            .frame(height: h * 0.62)
            .background(colors[.editorGroupHeaderTabsBackground])
            HStack(spacing: h * 0.12) {
                ForEach(["ESL", "3 Linear Methods", "3.4 Shrinkage", "3.4.1 Ridge"], id: \.self) { crumb in
                    Text(crumb).font(.system(size: max(4, h * 0.22))).foregroundStyle(colors[.breadcrumbForeground]).lineLimit(1)
                    if crumb != "3.4.1 Ridge" { Text("›").font(.system(size: max(4, h * 0.22))).foregroundStyle(colors[.breadcrumbForeground].opacity(0.6)) }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, h * 0.2)
            .frame(height: h * 0.38)
            .background(colors[.breadcrumbBackground])
        }
    }

    private func tab(title: String, active: Bool, height: CGFloat) -> some View {
        HStack(spacing: height * 0.15) {
            RoundedRectangle(cornerRadius: 1).fill(Color(red: 0.9, green: 0.3, blue: 0.3).opacity(0.85)).frame(width: height * 0.3, height: height * 0.36)
            Text(title).font(.system(size: max(4.5, height * 0.34))).lineLimit(1)
        }
        .foregroundStyle(active ? colors[.tabActiveForeground] : colors[.tabInactiveForeground])
        .padding(.horizontal, height * 0.45)
        .frame(height: height)
        .background(active ? colors[.tabActiveBackground] : colors[.tabInactiveBackground])
        .overlay(alignment: .top) { if active && style == .vscode { Rectangle().fill(colors[.tabActiveBorderTop]).frame(height: max(1, height * 0.06)) } }
        .overlay(alignment: .trailing) { Rectangle().fill(border).frame(width: 0.5) }
    }

    private func page(_ size: CGSize) -> some View {
        let canvas = colors.pageCanvas.color
        let minimap = style == .vscode ? size.width * 0.1 : 0
        let ruler = max(3, size.width * 0.02)
        let paperWidth = min(size.width - minimap - ruler - 16, size.height * 0.95)
        return HStack(spacing: 0) {
            ZStack {
                canvas
                RoundedRectangle(cornerRadius: 1).fill(Color.white)
                    .frame(width: paperWidth, height: size.height * 1.1)
                    .overlay(alignment: .topLeading) {
                        VStack(alignment: .leading, spacing: size.height * 0.035) {
                            Capsule().fill(Color.black.opacity(0.55)).frame(width: paperWidth * 0.45, height: max(1.5, size.height * 0.025))
                            ForEach(0..<4) { index in Capsule().fill(Color.black.opacity(0.16)).frame(width: paperWidth * [0.82, 0.76, 0.84, 0.6][index], height: max(1, size.height * 0.016)) }
                            Capsule().fill(Color.black.opacity(0.4)).frame(width: paperWidth * 0.5, height: max(1.2, size.height * 0.02)).frame(maxWidth: .infinity)
                            ForEach(0..<6) { index in Capsule().fill(Color.black.opacity(0.16)).frame(width: paperWidth * [0.8, 0.84, 0.7, 0.82, 0.76, 0.5][index], height: max(1, size.height * 0.016)) }
                        }
                        .padding(paperWidth * 0.09)
                    }
                    .offset(y: size.height * 0.08)
                    .shadow(color: .black.opacity(0.25), radius: 2, y: 1)
            }
            .clipped()
            if minimap > 0 {
                VStack(spacing: size.height * 0.03) {
                    ForEach(0..<5) { index in
                        RoundedRectangle(cornerRadius: 0.5).fill(Color.white.opacity(0.92)).frame(width: minimap * 0.62, height: minimap * 0.8)
                            .overlay(alignment: .topLeading) { if index == 2 { Rectangle().fill(Color.yellow.opacity(0.8)).frame(width: minimap * 0.4, height: 1.5).padding(3) } }
                    }
                }
                .frame(width: minimap, height: size.height, alignment: .top)
                .padding(.top, 4)
                .background(colors[.minimapBackground])
                .overlay(alignment: .top) { Rectangle().fill(colors[.minimapSliderBackground]).frame(height: size.height * 0.32).padding(.top, size.height * 0.04) }
            }
            ZStack(alignment: .top) {
                colors[.editorBackground]
                VStack(spacing: size.height * 0.12) {
                    ForEach(0..<4) { index in Rectangle().fill([Color.orange, colors.accent, Color.yellow, colors.accent][index].opacity(0.85)).frame(height: 1.5) }
                }
                .padding(.top, size.height * 0.1)
            }
            .frame(width: ruler)
        }
    }

    private func secondaryBar(_ size: CGSize) -> some View {
        let unit = size.height / 24
        return VStack(alignment: .leading, spacing: unit * 0.9) {
            HStack(spacing: unit * 0.3) {
                ForEach(0..<5) { index in
                    Capsule().fill(index == 0 ? colors.accent.opacity(0.8) : line).frame(height: unit * 0.9)
                }
            }
            ForEach(0..<3) { card in
                VStack(alignment: .leading, spacing: unit * 0.45) {
                    Capsule().fill(colors[.foreground].opacity(0.45)).frame(width: size.width * 0.45, height: max(1.5, unit * 0.45))
                    if card == 0 { RoundedRectangle(cornerRadius: 1).fill(Color.white).frame(height: unit * 2.4) }
                    ForEach(0..<2) { _ in Capsule().fill(line).frame(width: size.width * 0.62, height: max(1.2, unit * 0.36)) }
                }
                .padding(unit * 0.6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 3).fill(colors[.foreground].opacity(colors.isDark ? 0.05 : 0.04)))
            }
            Spacer(minLength: 0)
        }
        .padding(unit * 0.8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(colors[.sideBarBackground])
        .overlay(alignment: .leading) { Rectangle().fill(border).frame(width: 0.6) }
    }

    private func panelPart(_ size: CGSize) -> some View {
        let unit = size.height / 10
        return VStack(alignment: .leading, spacing: unit * 0.7) {
            HStack(spacing: unit * 1.0) {
                ForEach(["PROBLEMS", "REFERENCES", "HIERARCHY", "CONSOLE"], id: \.self) { title in
                    Text(title).font(.system(size: max(4, unit * 0.85))).foregroundStyle(title == "REFERENCES" ? colors[.panelTitleActiveForeground] : colors[.panelTitleInactiveForeground])
                        .overlay(alignment: .bottom) { if title == "REFERENCES" { Rectangle().fill(colors[.panelTitleActiveBorder]).frame(height: 0.8).offset(y: unit * 0.4) } }
                }
                Spacer(minLength: 0)
            }
            ForEach(0..<3) { index in
                HStack(spacing: unit * 0.5) {
                    Circle().fill(index == 0 ? Color.red.opacity(0.8) : colors.accent.opacity(0.7)).frame(width: unit * 0.7, height: unit * 0.7)
                    Capsule().fill(line).frame(width: size.width * [0.5, 0.42, 0.56][index], height: max(1.2, unit * 0.45))
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, unit * 1.2).padding(.top, unit * 0.8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(colors[.panelBackground])
        .overlay(alignment: .top) { Rectangle().fill(colors.border(.panelBorder) == .clear ? border : colors[.panelBorder]).frame(height: 0.6) }
    }

    private func statusBar(_ size: CGSize) -> some View {
        let h = size.height
        return HStack(spacing: h * 0.6) {
            if style == .vscode {
                Text("Read").font(.system(size: max(4, h * 0.5))).foregroundStyle(colors[.statusBarItemRemoteForeground])
                    .padding(.horizontal, h * 0.5).frame(maxHeight: .infinity).background(colors[.statusBarItemRemoteBackground])
            }
            ForEach(["890 equations · index", "p. 64, Ln 12", "1 h 12 min"], id: \.self) { item in
                Text(item).font(.system(size: max(4, h * 0.48))).lineLimit(1)
            }
            Spacer(minLength: 0)
            Image(systemName: "bell").font(.system(size: max(4, h * 0.5))).padding(.trailing, h * 0.6)
        }
        .foregroundStyle(colors[.statusBarForeground])
        .background(colors[.statusBarBackground])
        .overlay(alignment: .top) { if style == .classic { Rectangle().fill(border).frame(height: 0.6) } }
    }
}

/// Dims a miniature except one part, outlines that part and names it.
private struct MiniSpotlight: View {
    @Environment(\.theme) private var theme
    let frame: CGRect
    let size: CGSize
    let label: String
    let on: Bool

    var body: some View {
        let hole = frame.insetBy(dx: -1.5, dy: -1.5)
        ZStack(alignment: .topLeading) {
            Path { path in
                path.addRect(CGRect(origin: .zero, size: size))
                path.addRoundedRect(in: hole, cornerSize: CGSize(width: 4, height: 4))
            }
            .fill(Color.black.opacity(on ? 0.5 : 0), style: FillStyle(eoFill: true))
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .strokeBorder(theme.tourAccent, lineWidth: 2)
                .frame(width: hole.width, height: hole.height)
                .offset(x: hole.minX, y: hole.minY)
                .opacity(on ? 1 : 0)
                .scaleEffect(on ? 1 : 1.04, anchor: UnitPoint(x: hole.midX / max(1, size.width), y: hole.midY / max(1, size.height)))
            SceneCallout(text: label, size: labelSize)
                .position(clamped(calloutPoint))
                .opacity(on ? 1 : 0)
                .offset(y: on ? 0 : 6)
        }
    }

    /// The same miniature appears at 540 pt in a lesson and 168 pt in the introduction.
    private var labelSize: CGFloat { min(11, max(6, size.width * 0.024)) }

    /// Keep the annotation proportionate to the miniature and inside its edges.
    private func clamped(_ point: CGPoint) -> CGPoint {
        let half = labelWidth / 2
        let margin = labelSize * 0.55
        return CGPoint(x: min(max(point.x, half + margin), size.width - half - margin),
                       y: min(max(point.y, labelSize * 1.5), size.height - labelSize * 1.5))
    }

    private var labelWidth: CGFloat { CGFloat(label.count) * labelSize * 0.6 + labelSize * 1.6 }

    /// Inside a large part, beside a narrow one, under or over a flat one.
    private var calloutPoint: CGPoint {
        if frame.height < size.height * 0.14 {
            return CGPoint(x: frame.midX, y: frame.midY < size.height / 2 ? frame.maxY + labelSize * 1.6 : frame.minY - labelSize * 1.6)
        }
        if frame.width < size.width * 0.08 { return CGPoint(x: frame.maxX + labelWidth / 2 + labelSize * 0.8, y: frame.midY) }
        return CGPoint(x: frame.midX, y: frame.midY)
    }
}

struct WorkbenchScene: View {
    @Environment(\.theme) private var theme
    let region: MiniRegion
    let style: WorkbenchStyle
    let phase: Int
    var body: some View {
        MiniWorkbench(style: style, colors: theme, lit: region, phase: phase)
            .frame(width: 540, height: 300)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color.white.opacity(theme.isDark ? 0.14 : 0.5), lineWidth: 1))
            .shadow(color: .black.opacity(0.35), radius: 18, y: 10)
            .scaleEffect(phase >= 1 ? 1 : 0.97)
    }
}

// MARK: - How the tour works

// MARK: - Layouts

struct LayoutsScene: View {
    @Environment(\.theme) private var theme
    let phase: Int
    private let layouts: [(String, Set<MiniRegion>, Bool, Bool)] = [
        ("Reading", [.panel], false, false), ("Study", [], true, true), ("Research", [.secondarySideBar], false, true), ("Lab", [.sideBar], true, false)
    ]
    var body: some View {
        VStack(spacing: 18) {
            HStack(spacing: 14) {
                ForEach(Array(layouts.enumerated()), id: \.offset) { index, layout in
                    VStack(spacing: 7) {
                        MiniWorkbench(style: ThemeManager.shared.style, colors: theme, phase: 0, showsPanel: layout.2, showsSecondary: layout.3, hidden: layout.1)
                            .frame(width: 128, height: 82)
                            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(phase == index + 1 ? theme.accent : Color.white.opacity(0.2), lineWidth: phase == index + 1 ? 2 : 1))
                            .shadow(color: .black.opacity(0.3), radius: 8, y: 4)
                        Text(layout.0).font(.system(size: 12, weight: phase == index + 1 ? .bold : .medium)).foregroundStyle(theme.tourText)
                    }
                    .scaleEffect(phase == index + 1 ? 1.06 : 1)
                    .opacity(phase >= index + 1 ? 1 : 0.35)
                }
            }
            HStack(spacing: 12) {
                ZStack {
                    MiniWorkbench(style: ThemeManager.shared.style, colors: theme, phase: 0,
                                  hidden: phase >= 5 ? [.activityBar, .sideBar, .secondarySideBar, .panel] : [])
                        .frame(width: 210, height: 96)
                }
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .shadow(color: .black.opacity(0.3), radius: 8, y: 4)
                VStack(alignment: .leading, spacing: 6) {
                    Text("Zen Mode").font(.system(size: 15, weight: .bold)).foregroundStyle(theme.tourText)
                    Text("The side bars and the panel step away.").font(.system(size: 12)).foregroundStyle(theme.tourSecondary)
                        .frame(width: 150, alignment: .leading).fixedSize(horizontal: false, vertical: true)
                    ScenePressedKeys(keys: "⌥⌘Z", pressed: phase >= 5)
                }
            }
            .opacity(phase >= 5 ? 1 : 0.35)
        }
    }
}

// MARK: - Notifications

// MARK: - Opening a book

// MARK: - Library

struct LibraryScene: View {
    @Environment(\.theme) private var theme
    let phase: Int
    var body: some View {
        let dark = theme.isDark
        let pdf = Color(red: 0.9, green: 0.3, blue: 0.3)
        HStack(spacing: 30) {
            SceneSideBar(title: "Explorer", width: 250) {
                SceneRow(icon: "chevron-down", title: "LIBRARY", height: 18)
                SceneRow(icon: "library", iconColor: LibraryTreeStyle.kindColor("library", dark: dark), title: "Books", depth: 1) { count(10) }
                SceneRow(icon: "mortar-board", iconColor: LibraryTreeStyle.kindColor("mortar-board", dark: dark), title: "Stats", depth: 1) { count(2) }
                SceneRow(icon: "mortar-board", iconColor: LibraryTreeStyle.kindColor("mortar-board", dark: dark), title: "Quant", depth: 1) { count(9) }
                SceneRow(icon: "folder-library", iconColor: LibraryTreeStyle.kindColor("folder-library", dark: dark), title: "School", depth: 1) { count(104) }
                SceneRow(icon: "file-text", iconColor: LibraryTreeStyle.kindColor("file-text", dark: dark), title: "Papers", depth: 1) { count(phase >= 2 ? 3 : 2) }
                SceneRow(icon: "file-pdf", iconColor: pdf, title: "Adam: A Method for Stochastic…", depth: 2)
                SceneRow(icon: "file-pdf", iconColor: pdf, title: "Deep Residual Learning…", depth: 2)
                if phase >= 2 {
                    SceneRow(icon: "file-pdf", iconColor: pdf, title: "Attention Is All You Need", depth: 2, selected: phase >= 3) {
                        Text("NEW").font(.system(size: 8, weight: .bold)).foregroundStyle(theme[.badgeForeground]).padding(.horizontal, 4).padding(.vertical, 1)
                            .background(Capsule().fill(theme[.badgeBackground]))
                    }
                    .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .frame(height: 270)
            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            .shadow(color: .black.opacity(0.35), radius: 14, y: 8)
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Codicon("folder-opened", size: 22).foregroundStyle(.orange)
                    Text("~/Papers").font(.system(size: 13, weight: .semibold, design: .monospaced)).foregroundStyle(theme.tourText)
                }
                HStack(spacing: 6) {
                    Codicon("file-pdf", size: 16).foregroundStyle(pdf)
                    Text("1706.03762.pdf").font(.system(size: 12, design: .monospaced)).foregroundStyle(theme.tourText)
                }
                .padding(8)
                .background(RoundedRectangle(cornerRadius: 8).fill(theme.tourFill))
                .offset(y: phase >= 1 ? 0 : -30).opacity(phase >= 1 ? 1 : 0)
                Text("Saved in a watched folder: it appears in the Library by itself.")
                    .font(.system(size: 12)).foregroundStyle(theme.tourSecondary).frame(width: 220, alignment: .leading).fixedSize(horizontal: false, vertical: true)
                    .opacity(phase >= 2 ? 1 : 0)
            }
        }
    }

    private func count(_ value: Int) -> some View {
        Text("\(value)").font(.system(size: 9.5)).monospacedDigit().foregroundStyle(theme[.descriptionForeground])
    }
}

// MARK: - Catalog

// MARK: - arXiv

/// Names a spot only when given a name.
struct SpotIf: ViewModifier {
    let id: String?
    func body(content: Content) -> some View {
        if let id { content.sceneSpot(id) } else { content }
    }
}

// MARK: - Two PDFs side by side

// MARK: - Welcome page

// MARK: - Themes

struct ThemesScene: View {
    @Environment(\.theme) private var theme
    let phase: Int
    @State private var palettes: [(String, WorkbenchColors)] = []

    var body: some View {
        HStack(spacing: 22) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 6) {
                    Codicon("symbol-color", size: 12)
                    Text("Select Color Theme").font(.system(size: 10.5))
                    Spacer()
                    TutorialKeys(shortcut: "⌥⌘T", size: 9)
                }
                .foregroundStyle(theme[.quickInputForeground])
                .padding(.horizontal, 8).frame(height: 26)
                ForEach(Array(palettes.enumerated()), id: \.offset) { index, palette in
                    HStack {
                        Text(palette.0).font(.system(size: 10.5)).lineLimit(1)
                        Spacer()
                    }
                    .foregroundStyle(index == current ? theme[.quickInputListFocusForeground] : theme[.quickInputForeground])
                    .padding(.horizontal, 10).frame(height: 21)
                    .background(index == current ? theme[.quickInputListFocusBackground] : .clear)
                }
            }
            .frame(width: 230)
            .background(RoundedRectangle(cornerRadius: 6).fill(theme[.quickInputBackground]))
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .shadow(color: .black.opacity(0.35), radius: 10, y: 5)
            if let colors = palettes.indices.contains(current) ? palettes[current].1 : nil {
                MiniWorkbench(style: .vscode, colors: colors, lit: nil, phase: 0)
                    .frame(width: 330, height: 210)
                    .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                    .shadow(color: .black.opacity(0.35), radius: 14, y: 8)
                    .id(current)
                    .transition(.opacity)
            }
        }
        .onAppear(perform: load)
    }

    private var current: Int { min(max(0, phase - 1), max(0, palettes.count - 1)) }

    private func load() {
        guard palettes.isEmpty else { return }
        let manager = ThemeManager.shared
        palettes = ["dark-2026", "synthwave-84", "light-2026", "lemma-midnight", "solarized-light"].compactMap { id in
            guard let entry = manager.entry(id), let found = manager.theme(id) else { return nil }
            return (entry.label, WorkbenchColors(theme: found, defaults: manager.defaultsForPreview))
        }
    }
}

struct InterfaceStyleScene: View {
    @Environment(\.theme) private var theme
    let phase: Int
    @State private var classic: WorkbenchColors?

    var body: some View {
        VStack(spacing: 16) {
            ZStack {
                if phase % 2 == 0 {
                    MiniWorkbench(style: .vscode, colors: theme.isClassic ? (classic ?? theme) : theme, lit: nil, phase: 0).transition(.opacity)
                } else {
                    MiniWorkbench(style: .classic, colors: classic ?? theme, lit: nil, phase: 0).transition(.opacity)
                }
            }
            .frame(width: 420, height: 230)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .shadow(color: .black.opacity(0.35), radius: 16, y: 8)
            HStack(spacing: 0) {
                ForEach(["VS Code", "Classic"], id: \.self) { label in
                    let on = (label == "VS Code") == (phase % 2 == 0)
                    Text(label).font(.system(size: 12, weight: on ? .semibold : .regular))
                        .foregroundStyle(on ? theme[.buttonForeground] : theme.tourText)
                        .frame(width: 96, height: 26)
                        .background(Capsule().fill(on ? theme[.buttonBackground] : .clear))
                }
            }
            .padding(3)
            .background(Capsule().fill(theme.tourFill))
        }
        .onAppear {
            let manager = ThemeManager.shared
            classic = WorkbenchColors(theme: ThemeManager.classicTheme(WorkbenchTheme.current, accent: WorkbenchAccent.current,
                                                                       dark: WorkbenchTheme.current.scheme.map { $0 == .dark } ?? manager.systemIsDark),
                                      defaults: manager.defaultsForPreview)
        }
    }
}

extension WorkbenchColors {
    /// Whether these colours are the Classic interface's.
    var isClassic: Bool { theme.origin == "classic" }
}

// MARK: - Settings and shortcuts

struct SettingsScene: View {
    @Environment(\.theme) private var theme
    let phase: Int
    var body: some View {
        SceneWindow(title: "Settings") {
            HStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(["Commonly Used", "Workbench", "Editor", "Reading", "Lab", "Notifications"], id: \.self) { category in
                        Text(category).font(.system(size: 10, weight: category == "Editor" ? .semibold : .regular))
                            .foregroundStyle(category == "Editor" ? theme[.foreground] : theme[.descriptionForeground])
                    }
                }
                .padding(14).frame(width: 130, alignment: .topLeading).frame(maxHeight: .infinity, alignment: .top)
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 6) {
                        Codicon("search", size: 11).foregroundStyle(theme[.inputPlaceholderForeground])
                        Text(phase >= 1 ? "minimap" : "Search settings").font(.system(size: 10.5)).foregroundStyle(phase >= 1 ? theme[.inputForeground] : theme[.inputPlaceholderForeground])
                        Spacer()
                    }
                    .padding(.horizontal, 7).frame(height: 22)
                    .background(RoundedRectangle(cornerRadius: 3).fill(theme[.settingsTextInputBackground]))
                    .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(theme[.focusBorder], lineWidth: 1))
                    setting(title: "Editor › Minimap: Enabled", detail: "Show page miniatures beside the page.", checked: phase < 3, modified: phase >= 3)
                    setting(title: "Editor › Minimap: Show Slider", detail: "Always, or only under the pointer.", checked: false, modified: false)
                    setting(title: "Workbench › Appearance: Accent", detail: "Olive, blue, violet or copper over the theme.", checked: nil, modified: phase >= 2)
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .background(theme[.editorBackground])
        }
        .frame(width: 480, height: 260)
        .scenePointer(at: phase >= 2 ? "check" : nil, clicks: phase >= 3 ? 1 : 0)
    }

    private func setting(title: String, detail: String, checked: Bool?, modified: Bool) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Rectangle().fill(modified ? theme[.settingsModifiedItemIndicator] : .clear).frame(width: 2)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.system(size: 10.5, weight: .semibold)).foregroundStyle(theme[.settingsHeaderForeground])
                HStack(spacing: 6) {
                    if let checked {
                        RoundedRectangle(cornerRadius: 2).fill(theme[.checkboxBackground]).frame(width: 12, height: 12)
                            .overlay(RoundedRectangle(cornerRadius: 2).strokeBorder(theme[.checkboxBorder], lineWidth: 1))
                            .overlay { if checked { Codicon("check", size: 9).foregroundStyle(theme[.checkboxForeground]) } }
                            .modifier(SpotIf(id: title.hasSuffix("Enabled") ? "check" : nil))
                    } else {
                        Text("Violet").font(.system(size: 9.5)).padding(.horizontal, 6).frame(height: 16)
                            .background(RoundedRectangle(cornerRadius: 3).fill(theme[.dropdownBackground]))
                    }
                    Text(detail).font(.system(size: 9.5)).foregroundStyle(theme[.descriptionForeground])
                }
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - Arranging the window

// MARK: - Privacy and exports

struct PrivacyScene: View {
    @Environment(\.theme) private var theme
    let phase: Int
    private let local: [(String, String)] = [("note", "Notes"), ("bookmark", "Marks"), ("notebook", "Notebooks"), ("history", "Progress"), ("symbol-operator", "Derivations"), ("file-pdf", "PDFs untouched")]
    private let services: [(String, String)] = [("extensions", "Catalog"), ("cloud-download", "arXiv"), ("search", "Find the Paper"), ("comment-discussion", "ChatGPT")]
    var body: some View {
        HStack(spacing: 34) {
            VStack(spacing: 10) {
                HStack(spacing: 6) { Codicon("lock", size: 15); Text("On this Mac").font(.system(size: 14, weight: .bold)) }.foregroundStyle(theme.tourText)
                LazyVGrid(columns: [GridItem(.fixed(122)), GridItem(.fixed(122))], spacing: 8) {
                    ForEach(Array(local.enumerated()), id: \.offset) { index, item in
                        HStack(spacing: 6) {
                            Codicon(item.0, size: 12).foregroundStyle(theme.accent)
                            Text(item.1).font(.system(size: 10.5)).foregroundStyle(theme.tourText).lineLimit(1)
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 8).frame(height: 28)
                        .background(RoundedRectangle(cornerRadius: 7).fill(theme.tourFill))
                        .opacity(phase >= 1 ? 1 : 0)
                        .animation(.spring(response: 0.5, dampingFraction: 0.8).delay(Double(index) * 0.06), value: phase)
                    }
                }
            }
            .padding(16)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(theme[.editorWidgetBackground]).shadow(color: .black.opacity(0.3), radius: 12, y: 6))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(theme.accent.opacity(0.6), lineWidth: 1.5))
            VStack(alignment: .leading, spacing: 10) {
                Text("ONLY WHEN YOU CLICK").font(.system(size: 10, weight: .semibold)).tracking(1).foregroundStyle(theme.tourTertiary)
                ForEach(Array(services.enumerated()), id: \.offset) { index, service in
                    HStack(spacing: 8) {
                        Rectangle().fill(theme.tourText.opacity(0.35)).frame(width: 22, height: 1)
                            .overlay(Rectangle().fill(theme.accent).frame(width: phase >= 3 && index == 3 ? 22 : 0, height: 1.5), alignment: .leading)
                        Codicon(service.0, size: 13).foregroundStyle(theme.tourText)
                        Text(service.1).font(.system(size: 12, weight: .medium)).foregroundStyle(theme.tourText)
                        Codicon("cloud", size: 12).foregroundStyle(theme.tourTertiary)
                    }
                    .opacity(phase >= 2 ? 1 : 0)
                }
            }
        }
    }
}

