import SwiftUI
import AppKit
import LemmaCore

/// One setting, as VS Code's settings editor lists it: “Workbench › Appearance: Color Theme”, a description and a control.
struct SettingItem: Identifiable {
    enum Control {
        case toggle
        case choice([(value: String, label: String)])
        case number(ClosedRange<Double>, step: Double)
        case text(placeholder: String)
        case custom(String)
    }
    let id: String
    let category: String
    let section: String
    let title: String
    let description: String
    let control: Control
    let defaultValue: String
    let get: @MainActor () -> String
    let set: @MainActor (String) -> Void
    var commonlyUsed = false

    @MainActor var isModified: Bool { self.get() != defaultValue }
    var breadcrumb: String { section.isEmpty ? category : "\(category) › \(section)" }

    func matches(_ query: String) -> Bool {
        let query = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !query.isEmpty else { return true }
        let text = "\(category) \(section) \(title) \(description) \(id)".lowercased()
        return query.split(separator: " ").allSatisfy { text.contains($0) }
    }
}

@MainActor
enum SettingsRegistry {
    static func bool(_ key: String, _ fallback: Bool) -> (get: @MainActor () -> String, set: @MainActor (String) -> Void) {
        ({ String(UserDefaults.standard.object(forKey: key) as? Bool ?? fallback) }, { UserDefaults.standard.set($0 == "true", forKey: key) })
    }
    static func string(_ key: String, _ fallback: String) -> (get: @MainActor () -> String, set: @MainActor (String) -> Void) {
        ({ UserDefaults.standard.string(forKey: key) ?? fallback }, { UserDefaults.standard.set($0, forKey: key) })
    }

