import SwiftUI
import AppKit
import LemmaCore

/// Both sign-in and question follow-up belong to the study window.
struct AssistantPane: View {
    @Bindable var store: StudyStore
    @Environment(\.theme) private var theme
    @AppStorage(LemmaPreferences.questionProvider) private var defaultProvider = QuestionProvider.chatGPTWeb.rawValue
    @State private var showChrome = false
    private var runtime: QuestionRuntime { store.questions }

    /// The sheet fits a 13-inch screen: it never asks for more height than the screen has.
    private static var height: CGFloat { min(700, max(480, (NSScreen.main?.visibleFrame.height ?? 800) - 70)) }

    var body: some View {
        @Bindable var runtime = runtime
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Assistants").font(.title2.weight(.semibold))
                Spacer()
                Picker("View", selection: $runtime.panel) {
                    Text("Questions").tag("requests")
                    Text("Connections").tag("connections")
                }.pickerStyle(.segmented).frame(width: 260)
                Button("Continue reading") { store.showBrowserSetup = false }.keyboardShortcut(.cancelAction)
            }
            Divider()
            if runtime.panel == "requests" { requests }
            else { connections }
        }
        .padding(20).frame(width: 900, height: Self.height)
        .foregroundStyle(theme[.foreground])
        .background(theme[.editorBackground])
        .onAppear { runtime.refreshKeys() }
        .onDisappear { runtime.endLogin() }
    }

    @ViewBuilder private var requests: some View {
        @Bindable var runtime = runtime
        if let job = runtime.selected {
            HStack {
                Picker("Question", selection: $runtime.selectedID) {
                    ForEach(runtime.jobs) { item in
                        Text("\(item.provider.label) · \(item.packet.prompt.components(separatedBy: "Question:").last?.trimmingCharacters(in: .whitespacesAndNewlines).prefix(65) ?? item.packet.prompt.prefix(65))").tag(Optional(item.id))
                    }
                }.labelsHidden().frame(maxWidth: .infinity, alignment: .leading)
                if !job.finished { Button("Cancel question") { runtime.cancel(job.id) } }
                Button("Go to source note") {
                    if let id = job.packet.workspaceID, let book = store.library.first(where: { $0.id == id }) {
                        if store.workspace?.id != id { store.reopen(book) }
                        store.selectedNoteID = job.packet.noteID; store.revealStudy(); store.studySection = .notes
                        store.showBrowserSetup = false
                    }
                }
            }
            HStack(spacing: 8) {
                if !job.finished { ProgressView().controlSize(.small) }
                Image(systemName: job.failed ? "exclamationmark.circle" : job.finished ? "checkmark.circle" : "text.bubble")
                Text(job.message).font(.callout).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                Spacer()
                Text(job.provider.label + (job.model.map { " · \($0)" } ?? "")).font(.caption)
            }.foregroundStyle(job.failed ? theme[.errorForeground] : theme[.foreground])
            if job.provider == .chatGPTWeb && !job.finished {
                ChatGPTPageView(runtime: runtime).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if !job.answer.isEmpty {
                ScrollView {
                    if job.finished && !job.failed { MathPreview(text: job.answer) }
                    else { Text(job.answer).font(.body).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }
                }
            } else {
                Spacer()
                Text(job.failed ? "The source note is kept. Check the connection, then ask again from the note." : "Your question is running. You can close this panel and continue reading; Lemma saves the completed answer with its source.")
                    .font(.body).frame(maxWidth: 500, alignment: .leading)
                if job.failed { Button("Check connection") { runtime.connectionProvider = job.provider; runtime.panel = "connections" } }
                Spacer()
            }
        } else {
            Spacer()
            Text("Select a passage and press ⌘K to ask a question. Your answers appear here and beside their source notes.")
                .frame(maxWidth: 510, alignment: .leading)
            Spacer()
        }
    }

    private var connections: some View {
        @Bindable var runtime = runtime
        let provider = runtime.connectionProvider
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 16) {
                AssistantProviderList(runtime: runtime, defaultProvider: defaultProvider).frame(width: 190)
                Divider()
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(provider.label).font(.title3.weight(.semibold))
                        Spacer()
                        if defaultProvider == provider.rawValue { Text("Default for questions").font(.caption).foregroundStyle(theme[.descriptionForeground]) }
                        else { Button("Use by default") { defaultProvider = provider.rawValue } }
                    }
                    switch provider.kind {
                    case .web: WebConnectionPane(runtime: runtime)
                    case .cli: CLIConnectionPane(runtime: runtime, provider: provider)
                    case .api: APIConnectionPane(runtime: runtime, provider: provider)
                    }
                    Label(provider.privacySummary, systemImage: "lock.shield").font(.caption)
                        .foregroundStyle(theme[.descriptionForeground]).fixedSize(horizontal: false, vertical: true)
                        .accessibilityLabel("What is sent: \(provider.privacySummary)")
                }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            DisclosureGroup("Chrome companion for arXiv Quick Add", isExpanded: $showChrome) {
                HStack {
                    Text("Optional: add the paper from Chrome's active arXiv tab.").font(.caption)
                    Button("Prepare connection", action: store.installChromeHost)
                    Button("Show companion folder") { if let url = store.companionURL { NSWorkspace.shared.activateFileViewerSelecting([url]) } }
                    Button("Extensions") { store.openChrome(URL(string: "chrome://extensions/")!) }
                }.padding(.top, 8)
            }.font(.caption)
        }
    }
}
