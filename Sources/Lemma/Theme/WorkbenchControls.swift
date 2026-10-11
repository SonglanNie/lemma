import SwiftUI
import AppKit

// Controls shared by the sheets and panes that both interface styles show (the Assistants sheet, the full question
// draft): VS Code's flat buttons, inputs, tabs and list rows in the VS Code style, the native controls in Classic.

enum WorkbenchButtonKind { case primary, secondary }

extension View {
    /// A text button as the interface style draws it: VS Code's flat button, or the native bordered one in Classic.
    /// `compact` is the small size, for a button inside a line of text.
    func workbenchButton(_ kind: WorkbenchButtonKind = .secondary, compact: Bool = false) -> some View {
        modifier(WorkbenchButtonModifier(kind: kind, compact: compact))
    }

    /// A text button drawn as a link: the theme's link colour in the VS Code style, the native link in Classic.
    func workbenchLinkStyle() -> some View { modifier(WorkbenchLinkModifier()) }

    /// The box of a text input: the theme's input colours and border in the VS Code style, the text background in Classic.
    func workbenchInputBox() -> some View { modifier(WorkbenchInputBox()) }
}

private struct WorkbenchButtonModifier: ViewModifier {
    let kind: WorkbenchButtonKind
    var compact = false
    @State private var themes = ThemeManager.shared
    func body(content: Content) -> some View {
        if themes.style == .vscode {
            content.buttonStyle(VSButtonStyle(kind: kind == .primary ? .primary : .secondary, compact: compact))
        } else if kind == .primary {
            content.buttonStyle(.borderedProminent).controlSize(compact ? .small : .regular)
        } else {
            content.buttonStyle(.bordered).controlSize(compact ? .small : .regular)
        }
    }
}

private struct WorkbenchLinkModifier: ViewModifier {
    @State private var themes = ThemeManager.shared
    func body(content: Content) -> some View {
        if themes.style == .vscode { content.buttonStyle(VSLinkStyle()) } else { content.buttonStyle(.link) }
    }
}

/// VS Code's text link as a button style: the link colour, its active colour and an underline under the pointer.
struct VSLinkStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View { StyledLink(configuration: configuration) }

    private struct StyledLink: View {
        let configuration: Configuration
        @Environment(\.theme) private var theme
        @Environment(\.isEnabled) private var enabled
        @State private var hovering = false
        var body: some View {
            configuration.label
                .underline(hovering && enabled)
                .foregroundStyle(theme[hovering || configuration.isPressed ? .textLinkActiveForeground : .textLinkForeground])
                .opacity(enabled ? 1 : 0.45)
                .contentShape(Rectangle())
                .onHover { hovering = $0 }
        }
    }
}

private struct WorkbenchInputBox: ViewModifier {
    @Environment(\.theme) private var theme
    @State private var themes = ThemeManager.shared
    func body(content: Content) -> some View {
        if themes.style == .vscode {
            content
                .foregroundStyle(theme[.inputForeground])
                .background(theme[.inputBackground], in: RoundedRectangle(cornerRadius: 4))
                .overlay(RoundedRectangle(cornerRadius: 4).stroke(theme.border(.inputBorder), lineWidth: 1))
        } else {
            content.background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
        }
    }
}

extension WorkbenchColors {
    /// A hairline between two parts: the theme's border when it sets one, else the text colour, faintly.
    func hairline(_ key: TC) -> Color { has(key) ? self[key] : self[.foreground].opacity(0.1) }
}

/// A one-line input: VS Code's input box, or the native rounded field in Classic. `secure` hides what is typed.
struct WorkbenchTextField: View {
    let placeholder: String
    @Binding var text: String
    var secure = false
    var accessibilityLabel: String? = nil
    var onSubmit: () -> Void = {}
    @State private var themes = ThemeManager.shared

    var body: some View {
        Group {
            if themes.style == .vscode {
                VSTextField(placeholder: placeholder, text: $text, secure: secure, onSubmit: onSubmit)
            } else if secure {
                SecureField(placeholder, text: $text).textFieldStyle(.roundedBorder).onSubmit(onSubmit)
            } else {
                TextField(placeholder, text: $text).textFieldStyle(.roundedBorder).onSubmit(onSubmit)
            }
        }
        .accessibilityLabel(accessibilityLabel ?? placeholder)
    }
}

