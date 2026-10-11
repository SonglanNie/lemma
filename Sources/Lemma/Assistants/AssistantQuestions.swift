import SwiftUI
import AppKit
import LemmaCore

/// The questions asked in this session, newest first: what each asked, of whom, and how it stands.
struct QuestionJobList: View {
    @Bindable var runtime: QuestionRuntime
    @Environment(\.theme) private var theme

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 1) {
                ForEach(runtime.jobs) { job in row(job) }
            }
            .padding(.vertical, 6)
        }
    }

    private func row(_ job: QuestionJob) -> some View {
        let selected = runtime.selectedID == job.id
        return WorkbenchListRow(selected: selected) { runtime.selectedID = job.id } content: {
            HStack(alignment: .top, spacing: 9) {
                QuestionJobStatusIcon(job: job).padding(.top, 1)
                VStack(alignment: .leading, spacing: 2) {
                    Text(job.title.isEmpty ? "Question" : job.title).font(.ui(13)).lineLimit(2).multilineTextAlignment(.leading)
                    Text("\(job.provider.label) · \(job.startedAt.formatted(date: .omitted, time: .shortened))").font(.ui(11.5))
                        .foregroundStyle(selected ? theme[.listActiveSelectionForeground].opacity(0.75) : theme[.descriptionForeground])
                }
                Spacer(minLength: 0)
            }
        }
        .accessibilityLabel("\(job.title), \(job.provider.label), \(QuestionJobStatusIcon.state(job))")
    }
}

/// Running, answered, failed or cancelled, as a small icon. The spinner exists only while the question runs.
struct QuestionJobStatusIcon: View {
    let job: QuestionJob
    @State private var themes = ThemeManager.shared

    static func state(_ job: QuestionJob) -> String {
        !job.finished ? "running" : job.failureReason == "cancelled" ? "cancelled" : job.failed ? "failed" : "answered"
    }

    var body: some View {
        switch Self.state(job) {
        case "running":
            if themes.style == .vscode { SpinningCodicon(name: "loading", size: 16, color: .foreground).frame(width: 16, height: 16) }
            else { ProgressView().controlSize(.small).scaleEffect(0.8).frame(width: 16, height: 16) }
        case "cancelled": WorkbenchGlyph(codicon: "circle-slash", symbol: "xmark.circle", color: .descriptionForeground)
        case "failed": WorkbenchGlyph(codicon: "error", symbol: "exclamationmark.circle.fill", color: .errorForeground)
        default: WorkbenchGlyph(codicon: "pass-filled", symbol: "checkmark.circle.fill", color: .testingIconPassed)
        }
    }
}

/// One question: what it asked and how it was sent, its state with what can be done next, then the ChatGPT page or
/// the answer, edge to edge below a hairline.
struct QuestionJobDetail: View {
    @Bindable var store: StudyStore
    let job: QuestionJob
    @Environment(\.theme) private var theme
    @State private var themes = ThemeManager.shared
    private var runtime: QuestionRuntime { store.questions }

    /// The embedded page stays on view while it can still help: during the question, and after a failure, so the
    /// reader sees the draft or the sign-in ChatGPT shows. It is never created here.
    private var showsPage: Bool {
        job.provider == .chatGPTWeb && runtime.hasWebSession && (!job.finished || (job.failed && job.failureReason != "cancelled" && runtime.latestWebJob?.id == job.id))
    }

