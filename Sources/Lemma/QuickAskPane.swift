import SwiftUI
import AppKit
import PDFKit
import LemmaCore

/// Presented from the PDF view beside the passage: in the VS Code style an editor widget under the selection, drawn in
/// the theme's widget colours as VS Code's inline chat is; in the Classic style a popover.
@MainActor
final class QuickAskPopover: NSObject, NSPopoverDelegate {
    let popover = NSPopover()
    let panel = VSFloatingPanel()
    private weak var store: StudyStore?
    private let requestID: UUID

    var isShown: Bool { popover.isShown || panel.isShown }
    func close() {
        if popover.isShown { popover.close() }
        panel.close()
    }

    init(store: StudyStore, request: QuickAskRequest) {
        self.store = store; self.requestID = request.id
        super.init()
        popover.behavior = .semitransient
        popover.animates = false
        popover.delegate = self
        panel.onClose = { [weak self] in
            guard let self, self.store?.quickAsk?.id == self.requestID else { return }
            self.store?.quickAsk = nil
        }
    }

    func popoverDidClose(_ notification: Notification) {
        if store?.quickAsk?.id == requestID { store?.quickAsk = nil }
    }
}

@MainActor
extension RegionPDFView {
    func presentQuickAsk(_ request: QuickAskRequest, store: StudyStore) {
        guard window?.isVisible == true else { return }
        dismissQuickAsk(); dismissReferencePeek(); dismissDefinitionLookup()
        var anchor = CGRect(x: bounds.midX, y: bounds.midY, width: 1, height: 1)
        if let page = document?.page(at: request.pageIndex) {
            let rect = convert(request.region, from: page).intersection(bounds)
            if !rect.isNull, !rect.isEmpty { anchor = rect }
        }
        let presentation = QuickAskPopover(store: store, request: request)
        quickAskPopover = presentation
        if ThemeManager.shared.style == .vscode {
            // Under the passage, from its left edge, as VS Code's inline chat opens under its line.
            let width = min(QuickAskPane.width, max(360, bounds.width - 32))
            let line = CGRect(x: max(bounds.minX + 12, min(anchor.minX, bounds.maxX - width - 12)), y: anchor.minY, width: 1, height: anchor.height)
            let widget = QuickAskWidget(onHeight: { [weak presentation] in presentation?.panel.fit(height: $0) }) {
                QuickAskPane(store: store, request: request, widget: true, width: width) { [weak presentation] in presentation?.close() }
            }
            presentation.panel.show(widget, anchor: line, in: self, placement: .below, interactive: true, width: width,
                                    maxHeight: 700, takesKeyboard: true, resizable: true)
            return
        }
        // The view holds its presentation weakly: the popover keeps the view, so a strong reference would keep both alive.
        let controller = NSHostingController(rootView: QuickAskPane(store: store, request: request) { [weak presentation] in presentation?.close() }
            .environment(\.theme, ThemeManager.shared.colors).tint(.lemmaOlive))
        // The popover follows its content: the passage, then the context once found. With the size of the first layout
        // it kept, the preview was squeezed to a sliver and the context list hidden.
        controller.sizingOptions = [.preferredContentSize]
        presentation.popover.contentViewController = controller
        presentation.popover.show(relativeTo: anchor, of: self, preferredEdge: .maxX)
    }

    func dismissQuickAsk() {
        quickAskPopover?.panel.onClose = nil
        quickAskPopover?.close()
        quickAskPopover = nil
    }
}

/// The Ask widget's frame in the VS Code style: the theme's widget surface, its border and rounded corners. It reports
/// its height as the passage and the context arrive, so the floating panel can follow.
struct QuickAskWidget<Content: View>: View {
    @Environment(\.theme) private var theme
    var onHeight: (CGFloat) -> Void = { _ in }
    @ViewBuilder var content: Content
    var body: some View {
        content
            .fixedSize(horizontal: false, vertical: true)
            .background(GeometryReader { proxy in Color.clear.preference(key: QuickAskHeight.self, value: proxy.size.height) })
            .onPreferenceChange(QuickAskHeight.self) { height in onHeight(height) }
            .background(theme[.editorWidgetBackground])
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(theme.has(.editorWidgetBorder) ? theme[.editorWidgetBorder] : theme[.foreground].opacity(0.14), lineWidth: 1))
    }
}