/// The title bar of a workbench sheet: an icon and the title, the sheet's tabs, and its actions on the right, on the
/// side bar's colour with a hairline under it, as VS Code draws a panel's title bar.
struct WorkbenchSheetHeader<Tabs: View, Actions: View>: View {
    let codicon: String
    let symbol: String
    let title: String
    @ViewBuilder var tabs: Tabs
    @ViewBuilder var actions: Actions
    @Environment(\.theme) private var theme
    @State private var themes = ThemeManager.shared

    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: 8) {
                if themes.style == .vscode { Codicon(codicon, size: 16).foregroundStyle(theme[.iconForeground]) }
                else { Image(systemName: symbol).font(.system(size: 14)).foregroundStyle(theme[.descriptionForeground]) }
                Text(title).font(.ui(13, weight: .semibold)).lineLimit(1)
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
            HStack(spacing: 2) { tabs }.padding(.leading, 20)
            Spacer(minLength: 12)
            HStack(spacing: 8) { actions }
        }
        .padding(.leading, 16).padding(.trailing, 12)
        .frame(height: 44)
        .background(theme[.sideBarBackground])
        .overlay(alignment: .bottom) { Rectangle().fill(theme.hairline(.sideBarBorder)).frame(height: 1) }
    }
}

/// A tab of a sheet's title bar: VS Code's panel tab (uppercase, a line under the active one, a count badge).
struct WorkbenchSheetTab: View {
    let title: String
    var count: Int? = nil
    let active: Bool
    let select: () -> Void
    var body: some View {
        InspectorTitleTab(title: title, count: count, active: active, select: select)
            .padding(.horizontal, 4)
            .accessibilityLabel(count.map { "\(title), \($0)" } ?? title)
    }
}

/// A row of a workbench list that may take two lines: the full width, the hover tint and the selection colours in the
/// VS Code style; an inset, rounded selection in Classic, as its lists draw it.
struct WorkbenchListRow<Content: View>: View {
    let selected: Bool
    let action: () -> Void
    @ViewBuilder var content: Content
    @Environment(\.theme) private var theme
    @State private var themes = ThemeManager.shared
    @State private var hovering = false

    var body: some View {
        let vscode = themes.style == .vscode
        Button(action: action) {
            content
                .foregroundStyle(selected ? theme[.listActiveSelectionForeground] : theme[.foreground])
                .padding(.leading, vscode ? 14 : 10).padding(.trailing, 10).padding(.vertical, vscode ? 7 : 6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background {
                    if vscode { Rectangle().fill(selected ? theme[.listActiveSelectionBackground] : hovering ? theme[.listHoverBackground] : .clear) }
                    else { RoundedRectangle(cornerRadius: 6).fill(selected ? theme[.listActiveSelectionBackground] : .clear) }
                }
                .padding(.horizontal, vscode ? 0 : 8)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// A caption above a group of list rows (“INSTALLED COMMAND-LINE TOOL”).
struct WorkbenchListCaption: View {
    let title: String
    @Environment(\.theme) private var theme
    @State private var themes = ThemeManager.shared
    var body: some View {
        Text(title.uppercased()).font(.ui(10.5, weight: .semibold)).foregroundStyle(theme[.descriptionForeground]).lineLimit(1)
            .padding(.leading, themes.style == .vscode ? 14 : 18).padding(.top, 14).padding(.bottom, 4)
            .accessibilityAddTraits(.isHeader)
    }
}

/// A status glyph that is a codicon in the VS Code style and an SF Symbol in Classic.
struct WorkbenchGlyph: View {
    let codicon: String
    let symbol: String
    var color: TC = .iconForeground
    var size: CGFloat = 16
    @Environment(\.theme) private var theme
    @State private var themes = ThemeManager.shared
    var body: some View {
        Group {
            if themes.style == .vscode { Codicon(codicon, size: size) }
            else { Image(systemName: symbol).font(.system(size: size - 2)) }
        }
        .foregroundStyle(theme[color])
        .frame(width: size, height: size)
    }
}

/// A link-coloured text button with an icon: navigation that is not the main action (“Go to Source Note”).
struct WorkbenchLink: View {
    let title: String
    let codicon: String
    let symbol: String
    var size: CGFloat = 12
    let action: () -> Void
    @Environment(\.theme) private var theme
    @Environment(\.isEnabled) private var enabled
    @State private var themes = ThemeManager.shared
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if themes.style == .vscode { Codicon(codicon, size: size + 1) } else { Image(systemName: symbol).font(.system(size: size - 1)) }
                Text(title).underline(hovering && enabled)
            }
            .font(.ui(size))
            .foregroundStyle(theme[hovering ? .textLinkActiveForeground : .textLinkForeground])
            .opacity(enabled ? 1 : 0.45)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .fixedSize()
    }
}
