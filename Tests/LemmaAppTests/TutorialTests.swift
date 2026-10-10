import XCTest
import AppKit
import SwiftUI
import LemmaCore
@testable import Lemma

/// The Lemma Tour and the guides: their content, how they move, Show Me on the real window, where the callout goes,
/// when the tour opens by itself, and that every page and scene draws.
final class TutorialTests: XCTestCase {
    private var savedDefaults: [String: Any?] = [:]
    private let keys = [TutorialPreferences.shown, TutorialPreferences.seen, TutorialPreferences.position, ThemePreferences.style]
    private var roots: [URL] = []

    @MainActor override func setUp() async throws {
        _ = NSApplication.shared
        for key in keys { savedDefaults[key] = UserDefaults.standard.object(forKey: key) }
    }

    @MainActor override func tearDown() async throws {
        TutorialCenter.shared.close()
        for key in keys {
            if let value = savedDefaults[key] ?? nil { UserDefaults.standard.set(value, forKey: key) } else { UserDefaults.standard.removeObject(forKey: key) }
        }
        for root in roots { try? FileManager.default.removeItem(at: root) }
        ThemeManager.shared.style = WorkbenchStyle(rawValue: UserDefaults.standard.string(forKey: ThemePreferences.style) ?? "") ?? .vscode
    }

    /// A store on a temporary support folder: tests never touch the reader's own.
    @MainActor private func makeStore() -> StudyStore {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("lemma-tour-\(UUID().uuidString)", isDirectory: true)
        roots.append(root)
        return StudyStore(root: root)
    }

    @MainActor
    func testTheTourIsShortAndEachGuideAFewSteps() {
        let guides = TutorialContent.guides
        XCTAssertEqual(guides.first?.id, "tour", "The tour comes first")
        XCTAssertLessThanOrEqual(guides[0].steps.count, 7, "The tour stays a two-minute tour")
        XCTAssertLessThanOrEqual(guides.count - 1, 10)
        for guide in guides.dropFirst() { XCTAssertTrue((3...5).contains(guide.steps.count), "\(guide.id) has a few steps") }
        let ids = guides.flatMap { $0.steps.map(\.id) }
        XCTAssertEqual(Set(ids).count, ids.count, "Step ids are unique")
        XCTAssertLessThanOrEqual(ids.count, 45, "Nothing like a hundred steps")
        XCTAssertTrue(guides[0].steps.allSatisfy { $0.target != nil }, "Every step of the tour lights up a part of the real window")
        for guide in guides {
            for step in guide.steps {
                XCTAssertTrue(step.id.hasPrefix(guide.id + "."), step.id)
                let texts = [guide.title, guide.summary, step.title, step.body, step.classicBody ?? ""] + step.tips.map(\.text) + step.actions.map(\.title)
                for text in texts { XCTAssertFalse(text.contains("\u{2014}"), "App-authored text has no em dash: \(step.id)") }
                XCTAssertFalse(step.body.isEmpty, step.id)
                XCTAssertLessThanOrEqual(step.body.count, 230, "\(step.id) fits its callout")
                XCTAssertLessThanOrEqual(step.classicBody?.count ?? 0, 230, "\(step.id) fits its callout in Classic")
                XCTAssertLessThanOrEqual(step.tips.count, 2, "\(step.id): two shortcuts at most")
                if step.reveal != nil { XCTAssertNotNil(step.target, "\(step.id): something to light up after revealing it") }
            }
        }
    }

    @MainActor
    func testShortcutsParseIntoKeyCaps() {
        XCTAssertEqual(TutorialKeys.groups("⇧⌘P"), [["⇧", "⌘", "P"]])
        XCTAssertEqual(TutorialKeys.groups("⌥⌘← ⌥⌘→"), [["⌥", "⌘", "←"], ["⌥", "⌘", "→"]])
        XCTAssertEqual(TutorialKeys.groups("⌘-click"), [["⌘", "click"]])
        XCTAssertEqual(TutorialKeys.groups("⇧F11"), [["⇧", "F11"]])
        for guide in TutorialContent.guides {
            for step in guide.steps {
                for tip in step.tips { XCTAssertFalse(TutorialKeys.groups(tip.keys).flatMap { $0 }.isEmpty, "\(step.id): \(tip.keys)") }
            }
        }
    }

