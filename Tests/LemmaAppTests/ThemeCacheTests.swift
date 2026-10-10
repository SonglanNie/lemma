import XCTest
import AppKit
import LemmaCore
@testable import Lemma

/// Colours are resolved once per theme and their colour objects kept: views read dozens of them at every redraw.
final class ThemeCacheTests: XCTestCase {
    @MainActor
    func testColoursAreResolvedOnceAndKept() throws {
        let manager = ThemeManager.shared
        let colors = manager.colors
        XCTAssertTrue(colors.ns(.editorBackground) === colors.ns(.editorBackground), "The same colour object, not a new one per read")
        XCTAssertTrue(colors.token(.keyword) === colors.token(.keyword))
        // A colour no theme names still gets its stand-in, worked out once.
        let dark = colors.isDark
        let expected = WorkbenchColors.fallbacks[.listDropBackground].flatMap { colors.has($0) ? colors.rgba($0) : nil }
            ?? WorkbenchColors.lastResort(.listDropBackground, dark: dark, values: [:])
        if !colors.has(.listDropBackground) {
            XCTAssertEqual(colors.rgba(.listDropBackground).a, expected.a, accuracy: 0.0001)
        }
        let id = try XCTUnwrap(manager.entries.first?.id)
        let first = try XCTUnwrap(manager.previewColors(for: id)), second = try XCTUnwrap(manager.previewColors(for: id))
        XCTAssertTrue(first.ns(.editorBackground) === second.ns(.editorBackground), "A theme's miniature colours are kept")
        XCTAssertEqual(first.theme.id, id)
    }
}
