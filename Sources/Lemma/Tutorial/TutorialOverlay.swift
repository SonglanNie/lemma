import SwiftUI
import AppKit
import LemmaCore

/// The tour over the window. A step is a callout beside the part of the real window it explains, the rest dimmed
/// (Show Me); when that part cannot be shown, the step is a card in the middle with its animation. The first
/// launch's pages, the guides at a glance and the tour's last page are cards over the dimmed window, and a pill waits
/// at the bottom while the reader tries something. Placed over both interfaces; the parts of the window it can light
/// up report their frames through `tutorialAnchor`.
struct TutorialOverlay: View {
    @Bindable var store: StudyStore
    let anchors: [TutorialTarget: Anchor<CGRect>]
    @State private var center = TutorialCenter.shared
    @Environment(\.theme) private var theme

    var body: some View {
        if center.isPresented {
            GeometryReader { proxy in
                let bounds = CGRect(origin: .zero, size: proxy.size)
                ZStack {
                    if center.isPaused {
                        TutorialPill(store: store)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                            .padding(.bottom, 36)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    } else if center.screen == .step {
                        TutorialCoach(store: store, frames: anchors.mapValues { proxy[$0] }, bounds: bounds)
                            .transition(.opacity)
                    } else {
                        Rectangle().fill(Color.black.opacity(theme.isDark ? 0.45 : 0.22))
                            .contentShape(Rectangle())
                            .onTapGesture {}
                            .accessibilityHidden(true)
                            .transition(.opacity)
                        TutorialPages(store: store, size: proxy.size)
                    }
                }
                .frame(width: proxy.size.width, height: proxy.size.height)
                .foregroundStyle(theme.tourText)
            }
            .ignoresSafeArea()
            .transition(.opacity)
        }
    }
}

// MARK: - Placing the callout

/// Where a step's callout goes: beside the part of the window it explains, pointing at it.
enum TutorialCoachLayout {
    static let cardWidth: CGFloat = 352
    static let stagedWidth: CGFloat = 560

    /// What the callout points at: a part of the window, lit; the Classic toolbar, above the window's content; or
    /// nothing, when the part is not on screen.
    enum Anchor: Equatable { case lit(CGRect), toolbar(CGRect), none }

    /// The callout's top-left corner, the edge that carries its beak, and where along that edge the beak points.
    struct Placement: Equatable {
        var origin: CGPoint
        var edge: Edge?
        var beak: CGFloat
    }

    static func anchor(for target: TutorialTarget?, frames: [TutorialTarget: CGRect], bounds: CGRect, style: WorkbenchStyle) -> Anchor {
        guard let target else { return .none }
        if style == .classic, target.inClassicToolbar {
            let width: CGFloat = target == .layoutControls ? 120 : 320
            let x = target == .layoutControls ? bounds.maxX - width - 16 : bounds.midX - width / 2
            return .toolbar(CGRect(x: x, y: bounds.minY - 30, width: width, height: 26))
        }
        for alternative in target.alternatives {
            guard let frame = frames[alternative], frame.width >= 8, frame.height >= 8 else { continue }
            let hole = frame.insetBy(dx: -4, dy: -4).intersection(bounds.insetBy(dx: 2, dy: 2))
            if !hole.isNull, hole.width >= 8, hole.height >= 8 { return .lit(hole) }
        }
        return .none
    }

    static func placement(card: CGSize, anchor: Anchor, in bounds: CGRect) -> Placement {
        switch anchor {
        case let .lit(hole), let .toolbar(hole): place(card: card, near: hole, in: bounds)
        case .none: Placement(origin: CGPoint(x: bounds.midX - card.width / 2, y: max(bounds.minY + 16, bounds.midY - card.height / 2 - 12)), edge: nil, beak: 0)
        }
    }