    @MainActor
    func testFirstLaunchOpensTheWelcomeOnceThenTheColoursAndTheTour() async throws {
        UserDefaults.standard.removeObject(forKey: TutorialPreferences.shown)
        let store = makeStore()
        let center = TutorialCenter.shared
        XCTAssertTrue(center.presentIfFirstLaunch(store))
        XCTAssertTrue(UserDefaults.standard.bool(forKey: TutorialPreferences.shown), "Remembered at once, even if Lemma quits during the tour")
        try await Task.sleep(for: .milliseconds(700))
        XCTAssertTrue(center.isPresented)
        XCTAssertEqual(center.screen, .welcome)
        center.next()
        XCTAssertEqual(center.screen, .look)
        center.next()
        XCTAssertEqual(center.screen, .step)
        XCTAssertEqual(center.step.id, "tour.library")
        XCTAssertTrue(center.canGoBack, "From the first launch, Back returns to the colours")
        center.back()
        XCTAssertEqual(center.screen, .look)
        center.close()
        XCTAssertFalse(center.isPresented)
        XCTAssertFalse(center.presentIfFirstLaunch(store), "Only the first launch opens it by itself")
    }

    @MainActor
    func testTheTourEndsOnItsLastPage() {
        let store = makeStore()
        let center = TutorialCenter.shared
        center.resetProgress()
        center.startTour(store)
        XCTAssertEqual(center.screen, .step)
        XCTAssertEqual(center.step.id, "tour.library")
        XCTAssertFalse(center.canGoBack, "Opened from Help, the tour starts on its first step")
        XCTAssertTrue(center.seen.contains("tour.library"))
        for _ in 1..<center.tour.steps.count { center.next() }
        XCTAssertTrue(center.isLastStep)
        XCTAssertTrue(center.isComplete(center.tour))
        center.next()
        XCTAssertEqual(center.screen, .finish)
        center.back()
        XCTAssertEqual(center.screen, .step)
        XCTAssertTrue(center.isLastStep)
        center.next()
        center.next()
        XCTAssertFalse(center.isPresented, "The last page closes the tour")
        center.startTour(store)
        XCTAssertEqual(center.step.id, "tour.library", "A tour seen to the end starts again from the beginning")
    }

    @MainActor
    func testGuidesResumeWhereTheyWereLeftAndCloseAtTheirEnd() {
        let store = makeStore()
        let center = TutorialCenter.shared
        center.resetProgress()
        center.open(store, guide: "proofs")
        XCTAssertEqual(center.step.id, "proofs.results")
        center.next()
        XCTAssertEqual(center.step.id, "proofs.fold")
        center.close()
        center.open(store, guide: "proofs")
        XCTAssertEqual(center.step.id, "proofs.uses", "A guide picks up at its first step not seen yet")
        XCTAssertEqual(UserDefaults.standard.string(forKey: TutorialPreferences.position), "proofs.uses")
        center.next()
        XCTAssertTrue(center.isLastStep)
        center.next()
        XCTAssertFalse(center.isPresented, "A guide closes after its last step")
        // The guides at a glance lead to the tour.
        center.open(store)
        XCTAssertEqual(center.screen, .home)
        center.next()
        XCTAssertEqual(center.screen, .step)
        XCTAssertEqual(center.guide.id, "tour")
        center.showHome()
        XCTAssertEqual(center.screen, .home)
        center.begin(guide: 2)
        XCTAssertEqual(center.guide.id, center.guides[2].id)
    }

    @MainActor
    func testSearchFindsStepsByWordAndShortcut() {
        let center = TutorialCenter.shared
        XCTAssertTrue(center.matches("F10").contains { $0.step.id == "proofs.debug" })
        XCTAssertTrue(center.matches("zen").contains { $0.step.id == "window.layouts" })
        XCTAssertTrue(center.matches("free textbooks").contains { $0.step.id == "tour.library" })
        XCTAssertTrue(center.matches("  ").isEmpty)
    }

    @MainActor
    func testShowMeRevealsThePartAndClosingHidesWhatTheTourShowed() {
        let store = makeStore()
        let center = TutorialCenter.shared
        store.showPanel = false
        center.open(store, guide: "window")
        center.open(stepID: "window.panel")
        XCTAssertTrue(store.showPanel, "Show Me opens the panel by itself")
        center.close()
        XCTAssertFalse(store.showPanel, "Closing the tour hides what it showed")
        // What the reader changed after the tour showed it stays as the reader left it.
        store.showStudy = false
        store.studySection = .page
        center.open(store, guide: "notes")
        center.open(stepID: "notes.glossary")
        XCTAssertTrue(store.showStudy)
        XCTAssertEqual(store.studySection, .glossary)
        store.studySection = .notes
        center.close()
        XCTAssertFalse(store.showStudy)
        XCTAssertEqual(store.studySection, .notes)
        // Zen Mode hides the parts the tour lights up: the tour leaves it.
        store.toggleFocus()
        XCTAssertTrue(store.focusMode)
        center.startTour(store)
        XCTAssertFalse(store.focusMode)
        XCTAssertTrue(store.showLibrary)
    }