    static func items(store: StudyStore) -> [SettingItem] {
        let themes = ThemeManager.shared
        let themeChoices = themes.entries.map { ($0.id, $0.label) }
        let darkChoices = themes.entries.filter { $0.kind.isDark }.map { ($0.id, $0.label) }
        let lightChoices = themes.entries.filter { !$0.kind.isDark }.map { ($0.id, $0.label) }
        var items: [SettingItem] = []
        func add(_ id: String, _ category: String, _ section: String, _ title: String, _ description: String, _ control: SettingItem.Control,
                 default value: String, common: Bool = false, _ accessors: (get: @MainActor () -> String, set: @MainActor (String) -> Void)) {
            var item = SettingItem(id: id, category: category, section: section, title: title, description: description, control: control,
                                   defaultValue: value, get: accessors.get, set: accessors.set)
            item.commonlyUsed = common
            items.append(item)
        }
        // Updates: GitHub is contacted only when the reader asks, or once a day if this is on.
        let updates = Updates.shared
        add("update.automaticChecks", "Workbench", "Updates", "Check for Updates Automatically",
            "Once a day, ask GitHub whether a newer Lemma has been released (the request carries only Lemma's and macOS's versions). Lemma › Check for Updates… checks at once and offers to install the new version and relaunch.",
            .toggle, default: "false", ({ String(updates.automaticallyChecks) }, { updates.automaticallyChecks = $0 == "true" }))
        if updates.isAvailable {
            add("update.automaticDownloads", "Workbench", "Updates", "Download and Install Updates Automatically",
                "Download a new version in the background and install it when Lemma quits, without asking (this also turns on the daily check). Off, Lemma asks before downloading.",
                .toggle, default: "false", ({ String(updates.automaticallyDownloads) }, { updates.automaticallyDownloads = $0 == "true" }))
        }
        // Workbench › Appearance
        add(ThemePreferences.style, "Workbench", "Appearance", "Interface Style",
            "The VS Code style lays Lemma out as VS Code lays out code: a title bar with the command center, an activity bar, tabs, a status bar, codicons and VS Code colour themes. Classic is a native macOS window (toolbar, SF Symbols, System, Light, Graphite and Midnight). Every feature is available in both.",
            .choice(WorkbenchStyle.allCases.map { ($0.rawValue, $0.label) }), default: WorkbenchStyle.vscode.rawValue, common: true,
            ({ themes.style.rawValue }, { themes.style = WorkbenchStyle(rawValue: $0) ?? .vscode }))
        add("workbench.colorTheme", "Workbench", "Appearance", "Color Theme",
            "The colour theme of the workbench. Any VS Code colour theme works: install one from a .json file or a .vsix extension (drop it on the window).",
            .choice(themeChoices), default: ThemePreferences.defaultDark, common: true,
            ({ themes.selectedID }, { themes.choose($0) }))
        add("window.autoDetectColorScheme", "Workbench", "Appearance", "Auto Detect Color Scheme",
            "Follow macOS: use the preferred dark theme in Dark Mode and the preferred light theme in Light Mode.",
            .toggle, default: "true", common: true, ({ String(themes.autoDetect) }, { themes.autoDetect = $0 == "true" }))
        add("workbench.preferredDarkColorTheme", "Workbench", "Appearance", "Preferred Dark Color Theme",
            "The theme used in Dark Mode when Auto Detect Color Scheme is on.", .choice(darkChoices), default: ThemePreferences.defaultDark,
            ({ themes.preferredDarkID }, { themes.preferredDarkID = $0 }))
        add("workbench.preferredLightColorTheme", "Workbench", "Appearance", "Preferred Light Color Theme",
            "The theme used in Light Mode when Auto Detect Color Scheme is on.", .choice(lightChoices), default: ThemePreferences.defaultLight,
            ({ themes.preferredLightID }, { themes.preferredLightID = $0 }))
        add("workbench.accent", "Workbench", "Appearance", "Accent",
            "Lay an accent over the theme's own: focus borders, primary buttons, the active tab's edge, badges and links. Lemma Dark and Lemma Light already use Lemma's olive.",
            .choice(AccentOverride.allCases.map { ($0.rawValue, $0.label) }), default: AccentOverride.theme.rawValue,
            ({ themes.accent.rawValue }, { themes.accent = AccentOverride(rawValue: $0) ?? .theme }))
        add("workbench.colorCustomizations", "Workbench", "Appearance", "Installed Color Themes",
            "Themes installed from files are kept in Lemma's support folder. Remove one from the theme picker's context menu, or here.",
            .custom("installedThemes"), default: "", ({ "" }, { _ in }))
        // Workbench › Layout
        add("workbench.activityBar.visible", "Workbench", "Layout", "Activity Bar Visible", "Show the activity bar at the window's edge.",
            .toggle, default: "true", ({ String(store.workbenchLayout.activityBar) }, { store.workbenchLayout.activityBar = $0 == "true"; store.saveWorkbench() }))
        add("workbench.sideBar.location", "Workbench", "Layout", "Side Bar Location", "Where the primary side bar and the activity bar sit.",
            .choice([("left", "Left"), ("right", "Right")]), default: "left",
            ({ store.workbenchLayout.sidebarPosition.rawValue }, { store.workbenchLayout.sidebarPosition = SidebarPosition(rawValue: $0) ?? .left; store.saveWorkbench() }))
        add("workbench.startupEditor", "Workbench", "Layout", "Startup Editor", "Show the Welcome page when Lemma starts without a book.",
            .choice([("welcomePage", "Welcome Page"), ("none", "None")]), default: "welcomePage", string("workbench.startupEditor", "welcomePage"))
        add("workbench.notifications.toasts", "Workbench", "Notifications", "Show Toasts",
            "Show notifications at the bottom right as they arrive. They stay in the notification center (the bell) either way.",
            .toggle, default: "true", bool("workbench.notifications.toasts", true))
        // Editor (the page)
        add("editor.pageTheme", "Editor", "Page", "Page Theme",
            "How the PDF page is drawn: the original paper, a warmer sepia, or a night page that keeps hues. Captures, questions and exports always use the original page.",
            .choice(PageTheme.allCases.map { ($0.rawValue, $0.label) }), default: PageTheme.paper.rawValue, common: true,
            ({ store.pageTheme.rawValue }, { store.pageTheme = PageTheme(rawValue: $0) ?? .paper }))
        add("editor.lineNumbers", "Editor", "Page", "Line Numbers",
            "Number the page's lines beside it. Click a number to select its line; type “64:12” in Go to. Bars mark your highlights, notes, “?” marks and drawings.",
            .toggle, default: "true", common: true,
            ({ String(store.reader.showLineNumbers) }, { store.reader.showLineNumbers = $0 == "true" }))
        add("editor.minimap.enabled", "Editor", "Minimap", "Enabled",
            "Show page miniatures beside the page, with the visible region as a slider and your marks drawn over them.",
            .toggle, default: "true", common: true, ({ String(store.showMinimap) }, { store.showMinimap = $0 == "true" }))
        add("editor.minimap.showSlider", "Editor", "Minimap", "Show Slider",
            "When the slider marking the visible region is shown: only while the pointer is over the minimap, as in VS Code, or always.",
            .choice([("mouseover", "Mouse Over"), ("always", "Always")]), default: "mouseover",
            ({ store.minimapSliderAlways ? "always" : "mouseover" }, { store.minimapSliderAlways = $0 == "always" }))
        add(LemmaPreferences.referenceLinks, "Editor", "References", "Link References",
            "Underline references such as “(2.3)”, “Figure 2.1”, “Ex. 2.8” or “Rudin (1976)”. Click one to peek at it; Go to moves there and ⌥⌘← comes back.",
            .toggle, default: "true", ({ String(LemmaPreferences.flag(LemmaPreferences.referenceLinks)) }, {
                UserDefaults.standard.set($0 == "true", forKey: LemmaPreferences.referenceLinks); store.reader.showReferenceLinks = $0 == "true"
            }))
        add(LemmaPreferences.referenceCounts, "Editor", "References", "Reference Counts",
            "Show how often the text refers to each equation and figure, beside its label, as an editor's CodeLens. Click a count to list the places.",
            .toggle, default: "true", ({ String(LemmaPreferences.flag(LemmaPreferences.referenceCounts)) }, {
                UserDefaults.standard.set($0 == "true", forKey: LemmaPreferences.referenceCounts); store.reader.showReferenceCounts = $0 == "true"
            }))
        add(LemmaPreferences.hoverPreviews, "Editor", "Hover", "Enabled",
            "Preview an underlined reference or a symbol's meaning when the pointer rests on it.", .toggle, default: "true", common: true,
            bool(LemmaPreferences.hoverPreviews, true))
        add(EditorFont.familyKey, "Editor", "Font", "Font Family",
            "The font of code: notebooks, derivations, the console. Menlo is VS Code's default on macOS.",
            .choice(["Menlo", "SF Mono", "Monaco", "Courier New", "JetBrains Mono", "Fira Code"].filter { NSFont(name: $0, size: 12) != nil }.map { ($0, $0) }),
            default: "Menlo", string(EditorFont.familyKey, "Menlo"))
        add(EditorFont.sizeKey, "Editor", "Font", "Font Size", "The size of code, in points.", .number(9...24, step: 1), default: "12",
            ({ String(Int(EditorFont.size)) }, { UserDefaults.standard.set(Double($0) ?? 12, forKey: EditorFont.sizeKey) }))
        // Lab
        add(LabPreferences.gentle, "Lab", "Execution", "Run Gently",
            "Run Python at utility priority with at most two math threads, so long experiments keep the Mac cool and the battery healthy; they take longer.",
            .toggle, default: "true", common: true, bool(LabPreferences.gentle, true))
        add(LabPreferences.interpreter, "Lab", "Interpreter", "Python Path",
            "The python3 that runs notebooks and the console. Empty: found automatically (python.org, Homebrew, conda, pyenv), preferring one with NumPy and Matplotlib.",
            .text(placeholder: "Automatic"), default: "",
            (string(LabPreferences.interpreter, "").get, { store.lab.setPreferredInterpreter($0) }))
        add("lab.setup", "Lab", "Interpreter", "Lemma's Python",
            "A private Python environment in Lemma's folder with NumPy, SciPy, Matplotlib, SymPy and pandas, made from a Python 3 already on this Mac. Nothing outside that folder changes.",
            .custom("labSetup"), default: "", ({ "" }, { _ in }))
        // Questions
        add(LemmaPreferences.questionProvider, "Questions", "Sending", "Assistant",
            "ChatGPT Web inside Lemma; your installed Codex or Claude Code with the sign-in it already has; or the OpenAI, Anthropic or Gemini API with your own key, kept in your Keychain. Answers stay beside their source.",
            .choice(QuestionProvider.allCases.map { ($0.rawValue, $0.label) }),
            default: QuestionProvider.chatGPTWeb.rawValue, common: true, string(LemmaPreferences.questionProvider, QuestionProvider.chatGPTWeb.rawValue))
        add(LemmaPreferences.quickAskMode, "Questions", "Sending", "Quick Questions",
            "For ChatGPT Web: Send now sends the question in Lemma's ChatGPT page at once; Review first prepares it there for you to check and send. The other assistants always answer directly. Each question can still choose.",
            .choice([(WebQuestionMode.askAndSave.rawValue, "Send Now"), (WebQuestionMode.draft.rawValue, "Review First")]),
            default: LemmaPreferences.quickAskModeDefault.rawValue, common: true, string(LemmaPreferences.quickAskMode, LemmaPreferences.quickAskModeDefault.rawValue))
        add("questions.apiKeys", "Questions", "API Keys", "Keys",
            "Your OpenAI, Anthropic and Gemini API keys are stored in the macOS Keychain (items named “Lemma Assistant Keys”), never in settings or study files. Add, check or remove them in Assistants › Connections.",
            .custom("assistantKeys"), default: "", ({ "" }, { _ in }))
        for provider in QuestionProvider.allCases where provider.kind == .api {
            add("questions.\(provider.rawValue).model", "Questions", "API Keys", "\(provider.company) Model",
                "The model the \(provider.label) answers with. Empty: \(provider.defaultModel). Others: \(provider.suggestedModels.dropFirst().map(\.id).joined(separator: ", ")).",
                .text(placeholder: provider.defaultModel), default: "", string("questions.\(provider.rawValue).model", ""))
        }
        for (key, title, description) in [
            (LemmaPreferences.contextText, "Passage Text", "Include the text of the passage."),
            (LemmaPreferences.contextSection, "Section Title", "Include the current section's title."),
            (LemmaPreferences.contextCited, "Cited Equations and Figures", "Include the equations and figures the passage cites, as images."),
            (LemmaPreferences.contextGlossary, "Glossary Entries", "Include matching entries of your glossary (names, notation, scope)."),
            (LemmaPreferences.contextPins, "Pinned References", "Include your pinned references.")
        ] {
            add(key, "Questions", "Context", title, description + " Each question still lists its context before sending.", .toggle, default: "true", bool(key, true))
        }
        return items
    }
}

