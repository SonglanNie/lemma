import SwiftUI
import AppKit
import LemmaCore

// MARK: - What the tour is made of

/// A part of the real window the tour can light up. The views that draw it report their frames.
enum TutorialTarget: Hashable {
    case titleBar, commandCenter, layoutControls, activityBar, sideBar
    case editorTabs, breadcrumbs, selectionBar, page, minimap, overviewRuler, sideEditors, secondarySideBar, panel, statusBar

    /// Where to look when this part is not on screen: the minimap is optional, the command center sits in the title bar.
    var alternatives: [TutorialTarget] {
        switch self {
        case .minimap: [.minimap, .overviewRuler, .page]
        case .commandCenter, .layoutControls: [self, .titleBar]
        case .editorTabs: [.editorTabs, .breadcrumbs]
        default: [self]
        }
    }

    /// Parts of the window that exist only while a book is open.
    var needsBook: Bool {
        switch self {
        case .breadcrumbs, .selectionBar, .page, .minimap, .overviewRuler, .sideEditors, .secondarySideBar, .panel: true
        default: false
        }
    }

    /// The Classic interface keeps these in the window's toolbar, above what the tour draws over: it points at them.
    var inClassicToolbar: Bool {
        switch self {
        case .titleBar, .commandCenter, .layoutControls: true
        default: false
        }
    }

    /// Zen Mode hides these; the tour leaves Zen Mode to show them.
    var hiddenByZen: Bool {
        switch self {
        case .activityBar, .sideBar, .secondarySideBar, .panel: true
        default: false
        }
    }
}

struct TutorialAnchorKey: PreferenceKey {
    static var defaultValue: [TutorialTarget: Anchor<CGRect>] { [:] }
    static func reduce(value: inout [TutorialTarget: Anchor<CGRect>], nextValue: () -> [TutorialTarget: Anchor<CGRect>]) {
        value.merge(nextValue()) { $1 }
    }
}

extension View {
    /// Reports this view's frame to the tour, which can then light it up on the real window. The parts inside it keep
    /// theirs (the title bar holds the command center and the layout controls).
    func tutorialAnchor(_ target: TutorialTarget) -> some View {
        transformAnchorPreference(key: TutorialAnchorKey.self, value: .bounds) { anchors, bounds in anchors[target] = bounds }
    }
}

/// What an action needs before it can run.
enum TutorialRequirement {
    case none, book, selection, analysis

    @MainActor func isMet(_ store: StudyStore) -> Bool {
        switch self {
        case .none: true
        case .book: store.document != nil
        case .selection: store.reader.hasSelection
        case .analysis: store.analysis?.analysis != nil
        }
    }

    var hint: String {
        switch self {
        case .none: ""
        case .book: "Open a book first"
        case .selection: "Select a passage on the page first"
        case .analysis: "Open a book and let Lemma finish reading it"
        }
    }
}

/// A button of a step that does the thing on the real window: open Go to, a notebook, the Catalog.
struct TutorialAction: Identifiable {
    /// After the action: the tour waits in its pill so the result shows, or stays where it is.
    enum After { case pause, stay }
    let title: String
    let icon: String
    var requires: TutorialRequirement = .none
    var after: After = .pause
    let perform: @MainActor (StudyStore) -> Void
    var id: String { title }
}

/// A shortcut worth knowing, shown as key caps beside what it does.
struct TutorialTip: Hashable {
    let text: String
    let keys: String
}

struct TutorialStep: Identifiable {
    var id: String
    let title: String
    let body: String
    /// The same explanation for the Classic interface, where it differs.
    var classicBody: String? = nil
    /// At most two shortcuts.
    var tips: [TutorialTip] = []
    /// The animation shown when the part of the window the step is about cannot be lit up.
    let scene: TutorialScene
    /// The part of the real window this step is about.
    var target: TutorialTarget? = nil
    /// Shows the target before it is lit: a view of the side bar, the panel, the notebook. It never changes the
    /// reader's work, and the tour hides again what it showed when it closes.
    var reveal: (@MainActor (StudyStore) -> Void)? = nil
    var actions: [TutorialAction] = []

