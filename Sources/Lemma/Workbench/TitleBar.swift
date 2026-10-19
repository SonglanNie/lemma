import SwiftUI
import AppKit
import LemmaCore

/// VS Code's custom title bar: room for the window controls, Back and Forward, the command center in the middle,
/// and the layout controls on the right. The bar moves the window and zooms it on a double click.
struct VSTitleBar: View {
    @Bindable var store: StudyStore
    @Environment(\.theme) private var theme
    @Environment(\.controlActiveState) private var activeState
    var fullScreen = false

    var body: some View {
        let active = activeState != .inactive
        ZStack {
            TitleBarDragArea()
            HStack(spacing: 0) {
                Color.clear.frame(width: fullScreen ? 8 : 78).allowsHitTesting(false)
                LemmaGlyph(size: 20)
                    .frame(width: 32)
                    .accessibilityHidden(true)
                    .allowsHitTesting(false)
                Spacer(minLength: 0).allowsHitTesting(false)
            }
            HStack(spacing: 6) {
                Spacer(minLength: 0)
                HStack(spacing: 2) {
                    VSIconButton(icon: "arrow-left", help: "Go Back (⌥⌘←)", enabled: store.reader.canGoBack) { store.reader.back() }
                    VSIconButton(icon: "arrow-right", help: "Go Forward (⌥⌘→)", enabled: store.reader.canGoForward) { store.reader.forward() }
                }
                CommandCenterBox(store: store).tutorialAnchor(.commandCenter)
                Color.clear.frame(width: 52).allowsHitTesting(false)
                Spacer(minLength: 0)
            }
            HStack(spacing: 2) {
                Spacer(minLength: 0)
                LayoutControls(store: store).tutorialAnchor(.layoutControls)
            }.padding(.trailing, 8)
        }
        .frame(height: VSMetrics.titleBarHeight)
        .foregroundStyle(theme[active ? .titleBarActiveForeground : .titleBarInactiveForeground])
        .background(theme[active ? .titleBarActiveBackground : .titleBarInactiveBackground])
        .vsBorder(.bottom, .titleBarBorder, theme: theme)
    }
}

/// The search box in the middle of the title bar: Go to anything (⌘P), commands with “>”.
private struct CommandCenterBox: View {
    @Bindable var store: StudyStore
    @Environment(\.theme) private var theme
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 6) {
            Codicon("search", size: 14)
            Text(label).font(.ui(12)).lineLimit(1).truncationMode(.middle)
        }
        .foregroundStyle(theme[hovering ? .commandCenterActiveForeground : .commandCenterForeground])
        .padding(.horizontal, 10)
        .frame(minWidth: 220, idealWidth: 480, maxWidth: 600)
        .frame(height: 22)
        .background(RoundedRectangle(cornerRadius: 6).fill(theme[hovering ? .commandCenterActiveBackground : .commandCenterBackground]))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(theme[hovering ? .commandCenterActiveBorder : .commandCenterBorder], lineWidth: 1))
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture { store.showPalette(.goTo) }
        .help("Search pages, sections, equations, terms, notes and books (⌘P) · Commands (⇧⌘P)")
        .accessibilityElement(children: .ignore)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel("Go to")
        .accessibilityAction { store.showPalette(.goTo) }
        .layoutPriority(1)
    }

    private var label: String {
        if let title = store.workspace?.title { return title }
        if case let .project(id)? = store.activeSideEditor, let project = store.project(id) { return project.title }
        return "Lemma"
    }
}

