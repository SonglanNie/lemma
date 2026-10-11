import SwiftUI
import AppKit
import LemmaCore

extension QuestionProvider {
    /// What leaves the Mac, and where it goes, in one or two sentences.
    var privacySummary: String {
        switch self {
        case .chatGPTWeb:
            "What is sent: the ticked images and the draft go to chatgpt.com in this embedded page, under your ChatGPT account. The page does not load until you connect or ask."
        case .codex:
            "What is sent: Lemma runs your installed Codex, which sends the ticked images and the draft to OpenAI under the account Codex is signed in to. Lemma never sees its credentials."
        case .claudeCode:
            "What is sent: Lemma runs your installed Claude Code, which sends the ticked images and the draft to Anthropic, or to the cloud provider you set it up with, under its own sign-in. Lemma never sees its credentials."
        case .openAI:
            "What is sent: the ticked images and the draft go from this Mac straight to api.openai.com with your API key, billed to your OpenAI account. Lemma asks OpenAI not to store the response. The key stays in your Keychain."
        case .anthropic:
            "What is sent: the ticked images and the draft go from this Mac straight to api.anthropic.com with your API key, billed to your Anthropic account. The key stays in your Keychain."
        case .gemini:
            "What is sent: the ticked images and the draft go from this Mac straight to generativelanguage.googleapis.com with your API key. Google's Gemini API terms apply, and they differ between the free and paid tiers. The key stays in your Keychain."
        }
    }

    /// How Ask and save reaches the assistant, for the question sheet and the quick question.
    var sendingSummary: String {
        switch kind {
        case .web: "Uses your ChatGPT session in Lemma's embedded page. Wait here or keep reading; the answer stays with this passage."
        case .cli: "Runs your installed \(label) with the sign-in it already has. Wait here or keep reading; the answer stays with this passage."
        case .api: "Sends the ticked images and the text to \(company) with your API key. Wait here or keep reading; the answer stays with this passage."
        }
    }

    /// The ways a CLI can be set up, all of which Lemma uses as they are.
    var accountKinds: String {
        switch self {
        case .claudeCode: "a Claude account, a Claude Console account, an API key or a cloud provider such as Amazon Bedrock"
        case .codex: "a ChatGPT account or an API key"
        default: ""
        }
    }
}

/// The six assistants, grouped by how Lemma reaches them, and the Chrome companion apart at the foot of the list.
struct AssistantProviderList: View {
    @Bindable var runtime: QuestionRuntime
    let defaultProvider: String
    @Environment(\.theme) private var theme

    var body: some View {
        let companion = runtime.showsCompanion
        return VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 1) {
                    group("In Lemma", [.chatGPTWeb])
                    group("Installed command-line tool", [.codex, .claudeCode])
                    group("Your API key", [.openAI, .anthropic, .gemini])
                }
                .padding(.bottom, 10)
            }
            Rectangle().fill(theme.hairline(.sideBarBorder)).frame(height: 1)
            WorkbenchListRow(selected: companion) { runtime.showsCompanion = true } content: {
                HStack(spacing: 8) {
                    WorkbenchGlyph(codicon: "extensions", symbol: "puzzlepiece.extension", color: companion ? .listActiveSelectionForeground : .iconForeground)
                    Text("Chrome Companion").font(.ui(13)).lineLimit(1)
                    Spacer(minLength: 4)
                    Text("arXiv").font(.ui(11)).foregroundStyle(theme[.descriptionForeground])
                }
            }
            .padding(.vertical, 6)
            .help("Optional: add the paper from Chrome's active arXiv tab")
        }
    }

    private func group(_ title: String, _ providers: [QuestionProvider]) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            WorkbenchListCaption(title: title)
            ForEach(providers) { provider in row(provider) }
        }
    }

    private func row(_ provider: QuestionProvider) -> some View {
        let selected = !runtime.showsCompanion && runtime.connectionProvider == provider
        let ready: Bool = switch provider.kind {
        case .api: runtime.keyPresence[provider] == true
        case .cli: if case .signedIn = runtime.signIns[provider] { true } else { false }
        case .web: runtime.webLoaded
        }
        return WorkbenchListRow(selected: selected) { runtime.connectionProvider = provider; runtime.showsCompanion = false } content: {
            HStack(spacing: 8) {
                WorkbenchGlyph(codicon: provider.codicon, symbol: provider.symbol, color: selected ? .listActiveSelectionForeground : .iconForeground)
                Text(provider.label).font(.ui(13)).lineLimit(1)
                Spacer(minLength: 4)
                if defaultProvider == provider.rawValue {
                    Text("Default").font(.ui(11)).foregroundStyle(selected ? theme[.listActiveSelectionForeground].opacity(0.75) : theme[.descriptionForeground])
                }
                if ready {
                    WorkbenchGlyph(codicon: "pass-filled", symbol: "checkmark.circle.fill", color: .testingIconPassed, size: 14).accessibilityLabel("Ready")
                }
            }
        }
        .accessibilityLabel(provider.label + (defaultProvider == provider.rawValue ? ", default" : "") + (ready ? ", ready" : ""))
    }
}

