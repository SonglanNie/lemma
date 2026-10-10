import SwiftUI
import AppKit
import LemmaCore

// The tour's pages: on the first launch a welcome with the choice between the two interfaces and a page for the
// colours; the guides at a glance; the tour's last page; and the tour's card on the Welcome page and the Classic home.

/// The pages' footer: what dismisses on the left, the way forward on the right.
private struct PageFooter<Leading: View, Trailing: View>: View {
    @ViewBuilder var leading: Leading
    @ViewBuilder var trailing: Trailing
    var body: some View {
        HStack(spacing: 8) {
            leading
            Spacer(minLength: 8)
            trailing
        }
        .padding(.horizontal, 28).padding(.top, 20).padding(.bottom, 22)
    }
}

// MARK: - Welcome

/// The first page of the first launch: what Lemma is, and the choice between its two interfaces, switched live.
struct TutorialWelcomePage: View {
    @Bindable var store: StudyStore
    @State private var center = TutorialCenter.shared
    @Environment(\.theme) private var theme
    @State private var previews: (vscode: WorkbenchColors, classic: WorkbenchColors)?

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 0) {
                TutorialAppIcon(size: 52)
                Text("Welcome to Lemma")
                    .font(.system(size: 28, weight: .bold)).tracking(-0.4).foregroundStyle(theme.tourText)
                    .padding(.top, 16)
                Text("An IDE for reading mathematics: references become links, proofs become steps you can debug, and derivations are checked as you write them.")
                    .font(.system(size: 13.5)).lineSpacing(2).multilineTextAlignment(.center).foregroundStyle(theme.tourSecondary)
                    .frame(maxWidth: 520).fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 8)
            }
            .padding(.top, 30).padding(.horizontal, 28)

            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Choose your interface").font(.system(size: 14, weight: .semibold)).foregroundStyle(theme.tourText)
                    Spacer(minLength: 8)
                    Text("You can switch at any time in Settings.").font(.system(size: 12)).foregroundStyle(theme.tourTertiary)
                }
                if let previews {
                    HStack(alignment: .top, spacing: 12) {
                        InterfaceChoice(style: .vscode, colors: previews.vscode, title: "VS Code", badge: "Default",
                                        detail: "An editor's workbench: activity bar, tabs, panels and colour themes.")
                        InterfaceChoice(style: .classic, colors: previews.classic, title: "Classic", badge: nil,
                                        detail: "The native Mac window, with a toolbar and the system's colours.")
                    }
                    .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, 28).padding(.top, 24)

            PageFooter {
                Button("Skip the Tour") { center.close() }
                    .buttonStyle(TutorialButtonStyle(kind: .quiet))
                    .help("Help › Lemma Tour brings the tour back at any time")
                    .padding(.leading, -8)
            } trailing: {
                Text("The tour takes about two minutes.").font(.system(size: 12)).foregroundStyle(theme.tourTertiary).padding(.trailing, 6)
                Button { center.next() } label: { HStack(spacing: 6) { Text("Continue"); Codicon("arrow-right", size: 13) } }
                    .buttonStyle(TutorialButtonStyle(kind: .primary, large: true))
            }
        }
        .onAppear(perform: loadPreviews)
    }

    private func loadPreviews() {
        let manager = ThemeManager.shared
        let dark = manager.systemIsDark
        let vscodeTheme = manager.style == .vscode ? manager.colors.theme
            : manager.theme(dark ? ThemePreferences.defaultDark : ThemePreferences.defaultLight) ?? manager.colors.theme
        let classicTheme = ThemeManager.classicTheme(WorkbenchTheme.current, accent: WorkbenchAccent.current,
                                                     dark: WorkbenchTheme.current.scheme.map { $0 == .dark } ?? dark)
        previews = (WorkbenchColors(theme: vscodeTheme, defaults: manager.defaultsForPreview),
                    WorkbenchColors(theme: classicTheme, defaults: manager.defaultsForPreview))
    }
}

/// One interface, drawn in its own colours; choosing it switches the window behind the page at once.
private struct InterfaceChoice: View {
    @Environment(\.theme) private var theme
    @State private var themes = ThemeManager.shared
    let style: WorkbenchStyle
    let colors: WorkbenchColors
    let title: String
    let badge: String?
    let detail: String
    @State private var hovering = false