/// Toggle the primary side bar, the panel and the secondary side bar; customize the layout.
private struct LayoutControls: View {
    @Bindable var store: StudyStore
    var body: some View {
        HStack(spacing: 2) {
            VSIconButton(icon: store.showLibrary ? "layout-sidebar-left" : "layout-sidebar-left-off", help: "Toggle Primary Side Bar (⌘B)") { store.toggleLibrary() }
            VSIconButton(icon: store.showPanel ? "layout-panel" : "layout-panel-off", help: "Toggle Panel (⌘J)", enabled: store.workspace != nil) { store.togglePanel() }
            VSIconButton(icon: store.showStudy ? "layout-sidebar-right" : "layout-sidebar-right-off", help: "Toggle Secondary Side Bar (⌥⌘B)",
                         enabled: store.workspace != nil) { store.toggleStudy() }
            VSMenuButton(icon: "layout", help: "Customize Layout…") {
                var items: [VSMenuItem] = [.header("Layouts")]
                items += LayoutPreset.allCases.map { preset in .action(preset.label) { store.applyLayout(preset) } }
                items += [.separator,
                          .action(store.focusMode ? "Leave Zen Mode" : "Zen Mode", shortcut: "⌥⌘Z") { store.toggleFocus() },
                          .action(store.workbenchLayout.sidebarPosition == .left ? "Move Primary Side Bar Right" : "Move Primary Side Bar Left") {
                              store.workbenchLayout.sidebarPosition = store.workbenchLayout.sidebarPosition == .left ? .right : .left; store.saveWorkbench()
                          },
                          .action("Activity Bar", checked: store.workbenchLayout.activityBar) { store.workbenchLayout.activityBar.toggle(); store.saveWorkbench() },
                          .action("Minimap", checked: store.app.showMinimap) { store.app.showMinimap.toggle() },
                          .separator,
                          .action("Color Theme…", shortcut: "⌥⌘T") { store.showThemePicker() },
                          .action("Settings", shortcut: "⌘,") { store.openSettingsEditor() }]
                return items
            }
        }
    }
}

/// A transparent strip that moves the window, and zooms or minimizes it on a double click as the system setting says.
struct TitleBarDragArea: NSViewRepresentable {
    func makeNSView(context: Context) -> DragView { DragView() }
    func updateNSView(_ view: DragView, context: Context) {}

    final class DragView: NSView {
        override var mouseDownCanMoveWindow: Bool { true }
        override func mouseDown(with event: NSEvent) {
            guard let window else { return }
            if event.clickCount == 2 {
                let action = UserDefaults.standard.string(forKey: "AppleActionOnDoubleClick") ?? "Maximize"
                if action == "Minimize" { window.performMiniaturize(nil) } else if action != "None" { window.performZoom(nil) }
                return
            }
            window.performDrag(with: event)
        }
    }
}

/// Centres the window controls in the 35 pt title bar, as VS Code does with its custom title bar.
@MainActor
enum TrafficLights {
    static func place(in window: NSWindow, barHeight: CGFloat = VSMetrics.titleBarHeight) {
        guard !window.styleMask.contains(.fullScreen), let close = window.standardWindowButton(.closeButton),
              let titlebarView = close.superview, let container = titlebarView.superview else { return }
        let height = barHeight
        var containerFrame = container.frame
        if abs(containerFrame.height - height) > 0.5 || abs(containerFrame.minY - (window.frame.height - height)) > 0.5 {
            containerFrame.size.height = height
            containerFrame.origin.y = window.frame.height - height
            container.frame = containerFrame
            titlebarView.frame = NSRect(x: 0, y: 0, width: containerFrame.width, height: height)
        }
        // VS Code places them at (10, 9) from the top left of its 35 pt bar: floor((35 − 16) / 2) = 9.
        let buttons: [NSWindow.ButtonType] = [.closeButton, .miniaturizeButton, .zoomButton]
        for (offset, type) in buttons.enumerated() {
            guard let button = window.standardWindowButton(type) else { continue }
            let top = floor((height - 16) / 2)
            let origin = NSPoint(x: 10 + CGFloat(offset) * 20, y: (height - top - button.frame.height).rounded())
            if button.frame.origin != origin { button.setFrameOrigin(origin) }
        }
    }
}

/// Keeps each window's controls in place as it resizes, enters and leaves full screen, and sets its title bar up for
/// the workbench style. Every window has its own state: `attach` runs at each redraw of each window.
@MainActor
final class TitleBarCoordinator {
    static let shared = TitleBarCoordinator()
    private var windows: [ObjectIdentifier: WindowState] = [:]
    private var closing: NSObjectProtocol?

    @MainActor private final class WindowState {
        var observers: [NSObjectProtocol] = []
        var watches: [NSKeyValueObservation] = []
        /// The frame to keep while SwiftUI adds or removes the Classic toolbar after a switch of style.
        var keptFrame: (frame: NSRect, until: Date)?
        /// The style the window was last set up for. The window is set up again only when it changes: setting it up at
        /// every redraw kept undoing the reader's own resizing and moves.
        var configuredStyle: WorkbenchStyle?
    }

