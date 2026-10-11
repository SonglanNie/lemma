import SwiftUI
import WebKit
import AppKit

struct MathPreview: View {
    let text: String
    var onOpenLink: ((URL) -> Void)? = nil
    @State private var height: CGFloat = 80
    @Environment(\.theme) private var theme
    @State private var themes = ThemeManager.shared
    var body: some View {
        MathWebSurface(text: text, colours: themes.style == .vscode ? Self.colours(theme) : [:], height: $height, onOpenLink: onOpenLink)
            .frame(height: height)
            .accessibilityLabel("Formatted Markdown and mathematics")
    }

    /// The theme's text colours for the page, as VS Code's Markdown preview takes them: text, links, inline code, code
    /// blocks, quotes and rules. The Classic window keeps the page's own colours.
    static func colours(_ theme: WorkbenchColors) -> [String: String] {
        func css(_ key: TC) -> String {
            let c = theme.rgba(key)
            return String(format: "rgba(%d, %d, %d, %.3f)", Int((c.r * 255).rounded()), Int((c.g * 255).rounded()), Int((c.b * 255).rounded()), c.a)
        }
        return ["text": css(.foreground), "link": css(.textLinkForeground), "code-text": css(.textPreformatForeground),
                "code-bg": css(.textCodeBlockBackground), "quote-bg": css(.textBlockQuoteBackground), "rule": css(.textSeparatorForeground)]
    }
}

private struct MathWebSurface: NSViewRepresentable {
    let text: String
    let colours: [String: String]
    @Binding var height: CGFloat
    var onOpenLink: ((URL) -> Void)?
    func makeCoordinator() -> Coordinator { Coordinator(height: $height) }
    func makeNSView(context: Context) -> MathWebHost {
        context.coordinator.text = text
        context.coordinator.colours = colours
        context.coordinator.onOpenLink = onOpenLink
        return MathWebHost(client: context.coordinator)
    }
    func updateNSView(_ host: MathWebHost, context: Context) {
        context.coordinator.text = text
        context.coordinator.colours = colours
        context.coordinator.onOpenLink = onOpenLink
        context.coordinator.render()
    }
    static func dismantleNSView(_ host: MathWebHost, coordinator: Coordinator) { host.release() }

    @MainActor final class Coordinator: NSObject, MathWebClient {
        var text = ""
        var colours: [String: String] = [:]
        private var rendered: (text: String, colours: [String: String])?
        var onOpenLink: ((URL) -> Void)?
        var height: Binding<CGFloat>
        weak var view: MathWebView?
        init(height: Binding<CGFloat>) { self.height = height }

        func mathPageLoaded(_ view: MathWebView) { rendered = nil; render() }

        func render() {
            guard let view, view.pageLoaded, rendered?.text != text || rendered?.colours != colours else { return }
            rendered = (text, colours)
            view.callAsyncJavaScript("renderStudy(markdown, colours)", arguments: ["markdown": text, "colours": colours], in: nil, in: .page, completionHandler: nil)
        }

        func mathMessage(_ name: String, body: Any) {
            guard name == "studyHeight", let value = body as? NSNumber else { return }
            let measured = min(max(CGFloat(value.doubleValue), 24), 20000)
            if abs(height.wrappedValue - measured) > 1 { height.wrappedValue = measured }
        }

        func mathLinkActivated(_ url: URL) {
            if url.scheme == "lemma" {
                if let onOpenLink { onOpenLink(url) } else { NSWorkspace.shared.open(url) }
            } else if ["https", "http"].contains(url.scheme ?? "") {
                NSWorkspace.shared.open(url)
            }
        }
    }
}

// MARK: - Shared web views

/// What a preview does with the typeset page it borrowed: render once the page has loaded, read its messages
/// (`studyHeight`, `stepClicked`), and follow links the reader clicks.
@MainActor
protocol MathWebClient: AnyObject {
    var view: MathWebView? { get set }
    func mathPageLoaded(_ view: MathWebView)
    func render()
    func mathMessage(_ name: String, body: Any)
    func mathLinkActivated(_ url: URL)
}

extension MathWebClient {
    func mathLinkActivated(_ url: URL) {}
}

/// Web views showing Resources/Math/index.html (typeset Markdown, mathematics and derivation steps) for every preview.
///
/// WebKit gives each WKWebView its own web content process, whatever data store or process pool it is given, and a
/// released view's process lingers while a new view starts another. Previews therefore borrow their web view from here:
/// one handed back waits, with its page loaded, for the next preview (a few at most, for a minute), so hiding and
/// showing a pane or scrolling through notes reuses processes instead of starting new ones. They all share one
/// ephemeral data store: the page loads bundled files only and keeps nothing.
@MainActor
final class MathWebViews {
    static let shared = MathWebViews()
    let dataStore = WKWebsiteDataStore.nonPersistent()
    private var idle: [MathWebView] = []
    private let capacity = 4
    private var purge: Task<Void, Never>?

    var idleCount: Int { idle.count }

    func borrow() -> MathWebView {
        defer { schedulePurge() }
        if let view = idle.popLast() { return view }
        return MathWebView(dataStore: dataStore)
    }