    var body: some View {
        let selected = themes.style == style
        let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
        Button {
            guard !selected else { return }
            withAnimation(.easeInOut(duration: 0.25)) { themes.style = style }
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                MiniWorkbench(style: style, colors: colors, lit: nil, phase: 1)
                    .frame(height: 164)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(theme.tourHairline, lineWidth: 1))
                HStack(spacing: 8) {
                    ZStack {
                        Circle().strokeBorder(selected ? theme.tourAccent : theme.tourText.opacity(0.3), lineWidth: 1.5)
                        if selected { Circle().fill(theme.tourAccent).padding(4) }
                    }
                    .frame(width: 16, height: 16)
                    Text(title).font(.system(size: 14, weight: .semibold)).foregroundStyle(theme.tourText)
                    if let badge {
                        Text(badge).font(.system(size: 10.5, weight: .medium)).foregroundStyle(theme.tourSecondary)
                            .padding(.horizontal, 6).padding(.vertical, 1.5)
                            .background(Capsule().fill(theme.tourFill))
                            .overlay(Capsule().strokeBorder(theme.tourHairline, lineWidth: 1))
                    }
                    Spacer(minLength: 0)
                }
                Text(detail).font(.system(size: 12)).lineSpacing(1.5).foregroundStyle(theme.tourSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxHeight: .infinity, alignment: .top)
            .padding(10)
            .background(shape.fill(selected ? theme.tourAccent.opacity(theme.isDark ? 0.10 : 0.06) : hovering ? theme.tourFill : .clear))
            .overlay(shape.strokeBorder(selected ? theme.tourAccent : theme.tourHairline, lineWidth: selected ? 1.5 : 1))
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.15), value: hovering)
        .animation(.easeOut(duration: 0.2), value: selected)
        .accessibilityLabel("\(title) interface")
        .accessibilityAddTraits(selected ? [.isSelected, .isButton] : .isButton)
    }
}

// MARK: - Colours

/// Colour themes to try on the whole window (VS Code interface), or the Classic appearances and accents; and the page.
struct TutorialLookPage: View {
    @Bindable var store: StudyStore
    @State private var center = TutorialCenter.shared
    @State private var themes = ThemeManager.shared
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Text(themes.style == .vscode ? "Pick your colours" : "Pick an appearance")
                    .font(.system(size: 24, weight: .bold)).tracking(-0.3).foregroundStyle(theme.tourText)
                Text(themes.style == .vscode
                     ? "Rest the pointer on a theme to try it on the whole window, and click to keep it. Color Theme (⌥⌘T) lists them all."
                     : "The Classic interface keeps the Mac's appearances and four accents. The page keeps its own theme in both interfaces.")
                    .font(.system(size: 13)).lineSpacing(2).foregroundStyle(theme.tourSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 28).padding(.top, 26)

            ViewThatFits(in: .vertical) {
                choices
                ScrollView { choices }.scrollBounceBehavior(.basedOnSize)
            }