    @MainActor
    func testActionsPauseTheTourInItsPill() {
        let store = makeStore()
        let center = TutorialCenter.shared
        center.open(store, guide: "reading")
        center.open(stepID: "reading.goTo")
        guard let action = center.step.actions.first else { return XCTFail("reading.goTo has an action") }
        center.perform(action)
        XCTAssertTrue(center.isPaused, "The tour waits in its pill while the reader tries")
        XCTAssertEqual(store.palette?.mode, .goTo)
        XCTAssertEqual(center.trying, action.title)
        center.resume()
        XCTAssertFalse(center.isPaused)
        XCTAssertNil(store.palette)
        // An action that needs a book stays inert without one.
        center.open(stepID: "derive.start")
        let derive = center.step.actions[0]
        XCTAssertFalse(derive.requires.isMet(store))
        center.perform(derive)
        XCTAssertFalse(center.isPaused)
    }

    @MainActor
    func testTheCalloutSitsBesideItsPartAndPointsAtIt() {
        let bounds = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let card = CGSize(width: TutorialCoachLayout.cardWidth, height: 220)
        func place(_ hole: CGRect) -> TutorialCoachLayout.Placement { TutorialCoachLayout.place(card: card, near: hole, in: bounds) }
        func frame(_ placement: TutorialCoachLayout.Placement) -> CGRect { CGRect(origin: placement.origin, size: card) }

        let activityBar = CGRect(x: 0, y: 35, width: 48, height: 843)
        var placement = place(activityBar)
        XCTAssertEqual(placement.edge, .leading, "Beside a tall part on the left, pointing left")
        XCTAssertGreaterThan(placement.origin.x, activityBar.maxX)
        XCTAssertEqual(placement.origin.y + placement.beak, activityBar.midY, accuracy: 0.5, "The beak points at the part's middle")

        let notebook = CGRect(x: 1100, y: 35, width: 340, height: 843)
        placement = place(notebook)
        XCTAssertEqual(placement.edge, .trailing)
        XCTAssertLessThan(frame(placement).maxX, notebook.minX)

        let statusBar = CGRect(x: 0, y: 878, width: 1440, height: 22)
        placement = place(statusBar)
        XCTAssertEqual(placement.edge, .bottom, "Over a flat part at the bottom")
        XCTAssertLessThan(frame(placement).maxY, statusBar.minY)

        let commandCenter = CGRect(x: 420, y: 6, width: 600, height: 24)
        placement = place(commandCenter)
        XCTAssertEqual(placement.edge, .top, "Under the command center")
        XCTAssertGreaterThan(placement.origin.y, commandCenter.maxY)

        let page = CGRect(x: 350, y: 80, width: 900, height: 780)
        placement = place(page)
        XCTAssertNil(placement.edge, "Inside a part that leaves no room around it")
        XCTAssertTrue(page.contains(frame(placement)))

        for hole in [activityBar, notebook, statusBar, commandCenter, page, CGRect(x: 1390, y: 6, width: 44, height: 24)] {
            XCTAssertTrue(bounds.insetBy(dx: 11, dy: 11).contains(frame(place(hole))), "\(hole): the callout stays in the window")
        }

        // Without the part on screen the step is a card in the middle; Classic's toolbar is pointed at from below.
        XCTAssertEqual(TutorialCoachLayout.anchor(for: .page, frames: [:], bounds: bounds, style: .vscode), .none)
        XCTAssertEqual(TutorialCoachLayout.anchor(for: nil, frames: [.page: page], bounds: bounds, style: .vscode), .none)
        guard case let .toolbar(toolbar) = TutorialCoachLayout.anchor(for: .commandCenter, frames: [:], bounds: bounds, style: .classic) else {
            return XCTFail("Classic's command center is in the toolbar")
        }
        XCTAssertEqual(TutorialCoachLayout.placement(card: card, anchor: .toolbar(toolbar), in: bounds).edge, .top)
        let ruler = CGRect(x: 1250, y: 80, width: 14, height: 780)
        XCTAssertEqual(TutorialCoachLayout.anchor(for: .minimap, frames: [.overviewRuler: ruler], bounds: bounds, style: .vscode),
                       .lit(ruler.insetBy(dx: -4, dy: -4)), "A hidden minimap falls back on the overview ruler")
    }

