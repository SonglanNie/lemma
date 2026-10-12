import SwiftUI
import WebKit
import LemmaCore

/// ChatGPT's ordinary Web UI, hosted by Lemma. WebKit owns cookies and sign-in, never the workspace.
/// The page exists only while the reader uses it: QuestionRuntime creates the session on Connect or on a question
/// and releases it after a quiet period.
@MainActor
final class ChatGPTSession: NSObject, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler {
    weak var runtime: QuestionRuntime?
    let view: WKWebView
    private var active: QuestionJob?
    private var submitted = false
    /// The adapter asked for the question's packet: it is running on this page.
    private var started = false
    private var watchdog: Task<Void, Never>?
    static let home = URL(string: "https://chatgpt.com/")!

    /// macOS's text substitutions (smart quotes and dashes, text replacements, spelling correction) act on the text Lemma
    /// types into ChatGPT's composer as on typing: `"""` became `“”"` and the question no longer matched what Lemma
    /// prepared. WebKit reads these defaults when the app creates its first web view, so the app registers them at launch.
    static func disableTextSubstitutions() {
        UserDefaults.standard.register(defaults: ["WebAutomaticQuoteSubstitutionEnabled": false, "WebAutomaticDashSubstitutionEnabled": false,
                                                  "WebAutomaticTextReplacementEnabled": false, "WebAutomaticSpellingCorrectionEnabled": false])
    }