    /// Beside a tall part (right, then left), under or over a wide one; inside a part that leaves no room around it,
    /// at its lower trailing corner.
    static func place(card: CGSize, near hole: CGRect, in bounds: CGRect, gap: CGFloat = 8, margin: CGFloat = 12) -> Placement {
        let room = bounds.insetBy(dx: margin, dy: margin)
        let reach = gap + CoachBubble.beakLength
        func clampX(_ x: CGFloat) -> CGFloat { min(max(x, room.minX), room.maxX - card.width) }
        func clampY(_ y: CGFloat) -> CGFloat { min(max(y, room.minY), room.maxY - card.height) }
        let sides: [Edge] = hole.height > hole.width ? [.trailing, .leading, .bottom, .top] : [.bottom, .top, .trailing, .leading]
        for side in sides {
            switch side {
            case .trailing where hole.maxX + reach + card.width <= room.maxX:
                let y = clampY(hole.midY - card.height / 2)
                return Placement(origin: CGPoint(x: hole.maxX + reach, y: y), edge: .leading, beak: hole.midY - y)
            case .leading where hole.minX - reach - card.width >= room.minX:
                let y = clampY(hole.midY - card.height / 2)
                return Placement(origin: CGPoint(x: hole.minX - reach - card.width, y: y), edge: .trailing, beak: hole.midY - y)
            case .bottom where hole.maxY + reach + card.height <= room.maxY:
                let x = clampX(hole.midX - card.width / 2)
                return Placement(origin: CGPoint(x: x, y: hole.maxY + reach), edge: .top, beak: hole.midX - x)
            case .top where hole.minY - reach - card.height >= room.minY:
                let x = clampX(hole.midX - card.width / 2)
                return Placement(origin: CGPoint(x: x, y: hole.minY - reach - card.height), edge: .bottom, beak: hole.midX - x)
            default: continue
            }
        }
        let inside = hole.intersection(room)
        return Placement(origin: CGPoint(x: clampX(inside.maxX - card.width - 16), y: clampY(inside.maxY - card.height - 16)), edge: nil, beak: 0)
    }
}

// MARK: - A step

/// The step over the window: the part it explains lit, the rest dimmed but still usable, and the callout beside it.
private struct TutorialCoach: View {
    @Bindable var store: StudyStore
    let frames: [TutorialTarget: CGRect]
    let bounds: CGRect
    @State private var center = TutorialCenter.shared
    @State private var themes = ThemeManager.shared
    @State private var measured: CGSize?
    /// The step whose part of the window has had a moment to appear; until then its card in the middle waits, so a
    /// part the step has just revealed is lit without a flash of that card.
    @State private var patientStep: String?
    @Environment(\.theme) private var theme