private struct QuickAskHeight: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

/// Ask about a passage: the passage, an optional question and the kind of help, the context that goes with it (each
/// item can be left out), and where it goes. Return asks.
struct QuickAskPane: View {
    static let width: CGFloat = 480
    @Bindable var store: StudyStore
    let request: QuickAskRequest
    /// In the VS Code style's editor widget, which has its own close button; otherwise a popover.
    var widget = false
    var width = QuickAskPane.width
    var close: () -> Void = {}
    @Environment(\.theme) private var theme
    @State private var question = ""
    @State private var style: QuestionStyle = .explanation
    @State private var candidates = QuestionContextCandidates()
    @State private var selection = ContextSelection()
    @State private var resolving = true
    @State private var preview: NSImage?
    @AppStorage(LemmaPreferences.quickAskMode) private var modeName = LemmaPreferences.quickAskModeDefault.rawValue
    @AppStorage(LemmaPreferences.questionProvider) private var providerName = QuestionProvider.chatGPTWeb.rawValue
    @FocusState private var questionFocused: Bool

    private var provider: QuestionProvider { QuestionProvider(rawValue: providerName) ?? .chatGPTWeb }
    private var mode: WebQuestionMode { WebQuestionMode(rawValue: modeName) ?? LemmaPreferences.quickAskModeDefault }
    private var tooManyImages: Bool { selection.imageCount > ContextSelection.maximumImages }
    private var missingKey: Bool { provider.kind == .api && store.questions.keyPresence[provider] == false }
    private var chatGPTBusy: Bool { provider == .chatGPTWeb && store.questions.webBusy }
    private var canAsk: Bool { !resolving && !tooManyImages && !missingKey && !chatGPTBusy }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            passage
            VStack(alignment: .leading, spacing: 8) {
                questionField
                FlowLayout(spacing: 6) {
                    ForEach(QuestionStyle.allCases) { item in
                        Button(item.shortLabel) { style = item }
                            .buttonStyle(AskChipStyle(selected: item == style))
                            .help(item.instruction)
                            .accessibilityLabel("Kind of help: \(item.label)")
                            .accessibilityAddTraits(item == style ? .isSelected : [])
                    }
                }
                if question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text("Without a question, Lemma asks “\(style.defaultQuestion)”").font(.ui(11.5)).foregroundStyle(theme[.descriptionForeground])
                }
            }
            separator
            context
            separator
            footer
        }
        .padding(14)
        .frame(width: width, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
        .foregroundStyle(theme[.foreground])
        .task(id: request.id) { await load() }
        .onReceive(NotificationCenter.default.publisher(for: Self.qaNotification)) { performQA($0.userInfo as? [String: String] ?? [:]) }
    }

    static let qaNotification = Notification.Name("LemmaQuickAskQA")

    /// QA copies only (QAHooks posts the notification): fills the widget as a reader would, reports what it shows, and
    /// asks.
    private func performQA(_ info: [String: String]) {
        guard QAHooks.isAllowed else { return }
        if let value = info["question"] { question = value }
        if let value = info["style"].flatMap(QuestionStyle.init(rawValue:)) { style = value }
        if let value = info["provider"] { providerName = value }
        if let value = info["mode"] { modeName = value }
        switch info["untick"] {
        case "text": selection.sourceText = false
        case "section": selection.section = false
        case "cited": selection.cited = []
        default: break
        }
        if let name = info["state"], let directory = QAHooks.shared?.directory {
            let state: [String: Any] = [
                "question": question, "style": style.rawValue, "provider": provider.rawValue, "mode": mode.rawValue, "resolving": resolving,
                "preview": preview.map { [$0.size.width, $0.size.height] } ?? [], "sourceText": candidates.sourceText.count, "section": candidates.section ?? "",
                "cited": candidates.cited.map(\.target.key.spokenTitle), "glossary": candidates.glossary.map(\.title), "pins": candidates.pins.map(\.label),
                "images": selection.imageCount, "canAsk": canAsk, "summary": summary.text, "pageCaption": pageCaption,
                "prompt": store.workspace.map { _ in
                    store.composition(note: StudyNote(anchor: SourceAnchor(pageIndex: request.pageIndex, pageLabel: store.document?.page(at: request.pageIndex)?.label ?? String(request.pageIndex + 1),
                                                                         region: PageRegion(request.region), quote: request.quote, imageName: ""),
                                                      question: question.isEmpty ? style.defaultQuestion : question),
                                      style: style, candidates: candidates, selection: selection).prompt
                } ?? ""]
            try? JSONSerialization.data(withJSONObject: state, options: [.prettyPrinted, .sortedKeys]).write(to: directory.appendingPathComponent("\(name).json"))
        }
        if info["send"] == "1" { send() }
    }

    private var separator: some View { Rectangle().fill(theme[.foreground].opacity(0.1)).frame(height: 1) }

    private var header: some View {
        HStack(spacing: 7) {
            Codicon("comment-discussion", size: 15).foregroundStyle(theme[.iconForeground])
            Text("Ask about this passage").font(.ui(13, weight: .semibold))
            Spacer(minLength: 8)
            Text(pageCaption).font(.ui(11.5)).monospacedDigit().foregroundStyle(theme[.descriptionForeground])
            if widget { VSIconButton(icon: "close", help: "Close (Escape)", size: 14, action: close) }
        }
    }

    /// “p. 147 · PDF 157”, or “PDF page 157” for a book that prints no other numbers.
    private var pageCaption: String {
        let pdf = request.pageIndex + 1
        return store.printedLabel(for: request.pageIndex).map { "p. \($0) · PDF \(pdf)" } ?? "PDF page \(pdf)"
    }

    @ViewBuilder private var passage: some View {
        if let preview, preview.size.width > 0 {
            // The crop keeps its proportions at a height it cannot be squeezed below.
            let height = min(132, max(40, (width - 48) * preview.size.height / preview.size.width))
            Image(nsImage: preview).resizable().interpolation(.high).scaledToFit()
                .frame(maxWidth: .infinity).frame(height: height)
                .padding(8).background(Color.white, in: RoundedRectangle(cornerRadius: 4))
                .overlay(RoundedRectangle(cornerRadius: 4).stroke(theme[.foreground].opacity(0.12), lineWidth: 1))
                .accessibilityLabel("The passage you are asking about, sent as image 1")
        } else {
            RoundedRectangle(cornerRadius: 4).fill(theme[.foreground].opacity(0.06)).frame(height: 56)
        }
    }

    private var questionField: some View {
        TextField("", text: $question, prompt: Text("What don’t you understand? (optional)").foregroundColor(theme[.inputPlaceholderForeground]), axis: .vertical)
            .textFieldStyle(.plain).font(.ui(13)).lineLimit(2...6)
            .foregroundStyle(theme[.inputForeground])
            .padding(.horizontal, 9).padding(.vertical, 7)
            .background(theme[.inputBackground], in: RoundedRectangle(cornerRadius: 5))
            .overlay(RoundedRectangle(cornerRadius: 5).stroke(questionFocused ? theme[.focusBorder] : theme.border(.inputBorder).opacity(theme.has(.inputBorder) ? 1 : 0), lineWidth: 1))
            .focused($questionFocused).onSubmit(send)
            .accessibilityLabel("Your question")
    }

    // MARK: Context

    private var context: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text("SENT WITH YOUR QUESTION").font(.ui(10.5, weight: .semibold)).foregroundStyle(theme[.descriptionForeground])
                Spacer()
                Text("\(selection.imageCount) of \(ContextSelection.maximumImages) images").font(.ui(11)).monospacedDigit()
                    .foregroundStyle(tooManyImages ? theme[.errorForeground] : theme[.descriptionForeground])
            }
            // A long list scrolls rather than pushing the send buttons off screen.
            if contextRowCount > 7 {
                ScrollView { VStack(alignment: .leading, spacing: 0) { contextRows } }.frame(height: 7 * 26)
            } else {
                VStack(alignment: .leading, spacing: 0) { contextRows }
            }
        }
    }

    private var contextRowCount: Int {
        2 + (candidates.section == nil ? 0 : 1) + candidates.cited.count + (resolving ? 1 : 0) + candidates.glossary.count + candidates.pins.count
    }

    @ViewBuilder private var contextRows: some View {
        ContextRow(icon: "file-media", title: "The passage", detail: "image 1, always sent", isOn: .constant(true), fixed: true)
        ContextRow(icon: "quote", title: "Its text", detail: candidates.sourceText.isEmpty ? "no text layer on this page" : "\(candidates.sourceText.count) characters from the PDF",
                   isOn: $selection.sourceText).disabled(candidates.sourceText.isEmpty)
        if let section = candidates.section { ContextRow(icon: "list-tree", title: "Section", detail: section, isOn: $selection.section) }
        ForEach(candidates.cited) { item in
            ContextRow(icon: "symbol-numeric", title: item.target.key.spokenTitle, detail: "cited here · \(store.pageText(item.target.pageIndex))",
                       isOn: member(item.id, \.cited), thumbnail: NSImage(data: item.png))
        }
        if resolving {
            HStack(spacing: 6) { ProgressView().controlSize(.mini); Text("Finding the equations and figures it cites…") }
                .font(.ui(11.5)).foregroundStyle(theme[.descriptionForeground]).frame(height: 24)
        }
        ForEach(candidates.glossary) { note in
            ContextRow(icon: "book", title: "Glossary: \(note.title)", detail: note.notation.isEmpty ? "your entry, \(store.pageText(note.anchor.pageIndex))" : note.notation,
                       isOn: member(note.id, \.glossary))
        }
        ForEach(candidates.pins) { pin in
            ContextRow(icon: "pin", title: "Pin: \(pin.label)", detail: store.pageText(pin.anchor.pageIndex), isOn: member(pin.id, \.pins))
        }
    }

    private func member<ID: Hashable>(_ id: ID, _ path: WritableKeyPath<ContextSelection, Set<ID>>) -> Binding<Bool> {
        Binding(get: { selection[keyPath: path].contains(id) }, set: { value in
            if value { selection[keyPath: path].insert(id) } else { selection[keyPath: path].remove(id) }
        })
    }

    // MARK: Sending

    private var footer: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                if widget {
                    VSDropdown(options: QuestionProvider.allCases.map { ($0.rawValue, $0.label) }, selection: $providerName)
                        .help("The assistant that answers. Assistants › Connections sets each one up.")
                    if provider == .chatGPTWeb { AskModeToggle(mode: $modeName) }
                } else {
                    Picker("Assistant", selection: $providerName) {
                        ForEach(QuestionProvider.allCases) { Text($0.label).tag($0.rawValue) }
                    }
                    .pickerStyle(.menu).labelsHidden().fixedSize()
                    .help("The assistant that answers. Assistants › Connections sets each one up.")
                    if provider == .chatGPTWeb {
                        Picker("Sending", selection: $modeName) {
                            Text("Send now").tag(WebQuestionMode.askAndSave.rawValue)
                            Text("Review first").tag(WebQuestionMode.draft.rawValue)
                        }
                        .pickerStyle(.segmented).labelsHidden().fixedSize()
                        .help("Review first prepares the question in ChatGPT for you to check and send")
                    }
                }
                Spacer(minLength: 4)
                // Escape closes the popover as Cancel did (the widget closes on Escape by itself).
                if !widget { Button("Cancel", action: close).keyboardShortcut(.cancelAction).frame(width: 0, height: 0).opacity(0).accessibilityHidden(true) }
                askButton
            }
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(summary.text).font(.ui(11.5))
                    .foregroundStyle(summary.warning ? theme[.editorWarningForeground] : theme[.descriptionForeground])
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                Button("Full Draft…") {
                    store.openFullDraft(request, question: question, style: style, candidates: candidates, selection: selection)
                }
                .buttonStyle(.plain).font(.ui(12)).foregroundStyle(theme[.textLinkForeground]).fixedSize()
                .help("Save the note and edit the exact text before sending")
            }
        }
    }

    @ViewBuilder private var askButton: some View {
        let title = provider == .chatGPTWeb && mode == .draft ? "Prepare" : "Ask"
        if widget {
            Button(action: send) { Text(title).padding(.horizontal, 6) }
                .buttonStyle(.vsPrimary).keyboardShortcut(.defaultAction).disabled(!canAsk)
        } else {
            Button(title, action: send).buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction).disabled(!canAsk)
        }
    }

    /// Where the question goes and where its answer will be, or what stops it.
    private var summary: (text: String, warning: Bool) {
        if missingKey { return ("Add your \(provider.company) API key in Assistants › Connections first. It stays in your Keychain.", true) }
        if chatGPTBusy { return ("ChatGPT is answering another question. Wait for it, or choose another assistant.", true) }
        if tooManyImages { return ("Untick some images: one question carries at most \(ContextSelection.maximumImages).", true) }
        switch provider.kind {
        case .web: return (mode == .draft ? "Lemma prepares the question in its ChatGPT page for you to check and send. The answer is saved to this passage."
                                          : "Lemma sends the question in its ChatGPT page, with your account. The answer is saved to this passage.", false)
        case .cli: return ("Runs your installed \(provider.label) with its own sign-in. The answer is saved to this passage.", false)
        case .api: return ("Sends the question to \(provider.company) with your API key. The answer is saved to this passage.", false)
        }
    }

    private func send() {
        guard canAsk else { return }
        store.sendQuickAsk(request, question: question, style: style, candidates: candidates, selection: selection, mode: mode, provider: provider)
    }

    private func load() async {
        questionFocused = true
        store.questions.refreshKeys()
        if let page = store.document?.page(at: request.pageIndex),
           let data = try? PDFRegionRenderer.png(page: page, region: PageRegion(request.region), scale: 2) {
            preview = NSImage(data: data)
        }
        // Book material that is immediately available is offered first; citations follow once resolved.
        var initial = await store.contextCandidates(pageIndex: request.pageIndex, region: PageRegion(request.region), quote: "", noteID: nil)
        initial.sourceText = request.quote.trimmingCharacters(in: .whitespacesAndNewlines)
        initial.glossary = GlossaryMatcher.entries(mentionedIn: request.quote, from: store.workspace?.notes ?? [], near: request.pageIndex)
        candidates = initial
        selection = .defaults(for: initial)
        let full = await store.contextCandidates(pageIndex: request.pageIndex, region: PageRegion(request.region), quote: request.quote, noteID: nil)
        guard !Task.isCancelled else { return }
        let previous = selection
        candidates = full
        selection = .defaults(for: full)
        selection.sourceText = previous.sourceText; selection.section = previous.section
        selection.glossary = previous.glossary.intersection(Set(full.glossary.map(\.id)))
        selection.pins = previous.pins
        resolving = false
    }
}

