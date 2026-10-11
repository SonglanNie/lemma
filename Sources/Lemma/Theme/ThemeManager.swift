import SwiftUI
import AppKit
import LemmaCore

/// A theme the reader can choose: built in, or installed from a VS Code theme file or extension.
struct ThemeEntry: Identifiable, Equatable {
    let id: String
    let label: String
    let kind: ThemeKind
    /// “Lemma”, “VS Code”, “Community” or “Installed”, as the theme picker groups them.
    let group: String
    let file: URL?
    var author: String?
    var license: String?
}

/// An accent laid over the theme's own blue, kept from Lemma's earlier workbench (olive was its colour).
enum AccentOverride: String, CaseIterable, Identifiable {
    case theme, olive, blue, violet, copper
    var id: String { rawValue }
    var label: String { self == .theme ? "Theme" : rawValue.capitalized }

    func color(dark: Bool) -> RGBA? {
        switch (self, dark) {
        case (.theme, _): nil
        case (.olive, false): RGBA(0.42, 0.44, 0.10)
        case (.olive, true): RGBA(0.62, 0.66, 0.26)
        case (.blue, false): RGBA(hex: "#005FB8")
        case (.blue, true): RGBA(hex: "#0078D4")
        case (.violet, false): RGBA(0.43, 0.27, 0.68)
        case (.violet, true): RGBA(0.55, 0.40, 0.86)
        case (.copper, false): RGBA(0.62, 0.32, 0.14)
        case (.copper, true): RGBA(0.80, 0.47, 0.25)
        }
    }

    /// The colours VS Code themes tint with their accent.
    static let accentKeys: [String] = [
        "focusBorder", "button.background", "activityBar.activeBorder", "activityBarBadge.background", "tab.activeBorderTop",
        "panelTitle.activeBorder", "statusBarItem.remoteBackground", "progressBar.background", "textLink.foreground",
        "textLink.activeForeground", "inputOption.activeBorder", "sash.hoverBorder", "badge.background", "notificationLink.foreground",
        "pickerGroup.foreground", "settings.modifiedItemIndicator", "editorLink.activeForeground", "checkbox.selectBackground",
        "list.highlightForeground", "editorSuggestWidget.highlightForeground", "welcomePage.progress.foreground", "peekView.border",
        "notebook.focusedCellBorder", "statusBar.debuggingBackground"
    ]
}

extension Notification.Name {
    /// Posted when the workbench theme changes, for views drawn by AppKit.
    static let lemmaThemeChanged = Notification.Name("lemma.themeChanged")
}

enum ThemePreferences {
    static let colorTheme = "workbench.colorTheme"
    static let autoDetect = "window.autoDetectColorScheme"
    static let preferredDark = "workbench.preferredDarkColorTheme"
    static let preferredLight = "workbench.preferredLightColorTheme"
    static let accent = "workbench.vscodeAccent"
    static let style = "workbench.style"
    static let migrated = "workbench.themeMigrated2"
    /// Lemma's own pair since 3.0: warm graphite and paper with an olive accent. Readers who chose a theme keep it.
    static let defaultDark = "lemma-dark"
    static let defaultLight = "lemma-light"
}

/// The workbench's colour theme: VS Code's built-in themes, Lemma's own, popular community themes and any theme
/// the reader installs. Changing it re-renders the whole window at once (SwiftUI reads `colors` through the
/// environment; AppKit views listen for `lemmaThemeChanged`).
@MainActor @Observable
final class ThemeManager {
    static let shared = ThemeManager()