    func giveBack(_ view: MathWebView) {
        view.client = nil
        view.removeFromSuperview()
        guard idle.count < capacity else { return }
        // A preview borrowing it next shows nothing of this one while its own text renders.
        if view.pageLoaded { view.evaluateJavaScript("document.getElementById('content').innerHTML = ''; window.setStudyTheme?.({})", completionHandler: nil) }
        idle.append(view)
        schedulePurge()
    }

    /// Idle views go after a minute without use, and their processes with them.
    private func schedulePurge() {
        purge?.cancel()
        guard !idle.isEmpty else { purge = nil; return }
        purge = Task { [weak self] in
            try? await Task.sleep(for: .seconds(60))
            guard !Task.isCancelled else { return }
            self?.idle.removeAll()
        }
    }
}

/// A web view with the typeset page, forwarding its page's events to whichever preview has it now.
final class MathWebView: WKWebView {
    private(set) var pageLoaded = false
    weak var client: (any MathWebClient)?
    private let router: Router

    init(dataStore: WKWebsiteDataStore) {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = dataStore
        let router = Router()
        // The content controller keeps the router; the router keeps only a weak reference back.
        configuration.userContentController.add(router, name: "studyHeight")
        configuration.userContentController.add(router, name: "stepClicked")
        self.router = router
        super.init(frame: .zero, configuration: configuration)
        router.view = self
        navigationDelegate = router
        clearBackground()
        loadPage()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    private func loadPage() {
        pageLoaded = false
        // Codicons.resource finds the page in the app or SwiftPM's bundle without Bundle.module's fatal error.
        guard let url = Codicons.resource("Math/index.html") else { return }
        loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
    }

    fileprivate func pageDidLoad() {
        pageLoaded = true
        client?.mathPageLoaded(self)
    }

    /// Whether the trackpad gesture under way scrolls the page sideways; nil until it has moved.
    private var gestureSideways: Bool?

    /// A preview is as tall as its page and sits in its pane's scroll view, so vertical scrolling belongs to the pane.
    /// WebKit kept the gesture for the page, which had nowhere to go: the pane stopped scrolling under the pointer (a saved
    /// explanation could hardly be scrolled through). A gesture goes, as a whole, to the pane when it starts vertically
    /// and to the page when it starts sideways, so a wide equation or code block still scrolls across. A mouse wheel,
    /// which makes no gesture, is routed one notch at a time.
    override func scrollWheel(with event: NSEvent) {
        if Self.scrollsPage(event, gesture: &gestureSideways) { super.scrollWheel(with: event) } else { nextResponder?.scrollWheel(with: event) }
    }

    /// Whether a scroll event goes to the page rather than the pane: the direction a gesture took when it started moving
    /// (kept in `gesture` through its momentum), or each notch's own for a mouse wheel.
    static func scrollsPage(_ event: NSEvent, gesture: inout Bool?) -> Bool {
        let sideways = abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY)
        if event.phase.isEmpty && event.momentumPhase.isEmpty { return sideways }
        if event.phase.contains(.began) || event.phase.contains(.mayBegin) { gesture = nil }
        if gesture == nil, event.scrollingDeltaX != 0 || event.scrollingDeltaY != 0 { gesture = sideways }
        return gesture ?? false
    }

    /// The web content process ended (memory pressure, a crash): load the page again, and its preview renders again.
    fileprivate func processDidTerminate() { loadPage() }

    @MainActor private final class Router: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        weak var view: MathWebView?

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { view?.pageDidLoad() }

        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) { view?.processDidTerminate() }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            view?.client?.mathMessage(message.name, body: message.body)
        }

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void) {
            if navigationAction.navigationType == .linkActivated {
                if let url = navigationAction.request.url { view?.client?.mathLinkActivated(url) }
                decisionHandler(.cancel)
            } else { decisionHandler(navigationAction.request.url?.isFileURL == true ? .allow : .cancel) }
        }
    }
}

extension WKWebView {
    /// WebKit has no public switch for a transparent WKWebView on macOS; the `drawsBackground` key is the one its own
    /// views answer to. It is set only while WebKit still answers to it, so a macOS without the key shows an opaque
    /// view rather than raising an exception. The page's own background is transparent (study.css).
    func clearBackground() {
        if responds(to: NSSelectorFromString("_setDrawsBackground:")) || responds(to: NSSelectorFromString("setDrawsBackground:")) {
            setValue(false, forKey: "drawsBackground")
        }
        underPageBackgroundColor = .clear
    }
}

/// What a preview's representable returns to SwiftUI: a plain view holding the borrowed web view, so SwiftUI never
/// owns the shared view itself and can tear its host down however it likes.
final class MathWebHost: NSView {
    private var webView: MathWebView?

    init(client: any MathWebClient) {
        super.init(frame: .zero)
        let view = MathWebViews.shared.borrow()
        view.frame = bounds
        view.autoresizingMask = [.width, .height]
        addSubview(view)
        webView = view
        client.view = view
        view.client = client
        if view.pageLoaded { client.render() }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func release() {
        guard let view = webView else { return }
        webView = nil
        MathWebViews.shared.giveBack(view)
    }
}
