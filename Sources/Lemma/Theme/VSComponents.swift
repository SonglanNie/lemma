import SwiftUI
import AppKit
import LemmaCore

// The workbench's controls, drawn as VS Code draws them: flat, 2–5 pt corners, a 1 pt focus border in the theme's
// accent, hover tints from the theme, the system UI font at 13 pt and codicons at 16 pt.

enum VSMetrics {
    static let titleBarHeight: CGFloat = 35
    static let activityBarWidth: CGFloat = 48
    static let activityItemHeight: CGFloat = 48
    static let viewTitleHeight: CGFloat = 35
    static let paneHeaderHeight: CGFloat = 22
    static let rowHeight: CGFloat = 22
    static let tabHeight: CGFloat = 35
    static let breadcrumbHeight: CGFloat = 22
    static let statusBarHeight: CGFloat = 22
    static let panelTitleHeight: CGFloat = 35
    static let treeIndent: CGFloat = 8
    static let twistieWidth: CGFloat = 16
}

extension Font {
    /// The workbench's UI font: the system font, 13 pt unless stated.
    static func ui(_ size: CGFloat = 13, weight: Font.Weight = .regular) -> Font { .system(size: size, weight: weight) }
    /// The editor font (Menlo 12 by default on macOS, as in VS Code), configurable in Settings.
    static func code(_ size: CGFloat? = nil) -> Font { .custom(EditorFont.family, size: size ?? EditorFont.size) }
}

enum EditorFont {
    static let familyKey = "editor.fontFamily", sizeKey = "editor.fontSize"
    static var family: String {
        let value = UserDefaults.standard.string(forKey: familyKey) ?? "Menlo"
        return NSFont(name: value, size: 12) != nil ? value : "Menlo"
    }
    static var size: CGFloat { CGFloat(UserDefaults.standard.object(forKey: sizeKey) as? Double ?? 12) }
    static func nsFont(_ size: CGFloat? = nil, bold: Bool = false) -> NSFont {
        let font = NSFont(name: family, size: size ?? self.size) ?? .monospacedSystemFont(ofSize: size ?? self.size, weight: .regular)
        return bold ? NSFontManager.shared.convert(font, toHaveTrait: .boldFontMask) : font
    }
}

/// A toolbar action: a 16 pt codicon in a 22 pt square, tinted on hover, as VS Code's action bars.
struct VSIconButton: View {
    @Environment(\.theme) private var theme
    let icon: String
    var help: String = ""
    var size: CGFloat = 16
    var toggled = false
    var tint: Color? = nil
    var enabled = true
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Codicon(icon, size: size)
                .foregroundStyle(tint ?? theme[.iconForeground])
                .frame(width: size + 6, height: size + 6)
                .background(RoundedRectangle(cornerRadius: 6).fill(background))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(toggled && theme.has(.inputOptionActiveBorder) ? theme[.inputOptionActiveBorder] : .clear, lineWidth: 1))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.4)
        .onHover { hovering = $0 }
        .help(help)
        .accessibilityLabel(help.isEmpty ? icon : help)
        .accessibilityAddTraits(toggled ? .isSelected : [])
    }

    private var background: Color {
        if toggled { return theme.has(.actionBarToggledBackground) ? theme[.actionBarToggledBackground] : theme[.inputOptionActiveBackground] }
        return hovering && enabled ? theme[.toolbarHoverBackground] : .clear
    }
}

/// VS Code's text button: primary (accent) or secondary.
struct VSButtonStyle: ButtonStyle {
    enum Kind { case primary, secondary, prominent }
    var kind: Kind = .primary
    var compact = false
    @Environment(\.theme) private var theme
    @Environment(\.isEnabled) private var enabled

    func makeBody(configuration: Configuration) -> some View {
        StyledBody(configuration: configuration, kind: kind, compact: compact, theme: theme, enabled: enabled)
    }

