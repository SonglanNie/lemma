import AppKit

/// Quitting, and closing and bringing forward the reader's windows, whatever a window is doing: the session is saved and
/// helpers stop even when every window was closed before Lemma quits (a window's own `onReceive` would not be there to
/// hear it).
///
/// Not an application delegate adaptor: with one, SwiftUI rebuilt the window's root view each time the menus were
/// recomputed (closing a tab took twice as long), so the same work is done with notifications and an Apple event handler.
@MainActor
final class AppLifecycle: NSObject {
    static let shared = AppLifecycle()
    private(set) weak var app: AppModel?
    private var observers: [NSObjectProtocol] = []

    /// Starts following the app's lifecycle; called once the session is restored.
    func attach(_ app: AppModel) {
        self.app = app
        // Test processes create many stores and never quit as an app does.
        guard observers.isEmpty, NSClassFromString("XCTestCase") == nil else { return }
        // A notebook kernel, the analysis helper or an assistant's process that exits while Lemma writes to its input
        // must not end Lemma: the write fails with EPIPE instead of the process receiving SIGPIPE.
        signal(SIGPIPE, SIG_IGN)
        observers.append(NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { AppLifecycle.shared.app?.prepareForTermination() }
        })
        // Closing a reader window saves at once, rather than when Lemma eventually quits.
        observers.append(NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: nil, queue: .main) { notification in
            guard let window = notification.object as? NSWindow else { return }
            MainActor.assumeIsolated { AppLifecycle.shared.app?.windowWillClose(window) }
        })
        // The menus act on the window in front.
        observers.append(NotificationCenter.default.addObserver(forName: NSWindow.didBecomeKeyNotification, object: nil, queue: .main) { notification in
            guard let window = notification.object as? NSWindow else { return }
            MainActor.assumeIsolated { AppLifecycle.shared.app?.windowDidBecomeKey(window) }
        })
        // AppKit does not quit while a window shows a sheet: a quit from the Dock, another app, or a logout, restart or
        // shutdown would wait until the sheet closed (and hold up the restart). Quit events are handled here instead.
        NSAppleEventManager.shared().setEventHandler(self, andSelector: #selector(handleQuit(_:reply:)),
                                                     forEventClass: AEEventClass(kCoreEventClass), andEventID: AEEventID(kAEQuitApplication))
    }

    @objc private func handleQuit(_ event: NSAppleEventDescriptor, reply: NSAppleEventDescriptor) { quit() }

    /// Quits even while a sheet is shown: the sheets are dismissed first (their state in the store, then AppKit's), then
    /// Lemma quits as usual; the will-terminate notification saves and stops notebooks, questions and helpers.
    func quit(attempt: Int = 0) {
        // Quitting closes no window as a choice of the reader's: the session keeps them all.
        app?.quitting = true
        app?.dismissSheets()
        for window in NSApp.windows { if let sheet = window.attachedSheet { window.endSheet(sheet) } }
        if attempt < 20, NSApp.windows.contains(where: { $0.attachedSheet != nil }) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { MainActor.assumeIsolated { self.quit(attempt: attempt + 1) } }
            return
        }
        NSApp.terminate(nil)
    }
}
