import XCTest
import AppKit
import WebKit
import LemmaCore
@testable import Lemma

/// 3.2's design pass on the Assistants sheet and the saved explanations: the page that went blank on a tab switch,
/// explanations that would not scroll, and menus a theme's accent made invisible.
final class AssistantDesignTests: XCTestCase {
    @MainActor
    func testEveryThemesAccentIsReadableOnTheEditor() throws {
        let manager = ThemeManager.shared
        for entry in manager.entries {
            let theme = try XCTUnwrap(manager.theme(entry.id), entry.label)
            let colors = WorkbenchColors(theme: theme, defaults: manager.defaultsForPreview)
            let editor = colors.rgba(.editorBackground)
            XCTAssertGreaterThanOrEqual(colors.accentRGBA.contrast(with: editor), 3, "\(entry.label): menus and icons tinted with the accent stay visible")
        }
        // A theme whose focus border is readable keeps it as its accent; SynthWave '84's is meant to be nearly invisible.
        for id in ["lemma-dark", "lemma-light", "dark-2026", "light-2026"] {
            let colors = WorkbenchColors(theme: try XCTUnwrap(manager.theme(id)), defaults: manager.defaultsForPreview)
            XCTAssertEqual(colors.accentRGBA.hex, colors.rgba(.focusBorder).hex, id)
        }
        let synthwave = WorkbenchColors(theme: try XCTUnwrap(manager.theme("synthwave-84")), defaults: manager.defaultsForPreview)
        XCTAssertLessThan(synthwave.rgba(.focusBorder).contrast(with: synthwave.rgba(.editorBackground)), 3)
        XCTAssertNotEqual(synthwave.accentRGBA.hex, synthwave.rgba(.focusBorder).hex)
    }

    @MainActor
    func testTheChatGPTPageStaysInTheNewestHostWhenSwiftUITearsDownTheOldOne() {
        let page = WKWebView(frame: .zero)
        let shown = AssistantWebView.Host(page)
        XCTAssertTrue(page.superview === shown)
        // Switching tabs makes the new host first, then tears the old one down: the page went blank in 3.1.
        let next = AssistantWebView.Host(page)
        XCTAssertTrue(page.superview === next)
        shown.release()
        XCTAssertTrue(page.superview === next, "The page stays in the host that shows it")
        next.release()
        XCTAssertNil(page.superview)
    }

    @MainActor
    func testScrollingOverATypesetPreviewScrollsItsPane() throws {
        _ = NSApplication.shared
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 300), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        final class Flipped: NSView { override var isFlipped: Bool { true } }
        let pane = NSScrollView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
        let document = Flipped(frame: NSRect(x: 0, y: 0, width: 400, height: 2000))
        pane.documentView = document
        window.contentView = pane
        // A preview is as tall as its page, inside the pane's scroll view (a saved explanation in the Notes inspector).
        let preview = MathWebView(dataStore: .nonPersistent())
        preview.frame = NSRect(x: 0, y: 300, width: 400, height: 900)
        document.addSubview(preview)
        pane.contentView.scroll(to: NSPoint(x: 0, y: 400))
        pane.reflectScrolledClipView(pane.contentView)
        let before = pane.contentView.bounds.origin.y

        func gesture(_ steps: [(phase: Int64, dx: Double, dy: Double)]) {
            for step in steps {
                guard let event = Self.scroll(phase: step.phase, dx: step.dx, dy: step.dy) else { continue }
                preview.scrollWheel(with: event)
                RunLoop.current.run(until: Date().addingTimeInterval(0.02))
            }
        }
        // Fingers moving up: the pane shows what is further down, as it does over any other part of the note.
        gesture([(1, 0, -30), (2, 0, -30), (2, 0, -30), (4, 0, 0)])
        XCTAssertGreaterThan(pane.contentView.bounds.origin.y, before + 10, "The pane follows a vertical gesture over the preview")
    }

    @MainActor
    func testAGestureKeepsTheDirectionItStartedWith() throws {
        // A gesture that starts sideways belongs to the page (a wide equation scrolls across), even when it drifts down;
        // one that starts down belongs to the pane through its momentum. A mouse wheel decides notch by notch.
        var gesture: Bool?
        let sideways = try [(1, -30.0, -2.0), (2, -20, -25), (4, 0, 0)].map { try XCTUnwrap(Self.scroll(phase: Int64($0.0), dx: $0.1, dy: $0.2)) }
        XCTAssertEqual(sideways.map { MathWebView.scrollsPage($0, gesture: &gesture) }, [true, true, true])
        let down = try [(1, 0.0, -30.0), (2, -40, -5), (4, 0, 0)].map { try XCTUnwrap(Self.scroll(phase: Int64($0.0), dx: $0.1, dy: $0.2)) }
        XCTAssertEqual(down.map { MathWebView.scrollsPage($0, gesture: &gesture) }, [false, false, false])
        let momentum = try XCTUnwrap(Self.scroll(phase: 0, momentum: 2, dx: -30, dy: -1))
        XCTAssertFalse(MathWebView.scrollsPage(momentum, gesture: &gesture), "Momentum follows its gesture")
        let notch = try XCTUnwrap(Self.scroll(phase: 0, dx: 0, dy: -3, continuous: false))
        XCTAssertFalse(MathWebView.scrollsPage(notch, gesture: &gesture))
    }

    /// A scroll event as a trackpad (continuous, with phases) or a mouse wheel makes one.
    private static func scroll(phase: Int64, momentum: Int64 = 0, dx: Double, dy: Double, continuous: Bool = true) -> NSEvent? {
        guard let cg = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 2, wheel1: Int32(dy), wheel2: Int32(dx), wheel3: 0) else { return nil }
        cg.setIntegerValueField(.scrollWheelEventIsContinuous, value: continuous ? 1 : 0)
        cg.setIntegerValueField(.scrollWheelEventScrollPhase, value: phase)
        cg.setIntegerValueField(.scrollWheelEventMomentumPhase, value: momentum)
        cg.setDoubleValueField(.scrollWheelEventPointDeltaAxis1, value: dy)
        cg.setDoubleValueField(.scrollWheelEventPointDeltaAxis2, value: dx)
        return NSEvent(cgEvent: cg)
    }
}
