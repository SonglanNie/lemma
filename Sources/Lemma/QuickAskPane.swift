import SwiftUI
import AppKit
import PDFKit
import LemmaCore

/// Presented from the PDF view, anchored to the passage being asked about.
@MainActor
final class QuickAskPopover: NSObject, NSPopoverDelegate {
    let popover = NSPopover()
    private weak var store: StudyStore?
    private let requestID: UUID

    init(store: StudyStore, request: QuickAskRequest) {
        self.store = store; self.requestID = request.id
        super.init()
        popover.contentViewController = NSHostingController(rootView: QuickAskPane(store: store, request: request).tint(.lemmaOlive))
        popover.behavior = .semitransient
        popover.animates = false
        popover.delegate = self
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
        presentation.popover.show(relativeTo: anchor, of: self, preferredEdge: .maxX)
    }

    func dismissQuickAsk() {
        if quickAskPopover?.popover.isShown == true { quickAskPopover?.popover.close() }
        quickAskPopover = nil
    }
}

struct QuickAskPane: View {
    @Bindable var store: StudyStore
    let request: QuickAskRequest
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

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("Ask about this passage").font(.headline)
                Spacer()
                Text("PDF page \(request.pageIndex + 1)").font(.caption).foregroundStyle(.secondary)
            }
            if let preview {
                Image(nsImage: preview).resizable().scaledToFit().frame(maxWidth: .infinity, maxHeight: 84)
                    .padding(6).background(.white, in: RoundedRectangle(cornerRadius: 5)).accessibilityLabel("Selected source passage")
            }
            TextField("What don’t you understand? (optional)", text: $question, axis: .vertical)
                .lineLimit(2...5).textFieldStyle(.plain).font(.body).padding(9)
                .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
                .focused($questionFocused).onSubmit(send).accessibilityLabel("Your question")
            FlowLayout(spacing: 6) {
                ForEach(QuestionStyle.allCases) { item in
                    Button(item.shortLabel) { style = item }
                        .buttonStyle(ChipStyle(selected: item == style))
                        .help(item.instruction)
                        .accessibilityAddTraits(item == style ? .isSelected : [])
                }
            }
            if question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text("Without a question, Lemma asks: “\(style.defaultQuestion)”").font(.caption).foregroundStyle(.secondary)
            }
            Divider()
            contextList
            Picker("Assistant", selection: $providerName) {
                ForEach(QuestionProvider.allCases) { Text($0.label).tag($0.rawValue) }
            }.pickerStyle(.menu)
            if provider == .chatGPTWeb {
            Picker("Send with", selection: $modeName) {
                Text("Review in Lemma").tag(WebQuestionMode.draft.rawValue)
                Text("Ask and save").tag(WebQuestionMode.askAndSave.rawValue)
            }.pickerStyle(.segmented).labelsHidden()
            }
            Text(missingKey ? "Add your \(provider.company) API key in Assistants › Connections first. It is kept in your Keychain."
                 : provider == .chatGPTWeb && mode == .draft ? "Review and send in Lemma's ChatGPT panel. The answer is saved to this passage." : provider.sendingSummary)
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            HStack {
                Button("Full draft…") {
                    store.openFullDraft(request, question: question, style: style, candidates: candidates, selection: selection)
                }.help("Save the note and review the exact text before sending")
                Spacer()
                Button("Cancel") { store.quickAsk = nil }.keyboardShortcut(.cancelAction)
                Button("Ask", action: send).buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
                    .disabled(resolving || tooManyImages || missingKey)
            }
        }
        .padding(16).frame(width: 470)
        .task(id: request.id) { await load() }
    }

    @ViewBuilder private var contextList: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Context").font(.callout.weight(.medium))
                Spacer()
                Text("\(selection.imageCount) of \(ContextSelection.maximumImages) images").font(.caption.monospacedDigit())
                    .foregroundStyle(tooManyImages ? Color.red : Color.secondary)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 5) {
                    toggle("Passage text", detail: candidates.sourceText.isEmpty ? "none on this page" : "\(candidates.sourceText.count) characters", isOn: $selection.sourceText)
                        .disabled(candidates.sourceText.isEmpty)
                    if let section = candidates.section { toggle("Section", detail: section, isOn: $selection.section) }
                    ForEach(candidates.cited) { item in
                        toggle(item.target.key.spokenTitle, detail: "cited here · PDF page \(item.target.pageIndex + 1)", isOn: member(item.id, \.cited))
                    }
                    if resolving {
                        HStack(spacing: 6) { ProgressView().controlSize(.mini); Text("Finding cited equations and figures…") }.font(.caption).foregroundStyle(.secondary)
                    }
                    ForEach(candidates.glossary) { note in
                        toggle("Glossary: \(note.title)", detail: note.notation.isEmpty ? "PDF page \(note.anchor.pageIndex + 1)" : note.notation, isOn: member(note.id, \.glossary))
                    }
                    ForEach(candidates.pins) { pin in toggle("Pin: \(pin.label)", detail: "PDF page \(pin.anchor.pageIndex + 1)", isOn: member(pin.id, \.pins)) }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }.frame(maxHeight: 150)
            if tooManyImages { Text("Untick some images; one question carries at most \(ContextSelection.maximumImages).").font(.caption).foregroundStyle(.red) }
        }
    }

    private func toggle(_ title: String, detail: String, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            HStack(spacing: 6) {
                Text(title).font(.callout).lineLimit(1)
                Text(detail).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
            }
        }.toggleStyle(.checkbox)
    }

    private func member<ID: Hashable>(_ id: ID, _ path: WritableKeyPath<ContextSelection, Set<ID>>) -> Binding<Bool> {
        Binding(get: { selection[keyPath: path].contains(id) }, set: { value in
            if value { selection[keyPath: path].insert(id) } else { selection[keyPath: path].remove(id) }
        })
    }

    private func send() {
        guard !resolving, !tooManyImages, !missingKey else { return }
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
