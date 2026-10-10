import SwiftUI
import AppKit
import LemmaCore

/// The side bar's view containers, one icon each in the activity bar, as VS Code's Explorer, Search, Run and Debug…
enum ViewContainer: String, CaseIterable, Identifiable {
    case explorer, search, structure, debug, testing, lab, projects, marks, catalog
    var id: String { rawValue }

    var title: String {
        switch self {
        case .explorer: "Explorer"; case .search: "Search"; case .structure: "Structure"; case .debug: "Run and Debug"
        case .testing: "Testing"; case .lab: "Lab"; case .projects: "Projects"; case .marks: "Marks"; case .catalog: "Catalog"
        }
    }
    var icon: String {
        switch self {
        case .explorer: "files"; case .search: "search"; case .structure: "symbol-structure"; case .debug: "debug-alt"
        case .testing: "beaker"; case .lab: "notebook"; case .projects: "folder-library"; case .marks: "bookmark"; case .catalog: "extensions"
        }
    }
    var shortcut: String? {
        switch self { case .explorer: "⌥⌘1"; case .search: "⇧⌘F"; case .debug: "⇧⌘D"; case .catalog: "⇧⌘X"; default: nil }
    }
    var help: String {
        let base: String = switch self {
        case .explorer: "Explorer: open editors, your library, the book's outline and timeline"
        case .search: "Search: the book, your notes, or indexed pages"
        case .structure: "Structure: results, equations, figures and the book's index"
        case .debug: "Run and Debug: step through a proof with what is in scope"
        case .testing: "Testing: recall definitions and results as tests"
        case .lab: "Lab: Python notebooks and checked derivations"
        case .projects: "Projects: research questions across books"
        case .marks: "Marks: bookmarks, highlights and “?” marks"
        case .catalog: "Catalog: free textbooks and arXiv papers"
        }
        return shortcut.map { "\(base) (\($0))" } ?? base
    }

    /// The view revealed when the container is chosen.
    var primary: NavigatorSection {
        switch self {
        case .explorer: .contents; case .search: .search; case .structure: .results; case .debug: .debug; case .testing: .testing
        case .lab: .lab; case .projects: .projects; case .marks: .bookmarks; case .catalog: .catalog
        }
    }

    static func of(_ section: NavigatorSection) -> ViewContainer {
        switch section {
        case .library, .contents, .pages, .timeline: .explorer
        case .search: .search
        case .results, .symbols, .index: .structure
        case .debug: .debug
        case .testing: .testing
        case .lab: .lab
        case .projects: .projects
        case .bookmarks: .marks
        case .catalog: .catalog
        }
    }
}

/// VS Code's activity bar: 48 pt wide, 24 pt codicons, a 2 pt bar beside the active view, badges at the icon's corner.
struct VSActivityBar: View {
    @Bindable var store: StudyStore
    @Environment(\.theme) private var theme
    @Environment(\.controlActiveState) private var activeState

    var body: some View {
        VStack(spacing: 0) {
            ForEach(ViewContainer.allCases) { container in
                ActivityItem(icon: container.icon, help: container.help,
                             active: store.showLibrary && ViewContainer.of(store.navigatorSection) == container,
                             badge: badge(container)) {
                    if store.showLibrary && ViewContainer.of(store.navigatorSection) == container { store.toggleLibrary() }
                    else if ViewContainer.of(store.navigatorSection) == container { store.reveal(store.navigatorSection) }
                    else { store.reveal(container.primary) }
                }
            }
            Spacer(minLength: 8)
            ActivityItem(icon: "account", help: "Assistants: ChatGPT, Codex, Claude Code, and API keys for OpenAI, Anthropic and Gemini", active: false, badge: nil) { store.showBrowserSetup = true }
            ManageMenu(store: store)
        }
        .frame(width: VSMetrics.activityBarWidth)
        .frame(maxHeight: .infinity)
        .background(theme[.activityBarBackground])
        .vsBorder(store.workbenchLayout.sidebarPosition == .left ? .trailing : .leading, .activityBarBorder, theme: theme)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Activity Bar")
    }

