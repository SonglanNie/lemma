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

/// The six assistants, grouped by how Lemma reaches them.
struct AssistantProviderList: View {
    @Bindable var runtime: QuestionRuntime
    let defaultProvider: String
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            group("In Lemma", [.chatGPTWeb])
            group("Installed command-line tool", [.codex, .claudeCode])
            group("Your API key", [.openAI, .anthropic, .gemini])
            Spacer()
        }
    }

    private func group(_ title: String, _ providers: [QuestionProvider]) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title.uppercased()).font(.caption2.weight(.semibold)).foregroundStyle(theme[.descriptionForeground]).padding(.leading, 8).padding(.bottom, 2)
            ForEach(providers) { provider in row(provider) }
        }
    }

    private func row(_ provider: QuestionProvider) -> some View {
        let selected = runtime.connectionProvider == provider
        let ready: Bool = switch provider.kind {
        case .api: runtime.keyPresence[provider] == true
        case .cli: if case .signedIn = runtime.signIns[provider] { true } else { false }
        case .web: runtime.webLoaded
        }
        return Button { runtime.connectionProvider = provider } label: {
            HStack(spacing: 6) {
                Text(provider.label).lineLimit(1)
                Spacer(minLength: 4)
                if defaultProvider == provider.rawValue { Text("Default").font(.caption2).foregroundStyle(theme[.descriptionForeground]) }
                if ready { Image(systemName: "checkmark.circle.fill").font(.caption).foregroundStyle(theme[.testingIconPassed]).accessibilityLabel("Ready") }
            }
            .padding(.horizontal, 8).padding(.vertical, 5)
            .foregroundStyle(selected ? theme[.listActiveSelectionForeground] : theme[.foreground])
            .background(selected ? theme[.listActiveSelectionBackground] : .clear, in: RoundedRectangle(cornerRadius: 5))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// ChatGPT Web: nothing loads until the reader clicks Connect (or asks a ChatGPT question).
struct WebConnectionPane: View {
    @Bindable var runtime: QuestionRuntime
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("ChatGPT Web runs chatgpt.com inside Lemma with your usual account, model choice and limits. Its sign-in stays in this embedded browser, separate from Safari and Chrome.")
                .font(.callout).fixedSize(horizontal: false, vertical: true)
            Text("Sign in with your email address. Google and Apple sign-in may refuse to work inside an embedded browser; email sign-in works.")
                .font(.caption).foregroundStyle(theme[.descriptionForeground]).fixedSize(horizontal: false, vertical: true)
            if runtime.webLoaded || runtime.webBusy {
                HStack {
                    Button("New chat") { runtime.showConversation(ChatGPTSession.home) }.disabled(runtime.webBusy)
                    Button("Reload") { runtime.web.view.reload() }.disabled(runtime.webBusy)
                    Button("Close page") { runtime.closeWeb() }.disabled(runtime.webBusy)
                        .help("Unload chatgpt.com from Lemma. You stay signed in.")
                    Spacer()
                    Text("Questions use your normal ChatGPT access and limits.").font(.caption)
                }
                ChatGPTPageView(runtime: runtime).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Spacer()
                VStack(spacing: 8) {
                    Button("Connect ChatGPT") { runtime.connectWeb() }.controlSize(.large)
                    Text("Opens chatgpt.com here. Nothing is loaded until you click.").font(.caption).foregroundStyle(theme[.descriptionForeground])
                }.frame(maxWidth: .infinity)
                Spacer()
            }
        }
    }
}

