import XCTest
import AppKit
import PDFKit
import SwiftUI
import LemmaCore
@testable import Lemma

/// Lemma 2.0's workbench: VS Code colour themes, the Classic style, special editors, settings and Run and Debug.
final class WorkbenchStyleTests: XCTestCase {
    @MainActor
    func testRestartRestoresTheSpecialEditorInFrontOfAnOpenBook() throws {
        ThemeManager.shared.style = .vscode
        let fixture = try WorkbenchFixture()
        defer { fixture.close() }
        let store = fixture.store
        store.open(fixture.book)
        let bookID = try XCTUnwrap(store.workspace?.id)
        for editor in [SpecialEditor.settings, .welcome] {
            store.openSpecial(editor)
            store.flush()
            let restarted = StudyStore(app: AppModel(root: store.repository.root))
            restarted.app.restore()
            XCTAssertEqual(restarted.workspace?.id, bookID)
            XCTAssertEqual(restarted.activeSpecial, editor, "Reopening the book must preserve the tab that was in front.")
            let session = try JSONDecoder().decode(WorkbenchSession.self, from: Data(contentsOf: restarted.app.sessionURL))
            XCTAssertEqual(session.windows.first?.activeSpecial, editor, "The restored active editor must also remain saved.")
            restarted.flush()
        }
    }

    private var savedDefaults: [String: Any?] = [:]
    private let keys = [ThemePreferences.colorTheme, ThemePreferences.autoDetect, ThemePreferences.style, ThemePreferences.accent,
                        "workbench.theme", "workbench.accent", "workbench.startupEditor"]

    @MainActor override func setUp() async throws {
        _ = NSApplication.shared
        for key in keys { savedDefaults[key] = UserDefaults.standard.object(forKey: key) }
    }

    @MainActor override func tearDown() async throws {
        for key in keys {
            if let value = savedDefaults[key] ?? nil { UserDefaults.standard.set(value, forKey: key) } else { UserDefaults.standard.removeObject(forKey: key) }
        }
        ThemeManager.shared.style = WorkbenchStyle(rawValue: UserDefaults.standard.string(forKey: ThemePreferences.style) ?? "") ?? .vscode
        ThemeManager.shared.apply()
    }

    @MainActor
    func testEveryBundledThemeLoadsAndResolvesTheWorkbenchColours() throws {
        let manager = ThemeManager.shared
        XCTAssertGreaterThanOrEqual(manager.entries.count, 80, "VS Code's themes, Lemma's and the community's are bundled.")
        for id in ["dark-2026", "light-2026", "dark-modern", "light-modern", "hc-black", "moonlight", "moonlight-ii", "synthwave-84", "lemma-midnight"] {
            XCTAssertNotNil(manager.entry(id), "\(id) is bundled")
        }
        for entry in manager.entries {
            let theme = try XCTUnwrap(manager.theme(entry.id), "\(entry.label) loads")
            XCTAssertEqual(theme.kind.isDark, entry.kind.isDark, entry.label)
            let colors = WorkbenchColors(theme: theme, defaults: manager.defaultsForPreview)
            // Text must stay readable on the main surfaces, whatever the theme.
            let editor = colors.rgba(.editorBackground).over(RGBA(0.5, 0.5, 0.5))
            XCTAssertGreaterThan(colors.rgba(.editorForeground).over(editor).contrast(with: editor), 2.2, "\(entry.label): editor text")
            XCTAssertNotEqual(colors.rgba(.sideBarBackground).hex, "", entry.label)
        }
    }