    init(runtime: QuestionRuntime) {
        self.runtime = runtime
        Self.disableTextSubstitutions()
        let config = WKWebViewConfiguration()
        config.websiteDataStore = runtime.root.deletingLastPathComponent().standardizedFileURL == WorkspaceRepository.defaultRoot.standardizedFileURL ? .default() : .nonPersistent()
        let scripts = config.userContentController
        let bridge = """
        if (location.origin === 'https://chatgpt.com') {
          let sequence = 0; const calls = new Map();
          window.LemmaNativeRPC = message => new Promise((resolve, reject) => {
            const callID = ++sequence; calls.set(callID, {resolve, reject});
            window.webkit.messageHandlers.lemmaAssistant.postMessage({...message, callID});
          });
          window.LemmaNativeReply = value => { const call = calls.get(value.callID); if (call) { calls.delete(value.callID); call.resolve(value); } };
        }
        """
        scripts.addUserScript(WKUserScript(source: bridge, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        for name in ["dom", "content"] {
            // Codicons.resource looks in the app and in SwiftPM's bundle without Bundle.module, which stops the app
            // when its bundle is missing.
            if let url = Codicons.resource("Assistant/\(name).js"), let source = try? String(contentsOf: url, encoding: .utf8) {
                scripts.addUserScript(WKUserScript(source: "if (location.origin === 'https://chatgpt.com') {\n" + source + "\n}", injectionTime: .atDocumentEnd, forMainFrameOnly: true))
            }
        }
        view = WKWebView(frame: .zero, configuration: config)
        super.init()
        // The content controller keeps its handlers alive; a weak relay lets the session be released.
        scripts.add(WeakScriptHandler(self), name: "lemmaAssistant")
        view.navigationDelegate = self; view.uiDelegate = self
        view.clearBackground()
    }

    func connect() {
        if view.url == nil || view.url?.scheme == "about" { view.load(URLRequest(url: Self.home)) }
    }

    func openConversation(_ url: URL) { active = nil; watchdog?.cancel(); view.load(URLRequest(url: url)) }

    func start(_ job: QuestionJob) {
        active = job; submitted = false; started = false
        job.message = "Opening ChatGPT inside Lemma. Sign in here if needed."
        // Always a full page load of a new chat. A `#fragment` on the page already shown would be a same-document
        // navigation: WebKit never reports didFinish for it, and the question would wait at “Opening ChatGPT…”.
        view.load(URLRequest(url: Self.home))
        watchdog?.cancel()
        watchdog = Task { [weak self, weak job] in
            // If the page loaded without reporting didFinish, start the adapter directly. It ignores a second start
            // for the same question, and the nudges stop once it has asked for the question.
            for _ in 0..<40 {
                try? await Task.sleep(for: .seconds(15))
                guard let self, let job, !Task.isCancelled, self.active === job, !job.finished, !self.started else { return }
                if self.view.url?.host == "chatgpt.com", !self.view.isLoading { self.begin(job) }
            }
        }
    }

    func cancel(_ id: UUID) {
        guard active?.id == id else { return }
        view.evaluateJavaScript("window.LemmaCancel?.('\(id.uuidString)')")
        active = nil; watchdog?.cancel()
    }

    /// Unloads the page and detaches the session so its WebKit process can end. Cookies (the sign-in) are kept.
    func release() {
        watchdog?.cancel(); active = nil
        view.stopLoading()
        view.navigationDelegate = nil; view.uiDelegate = nil
        view.configuration.userContentController.removeScriptMessageHandler(forName: "lemmaAssistant")
        view.configuration.userContentController.removeAllUserScripts()
        view.load(URLRequest(url: URL(string: "about:blank")!))
    }

    private func begin(_ job: QuestionJob) {
        // Replacing a draft that is not Lemma's own is the reader's choice, made in the Questions panel.
        view.evaluateJavaScript("window.LemmaStart?.('\(job.id.uuidString)', {replaceDraft: \(job.replacesDraft)})") { [weak self, weak job] _, error in
            guard let error else { return }
            Task { @MainActor in
                guard let self, let job, !job.finished else { return }
                self.runtime?.finish(job, result: BrowserResult(requestID: job.id, status: "error", message: "ChatGPT could not start the question: \(error.localizedDescription)"))
            }
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard webView.url?.host == "chatgpt.com", let active, !active.finished, !submitted else { return }
        begin(active)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { failed(error) }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { failed(error) }

    private func failed(_ error: Error) {
        let error = error as NSError
        // A newer navigation replacing this one, or WebKit handing a download or app link elsewhere, is not a failure.
        if error.code == NSURLErrorCancelled || (error.domain == WKErrorDomain && error.code == 102) { return }
        guard let active, !active.finished else { return }
        active.failureReason = "load"
        runtime?.finish(active, result: BrowserResult(requestID: active.id, status: "error", message: "ChatGPT could not load: \(error.localizedDescription). Check the connection, then ask again."))
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        guard let active, !active.finished else { return }
        active.failureReason = "crash"
        runtime?.finish(active, result: BrowserResult(requestID: active.id, status: "error", message: "The ChatGPT page stopped unexpectedly. Ask again."))
    }

    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        // Sign-in and conversation links remain in this Lemma window.
        if let url = navigationAction.request.url, ["https", "http"].contains(url.scheme) { webView.load(navigationAction.request) }
        return nil
    }

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.frameInfo.isMainFrame, message.frameInfo.securityOrigin.protocol == "https", message.frameInfo.securityOrigin.host == "chatgpt.com",
              let body = message.body as? [String: Any], let callID = body["callID"] as? Int,
              let id = (body["requestID"] as? String).flatMap(UUID.init(uuidString:)),
              let active, id == active.id, !active.finished, let runtime else { return }
        var response: [String: Any] = ["ok": true, "callID": callID]
        do {
            switch body["operation"] as? String {
            case "packet":
                started = true
                let bytes = try WorkspaceRepository.encoder.encode(active.packet)
                response["packet"] = try JSONSerialization.jsonObject(with: bytes)
            case "image":
                guard let name = body["name"] as? String, let index = body["index"] as? Int else { throw BridgeError.invalidImage }
                let mailbox = BrowserMailbox(root: runtime.root.deletingLastPathComponent())
                let (data, done) = try mailbox.imageChunk(requestID: id, name: name, index: index)
                response["data"] = data.base64EncodedString(); response["done"] = done
            case "progress": active.answer = body["answer"] as? String ?? active.answer
            case "result":
                guard let state = body["status"] as? String else { throw BridgeError.invalidRequest }
                let result = BrowserResult(requestID: id, status: state, answer: body["answer"] as? String,
                                           conversationURL: body["conversationURL"] as? String, message: body["message"] as? String)
                if state == "error" { active.failureReason = body["reason"] as? String }
                if state == "complete" || state == "error" { runtime.finish(active, result: result) }
                else {
                    if state == "sent" { submitted = true }
                    active.message = result.message ?? state
                    try BrowserMailbox(root: runtime.root.deletingLastPathComponent()).saveResult(result)
                }
            default: throw BridgeError.invalidRequest
            }
        } catch { response["ok"] = false; response["error"] = error.localizedDescription }
        if let bytes = try? JSONSerialization.data(withJSONObject: response), let json = String(data: bytes, encoding: .utf8) {
            view.evaluateJavaScript("window.LemmaNativeReply(\(json))")
        }
    }
}

/// Forwards script messages without keeping the session alive.
@MainActor
private final class WeakScriptHandler: NSObject, WKScriptMessageHandler {
    weak var target: ChatGPTSession?
    init(_ target: ChatGPTSession) { self.target = target }
    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        target?.userContentController(controller, didReceive: message)
    }
}

/// Shows the session's one web view. A tab switch can make a new host before SwiftUI tears the old one down; handing
/// SwiftUI the web view itself, the old host's teardown then took it out of the new one, and the page went blank. Each
/// host is a plain view holding the web view instead: the newest host takes it, and a host going away lets it go only
/// if it still holds it.
struct AssistantWebView: NSViewRepresentable {
    let view: WKWebView
    func makeNSView(context: Context) -> Host { Host(view) }
    func updateNSView(_ host: Host, context: Context) { if view.superview == nil { host.adopt() } }
    static func dismantleNSView(_ host: Host, coordinator: ()) { host.release() }

    final class Host: NSView {
        private let webView: NSView
        init(_ webView: NSView) {
            self.webView = webView
            super.init(frame: .zero)
            adopt()
        }
        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

        func adopt() {
            guard webView.superview !== self else { return }
            webView.removeFromSuperview()
            webView.frame = bounds
            webView.autoresizingMask = [.width, .height]
            addSubview(webView)
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if window != nil { adopt() }
        }

        func release() { if webView.superview === self { webView.removeFromSuperview() } }
    }
}

/// The embedded ChatGPT page, counted while on screen so the runtime does not release it under the reader.
struct ChatGPTPageView: View {
    let runtime: QuestionRuntime
    var body: some View {
        AssistantWebView(view: runtime.web.view)
            .onAppear { runtime.webViewAppeared() }
            .onDisappear { runtime.webViewDisappeared() }
    }
}