    @MainActor
    func testKeysMoveTheTourAndShortcutsReachTheWindow() throws {
        let store = makeStore()
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 800, height: 600), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        store.mainWindow = window
        let center = TutorialCenter.shared
        center.resetProgress()
        center.startTour(store)
        func key(_ code: UInt16, _ characters: String, _ modifiers: NSEvent.ModifierFlags = [], in target: NSWindow? = nil) -> NSEvent {
            NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: modifiers, timestamp: 0, windowNumber: (target ?? window).windowNumber, context: nil,
                             characters: characters, charactersIgnoringModifiers: characters, isARepeat: false, keyCode: code)!
        }
        XCTAssertEqual(center.step.id, "tour.library")
        XCTAssertNil(center.handle(key(124, "\u{F703}")), "→ is the tour's")
        XCTAssertEqual(center.step.id, "tour.goTo")
        XCTAssertNil(center.handle(key(36, "\r")))
        XCTAssertEqual(center.step.id, "tour.links", "Return continues")
        XCTAssertNil(center.handle(key(123, "\u{F702}")))
        XCTAssertEqual(center.step.id, "tour.goTo")
        // A shortcut reaches the window, and the tour waits in its pill so its effect shows.
        XCTAssertNotNil(center.handle(key(35, "p", .command)))
        XCTAssertTrue(center.isPaused)
        center.resume()
        for (code, characters) in [(UInt16(123), "\u{F702}"), (UInt16(124), "\u{F703}")] {
            let step = center.step.id
            XCTAssertNotNil(center.handle(key(code, characters, [.option, .command])), "History shortcuts reach the reader")
            XCTAssertTrue(center.isPaused)
            XCTAssertEqual(center.step.id, step, "History shortcuts do not move the tour")
            center.resume()
        }
        // While a part of the window has the keyboard, its keys are its own: the window stays usable under the tour.
        final class Focusable: NSView { override var acceptsFirstResponder: Bool { true } }
        let page = Focusable(frame: CGRect(x: 0, y: 0, width: 100, height: 100))
        window.contentView?.addSubview(page)
        window.makeFirstResponder(page)
        XCTAssertNotNil(center.handle(key(124, "\u{F703}")))
        XCTAssertEqual(center.step.id, "tour.goTo")
        center.next()
        XCTAssertTrue(window.firstResponder === window, "Moving through the tour takes the keys back")
        XCTAssertNil(center.handle(key(53, "\u{1B}")), "Escape closes")
        XCTAssertFalse(center.isPresented)
        // Keys typed for another window are not the tour's.
        center.startTour(store)
        let other = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 200, height: 200), styleMask: [.titled], backing: .buffered, defer: false)
        other.isReleasedWhenClosed = false
        defer { other.close() }
        let step = center.step.id
        XCTAssertNotNil(center.handle(key(124, "\u{F703}", in: other)))
        XCTAssertEqual(center.step.id, step)
    }

    /// Every page and every step draws, in both interfaces, without a book open (so steps show as cards with their
    /// animation). One hosting view per interface is reused (a new one per step would grow SwiftUI's attribute graph
    /// without bound in a test).
    @MainActor
    func testEveryPageAndStepDraws() throws {
        let store = makeStore()
        let center = TutorialCenter.shared
        center.startTour(store)
        for style in WorkbenchStyle.allCases {
            ThemeManager.shared.style = style
            let host = NSHostingView(rootView: TutorialOverlay(store: store, anchors: [:]).environment(\.theme, ThemeManager.shared.colors))
            host.frame = CGRect(x: 0, y: 0, width: 1280, height: 820)
            func draw(_ label: String) throws {
                try autoreleasepool {
                    RunLoop.current.run(until: Date().addingTimeInterval(0.01))
                    host.layoutSubtreeIfNeeded()
                    let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds), label)
                    host.cacheDisplay(in: host.bounds, to: bitmap)
                    XCTAssertGreaterThan(bitmap.pixelsWide, 0, label)
                }
            }
            for guide in center.guides {
                for step in guide.steps {
                    center.open(stepID: step.id)
                    try draw(step.id)
                }
            }
            center.showSetupForQA(.welcome); try draw("welcome")
            center.showSetupForQA(.look); try draw("look")
            center.showHome(); try draw("home")
            center.query = "proof"; try draw("search")
            center.query = ""
            center.open(stepID: center.tour.steps[center.tour.steps.count - 1].id)
            center.next(); try draw("finish")
            center.pause(); try draw("pill")
            center.resume()
        }
    }
}