/// Codex and Claude Code: the reader's own installed CLI with whatever sign-in it already has.
struct CLIConnectionPane: View {
    @Bindable var runtime: QuestionRuntime
    let provider: QuestionProvider
    @Environment(\.theme) private var theme
    @State private var path = ""
    @State private var model = ""
    @State private var code = ""
    /// Where automatic discovery finds the CLI, looked up when the pane appears rather than on every redraw.
    @State private var automatic = "Automatic"

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Lemma runs your installed \(provider.label) and uses the sign-in it already has: \(provider.accountKinds). You stay here while it answers.")
                .font(.callout).fixedSize(horizontal: false, vertical: true)
            HStack {
                if runtime.checking.contains(provider) { ProgressView().controlSize(.small) }
                Text(runtime.connections[provider] ?? "Checking the installed CLI…").font(.callout).textSelection(.enabled)
                    .foregroundStyle(statusFailed ? theme[.errorForeground] : theme[.foreground]).fixedSize(horizontal: false, vertical: true)
                Spacer()
                Button("Check again") { Task { await runtime.check(provider) } }.disabled(runtime.checking.contains(provider))
            }
            HStack {
                ForEach(QuestionCLI.signInMethods(provider), id: \.self) { method in
                    Button(method.title) { runtime.signIn(provider, method: method) }.disabled(runtime.loginProvider != nil)
                }
                if let other = runtime.loginProvider, other != provider {
                    Text("Signing in to \(other.label)…").font(.caption).foregroundStyle(theme[.descriptionForeground])
                    Button("Cancel that sign-in", action: runtime.endLogin).controlSize(.small)
                }
            }
            Text("Sign-in opens \(provider.company)'s own page in your default browser, and \(provider.label) keeps the credentials. You can also sign in in Terminal, or set \(provider.label) up with an API key; Lemma uses it as it is.")
                .font(.caption).foregroundStyle(theme[.descriptionForeground]).fixedSize(horizontal: false, vertical: true)
            if runtime.loginProvider == provider { loginArea }
            Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 10) {
                GridRow {
                    Text("Executable")
                    TextField(automatic, text: $path)
                        .onSubmit(save).accessibilityLabel("\(provider.label) executable path")
                    Button("Choose…") {
                        let panel = NSOpenPanel(); panel.canChooseFiles = true; panel.canChooseDirectories = false
                        panel.treatsFilePackagesAsDirectories = true; panel.showsHiddenFiles = true
                        if panel.runModal() == .OK, let url = panel.url { path = url.path; save() }
                    }
                }
                GridRow {
                    Text("Model")
                    TextField("CLI default", text: $model).onSubmit(save).accessibilityLabel("\(provider.label) model")
                    Button("Apply", action: save)
                }
            }
            Text("Leave both empty for automatic discovery and the CLI's default model. Lemma looks in your login shell's PATH, Homebrew, ~/.local/bin, Volta, nvm, fnm, asdf and mise, and runs the CLI with its own folder first on PATH so it finds Node.")
                .font(.caption).foregroundStyle(theme[.descriptionForeground]).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .task(id: provider) {
            path = runtime.preferredPath(provider)
            model = runtime.chosenModel(provider)
            await runtime.check(provider)
            automatic = await runtime.resolvedExecutable(provider)?.path ?? "Automatic: not found"
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
                    Text("Your browser should show \(provider.company)'s sign-in page. If it did not open:").font(.callout)
                    Button("Open sign-in page", action: runtime.openLoginPage)
                }
            }
            ScrollView {
                Text(runtime.loginMessage).font(.system(size: 12, design: .monospaced)).textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }.frame(maxHeight: 110)
            HStack {
                TextField("Code, if the sign-in page shows one to paste here", text: $code).onSubmit(sendCode)
                Button("Submit code", action: sendCode).disabled(code.isEmpty)
                Button("Cancel sign-in", action: runtime.endLogin)
            }
            if let command = runtime.loginCommand {
                HStack(spacing: 6) {
                    Text("Or in Terminal:").font(.caption)
                    Text(command).font(.caption.monospaced()).textSelection(.enabled)
                    Button("Copy") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(command, forType: .string) }.controlSize(.small)
                }.foregroundStyle(theme[.descriptionForeground])
            }
        }
        .padding(10).background(theme[.textCodeBlockBackground], in: RoundedRectangle(cornerRadius: 6))
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
    @State private var key = ""
    @State private var replacing = false
    @State private var model = ""
    @State private var problem: String?

    var body: some View {
        let saved = runtime.keyPresence[provider] == true
        VStack(alignment: .leading, spacing: 12) {
            Text("Lemma sends your question straight to \(provider.company) with your own API key. Usage is billed to your \(provider.company) account; Lemma has no account or server of its own.")
                .font(.callout).fixedSize(horizontal: false, vertical: true)
            Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 12) {
                GridRow {
                    Text("API key")
                    if saved && !replacing {
                        HStack(spacing: 10) {
                            Label("Saved in your Keychain", systemImage: "key.fill")
                            Button("Replace…") { replacing = true; problem = nil }
                            Button("Remove", role: .destructive, action: remove)
                        }
                    } else {
                        HStack {
                            SecureField("Paste your \(provider.company) API key", text: $key).onSubmit(save)
                                .accessibilityLabel("\(provider.company) API key")
                            Button("Save", action: save).disabled(key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                            if replacing { Button("Cancel") { replacing = false; key = "" } }
                        }
                    }
                }
                GridRow {
                    Text("Model")
                    HStack {
                        TextField(provider.defaultModel, text: $model).onSubmit(applyModel).accessibilityLabel("\(provider.label) model")
                        Menu("Choose") {
                            ForEach(provider.suggestedModels, id: \.self) { choice in
                                Button("\(choice.id): \(choice.note)") { model = choice.id; applyModel() }
                            }
                        }.fixedSize()
                        Button("Apply", action: applyModel)
                    }
                }
            }
            HStack(spacing: 10) {
                Button("Check") { Task { await runtime.checkKey(provider) } }.disabled(!saved || runtime.checking.contains(provider))
                if runtime.checking.contains(provider) { ProgressView().controlSize(.small) }
                if let text = problem ?? runtime.apiStatus[provider] {
                    Text(text).font(.callout).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                        .foregroundStyle(problem != nil || runtime.apiStatusFailed.contains(provider) ? theme[.errorForeground] : theme[.foreground])
                }
                Spacer()
                if let page = provider.apiKeyPage { Link("Get an API key", destination: page) }
            }
            Text("Check sends one request to \(provider.apiHost ?? provider.company) that confirms the key and the model without generating text. Nothing is sent until you click Check or ask a question. Leave the model empty for \(provider.defaultModel).")
                .font(.caption).foregroundStyle(theme[.descriptionForeground]).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .task(id: provider) {
            model = runtime.chosenModel(provider); key = ""; replacing = false; problem = nil
            runtime.refreshKeys()
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