    func text(for style: WorkbenchStyle) -> String { style == .classic ? classicBody ?? body : body }
}

/// The tour, or one of the guides that go deeper: a few steps on one subject.
struct TutorialGuide: Identifiable {
    let id: String
    let title: String
    let summary: String
    let icon: String
    let steps: [TutorialStep]

    init(_ id: String, _ title: String, summary: String, icon: String, steps: [TutorialStep]) {
        self.id = id; self.title = title; self.summary = summary; self.icon = icon
        self.steps = steps.map { step in
            var copy = step
            copy.id = "\(id).\(step.id)"
            return copy
        }
    }

    /// About twenty seconds a step, rounded up to whole minutes.
    var minutes: Int { max(1, Int((Double(steps.count) * 20 / 60).rounded(.up))) }
}

enum TutorialPreferences {
    /// Set once the tour has opened by itself on a first launch.
    static let shown = "tutorial.shown"
    static let seen = "tutorial.seen"
    static let position = "tutorial.position"
}

/// The parts of the window the tour shows to light them up. Closing the tour hides again what it showed, unless the
/// reader changed that part since.
struct TutorialLayout: Equatable {
    var showLibrary: Bool
    var navigatorSection: NavigatorSection
    var showPanel: Bool
    var panelTab: PanelTab
    var showStudy: Bool
    var studySection: StudySection

    @MainActor init(_ store: StudyStore) {
        showLibrary = store.showLibrary; navigatorSection = store.navigatorSection
        showPanel = store.showPanel; panelTab = store.panelTab
        showStudy = store.showStudy; studySection = store.studySection
    }

    /// Puts back each part from `before` that is still as the tour left it in `shown`.
    @MainActor static func restore(_ store: StudyStore, before: TutorialLayout, shown: TutorialLayout) {
        let now = TutorialLayout(store)
        if now.showLibrary == shown.showLibrary, before.showLibrary != shown.showLibrary { store.showLibrary = before.showLibrary }
        if now.navigatorSection == shown.navigatorSection, before.navigatorSection != shown.navigatorSection { store.navigatorSection = before.navigatorSection }
        if now.showPanel == shown.showPanel, before.showPanel != shown.showPanel { store.showPanel = before.showPanel }
        if now.panelTab == shown.panelTab, before.panelTab != shown.panelTab { store.panelTab = before.panelTab }
        if now.showStudy == shown.showStudy, before.showStudy != shown.showStudy { store.showStudy = before.showStudy }
        if now.studySection == shown.studySection, before.studySection != shown.studySection { store.studySection = before.studySection }
    }
}

// MARK: - The tour's state

/// The tour and the guides: whether they show, where the reader is and what they have seen. One per app, like the
/// theme manager; steps act on the window through the store they are given.
@MainActor @Observable
final class TutorialCenter {
    static let shared = TutorialCenter()

    /// The first launch's welcome and colours, the guides at a glance, a step over the window, or the tour's last page.
    enum Screen: Equatable { case welcome, look, home, step, finish }

    /// The tour first, then the guides.
    let guides: [TutorialGuide]
    private(set) var isPresented = false
    private(set) var screen: Screen = .home
    /// Set aside in a pill while the reader tries something.
    private(set) var isPaused = false
    private(set) var guideIndex = 0
    private(set) var stepIndex = 0
    /// Whether the last move went forward, for the direction of the transition.
    private(set) var movedForward = true
    /// The tour began on the first launch's pages, so Back from its first step returns to them.
    private(set) var startedFromSetup = false
    /// Bumped to play a step's animation again.
    var replay = 0
    var query = ""
    private(set) var seen: Set<String>
    /// The action the reader tried last, named in the pill.
    private(set) var trying: String?
    @ObservationIgnored private(set) weak var store: StudyStore?
    @ObservationIgnored private var keyMonitor: Any?
    /// What had the keyboard before the tour took it (a note's editor would otherwise take keys typed for the tour).
    @ObservationIgnored private weak var previousResponder: NSResponder?
    /// The window before the tour showed a part of it, and as the tour last left it.
    @ObservationIgnored private var layoutBefore: TutorialLayout?
    @ObservationIgnored private var layoutShown: TutorialLayout?
    /// Where the coach card and the lit part are, written by the overlay for QA.
    @ObservationIgnored var qaLayout: [String: Any] = [:]

