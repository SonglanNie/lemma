import SwiftUI

/// The same handle separates editor groups, source comparisons and stacked editors.
struct ResizablePair<First: View, Second: View>: View {
    @Bindable var store: StudyStore
    let id: String
    let axis: VSSash.Axis
    var minimumFirst: CGFloat = 100
    var minimumSecond: CGFloat = 100
    var preferredFirst: CGFloat? = nil
    var showsSecond = true
    @ViewBuilder let first: () -> First
    @ViewBuilder let second: () -> Second
    @State private var draggingExtent: CGFloat?

    var body: some View {
        GeometryReader { geometry in
            let total = axis == .vertical ? geometry.size.width : geometry.size.height
            let room = max(0, total - ResizeSashView.thickness)
            let ratio = min(1, room / max(1, minimumFirst + minimumSecond))
            let lower = minimumFirst * ratio
            let upper = max(lower, room - minimumSecond * ratio)
            let initial = preferredFirst ?? room / 2
            let remembered = store.workbenchLayout.explorerHeights[id].map { CGFloat($0) }
            let extent = min(upper, max(lower, draggingExtent ?? remembered ?? initial))
            if axis == .vertical {
                HStack(spacing: 0) {
                    first().frame(width: showsSecond ? extent : nil).frame(maxWidth: .infinity, maxHeight: .infinity).clipped()
                    if showsSecond {
                        sash(extent: extent, remaining: room - extent, initial: initial, lower: lower, upper: upper)
                        second().frame(width: room - extent).frame(maxHeight: .infinity).clipped()
                    }
                }
            } else {
                VStack(spacing: 0) {
                    first().frame(height: showsSecond ? extent : nil).frame(maxWidth: .infinity, maxHeight: .infinity).clipped()
                    if showsSecond {
                        sash(extent: extent, remaining: room - extent, initial: initial, lower: lower, upper: upper)
                        second().frame(height: room - extent).frame(maxWidth: .infinity).clipped()
                    }
                }
            }
        }
    }

    private func sash(extent: CGFloat, remaining: CGFloat, initial: CGFloat, lower: CGFloat, upper: CGFloat) -> some View {
        VSSash(axis: axis, onDrag: { delta in
            draggingExtent = min(upper, max(lower, (draggingExtent ?? extent) + delta))
        }, onEnd: {
            if let draggingExtent { save(draggingExtent) }
            draggingExtent = nil
        }, onDoubleClick: {
            save(min(upper, max(lower, initial)))
        })
        .accessibilityElement()
        .accessibilityLabel(axis == .vertical ? "Editor widths" : "Pane heights")
        .accessibilityValue("\(Int(extent)) / \(Int(remaining)) points")
        .accessibilityAdjustableAction { direction in
            save(min(upper, max(lower, extent + (direction == .increment ? 20 : -20))))
        }
        .help("Drag to resize; double-click to reset sizes")
    }
    private func save(_ extent: CGFloat) {
        store.workbenchLayout.explorerHeights[id] = Double(extent)
        store.saveWorkbench()
    }
}