    var body: some View {
        let anchor = TutorialCoachLayout.anchor(for: center.step.target, frames: frames, bounds: bounds, style: themes.style)
        let staged = anchor == .none
        let waiting = staged && center.step.target != nil && patientStep != center.step.id
        let width = staged ? min(TutorialCoachLayout.stagedWidth, bounds.width - 48) : TutorialCoachLayout.cardWidth
        let size = CGSize(width: width, height: measured?.height ?? (staged ? 470 : 220))
        let placement = TutorialCoachLayout.placement(card: size, anchor: anchor, in: bounds)
        let lit: CGRect? = if case let .lit(rect) = anchor { rect } else { nil }
        let hole = lit ?? CGRect(x: bounds.midX, y: bounds.midY, width: 0, height: 0)
        ZStack(alignment: .topLeading) {
            // Lighter without a lit part: the window stays readable around the card.
            SpotlightShape(hole: hole)
                .fill(Color.black.opacity(lit == nil ? (theme.isDark ? 0.34 : 0.18) : (theme.isDark ? 0.42 : 0.26)), style: FillStyle(eoFill: true))
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            if lit != nil {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(theme.tourAccent, lineWidth: 1.5)
                    .frame(width: hole.width, height: hole.height)
                    .offset(x: hole.minX, y: hole.minY)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
            TutorialStepCard(store: store, staged: staged, placement: placement)
                .frame(width: width)
                .fixedSize(horizontal: false, vertical: true)
                .onGeometryChange(for: CGSize.self) { $0.size } action: { measured = $0 }
                .opacity(measured == nil || waiting ? 0 : 1)
                .offset(x: placement.origin.x, y: placement.origin.y)
        }
        .frame(width: bounds.width, height: bounds.height, alignment: .topLeading)
        .task(id: center.step.id) {
            try? await Task.sleep(for: .milliseconds(200))
            patientStep = center.step.id
        }
        .animation(.spring(response: 0.42, dampingFraction: 0.88), value: placement)
        .animation(.spring(response: 0.42, dampingFraction: 0.88), value: hole)
        .onChange(of: QALayout(step: center.step.id, anchor: anchor, placement: placement, size: size), initial: true) { _, layout in
            guard QAHooks.shared != nil else { return }
            center.qaLayout = layout.dictionary
        }
    }

    /// What QA reads back about the step on screen.
    private struct QALayout: Equatable {
        let step: String
        let anchor: TutorialCoachLayout.Anchor
        let placement: TutorialCoachLayout.Placement
        let size: CGSize
        var dictionary: [String: Any] {
            let mode: String
            var target: [Double] = []
            switch anchor {
            case let .lit(rect): mode = "spotlight"; target = [rect.minX, rect.minY, rect.width, rect.height].map(Double.init)
            case let .toolbar(rect): mode = "toolbar"; target = [rect.minX, rect.minY, rect.width, rect.height].map(Double.init)
            case .none: mode = "card"
            }
            let edge = placement.edge.map { "\($0)" } ?? "none"
            return ["step": step, "mode": mode, "target": target, "edge": edge,
                    "card": [placement.origin.x, placement.origin.y, size.width, size.height].map(Double.init)]
        }
    }
}

/// The callout of a step: its title and explanation, its shortcuts, what to try, and how far the guide has come.
/// Without a part of the window to point at, it also shows the step's animation.
private struct TutorialStepCard: View {
    @Bindable var store: StudyStore
    let staged: Bool
    let placement: TutorialCoachLayout.Placement
    @State private var center = TutorialCenter.shared
    @State private var themes = ThemeManager.shared
    @Environment(\.theme) private var theme