    private struct StyledBody: View {
        let configuration: Configuration
        let kind: Kind
        let compact: Bool
        let theme: WorkbenchColors
        let enabled: Bool
        @State private var hovering = false

        var body: some View {
            let background: TC = switch kind {
            case .primary: hovering ? .buttonHoverBackground : .buttonBackground
            case .secondary: hovering ? .buttonSecondaryHoverBackground : .buttonSecondaryBackground
            case .prominent: hovering ? .extensionButtonProminentHoverBackground : .extensionButtonProminentBackground
            }
            let foreground: TC = switch kind { case .primary: .buttonForeground; case .secondary: .buttonSecondaryForeground; case .prominent: .extensionButtonProminentForeground }
            configuration.label
                .font(.ui(compact ? 11 : 12))
                .lineLimit(1)
                .foregroundStyle(theme[foreground])
                .padding(.horizontal, compact ? 6 : 8)
                .frame(minHeight: compact ? 22 : 26)
                .background(RoundedRectangle(cornerRadius: 4).fill(theme[background]))
                .overlay(RoundedRectangle(cornerRadius: 4).stroke(theme.border(.buttonBorder), lineWidth: 1))
                .opacity(enabled ? (configuration.isPressed ? 0.85 : 1) : 0.4)
                .contentShape(Rectangle())
                .onHover { hovering = $0 && enabled }
        }
    }
}

extension ButtonStyle where Self == VSButtonStyle {
    static var vsPrimary: VSButtonStyle { VSButtonStyle(kind: .primary) }
    static var vsSecondary: VSButtonStyle { VSButtonStyle(kind: .secondary) }
    static var vsProminent: VSButtonStyle { VSButtonStyle(kind: .prominent, compact: true) }
}

/// A link-coloured text button, as VS Code's walkthrough and settings links.
struct VSLinkButton: View {
    @Environment(\.theme) private var theme
    let title: String
    var icon: String? = nil
    let action: () -> Void
    @State private var hovering = false
    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if let icon { Codicon(icon, size: 14) }
                Text(title).underline(hovering)
            }
            .font(.ui(13)).foregroundStyle(theme[hovering ? .textLinkActiveForeground : .textLinkForeground]).contentShape(Rectangle())
        }.buttonStyle(.plain).onHover { hovering = $0 }
    }
}

/// An input box: input colours, a 1 pt border that turns to the focus colour.
struct VSTextField: View {
    @Environment(\.theme) private var theme
    let placeholder: String
    @Binding var text: String
    var icon: String? = nil
    var onSubmit: () -> Void = {}
    var trailing: AnyView? = nil
    /// ↓ in the field, to move into the list it filters.
    var onDownArrow: (() -> Void)? = nil
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 4) {
            if let icon { Codicon(icon, size: 14).foregroundStyle(theme[.inputPlaceholderForeground]) }
            TextField("", text: $text, prompt: Text(placeholder).foregroundColor(theme[.inputPlaceholderForeground]))
                .textFieldStyle(.plain).font(.ui(13)).foregroundStyle(theme[.inputForeground])
                .focused($focused).onSubmit(onSubmit)
                .onKeyPress(.downArrow) {
                    guard let onDownArrow else { return .ignored }
                    onDownArrow(); return .handled
                }
                .accessibilityLabel(placeholder)
            if !text.isEmpty, trailing == nil {
                VSIconButton(icon: "close", help: "Clear", size: 14) { text = "" }
            }
            if let trailing { trailing }
        }
        .padding(.horizontal, 6)
        .frame(height: 28)
        .background(RoundedRectangle(cornerRadius: 4).fill(theme[.inputBackground]))
        .overlay(RoundedRectangle(cornerRadius: 4).stroke(focused ? theme[.focusBorder] : theme.border(.inputBorder), lineWidth: 1))
    }
}

