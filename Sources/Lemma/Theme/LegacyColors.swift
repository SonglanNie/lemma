import SwiftUI
import AppKit
import LemmaCore

/// The current theme for code that may run off the main actor (NSColor providers, PDF drawing).
final class ThemeSnapshot: @unchecked Sendable {
    static let shared = ThemeSnapshot()
    private let lock = NSLock()
    private var stored: WorkbenchColors?
    var colors: WorkbenchColors? {
        get { lock.withLock { stored } }
        set { lock.withLock { stored = newValue } }
    }
    func rgba(_ key: TC, dark: Bool = true) -> RGBA {
        colors?.rgba(key) ?? WorkbenchColors.lastResort(key, dark: dark, values: [:])
    }
}

// Lemma's earlier palette names, now read from the colour theme. SwiftUI views that use them depend on the theme
// through Observation, so they redraw when it changes.
extension Color {
    /// The theme's accent (focus border, primary buttons, active tab edge). Olive was Lemma's colour before 2.0.
    @MainActor static var lemmaOlive: Color { ThemeManager.shared.colors.accent }
    /// A selected row.
    @MainActor static var lemmaOliveSelection: Color {
        ThemeManager.shared.style == .classic ? Color(nsColor: WorkbenchAccent.current.selectionColor) : ThemeManager.shared.colors[.listActiveSelectionBackground]
    }
    /// The editor's background (the page area, breadcrumbs, the active tab).
    @MainActor static var lemmaEditor: Color { ThemeManager.shared.colors[.editorBackground] }
    /// Activity bar, tab strip and status bar.
    @MainActor static var lemmaChrome: Color { ThemeManager.shared.colors[.activityBarBackground] }
    /// Side bars.
    @MainActor static var lemmaSidebar: Color { ThemeManager.shared.colors[.sideBarBackground] }
}

extension NSColor {
    static var lemmaOlive: NSColor { NSColor(name: "lemma.accent") { _ in ThemeSnapshot.shared.rgba(.focusBorder).nsColor } }
    static var lemmaOliveSelection: NSColor { NSColor(name: "lemma.selection") { _ in ThemeSnapshot.shared.rgba(.listActiveSelectionBackground).nsColor } }
    static var lemmaChrome: NSColor { NSColor(name: "lemma.chrome") { _ in ThemeSnapshot.shared.rgba(.activityBarBackground).nsColor } }
    static var lemmaSidebar: NSColor { NSColor(name: "lemma.sidebar") { _ in ThemeSnapshot.shared.rgba(.sideBarBackground).nsColor } }
}

extension RGBA {
    /// This colour made readable on `background` (contrast ≥ `ratio`), keeping its hue.
    func readable(on background: RGBA, ratio: Double = 4.5) -> RGBA {
        var colour = RGBA(r, g, b, 1)
        var step = 0
        let towardsDark = !background.isDark
        while colour.contrast(with: background) < ratio, step < 24 {
            colour = towardsDark ? colour.darken(0.12) : colour.lighten(0.12)
            if colour.relativeLuminance <= 0.0001 || colour.relativeLuminance >= 0.9999 { break }
            step += 1
        }
        return colour
    }
}
