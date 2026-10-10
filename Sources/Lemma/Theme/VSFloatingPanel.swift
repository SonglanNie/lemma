import SwiftUI
import AppKit

/// A borderless child window that shows SwiftUI content beside a place in a view: VS Code's hover and peek widgets,
/// drawn by Lemma rather than as a popover with an arrow.
@MainActor
final class VSFloatingPanel {
    private final class Panel: NSPanel {
        var acceptsKey = false
        override var canBecomeKey: Bool { acceptsKey }
        override var canBecomeMain: Bool { false }
        override func cancelOperation(_ sender: Any?) { onCancel?() }
        var onCancel: (() -> Void)?
    }

    enum Placement { case above, below }

    private var panel: Panel?
    private var monitors: [Any] = []
    var onClose: (() -> Void)?

    var isShown: Bool { panel?.isVisible == true }

    /// Shows `content` next to `anchor` (in `view`'s coordinates). Interactive widgets take clicks and the keyboard and
    /// close on Escape or a click elsewhere; hovers let the pointer through.
    func show<Content: View>(_ content: Content, anchor: CGRect, in view: NSView, placement: Placement, interactive: Bool,
                             width: CGFloat? = nil, maxHeight: CGFloat = 560) {
        close(notify: false)
        guard let window = view.window else { return }
        let root = content.environment(\.theme, ThemeManager.shared.colors)
        let hosting = NSHostingView(rootView: AnyView(root))
        if let width { hosting.frame.size.width = width }
        let fitting = hosting.fittingSize
        let size = CGSize(width: width ?? min(fitting.width, 760), height: min(fitting.height, maxHeight))
        let anchorOnScreen = window.convertToScreen(view.convert(anchor, to: nil))
        let screen = window.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? .zero
        // Widgets stay inside the window, as VS Code's do (and on its screen); one that cannot fit below its line goes above.
        let content = window.convertToScreen(window.contentLayoutRect)
        let area = screen.isEmpty ? content : content.intersection(screen)
        var origin = CGPoint(x: anchorOnScreen.minX, y: 0)
        switch placement {
        case .above:
            origin.y = anchorOnScreen.maxY + 4
            if origin.y + size.height > area.maxY, anchorOnScreen.minY - 4 - size.height >= area.minY { origin.y = anchorOnScreen.minY - 4 - size.height }
        case .below:
            origin.y = anchorOnScreen.minY - 4 - size.height
            if origin.y < area.minY, anchorOnScreen.maxY + 4 + size.height <= area.maxY { origin.y = anchorOnScreen.maxY + 4 }
        }
        origin.x = max(area.minX + 4, min(origin.x, area.maxX - size.width - 4))
        // Taller than the room left: aligned with the window's top, it covers the line rather than leaving the window.
        origin.y = min(max(area.minY + 4, origin.y), area.maxY - size.height - 4)

        let panel = Panel(contentRect: NSRect(origin: origin, size: size), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.acceptsKey = interactive
        panel.ignoresMouseEvents = !interactive
        panel.isReleasedWhenClosed = false
        panel.animationBehavior = .none
        panel.appearance = NSApp.appearance
        hosting.frame = NSRect(origin: .zero, size: size)
        panel.contentView = hosting
        panel.onCancel = { [weak self] in self?.close() }
        // Clicks reach its buttons without taking the keyboard from the reader's window, which stays active as with
        // VS Code's inline peek; a text field inside takes the keyboard when clicked.
        panel.becomesKeyOnlyIfNeeded = true
        window.addChildWindow(panel, ordered: .above)
        panel.invalidateShadow()
        self.panel = panel
        if interactive {
            monitors.append(NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
                if let self, let panel = self.panel, event.window !== panel { self.close() }
                return event
            } as Any)
            monitors.append(NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                // Escape closes the widget when it is typed in the window the widget belongs to (typed in the widget,
                // it reaches its cancelOperation), unless a sheet or a modal window is up or a text field has the
                // keyboard: elsewhere in the app Escape keeps its own meaning.
                guard event.keyCode == 53, let self, let panel = self.panel, panel.isVisible, let parent = panel.parent,
                      event.window === parent, NSApp.modalWindow == nil, parent.attachedSheet == nil,
                      !(parent.firstResponder is NSText) else { return event }
                self.close()
                return nil
            } as Any)
        }
    }

    func close(notify: Bool = true) {
        for monitor in monitors { NSEvent.removeMonitor(monitor) }
        monitors.removeAll()
        guard let panel else { return }
        panel.parent?.removeChildWindow(panel)
        panel.orderOut(nil)
        self.panel = nil
        if notify { onClose?() }
    }
}

/// VS Code's hover widget: a rectangle with a 1 pt border, the content padded 4×8, and a status row of hints or actions.
struct VSHoverChrome<Content: View>: View {
    @Environment(\.theme) private var theme
    var status: String? = nil
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            content.padding(.horizontal, 8).padding(.vertical, 6)
            if let status {
                Rectangle().fill(theme[.editorHoverWidgetBorder]).frame(height: 1)
                Text(status).font(.ui(12)).foregroundStyle(theme[.textLinkForeground]).lineLimit(1)
                    .padding(.horizontal, 8).frame(maxWidth: .infinity, minHeight: 22, alignment: .leading)
                    .background(theme[.editorHoverWidgetStatusBarBackground])
            }
        }
        .foregroundStyle(theme[.editorHoverWidgetForeground])
        .background(theme[.editorHoverWidgetBackground])
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(theme[.editorHoverWidgetBorder], lineWidth: 1))
        .fixedSize()
    }
}

/// VS Code's peek view: a 2 pt frame in the peek colour, a title bar with the name, its place and actions, the body below.
struct VSPeekChrome<Actions: View, Content: View>: View {
    @Environment(\.theme) private var theme
    let icon: String
    let title: String
    var description: String = ""
    @ViewBuilder var actions: Actions
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 4) {
                Codicon(icon, size: 16).foregroundStyle(theme[.peekViewTitleLabelForeground])
                Text(title).font(.ui(13)).foregroundStyle(theme[.peekViewTitleLabelForeground]).lineLimit(1)
                if !description.isEmpty {
                    Text("-").font(.ui(12)).foregroundStyle(theme[.peekViewTitleDescriptionForeground])
                    Text(description).font(.ui(12)).foregroundStyle(theme[.peekViewTitleDescriptionForeground]).lineLimit(1)
                }
                Spacer(minLength: 8)
                HStack(spacing: 2) { actions }
            }
            .padding(.leading, 12).padding(.trailing, 4)
            .frame(height: 26)
            .background(theme[.peekViewTitleBackground])
            Rectangle().fill(theme[.peekViewBorder]).frame(height: 1)
            content
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .background(theme[.peekViewEditorBackground])
        }
        .overlay(alignment: .top) { Rectangle().fill(theme[.peekViewBorder]).frame(height: 2) }
        .overlay(alignment: .bottom) { Rectangle().fill(theme[.peekViewBorder]).frame(height: 2) }
        .overlay(Rectangle().stroke(theme[.peekViewBorder].opacity(0.6), lineWidth: 1))
    }
}