/// One item of context: a checkbox, what it is and where it comes from, and its image when it is sent as one.
private struct ContextRow: View {
    @Environment(\.theme) private var theme
    @Environment(\.isEnabled) private var enabled
    let icon: String
    let title: String
    let detail: String
    @Binding var isOn: Bool
    var fixed = false
    var thumbnail: NSImage? = nil

    var body: some View {
        Button { if !fixed { isOn.toggle() } } label: {
            HStack(spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 3).fill(theme[.checkboxBackground])
                    RoundedRectangle(cornerRadius: 3).stroke(theme[.checkboxBorder], lineWidth: 1)
                    if isOn { Codicon("check", size: 12).foregroundStyle(theme[.checkboxForeground]) }
                }
                .frame(width: 15, height: 15).opacity(fixed ? 0.55 : 1)
                Codicon(icon, size: 13).foregroundStyle(theme[.descriptionForeground])
                Text(title).font(.ui(12.5)).lineLimit(1).layoutPriority(1)
                Text(detail).font(.ui(11.5)).foregroundStyle(theme[.descriptionForeground]).lineLimit(1).truncationMode(.middle)
                Spacer(minLength: 4)
                if let thumbnail {
                    Image(nsImage: thumbnail).resizable().interpolation(.high).scaledToFit().frame(maxWidth: 120, maxHeight: 20)
                        .padding(2).background(Color.white, in: RoundedRectangle(cornerRadius: 2))
                }
            }
            .frame(height: 26)
            .opacity(enabled ? 1 : 0.5)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(fixed ? "The passage itself is always sent" : isOn ? "Sent with the question: click to leave it out" : "Left out: click to send it")
        .accessibilityLabel("\(title), \(detail)")
        .accessibilityValue(isOn ? "included" : "left out")
        .accessibilityAddTraits(.isButton)
    }
}