/// A square option toggle inside an input (Aa, ab, .*), as VS Code's find and search widgets.
struct VSInputOption: View {
    @Environment(\.theme) private var theme
    let icon: String
    let help: String
    @Binding var isOn: Bool
    @State private var hovering = false
    var body: some View {
        Button { isOn.toggle() } label: {
            Codicon(icon, size: 16).foregroundStyle(isOn ? theme[.inputOptionActiveForeground] : theme[.iconForeground])
                .frame(width: 20, height: 20)
                .background(RoundedRectangle(cornerRadius: 3).fill(isOn ? theme[.inputOptionActiveBackground] : hovering ? theme[.inputOptionHoverBackground] : .clear))
                .overlay(RoundedRectangle(cornerRadius: 3).stroke(isOn ? theme[.inputOptionActiveBorder] : .clear, lineWidth: 1))
        }.buttonStyle(.plain).onHover { hovering = $0 }.help(help).accessibilityLabel(help).accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

/// VS Code's checkbox: an 18 pt rounded square with a check codicon.
struct VSCheckbox: View {
    @Environment(\.theme) private var theme
    @Binding var isOn: Bool
    var label: String? = nil
    var body: some View {
        Button { isOn.toggle() } label: {
            HStack(spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 3).fill(theme[.checkboxBackground])
                    RoundedRectangle(cornerRadius: 3).stroke(theme[.checkboxBorder], lineWidth: 1)
                    if isOn { Codicon("check", size: 14).foregroundStyle(theme[.checkboxForeground]) }
                }.frame(width: 18, height: 18)
                if let label { Text(label).font(.ui(13)).foregroundStyle(theme[.foreground]) }
            }.contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityLabel(label ?? "Checkbox").accessibilityValue(isOn ? "on" : "off")
    }
}

/// A count badge: “12” on the badge colours, in an 18 pt capsule.
struct VSBadge: View {
    @Environment(\.theme) private var theme
    let count: Int
    var background: TC = .badgeBackground
    var foreground: TC = .badgeForeground
    var body: some View {
        Text(count > 999 ? "999+" : "\(count)")
            .font(.ui(11)).monospacedDigit()
            .foregroundStyle(theme[foreground])
            .padding(.horizontal, 5)
            .frame(minWidth: 18, minHeight: 18)
            .background(Capsule().fill(theme[background]))
    }
}

/// A keyboard shortcut as key caps (“⇧ ⌘ P”), as VS Code's keybinding labels.
struct VSKeybinding: View {
    @Environment(\.theme) private var theme
    let shortcut: String
    var body: some View {
        HStack(spacing: 2) {
            ForEach(Array(VSKeybinding.keys(shortcut).enumerated()), id: \.offset) { _, key in
                Text(key)
                    .font(.ui(11))
                    .foregroundStyle(theme[.keybindingLabelForeground])
                    .padding(.horizontal, 5).frame(minWidth: 18, minHeight: 18)
                    .background(RoundedRectangle(cornerRadius: 3).fill(theme[.keybindingLabelBackground]))
                    .overlay(RoundedRectangle(cornerRadius: 3).stroke(theme[.keybindingLabelBorder], lineWidth: 1))
                    .overlay(alignment: .bottom) { RoundedRectangle(cornerRadius: 3).fill(theme[.keybindingLabelBottomBorder]).frame(height: 1).padding(.horizontal, 1) }
            }
        }.accessibilityLabel(shortcut)
    }