    private(set) var colors: WorkbenchColors
    private(set) var entries: [ThemeEntry] = []
    /// A theme shown while the picker moves over it; Escape returns to the chosen one.
    private(set) var previewID: String?
    @ObservationIgnored private var defaults = ColorDefaults()
    @ObservationIgnored private var loaded: [String: ColorTheme] = [:]
    @ObservationIgnored private var appearanceObservation: NSObjectProtocol?
    /// Miniature colours of other themes, resolved once each (theme tiles and the tour draw many at every redraw).
    @ObservationIgnored private var previews: [String: WorkbenchColors] = [:]
    /// VS Code's theme as last read from its settings, with the settings file's modification time.
    @ObservationIgnored private var vscodeSettings: (stamp: Double?, label: String?)?
    @ObservationIgnored private var vscodeMatch: (label: String, entries: Int, id: String?)?
    /// Colour themes contributed by VS Code's extensions, with the extensions folder's modification time.
    @ObservationIgnored private var vscodeExtensions: (stamp: Double, themes: [(folder: URL, label: String, path: String)])?
    /// Where installed themes are kept (`Themes` in the support folder); tests point it at a temporary folder.
    @ObservationIgnored var installedDirectory: URL

    var selectedID: String {
        get { UserDefaults.standard.string(forKey: ThemePreferences.colorTheme) ?? ThemePreferences.defaultDark }
        set { UserDefaults.standard.set(newValue, forKey: ThemePreferences.colorTheme); apply() }
    }
    var autoDetect: Bool {
        get { UserDefaults.standard.object(forKey: ThemePreferences.autoDetect) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: ThemePreferences.autoDetect); apply() }
    }
    var preferredDarkID: String {
        get { UserDefaults.standard.string(forKey: ThemePreferences.preferredDark) ?? ThemePreferences.defaultDark }
        set { UserDefaults.standard.set(newValue, forKey: ThemePreferences.preferredDark); apply() }
    }
    var preferredLightID: String {
        get { UserDefaults.standard.string(forKey: ThemePreferences.preferredLight) ?? ThemePreferences.defaultLight }
        set { UserDefaults.standard.set(newValue, forKey: ThemePreferences.preferredLight); apply() }
    }
    var accent: AccentOverride {
        get { AccentOverride(rawValue: UserDefaults.standard.string(forKey: ThemePreferences.accent) ?? "") ?? .theme }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: ThemePreferences.accent); apply() }
    }
    /// VS Code's workbench, or Lemma 1.1's native one (Classic). Switching redraws the window at once.
    var style: WorkbenchStyle = WorkbenchStyle(rawValue: UserDefaults.standard.string(forKey: ThemePreferences.style) ?? "") ?? .vscode {
        didSet { UserDefaults.standard.set(style.rawValue, forKey: ThemePreferences.style); apply() }
    }
    /// Bumped on every change, for views that cache drawings.
    private(set) var revision = 0

    private init() {
        let support = ProcessInfo.processInfo.environment["LEMMA_SUPPORT_DIR"].map { URL(fileURLWithPath: $0, isDirectory: true) }
            ?? WorkspaceRepository.defaultRoot
        installedDirectory = support.appendingPathComponent("Themes", isDirectory: true)
        colors = WorkbenchColors(theme: Self.fallbackTheme(dark: true), defaults: ColorDefaults())
        ThemeSnapshot.shared.colors = colors
        if let url = Codicons.resource("Themes/defaults.json"), let data = try? Data(contentsOf: url), let parsed = try? ColorDefaults(json: data) {
            defaults = parsed
        }
        Self.migrateEarlierChoices()
        reloadEntries()
        apply()
    }

    /// Follows macOS's light and dark appearance while automatic switching is on.
    func startFollowingSystem() {
        guard appearanceObservation == nil else { return }
        appearanceObservation = DistributedNotificationCenter.default().addObserver(forName: Notification.Name("AppleInterfaceThemeChangedNotification"), object: nil, queue: .main) { _ in
            MainActor.assumeIsolated {
                // The preference is written just before the notification; read it a moment later.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    let manager = ThemeManager.shared
                    if manager.style == .classic ? WorkbenchTheme.current == .system : (manager.autoDetect && manager.previewID == nil) { manager.apply() }
                }
            }
        }
        apply()
    }

    /// Lemma 1.1 stored “system”, “light”, “graphite” or “midnight” (still used by the Classic style); the VS Code
    /// style starts from the closest theme once.
    private static func migrateEarlierChoices() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: ThemePreferences.migrated) else { return }
        defaults.set(true, forKey: ThemePreferences.migrated)
        switch defaults.string(forKey: "workbench.theme") {
        case "light": defaults.set(false, forKey: ThemePreferences.autoDetect); defaults.set(ThemePreferences.defaultLight, forKey: ThemePreferences.colorTheme)
        case "graphite": defaults.set(false, forKey: ThemePreferences.autoDetect); defaults.set("lemma-graphite", forKey: ThemePreferences.colorTheme)
        case "midnight": defaults.set(false, forKey: ThemePreferences.autoDetect); defaults.set("lemma-midnight", forKey: ThemePreferences.colorTheme)
        default: break
        }
    }

    /// macOS's own setting, independent of the appearance Lemma gives its windows.
    var systemIsDark: Bool { UserDefaults.standard.string(forKey: "AppleInterfaceStyle")?.lowercased() == "dark" }

    /// The theme in force: the previewed one, the one following macOS, or the chosen one.
    var effectiveID: String {
        if let previewID { return previewID }
        if autoDetect { return systemIsDark ? preferredDarkID : preferredLightID }
        return selectedID
    }

    func entry(_ id: String) -> ThemeEntry? { entries.first { $0.id == id } }

    /// VS Code's registered defaults, for miniatures of themes other than the current one.
    var defaultsForPreview: ColorDefaults { defaults }

    func reloadEntries() {
        previews = [:]
        var list: [ThemeEntry] = []
        if let index = Codicons.resource("Themes/index.json"), let data = try? Data(contentsOf: index),
           let items = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
            let folder = index.deletingLastPathComponent()
            for item in items {
                guard let id = item["id"] as? String, let label = item["label"] as? String, let file = item["file"] as? String,
                      let kind = (item["kind"] as? String).flatMap(ThemeKind.init(rawValue:)) else { continue }
                list.append(ThemeEntry(id: id, label: label, kind: kind, group: item["group"] as? String ?? "VS Code",
                                       file: folder.appendingPathComponent(file), author: item["author"] as? String, license: item["license"] as? String))
            }
        }
        if list.isEmpty {
            list = [ThemeEntry(id: ThemePreferences.defaultDark, label: "Lemma Dark", kind: .dark, group: "Lemma", file: nil),
                    ThemeEntry(id: ThemePreferences.defaultLight, label: "Lemma Light", kind: .light, group: "Lemma", file: nil)]
        }
        for url in (try? FileManager.default.contentsOfDirectory(at: installedDirectory, includingPropertiesForKeys: nil)) ?? [] where url.pathExtension == "json" {
            guard let data = try? Data(contentsOf: url),
                  let theme = try? ThemeFile.theme(data: data, id: "installed-" + url.deletingPathExtension().lastPathComponent,
                                                   fallbackName: url.deletingPathExtension().lastPathComponent, origin: url.path) else { continue }
            list.append(ThemeEntry(id: theme.id, label: theme.name, kind: theme.kind, group: "Installed", file: url, author: theme.author))
            loaded[theme.id] = theme
        }
        entries = list
    }

    /// A theme's colours for miniatures (theme tiles, the tour's previews), resolved once per theme and kept.
    func previewColors(for id: String) -> WorkbenchColors? {
        if let cached = previews[id] { return cached }
        guard let theme = theme(id) else { return nil }
        let colors = WorkbenchColors(theme: theme, defaults: defaults)
        previews[id] = colors
        return colors
    }

    func theme(_ id: String) -> ColorTheme? {
        if let cached = loaded[id] { return cached }
        guard let entry = entry(id) else { return nil }
        guard let file = entry.file, let data = try? Data(contentsOf: file),
              let theme = try? ThemeFile.theme(data: data, id: id, fallbackName: entry.label, kind: entry.kind, origin: entry.group == "Installed" ? file.path : "builtin")
        else { return entry.file == nil ? Self.fallbackTheme(dark: entry.kind.isDark) : nil }
        var named = theme
        named.name = entry.label
        loaded[id] = named
        return named
    }

    /// Resolves the theme in force and tells the window.
    func apply() {
        if style == .classic { applyClassic(); return }
        let id = effectiveID
        let fallbackID = (autoDetect ? systemIsDark : (entry(selectedID)?.kind.isDark ?? true)) ? ThemePreferences.defaultDark : ThemePreferences.defaultLight
        var theme = self.theme(id) ?? self.theme(fallbackID) ?? Self.fallbackTheme(dark: systemIsDark)
        if let accentColor = accent.color(dark: theme.kind.isDark) {
            for key in AccentOverride.accentKeys { theme.colors[key] = key == "statusBar.debuggingBackground" ? accentColor.darken(0.1) : accentColor }
            theme.colors["button.hoverBackground"] = theme.kind.isDark ? accentColor.lighten(0.12) : accentColor.darken(0.12)
            theme.colors["activityBarBadge.background"] = accentColor
            theme.colors["list.activeSelectionBackground"] = accentColor.transparent(theme.kind.isDark ? 0.45 : 0.22)
            theme.colors["quickInputList.focusBackground"] = accentColor.transparent(theme.kind.isDark ? 0.45 : 0.22)
        }
        colors = WorkbenchColors(theme: theme, defaults: defaults)
        ThemeSnapshot.shared.colors = colors
        revision += 1
        // The accessibility high-contrast names only work with bestMatch: NSAppearance(named:) returns nil for them, which
        // left menus, hovers and peeks following macOS instead of a high-contrast theme. Use their base appearances.
        let appearance: NSAppearance? = theme.kind.isDark ? NSAppearance(named: .darkAqua) : NSAppearance(named: .aqua)
        // Native controls, menus and popovers take the theme's kind.
        NSApp?.appearance = appearance
        NotificationCenter.default.post(name: .lemmaThemeChanged, object: nil)
    }

    /// The Classic style: Lemma 1.1's System, Light, Graphite and Midnight with its four accents. Midnight now also
    /// tints the editor, so it is distinct from Graphite (in 1.1 only the bars changed, and not until a restart).
    private func applyClassic() {
        let classic = WorkbenchTheme.current
        let dark = classic.scheme.map { $0 == .dark } ?? systemIsDark
        let theme = Self.classicTheme(classic, accent: WorkbenchAccent.current, dark: dark)
        colors = WorkbenchColors(theme: theme, defaults: defaults)
        ThemeSnapshot.shared.colors = colors
        revision += 1
        // “System” is resolved to macOS's current appearance and applied again when it changes: leaving it to SwiftUI after
        // a VS Code theme had set the window light could keep the text dark on dark bars.
        NSApp?.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        NotificationCenter.default.post(name: .lemmaThemeChanged, object: nil)
    }

    static func classicTheme(_ classic: WorkbenchTheme, accent: WorkbenchAccent, dark: Bool) -> ColorTheme {
        let appearance = NSAppearance(named: dark ? .darkAqua : .aqua)!
        func system(_ color: NSColor) -> RGBA {
            var value = RGBA(0, 0, 0)
            appearance.performAsCurrentDrawingAppearance { value = RGBA(color) }
            return value
        }
        let midnight = classic == .midnight
        let chrome = midnight ? RGBA(0.07, 0.09, 0.14) : dark ? RGBA(0.125, 0.125, 0.125) : RGBA(0.885, 0.885, 0.885)
        let sidebar = midnight ? RGBA(0.10, 0.12, 0.19) : dark ? RGBA(0.165, 0.165, 0.165) : RGBA(0.955, 0.955, 0.955)
        let editor = midnight ? RGBA(0.085, 0.105, 0.165) : system(.windowBackgroundColor)
        let control = midnight ? RGBA(0.11, 0.135, 0.205) : system(.controlBackgroundColor)
        let label = system(.labelColor), secondary = system(.secondaryLabelColor), separator = system(.separatorColor)
        let tint = RGBA(accent.color(dark: dark))
        let colors: [String: RGBA] = [
            "foreground": label, "descriptionForeground": secondary, "icon.foreground": secondary, "focusBorder": tint,
            "widget.border": separator, "editor.background": editor, "editor.foreground": label,
            "activityBar.background": chrome, "activityBar.foreground": tint, "activityBar.inactiveForeground": secondary, "activityBar.activeBorder": tint,
            "sideBar.background": sidebar, "sideBar.foreground": label, "sideBar.border": separator,
            "sideBarSectionHeader.background": sidebar, "sideBarSectionHeader.foreground": label, "sideBarSectionHeader.border": separator,
            "titleBar.activeBackground": chrome, "statusBar.background": chrome, "statusBar.foreground": secondary, "statusBar.border": separator,
            "statusBarItem.remoteBackground": tint, "statusBarItem.remoteForeground": RGBA(1, 1, 1), "statusBar.debuggingBackground": tint.darken(0.1),
            "editorGroupHeader.tabsBackground": chrome, "tab.activeBackground": editor, "tab.inactiveBackground": chrome, "tab.activeBorderTop": tint,
            "tab.border": separator, "editorGroup.border": separator, "breadcrumb.background": editor, "panel.background": control, "panel.border": separator,
            "panelTitle.activeBorder": tint, "list.activeSelectionBackground": tint.transparent(0.16), "list.activeSelectionForeground": label,
            "list.inactiveSelectionBackground": tint.transparent(0.1), "list.hoverBackground": label.transparent(0.06), "list.highlightForeground": tint,
            "input.background": control, "input.border": separator, "dropdown.background": control, "dropdown.border": separator,
            "button.background": tint, "button.foreground": RGBA(1, 1, 1), "button.secondaryBackground": label.transparent(0.08),
            "button.secondaryForeground": label, "badge.background": tint, "badge.foreground": RGBA(1, 1, 1), "textLink.foreground": tint,
            "toolbar.hoverBackground": label.transparent(0.08), "editorWidget.background": control, "editorHoverWidget.background": control,
            "quickInput.background": editor, "quickInputList.focusBackground": RGBA(accent.selectionColor), "quickInputList.focusForeground": RGBA(1, 1, 1),
            "minimap.background": editor, "notifications.background": control, "debugToolBar.background": control
        ]
        return ColorTheme(id: "classic-\(classic.rawValue)", name: "Classic \(classic.label)", kind: dark ? .dark : .light, colors: colors, origin: "classic")
    }

    /// Chooses a theme. With automatic switching on, it becomes the preferred theme of its kind (as VS Code does).
    func choose(_ id: String) {
        previewID = nil
        guard let entry = entry(id) else { return }
        if autoDetect {
            if entry.kind.isDark == systemIsDark {
                if entry.kind.isDark { preferredDarkID = id } else { preferredLightID = id }
            } else {
                // A light theme chosen while macOS is dark: follow the reader rather than macOS.
                UserDefaults.standard.set(false, forKey: ThemePreferences.autoDetect)
            }
        }
        selectedID = id
    }

    func preview(_ id: String?) {
        guard previewID != id else { return }
        previewID = id
        apply()
    }

    // MARK: The theme of the reader's VS Code

    /// The colour theme chosen in VS Code's user settings, if VS Code is installed. Read locally, and again only when
    /// the settings file changes: the palette, the command list, the Welcome page and the tour ask for it often.
    var vscodeThemeLabel: String? {
        let settings = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/Code/User/settings.json")
        let stamp = Self.modificationTime(settings.path)
        if let cached = vscodeSettings, cached.stamp == stamp { return cached.label }
        var label: String?
        if stamp != nil, let data = try? Data(contentsOf: settings), let object = try? ThemeFile.object(data) {
            label = object["workbench.colorTheme"] as? String
        }
        vscodeSettings = (stamp, label)
        return label
    }

    /// The bundled or installed theme with the same name as VS Code's, if any.
    var vscodeThemeID: String? {
        guard let label = vscodeThemeLabel else { return nil }
        if let match = vscodeMatch, match.label == label, match.entries == entries.count { return match.id }
        func normal(_ text: String) -> String {
            var value = text.lowercased().replacingOccurrences(of: "’", with: "'")
            for prefix in ["default ", "visual studio "] where value.hasPrefix(prefix) { value.removeFirst(prefix.count) }
            return value.replacingOccurrences(of: " ", with: "").replacingOccurrences(of: "-", with: "")
        }
        let wanted = normal(label)
        let id = entries.first { normal($0.label) == wanted }?.id
        vscodeMatch = (label, entries.count, id)
        return id
    }

    /// Uses VS Code's own theme: the bundled copy, or the theme file of the extension installed in VS Code.
    @discardableResult
    func useVSCodeTheme() throws -> ThemeEntry? {
        if let id = vscodeThemeID, let entry = entry(id) { choose(id); return entry }
        guard let label = vscodeThemeLabel else { return nil }
        for theme in vscodeExtensionThemes() where theme.label.caseInsensitiveCompare(label) == .orderedSame {
            let installed = try install(from: theme.folder.appendingPathComponent(theme.path))
            if let first = installed.first { choose(first.id); return first }
        }
        return nil
    }

    /// The colour themes VS Code's extensions contribute, read again only when the extensions folder changes.
    private func vscodeExtensionThemes() -> [(folder: URL, label: String, path: String)] {
        let extensions = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".vscode/extensions")
        let stamp = Self.modificationTime(extensions.path)
        if let cached = vscodeExtensions, let stamp, cached.stamp == stamp { return cached.themes }
        var themes: [(folder: URL, label: String, path: String)] = []
        for folder in (try? FileManager.default.contentsOfDirectory(at: extensions, includingPropertiesForKeys: nil)) ?? [] {
            guard let package = try? Data(contentsOf: folder.appendingPathComponent("package.json")),
                  let contributed = try? ThemeFile.contributedThemes(packageJSON: package) else { continue }
            themes += contributed.map { (folder, $0.label, $0.path) }
        }
        if let stamp { vscodeExtensions = (stamp, themes) }
        return themes
    }

    /// A file's modification time, or nil when it is not there (one `stat`, rather than reading it).
    private static func modificationTime(_ path: String) -> Double? {
        var info = stat()
        guard stat(path, &info) == 0 else { return nil }
        return Double(info.st_mtimespec.tv_sec) + Double(info.st_mtimespec.tv_nsec) / 1_000_000_000
    }

    /// Installs a VS Code colour theme: a theme `.json`, or a `.vsix` extension whose themes are all added.
    @discardableResult
    func install(from url: URL) throws -> [ThemeEntry] {
        try FileManager.default.createDirectory(at: installedDirectory, withIntermediateDirectories: true)
        var files: [(name: String, data: Data, kind: ThemeKind?)] = []
        switch url.pathExtension.lowercased() {
        case "vsix", "zip":
            let folder = FileManager.default.temporaryDirectory.appendingPathComponent("lemma-theme-\(UUID().uuidString)")
            defer { try? FileManager.default.removeItem(at: folder) }
            try Self.unzip(url, to: folder)
            let extensionFolder = folder.appendingPathComponent("extension")
            let package = try Data(contentsOf: extensionFolder.appendingPathComponent("package.json"))
            for theme in try ThemeFile.contributedThemes(packageJSON: package) {
                let themeURL = extensionFolder.appendingPathComponent(theme.path).standardizedFileURL
                guard themeURL.path.hasPrefix(extensionFolder.standardizedFileURL.path) else { continue }
                // Includes are resolved now, since the installed copy stands alone.
                let data = try Data(contentsOf: themeURL)
                let parsed = try ThemeFile.theme(data: data, id: "x", fallbackName: theme.label, kind: theme.kind, origin: themeURL.path) { include in
                    try Data(contentsOf: themeURL.deletingLastPathComponent().appendingPathComponent(include))
                }
                files.append((theme.label, try Self.serialize(parsed), parsed.kind))
            }
        default:
            let data = try Data(contentsOf: url)
            let parsed = try ThemeFile.theme(data: data, id: "x", fallbackName: url.deletingPathExtension().lastPathComponent, origin: url.path) { include in
                try Data(contentsOf: url.deletingLastPathComponent().appendingPathComponent(include))
            }
            files.append((parsed.name, try Self.serialize(parsed), parsed.kind))
        }
        guard !files.isEmpty else { throw ThemeFileError.unreadable("This extension contributes no colour theme.") }
        var installed: [String] = []
        for file in files {
            let slug = file.name.lowercased().map { $0.isLetter || $0.isNumber ? $0 : "-" }.reduce("") { $0 + String($1) }
            let target = installedDirectory.appendingPathComponent("\(slug).json")
            try file.data.write(to: target, options: .atomic)
            installed.append("installed-" + slug)
            loaded.removeValue(forKey: "installed-" + slug)
        }
        reloadEntries()
        return entries.filter { installed.contains($0.id) }
    }

    func uninstall(_ id: String) {
        guard let entry = entry(id), entry.group == "Installed", let file = entry.file else { return }
        try? FileManager.default.removeItem(at: file)
        loaded.removeValue(forKey: id)
        if selectedID == id { selectedID = ThemePreferences.defaultDark }
        reloadEntries(); apply()
    }

    private static func serialize(_ theme: ColorTheme) throws -> Data {
        var colors: [String: String] = [:]
        for (key, value) in theme.colors { colors[key] = value.hex }
        let tokenColors: [[String: Any]] = theme.tokenRules.map { rule in
            var settings: [String: String] = [:]
            if let foreground = rule.foreground { settings["foreground"] = foreground.hex }
            if let background = rule.background { settings["background"] = background.hex }
            if let style = rule.fontStyle { settings["fontStyle"] = style }
            var entry: [String: Any] = ["settings": settings]
            if !rule.scopes.isEmpty { entry["scope"] = rule.scopes }
            return entry
        }
        let type = switch theme.kind { case .dark: "dark"; case .light: "light"; case .hcDark: "hc"; case .hcLight: "hcLight" }
        var object: [String: Any] = ["name": theme.name, "type": type, "colors": colors, "tokenColors": tokenColors]
        if let author = theme.author { object["author"] = author }
        return try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
    }

    private static func unzip(_ archive: URL, to folder: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = ["-x", "-k", archive.path, folder.path]
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw ThemeFileError.unreadable("Could not open this extension package.") }
    }

    /// Dark Modern and Light Modern's main colours, used only when the bundled themes cannot be read.
    static func fallbackTheme(dark: Bool) -> ColorTheme {
        let pairs: [String: String] = dark ? [
            "editor.background": "#1F1F1F", "editor.foreground": "#CCCCCC", "foreground": "#CCCCCC", "focusBorder": "#0078D4",
            "activityBar.background": "#181818", "activityBar.foreground": "#D7D7D7", "activityBar.inactiveForeground": "#868686",
            "activityBar.activeBorder": "#0078D4", "activityBar.border": "#2B2B2B", "sideBar.background": "#181818", "sideBar.border": "#2B2B2B",
            "sideBar.foreground": "#CCCCCC", "sideBarSectionHeader.background": "#181818", "sideBarSectionHeader.border": "#2B2B2B",
            "titleBar.activeBackground": "#181818", "titleBar.activeForeground": "#CCCCCC", "titleBar.border": "#2B2B2B",
            "statusBar.background": "#181818", "statusBar.foreground": "#CCCCCC", "statusBar.border": "#2B2B2B",
            "statusBarItem.remoteBackground": "#0078D4", "statusBarItem.remoteForeground": "#FFFFFF",
            "tab.activeBackground": "#1F1F1F", "tab.inactiveBackground": "#181818", "tab.activeBorderTop": "#0078D4", "tab.border": "#2B2B2B",
            "editorGroupHeader.tabsBackground": "#181818", "editorGroupHeader.tabsBorder": "#2B2B2B", "panel.background": "#181818",
            "panel.border": "#2B2B2B", "panelTitle.activeBorder": "#0078D4", "input.background": "#313131", "input.border": "#3C3C3C",
            "button.background": "#0078D4", "button.foreground": "#FFFFFF", "list.activeSelectionBackground": "#04395E",
            "list.hoverBackground": "#2A2D2E", "badge.background": "#616161", "badge.foreground": "#F8F8F8", "descriptionForeground": "#9D9D9D",
            "widget.border": "#313131", "editorWidget.background": "#202020", "quickInput.background": "#222222", "textLink.foreground": "#4daafc"
        ] : [
            "editor.background": "#FFFFFF", "editor.foreground": "#3B3B3B", "foreground": "#3B3B3B", "focusBorder": "#005FB8",
            "activityBar.background": "#F8F8F8", "activityBar.foreground": "#1F1F1F", "activityBar.inactiveForeground": "#616161",
            "activityBar.activeBorder": "#005FB8", "activityBar.border": "#E5E5E5", "sideBar.background": "#F8F8F8", "sideBar.border": "#E5E5E5",
            "sideBar.foreground": "#3B3B3B", "sideBarSectionHeader.background": "#F8F8F8", "sideBarSectionHeader.border": "#E5E5E5",
            "titleBar.activeBackground": "#F8F8F8", "titleBar.activeForeground": "#1E1E1E", "titleBar.border": "#E5E5E5",
            "statusBar.background": "#F8F8F8", "statusBar.foreground": "#3B3B3B", "statusBar.border": "#E5E5E5",
            "statusBarItem.remoteBackground": "#005FB8", "statusBarItem.remoteForeground": "#FFFFFF",
            "tab.activeBackground": "#FFFFFF", "tab.inactiveBackground": "#F8F8F8", "tab.activeBorderTop": "#005FB8", "tab.border": "#E5E5E5",
            "editorGroupHeader.tabsBackground": "#F8F8F8", "editorGroupHeader.tabsBorder": "#E5E5E5", "panel.background": "#F8F8F8",
            "panel.border": "#E5E5E5", "panelTitle.activeBorder": "#005FB8", "input.background": "#FFFFFF", "input.border": "#CECECE",
            "button.background": "#005FB8", "button.foreground": "#FFFFFF", "list.activeSelectionBackground": "#E8E8E8",
            "list.hoverBackground": "#F2F2F2", "badge.background": "#CCCCCC", "badge.foreground": "#3B3B3B", "descriptionForeground": "#3B3B3B",
            "widget.border": "#E5E5E5", "editorWidget.background": "#F8F8F8", "quickInput.background": "#F8F8F8", "textLink.foreground": "#005FB8"
        ]
        var colors: [String: RGBA] = [:]
        for (key, value) in pairs { colors[key] = RGBA(hex: value) }
        return ColorTheme(id: dark ? ThemePreferences.defaultDark : ThemePreferences.defaultLight, name: dark ? "Dark Modern" : "Light Modern",
                          kind: dark ? .dark : .light, colors: colors)
    }
}

