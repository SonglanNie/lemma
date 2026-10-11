import SwiftUI
import AppKit
import LemmaCore

/// Both sign-in and question follow-up belong to the study window. The sheet is drawn as a workbench part: a title bar
/// with the two tabs, a list on the side bar's colour, and the selected question or assistant beside it.
struct AssistantPane: View {
    @Bindable var store: StudyStore
    @Environment(\.theme) private var theme
    @AppStorage(LemmaPreferences.questionProvider) private var defaultProvider = QuestionProvider.chatGPTWeb.rawValue
    @State private var themes = ThemeManager.shared
    private var runtime: QuestionRuntime { store.questions }

    /// The sheet fits a 13-inch screen: it never asks for more height than the screen has.
    private static var height: CGFloat { min(700, max(480, (NSScreen.main?.visibleFrame.height ?? 800) - 70)) }
    static let listWidth: CGFloat = 248

    var body: some View {
        VStack(spacing: 0) {
            header
            if runtime.panel == "requests" { requests } else { connections }
        }
        .frame(width: 900, height: Self.height)
        .foregroundStyle(theme[.foreground])
        .background(theme[.editorBackground])
        .onAppear { runtime.refreshKeys() }
        .onDisappear { runtime.endLogin() }
    }

    private var header: some View {
        @Bindable var runtime = runtime
        let running = runtime.jobs.filter { !$0.finished }.count
        return WorkbenchSheetHeader(codicon: "comment-discussion", symbol: "text.bubble", title: "Assistants") {
            if themes.style == .vscode {
                WorkbenchSheetTab(title: "Questions", count: running > 0 ? running : nil, active: runtime.panel == "requests") { runtime.panel = "requests" }
                WorkbenchSheetTab(title: "Connections", active: runtime.panel == "connections") { runtime.panel = "connections" }
            } else {
                Picker("View", selection: $runtime.panel) {
                    Text("Questions").tag("requests")
                    Text("Connections").tag("connections")
                }.pickerStyle(.segmented).labelsHidden().fixedSize()
            }
        } actions: {
            Button("Continue Reading") { store.showBrowserSetup = false }
                .keyboardShortcut(.cancelAction)
                .workbenchButton(.secondary)
                .help("Back to the page. Questions keep running and their answers are saved (Escape)")
        }
    }

    /// The side column: the side bar's colour with its border, the full height of the sheet.
    private func sideColumn<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .frame(width: Self.listWidth)
            .frame(maxHeight: .infinity, alignment: .top)
            .background(theme[.sideBarBackground])
            .overlay(alignment: .trailing) { Rectangle().fill(theme.hairline(.sideBarBorder)).frame(width: 1) }
    }

    @ViewBuilder private var requests: some View {
        if runtime.jobs.isEmpty {
            AssistantEmptyState { runtime.panel = "connections" }
        } else {
            HStack(spacing: 0) {
                sideColumn { QuestionJobList(runtime: runtime) }
                if let job = runtime.selected { QuestionJobDetail(store: store, job: job) }
                else { Color.clear.frame(maxWidth: .infinity, maxHeight: .infinity) }
            }
        }
    }

    private var connections: some View {
        let provider = runtime.connectionProvider
        let companion = runtime.showsCompanion
        let webPage = !companion && provider.kind == .web
        return HStack(spacing: 0) {
            sideColumn {
                AssistantProviderList(runtime: runtime, defaultProvider: defaultProvider)
            }
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 14) {
                    if companion { ChromeCompanionPane(store: store) }
                    else {
                        connectionTitle(provider)
                        switch provider.kind {
                        case .web: WebConnectionPane(runtime: runtime)
                        case .cli: CLIConnectionPane(runtime: runtime, provider: provider)
                        case .api: APIConnectionPane(runtime: runtime, provider: provider)
                        }
                    }
                }
                .padding(.horizontal, 24).padding(.top, 18).padding(.bottom, webPage ? 14 : 18)
                if webPage && (runtime.webLoaded || runtime.webBusy) {
                    // The page fills the rest of the sheet, as VS Code shows a web view in an editor.
                    ChatGPTPageView(runtime: runtime).frame(maxWidth: .infinity, maxHeight: .infinity)
                        .overlay(alignment: .top) { Rectangle().fill(theme.hairline(.panelBorder)).frame(height: 1) }
                } else if webPage {
                    WebConnectPrompt(runtime: runtime)
                } else {
                    Spacer(minLength: 0)
                }
                if !companion { privacyFooter(provider) }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    private func connectionTitle(_ provider: QuestionProvider) -> some View {
        HStack(alignment: .center, spacing: 10) {
            Text(provider.label).font(.ui(15, weight: .semibold))
            if defaultProvider == provider.rawValue {
                Text("Default for questions").font(.ui(11)).foregroundStyle(theme[.descriptionForeground])
                    .padding(.horizontal, 8).frame(height: 18)
                    .background(Capsule().fill(theme[.foreground].opacity(0.08)))
            }
            Spacer(minLength: 8)
            if defaultProvider != provider.rawValue {
                Button("Use by Default") { defaultProvider = provider.rawValue }.workbenchButton(.secondary)
                    .help("Questions go to \(provider.label) unless you choose another assistant when you ask")
            }
        }
    }

    /// What leaves the Mac with a question, under the assistant's settings.
    private func privacyFooter(_ provider: QuestionProvider) -> some View {
        HStack(alignment: .top, spacing: 8) {
            WorkbenchGlyph(codicon: "lock", symbol: "lock.shield", color: .descriptionForeground, size: 14).padding(.top, 1)
            Text(provider.privacySummary).font(.ui(12)).foregroundStyle(theme[.descriptionForeground])
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 24).padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .top) { Rectangle().fill(theme.hairline(.panelBorder)).frame(height: 1) }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(provider.privacySummary)
    }
}

/// No question yet: what the tab is for and how to ask, centred as VS Code's empty editor shows its shortcuts.
private struct AssistantEmptyState: View {
    let openConnections: () -> Void
    @Environment(\.theme) private var theme
    var body: some View {
        VStack(spacing: 10) {
            WorkbenchGlyph(codicon: "comment-discussion", symbol: "text.bubble", color: .descriptionForeground, size: 34).opacity(0.6).padding(.bottom, 4)
            Text("No questions yet").font(.ui(15, weight: .semibold))
            Text("Each question you ask and its answer appear here while you keep reading. The answer is also saved beside its passage.")
                .font(.ui(13)).foregroundStyle(theme[.descriptionForeground]).multilineTextAlignment(.center).lineSpacing(2)
                .frame(maxWidth: 420).fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                Text("Ask about a selected passage").font(.ui(12)).foregroundStyle(theme[.descriptionForeground])
                VSKeybinding(shortcut: "⌘K")
            }
            .padding(.top, 8)
            WorkbenchLink(title: "Set up an assistant", codicon: "plug", symbol: "powerplug", action: openConnections).padding(.top, 2)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