/// Send now or Review first, for ChatGPT Web: two options in one rounded box, the chosen one filled, as VS Code's
/// toggles are drawn.
private struct AskModeToggle: View {
    @Binding var mode: String
    @Environment(\.theme) private var theme
    var body: some View {
        HStack(spacing: 0) {
            option("Send now", WebQuestionMode.askAndSave, help: "Lemma sends the question in its ChatGPT page")
            option("Review first", WebQuestionMode.draft, help: "Lemma prepares the question in its ChatGPT page; you check it and press Send")
        }
        .padding(2)
        .background(theme[.foreground].opacity(0.08), in: RoundedRectangle(cornerRadius: 5))
        .fixedSize()
    }

    private func option(_ title: String, _ value: WebQuestionMode, help: String) -> some View {
        let chosen = mode == value.rawValue
        return Button { mode = value.rawValue } label: {
            Text(title).font(.ui(12, weight: chosen ? .semibold : .regular))
                .foregroundStyle(chosen ? theme[.inputOptionActiveForeground] : theme[.descriptionForeground])
                .padding(.horizontal, 8).frame(height: 22)
                .background(chosen ? theme[.inputOptionActiveBackground] : .clear, in: RoundedRectangle(cornerRadius: 4))
                .overlay(RoundedRectangle(cornerRadius: 4).stroke(chosen ? theme.border(.inputOptionActiveBorder) : .clear, lineWidth: 1))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain).help(help)
        .accessibilityLabel(title).accessibilityAddTraits(chosen ? .isSelected : [])
    }
}