extension QuestionProvider {
    /// The list's icon for each way of reaching an assistant: the embedded page, a command-line tool, an API key.
    var codicon: String { switch kind { case .web: "globe"; case .cli: "terminal"; case .api: "key" } }
    var symbol: String { switch kind { case .web: "globe"; case .cli: "terminal"; case .api: "key" } }
}

/// ChatGPT Web: what it is and, once the page is loaded, its controls. The page itself fills the sheet below them.
struct WebConnectionPane: View {
    @Bindable var runtime: QuestionRuntime
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("ChatGPT Web runs chatgpt.com inside Lemma with your usual account, model choice and limits. Its sign-in stays in this embedded browser, separate from Safari and Chrome.")
                .font(.ui(13)).lineSpacing(2).fixedSize(horizontal: false, vertical: true)
            Text("Sign in with your email address. Google and Apple sign-in may refuse to work inside an embedded browser; email sign-in works.")
                .font(.ui(12)).foregroundStyle(theme[.descriptionForeground]).fixedSize(horizontal: false, vertical: true)
            if runtime.webLoaded || runtime.webBusy {
                HStack(spacing: 8) {
                    Button("New Chat") { runtime.showConversation(ChatGPTSession.home) }.workbenchButton().disabled(runtime.webBusy)
                    Button("Reload") { runtime.web.view.reload() }.workbenchButton().disabled(runtime.webBusy)
                    Button("Close Page") { runtime.closeWeb() }.workbenchButton().disabled(runtime.webBusy)
                        .help("Unload chatgpt.com from Lemma. You stay signed in.")
                    Spacer(minLength: 8)
                    Text("Questions use your normal ChatGPT access and limits.").font(.ui(12)).foregroundStyle(theme[.descriptionForeground])
                        .lineLimit(1).truncationMode(.tail)
                }
                .padding(.top, 6)
            }
        }
    }
}