    @MainActor
    func testChoosingAThemeChangesEverySurfaceAtOnce() throws {
        let manager = ThemeManager.shared
        manager.style = .vscode
        manager.autoDetect = false
        manager.choose("moonlight-ii")
        XCTAssertEqual(manager.colors.theme.name, "Moonlight II")
        XCTAssertEqual(manager.colors.rgba(.sideBarBackground).hex, "#1E2030")
        XCTAssertEqual(ThemeSnapshot.shared.colors?.rgba(.sideBarBackground).hex, "#1E2030", "AppKit drawing reads the same theme.")
        XCTAssertEqual(NSApp.appearance?.name, .darkAqua)
        manager.choose("light-2026")
        XCTAssertFalse(manager.colors.isDark)
        XCTAssertEqual(NSApp.appearance?.name, .aqua)
        // Previewing (the picker's arrow keys) and cancelling returns to the chosen theme.
        manager.preview("lemma-midnight")
        XCTAssertEqual(manager.colors.theme.name, "Lemma Midnight")
        manager.preview(nil)
        XCTAssertEqual(manager.colors.theme.name, "Light 2026")
    }

    @MainActor
    func testClassicStyleKeepsLemma11sThemesAndMidnightNowTintsTheEditor() throws {
        let manager = ThemeManager.shared
        manager.style = .classic
        UserDefaults.standard.set("graphite", forKey: "workbench.theme")
        UserDefaults.standard.set("olive", forKey: "workbench.accent")
        manager.apply()
        let graphite = manager.colors
        XCTAssertEqual(graphite.theme.origin, "classic")
        XCTAssertTrue(graphite.isDark)
        UserDefaults.standard.set("midnight", forKey: "workbench.theme")
        manager.apply()
        let midnight = manager.colors
        XCTAssertNotEqual(midnight.rgba(.editorBackground).hex, graphite.rgba(.editorBackground).hex, "Midnight is visible in the editor, not only in the bars.")
        XCTAssertGreaterThan(midnight.rgba(.editorBackground).b, midnight.rgba(.editorBackground).r, "Midnight is blue.")
        XCTAssertEqual(midnight.rgba(.activityBarBackground).hex, RGBA(0.07, 0.09, 0.14).hex)
        UserDefaults.standard.set("blue", forKey: "workbench.accent")
        manager.apply()
        XCTAssertEqual(manager.colors.rgba(.focusBorder).hex, RGBA(WorkbenchAccent.blue.color(dark: true)).hex)
        manager.style = .vscode
        XCTAssertNotEqual(manager.colors.theme.origin, "classic")
        XCTAssertEqual(UserDefaults.standard.string(forKey: ThemePreferences.style), "vscode")
    }

    @MainActor
    func testInstallingAVSCodeThemeFile() throws {
        let manager = ThemeManager.shared
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        // Installing writes into the support folder: the test's own, never the reader's.
        let installed = manager.installedDirectory
        manager.installedDirectory = folder.appendingPathComponent("Themes", isDirectory: true)
        defer { manager.installedDirectory = installed; manager.reloadEntries() }
        let file = folder.appendingPathComponent("my-theme.json")
        try """
        // Exported from VS Code
        { "name": "Test Plum \(UUID().uuidString.prefix(6))", "type": "dark",
          "colors": { "editor.background": "#2B1B2E", "sideBar.background": "#24162A", },
          "tokenColors": [ { "scope": "keyword", "settings": { "foreground": "#FF79C6" } } ] }
        """.write(to: file, atomically: true, encoding: .utf8)
        let entry = try XCTUnwrap(try manager.install(from: file).first)
        defer { manager.uninstall(entry.id) }
        XCTAssertEqual(entry.group, "Installed")
        XCTAssertEqual(entry.kind, .dark)
        manager.style = .vscode
        manager.autoDetect = false
        manager.choose(entry.id)
        XCTAssertEqual(manager.colors.rgba(.sideBarBackground).hex, "#24162A")
        XCTAssertEqual(RGBA(manager.colors.token(.keyword)).hex, "#FF79C6")
        manager.uninstall(entry.id)
        XCTAssertNil(manager.entry(entry.id))
    }

