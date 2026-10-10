import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// A Library PDF dropped near the reader's right edge opens beside it. The side group accepts the whole area.
struct EditorDropTarget: ViewModifier {
    let store: StudyStore
    var toSide = false
    @Environment(\.theme) private var theme
    @State private var destination: EditorDropDestination?

    func body(content: Content) -> some View {
        GeometryReader { geometry in
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .overlay(alignment: .trailing) {
                    if let destination = destination ?? (toSide ? store.sidePDFDropDestination : store.mainPDFDropDestination) {
                        let side = destination == .side
                        ZStack {
                            Rectangle().fill(theme.accent.opacity(0.16))
                            Rectangle().strokeBorder(theme.accent, lineWidth: 1)
                            Text(side ? "Open to the Side" : "Open PDF")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(theme[.editorForeground])
                                .padding(.horizontal, 12).padding(.vertical, 8)
                                .background(theme[.editorBackground])
                        }
                        .frame(width: side && !toSide ? geometry.size.width / 2 : geometry.size.width)
                        .allowsHitTesting(false)
                    }
                }
                .onDrop(of: [UTType.text], delegate: EditorPDFDropDelegate(store: store, width: geometry.size.width,
                    toSide: toSide, destination: $destination))
        }
    }
}

enum EditorDropDestination {
    case main, side
}

private struct EditorPDFDropDelegate: DropDelegate {
    let store: StudyStore
    let width: CGFloat
    let toSide: Bool
    @Binding var destination: EditorDropDestination?

    private func destination(for info: DropInfo) -> EditorDropDestination {
        if toSide || (store.workspace != nil && info.location.x >= width * 0.65) { return .side }
        return .main
    }

    func dropEntered(info: DropInfo) { destination = destination(for: info) }
    func dropExited(info: DropInfo) { destination = nil }
    func dropUpdated(info: DropInfo) -> DropProposal? {
        destination = destination(for: info)
        return DropProposal(operation: .copy)
    }

    func performDrop(info: DropInfo) -> Bool {
        let toSide = destination(for: info) == .side
        destination = nil
        guard let provider = info.itemProviders(for: [UTType.text]).first, provider.canLoadObject(ofClass: String.self) else { return false }
        _ = provider.loadObject(ofClass: String.self) { value, _ in
            guard let value else { return }
            Task { @MainActor in store.openEditorDrop(value, toSide: toSide) }
        }
        return true
    }
}

/// PDFKit owns the native page surface's drag callbacks, so it forwards Library drops explicitly.
@MainActor
final class PDFEditorDropHandler {
    weak var store: StudyStore?
    let toSide: Bool

    init(store: StudyStore, toSide: Bool) { self.store = store; self.toSide = toSide }

    func accepts(_ sender: any NSDraggingInfo) -> Bool { payload(sender) != nil }

    private func payload(_ sender: any NSDraggingInfo) -> String? {
        guard let value = sender.draggingPasteboard.string(forType: .string) else { return nil }
        if value.hasPrefix("lemma-book:") || value.hasPrefix("lemma-tab:") { return value }
        guard let url = URL(string: value), url.isFileURL, url.pathExtension.lowercased() == "pdf" else { return nil }
        return value
    }

    private func destination(_ sender: any NSDraggingInfo, in view: NSView) -> EditorDropDestination {
        let x = view.convert(sender.draggingLocation, from: nil).x
        return toSide || (store?.workspace != nil && x >= view.bounds.width * 0.65) ? .side : .main
    }

    func update(_ sender: any NSDraggingInfo, in view: NSView) -> NSDragOperation? {
        guard accepts(sender) else { return nil }
        let destination = destination(sender, in: view)
        if toSide { store?.sidePDFDropDestination = destination } else { store?.mainPDFDropDestination = destination }
        return .copy
    }

    func perform(_ sender: any NSDraggingInfo, in view: NSView) -> Bool? {
        guard let value = payload(sender) else { return nil }
        let side = destination(sender, in: view) == .side
        clear()
        return store?.openEditorDrop(value, toSide: side) ?? false
    }

    func clear() {
        if toSide { store?.sidePDFDropDestination = nil } else { store?.mainPDFDropDestination = nil }
    }
}