/// Before ChatGPT's page is loaded: nothing loads until the reader clicks Connect (or asks a ChatGPT question).
struct WebConnectPrompt: View {
    @Bindable var runtime: QuestionRuntime
    @Environment(\.theme) private var theme
    var body: some View {
        VStack(spacing: 10) {
            WorkbenchGlyph(codicon: "globe", symbol: "globe", color: .descriptionForeground, size: 30).opacity(0.6).padding(.bottom, 2)
            Button("Connect ChatGPT") { runtime.connectWeb() }.workbenchButton(.primary).controlSize(.large)
            Text("Opens chatgpt.com here. Nothing is loaded until you click.").font(.ui(12)).foregroundStyle(theme[.descriptionForeground])
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Codex and Claude Code: the reader's own installed CLI with whatever sign-in it already has.
struct CLIConnectionPane: View {
    @Bindable var runtime: QuestionRuntime
    let provider: QuestionProvider
    @Environment(\.theme) private var theme
    @State private var themes = ThemeManager.shared
    @State private var path = ""
    @State private var model = ""
    @State private var code = ""
    /// Where automatic discovery finds the CLI, looked up when the pane appears rather than on every redraw.
    @State private var automatic = "Automatic"

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Lemma runs your installed \(provider.label) and uses the sign-in it already has: \(provider.accountKinds). You stay here while it answers.")
                .font(.ui(13)).lineSpacing(2).fixedSize(horizontal: false, vertical: true)
            HStack(alignment: .center, spacing: 10) {
                statusIcon
                Text(runtime.connections[provider] ?? "Checking the installed CLI…").font(.ui(13)).textSelection(.enabled)
                    .foregroundStyle(statusFailed ? theme[.errorForeground] : theme[.foreground]).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                Button("Check Again") { Task { await runtime.check(provider) } }.workbenchButton().disabled(runtime.checking.contains(provider))
            }
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    ForEach(QuestionCLI.signInMethods(provider), id: \.self) { method in
                        Button(method.title) { runtime.signIn(provider, method: method) }.workbenchButton().disabled(runtime.loginProvider != nil)
                    }
                    if let other = runtime.loginProvider, other != provider {
                        Text("Signing in to \(other.label)…").font(.ui(12)).foregroundStyle(theme[.descriptionForeground])
                        Button("Cancel That Sign-In", action: runtime.endLogin).workbenchButton()
                    }
                }
                Text("Sign-in opens \(provider.company)'s own page in your default browser, and \(provider.label) keeps the credentials. You can also sign in in Terminal, or set \(provider.label) up with an API key; Lemma uses it as it is.")
                    .font(.ui(12)).foregroundStyle(theme[.descriptionForeground]).fixedSize(horizontal: false, vertical: true)
            }
            if runtime.loginProvider == provider { loginArea }
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 10) {
                GridRow {
                    Text("Executable").font(.ui(13)).foregroundStyle(theme[.descriptionForeground])
                    WorkbenchTextField(placeholder: automatic, text: $path, accessibilityLabel: "\(provider.label) executable path", onSubmit: save)
                    Button("Choose…") {
                        let panel = NSOpenPanel(); panel.canChooseFiles = true; panel.canChooseDirectories = false
                        panel.treatsFilePackagesAsDirectories = true; panel.showsHiddenFiles = true
                        if panel.runModal() == .OK, let url = panel.url { path = url.path; save() }
                    }.workbenchButton()
                }
                GridRow {
                    Text("Model").font(.ui(13)).foregroundStyle(theme[.descriptionForeground])
                    WorkbenchTextField(placeholder: "CLI default", text: $model, accessibilityLabel: "\(provider.label) model", onSubmit: save)
                    Button("Apply", action: save).workbenchButton()
                }
            }
            Text("Leave both empty for automatic discovery and the CLI's default model. Lemma looks in your login shell's PATH, Homebrew, ~/.local/bin, Volta, nvm, fnm, asdf and mise, and runs the CLI with its own folder first on PATH so it finds Node.")
                .font(.ui(12)).foregroundStyle(theme[.descriptionForeground]).fixedSize(horizontal: false, vertical: true)
        }
        .task(id: provider) {
            path = runtime.preferredPath(provider)
            model = runtime.chosenModel(provider)
            await runtime.check(provider)
            automatic = await runtime.resolvedExecutable(provider)?.path ?? "Automatic: not found"
        }
    }

    @ViewBuilder private var statusIcon: some View {
        if runtime.checking.contains(provider) {
            if themes.style == .vscode { SpinningCodicon(name: "loading", size: 16, color: .foreground).frame(width: 16, height: 16) }
            else { ProgressView().controlSize(.small).frame(width: 16, height: 16) }
        } else if case .signedIn = runtime.signIns[provider] {
            WorkbenchGlyph(codicon: "pass-filled", symbol: "checkmark.circle.fill", color: .testingIconPassed)
        } else if statusFailed {
            WorkbenchGlyph(codicon: "error", symbol: "exclamationmark.circle.fill", color: .errorForeground)
        }
    }

    private var statusFailed: Bool {
        switch runtime.signIns[provider] {
        case .signedIn: false
        case .signedOut, .unknown: true
        case nil: runtime.connections[provider] != nil
        }
    }

    private var loginArea: some View {
        VStack(alignment: .leading, spacing: 8) {
            if runtime.loginURL != nil {
                HStack {
                    Text("Your browser should show \(provider.company)'s sign-in page. If it did not open:").font(.ui(13))
                    Button("Open Sign-In Page", action: runtime.openLoginPage).workbenchButton()
                }
            }
            ScrollView {
                Text(runtime.loginMessage).font(.code(12)).textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }.frame(maxHeight: 110)
            HStack {
                WorkbenchTextField(placeholder: "Code, if the sign-in page shows one to paste here", text: $code, onSubmit: sendCode)
                Button("Submit Code", action: sendCode).workbenchButton(.primary).disabled(code.isEmpty)
                Button("Cancel Sign-In", action: runtime.endLogin).workbenchButton()
            }
            if let command = runtime.loginCommand {
                HStack(spacing: 6) {
                    Text("Or in Terminal:").font(.ui(12))
                    Text(command).font(.code(12)).textSelection(.enabled)
                    Button("Copy") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(command, forType: .string) }.workbenchButton()
                }.foregroundStyle(theme[.descriptionForeground])
            }
        }
        .padding(10).background(theme[.textCodeBlockBackground], in: RoundedRectangle(cornerRadius: themes.style == .vscode ? 4 : 6))
    }

    private func sendCode() {
        let value = code.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }
        runtime.loginProcess?.send(value); code = ""
    }

    private func save() {
        let typed = CLIEnvironment.expandingTilde(path)
        path = typed
        UserDefaults.standard.set(typed, forKey: "questions.\(provider.rawValue).path")
        UserDefaults.standard.set(model.trimmingCharacters(in: .whitespacesAndNewlines), forKey: "questions.\(provider.rawValue).model")
        Task {
            await runtime.check(provider)
            automatic = await runtime.resolvedExecutable(provider)?.path ?? "Automatic: not found"
        }
    }
}

