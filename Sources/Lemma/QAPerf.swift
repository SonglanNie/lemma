import AppKit
import QuartzCore
import PDFKit

/// Performance probes for QA copies: how often SwiftUI evaluates the views that follow the reading position, and a
/// scrolling benchmark. Counting is off except while a benchmark runs, so a probe costs one Boolean test.
@MainActor
enum QAPerf {
    static private(set) var counting = false
    static private(set) var counts: [String: Int] = [:]

    /// Records one evaluation of a view's body (or another event) while a benchmark runs.
    static func tick(_ name: String) { if counting { counts[name, default: 0] += 1 } }

    /// Scrolls the main PDF view through `pages` pages, `step` points on screen per frame at `fps` frames per second,
    /// and writes the main thread's busy time per frame (mean, p50, p95, p99, max, frames over the 120 Hz and 60 Hz
    /// budgets), the duration of the scroll call itself and the number of body evaluations of the views that follow
    /// the reading position.
    ///
    /// Method: a timer in the common run-loop modes moves the clip view as momentum scrolling does (with the scroll view's
    /// live-scroll notifications around it, as a trackpad gesture posts them), and a run-loop
    /// observer ordered after Core Animation's commit adds up the time from each wake-up to the next wait. A frame's
    /// busy time is the sum over the run-loop turns between two ticks: the scroll, the notifications and async blocks
    /// it triggers, SwiftUI updates, layout, drawing and the transaction commit (not the render server's own work).
    static func scrollBench(store: StudyStore, info: [String: String], output: URL) async throws {
        guard let view = store.reader.view, let document = view.document, let documentView = view.documentView,
              let scrollView = documentView.enclosingScrollView, let current = view.currentPage else { throw QAHooks.QAError.missing("open book") }
        let pages = Int(info["pages"] ?? "") ?? 30
        let step = CGFloat(Double(info["step"] ?? "") ?? 24)
        let fps = Double(info["fps"] ?? "") ?? 120
        let clip = scrollView.contentView
        let startIndex = document.index(for: current)
        let endIndex = min(document.pageCount - 1, startIndex + max(1, pages))
        guard let endPage = document.page(at: endIndex) else { throw QAHooks.QAError.missing("end page") }
        let target = documentView.convert(view.convert(endPage.bounds(for: .cropBox), from: endPage), from: view)
        let startY = clip.bounds.origin.y
        let endY = documentView.isFlipped ? target.minY - 8 : target.maxY + 8 - clip.bounds.height
        let stepInDocument = step / max(scrollView.magnification, 0.01)
        let frameCount = max(1, Int((abs(endY - startY) / max(stepInDocument, 0.1)).rounded(.up)))

        let run = ScrollBenchRun(scrollView: scrollView, startY: startY, endY: endY, frameCount: frameCount)
        counts = [:]; counting = true
        let started = CACurrentMediaTime()
        await run.perform(fps: fps)
        let wall = CACurrentMediaTime() - started
        // PDFKit moves its current page a moment after scrolling stops; the work that follows is reported apart.
        let settle = await run.settle(seconds: 0.4)
        counting = false

        let busy = run.busy, calls = run.calls
        func percentile(_ values: [Double], _ p: Double) -> Double {
            let sorted = values.sorted()
            return sorted.isEmpty ? 0 : sorted[min(sorted.count - 1, Int((Double(sorted.count - 1) * p).rounded()))]
        }
        func rounded(_ value: Double) -> Double { (value * 1000).rounded() / 1000 }
        func mean(_ values: [Double]) -> Double { values.isEmpty ? 0 : values.reduce(0, +) / Double(values.count) }
        let result: [String: Any] = [
            "frames": busy.count, "wallSeconds": rounded(wall), "fps": fps, "stepPoints": step,
            "pageStart": startIndex + 1, "pageEnd": document.index(for: view.currentPage ?? endPage) + 1,
            "magnification": rounded(scrollView.magnification), "displayMode": view.displayMode.rawValue,
            "lineNumbers": store.reader.showLineNumbers, "links": store.reader.showReferenceLinks, "counts": store.reader.showReferenceCounts,
            "analysis": store.analysis?.analysis != nil, "minimap": store.app.showMinimap,
            "busyMs": ["mean": rounded(mean(busy)), "p50": rounded(percentile(busy, 0.5)), "p95": rounded(percentile(busy, 0.95)),
                       "p99": rounded(percentile(busy, 0.99)), "max": rounded(busy.max() ?? 0), "total": rounded(busy.reduce(0, +))],
            "framesOver8ms": busy.filter { $0 > 1000 / 120 }.count, "framesOver16ms": busy.filter { $0 > 1000 / 60 }.count,
            "scrollCallMs": ["mean": rounded(mean(calls)), "p95": rounded(percentile(calls, 0.95))],
            "settleBusyMs": rounded(settle * 1000),
            "bodies": counts,
            // The mean busy time of frames in which each event happened, against frames without any of them.
            "framesWith": run.eventCosts().mapValues { ["frames": $0.frames, "meanMs": rounded($0.mean)] }
        ]
        try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys]).write(to: output)
    }
}