/// VS Code's settings editor: a search box, a table of contents, and every setting with its description.
struct SettingsEditor: View {
    @Bindable var store: StudyStore
    @Environment(\.theme) private var theme
    @State private var query = ""
    @State private var selectedCategory = "Commonly Used"
    @State private var refresh = 0

    var body: some View {
        let items = SettingsRegistry.items(store: store)
        let categories = ["Commonly Used"] + orderedCategories(items)
        let visible = query.isEmpty ? (selectedCategory == "Commonly Used" ? items.filter(\.commonlyUsed) : items.filter { $0.category == selectedCategory })
            : items.filter { $0.matches(query) }
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                VSTextField(placeholder: "Search settings", text: $query, icon: "search")
                Text("\(visible.count) \(visible.count == 1 ? "Setting" : "Settings")").font(.ui(12)).foregroundStyle(theme[.descriptionForeground]).fixedSize()
            }
            .padding(.horizontal, 24).padding(.top, 14).padding(.bottom, 10)
            HStack(spacing: 0) {
                Text("User").font(.ui(13)).foregroundStyle(theme[.panelTitleActiveForeground])
                    .padding(.horizontal, 2).frame(height: 30)
                    .overlay(alignment: .bottom) { Rectangle().fill(theme[.panelTitleActiveBorder]).frame(height: 1) }
                Spacer()
                VSLinkButton(title: "Open Keyboard Shortcuts", icon: "keyboard") { store.openShortcutsEditor() }
            }
            .padding(.horizontal, 24)
            Rectangle().fill(theme.border(.settingsHeaderBorder)).frame(height: 1)
            HStack(alignment: .top, spacing: 0) {
                if query.isEmpty {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(categories, id: \.self) { category in
                            VSRow(selected: category == selectedCategory, action: { selectedCategory = category }) {
                                Text(category).font(.ui(13, weight: category == selectedCategory ? .semibold : .regular)).lineLimit(1)
                                Spacer(minLength: 0)
                            }
                        }
                        Spacer()
                    }
                    .frame(width: 200).padding(.top, 12)
                    Rectangle().fill(theme.border(.settingsSashBorder)).frame(width: 1)
                }
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(query.isEmpty ? selectedCategory : "Search Results").font(.ui(26, weight: .regular))
                            .foregroundStyle(theme[.settingsHeaderForeground]).padding(.bottom, 10).padding(.top, 4)
                        if visible.isEmpty {
                            Text("No settings found.").font(.ui(13)).foregroundStyle(theme[.descriptionForeground])
                        }
                        ForEach(groups(visible), id: \.title) { group in
                            if !group.title.isEmpty {
                                Text(group.title).font(.ui(18, weight: .semibold)).foregroundStyle(theme[.settingsHeaderForeground])
                                    .padding(.top, 18).padding(.bottom, 6)
                            }
                            ForEach(group.items) { item in SettingRow(store: store, item: item, refresh: $refresh) }
                        }
                    }
                    .padding(.horizontal, 24).padding(.vertical, 12)
                    .frame(maxWidth: 900, alignment: .leading)
                    .id(refresh)
                }
            }
        }
        .background(theme[.editorBackground])
    }

    private func orderedCategories(_ items: [SettingItem]) -> [String] {
        var seen: [String] = []
        for item in items where !seen.contains(item.category) { seen.append(item.category) }
        return seen
    }

    private func groups(_ items: [SettingItem]) -> [(title: String, items: [SettingItem])] {
        var result: [(String, [SettingItem])] = []
        for item in items {
            let title = item.breadcrumb
            if let index = result.firstIndex(where: { $0.0 == title }) { result[index].1.append(item) } else { result.append((title, [item])) }
        }
        return result
    }
}

