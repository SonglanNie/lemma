import SwiftUI
import AppKit

enum WorkbenchTheme: String, CaseIterable, Identifiable {
    case system, light, graphite, midnight
    var id: String { rawValue }
    var label: String { switch self { case .system: "System"; case .light: "Light"; case .graphite: "Graphite"; case .midnight: "Midnight" } }
    var scheme: ColorScheme? { switch self { case .system: nil; case .light: .light; case .graphite, .midnight: .dark } }
    var appearance: NSAppearance? { switch self { case .system: nil; case .light: NSAppearance(named: .aqua); case .graphite, .midnight: NSAppearance(named: .darkAqua) } }
    static var current: Self { Self(rawValue: UserDefaults.standard.string(forKey: "workbench.theme") ?? "") ?? .system }
}

enum WorkbenchAccent: String, CaseIterable, Identifiable {
    case olive, blue, violet, copper
    var id: String { rawValue }
    var label: String { rawValue.capitalized }
    static var current: Self { Self(rawValue: UserDefaults.standard.string(forKey: "workbench.accent") ?? "") ?? .olive }

    /// Dark text against light surfaces and light text against dark surfaces, with one meaning in both.
    func color(dark: Bool) -> NSColor {
        let rgb: (Double, Double, Double) = switch (self, dark) {
        case (.olive, false): (0.324, 0.326, 0.082)
        case (.olive, true): (0.744, 0.754, 0.489)
        case (.blue, false): (0.08, 0.35, 0.62)
        case (.blue, true): (0.49, 0.73, 0.96)
        case (.violet, false): (0.39, 0.23, 0.63)
        case (.violet, true): (0.75, 0.62, 0.97)
        case (.copper, false): (0.52, 0.27, 0.13)
        case (.copper, true): (0.92, 0.66, 0.48)
        }
        return NSColor(srgbRed: rgb.0, green: rgb.1, blue: rgb.2, alpha: 1)
    }

    var selectionColor: NSColor {
        switch self {
        case .olive: NSColor(srgbRed: 0.36, green: 0.37, blue: 0.10, alpha: 1)
        case .blue: NSColor(srgbRed: 0.14, green: 0.36, blue: 0.59, alpha: 1)
        case .violet: NSColor(srgbRed: 0.38, green: 0.27, blue: 0.55, alpha: 1)
        case .copper: NSColor(srgbRed: 0.50, green: 0.30, blue: 0.18, alpha: 1)
        }
    }
}

enum WorkbenchDensity: String, CaseIterable, Identifiable {
    case compact, comfortable
    var id: String { rawValue }
    var label: String { rawValue.capitalized }
    var tabHeight: CGFloat { self == .compact ? 32 : 38 }
    var sideTabHeight: CGFloat { self == .compact ? 28 : 34 }
    var barHeight: CGFloat { self == .compact ? 28 : 34 }
    var iconHeight: CGFloat { self == .compact ? 32 : 38 }
}

private struct DensityKey: EnvironmentKey { static let defaultValue = WorkbenchDensity.compact }
extension EnvironmentValues {
    var workbenchDensity: WorkbenchDensity { get { self[DensityKey.self] } set { self[DensityKey.self] = newValue } }
}

/// The same customization surface is available from Settings and the title bar's layout control.
struct WorkbenchAppearanceView: View {
    @Bindable var store: StudyStore
    @AppStorage("workbench.theme") private var theme = WorkbenchTheme.system.rawValue
    @AppStorage("workbench.accent") private var accent = WorkbenchAccent.olive.rawValue
    @AppStorage("workbench.density") private var density = WorkbenchDensity.compact.rawValue

