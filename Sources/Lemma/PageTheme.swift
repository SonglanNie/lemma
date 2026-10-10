import AppKit
import PDFKit
import Accelerate
import LemmaCore

/// How the page is drawn on screen: the original paper, a warmer sepia, or a night page · light text on a dark page
/// whose colours keep their hue (an orange point stays orange, a blue heading blue). Captures, previews sent to
/// ChatGPT and exports always use the original page.
enum PageTheme: String, CaseIterable, Identifiable {
    case paper, sepia, night
    var id: String { rawValue }
    var label: String { switch self { case .paper: "Paper"; case .sepia: "Sepia"; case .night: "Night" } }
    var symbol: String { switch self { case .paper: "doc"; case .sepia: "doc.fill"; case .night: "moon" } }
    var isDark: Bool { self == .night }
}

/// The theme, read by pages as they draw (possibly off the main thread).
final class PageThemeState: @unchecked Sendable {
    static let shared = PageThemeState()
    private let lock = NSLock()
    private var current: PageTheme = .paper

    var theme: PageTheme {
        get { lock.withLock { current } }
        set { lock.withLock { current = newValue } }
    }
}

/// Pages of documents opened in the reader: they draw themselves in the current theme. The page is drawn into a
/// bitmap the size of the tile PDFKit asks for, its pixels are recoloured, and the bitmap is drawn in its place:
/// blend modes cannot be used because PDFKit paints the white paper separately from the page's content.
final class ThemedPage: PDFPage {
    override func draw(with box: PDFDisplayBox, to context: CGContext) {
        let theme = PageThemeState.shared.theme
        guard theme != .paper else { super.draw(with: box, to: context); return }
        let bounds = self.bounds(for: box)
        // PDFPage draws with the box's lower-left corner at the context's origin, whatever the box's own origin.
        guard rotation % 360 == 0 else { super.draw(with: box, to: context); return }
        let pageRect = CGRect(origin: .zero, size: bounds.size)
        let clip = context.boundingBoxOfClipPath.intersection(pageRect)
        guard !clip.isNull, clip.width > 0, clip.height > 0 else { return }
        let device = context.userSpaceToDeviceSpaceTransform
        let scale = max(0.25, min(8, hypot(device.a, device.b)))
        let width = Int(ceil(clip.width * scale)), height = Int(ceil(clip.height * scale))
        guard width > 0, height > 0, width * height < 40_000_000,
              let bitmap = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                     space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            super.draw(with: box, to: context); return
        }
        bitmap.setFillColor(CGColor(gray: 1, alpha: 1))
        bitmap.fill(CGRect(x: 0, y: 0, width: width, height: height))
        bitmap.scaleBy(x: CGFloat(width) / clip.width, y: CGFloat(height) / clip.height)
        bitmap.translateBy(x: -clip.minX, y: -clip.minY)
        super.draw(with: box, to: bitmap)
        guard let data = bitmap.data else { super.draw(with: box, to: context); return }
        ThemedPage.recolour(data.assumingMemoryBound(to: UInt8.self), width: width, height: height, theme: theme)
        guard let image = bitmap.makeImage() else { super.draw(with: box, to: context); return }
        context.saveGState()
        context.interpolationQuality = .none
        context.draw(image, in: clip)
        context.restoreGState()
    }

    /// Night: luminance inverted and hue kept (out = c + 1 − 2Y), then mapped into the editor's greys.
    /// Sepia: the paper tinted warm, ink kept dark.
    ///
    /// Done with vImage on PDFKit's tile threads: the inversion is a 4×4 matrix (its saturation is the clamp to
    /// 0…255), the mapping into greys a lookup table. The bitmap is opaque (drawn on white), so premultiplication
    /// does not matter; channels are in memory order R, G, B, A.
    static func recolour(_ pixels: UnsafeMutablePointer<UInt8>, width: Int, height: Int, theme: PageTheme) {
        guard theme != .paper, width > 0, height > 0 else { return }
        var buffer = vImage_Buffer(data: pixels, height: vImagePixelCount(height), width: vImagePixelCount(width), rowBytes: width * 4)
        switch theme {
        case .paper: return
        case .sepia:
            _ = vImageMatrixMultiply_ARGB8888(&buffer, &buffer, sepiaMatrix, 1024, nil, nil, vImage_Flags(kvImageNoFlags))
        case .night:
            _ = vImageMatrixMultiply_ARGB8888(&buffer, &buffer, nightMatrix, 8192, nil, nightBias, vImage_Flags(kvImageNoFlags))
            nightGreys.withUnsafeBufferPointer { greys in
                _ = vImageTableLookUp_ARGB8888(&buffer, &buffer, greys.baseAddress, greys.baseAddress, greys.baseAddress, nil, vImage_Flags(kvImageNoFlags))
            }
        }
    }

    /// out[i] = Σ in[j] · m[4j + i] / divisor, with power-of-two divisors so that alpha stays exactly 255 (results are
    /// within one level of the former per-pixel loop). Sepia scales each colour channel by (0.965, 0.925, 0.835).
    private static let sepiaMatrix: [Int16] = [988, 0, 0, 0, 0, 947, 0, 0, 0, 0, 855, 0, 0, 0, 0, 1024]
    /// Night: c + 255 − 2Y with Y = 0.2126 R + 0.7152 G + 0.0722 B, in 8192ths (2Y's weights sum to exactly 2 · 8192).
    private static let nightMatrix: [Int16] = [
        8192 - 3483, -3483, -3483, 0,
        -11_718, 8192 - 11_718, -11_718, 0,
        -1183, -1183, 8192 - 1183, 0,
        0, 0, 0, 8192
    ]
    private static let nightBias: [Int32] = [255 * 8192, 255 * 8192, 255 * 8192, 0]
    /// The inverted values mapped into the editor's greys, 30 … 222 (0.118 … 0.87 of 255).
    private static let nightGreys: [Pixel_8] = (0...255).map { value in
        let floor: Float = 30, span: Float = 192
        return Pixel_8(floor + Float(value) * span / 255)
    }
}