extension QAPerf {
    /// Turns a mouse wheel with ⌘ held over the main PDF view (its middle, or `x`, `y`), as a free-spinning wheel sends
    /// it: `events` scroll events `gap` ms apart, each of `lines` lines and `points` points, zooming in (`direction=out`
    /// zooms out). Writes the main thread's busy time between events (each, mean, p95, max, events over the gap), the time of the
    /// scroll call itself, the zoom after each event, how far the point under the pointer moved, the scale notifications
    /// PDFKit posted and the body evaluations.
    static func zoomBench(store: StudyStore, info: [String: String], output: URL) async throws {
        guard let view = store.reader.view, view.window != nil else { throw QAHooks.QAError.missing("open book") }
        let events = Int(info["events"] ?? "") ?? 60, lines = Int64(info["lines"] ?? "") ?? 40
        let gap = Double(info["gap"] ?? "") ?? 15, points = Double(info["points"] ?? "") ?? 400
        let sign: Double = info["direction"] == "out" ? -1 : 1
        // x= and y= (0.5): where the pointer is, as fractions of the view's width and height from its top left.
        let x = Double(info["x"] ?? "") ?? 0.5, y = Double(info["y"] ?? "") ?? 0.5
        let inWindow = view.convert(CGPoint(x: view.bounds.minX + view.bounds.width * x,
                                            y: view.isFlipped ? view.bounds.minY + view.bounds.height * y : view.bounds.maxY - view.bounds.height * y), to: nil)
        // The point of the page under the pointer, which should stay there (until the document's edge stops it).
        let pointer = view.convert(inWindow, from: nil), page = view.page(for: pointer, nearest: true)
        let anchor = page.map { view.convert(pointer, to: $0) }
        // An event made here has no window, so its location in the window is its location on the screen: it is given the
        // pointer's window coordinates, as the screen numbers them from the top.
        let location = CGPoint(x: inWindow.x, y: (NSScreen.screens.first?.frame.height ?? 0) - inWindow.y)
        final class Box { var notes = 0 }
        let box = Box()
        let observer = NotificationCenter.default.addObserver(forName: .PDFViewScaleChanged, object: view, queue: nil) { _ in box.notes += 1 }
        defer { NotificationCenter.default.removeObserver(observer) }
        let meter = BusyMeter()
        var busy: [Double] = [], calls: [Double] = [], scales: [Double] = [Double(view.scaleFactor)], drift: [Double] = []
        counts = [:]; counting = true
        meter.start()
        let started = CACurrentMediaTime()
        for _ in 0..<events {
            guard let event = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 1, wheel1: Int32(sign * points), wheel2: 0, wheel3: 0) else { continue }
            event.setIntegerValueField(.scrollWheelEventIsContinuous, value: 1)
            event.setIntegerValueField(.scrollWheelEventDeltaAxis1, value: Int64(sign) * lines)
            event.setDoubleValueField(.scrollWheelEventPointDeltaAxis1, value: sign * points)
            event.timestamp = clock_gettime_nsec_np(CLOCK_UPTIME_RAW)
            event.location = location
            event.flags = .maskCommand
            guard let scroll = NSEvent(cgEvent: event) else { continue }
            let before = CACurrentMediaTime()
            view.scrollWheel(with: scroll)
            calls.append((CACurrentMediaTime() - before) * 1000)
            try await Task.sleep(for: .milliseconds(gap))
            busy.append(meter.take() * 1000)
            scales.append(Double(view.scaleFactor))
            if let anchor, let page {
                let held = view.convert(anchor, from: page)
                drift.append(Double(hypot(held.x - pointer.x, held.y - pointer.y)))
            }
        }
        let wall = CACurrentMediaTime() - started
        try await Task.sleep(for: .milliseconds(400))
        let settle = meter.take() * 1000
        meter.stop()
        counting = false
        scales.append(Double(view.scaleFactor))
        func rounded(_ value: Double) -> Double { (value * 1000).rounded() / 1000 }
        func percentile(_ values: [Double], _ p: Double) -> Double {
            let sorted = values.sorted()
            return sorted.isEmpty ? 0 : sorted[min(sorted.count - 1, Int((Double(sorted.count - 1) * p).rounded()))]
        }
        let result: [String: Any] = [
            "events": events, "gapMs": gap, "lines": lines, "wallSeconds": rounded(wall),
            "busyMs": ["mean": rounded(busy.reduce(0, +) / Double(max(busy.count, 1))), "p95": rounded(percentile(busy, 0.95)),
                       "max": rounded(busy.max() ?? 0)],
            "eventsOverGap": busy.filter { $0 > gap }.count,
            "scrollCallMs": ["mean": rounded(calls.reduce(0, +) / Double(max(calls.count, 1))), "p95": rounded(percentile(calls, 0.95))],
            "settleBusyMs": rounded(settle), "scaleNotifications": box.notes, "maxDriftPoints": rounded(drift.max() ?? 0),
            "busy": busy.map { ($0 * 10).rounded() / 10 }, "scales": scales.map(rounded), "bodies": counts
        ]
        try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys]).write(to: output)
    }
}