    /// “⇧⌘P” → [“⇧”, “⌘”, “P”]; chords (“⌘K ⌘T”) keep their space.
    static func keys(_ shortcut: String) -> [String] {
        var keys: [String] = []
        let modifiers: Set<Character> = ["⌘", "⇧", "⌥", "⌃"]
        var current = ""
        for character in shortcut {
            if character == " " { if !current.isEmpty { keys.append(current); current = "" }; continue }
            if modifiers.contains(character) {
                if !current.isEmpty { keys.append(current); current = "" }
                keys.append(String(character))
            } else { current.append(character) }
        }
        if !current.isEmpty { keys.append(current) }
        return keys
    }
}

/// The title row of a side bar view: “EXPLORER”, with the view's actions.
struct VSViewTitle<Actions: View>: View {
    @Environment(\.theme) private var theme
    let title: String
    var subtitle: String? = nil
    @ViewBuilder var actions: Actions
    @State private var hovering = false
    var body: some View {
        HStack(spacing: 4) {
            Text(title.uppercased()).font(.ui(11)).foregroundStyle(theme[.sideBarTitleForeground]).lineLimit(1)
            if let subtitle { Text(subtitle).font(.ui(11)).foregroundStyle(theme[.descriptionForeground]).lineLimit(1).truncationMode(.middle) }
            Spacer(minLength: 4)
            HStack(spacing: 2) { actions }
        }
        .padding(.leading, 20).padding(.trailing, 8)
        .frame(height: VSMetrics.viewTitleHeight)
        .background(theme.has(.sideBarTitleBackground) ? theme[.sideBarTitleBackground] : .clear)
        .onHover { hovering = $0 }
        .accessibilityElement(children: .contain)
    }
}

/// A collapsible pane inside a side bar view (“OPEN EDITORS”, “OUTLINE”), as VS Code's pane headers.
struct VSPane<Actions: View, Content: View>: View {
    @Environment(\.theme) private var theme
    let title: String
    @Binding var expanded: Bool
    var count: Int? = nil
    var showsTopBorder = true
    @ViewBuilder var actions: Actions
    @ViewBuilder var content: Content
    @State private var hovering = false

    var body: some View {
        VStack(spacing: 0) {
            Button { withAnimation(.easeOut(duration: 0.12)) { expanded.toggle() } } label: {
                HStack(spacing: 2) {
                    Codicon(expanded ? "chevron-down" : "chevron-right", size: 16).foregroundStyle(theme[.sideBarSectionHeaderForeground])
                    Text(title.uppercased()).font(.ui(11, weight: .bold)).foregroundStyle(theme[.sideBarSectionHeaderForeground]).lineLimit(1)
                    Spacer(minLength: 4)
                    if hovering && expanded { HStack(spacing: 2) { actions } }
                    else if let count, count > 0 { VSBadge(count: count) }
                }
                .padding(.leading, 2).padding(.trailing, 8)
                .frame(height: VSMetrics.paneHeaderHeight)
                .background(theme[.sideBarSectionHeaderBackground])
                .overlay(alignment: .top) { if showsTopBorder { Rectangle().fill(theme.border(.sideBarSectionHeaderBorder)).frame(height: 1) } }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { hovering = $0 }
            .accessibilityLabel(title)
            .accessibilityValue(expanded ? "expanded" : "collapsed")
            if expanded { content }
        }
    }
}

/// A row in a VS Code list or tree: 22 pt, hover tint, selection colours, optional focus outline.
struct VSRow<Content: View>: View {
    @Environment(\.theme) private var theme
    var selected = false
    var depth = 0
    var height: CGFloat = VSMetrics.rowHeight
    var action: (() -> Void)? = nil
    @ViewBuilder var content: Content
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 0) { content }
            .padding(.leading, CGFloat(depth) * VSMetrics.treeIndent + 8).padding(.trailing, 8)
            .frame(maxWidth: .infinity, minHeight: height, alignment: .leading)
            .foregroundStyle(selected ? theme[.listActiveSelectionForeground] : hovering ? theme[.listHoverForeground] : theme[.sideBarForeground])
            .background(selected ? theme[.listActiveSelectionBackground] : hovering ? theme[.listHoverBackground] : .clear)
            .contentShape(Rectangle())
            .onHover { hovering = $0 }
            .onTapGesture { action?() }
            .accessibilityAddTraits(selected ? [.isSelected, .isButton] : .isButton)
    }
}

