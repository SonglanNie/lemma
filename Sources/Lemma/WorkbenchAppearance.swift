import SwiftUI
import AppKit
import PDFKit
import LemmaCore

@MainActor
extension StudyStore {
    /// Gives AppKit-drawn views the theme's colours: the PDF canvas, marks over the page, the overlay.
    func applyAppearance() {
        let colors = ThemeManager.shared.colors
        if let view = reader.view {
            view.backgroundColor = PageThemeState.shared.theme.isDark ? NSColor(white: 0.085, alpha: 1) : colors.pageCanvas.nsColor
            view.refreshCaptureOverlay()
        }
    }
}