/// One benchmark pass: a timer that moves the clip view a step per tick and reads the busy time of the frame before.
@MainActor
private final class ScrollBenchRun {
    private let scrollView: NSScrollView
    private let startY: CGFloat, endY: CGFloat
    private let frameCount: Int
    private let meter = BusyMeter()
    private var frame = 0
    private var timer: Timer?
    private var finished: CheckedContinuation<Void, Never>?
    private(set) var busy: [Double] = []
    private(set) var calls: [Double] = []
    /// The probe counts at each tick, to attribute each frame's busy time to what happened in it.
    private var events: [[String: Int]] = []
    private var lastCounts: [String: Int] = [:]

    init(scrollView: NSScrollView, startY: CGFloat, endY: CGFloat, frameCount: Int) {
        self.scrollView = scrollView; self.startY = startY; self.endY = endY; self.frameCount = frameCount
    }

    func perform(fps: Double) async {
        meter.start()
        NotificationCenter.default.post(name: NSScrollView.willStartLiveScrollNotification, object: scrollView)
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            finished = continuation
            let timer = Timer(timeInterval: 1 / fps, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.tick() }
            }
            self.timer = timer
            RunLoop.main.add(timer, forMode: .common)
        }
        NotificationCenter.default.post(name: NSScrollView.didEndLiveScrollNotification, object: scrollView)
    }

    func eventCosts() -> [String: (frames: Int, mean: Double)] {
        var sums: [String: (Int, Double)] = [:]
        var quiet = (0, 0.0)
        for (frame, names) in zip(busy, events) {
            if names.isEmpty { quiet.0 += 1; quiet.1 += frame }
            for name in names.keys { sums[name, default: (0, 0)].0 += 1; sums[name, default: (0, 0)].1 += frame }
        }
        var result = sums.mapValues { (frames: $0.0, mean: $0.1 / Double(max($0.0, 1))) }
        result["(none)"] = (quiet.0, quiet.1 / Double(max(quiet.0, 1)))
        return result
    }

    /// Busy time after the last frame, while the reader settles.
    func settle(seconds: Double) async -> CFTimeInterval {
        _ = meter.take()
        try? await Task.sleep(for: .seconds(seconds))
        let busy = meter.take()
        meter.stop()
        return busy
    }

    private func tick() {
        let previous = meter.take() * 1000
        if frame > 0 {
            busy.append(previous)
            let now = QAPerf.counts
            events.append(now.filter { $0.value != lastCounts[$0.key] }.mapValues { _ in 1 })
            lastCounts = now
        } else { lastCounts = QAPerf.counts }
        guard frame < frameCount else {
            timer?.invalidate(); timer = nil
            finished?.resume(); finished = nil
            return
        }
        frame += 1
        let clip = scrollView.contentView
        let y = startY + (endY - startY) * CGFloat(frame) / CGFloat(frameCount)
        let before = CACurrentMediaTime()
        clip.scroll(to: CGPoint(x: clip.bounds.origin.x, y: y))
        scrollView.reflectScrolledClipView(clip)
        NotificationCenter.default.post(name: NSScrollView.didLiveScrollNotification, object: scrollView)
        calls.append((CACurrentMediaTime() - before) * 1000)
    }
}