            PageFooter {
                Button { center.back() } label: { Codicon("arrow-left", size: 13) }
                    .buttonStyle(TutorialButtonStyle(kind: .secondary, large: true))
                    .help("Back")
                    .accessibilityLabel("Back")
                Button("Skip the Tour") { center.close() }
                    .buttonStyle(TutorialButtonStyle(kind: .quiet))
                    .help("Help › Lemma Tour brings the tour back at any time")
            } trailing: {
                Button { center.next() } label: { HStack(spacing: 6) { Text("Start the Tour"); Codicon("arrow-right", size: 13) } }
                    .buttonStyle(TutorialButtonStyle(kind: .primary, large: true))
            }
        }
        .onDisappear { themes.preview(nil) }
    }

    private var choices: some View {
        VStack(alignment: .leading, spacing: 20) {
            if themes.style == .vscode { vscodeThemes } else { classicAppearances }
            options
        }
        .padding(.horizontal, 28).padding(.top, 20)
    }

    /// Lemma's own themes first (when this version has them), then the reader's VS Code theme and a few favourites.
    private var picks: [ThemeEntry] {
        var ids = ["lemma-dark", "lemma-light", "dark-2026", "light-2026", "moonlight-ii", "synthwave-84", "tokyo-night", "catppuccin-mocha",
                   "github-light-default", "solarized-light", "dracula", "lemma-midnight"]
        if let mine = themes.vscodeThemeID { ids.removeAll { $0 == mine }; ids.insert(mine, at: 0) }
        return Array(ids.compactMap { themes.entry($0) }.prefix(8))
    }

    private var vscodeThemes: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12, alignment: .top), count: 4), alignment: .leading, spacing: 12) {
            ForEach(picks) { entry in
                VStack(alignment: .leading, spacing: 2) {
                    ThemeTile(entry: entry, selected: themes.effectiveID == entry.id && themes.previewID == nil) { themes.choose(entry.id) }
                        .onHover { inside in themes.preview(inside ? entry.id : nil) }
                    if entry.id == themes.vscodeThemeID {
                        Text("Your VS Code theme").font(.system(size: 10.5, weight: .medium)).foregroundStyle(theme.tourAccent)
                    }
                }
            }
        }
    }

    private var classicAppearances: some View {
        HStack(spacing: 12) {
            ForEach(WorkbenchTheme.allCases) { option in
                let selected = WorkbenchTheme.current == option
                Button {
                    UserDefaults.standard.set(option.rawValue, forKey: "workbench.theme")
                    themes.apply()
                } label: {
                    VStack(alignment: .leading, spacing: 6) {
                        let dark = option.scheme.map { $0 == .dark } ?? themes.systemIsDark
                        let colors = WorkbenchColors(theme: ThemeManager.classicTheme(option, accent: WorkbenchAccent.current, dark: dark),
                                                     defaults: themes.defaultsForPreview)
                        MiniWorkbench(style: .classic, colors: colors, lit: nil, phase: 1)
                            .frame(height: 92)
                            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .strokeBorder(selected ? theme.tourAccent : theme.tourHairline, lineWidth: selected ? 2 : 1))
                        Text(option.label).font(.system(size: 12, weight: selected ? .semibold : .regular)).foregroundStyle(theme.tourText)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(option.label) appearance")
                .accessibilityAddTraits(selected ? [.isSelected, .isButton] : .isButton)
            }
        }
    }

    private var options: some View {
        Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 10) {
            if themes.style == .vscode {
                GridRow {
                    label("Light and dark")
                    Toggle("Follow macOS light and dark", isOn: Binding(get: { themes.autoDetect }, set: { themes.autoDetect = $0 }))
                        .toggleStyle(.switch).controlSize(.small).font(.system(size: 12.5))
                }
                GridRow {
                    label("Accent")
                    HStack(spacing: 6) {
                        ForEach(AccentOverride.allCases) { accent in
                            chip(accent.label, swatch: accent.color(dark: theme.isDark)?.color ?? theme[.focusBorder], selected: themes.accent == accent) { themes.accent = accent }
                        }
                    }
                }
            } else {
                GridRow {
                    label("Accent")
                    HStack(spacing: 6) {
                        ForEach(WorkbenchAccent.allCases) { accent in
                            chip(accent.label, swatch: Color(nsColor: accent.color(dark: theme.isDark)), selected: WorkbenchAccent.current == accent) {
                                UserDefaults.standard.set(accent.rawValue, forKey: "workbench.accent")
                                themes.apply()
                            }
                        }
                    }
                }
            }
            GridRow {
                label("The page")
                HStack(spacing: 6) {
                    ForEach(PageTheme.allCases) { page in
                        chip(page.label, swatch: page == .night ? Color(white: 0.15) : page == .sepia ? Color(red: 0.96, green: 0.91, blue: 0.8) : .white,
                             selected: store.pageTheme == page) { store.pageTheme = page }
                    }
                }
            }
        }
    }

    private func label(_ text: String) -> some View {
        Text(text).font(.system(size: 12.5, weight: .medium)).foregroundStyle(theme.tourSecondary).gridColumnAlignment(.leading)
    }

    private func chip(_ label: String, swatch: Color, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Circle().fill(swatch).frame(width: 11, height: 11).overlay(Circle().strokeBorder(theme.tourText.opacity(0.25), lineWidth: 0.5))
                Text(label).font(.system(size: 12, weight: selected ? .semibold : .regular)).foregroundStyle(theme.tourText)
            }
            .padding(.horizontal, 9).frame(height: 26)
            .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(selected ? theme.tourAccent.opacity(theme.isDark ? 0.18 : 0.10) : theme.tourFill))
            .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(selected ? theme.tourAccent : theme.tourHairline, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? [.isSelected, .isButton] : .isButton)
    }
}