    private init() {
        guides = TutorialContent.guides
        let ids = Set(guides.flatMap { $0.steps.map(\.id) })
        seen = Set((UserDefaults.standard.stringArray(forKey: TutorialPreferences.seen) ?? []).filter(ids.contains))
        if let position = UserDefaults.standard.string(forKey: TutorialPreferences.position), let found = Self.locate(position, in: guides) {
            guideIndex = found.guide; stepIndex = found.step
        }
    }

    var tour: TutorialGuide { guides[0] }
    var guide: TutorialGuide { guides[guideIndex] }
    var step: TutorialStep { guide.steps[stepIndex] }
    var isTour: Bool { guideIndex == 0 }
    var isLastStep: Bool { stepIndex == guide.steps.count - 1 }
    var canGoBack: Bool { stepIndex > 0 || (isTour && startedFromSetup) }
    var lessonCount: Int { guides.reduce(0) { $0 + $1.steps.count } }
    var seenCount: Int { guides.reduce(0) { $0 + seenSteps($1) } }

    func seenSteps(_ guide: TutorialGuide) -> Int { guide.steps.filter { seen.contains($0.id) }.count }
    func isComplete(_ guide: TutorialGuide) -> Bool { guide.steps.allSatisfy { seen.contains($0.id) } }
    /// Where a guide picks up: its first step not seen yet, or its beginning once it has all been seen.
    func resumeStep(_ guide: TutorialGuide) -> Int { guide.steps.firstIndex { !seen.contains($0.id) } ?? 0 }

    // MARK: Opening and closing