    @MainActor
    func testSettingsAreUniqueAndRoundTrip() throws {
        let fixture = try WorkbenchFixture()
        defer { fixture.close() }
        let items = SettingsRegistry.items(store: fixture.store)
        XCTAssertEqual(Set(items.map(\.id)).count, items.count, "One row per setting.")
        let style = try XCTUnwrap(items.first { $0.id == ThemePreferences.style })
        style.set("classic")
        XCTAssertEqual(ThemeManager.shared.style, .classic)
        XCTAssertTrue(style.isModified)
        style.set("vscode")
        XCTAssertFalse(style.isModified)
        let minimap = try XCTUnwrap(items.first { $0.id == "editor.minimap.enabled" })
        minimap.set("false")
        XCTAssertFalse(fixture.store.app.showMinimap)
        minimap.set("true")
        XCTAssertTrue(items.filter(\.commonlyUsed).count >= 6)
        XCTAssertTrue(try XCTUnwrap(items.first { $0.id == "workbench.colorTheme" }).matches("color theme"))
        // Every value of every setting is applied and read back (a setting written where nothing reads it fails here).
        for item in items {
            let before = item.get()
            switch item.control {
            case .toggle:
                for value in ["false", "true"] { item.set(value); XCTAssertEqual(item.get(), value, "\(item.id) = \(value)") }
            case let .choice(options):
                for option in options.prefix(12) { item.set(option.value); XCTAssertEqual(item.get(), option.value, "\(item.id) = \(option.value)") }
            default: continue
            }
            item.set(before)
        }
        ThemeManager.shared.style = .vscode
    }

    @MainActor
    func testSpecialEditorsOpenAsTabsAndClassicKeepsItsWindowsAndSheets() throws {
        let fixture = try WorkbenchFixture()
        defer { fixture.close() }
        let store = fixture.store
        ThemeManager.shared.style = .vscode
        store.open(fixture.book)
        store.openSettingsEditor()
        XCTAssertEqual(store.activeSpecial, .settings)
        XCTAssertEqual(store.specialTabs, [.settings])
        XCTAssertEqual(store.activeMainTabID, SpecialEditor.settings.id)
        store.activateMainTab(try XCTUnwrap(store.workspace?.id))
        XCTAssertNil(store.activeSpecial, "Choosing the book's tab brings the book back in front.")
        store.openSpecial(.shortcuts)
        store.closeSpecial(.shortcuts)
        XCTAssertNil(store.activeSpecial)
        XCTAssertEqual(store.specialTabs, [.settings])
        ThemeManager.shared.style = .classic
        store.openShortcutsEditor()
        XCTAssertTrue(store.showShortcuts, "Classic shows 1.1's shortcuts sheet.")
        store.openSpecial(.releaseNotes)
        XCTAssertTrue(store.showReleaseNotes)
        ThemeManager.shared.style = .vscode
    }

    @MainActor
    func testRunAndDebugStepsThroughAProofAndIntoWhatItCites() async throws {
        let fixture = try WorkbenchFixture(hosted: true)
        defer { fixture.close() }
        let store = fixture.store
        let source = try XCTUnwrap(Bundle.module.url(forResource: "book-chapters", withExtension: "pdf", subdirectory: "Fixtures"))
        let copy = fixture.root.appendingPathComponent("Notes_on_Linear_Smoothers.pdf")
        try FileManager.default.copyItem(at: source, to: copy)
        store.open(copy)
        try await fixture.waitForAnalysis()
        try await fixture.settle()
        let theorem = ReferenceKey(kind: .theorem, number: "1.3", name: "Theorem")
        store.goToKey(theorem)
        try await fixture.settle()
        store.startDebugging(at: theorem)
        let session = try XCTUnwrap(store.debug)
        XCTAssertEqual(session.frames.map(\.key), [theorem])
        XCTAssertTrue(store.reader.rulerMode && store.reader.debugging)
        XCTAssertNotNil(store.debugGoal()?.image, "The statement being proved is rendered from the page.")
        let start = try XCTUnwrap(store.reader.rulerLine)
        store.debugStepOver()
        XCTAssertNotEqual(store.reader.rulerLine, start)
        // Step into the first result the proof cites (Definition 1.1 or Lemma 1.2), then back out.
        var steps = 0
        while store.debug?.frames.count == 1, steps < 60 { store.debugStepInto(); steps += 1 }
        let inner = try XCTUnwrap(store.debug?.frames.last)
        XCTAssertNotEqual(inner.key, theorem, "Stepping into a citation pushes a frame.")
        XCTAssertEqual(store.debug?.frames.count, 2)
        store.debugStepOut()
        XCTAssertEqual(store.debug?.frames.count, 1)
        // A breakpoint is where Continue stops.
        store.debugRestart()
        store.debugStepOver(); store.debugStepOver()
        store.toggleBreakpoint()
        XCTAssertEqual(store.breakpoints.count, 1)
        let marked = try XCTUnwrap(store.reader.rulerLine)
        store.debugRestart()
        store.debugContinue()
        XCTAssertEqual(store.reader.rulerLine, marked)
        store.debugContinue()
        XCTAssertEqual(store.debug?.finished, true, "Without another breakpoint, Continue runs to the end of the proof.")
        store.addWatch("Lemma 1.2")
        XCTAssertEqual(store.evaluateWatch("Lemma 1.2").target?.key.number, "1.2")
        store.stopDebugging()
        XCTAssertNil(store.debug)
        XCTAssertFalse(store.reader.rulerMode, "Stopping puts the ruler away when debugging had taken it out.")
        store.saveWorkbench()
        let saved = try JSONDecoder().decode(WorkbenchSession.self, from: Data(contentsOf: store.app.sessionURL))
        XCTAssertEqual(saved.books[try XCTUnwrap(store.workspace?.id)]?.breakpoints.count, 1, "Breakpoints are kept with the book's session.")
    }