// MARK: - The guides at a glance

/// The tour at the head, then the guides, each a few steps on one subject; a search field finds any step.
struct TutorialHomePage: View {
    @Bindable var store: StudyStore
    @State private var center = TutorialCenter.shared
    @Environment(\.theme) private var theme
    @FocusState private var searching: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 14) {
                TutorialAppIcon(size: 40)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Lemma Tour").font(.system(size: 22, weight: .bold)).tracking(-0.3).foregroundStyle(theme.tourText)
                    Text("Learn the essentials in two minutes on your own window, then pick a guide when you need it.")
                        .font(.system(size: 13)).foregroundStyle(theme.tourSecondary).fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                TutorialCloseButton { center.close() }
            }
            .padding(.horizontal, 24).padding(.top, 22)

            tourRow.padding(.horizontal, 24).padding(.top, 18)

            HStack(alignment: .center, spacing: 10) {
                Text("Guides").font(.system(size: 14, weight: .semibold)).foregroundStyle(theme.tourText)
                Spacer(minLength: 8)
                searchField.frame(width: 220)
            }
            .padding(.horizontal, 24).padding(.top, 20).padding(.bottom, 6)

            ViewThatFits(in: .vertical) {
                list
                ScrollView { list }.scrollBounceBehavior(.basedOnSize)
            }

            HStack(spacing: 10) {
                Text("Help › Lemma Tour starts the tour; Help › Lemma Guides opens this page.").font(.system(size: 11.5)).foregroundStyle(theme.tourTertiary)
                Spacer(minLength: 8)
                if center.seenCount > 0 {
                    Button("Start Over") { center.resetProgress() }
                        .buttonStyle(TutorialButtonStyle(kind: .quiet))
                        .help("Forget which steps you have seen")
                }
            }
            .padding(.horizontal, 24).padding(.vertical, 12)
            .overlay(alignment: .top) { Rectangle().fill(theme.tourHairline).frame(height: 1) }
        }
    }

    private var tourRow: some View {
        let tour = center.tour
        let seen = center.seenSteps(tour)
        let complete = center.isComplete(tour)
        let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
        return HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text("The Tour").font(.system(size: 14, weight: .semibold)).foregroundStyle(theme.tourText)
                Text(tour.summary).font(.system(size: 12.5)).foregroundStyle(theme.tourSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(complete ? "Seen" : seen > 0 ? "\(seen) of \(tour.steps.count) steps seen" : "\(tour.steps.count) steps · about \(tour.minutes) minutes")
                    .font(.system(size: 11.5)).monospacedDigit().foregroundStyle(theme.tourTertiary).padding(.top, 2)
            }
            Spacer(minLength: 8)
            Button { center.next() } label: {
                HStack(spacing: 6) { Text(complete ? "Take It Again" : seen > 0 ? "Continue" : "Take the Tour"); Codicon("arrow-right", size: 13) }
            }
            .buttonStyle(TutorialButtonStyle(kind: .primary, large: true))
        }
        .padding(14)
        .background(shape.fill(theme.tourAccent.opacity(theme.isDark ? 0.10 : 0.06)))
        .overlay(shape.strokeBorder(theme.tourAccent.opacity(0.45), lineWidth: 1))
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Codicon("search", size: 13).foregroundStyle(theme.tourTertiary)
            TextField("", text: $center.query, prompt: Text("Search the guides").foregroundColor(theme.tourTertiary))
                .textFieldStyle(.plain).font(.system(size: 12.5)).foregroundStyle(theme.tourText)
                .focused($searching)
                .accessibilityLabel("Search the guides")
            if !center.query.isEmpty {
                Button { center.query = "" } label: { Codicon("close", size: 12).foregroundStyle(theme.tourTertiary) }
                    .buttonStyle(.plain).accessibilityLabel("Clear the search")
            }
        }
        .padding(.horizontal, 8).frame(height: 26)
        .background(RoundedRectangle(cornerRadius: 4, style: .continuous).fill(theme[.inputBackground]))
        .overlay(RoundedRectangle(cornerRadius: 4, style: .continuous).strokeBorder(searching ? theme[.focusBorder] : theme.border(.inputBorder), lineWidth: 1))
    }

    @ViewBuilder private var list: some View {
        VStack(alignment: .leading, spacing: 1) {
            if center.query.trimmingCharacters(in: .whitespaces).isEmpty {
                ForEach(Array(center.guides.enumerated()).dropFirst(), id: \.element.id) { index, guide in
                    GuideRow(guide: guide) { center.begin(guide: index) }
                }
            } else {
                let found = center.matches(center.query)
                if found.isEmpty {
                    Text("No step mentions “\(center.query)”.").font(.system(size: 12.5)).foregroundStyle(theme.tourSecondary).padding(.horizontal, 10).padding(.vertical, 12)
                }
                ForEach(found, id: \.step.id) { match in
                    StepRow(guide: match.guide, step: match.step) { center.open(stepID: match.step.id) }
                }
            }
        }
        .padding(.horizontal, 14).padding(.bottom, 12)
    }
}