/// A twistie: the chevron of a tree row, or the room it takes.
struct VSTwistie: View {
    @Environment(\.theme) private var theme
    let expandable: Bool
    let expanded: Bool
    var toggle: () -> Void = {}
    var body: some View {
        Group {
            if expandable {
                Codicon(expanded ? "chevron-down" : "chevron-right", size: 16).foregroundStyle(theme[.iconForeground])
                    .contentShape(Rectangle()).onTapGesture(perform: toggle)
            } else { Color.clear }
        }.frame(width: VSMetrics.twistieWidth, height: 16)
    }
}

/// All workbench dividers share a native, twelve-point grab area and a thin visible line.
struct VSSash: View {
    enum Axis { case vertical, horizontal }
    @Environment(\.theme) private var theme
    let axis: Axis
    var onDrag: (CGFloat) -> Void
    var onEnd: () -> Void = {}
    var onDoubleClick: () -> Void = {}
    var body: some View {
        let classic = ThemeManager.shared.style == .classic
        let accent = classic ? Color.lemmaOlive : theme.has(.sashHoverBorder) ? theme[.sashHoverBorder] : theme[.focusBorder]
        NativeResizeSash(axis: axis, line: classic ? Color(nsColor: .separatorColor) : theme.border(.sideBarBorder),
                         accent: accent, onDrag: onDrag, onEnd: onEnd, onDoubleClick: onDoubleClick)
            .frame(width: axis == .vertical ? ResizeSashView.thickness : nil,
                   height: axis == .horizontal ? ResizeSashView.thickness : nil)
    }
}

/// VS Code's 2 pt progress line under a view's title while it works.
struct VSProgressLine: View {
    @Environment(\.theme) private var theme
    var value: Double? = nil
    var body: some View {
        GeometryReader { geometry in
            if let value {
                Rectangle().fill(theme[.progressBarBackground]).frame(width: geometry.size.width * max(0, min(1, value)))
            } else {
                // The sweep is a Core Animation layer, animated by the render server, that exists only while the line
                // is shown. (A SwiftUI forever animation had the main thread redraw at every frame, and could outlive it.)
                ProgressSweep(color: theme.ns(.progressBarBackground))
            }
        }.frame(height: 2).clipped()
    }
}

private struct ProgressSweep: NSViewRepresentable {
    let color: NSColor
    func makeNSView(context: Context) -> ProgressSweepView { ProgressSweepView() }
    func updateNSView(_ view: ProgressSweepView, context: Context) { view.color = color }
}

/// A bar a third of the line wide crossing it every 1.6 s.
private final class ProgressSweepView: NSView {
    private let bar = CALayer()
    var color: NSColor = .controlAccentColor { didSet { if color != oldValue { bar.backgroundColor = color.cgColor } } }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.masksToBounds = true
        layer?.addSublayer(bar)
    }
    required init?(coder: NSCoder) { nil }

    override func layout() { super.layout(); sweep() }
    override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); sweep() }

    private func sweep() {
        let width = bounds.width
        CATransaction.begin(); CATransaction.setDisableActions(true)
        bar.frame = CGRect(x: 0, y: 0, width: width * 0.3, height: bounds.height)
        bar.backgroundColor = color.cgColor
        CATransaction.commit()
        bar.removeAnimation(forKey: "sweep")
        guard window != nil, width > 0 else { return }
        let animation = CABasicAnimation(keyPath: "position.x")
        // The bar's centre goes from just before the line to just after it.
        animation.fromValue = -0.15 * width
        animation.toValue = 1.15 * width
        animation.duration = 1.6
        animation.repeatCount = .infinity
        bar.add(animation, forKey: "sweep")
    }
}