    @MainActor
    func testSteppingWithoutARulerLineDoesNotRecurse() async throws {
        let fixture = try WorkbenchFixture(hosted: true)
        defer { fixture.close() }
        let store = fixture.store
        let source = try XCTUnwrap(Bundle.module.url(forResource: "book-chapters", withExtension: "pdf", subdirectory: "Fixtures"))
        let copy = fixture.root.appendingPathComponent("Notes_on_Linear_Smoothers.pdf")
        try FileManager.default.copyItem(at: source, to: copy)
        store.open(copy)
        try await fixture.waitForAnalysis()
        try await fixture.settle()
        store.startDebugging()
        XCTAssertNotNil(store.debug)
        // F11, F5 and F10 with no line under the ruler (after scrolling to a page of figures, say) called one another
        // until the stack overflowed.
        for step in [store.debugStepInto, store.debugContinue, store.debugStepOver, store.debugStepBack] {
            store.reader.rulerLine = nil
            step()
            XCTAssertNotNil(store.debug, "The session goes on.")
        }
        store.stopDebugging()
    }

    @MainActor
    func testEveryCodiconHasAGlyphAndASystemSymbolForTheClassicStyle() throws {
        // Reading the table also proves it has no duplicate keys (a duplicate traps at run time).
        XCTAssertGreaterThan(Codicons.fallbackSymbol.count, 150)
        for (codicon, symbol) in Codicons.fallbackSymbol {
            XCTAssertNotNil(NSImage(systemSymbolName: symbol, accessibilityDescription: nil), "\(codicon) → \(symbol) is an SF Symbol")
            if Codicons.isAvailable { XCTAssertNotNil(Codicons.mapping[codicon], "\(codicon) is a codicon") }
        }
        for symbol in Codicons.systemSymbols {
            XCTAssertNotNil(NSImage(systemSymbolName: symbol, accessibilityDescription: nil), "\(symbol) is an SF Symbol")
            XCTAssertNil(Codicons.mapping[symbol], "\(symbol) has no codicon, or the codicon would be drawn")
        }
    }