    var body: some View {
        let step = center.step
        let bubble = CoachBubble(edge: placement.edge, offset: placement.beak)
        VStack(alignment: .leading, spacing: 0) {
            TutorialProgressStrip()
            VStack(alignment: .leading, spacing: 0) {
                if staged { stage(step).padding(.top, 14) }
                HStack(alignment: .top, spacing: 8) {
                    Text(step.title)
                        .font(.system(size: staged ? 17 : 15, weight: .semibold))
                        .foregroundStyle(theme.tourText)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                    Spacer(minLength: 4)
                    TutorialCloseButton(help: center.isTour ? "Skip the tour (⎋). Help › Lemma Tour brings it back." : "Close the guide (⎋)") { center.close() }
                        .padding(.top, -2).padding(.trailing, -4)
                }
                .padding(.top, staged ? 14 : 12)
                TutorialProse.text(step.text(for: themes.style), size: 13)
                    .lineSpacing(2.5)
                    .foregroundStyle(theme.tourSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 5)
                if !step.tips.isEmpty { keys(Array(step.tips.prefix(2))).padding(.top, 12) }
                actions(step)
            }
            .id(step.id)
            .transition(.opacity.animation(.easeOut(duration: 0.16)))
            footer.padding(.top, 16)
        }
        .padding(16)
        .background {
            bubble.fill(theme.tourSurface)
                .shadow(color: theme.tourShadow, radius: 20, y: 10)
            bubble.stroke(theme.tourBorder, lineWidth: 1)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(center.guide.title), step \(center.stepIndex + 1) of \(center.guide.steps.count)")
    }

    private func stage(_ step: TutorialStep) -> some View {
        let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)
        return ZStack {
            shape.fill(theme.tourFill)
            TutorialSceneView(scene: step.scene, replay: center.replay, style: themes.style)
                .id("\(step.id)-\(themes.style.rawValue)")
                .padding(.horizontal, 8).padding(.vertical, 6)
        }
        .aspectRatio(2, contentMode: .fit)
        .clipShape(shape)
        .overlay(shape.strokeBorder(theme.tourHairline, lineWidth: 1))
        // Top right: the scenes put key caps and pointers along their bottom edge.
        .overlay(alignment: .topTrailing) {
            Button { center.replay += 1 } label: {
                Codicon("refresh", size: 13).foregroundStyle(theme.tourSecondary)
                    .frame(width: 26, height: 26)
                    .background(Circle().fill(theme.tourSurface.opacity(0.9)))
                    .overlay(Circle().strokeBorder(theme.tourHairline, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .help("Play the animation again")
            .accessibilityLabel("Replay the animation")
            .padding(8)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Animation: \(step.title)")
    }

    private func keys(_ tips: [TutorialTip]) -> some View {
        let row = { (tip: TutorialTip) in
            HStack(spacing: 7) {
                TutorialKeys(shortcut: tip.keys, size: 11)
                Text(tip.text).font(.system(size: 12)).foregroundStyle(theme.tourSecondary).lineLimit(1)
            }
        }
        return ViewThatFits(in: .horizontal) {
            HStack(spacing: 16) { ForEach(tips, id: \.self) { row($0) } }
            VStack(alignment: .leading, spacing: 7) { ForEach(tips, id: \.self) { row($0) } }
        }
    }

    @ViewBuilder private func actions(_ step: TutorialStep) -> some View {
        let needsBook = store.document == nil
            && ((staged && step.target?.needsBook == true) || step.actions.contains { $0.requires != .none && !$0.requires.isMet(store) })
        if !step.actions.isEmpty {
            HStack(spacing: 8) {
                ForEach(step.actions) { action in
                    let ready = action.requires.isMet(store)
                    Button { center.perform(action) } label: {
                        HStack(spacing: 6) { Codicon(action.icon, size: 13); Text(action.title) }
                    }
                    .buttonStyle(TutorialButtonStyle(kind: .secondary))
                    .disabled(!ready)
                    .help(ready ? "Try it now; the tour waits at the bottom of the window" : action.requires.hint)
                }
            }
            .padding(.top, 14)
        }
        if needsBook {
            HStack(spacing: 6) {
                Codicon("info", size: 13).foregroundStyle(theme.tourTertiary)
                Text("Open a book to see this on your own window.").font(.system(size: 12)).foregroundStyle(theme.tourTertiary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 4)
                Button("Open a PDF…") { store.choosePDF() }.buttonStyle(TutorialButtonStyle(kind: .quiet))
            }
            .padding(.top, 12)
        }
    }

    private var footer: some View {
        HStack(spacing: 8) {
            if center.isTour {
                Button("Skip Tour") { center.close() }
                    .buttonStyle(TutorialButtonStyle(kind: .quiet))
                    .help("Close the tour (⎋). Help › Lemma Tour brings it back where you left it.")
                    .padding(.leading, -8)
            } else {
                Button("All Guides") { center.showHome() }
                    .buttonStyle(TutorialButtonStyle(kind: .quiet))
                    .padding(.leading, -8)
            }
            Spacer(minLength: 8)
            if center.canGoBack {
                Button { center.back() } label: { Codicon("arrow-left", size: 13) }
                    .buttonStyle(TutorialButtonStyle(kind: .secondary))
                    .help("Back (←)")
                    .accessibilityLabel("Back")
            }
            Button { center.next() } label: {
                HStack(spacing: 6) {
                    Text(nextTitle)
                    if !(center.isLastStep && !center.isTour) { Codicon("arrow-right", size: 13) }
                }
            }
            .buttonStyle(TutorialButtonStyle(kind: .primary))
            .help(center.isLastStep && !center.isTour ? "Close the guide (Return)" : "Next (→ or Return)")
        }
    }

    private var nextTitle: String {
        guard center.isLastStep else { return "Next" }
        return center.isTour ? "Finish" : "Done"
    }
}

/// How far the guide has come: one segment per step, filled up to the step on screen. Each segment opens its step.
private struct TutorialProgressStrip: View {
    @State private var center = TutorialCenter.shared
    @Environment(\.theme) private var theme

    var body: some View {
        HStack(spacing: 4) {
            ForEach(Array(center.guide.steps.enumerated()), id: \.element.id) { index, step in
                Button { if index != center.stepIndex { center.open(stepID: step.id) } } label: {
                    Capsule()
                        .fill(index <= center.stepIndex ? theme.tourAccent : theme.tourText.opacity(0.14))
                        .frame(height: 3)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(step.title)
            }
        }
        .padding(.top, -4)
        .animation(.easeOut(duration: 0.25), value: center.stepIndex)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Step \(center.stepIndex + 1) of \(center.guide.steps.count)")
    }
}

/// The window dimmed around one rounded hole; the hole moves smoothly from one part of the window to the next.
private struct SpotlightShape: Shape {
    var hole: CGRect
    var animatableData: AnimatablePair<AnimatablePair<CGFloat, CGFloat>, AnimatablePair<CGFloat, CGFloat>> {
        get { AnimatablePair(AnimatablePair(hole.minX, hole.minY), AnimatablePair(hole.width, hole.height)) }
        set { hole = CGRect(x: newValue.first.first, y: newValue.first.second, width: newValue.second.first, height: newValue.second.second) }
    }
    func path(in rect: CGRect) -> Path {
        var path = Path(rect)
        if hole.width > 0, hole.height > 0 { path.addRoundedRect(in: hole, cornerSize: CGSize(width: 8, height: 8), style: .continuous) }
        return path
    }
}

// MARK: - Pages

/// The first launch's welcome and colours, the guides at a glance and the tour's last page, centred over the window.
private struct TutorialPages: View {
    @Bindable var store: StudyStore
    let size: CGSize
    @State private var center = TutorialCenter.shared
    @Environment(\.theme) private var theme

    var body: some View {
        let width: CGFloat = switch center.screen {
        case .finish: 520
        case .home: 680
        default: 720
        }
        Group {
            switch center.screen {
            case .welcome: TutorialWelcomePage(store: store)
            case .look: TutorialLookPage(store: store)
            case .home: TutorialHomePage(store: store)
            case .finish, .step: TutorialFinishPage(store: store)
            }
        }
        .id(center.screen)
        .transition(TutorialTransition.page)
        .frame(width: min(width, size.width - 48))
        // The surface hugs the page; the limit only keeps a tall page (one that scrolls) inside the window.
        .tutorialSurface(theme)
        .frame(maxHeight: size.height - 48)
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
        .accessibilityLabel("Lemma Tour")
    }
}

// MARK: - Pill

/// While the reader tries something, the tour waits here.
private struct TutorialPill: View {
    @Bindable var store: StudyStore
    @State private var center = TutorialCenter.shared
    @Environment(\.theme) private var theme

    var body: some View {
        HStack(spacing: 10) {
            TutorialAppIcon(size: 20)
            VStack(alignment: .leading, spacing: 0) {
                Text(center.isTour || center.screen != .step ? "Lemma Tour" : center.guide.title).font(.system(size: 12, weight: .semibold)).foregroundStyle(theme.tourText)
                Text(status).font(.system(size: 11)).foregroundStyle(theme.tourSecondary).lineLimit(1)
            }
            .frame(maxWidth: 300, alignment: .leading)
            Button { center.resume() } label: { Text("Resume") }
                .buttonStyle(TutorialButtonStyle(kind: .primary))
                .help("Back to the tour")
            TutorialCloseButton(help: "Close the tour") { center.close() }
        }
        .padding(.leading, 8).padding(.trailing, 8).padding(.vertical, 7)
        .background(Capsule().fill(theme.tourSurface).shadow(color: theme.tourShadow, radius: 16, y: 8))
        .overlay(Capsule().strokeBorder(theme.tourBorder, lineWidth: 1))
        .fixedSize()
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Lemma Tour, paused")
    }

    private var status: String {
        if let trying = center.trying { return "Trying: \(trying)" }
        return center.screen == .step ? "Paused on “\(center.step.title)”" : "Paused"
    }
}