/// The workbench's look: VS Code's, or Lemma 1.1's native macOS look.
enum WorkbenchStyle: String, CaseIterable, Identifiable {
    case vscode, classic
    var id: String { rawValue }
    var label: String { self == .vscode ? "VS Code style" : "Classic" }
}

extension WorkbenchColors {
    /// The canvas around PDF pages: a little darker than the editor so white paper stands out in light themes.
    var pageCanvas: RGBA {
        let background = rgba(.editorBackground)
        if theme.origin == "classic" { return background }
        // Light themes: 11 % towards black, enough for the white paper's edge to read on a paper-coloured editor.
        return isDark ? background.darken(0.22) : background.mixed(with: RGBA(0, 0, 0), 0.11)
    }
    /// The accent the theme uses for focus and primary actions, readable on the editor. A theme whose focus border is
    /// meant to be nearly invisible (SynthWave '84's is #1F212B on #262335) takes its primary button colour, made
    /// readable, instead: tinted with it, borderless menus, selected icons and accent lines had vanished. Focus rings
    /// keep `focusBorder` itself, and marks on the page take it from the theme snapshot as before.
    var accent: Color { focusIsReadable ? self[.focusBorder] : accentRGBA.color }
    var accentRGBA: RGBA {
        focusIsReadable ? rgba(.focusBorder) : rgba(.buttonBackground).readable(on: rgba(.editorBackground), ratio: 3)
    }
    private var focusIsReadable: Bool { rgba(.focusBorder).contrast(with: rgba(.editorBackground)) >= 3 }
}