/// OpenAI, Anthropic and Gemini: the reader's own key, kept in the Keychain. Nothing is sent until Check or a question.
struct APIConnectionPane: View {
    @Bindable var runtime: QuestionRuntime
    let provider: QuestionProvider
    @Environment(\.theme) private var theme
    @State private var themes = ThemeManager.shared
    @State private var key = ""
    @State private var replacing = false
    @State private var model = ""
    @State private var problem: String?

    var body: some View {
        let saved = runtime.keyPresence[provider] == true
        VStack(alignment: .leading, spacing: 14) {
            Text("Lemma sends your question straight to \(provider.company) with your own API key. Usage is billed to your \(provider.company) account; Lemma has no account or server of its own.")
                .font(.ui(13)).lineSpacing(2).fixedSize(horizontal: false, vertical: true)
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 10) {
                GridRow {
                    Text("API key").font(.ui(13)).foregroundStyle(theme[.descriptionForeground])
                    if saved && !replacing {
                        HStack(spacing: 8) {
                            WorkbenchGlyph(codicon: "key", symbol: "key.fill", color: .testingIconPassed, size: 14)
                            Text("Saved in your Keychain").font(.ui(13))
                            Spacer(minLength: 8)
                            Button("Replace…") { replacing = true; problem = nil }.workbenchButton()
                            Button("Remove", role: .destructive, action: remove).workbenchButton()
                        }
                    } else {
                        HStack(spacing: 8) {
                            WorkbenchTextField(placeholder: "Paste your \(provider.company) API key", text: $key, secure: true,
                                               accessibilityLabel: "\(provider.company) API key", onSubmit: save)
                            Button("Save", action: save).workbenchButton(.primary).disabled(key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                            if replacing { Button("Cancel") { replacing = false; key = "" }.workbenchButton() }
                        }
                    }
                }
                GridRow {
                    Text("Model").font(.ui(13)).foregroundStyle(theme[.descriptionForeground])
                    HStack(spacing: 8) {
                        WorkbenchTextField(placeholder: provider.defaultModel, text: $model, accessibilityLabel: "\(provider.label) model", onSubmit: applyModel)
                        modelMenu
                        Button("Apply", action: applyModel).workbenchButton()
                    }
                }
            }
            HStack(spacing: 10) {
                Button("Check") { Task { await runtime.checkKey(provider) } }.workbenchButton().disabled(!saved || runtime.checking.contains(provider))
                if runtime.checking.contains(provider) {
                    if themes.style == .vscode { SpinningCodicon(name: "loading", size: 16, color: .foreground).frame(width: 16, height: 16) }
                    else { ProgressView().controlSize(.small) }
                }
                if let text = problem ?? runtime.apiStatus[provider] {
                    Text(text).font(.ui(13)).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                        .foregroundStyle(problem != nil || runtime.apiStatusFailed.contains(provider) ? theme[.errorForeground] : theme[.foreground])
                }
                Spacer(minLength: 8)
                if let page = provider.apiKeyPage {
                    WorkbenchLink(title: "Get an API key", codicon: "link-external", symbol: "arrow.up.right.square") { NSWorkspace.shared.open(page) }
                        .help(page.absoluteString)
                }
            }
            Text("Check sends one request to \(provider.apiHost ?? provider.company) that confirms the key and the model without generating text. Nothing is sent until you click Check or ask a question. Leave the model empty for \(provider.defaultModel).")
                .font(.ui(12)).foregroundStyle(theme[.descriptionForeground]).fixedSize(horizontal: false, vertical: true)
        }
        .task(id: provider) {
            model = runtime.chosenModel(provider); key = ""; replacing = false; problem = nil
            runtime.refreshKeys()
        }
    }