    /// On the first launch, opens the welcome, then the colours and the tour. Returns whether it did.
    @discardableResult
    func presentIfFirstLaunch(_ store: StudyStore) -> Bool {
        let environment = ProcessInfo.processInfo.environment
        // QA copies keep the window to themselves unless asked to show the tour.
        let quiet = (environment["LEMMA_QA_DIR"] != nil || QAHooks.shared != nil) && environment["LEMMA_SHOW_TUTORIAL"] == nil
        guard !UserDefaults.standard.bool(forKey: TutorialPreferences.shown), !quiet else { return false }
        UserDefaults.standard.set(true, forKey: TutorialPreferences.shown)
        self.store = store
        // After the window has laid out what it restored.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { [weak self] in
            guard let self, let store = self.store else { return }
            self.startedFromSetup = true
            self.screen = .welcome
            self.present(store)
        }
        return true
    }

    /// The guides at a glance, with the tour at their head (Help › Lemma Guides).
    func open(_ store: StudyStore) {
        self.store = store
        store.palette = nil
        startedFromSetup = false
        screen = .home
        present(store)
    }

    /// The tour itself, where it was left (Help › Lemma Tour).
    func startTour(_ store: StudyStore) {
        open(store, guide: tour.id)
    }

    /// One guide, where it was left.
    func open(_ store: StudyStore, guide id: String) {
        self.store = store
        store.palette = nil
        startedFromSetup = false
        guard let index = guides.firstIndex(where: { $0.id == id }) else { return open(store) }
        guideIndex = index
        stepIndex = resumeStep(guides[index])
        screen = .step
        present(store)
    }

    private func present(_ store: StudyStore) {
        isPaused = false
        trying = nil
        query = ""
        if !isPresented { withAnimation(.easeOut(duration: 0.2)) { isPresented = true } }
        installKeyMonitor()
        if screen == .step { enterStep() } else { savePosition() }
    }

    func close() {
        guard isPresented else { return }
        ThemeManager.shared.preview(nil)
        removeKeyMonitor()
        withAnimation(.easeOut(duration: 0.18)) { isPresented = false }
        isPaused = false
        trying = nil
        restoreLayout()
        savePosition()
        if let window = store?.mainWindow, let view = previousResponder as? NSView, view.window === window { window.makeFirstResponder(view) }
        previousResponder = nil
        // The first launch's offer of the reader's VS Code theme waits for the tour (its colour page offers the same theme).
        store?.offerVSCodeTheme()
    }

    // MARK: Moving

    func next() {
        switch screen {
        case .welcome: show(.look)
        case .look: begin(guide: 0, at: 0)
        case .home: begin(guide: 0, at: resumeStep(tour))
        case .finish: close()
        case .step:
            if !isLastStep { move(to: stepIndex + 1, forward: true) }
            else if isTour { show(.finish) }
            else { close() }
        }
    }

    func back() {
        switch screen {
        case .look: show(.welcome)
        case .finish: begin(guide: 0, at: tour.steps.count - 1, forward: false)
        case .step:
            if stepIndex > 0 { move(to: stepIndex - 1, forward: false) }
            else if isTour && startedFromSetup { show(.look) }
        case .welcome, .home: break
        }
    }

    /// The guides at a glance, from a step or the last page.
    func showHome() {
        restoreLayout()
        show(.home)
    }

    /// Starts a guide (the tour is the first) on one of its steps.
    func begin(guide index: Int, at step: Int? = nil, forward: Bool = true) {
        guard guides.indices.contains(index) else { return }
        movedForward = forward
        withAnimation(.spring(response: 0.42, dampingFraction: 0.9)) {
            guideIndex = index
            stepIndex = max(0, min(guides[index].steps.count - 1, step ?? resumeStep(guides[index])))
            screen = .step
            query = ""
        }
        enterStep()
    }

    func open(stepID: String) {
        guard let found = Self.locate(stepID, in: guides) else { return }
        begin(guide: found.guide, at: found.step)
    }

    /// QA: the first launch's pages, without forgetting that the tour was shown.
    func showSetupForQA(_ screen: Screen) {
        startedFromSetup = true
        show(screen)
    }

    private func show(_ screen: Screen) {
        withAnimation(.spring(response: 0.42, dampingFraction: 0.9)) {
            self.screen = screen
            query = ""
        }
        isPaused = false
        trying = nil
        installKeyMonitor()
        reclaimKeys()
        savePosition()
    }

    private func move(to step: Int, forward: Bool) {
        movedForward = forward
        withAnimation(.spring(response: 0.42, dampingFraction: 0.9)) { stepIndex = step }
        enterStep()
    }

    /// Show Me, always: the part of the window the step is about is shown if hidden, and the overlay lights it up.
    private func enterStep() {
        isPaused = false
        trying = nil
        installKeyMonitor()
        if let store, let target = step.target {
            if store.focusMode, target.hiddenByZen { store.toggleFocus() }
            if let reveal = step.reveal {
                if layoutBefore == nil { layoutBefore = TutorialLayout(store) }
                reveal(store)
                layoutShown = TutorialLayout(store)
            }
        }
        markSeen()
        reclaimKeys()
        savePosition()
    }

    private func restoreLayout() {
        if let store, let before = layoutBefore, let shown = layoutShown { TutorialLayout.restore(store, before: before, shown: shown) }
        layoutBefore = nil
        layoutShown = nil
    }

    // MARK: On the real window

    func perform(_ action: TutorialAction) {
        guard let store, action.requires.isMet(store) else { return }
        // Once the reader acts on the window, what it shows is theirs: closing the tour leaves it as it is.
        layoutBefore = nil
        layoutShown = nil
        action.perform(store)
        if action.after == .pause {
            pause()
            trying = action.title
        }
    }

    /// The pill only, so what the reader does shows. The step stays where it was.
    func pause() {
        guard isPresented else { return }
        trying = nil
        removeKeyMonitor()
        withAnimation(.spring(response: 0.4, dampingFraction: 0.9)) { isPaused = true }
    }

    /// Back from the pill; a palette left open by an action closes under it.
    func resume() {
        guard isPresented else { return }
        trying = nil
        store?.palette = nil
        withAnimation(.spring(response: 0.4, dampingFraction: 0.9)) { isPaused = false }
        installKeyMonitor()
        if screen == .step { enterStep() } else { reclaimKeys() }
    }

    // MARK: Progress

    private func markSeen() {
        guard screen == .step, !seen.contains(step.id) else { return }
        seen.insert(step.id)
        UserDefaults.standard.set(seen.sorted(), forKey: TutorialPreferences.seen)
    }

    func resetProgress() {
        seen = []
        UserDefaults.standard.removeObject(forKey: TutorialPreferences.seen)
    }

    private func savePosition() { UserDefaults.standard.set(step.id, forKey: TutorialPreferences.position) }

    private static func locate(_ id: String, in guides: [TutorialGuide]) -> (guide: Int, step: Int)? {
        for (g, guide) in guides.enumerated() {
            if let s = guide.steps.firstIndex(where: { $0.id == id }) { return (g, s) }
        }
        return nil
    }

    /// Steps whose title, text or shortcuts contain every word of the query, for the guides' search field.
    func matches(_ query: String) -> [(guide: TutorialGuide, step: TutorialStep)] {
        let words = query.lowercased().split(separator: " ").map(String.init).filter { !$0.isEmpty }
        guard !words.isEmpty else { return [] }
        var found: [(TutorialGuide, TutorialStep)] = []
        for guide in guides {
            for step in guide.steps {
                let haystack = ([guide.title, step.title, step.body, step.classicBody ?? ""] + step.tips.map { "\($0.text) \($0.keys)" })
                    .joined(separator: " ").lowercased()
                if words.allSatisfy({ haystack.contains($0) }) { found.append((guide, step)) }
            }
        }
        return found
    }

    // MARK: Keys

    /// While the tour shows and nothing else in the window has the keyboard: ← and → move, Return continues, Escape
    /// closes. A shortcut with ⌘, ⌃ or ⌥, or a function key, sets the tour aside and reaches the window, so what it
    /// does shows at once.
    private func installKeyMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            TutorialCenter.shared.handle(event)
        }
    }

    private func removeKeyMonitor() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
    }

    /// The tour takes the keys back after the reader moved through it (they may have clicked into the page before).
    private func reclaimKeys() {
        guard let window = store?.mainWindow, window.firstResponder !== window else { return }
        if previousResponder == nil { previousResponder = window.firstResponder }
        window.makeFirstResponder(nil)
    }

    /// Handles a key typed while the tour shows; returns the event when the window should still receive it.
    func handle(_ event: NSEvent) -> NSEvent? {
        guard isPresented, !isPaused, let window = store?.mainWindow, event.window === window else { return event }
        let modifiers = event.modifierFlags.intersection([.command, .control, .option])
        let key = event.charactersIgnoringModifiers?.lowercased() ?? ""
        if modifiers == .command, key == "w" { close(); return nil }
        // Quitting, and editing a field.
        if modifiers == .command, ["q", "a", "c", "v", "x", "z"].contains(key) { return event }
        if !modifiers.isEmpty || Self.functionKeys.contains(event.keyCode) {
            pause()
            return event
        }
        if window.firstResponder is NSTextView {
            guard event.keyCode == 53 else { return event }
            if query.isEmpty { window.makeFirstResponder(nil) } else { query = "" }
            return nil
        }
        // The page, a list or another control has the keyboard: the window keeps working under the tour.
        if let responder = window.firstResponder, responder !== window { return event }
        switch event.keyCode {
        case 53: close()
        case 123: back()
        case 124, 36, 76: next()
        case 48: return event
        default: return event
        }
        return nil
    }

    private static let functionKeys: Set<UInt16> = [96, 97, 98, 99, 100, 101, 103, 109, 111, 118, 120, 122]
}