/// A help-style capsule in the theme's colours: the button colour when chosen, a faint fill otherwise.
struct AskChipStyle: ButtonStyle {
    let selected: Bool
    @Environment(\.theme) private var theme
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.ui(12, weight: selected ? .semibold : .regular))
            .padding(.horizontal, 10).frame(height: 24)
            .foregroundStyle(selected ? theme[.buttonForeground] : theme[.foreground])
            .background(selected ? theme[.buttonBackground] : theme[.foreground].opacity(configuration.isPressed ? 0.18 : 0.08), in: Capsule())
            .contentShape(Capsule())
    }
}

/// A selectable capsule for compact single-choice rows.
struct ChipStyle: ButtonStyle {
    let selected: Bool
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.callout)
            .padding(.horizontal, 10).padding(.vertical, 4)
            .foregroundStyle(selected ? Color.white : Color.primary)
            .background(selected ? Color.lemmaOlive : Color.secondary.opacity(configuration.isPressed ? 0.25 : 0.12), in: Capsule())
            .contentShape(Capsule())
    }
}

/// Lays out children in rows, wrapping when the width runs out.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(width: proposal.width ?? .infinity, subviews: subviews)
        let height = rows.map(\.height).reduce(0, +) + spacing * CGFloat(max(0, rows.count - 1))
        let width = rows.map(\.width).max() ?? 0
        return CGSize(width: proposal.width ?? width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in arrange(width: bounds.width, subviews: subviews) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private func arrange(width: CGFloat, subviews: Subviews) -> [(indices: [Int], width: CGFloat, height: CGFloat)] {
        var rows: [(indices: [Int], width: CGFloat, height: CGFloat)] = []
        var current: (indices: [Int], width: CGFloat, height: CGFloat) = ([], 0, 0)
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let needed = current.indices.isEmpty ? size.width : current.width + spacing + size.width
            if needed > width, !current.indices.isEmpty {
                rows.append(current); current = ([index], size.width, size.height)
            } else {
                current.indices.append(index); current.width = needed; current.height = max(current.height, size.height)
            }
        }
        if !current.indices.isEmpty { rows.append(current) }
        return rows
    }
}