/// Time the main thread spends between waking up and waiting again, read once per frame.
private final class BusyMeter: @unchecked Sendable {
    private var wake: CFTimeInterval = 0
    private var busy: CFTimeInterval = 0
    private var observer: CFRunLoopObserver?

    func start() {
        wake = CACurrentMediaTime(); busy = 0
        let activities = CFRunLoopActivity.afterWaiting.rawValue | CFRunLoopActivity.beforeWaiting.rawValue
        // Ordered last, after Core Animation's commit observer, so a turn's busy time includes the commit.
        let observer = CFRunLoopObserverCreateWithHandler(kCFAllocatorDefault, activities, true, CFIndex.max) { [unowned self] _, activity in
            let now = CACurrentMediaTime()
            if activity == .afterWaiting { self.wake = now }
            else if self.wake > 0 { self.busy += now - self.wake; self.wake = 0 }
        }
        CFRunLoopAddObserver(CFRunLoopGetMain(), observer, .commonModes)
        self.observer = observer
    }

    func stop() {
        guard let observer else { return }
        CFRunLoopRemoveObserver(CFRunLoopGetMain(), observer, .commonModes)
        CFRunLoopObserverInvalidate(observer)
        self.observer = nil
    }

    /// Busy time since the previous call, including the turn in progress up to now.
    func take() -> CFTimeInterval {
        let now = CACurrentMediaTime()
        var total = busy
        if wake > 0 { total += now - wake; wake = now }
        busy = 0
        return total
    }
}