    /// The suggested models, in a native menu under a button drawn as the others are.
    @ViewBuilder private var modelMenu: some View {
        if themes.style == .vscode {
            VSMenu(items: {
                provider.suggestedModels.map { choice in .action("\(choice.id): \(choice.note)", checked: choice.id == model) { model = choice.id; applyModel() } }
            }) {
                HStack(spacing: 4) { Text("Choose"); Codicon("chevron-down", size: 12) }
                    .font(.ui(12)).foregroundStyle(theme[.buttonSecondaryForeground])
                    .padding(.horizontal, 8).frame(height: 26)
                    .background(RoundedRectangle(cornerRadius: 4).fill(theme[.buttonSecondaryBackground]))
                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(theme.border(.buttonBorder), lineWidth: 1))
            }
            .fixedSize()
            .help("Models \(provider.company) suggests")
        } else {
            Menu("Choose") {
                ForEach(provider.suggestedModels, id: \.self) { choice in
                    Button("\(choice.id): \(choice.note)") { model = choice.id; applyModel() }
                }
            }.fixedSize()
        }
    }

    private func save() {
        do { try runtime.saveKey(key, for: provider); key = ""; replacing = false; problem = nil }
        catch { problem = error.localizedDescription }
    }

    private func remove() {
        do { try runtime.removeKey(for: provider); problem = nil } catch { problem = error.localizedDescription }
    }

    private func applyModel() {
        let value = model.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            if !value.isEmpty { _ = try APIRequestBuilder.validatedModel(value, provider: provider) }
            UserDefaults.standard.set(value, forKey: "questions.\(provider.rawValue).model")
            model = value; problem = nil
            runtime.apiStatus[provider] = "Questions will use \(runtime.model(for: provider))."; runtime.apiStatusFailed.remove(provider)
        } catch { problem = error.localizedDescription }
    }
}

/// The Chrome companion: an optional extension for arXiv Quick Add, set up once. It is not an assistant.
struct ChromeCompanionPane: View {
    @Bindable var store: StudyStore
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Chrome Companion").font(.ui(15, weight: .semibold))
            Text("Optional: add the paper from Chrome's active arXiv tab. Questions do not need it.")
                .font(.ui(13)).lineSpacing(2).fixedSize(horizontal: false, vertical: true)
            step(1, "Prepare the connection between Chrome and Lemma.") {
                Button("Prepare Connection", action: store.installChromeHost).workbenchButton()
            }
            step(2, "In Chrome's Extensions page, turn on Developer mode, choose Load unpacked, and pick the companion folder.") {
                Button("Extensions") { store.openChrome(URL(string: "chrome://extensions/")!) }.workbenchButton()
                Button("Show Companion Folder") { if let url = store.companionURL { NSWorkspace.shared.activateFileViewerSelecting([url]) } }.workbenchButton()
            }
        }
    }

    private func step<Actions: View>(_ number: Int, _ text: String, @ViewBuilder actions: () -> Actions) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(number)").font(.ui(11, weight: .semibold)).monospacedDigit().foregroundStyle(theme[.foreground])
                .frame(width: 18, height: 18).background(Circle().fill(theme[.foreground].opacity(0.1)))
            VStack(alignment: .leading, spacing: 8) {
                Text(text).font(.ui(13)).fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 8) { actions() }
            }
        }
    }
}

/// Settings editor: which API keys are saved, and the way to manage them. The keys themselves are never shown.
struct AssistantKeysControl: View {
    @Bindable var store: StudyStore
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(QuestionProvider.allCases.filter { $0.kind == .api }) { provider in
                HStack(spacing: 8) {
                    Codicon("key", size: 14)
                    Text(provider.label).font(.ui(13))
                    Text(store.questions.keyPresence[provider] == true ? "Saved in your Keychain" : "No key")
                        .font(.ui(12)).foregroundStyle(theme[.descriptionForeground])
                }
            }
            Button("Manage in Assistants…") {
                store.questions.connectionProvider = QuestionProvider.allCases.first { $0.kind == .api && store.questions.keyPresence[$0] == true } ?? .openAI
                store.questions.panel = "connections"
                store.showBrowserSetup = true
            }.buttonStyle(.vsSecondary)
        }
        .onAppear { store.questions.refreshKeys() }
    }
}