/// A guide in the list: its icon, title and summary, and how much of it has been seen.
private struct GuideRow: View {
    let guide: TutorialGuide
    let action: () -> Void
    @State private var center = TutorialCenter.shared
    @Environment(\.theme) private var theme
    @State private var hovering = false

    var body: some View {
        let seen = center.seenSteps(guide)
        Button(action: action) {
            HStack(spacing: 12) {
                Codicon(guide.icon, size: 16).foregroundStyle(theme[.iconForeground]).frame(width: 20)
                VStack(alignment: .leading, spacing: 1) {
                    Text(guide.title).font(.system(size: 13, weight: .medium)).foregroundStyle(theme.tourText)
                    Text(guide.summary).font(.system(size: 12)).foregroundStyle(theme.tourSecondary).lineLimit(1)
                }
                Spacer(minLength: 8)
                if center.isComplete(guide) {
                    Codicon("pass-filled", size: 14).foregroundStyle(theme[.testingIconPassed]).help("Seen")
                } else {
                    Text(seen > 0 ? "\(seen) of \(guide.steps.count)" : "\(guide.steps.count) steps")
                        .font(.system(size: 11.5)).monospacedDigit().foregroundStyle(theme.tourTertiary)
                }
                Codicon("chevron-right", size: 12).foregroundStyle(theme.tourTertiary.opacity(hovering ? 1 : 0.6))
            }
            .padding(.horizontal, 10).frame(height: 42)
            .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(hovering ? theme[.listHoverBackground] : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityLabel("\(guide.title), \(seen) of \(guide.steps.count) steps seen")
    }
}

/// A step found by the search, with the guide it belongs to.
private struct StepRow: View {
    let guide: TutorialGuide
    let step: TutorialStep
    let action: () -> Void
    @Environment(\.theme) private var theme
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Codicon(guide.icon, size: 16).foregroundStyle(theme[.iconForeground]).frame(width: 20)
                VStack(alignment: .leading, spacing: 1) {
                    Text(step.title).font(.system(size: 13, weight: .medium)).foregroundStyle(theme.tourText).lineLimit(1)
                    Text(guide.title).font(.system(size: 12)).foregroundStyle(theme.tourSecondary).lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10).frame(height: 42)
            .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(hovering ? theme[.listHoverBackground] : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

// MARK: - Finish

/// The tour's last page: the shortcuts worth keeping, then the guides or a first book.
struct TutorialFinishPage: View {
    @Bindable var store: StudyStore
    @State private var center = TutorialCenter.shared
    @Environment(\.theme) private var theme

    private let keys: [(String, String)] = [
        ("⌘P", "Go to anything"), ("⇧⌘P", "Run any command"), ("⌘K", "Ask about the selection"),
        ("F5", "Debug the proof in view"), ("⌥⌘E", "Work through a step"), ("⌘/", "Every shortcut")
    ]

    var body: some View {
        VStack(spacing: 0) {
            Codicon("pass-filled", size: 34).foregroundStyle(theme[.testingIconPassed])
                .padding(.top, 30)
            Text("You're ready").font(.system(size: 26, weight: .bold)).tracking(-0.4).foregroundStyle(theme.tourText).padding(.top, 12)
            Text("These shortcuts are worth keeping:").font(.system(size: 13)).foregroundStyle(theme.tourSecondary).padding(.top, 6)
            Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 9) {
                ForEach(0..<3, id: \.self) { row in
                    GridRow {
                        ForEach(0..<2, id: \.self) { column in
                            let entry = keys[row * 2 + column]
                            TutorialKeys(shortcut: entry.0, size: 11).gridColumnAlignment(.trailing)
                            Text(entry.1).font(.system(size: 12.5)).foregroundStyle(theme.tourText.opacity(0.88)).lineLimit(1)
                                .padding(.trailing, column == 0 ? 14 : 0)
                        }
                    }
                }
            }
            .padding(.top, 16)
            Text("The guides go deeper: proofs, derivations, the Lab, notes and more.")
                .font(.system(size: 12.5)).foregroundStyle(theme.tourTertiary).multilineTextAlignment(.center)
                .padding(.top, 18).padding(.horizontal, 28)
            PageFooter {
                Button("Explore the Guides") { center.showHome() }
                    .buttonStyle(TutorialButtonStyle(kind: .secondary, large: true))
            } trailing: {
                if store.document == nil {
                    Button { center.close(); store.catalogMode = .books; store.reveal(.catalog) } label: { Text("Free Textbooks") }
                        .buttonStyle(TutorialButtonStyle(kind: .secondary, large: true))
                    Button { center.close(); store.choosePDF() } label: { Text("Open a PDF…") }
                        .buttonStyle(TutorialButtonStyle(kind: .primary, large: true))
                } else {
                    Button { center.close() } label: { HStack(spacing: 6) { Text("Start Reading"); Codicon("arrow-right", size: 13) } }
                        .buttonStyle(TutorialButtonStyle(kind: .primary, large: true))
                }
            }
        }
    }
}

// MARK: - The tour's card on the Welcome page and the Classic home

/// Invites the reader to the tour, back into it, or to the guides once the tour has been seen. In a narrow column the
/// buttons go under the text.
struct TutorialPromoCard: View {
    @Bindable var store: StudyStore
    @State private var center = TutorialCenter.shared
    @State private var compact = false
    @Environment(\.theme) private var theme

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
        Group {
            if compact {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .top, spacing: 12) { TutorialAppIcon(size: 32); text }
                    HStack(spacing: 8) { Spacer(minLength: 0); buttons }
                }
            } else {
                HStack(spacing: 14) {
                    TutorialAppIcon(size: 36)
                    text
                    Spacer(minLength: 8)
                    buttons
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(shape.fill(theme.tourFill))
        .overlay(shape.strokeBorder(theme.tourHairline, lineWidth: 1))
        .onGeometryChange(for: Bool.self) { $0.size.width < 470 } action: { compact = $0 }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(center.isComplete(center.tour) ? "Lemma Guides" : "The Lemma Tour")
    }

    private var text: some View {
        let tour = center.tour
        let seen = center.seenSteps(tour)
        let complete = center.isComplete(tour)
        return VStack(alignment: .leading, spacing: 2) {
            Text(complete ? "Lemma Guides" : "The Lemma Tour").font(.system(size: 14, weight: .semibold)).foregroundStyle(theme.tourText)
            Text(complete ? "Proofs, derivations, the Lab and more, a few steps each."
                 : seen > 0 ? "\(seen) of \(tour.steps.count) steps seen. Pick up where you left off."
                 : "\(tour.steps.count) steps on your own window, about \(tour.minutes) minutes.")
                .font(.system(size: 12)).foregroundStyle(theme.tourSecondary).fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder private var buttons: some View {
        let complete = center.isComplete(center.tour)
        let seen = center.seenSteps(center.tour)
        Button(complete ? "Tour Again" : "Guides") { complete ? center.startTour(store) : center.open(store) }
            .buttonStyle(TutorialButtonStyle(kind: .quiet))
        Button(complete ? "Open the Guides" : seen > 0 ? "Continue the Tour" : "Take the Tour") { complete ? center.open(store) : center.startTour(store) }
            .buttonStyle(TutorialButtonStyle(kind: .primary))
    }
}