/// A trackpad gesture for QA copies, sent inside the process to the view under a point of a window, as AppKit sends a
/// scroll event to the view its hit test finds: began, `steps` changes of (dx, dy) points, ended, then `momentum`
/// momentum events. It shows who receives the gesture and whether the scroll views around the point follow it at once.
@MainActor
enum QAWheel {
    static func perform(window: NSWindow, info: [String: String], output: URL) async throws {
        guard let content = window.contentView else { throw QAHooks.QAError.missing("window content") }
        // x and y are points from the window's top left; target=math aims at the middle of the first typeset preview on
        // screen, target=mathAbove at 12 points above it (the pane's own content, for comparison).
        var point = NSPoint(x: Double(info["x"] ?? "") ?? 0, y: window.frame.height - (Double(info["y"] ?? "") ?? 0))
        if let aim = info["target"] {
            func previews(in view: NSView) -> [MathWebView] { (view as? MathWebView).map { [$0] } ?? view.subviews.flatMap(previews) }
            // What of each preview its scroll view shows, in window coordinates.
            func shown(_ preview: MathWebView) -> NSRect {
                let frame = preview.convert(preview.bounds, to: nil)
                guard let clip = preview.enclosingScrollView?.contentView else { return frame }
                return frame.intersection(clip.convert(clip.bounds, to: nil))
            }
            guard let preview = previews(in: content).first(where: { !shown($0).isEmpty }) else { throw QAHooks.QAError.missing("a typeset preview on screen") }
            let visible = shown(preview)
            point = NSPoint(x: visible.midX, y: aim == "mathAbove" ? visible.maxY + 12 : visible.midY)
        }
        guard let target = content.hitTest(point) else { throw QAHooks.QAError.missing("a view at that point") }
        let steps = Int(info["steps"] ?? "") ?? 8, momentum = Int(info["momentum"] ?? "") ?? 6
        let dx = Double(info["dx"] ?? "") ?? 0, dy = Double(info["dy"] ?? "") ?? -24
        var scrollViews: [NSScrollView] = []
        var chain: [String] = []
        var view: NSView? = target
        while let current = view {
            chain.append(String(describing: type(of: current)))
            if let scroll = current as? NSScrollView { scrollViews.append(scroll) }
            view = current.superview
        }
        let screen = window.convertPoint(toScreen: point)
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        let location = CGPoint(x: screen.x, y: primaryHeight - screen.y)
        var log: [[String: Any]] = []
        func record(_ label: String) {
            log.append(["event": label, "offsets": scrollViews.map { Double($0.documentVisibleRect.origin.y) }])
        }
        // Phases as CGEvent numbers them: began 1, changed 2, ended 4; momentum begin 1, continue 2, end 3.
        var plan: [(label: String, phase: Int64, momentum: Int64, dx: Double, dy: Double)] = [("began", 1, 0, dx, dy)]
        plan += Array(repeating: ("changed", 2, 0, dx, dy), count: max(0, steps - 1))
        plan.append(("ended", 4, 0, 0, 0))
        if momentum > 0 {
            plan.append(("momentumBegin", 0, 1, dx * 0.8, dy * 0.8))
            for index in 1..<max(2, momentum) { let decay = pow(0.8, Double(index + 1)); plan.append(("momentum", 0, 2, dx * decay, dy * decay)) }
            plan.append(("momentumEnd", 0, 3, 0, 0))
        }
        record("start")
        for step in plan {
            guard let event = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 2, wheel1: Int32(step.dy), wheel2: Int32(step.dx), wheel3: 0) else { continue }
            event.setIntegerValueField(.scrollWheelEventIsContinuous, value: 1)
            event.setIntegerValueField(.scrollWheelEventScrollPhase, value: step.phase)
            event.setIntegerValueField(.scrollWheelEventMomentumPhase, value: step.momentum)
            event.setDoubleValueField(.scrollWheelEventPointDeltaAxis1, value: step.dy)
            event.setDoubleValueField(.scrollWheelEventPointDeltaAxis2, value: step.dx)
            event.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1, value: step.dy)
            event.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2, value: step.dx)
            event.location = location
            guard let scroll = NSEvent(cgEvent: event) else { continue }
            target.scrollWheel(with: scroll)
            try await Task.sleep(for: .milliseconds(16))
            record(step.label)
        }
        try await Task.sleep(for: .milliseconds(700))
        record("settled")
        let result: [String: Any] = ["views": chain, "scrollViews": scrollViews.count, "point": [point.x, window.frame.height - point.y], "log": log]
        try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted]).write(to: output)
    }
}