    @MainActor
    func testLibrarySearchFindsWordsAcrossBooksAndKeepsTheirText() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("lemma-search-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let source = try XCTUnwrap(Bundle.module.url(forResource: "book-chapters", withExtension: "pdf", subdirectory: "Fixtures"))
        func finish(_ search: LibraryTextSearch) async throws {
            let deadline = Date.now.addingTimeInterval(20)
            while search.isSearching, Date.now < deadline { try await Task.sleep(for: .milliseconds(50)) }
            XCTAssertFalse(search.isSearching)
        }
        // Without the helper (tests, `swift run`) the text is read here and written beside the analysis.
        let search = LibraryTextSearch(cacheFolder: root, helper: nil)
        let books = [("notes", "Notes on Linear Smoothers", source.path), ("gone", "Gone", root.appendingPathComponent("missing.pdf").path)]
        search.query = "smoother"
        search.run(books: books)
        try await finish(search)
        XCTAssertEqual(search.results.map(\.id), ["notes"])
        XCTAssertGreaterThan(search.hitCount, 2)
        XCTAssertEqual(search.unreadableBooks, 1, "A book whose PDF cannot be read is reported, not counted as having no match.")
        let saved = try XCTUnwrap(PageTextFile.read(root.appendingPathComponent("notes/pagetext.json")))
        XCTAssertTrue(saved.contains { $0.text.contains("Nadaraya") })
        let all = search.hitCount
        search.query = "Smoother"; search.matchCase = true
        search.run(books: books)
        try await finish(search)
        XCTAssertLessThan(search.hitCount, all, "Match Case leaves out “smoother”.")
        search.query = "smooth"; search.matchCase = false; search.wholeWord = true
        search.run(books: books)
        try await finish(search)
        XCTAssertTrue(search.results.flatMap(\.hits).allSatisfy { $0.match.lowercased() == "smooth" }, "Whole Word leaves out “smoother”.")

        // Where every match is, beyond the matches listed, for the book being read.
        let marked = LibraryTextSearch.search(book: books[0], query: "smoother", matchCase: false, wholeWord: false,
                                              cache: PageTextCache(folder: root, helper: nil), limit: 2, ranges: true)
        XCTAssertEqual(marked.hits.count, 2)
        XCTAssertTrue(marked.truncated)
        XCTAssertEqual(marked.ranges.count, all, "Every match is marked, not only those listed.")

        // The packaged app has the helper write the file; one that fails is not tried again this session.
        let log = root.appendingPathComponent("runs.log")
        func helper(_ name: String, _ body: String) throws -> URL {
            let url = root.appendingPathComponent(name)
            try "#!/bin/sh\necho run >> '\(log.path)'\n\(body)\n".write(to: url, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
            return url
        }
        let writes = try helper("writes.sh", #"mkdir -p "$(dirname "$4")"; printf '[{"text":"A kernel smoother","label":"xii"}]' > "$4""#)
        let cache = PageTextCache(folder: root.appendingPathComponent("out", isDirectory: true), helper: writes)
        await cache.prepare(id: "b", path: source.path)
        XCTAssertEqual(cache.pages(for: "b", path: source.path), [PageText(text: "A kernel smoother", label: "xii")])
        await cache.prepare(id: "b", path: source.path)
        let fails = try helper("fails.sh", "exit 1")
        let broken = PageTextCache(folder: root.appendingPathComponent("broken", isDirectory: true), helper: fails)
        await broken.prepare(id: "c", path: source.path)
        XCTAssertNil(broken.pages(for: "c", path: source.path), "Without the helper's file the app does not read the PDF itself.")
        await broken.prepare(id: "c", path: source.path)
        XCTAssertEqual(try String(contentsOf: log, encoding: .utf8).split(separator: "\n").count, 2, "Each helper ran once.")
    }

    @MainActor
    func testSearchingTheLibraryMarksTheOpenBookWithoutMovingIt() async throws {
        let fixture = try WorkbenchFixture(hosted: true)
        defer { fixture.close() }
        let store = fixture.store
        let source = try XCTUnwrap(Bundle.module.url(forResource: "book-chapters", withExtension: "pdf", subdirectory: "Fixtures"))
        let copy = fixture.root.appendingPathComponent("Notes_on_Linear_Smoothers.pdf")
        try FileManager.default.copyItem(at: source, to: copy)
        store.open(copy)
        try await fixture.settle()
        let page = store.reader.view?.currentPage
        store.app.librarySearch.query = "smoother"
        store.runLibrarySearch()
        let deadline = Date.now.addingTimeInterval(20)
        while store.app.librarySearch.isSearching || store.reader.isSearching, Date.now < deadline { try await Task.sleep(for: .milliseconds(50)) }
        let listed = try XCTUnwrap(store.app.librarySearch.results.first { $0.id == store.workspace?.id })
        XCTAssertEqual(store.reader.searchResults.count, listed.hits.count, "The open book's matches mark its minimap and ruler.")
        XCTAssertTrue(store.reader.searchResults.allSatisfy { $0.string?.lowercased() == "smoother" }, "Cached ranges select the words PDFKit sees.")
        XCTAssertTrue(store.reader.view?.currentPage === page, "Searching does not move the page.")
        store.app.librarySearch.clear(); store.reader.resetSearch()
        XCTAssertTrue(store.reader.searchResults.isEmpty)
    }

    @MainActor
    func testTheVSCodeTitleBarStaysTransparentWhenSwiftUISetsItUpAgain() throws {
        _ = NSApplication.shared
        ThemeManager.shared.style = .vscode
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 900, height: 600), styleMask: [.titled, .closable, .miniaturizable, .resizable],
                              backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        TitleBarCoordinator.shared.attach(window)
        XCTAssertTrue(window.titlebarAppearsTransparent)
        XCTAssertTrue(window.styleMask.contains(.fullSizeContentView))
        // At launch SwiftUI configures the window again after Lemma did; the native bar then covered Lemma's own.
        window.titlebarAppearsTransparent = false
        XCTAssertTrue(window.titlebarAppearsTransparent, "The transparent title bar is put back at once.")
        window.titleVisibility = .visible
        XCTAssertEqual(window.titleVisibility, .hidden)
        ThemeManager.shared.style = .classic
        TitleBarCoordinator.shared.attach(window)
        XCTAssertFalse(window.titlebarAppearsTransparent, "Classic keeps the native title bar.")
        ThemeManager.shared.style = .vscode
    }

    @MainActor
    func testSpinningIconsTurnInCoreAnimation() throws {
        // A SwiftUI animation repeated forever kept redrawing the window after a save had ended (10–35 % CPU at rest).
        let view = SpinningCodicon.SpinnerView(frame: NSRect(x: 0, y: 0, width: 16, height: 16))
        view.show(Codicons.image("sync"))
        let glyph = try XCTUnwrap(view.layer?.sublayers?.first)
        XCTAssertNotNil(glyph.animation(forKey: "spin"))
        XCTAssertNotNil(glyph.contents)
    }

    @MainActor
    func testMenusOpenRightUnderTheirControlInFlippedAndUnflippedViews() throws {
        _ = NSApplication.shared
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 600, height: 500), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        final class Flipped: NSView { override var isFlipped: Bool { true } }
        let container = NSView(frame: CGRect(x: 0, y: 0, width: 600, height: 500))
        window.contentView = container
        // A control 30 pt from the top of the window, in a flipped view (as SwiftUI's) and in an unflipped one.
        let flipped = Flipped(frame: CGRect(x: 0, y: 0, width: 600, height: 500)), plain = NSView(frame: CGRect(x: 0, y: 0, width: 600, height: 500))
        container.addSubview(flipped); container.addSubview(plain)
        let a = NSView(frame: CGRect(x: 40, y: 30, width: 200, height: 26)), b = NSView(frame: CGRect(x: 40, y: 500 - 30 - 26, width: 200, height: 26))
        flipped.addSubview(a); plain.addSubview(b)
        for control in [a, b] {
            let frame = control.convert(control.bounds, to: nil)
            let opened = control.convert(NativeMenu.location(under: control), to: nil)
            XCTAssertEqual(opened.y, frame.minY - 2, accuracy: 0.01, "The menu's top is 2 pt under the control, near the top of the window.")
            XCTAssertEqual(opened.x, frame.minX, accuracy: 0.01)
            // Status bar menus open above their item: the menu's top is its height above the control.
            let above = control.convert(NativeMenu.location(under: control, placement: .above, menuHeight: 80), to: nil)
            XCTAssertEqual(above.y, frame.maxY + 2 + 80, accuracy: 0.01)
            let beside = control.convert(NativeMenu.location(under: control, placement: .trailingUp, menuHeight: 80), to: nil)
            XCTAssertEqual(beside.x, frame.maxX + 2, accuracy: 0.01)
            XCTAssertEqual(beside.y, frame.minY + 80, accuracy: 0.01, "The Manage menu rises from the gear's bottom.")
        }
    }