/// Makes documents create `ThemedPage`s; set as the delegate before any page is read.
final class ThemedPageProvider: NSObject, PDFDocumentDelegate, @unchecked Sendable {
    static let shared = ThemedPageProvider()
    func classForPage() -> AnyClass { ThemedPage.self }
}

extension NSColor {
    /// Marks drawn over the page (reference underlines, counts, the flash after Go to): the theme's accent, made
    /// readable on the paper (darker on a white or sepia page, lighter on a night page). Computed once per accent and
    /// page brightness: it is asked for by every mark laid over the page.
    static var lemmaOliveOnPage: NSColor {
        OnPageAccent.shared.color(accent: ThemeSnapshot.shared.rgba(.focusBorder), dark: PageThemeState.shared.theme.isDark)
    }
    /// Secondary text drawn on the page, such as reference counts.
    static var lemmaPageSecondary: NSColor { PageThemeState.shared.theme.isDark ? NSColor(white: 0.62, alpha: 1) : NSColor(white: 0.42, alpha: 1) }
    /// The paper colour of panels laid over the page (folded proofs).
    static var lemmaPagePaper: NSColor {
        switch PageThemeState.shared.theme {
        case .paper: NSColor(srgbRed: 0.984, green: 0.98, blue: 0.961, alpha: 1)
        case .sepia: NSColor(srgbRed: 0.95, green: 0.91, blue: 0.82, alpha: 1)
        case .night: NSColor(srgbRed: 0.16, green: 0.165, blue: 0.15, alpha: 1)
        }
    }
    /// The veil the reading ruler lays over the rest of the page.
    static var lemmaPageVeil: NSColor { PageThemeState.shared.theme.isDark ? NSColor(white: 0.07, alpha: 0.62) : NSColor(white: 1, alpha: 0.58) }
}

/// The last accent made readable on the page; the theme changes rarely, so one entry is enough.
private final class OnPageAccent: @unchecked Sendable {
    static let shared = OnPageAccent()
    private let lock = NSLock()
    private var cached: (accent: RGBA, dark: Bool, color: NSColor)?

    func color(accent: RGBA, dark: Bool) -> NSColor {
        lock.withLock {
            if let cached, cached.accent == accent, cached.dark == dark { return cached.color }
            let paper = dark ? RGBA(0.118, 0.118, 0.118) : RGBA(1, 1, 1)
            let color = accent.readable(on: paper, ratio: 4.5).nsColor
            cached = (accent, dark, color)
            return color
        }
    }
}

@MainActor
extension StudyStore {
    var pageTheme: PageTheme {
        get { PageTheme(rawValue: UserDefaults.standard.string(forKey: LemmaPreferences.pageTheme) ?? "") ?? .paper }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: LemmaPreferences.pageTheme)
            applyPageTheme()
        }
    }

    func cyclePageTheme() {
        let all = PageTheme.allCases
        pageTheme = all[((all.firstIndex(of: pageTheme) ?? 0) + 1) % all.count]
        status = "Page: \(pageTheme.label)"
    }

    /// Redraws every open view of the book in the current theme: the reader, and the side editors and peeks, which share
    /// its document but keep their own tiles.
    func applyPageTheme() {
        let theme = pageTheme
        PageThemeState.shared.theme = theme
        pageThemeRevision += 1
        let main = reader.view
        for window in NSApp.windows where window.isVisible {
            for view in window.contentView?.pdfViews() ?? [] where view !== main && view.document != nil {
                // The side editor redraws when SwiftUI hands it the new revision; peeks and others are redrawn here.
                if view is SecondaryPDFView { continue }
                view.redrawPages()
            }
        }
        guard let view = main, view.document != nil else { return }
        view.backgroundColor = theme.isDark ? NSColor(white: 0.085, alpha: 1) : ThemeManager.shared.colors.pageCanvas.nsColor
        view.redrawPages()
        reader.updatePage()
        view.refreshCaptureOverlay()
    }
}

extension PDFView {
    /// PDFKit keeps the tiles it has drawn; giving the view its document again redraws every page, in place.
    func redrawPages() {
        guard let document else { return }
        let destination = currentDestination, highlighted = highlightedSelections
        let scale = scaleFactor, automatic = autoScales
        self.document = nil
        self.document = document
        autoScales = automatic
        if !automatic { scaleFactor = scale }
        if let destination { go(to: destination) }
        if let highlighted { highlightedSelections = highlighted }
    }
}

extension NSView {
    /// The PDF views in this view's hierarchy.
    func pdfViews() -> [PDFView] {
        if let view = self as? PDFView { return [view] }
        return subviews.flatMap { $0.pdfViews() }
    }
}
