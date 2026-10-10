import XCTest
import AppKit
import SwiftUI
@testable import Lemma

final class LabInputAppearanceTests: XCTestCase {
    /// Empty input has no syntax tokens to recolour it: typing and the caret must still follow the theme.
    @MainActor
    func testEmptyPythonInputFollowsTheThemeBeforeAndAfterSwitching() async throws {
        _ = NSApplication.shared
        let manager = ThemeManager.shared
        let savedStyle = manager.style
        let savedTheme = manager.selectedID
        let savedAuto = manager.autoDetect
        defer { manager.choose(savedTheme); manager.autoDetect = savedAuto; manager.style = savedStyle }
        manager.style = .vscode
        manager.autoDetect = false
        manager.choose("synthwave-84")

        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 480, height: 100), styleMask: .titled, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        let host = NSHostingView(rootView: LabCodeEditor(text: .constant(""), onRun: { _ in }, submitsOnReturn: true))
        window.contentView = host
        window.orderFront(nil)
        try await Task.sleep(for: .milliseconds(100))
        func find(_ view: NSView) -> LabTextView? {
            if let editor = view as? LabTextView { return editor }
            for child in view.subviews { if let editor = find(child) { return editor } }
            return nil
        }
        let editor = try XCTUnwrap(find(host))
        func check() {
            let expected = manager.colors.ns(.editorForeground).usingColorSpace(.sRGB)
            XCTAssertEqual(editor.insertionPointColor.usingColorSpace(.sRGB), expected)
            XCTAssertEqual((editor.typingAttributes[.foregroundColor] as? NSColor)?.usingColorSpace(.sRGB), expected)
        }
        check()
        manager.choose("light-2026")
        try await Task.sleep(for: .milliseconds(30))
        check()
    }
}