    @MainActor
    func testAMenusAnchorFollowsItsControlInAScrolledSettingsList() async throws {
        _ = NSApplication.shared
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 500, height: 400), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        let view = ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Color.clear.frame(height: 120)
                VSDropdown(options: [(1, "One"), (2, "Two")], selection: .constant(1), width: 200)
                Color.clear.frame(height: 900)
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
        window.contentView = NSHostingView(rootView: view.environment(\.theme, ThemeManager.shared.colors))
        window.orderFront(nil)
        try await Task.sleep(for: .milliseconds(150))
        func anchors(in view: NSView) -> [NSView] { (view.identifier == MenuAnchorView.identifier ? [view] : []) + view.subviews.flatMap(anchors) }
        let anchor = try XCTUnwrap(anchors(in: try XCTUnwrap(window.contentView)).first)
        let content = try XCTUnwrap(window.contentView)
        // In the window's own (bottom-left) coordinates the dropdown is 120 pt below the top, 26 pt tall.
        var frame = anchor.convert(anchor.bounds, to: nil)
        XCTAssertEqual(frame.height, 26, accuracy: 0.5)
        XCTAssertEqual(content.bounds.height - frame.maxY, 120, accuracy: 1, "The anchor covers the dropdown.")
        // Scrolled by 80 pt, the anchor (and so the menu) moves with the control.
        let scroll = try XCTUnwrap({ () -> NSScrollView? in
            func find(_ view: NSView) -> NSScrollView? { (view as? NSScrollView) ?? view.subviews.lazy.compactMap(find).first }
            return find(content)
        }())
        scroll.contentView.scroll(to: CGPoint(x: 0, y: 80)); scroll.reflectScrolledClipView(scroll.contentView)
        try await Task.sleep(for: .milliseconds(100))
        frame = anchor.convert(anchor.bounds, to: nil)
        XCTAssertEqual(content.bounds.height - frame.maxY, 40, accuracy: 1)
    }

    @MainActor
    func testOpeningABookBringsItToTheFrontAndEndsTheOtherBooksDebugSession() async throws {
        // Settings opens as a tab in the VS Code style only (the test runner's saved style can be Classic).
        ThemeManager.shared.style = .vscode
        let fixture = try WorkbenchFixture(hosted: true)
        defer { fixture.close() }
        let store = fixture.store
        store.open(fixture.book)
        try await fixture.settle()
        store.openSpecial(.settings)
        XCTAssertEqual(store.activeSpecial, .settings)
        // Opening another book while Settings is in front shows that book (it stayed behind Settings).
        store.open(fixture.paper)
        XCTAssertNil(store.activeSpecial)
        try await fixture.settle()
        store.openSpecial(.welcome)
        let paperID = try XCTUnwrap(store.workspace?.id)
        store.activateTab(paperID)
        XCTAssertNil(store.activeSpecial, "Choosing the book already open brings it back in front of Welcome.")
        store.startDebugging()
        XCTAssertNotNil(store.debug)
        let bookID = try XCTUnwrap(store.tabs.first { $0.id != paperID }?.id)
        store.activateTab(bookID)
        XCTAssertNil(store.debug, "A debug session belongs to its book.")
        XCTAssertFalse(store.reader.debugging)
    }

    @MainActor
    func testClosingTheThemePickerAnyWayDropsItsPreview() throws {
        let fixture = try WorkbenchFixture()
        defer { fixture.close() }
        let store = fixture.store
        let manager = ThemeManager.shared
        manager.style = .vscode
        store.showPalette(.themes)
        manager.preview("lemma-midnight")
        XCTAssertEqual(manager.previewID, "lemma-midnight")
        store.showPalette(.commands)
        XCTAssertNil(manager.previewID, "Another palette replaced the picker: the preview goes.")
        store.showPalette(.themes); manager.preview("lemma-paper")
        store.openSpecial(.settings)
        XCTAssertNil(manager.previewID)
        store.closeSpecial(.settings)
    }

    @MainActor
    func testRecallTestsMatchTheirOwnStatementAndKeyboardShortcutsAreUnique() throws {
        XCTAssertTrue(StudyStore.question("Theorem 2.1", isAbout: "Theorem 2.1"))
        XCTAssertTrue(StudyStore.question("Theorem 2.1 (Hoeffding)", isAbout: "Theorem 2.1"))
        XCTAssertTrue(StudyStore.question("Theorem 2.1. State it.", isAbout: "Theorem 2.1"))
        XCTAssertFalse(StudyStore.question("Theorem 2.10 (Bernstein)", isAbout: "Theorem 2.1"))
        XCTAssertFalse(StudyStore.question("Theorem 2.1.3", isAbout: "Theorem 2.1"))
        XCTAssertFalse(StudyStore.isRecallable(ReferenceKey(kind: .theorem, number: "2.1", name: "Example")))
        XCTAssertTrue(StudyStore.isRecallable(ReferenceKey(kind: .theorem, number: "2.1", name: "Lemma")))
        // One action per shortcut; view bindings must not overlap study actions.
        let fixture = try WorkbenchFixture()
        defer { fixture.close() }
        fixture.store.open(fixture.book)
        var byShortcut: [String: Set<String>] = [:]
        for item in fixture.store.commandCatalog() { if let shortcut = item.shortcut { byShortcut[shortcut, default: []].insert(item.title) } }
        for (shortcut, titles) in byShortcut { XCTAssertEqual(titles.count, 1, "\(shortcut) is bound to \(titles.sorted())") }
        for container in ViewContainer.allCases {
            guard let shortcut = container.shortcut else { continue }
            XCTAssertNil(byShortcut[shortcut], "\(shortcut) shows \(container.title) but runs \(byShortcut[shortcut]?.sorted() ?? [])")
        }
        XCTAssertEqual(ViewContainer.explorer.shortcut, "⌥⌘1")
        XCTAssertEqual(ViewContainer.search.shortcut, "⇧⌘F")
        XCTAssertEqual(ViewContainer.debug.shortcut, "⇧⌘D")
    }

    @MainActor
    func testToastsCanBeTurnedOffAndStayInTheBell() throws {
        let fixture = try WorkbenchFixture()
        defer { fixture.close(); UserDefaults.standard.removeObject(forKey: "workbench.notifications.toasts") }
        let store = fixture.store
        store.notify("One")
        XCTAssertEqual(store.visibleToasts.count, 1)
        UserDefaults.standard.set(false, forKey: "workbench.notifications.toasts")
        store.notify("Two")
        XCTAssertTrue(store.visibleToasts.isEmpty)
        XCTAssertEqual(store.notifications.count, 2, "The bell keeps them.")
    }

    @MainActor
    func testFuzzyHighlightsAndKeyCaps() {
        let ranges = FuzzyMatch.ranges(of: "lin reg", in: "Linear Regression")
        XCTAssertEqual(ranges.count, 2)
        XCTAssertEqual(ranges.map { String("Linear Regression"[$0]) }, ["Lin", "Reg"])
        XCTAssertEqual(VSKeybinding.keys("⇧⌘P"), ["⇧", "⌘", "P"])
        XCTAssertEqual(VSKeybinding.keys("⌘K ⌘T"), ["⌘", "K", "⌘", "T"])
        XCTAssertEqual(VSKeybinding.keys("F5"), ["F5"])
        XCTAssertEqual(VSSearchView.lead("the ridge solutions are easily seen to be such as "), "… be such as ", "The space before a match is kept.")
        XCTAssertEqual(VSSearchView.lead("  short "), "short ")
    }
}