/// A dropdown: VS Code's select box drawn over a native menu.
struct VSDropdown<Value: Hashable>: View {
    @Environment(\.theme) private var theme
    let options: [(value: Value, label: String)]
    @Binding var selection: Value
    var width: CGFloat? = nil
    var body: some View {
        VSMenu(items: { options.map { option in .action(option.label, checked: option.value == selection) { selection = option.value } } }) {
            HStack(spacing: 4) {
                Text(options.first { $0.value == selection }?.label ?? "").font(.ui(13)).foregroundStyle(theme[.dropdownForeground]).lineLimit(1)
                Spacer(minLength: 4)
                Codicon("chevron-down", size: 14).foregroundStyle(theme[.dropdownForeground])
            }
            .padding(.horizontal, 6).frame(width: width, height: 26)
            .background(RoundedRectangle(cornerRadius: 4).fill(theme[.dropdownBackground]))
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(theme.border(.dropdownBorder), lineWidth: 1))
        }
        .fixedSize(horizontal: width == nil, vertical: true)
    }
}

/// An empty view's message, as VS Code's welcome views: text and optional buttons, left aligned.
struct VSWelcomeView<Buttons: View>: View {
    @Environment(\.theme) private var theme
    let message: String
    @ViewBuilder var buttons: Buttons
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(message).font(.ui(13)).foregroundStyle(theme[.foreground]).fixedSize(horizontal: false, vertical: true).lineSpacing(2)
            buttons
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20).padding(.top, 13)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

extension View {
    /// A thin border on one edge in a theme colour, drawn only when the theme defines it.
    func vsBorder(_ edge: Edge, _ key: TC, theme: WorkbenchColors) -> some View {
        overlay(alignment: edge == .top ? .top : edge == .bottom ? .bottom : edge == .leading ? .leading : .trailing) {
            if theme.has(key) {
                Rectangle().fill(theme[key]).frame(width: edge == .leading || edge == .trailing ? 1 : nil, height: edge == .top || edge == .bottom ? 1 : nil)
            }
        }
    }

    /// A widget's shadow (hovers, the quick input, notifications) in the theme's shadow colour.
    func vsWidgetShadow(_ theme: WorkbenchColors) -> some View {
        shadow(color: theme.has(.widgetShadow) ? theme[.widgetShadow] : .black.opacity(0.14), radius: 6, x: 0, y: 0)
    }
}

/// Highlights the characters of `text` that a fuzzy query matched, as VS Code's quick open does.
struct VSHighlightedText: View {
    @Environment(\.theme) private var theme
    let text: String
    let matches: [Range<String.Index>]
    var highlight: TC = .listHighlightForeground
    var body: some View {
        var attributed = AttributedString(text)
        for range in matches {
            if let lower = AttributedString.Index(range.lowerBound, within: attributed), let upper = AttributedString.Index(range.upperBound, within: attributed) {
                attributed[lower..<upper].foregroundColor = theme[highlight]
                attributed[lower..<upper].font = .ui(13, weight: .bold)
            }
        }
        return Text(attributed)
    }
}

enum FuzzyMatch {
    /// Contiguous matches of the query's words in `text`, case-insensitive, for highlighting.
    static func ranges(of query: String, in text: String) -> [Range<String.Index>] {
        let words = query.lowercased().split(whereSeparator: { $0 == " " }).map(String.init).filter { !$0.isEmpty }
        guard !words.isEmpty else { return [] }
        var ranges: [Range<String.Index>] = []
        let lower = text.lowercased()
        guard lower.count == text.count else { return [] }
        for word in words {
            if let range = lower.range(of: word) {
                let start = text.index(text.startIndex, offsetBy: lower.distance(from: lower.startIndex, to: range.lowerBound))
                let end = text.index(start, offsetBy: word.count)
                ranges.append(start..<end)
            } else {
                // Initials: every character of the word in order (VS Code's fuzzy scoring keeps them).
                var index = lower.startIndex
                var found: [Range<String.Index>] = []
                for character in word {
                    guard let hit = lower[index...].firstIndex(of: character) else { found = []; break }
                    let offset = lower.distance(from: lower.startIndex, to: hit)
                    let start = text.index(text.startIndex, offsetBy: offset)
                    found.append(start..<text.index(after: start))
                    index = lower.index(after: hit)
                }
                ranges += found
            }
        }
        return ranges
    }
}