private struct SettingRow: View {
    @Bindable var store: StudyStore
    @Environment(\.theme) private var theme
    let item: SettingItem
    @Binding var refresh: Int
    @State private var hovering = false
    @State private var text = ""

    var body: some View {
        let modified = item.isModified
        HStack(alignment: .top, spacing: 0) {
            Rectangle().fill(modified ? theme[.settingsModifiedItemIndicator] : .clear).frame(width: 2).padding(.vertical, 4)
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    (Text("\(item.breadcrumb): ").foregroundColor(theme[.settingsHeaderForeground]) + Text(item.title).bold().foregroundColor(theme[.settingsHeaderForeground]))
                        .font(.ui(13))
                    if modified { Text("Modified").font(.ui(11)).foregroundStyle(theme[.descriptionForeground]) }
                    Spacer(minLength: 0)
                    if hovering && modified {
                        VSIconButton(icon: "discard", help: "Reset Setting") { item.set(item.defaultValue); refresh += 1 }
                    }
                }
                if case .toggle = item.control {
                    HStack(alignment: .top, spacing: 8) {
                        VSCheckbox(isOn: Binding(get: { item.get() == "true" }, set: { item.set(String($0)); refresh += 1 }))
                        Text(item.description).font(.ui(13)).foregroundStyle(theme[.descriptionForeground]).fixedSize(horizontal: false, vertical: true)
                    }
                } else {
                    Text(item.description).font(.ui(13)).foregroundStyle(theme[.descriptionForeground]).fixedSize(horizontal: false, vertical: true)
                    control
                }
            }
            .padding(.leading, 10).padding(.vertical, 10).padding(.trailing, 10)
        }
        .background(hovering ? theme[.settingsRowHoverBackground] : .clear)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onAppear { text = item.get() }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(item.breadcrumb): \(item.title)")
    }

    @ViewBuilder private var control: some View {
        switch item.control {
        case .toggle: EmptyView()
        case let .choice(options):
            VSDropdown(options: options, selection: Binding(get: { item.get() }, set: { item.set($0); refresh += 1 }), width: 320)
        case let .number(range, step):
            HStack(spacing: 6) {
                VSTextField(placeholder: "", text: $text, onSubmit: commitNumber(range)).frame(width: 90)
                Stepper("", value: Binding(get: { Double(item.get()) ?? range.lowerBound }, set: {
                    item.set(String(Int(min(range.upperBound, max(range.lowerBound, $0))))); text = item.get(); refresh += 1
                }), in: range, step: step).labelsHidden()
            }
        case let .text(placeholder):
            VSTextField(placeholder: placeholder, text: $text, onSubmit: { item.set(text); refresh += 1 }).frame(maxWidth: 420)
                .onChange(of: text) { _, value in item.set(value) }
        case let .custom(kind):
            if kind == "installedThemes" { InstalledThemesControl(store: store) }
            else if kind == "assistantKeys" { AssistantKeysControl(store: store) }
            else if kind == "labSetup" { Button("Set Up Python for the Lab…") { store.showPythonSetup() }.buttonStyle(.vsSecondary) }
        }
    }

    private func commitNumber(_ range: ClosedRange<Double>) -> () -> Void {
        { if let value = Double(text) { item.set(String(Int(min(range.upperBound, max(range.lowerBound, value))))); text = item.get(); refresh += 1 } }
    }
}

private struct InstalledThemesControl: View {
    @Bindable var store: StudyStore
    @Environment(\.theme) private var theme
    @State private var themes = ThemeManager.shared
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            let installed = themes.entries.filter { $0.group == "Installed" }
            if installed.isEmpty { Text("No installed themes yet.").font(.ui(12)).foregroundStyle(theme[.descriptionForeground]) }
            ForEach(installed) { entry in
                HStack(spacing: 8) {
                    Codicon("symbol-color", size: 14)
                    Text(entry.label).font(.ui(13))
                    Text(entry.kind.label).font(.ui(12)).foregroundStyle(theme[.descriptionForeground])
                    Spacer()
                    Button("Uninstall") { themes.uninstall(entry.id) }.buttonStyle(.vsSecondary)
                }.frame(maxWidth: 420)
            }
            HStack(spacing: 8) {
                Button("Install from File…") { store.installThemeFromFile() }.buttonStyle(.vsPrimary)
                Button("Browse Color Themes") { store.showThemePicker() }.buttonStyle(.vsSecondary)
            }
        }
    }
}
