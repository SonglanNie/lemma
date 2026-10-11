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
            // panel=connections|requests provider=<raw value> companion=1 (the Chrome companion's setup)
            questions.panel = info["panel"] ?? "connections"
            if let provider { questions.connectionProvider = provider }
            if info["companion"] == "1" { questions.showsCompanion = true }
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
            state["jobs"] = questions.jobs.map { ["provider": $0.provider.rawValue, "finished": $0.finished, "failed": $0.failed, "message": $0.message,
                                                  "reason": $0.failureReason ?? "", "title": $0.title, "answer": String($0.answer.prefix(4000)), "model": $0.model ?? ""] }
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
        case "assistantSelect":
            // index= (0 is the newest question)
            if let index = info["index"].flatMap(Int.init), questions.jobs.indices.contains(index) { questions.selectedID = questions.jobs[index].id }
        case "assistantFail":
            // Ends the selected running question with a failure, to show the Questions panel's states:
            // reason=draft|signedOut|insert|load|crash|timeout message=…
            guard let job = questions.selected, !job.finished else { throw QAHooks.QAError.missing("a running question") }
            job.failureReason = info["reason"]
            questions.finish(job, result: BrowserResult(requestID: job.id, status: "error", message: info["message"] ?? "The question stopped."))
        case "assistantDemo":
            // Stand-in questions in every state, for snapshots of the Questions panel. Nothing is sent: the jobs are made
            // here, and the ChatGPT page is a local stand-in, so nothing loads from chatgpt.com.
            // jobs=running,failed,cancelled,answered,cli (oldest first; the last is selected).
            demoQuestions(info["jobs"] ?? "cli,cancelled,answered,failed,running")
        case "assistantExplanation":
            // A long stand-in explanation (display equations, a wide tagged one, code) saved on the selected note, or on a
            // new note from the current selection, shown in the Notes inspector.
            if currentNote == nil {
                guard reader.hasSelection else { throw QAHooks.QAError.missing("a selection or a note") }
                addNote()
                updateNote { $0.question = info["question"] ?? "Explain this step." }
            }
            guard let id = selectedNoteID else { throw QAHooks.QAError.missing("a note") }
            updateNote(id: id) { $0.explanation = SavedExplanation(body: Self.demoAnswer, provider: .chatGPTWeb) }
            showStudy = true; studySection = .notes
        default: throw QAHooks.QAError.missing("action \(action)")
        }
    }

    private func demoQuestions(_ kinds: String) {
        let images = [BrowserImage(name: "source.png", label: "The passage", byteCount: 1), BrowserImage(name: "cited-1.png", label: "(4.17)", byteCount: 1)]
        let noteID = currentNote?.id ?? workspace?.notes.first?.id ?? UUID()
        for kind in kinds.split(separator: ",").map(String.init) {
            let provider: QuestionProvider = kind == "cli" ? .claudeCode : .chatGPTWeb
            let title = ["running": "Explain this step.", "failed": "Why does the log of the denominator disappear?", "cancelled": "Give me a hint for this step.",
                         "cli": "What does the decision boundary look like when the variances differ?"][kind] ?? "Explain this step."
            let packet = BrowserPacket(noteID: noteID, mode: .askAndSave, prompt: "Question:\n\(title)\n", images: images, provider: provider, workspaceID: workspace?.id)
            let job = QuestionJob(packet, title: title)
            switch kind {
            case "running": job.message = "Question sent. ChatGPT is answering…"
            case "failed":
                job.finished = true; job.failed = true; job.failureReason = "draft"
                job.message = "ChatGPT's composer already holds an unsent draft, and Lemma left it in place."
            case "cancelled":
                job.finished = true; job.failed = true; job.failureReason = "cancelled"; job.message = "Question cancelled. Its source note is kept."
            default:
                job.finished = true; job.answer = Self.demoAnswer; job.message = "Answer saved beside its source."
                if kind == "cli" { job.model = "claude-opus-5-5" }
            }
            questions.jobs.insert(job, at: 0)
        }
        questions.selectedID = questions.jobs.first?.id
        questions.panel = "requests"
        if kinds.contains("running") || kinds.contains("failed") {
            questions.web.view.loadHTMLString(Self.demoPage, baseURL: nil)
            questions.webLoaded = true
        }
        showBrowserSetup = true
    }

    /// A page drawn like ChatGPT's while it thinks, in both appearances, for the panel's snapshots.
    private static let demoPage = """
    <!doctype html><html><head><meta charset="utf-8"><style>
    :root { color-scheme: light dark; }
    body { margin: 0; height: 100vh; display: flex; flex-direction: column; font: 15px/1.5 -apple-system, sans-serif;
           background: light-dark(#ffffff, #212121); color: light-dark(#0d0d0d, #ececec); }
    header { display: flex; align-items: center; gap: 20px; padding: 14px 18px; color: light-dark(#5d5d5d, #b4b4b4); }
    header i { width: 18px; height: 18px; border: 2px solid currentColor; border-radius: 5px; opacity: .8; }
    header span { flex: 1; }
    main { flex: 1; width: 100%; max-width: 760px; margin: 0 auto; padding: 0 24px; box-sizing: border-box; }
    .user { margin: 8px 0 30px auto; max-width: 68%; padding: 14px 20px; border-radius: 22px; background: light-dark(#f4f4f4, #303030); color: light-dark(#5d5d5d, #b4b4b4); }
    .think { color: light-dark(#8f8f8f, #9b9b9b); margin: 6px 0 10px; } .step { color: light-dark(#5d5d5d, #b4b4b4); }
    footer { padding: 0 24px 12px; } .note { text-align: center; font-size: 12px; color: light-dark(#5d5d5d, #b4b4b4); margin: 8px 0; }
    .composer { max-width: 760px; margin: 0 auto; border-radius: 28px; padding: 14px 18px 10px; background: light-dark(#ffffff, #303030);
                border: 1px solid light-dark(#e3e3e3, transparent); box-shadow: 0 2px 8px rgba(0,0,0,.06); color: light-dark(#8f8f8f, #9b9b9b); }
    .row { display: flex; justify-content: space-between; align-items: center; margin-top: 14px; }
    .stop { width: 34px; height: 34px; border-radius: 17px; background: light-dark(#0d0d0d, #ececec); }
    </style></head><body>
    <header><i></i><i></i><span></span>Share&nbsp;&nbsp;···</header>
    <main><div class="user">Show more ⌄</div><div class="think">Thinking ⌄</div><div class="step">Deriving the classifier</div></main>
    <footer><div class="note">ChatGPT can make mistakes. Check important info.</div>
    <div class="composer">Ask ChatGPT<div class="row"><span>＋</span><span>Extra High ⌄ &nbsp;&nbsp;</span><span class="stop"></span></div></div></footer>
    </body></html>
    """

    /// An answer with what saved explanations carry: paragraphs, bold, lists, inline and display mathematics (one of them
    /// too wide for the inspector, with its tag), and a code block.
    static let demoAnswer = #"""
    The goal is to understand how the posterior probability $p_k(x)$ in (4.17) becomes the **linear discriminant function** $\delta_k(x)$ in (4.18), and then how we obtain the decision boundary in (4.19).

    The key idea is that **we don't need the exact posterior probabilities to classify an observation. We only need to know which one is largest.**

    ## 1. Starting from equation (4.17)

    The book gives:

    $$
    p_k(x) = \frac{\pi_k \frac{1}{\sqrt{2\pi}\sigma} \exp\left(-\frac{(x-\mu_k)^2}{2\sigma^2}\right)}{\sum_{l=1}^K \pi_l \frac{1}{\sqrt{2\pi}\sigma} \exp\left(-\frac{(x-\mu_l)^2}{2\sigma^2}\right)} \tag{4.17}
    $$

    Here:

    - $p_k(x) = P(Y = k \mid X = x)$ is the posterior probability that observation $x$ belongs to class $k$.
    - $\pi_k = P(Y = k)$ is the prior probability of class $k$.
    - $\mu_k$ is the mean of $X$ in class $k$.
    - $\sigma^2$ is the variance of $X$, assumed **identical across all classes**.

    We also assume $\sigma^2 > 0$ and $\pi_k > 0$ for the logarithms to make sense.

    ## 2. The denominator does not depend on $k$

    The denominator is the same sum for every class, so it cannot change which class has the largest posterior:

    $$
    \arg\max_k p_k(x) = \arg\max_k \; \pi_k \exp\left(-\frac{(x-\mu_k)^2}{2\sigma^2}\right).
    $$

    ## 3. Taking the logarithm

    The logarithm is increasing, so we can maximize $\log \pi_k - \frac{(x-\mu_k)^2}{2\sigma^2}$ instead. Expanding the square,

    $$
    -\frac{(x-\mu_k)^2}{2\sigma^2} = -\frac{x^2}{2\sigma^2} + x\cdot\frac{\mu_k}{\sigma^2} - \frac{\mu_k^2}{2\sigma^2},
    $$

    and the first term is the same for every class. What is left is exactly

    $$
    \delta_k(x) = x\cdot\frac{\mu_k}{\sigma^2} - \frac{\mu_k^2}{2\sigma^2} + \log(\pi_k). \tag{4.18}
    $$

    ## 4. The boundary for two classes

    With $K = 2$ and $\pi_1 = \pi_2$, setting $\delta_1(x) = \delta_2(x)$ gives $x = \frac{\mu_1 + \mu_2}{2}$, the midpoint of the two means.

    ```python
    import numpy as np
    mu1, mu2, sigma = -1.25, 1.25, 1.0
    boundary = (mu1 + mu2) / 2   # 0.0
    ```

    So the Bayes classifier assigns $x$ to class 1 when $x < 0$ and to class 2 otherwise.
    """#
}
