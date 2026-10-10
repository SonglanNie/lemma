import SwiftUI
import AppKit

/// Explicit pane widths make a restored layout predictable and support either explorer position.
struct WorkspacePanes<Editor: View>: View {
    @Bindable var store: StudyStore
    @ViewBuilder let editor: () -> Editor

    var body: some View {
        GeometryReader { geometry in
            let widths = fittedWidths(geometry.size.width)
            let spare = max(0, geometry.size.width - widths.sidebar - widths.inspector - 370
                            - (widths.sidebar > 0 ? ResizeSashView.thickness : 0) - (widths.inspector > 0 ? ResizeSashView.thickness : 0))
            HStack(spacing: 0) {
                if store.workbenchLayout.sidebarPosition == .left {
                    if store.showLibrary { navigator(widths.sidebar); paneDivider(.sidebar, onLeft: true, widths: widths, spare: spare) }
                    editor().frame(maxWidth: .infinity, maxHeight: .infinity)
                    if store.showStudy, store.workspace != nil { paneDivider(.inspector, onLeft: false, widths: widths, spare: spare); inspector(widths.inspector) }
                } else {
                    if store.showStudy, store.workspace != nil { inspector(widths.inspector); paneDivider(.inspector, onLeft: true, widths: widths, spare: spare) }
                    editor().frame(maxWidth: .infinity, maxHeight: .infinity)
                    if store.showLibrary { paneDivider(.sidebar, onLeft: false, widths: widths, spare: spare); navigator(widths.sidebar) }
                }
            }
        }
    }

    private func fittedWidths(_ available: CGFloat) -> (sidebar: CGFloat, inspector: CGFloat) {
        var sidebar = store.showLibrary ? min(400, max(180, store.workbenchLayout.sidebarWidth)) : 0
        var inspector = store.showStudy && store.workspace != nil ? min(500, max(260, store.workbenchLayout.inspectorWidth)) : 0
        let total = sidebar + inspector
        let room = max(0, available - 370 - (sidebar > 0 ? ResizeSashView.thickness : 0) - (inspector > 0 ? ResizeSashView.thickness : 0))
        if total > room, total > 0 {
            let minimumSidebar: CGFloat = sidebar > 0 ? 180 : 0
            let minimumInspector: CGFloat = inspector > 0 ? 260 : 0
            let minimum = minimumSidebar + minimumInspector
            if room >= minimum, total > minimum {
                let ratio = (room - minimum) / (total - minimum)
                sidebar = minimumSidebar + (sidebar - minimumSidebar) * ratio
                inspector = minimumInspector + (inspector - minimumInspector) * ratio
            } else { let ratio = room / total; sidebar *= ratio; inspector *= ratio }
        }
        return (sidebar, inspector)
    }

    private func navigator(_ width: CGFloat) -> some View {
        Group {
            if ThemeManager.shared.style == .classic { NavigatorPane(store: store) } else { VSSideBar(store: store) }
        }.frame(width: width, height: nil).frame(maxHeight: .infinity).tutorialAnchor(.sideBar)
    }
    private func inspector(_ width: CGFloat) -> some View {
        StudyPane(store: store).frame(width: width, height: nil).frame(maxHeight: .infinity).tutorialAnchor(.secondarySideBar)
    }
    private func paneDivider(_ pane: WorkbenchPaneDivider.Pane, onLeft: Bool,
                             widths: (sidebar: CGFloat, inspector: CGFloat), spare: CGFloat) -> some View {
        let width = pane == .sidebar ? widths.sidebar : widths.inspector
        return WorkbenchPaneDivider(store: store, pane: pane, onLeft: onLeft, displayedWidth: width, maximumWidth: width + spare) {
            // Start from the sizes on screen, including when the window has constrained both side bars.
            if store.showLibrary { store.workbenchLayout.sidebarWidth = widths.sidebar }
            if store.showStudy, store.workspace != nil { store.workbenchLayout.inspectorWidth = widths.inspector }
        }
    }
}

private struct WorkbenchPaneDivider: View {
    enum Pane { case sidebar, inspector }
    @Bindable var store: StudyStore
    let pane: Pane
    let onLeft: Bool
    let displayedWidth: Double
    let maximumWidth: Double
    let onStart: () -> Void
    @State private var draggingWidth: Double?
    @discardableResult private func resize(_ value: Double) -> Double {
        let maximum = min(pane == .sidebar ? 400 : 500, maximumWidth)
        let minimum = min(maximum, pane == .sidebar ? 180 : 260)
        let value = min(maximum, max(minimum, value))
        if pane == .sidebar { store.workbenchLayout.sidebarWidth = value }
        else { store.workbenchLayout.inspectorWidth = value }
        return value
    }

    var body: some View {
        VSSash(axis: .vertical, onDrag: { delta in
                if draggingWidth == nil { onStart() }
                draggingWidth = resize((draggingWidth ?? displayedWidth) + delta * (onLeft ? 1 : -1))
            }, onEnd: { draggingWidth = nil; store.saveWorkbench(); store.fitPageIfOverflowing() }, onDoubleClick: {
                onStart(); resize(pane == .sidebar ? 264 : 370); store.saveWorkbench(); store.fitPageIfOverflowing()
            })
            .frame(maxHeight: .infinity)
            .accessibilityElement()
            .accessibilityLabel(pane == .sidebar ? "Explorer width" : "Notebook inspector width")
            .accessibilityValue("\(Int(displayedWidth)) points")
            .accessibilityAdjustableAction { direction in
                onStart(); resize(displayedWidth + (direction == .increment ? 20 : -20)); store.saveWorkbench(); store.fitPageIfOverflowing()
            }
            .help("Drag to resize; double-click to reset width")
    }
}