    private func badge(_ container: ViewContainer) -> ActivityBadge? {
        switch container {
        case .search:
            let count = store.reader.searchResults.count
            return count > 0 ? .count(count) : nil
        case .testing:
            let due = store.reviewNotes.count
            return due > 0 ? .count(due) : nil
        case .debug: return store.debug != nil ? .dot : nil
        case .lab: return store.lab.sessions.values.contains { $0.state == .busy } ? .progress : nil
        case .catalog: return store.downloads.progress.isEmpty ? nil : .progress
        case .marks:
            let open = store.openMarks.count
            return open > 0 ? .count(open) : nil
        default: return nil
        }
    }
}

enum ActivityBadge: Equatable { case count(Int), dot, progress }

private struct ActivityItem: View {
    @Environment(\.theme) private var theme
    let icon: String
    let help: String
    let active: Bool
    let badge: ActivityBadge?
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            ZStack {
                if active && theme.has(.activityBarActiveBackground) { theme[.activityBarActiveBackground] }
                Codicon(icon, size: 24)
                    .foregroundStyle(active || hovering ? theme[.activityBarForeground] : theme[.activityBarInactiveForeground])
                if let badge {
                    badgeView(badge).offset(x: 9, y: 8)
                }
            }
            .frame(width: VSMetrics.activityBarWidth, height: VSMetrics.activityItemHeight)
            .overlay(alignment: .leading) {
                if active { Rectangle().fill(theme[.activityBarActiveBorder]).frame(width: 2) }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(help)
        .accessibilityLabel(help)
        .accessibilityAddTraits(active ? .isSelected : [])
    }

    @ViewBuilder private func badgeView(_ badge: ActivityBadge) -> some View {
        switch badge {
        case let .count(count):
            Text(count > 99 ? "99+" : "\(count)").font(.system(size: 9, weight: .semibold)).monospacedDigit()
                .foregroundStyle(theme[.activityBarBadgeForeground])
                .padding(.horizontal, 4).frame(minWidth: 16, minHeight: 16)
                .background(Capsule().fill(theme[.activityBarBadgeBackground]))
        case .dot:
            Circle().fill(theme[.activityBarBadgeBackground]).frame(width: 8, height: 8).offset(x: -3, y: 3)
        case .progress:
            Codicon("loading", size: 12).foregroundStyle(theme[.activityBarBadgeBackground])
                .rotationEffect(.degrees(0)).offset(x: -2, y: 2)
        }
    }
}

/// The gear at the bottom of the activity bar: VS Code's Manage menu.
private struct ManageMenu: View {
    @Bindable var store: StudyStore
    @Environment(\.theme) private var theme
    @State private var hovering = false
    var body: some View {
        VSMenu(items: {
            [.action("Command Palette…", shortcut: "⇧⌘P") { store.showPalette(.commands) },
             .separator,
             .action("Settings", shortcut: "⌘,") { store.openSettingsEditor() },
             .action("Keyboard Shortcuts", shortcut: "⌘/") { store.openShortcutsEditor() },
             .separator,
             .action("Color Theme…", shortcut: "⌥⌘T") { store.showThemePicker() },
             .action("Install Color Theme from File…") { store.installThemeFromFile() },
             .separator,
             .action("Lemma Tour") { TutorialCenter.shared.startTour(store) },
             .action("Lemma Guides") { TutorialCenter.shared.open(store) },
             .action("Welcome") { store.openWelcome() },
             .action("What’s New in Lemma") { store.openSpecial(.releaseNotes) },
             .action("Assistants…") { store.showBrowserSetup = true }]
        }, placement: .trailingUp) {
            Codicon("settings-gear", size: 24)
                .foregroundStyle(hovering ? theme[.activityBarForeground] : theme[.activityBarInactiveForeground])
                .frame(width: VSMetrics.activityBarWidth, height: VSMetrics.activityItemHeight)
        }
        .onHover { hovering = $0 }
        .help("Manage")
        .accessibilityLabel("Manage")
    }
}

@MainActor
extension StudyStore {
    func installThemeFromFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json, .init(filenameExtension: "vsix") ?? .zip, .zip]
        panel.allowsMultipleSelection = false
        panel.message = "Choose a VS Code color theme (.json) or a theme extension (.vsix)."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let installed = try ThemeManager.shared.install(from: url)
            if let first = installed.first {
                ThemeManager.shared.choose(first.id)
                notify("Installed \(installed.map(\.label).joined(separator: ", ")).", source: "Color Theme")
            }
        } catch {
            notify("Could not install this theme: \(error.localizedDescription)", severity: .error, source: "Color Theme")
        }
    }
}