    var body: some View {
        Form {
            Section {
                Picker("Interface style", selection: Binding(get: { ThemeManager.shared.style }, set: { ThemeManager.shared.style = $0 })) {
                    ForEach(WorkbenchStyle.allCases) { style in Text(style.label).tag(style) }
                }
                Text("The VS Code style lays Lemma out as VS Code lays out code: a title bar with the command center, an activity bar, tabs, a status bar and VS Code colour themes. Classic is a native macOS window with a toolbar and SF Symbols. Both have every feature.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            } header: { Text("Interface") }
            Section {
                HStack(spacing: 10) {
                    ForEach(WorkbenchTheme.allCases) { option in
                        Button { theme = option.rawValue } label: {
                            VStack(spacing: 7) {
                                ThemeSwatch(theme: option, accent: WorkbenchAccent(rawValue: accent) ?? .olive)
                                    .frame(height: 66)
                                    .overlay(RoundedRectangle(cornerRadius: 5).stroke(theme == option.rawValue ? Color.lemmaOlive : Color.secondary.opacity(0.3), lineWidth: theme == option.rawValue ? 2 : 0.5))
                                Text(option.label).font(.caption.weight(theme == option.rawValue ? .semibold : .regular))
                            }.contentShape(Rectangle())
                        }.buttonStyle(.plain).accessibilityLabel("\(option.label) workbench theme")
                            .accessibilityAddTraits(theme == option.rawValue ? .isSelected : [])
                    }
                }.padding(.vertical, 4)
                HStack(spacing: 14) {
                    Text("Accent").font(.callout)
                    Spacer()
                    ForEach(WorkbenchAccent.allCases) { option in
                        Button { accent = option.rawValue } label: {
                            Circle().fill(Color(nsColor: option.color(dark: false))).frame(width: 22, height: 22)
                                .overlay { if option.rawValue == accent { Image(systemName: "checkmark").font(.system(size: 10, weight: .bold)).foregroundStyle(.white) } }
                        }.buttonStyle(.plain).help(option.label).accessibilityLabel("\(option.label) accent")
                            .accessibilityAddTraits(option.rawValue == accent ? .isSelected : [])
                    }
                }
                Picker("Density", selection: $density) { ForEach(WorkbenchDensity.allCases) { Text($0.label).tag($0.rawValue) } }
                Text("The page has its own Paper, Sepia and Night themes in Reading settings.")
                    .font(.caption).foregroundStyle(.secondary)
            } header: { Text("Appearance") }

            Section {
                HStack(spacing: 8) {
                    ForEach(LayoutPreset.allCases) { preset in
                        Button { store.applyLayout(preset) } label: { Label(preset.label, systemImage: preset.symbol) }
                    }
                }.controlSize(.small)
                Picker("Explorer position", selection: $store.workbenchLayout.sidebarPosition) {
                    ForEach(SidebarPosition.allCases) { Text($0.label).tag($0) }
                }
                Toggle("Activity bar", isOn: $store.workbenchLayout.activityBar)
                Toggle("Explorer", isOn: $store.showLibrary)
                Toggle("Notebook inspector", isOn: $store.showStudy)
                Toggle("Bottom panel", isOn: $store.showPanel)
                Text("Drag the dividers to set your widths. Books, side editors, views and pane sizes are remembered between sessions.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Button("Reset Pane Sizes") {
                    store.workbenchLayout.sidebarWidth = 264; store.workbenchLayout.inspectorWidth = 370
                }.buttonStyle(.borderless)
            } header: { Text("Layout") }
        }
        .formStyle(.grouped)
        .onChange(of: theme) { _, _ in ThemeManager.shared.apply(); store.applyAppearance() }
        .onChange(of: accent) { _, _ in ThemeManager.shared.apply(); store.applyAppearance() }
    }
}

private struct ThemeSwatch: View {
    let theme: WorkbenchTheme
    let accent: WorkbenchAccent
    @Environment(\.colorScheme) private var systemScheme
    var body: some View {
        let dark = theme.scheme == .dark || (theme == .system && systemScheme == .dark)
        let chrome: Color = theme == .midnight ? Color(red: 0.07, green: 0.09, blue: 0.14) : dark ? Color(white: 0.13) : Color(white: 0.88)
        let surface: Color = theme == .midnight ? Color(red: 0.10, green: 0.12, blue: 0.19) : dark ? Color(white: 0.18) : Color(white: 0.95)
        VStack(spacing: 1) {
            HStack(spacing: 2) { Circle().fill(Color.secondary).frame(width: 3); Circle().fill(Color.secondary).frame(width: 3); Spacer() }.frame(height: 9).padding(.horizontal, 4)
            HStack(spacing: 1) {
                VStack(spacing: 4) {
                    RoundedRectangle(cornerRadius: 1).fill(Color(nsColor: accent.color(dark: dark))).frame(width: 4, height: 5)
                    Rectangle().fill(Color.secondary.opacity(0.6)).frame(width: 4, height: 1)
                    Spacer()
                }.padding(.top, 4).frame(width: 10)
                surface.frame(width: 22)
                VStack(spacing: 4) {
                    Color(nsColor: accent.color(dark: dark)).frame(height: 2)
                    VStack(alignment: .leading, spacing: 4) {
                        Rectangle().fill(Color.gray.opacity(0.8)).frame(width: 22, height: 2)
                        ForEach(0..<3) { _ in Rectangle().fill(Color.gray.opacity(0.5)).frame(height: 1) }
                        Spacer()
                    }.padding(7).frame(maxWidth: .infinity).background(Color.white)
                }
                surface.frame(width: 16)
            }
        }.background(chrome).clipShape(RoundedRectangle(cornerRadius: 5)).accessibilityHidden(true)
    }
}