    private var showsAnswer: Bool { !job.answer.isEmpty && !(job.failed && job.failureReason == "cancelled") }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 16) {
                header
                status
            }
            .padding(.horizontal, 24).padding(.top, 18).padding(.bottom, 16)
            if showsPage {
                ChatGPTPageView(runtime: runtime)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .overlay(alignment: .top) {
                        ZStack(alignment: .top) {
                            Rectangle().fill(theme.hairline(.panelBorder)).frame(height: 1)
                            // VS Code's progress line along the top of the part that is working.
                            if !job.finished && themes.style == .vscode { VSProgressLine() }
                        }
                    }
            } else if showsAnswer {
                ScrollView {
                    answer
                        .frame(maxWidth: 700, alignment: .leading)
                        .padding(.horizontal, 24).padding(.top, 18).padding(.bottom, 24)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .overlay(alignment: .top) { Rectangle().fill(theme.hairline(.panelBorder)).frame(height: 1) }
            } else {
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    @ViewBuilder private var answer: some View {
        if job.finished && !job.failed { MathPreview(text: job.answer) }
        else { Text(job.answer).font(.ui(13)).lineSpacing(3).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(job.title.isEmpty ? "Question" : job.title).font(.ui(15, weight: .semibold)).lineLimit(3)
                .textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(details).font(.ui(12)).foregroundStyle(theme[.descriptionForeground]).lineLimit(1).truncationMode(.middle)
                Spacer(minLength: 8)
                WorkbenchLink(title: "Go to Source Note", codicon: "go-to-file", symbol: "arrow.up.forward.square", action: goToSource)
                    .disabled(job.packet.workspaceID.flatMap { id in store.library.first { $0.id == id } } == nil)
                    .help("Close Assistants and show the note this question belongs to")
            }
        }
    }

    /// “ChatGPT Web · 3 images · asked at 18:18”.
    private var details: String {
        var parts = [job.provider.label + (job.model.map { " · \($0)" } ?? "")]
        parts.append(job.packet.images.count == 1 ? "1 image" : "\(job.packet.images.count) images")
        if job.provider == .chatGPTWeb { parts.append(job.packet.mode == .draft ? "reviewed before sending" : "sent at once") }
        parts.append("asked at \(job.startedAt.formatted(date: .omitted, time: .shortened))")
        return parts.joined(separator: " · ")
    }

    @ViewBuilder private var status: some View {
        if !job.finished {
            statusLine {
                if themes.style == .vscode { SpinningCodicon(name: "loading", size: 16, color: .foreground).frame(width: 16, height: 16) }
                else { ProgressView().controlSize(.small).frame(width: 16, height: 16) }
            } message: {
                Text(job.message)
            } actions: {
                Button("Cancel Question") { runtime.cancel(job.id) }.workbenchButton(.secondary)
            }
        } else if job.failureReason == "cancelled" {
            statusLine {
                WorkbenchGlyph(codicon: "circle-slash", symbol: "xmark.circle", color: .descriptionForeground)
            } message: {
                Text("Question cancelled. Its note is kept; the passage can be asked about again.")
            } actions: { askAgain(.secondary) }
        } else if job.failed {
            failure
        } else {
            statusLine {
                WorkbenchGlyph(codicon: "pass-filled", symbol: "checkmark.circle.fill", color: .testingIconPassed)
            } message: {
                Text(job.message)
            } actions: {
                if let raw = savedConversation, let url = URL(string: raw) {
                    Button("Open Conversation") { runtime.showConversation(url) }.workbenchButton(.secondary).disabled(runtime.webBusy)
                }
            }
        }
    }

    /// A failure, in VS Code's validation colours: what happened, what to do, and the actions that fit, the likeliest
    /// one first and in the button colour.
    private var failure: some View {
        HStack(alignment: .top, spacing: 10) {
            WorkbenchGlyph(codicon: "error", symbol: "exclamationmark.triangle.fill", color: .errorForeground).padding(.top, 1)
            VStack(alignment: .leading, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(job.message).font(.ui(13)).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                    if let hint { Text(hint).font(.ui(12)).foregroundStyle(theme[.descriptionForeground]).fixedSize(horizontal: false, vertical: true) }
                }
                HStack(spacing: 8) {
                    if job.failureReason == "draft" {
                        Button("Replace Draft and Ask Again") { runtime.retry(job, replacingDraft: true) }.workbenchButton(.primary).disabled(!canAskAgain)
                            .help("Clears ChatGPT's composer, then prepares this question in it")
                        askAgain(.secondary)
                    } else {
                        askAgain(.primary)
                    }
                    if job.provider.kind != .web || job.failureReason == "load" {
                        Button("Check Connection") { runtime.connectionProvider = job.provider; runtime.panel = "connections" }.workbenchButton(.secondary)
                    }
                }
                .fixedSize()
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(theme[.inputValidationErrorBackground], in: RoundedRectangle(cornerRadius: themes.style == .vscode ? 4 : 8))
        .overlay(RoundedRectangle(cornerRadius: themes.style == .vscode ? 4 : 8).stroke(theme.border(.inputValidationErrorBorder), lineWidth: 1))
    }

    /// A state on one line: its icon, the message and the actions beside it, with no box around them.
    private func statusLine<Icon: View, Message: View, Actions: View>(@ViewBuilder icon: () -> Icon, @ViewBuilder message: () -> Message,
                                                                    @ViewBuilder actions: () -> Actions) -> some View {
        HStack(alignment: .center, spacing: 10) {
            icon().frame(width: 16, height: 16)
            message().font(.ui(13)).fixedSize(horizontal: false, vertical: true).frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 8) { actions() }.fixedSize()
        }
        .frame(minHeight: 26)
    }

    /// What to do about a ChatGPT failure, when the message alone does not say.
    private var hint: String? {
        switch job.failureReason {
        case "draft": "ChatGPT shows unsent text again in every new chat. Clear it in the page below, or let Lemma replace it."
        case "signedOut": "Sign in to ChatGPT in the page below, then ask again."
        case "insert": "Review first, in the question's sending choice, lets you check the text before it is sent."
        default: nil
        }
    }

    private var savedConversation: String? {
        guard job.provider == .chatGPTWeb, let id = job.packet.workspaceID else { return nil }
        let book = store.workspace?.id == id ? store.workspace : store.library.first { $0.id == id }
        return book?.notes.first { $0.id == job.packet.noteID }?.explanation?.conversationURL
    }

    private var canAskAgain: Bool {
        let busy = job.provider == .chatGPTWeb && runtime.webBusy
        let book = job.packet.workspaceID.flatMap { id in store.workspace?.id == id ? store.workspace : store.library.first { $0.id == id } }
        let note = book?.notes.first { $0.id == job.packet.noteID }
        return !busy && note != nil && note?.pendingRequestID == nil
    }

    private func askAgain(_ kind: WorkbenchButtonKind) -> some View {
        Button("Ask Again") { runtime.retry(job) }.workbenchButton(kind).disabled(!canAskAgain)
            .help("Sends the same draft and images again, and saves the answer to the same note")
    }

    private func goToSource() {
        guard let id = job.packet.workspaceID, let book = store.library.first(where: { $0.id == id }) else { return }
        if store.workspace?.id != id { store.reopen(book) }
        store.selectedNoteID = job.packet.noteID; store.revealStudy(); store.studySection = .notes
        store.showBrowserSetup = false
    }
}