    func attach(_ window: NSWindow) {
        let style = ThemeManager.shared.style
        let key = ObjectIdentifier(window)
        let isNewWindow = windows[key] == nil
        let state = windows[key] ?? WindowState()
        if isNewWindow || state.configuredStyle != style {
            // Only a switch of style in a window already on screen keeps its frame (AppKit moves it when the toolbar
            // comes or goes); when a window opens the frame is the app's to set.
            configure(window, state: state, keepFrame: !isNewWindow)
            state.configuredStyle = style
        } else if style == .vscode {
            TrafficLights.place(in: window)
        }
        guard isNewWindow else { return }
        windows[key] = state
        if closing == nil {
            closing = NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: nil, queue: .main) { notification in
                guard let window = notification.object as? NSWindow else { return }
                let key = ObjectIdentifier(window)
                MainActor.assumeIsolated {
                    guard let state = TitleBarCoordinator.shared.windows.removeValue(forKey: key) else { return }
                    for observer in state.observers { NotificationCenter.default.removeObserver(observer) }
                }
            }
        }
        let names: [Notification.Name] = [NSWindow.didResizeNotification, NSWindow.didEndLiveResizeNotification, NSWindow.didExitFullScreenNotification,
                                          NSWindow.didBecomeKeyNotification, NSWindow.didChangeScreenNotification]
        for name in names {
            let endsLiveResize = name == NSWindow.didEndLiveResizeNotification
            state.observers.append(NotificationCenter.default.addObserver(forName: name, object: window, queue: .main) { [weak state, weak window] _ in
                MainActor.assumeIsolated {
                    guard let window, let state else { return }
                    // A size the reader chose is never undone.
                    if endsLiveResize { state.keptFrame = nil }
                    if let kept = state.keptFrame, Date() < kept.until, !window.inLiveResize, window.frame != kept.frame, !window.styleMask.contains(.fullScreen) {
                        window.setFrame(kept.frame, display: true)
                    }
                    if ThemeManager.shared.style == .vscode { TitleBarCoordinator.restoreTransparency(window); TrafficLights.place(in: window) }
                }
            })
        }
        // SwiftUI sets the title bar up again while it builds the scene (after this ran when the window opened): put the
        // VS Code style's transparent title bar back whenever that happens, or the native bar covers Lemma's own.
        // Key-value observation hears of each change; the window's every update (`didUpdateNotification`, posted for
        // each event while Lemma is in front) is not watched for it any more.
        state.watches = [window.observe(\.titlebarAppearsTransparent) { window, _ in
            MainActor.assumeIsolated { TitleBarCoordinator.restoreTransparency(window) }
        }, window.observe(\.titleVisibility) { window, _ in
            MainActor.assumeIsolated { TitleBarCoordinator.restoreTransparency(window) }
        }]
        if ThemeManager.shared.style == .vscode {
            TrafficLights.place(in: window)
            DispatchQueue.main.async { [weak window] in if let window { TrafficLights.place(in: window) } }
        }
    }

    private static func restoreTransparency(_ window: NSWindow) {
        guard ThemeManager.shared.style == .vscode, !window.titlebarAppearsTransparent || window.titleVisibility != .hidden else { return }
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        TrafficLights.place(in: window)
    }

    /// VS Code: a transparent title bar under Lemma's own, full-size content. Classic: the native title bar and toolbar.
    private func configure(_ window: NSWindow, state: WindowState, keepFrame: Bool) {
        // Changing the title bar and toolbar makes AppKit keep the content's size and move the frame: keep the frame.
        let frame = window.frame
        let fullScreen = window.styleMask.contains(.fullScreen)
        if ThemeManager.shared.style == .vscode {
            if !window.styleMask.contains(.fullSizeContentView) { window.styleMask.insert(.fullSizeContentView) }
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.toolbar?.isVisible = false
        } else {
            window.toolbar?.isVisible = true
            window.titlebarAppearsTransparent = false
            window.titleVisibility = .visible
            if window.styleMask.contains(.fullSizeContentView) && !fullScreen { window.styleMask.remove(.fullSizeContentView) }
            window.standardWindowButton(.closeButton)?.superview?.needsLayout = true
        }
        guard !fullScreen, keepFrame else { return }
        if state.keptFrame == nil || Date() >= state.keptFrame!.until { state.keptFrame = (frame, Date().addingTimeInterval(1.5)) }
        if window.frame != frame { window.setFrame(frame, display: true) }
        for delay in [0.0, 0.15, 0.5] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak state, weak window] in
                guard let window, let kept = state?.keptFrame, window.frame != kept.frame, !window.styleMask.contains(.fullScreen) else { return }
                window.setFrame(kept.frame, display: true)
            }
        }
    }
}
