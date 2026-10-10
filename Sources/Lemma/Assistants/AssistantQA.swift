import AppKit
import LemmaCore

/// QA actions for the Assistants sheet and the question sheet (QA copies only; see QAHooks). They never send a
/// question, never run Check, and only ever write keys to the in-memory store a QA copy uses.
@MainActor
extension StudyStore {
    func performAssistantQA(_ action: String, info: [String: String]) async throws {
        let provider = info["provider"].flatMap(QuestionProvider.init(rawValue:))
        switch action {
        case "assistants":
            // panel=connections|requests provider=<raw value>
            questions.panel = info["panel"] ?? "connections"
            if let provider { questions.connectionProvider = provider }
            showBrowserSetup = true
        case "assistantsClose": showBrowserSetup = false
        case "assistantKey":
            guard let provider, questions.keys is MemoryAPIKeyStore else { throw QAHooks.QAError.missing("an in-memory key store") }
            if info["remove"] == "1" { try questions.removeKey(for: provider) } else { try questions.saveKey(info["value"] ?? "qa-not-a-real-key", for: provider) }
        case "assistantSignIn":
            // Only with an executable chosen in the QA copy's settings (a stand-in CLI), never a real sign-in.
            guard let provider, !questions.preferredPath(provider).isEmpty else { throw QAHooks.QAError.missing("a chosen stand-in executable") }
            let methods = QuestionCLI.signInMethods(provider)
            let index = Int(info["index"] ?? "") ?? 0
            guard methods.indices.contains(index) else { throw QAHooks.QAError.missing("sign-in method \(index)") }
            questions.signIn(provider, method: methods[index])
        case "assistantConnectWeb": questions.connectWeb()
        case "assistantCloseWeb": questions.closeWeb()
        case "assistantState":
            var state: [String: Any] = ["panel": questions.panel, "provider": questions.connectionProvider.rawValue,
                                        "webLoaded": questions.webLoaded, "webSession": questions.hasWebSession,
                                        "webURL": questions.hasWebSession ? (questions.web.view.url?.absoluteString ?? "") : "",
                                        "loginProvider": questions.loginProvider?.rawValue ?? "", "loginURL": questions.loginURL?.absoluteString ?? ""]
            state["connections"] = Dictionary(uniqueKeysWithValues: questions.connections.map { ($0.key.rawValue, $0.value) })
            state["keys"] = Dictionary(uniqueKeysWithValues: questions.keyPresence.map { ($0.key.rawValue, $0.value) })
            state["apiStatus"] = Dictionary(uniqueKeysWithValues: questions.apiStatus.map { ($0.key.rawValue, $0.value) })
            state["jobs"] = questions.jobs.map { ["provider": $0.provider.rawValue, "finished": $0.finished, "failed": $0.failed, "message": $0.message] }
            guard let directory = QAHooks.shared?.directory else { return }
            try JSONSerialization.data(withJSONObject: state, options: [.prettyPrinted, .sortedKeys])
                .write(to: directory.appendingPathComponent("\(info["name"] ?? "assistants").json"))
        case "questionSheet":
            // Opens the full draft for the current (or first) note; with a selection and no note, saves one first.
            if workspace?.notes.isEmpty != false, reader.hasSelection {
                addNote()
                updateNote { $0.question = info["question"] ?? "Why does this hold?" }
            }
            if selectedNoteID == nil { selectedNoteID = workspace?.notes.first?.id }
            showQuestion = selectedNoteID != nil
        case "questionSheetClose": showQuestion = false
        default: throw QAHooks.QAError.missing("action \(action)")
        }
    }
}
