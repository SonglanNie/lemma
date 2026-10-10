import AppKit

@MainActor
extension TutorialCenter {
    /// QA actions for the tour: `tutorial` (the guides at a glance), `tutorialTour`, `tutorialGuide id=…`,
    /// `tutorialStep id=…`, `tutorialScreen value=welcome|look|home|finish`, `tutorialNext`, `tutorialBack`,
    /// `tutorialPause`, `tutorialResume`, `tutorialClose`, `tutorialReplay`, `tutorialAction index=…`,
    /// `tutorialQuery value=…`, `tutorialWindowSize value=960x640`, `tutorialFirstLaunch` (forgets that the tour was shown and opens it as on a first launch)
    /// and `tutorialState` (the screen, the step, where its callout sits and what it lights up, and every step id).
    func performQA(_ action: String, info: [String: String], store: StudyStore) {
        switch action {
        case "tutorial", "tutorialHome", "tutorialMap": open(store)
        case "tutorialTour": startTour(store)
        case "tutorialGuide": open(store, guide: info["id"] ?? "")
        case "tutorialStep":
            if !isPresented { startTour(store) }
            if let id = info["id"] { open(stepID: id) }
        case "tutorialScreen":
            if !isPresented { open(store) }
            switch info["value"] {
            case "welcome": showSetupForQA(.welcome)
            case "look": showSetupForQA(.look)
            case "finish": open(stepID: tour.steps[tour.steps.count - 1].id); next()
            default: showHome()
            }
        case "tutorialNext": next()
        case "tutorialBack": back()
        case "tutorialPause", "tutorialMinimize": pause()
        case "tutorialResume", "tutorialRestore": resume()
        case "tutorialClose": close()
        case "tutorialReplay": replay += 1
        case "tutorialQuery": query = info["value"] ?? ""
        case "tutorialWindowSize":
            // `value=960x640`: the window's content size, to check the pages in a small window.
            let parts = (info["value"] ?? "").split(separator: "x").compactMap { Double($0) }
            if parts.count == 2, let window = store.mainWindow { window.setContentSize(NSSize(width: parts[0], height: parts[1])) }
        case "tutorialAction":
            let index = Int(info["index"] ?? "") ?? 0
            if screen == .step, step.actions.indices.contains(index) { perform(step.actions[index]) }
        case "tutorialFirstLaunch":
            UserDefaults.standard.removeObject(forKey: TutorialPreferences.shown)
            setenv("LEMMA_SHOW_TUTORIAL", "1", 1)
            presentIfFirstLaunch(store)
        case "tutorialState":
            var state: [String: Any] = ["presented": isPresented, "paused": isPaused, "screen": "\(screen)", "step": step.id,
                                        "guides": guides.map { ["id": $0.id, "steps": $0.steps.map(\.id)] },
                                        "seen": seenCount, "lessons": lessonCount, "shown": UserDefaults.standard.bool(forKey: TutorialPreferences.shown)]
            if screen == .step, !isPaused { state["layout"] = qaLayout }
            if let directory = QAHooks.shared?.directory, let data = try? JSONSerialization.data(withJSONObject: state, options: [.prettyPrinted, .sortedKeys]) {
                try? data.write(to: directory.appendingPathComponent("\(info["name"] ?? "tutorial").json"))
            }
        default: break
        }
    }
}
