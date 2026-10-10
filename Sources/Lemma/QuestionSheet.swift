import SwiftUI
import AppKit
import LemmaCore

struct QuestionSheet: View {
    @Bindable var store: StudyStore
    @State private var prompt = ""
    @State private var generatedPrompt = ""
    @State private var style: QuestionStyle = .explanation
    @State private var candidates = QuestionContextCandidates()
    @State private var selection = ContextSelection()
    @State private var loading = true
    @State private var noteID: UUID?
    @AppStorage(LemmaPreferences.questionProvider) private var providerName = QuestionProvider.chatGPTWeb.rawValue
    private var provider: QuestionProvider { QuestionProvider(rawValue: providerName) ?? .chatGPTWeb }

    private var note: StudyNote? { store.workspace?.notes.first { $0.id == noteID } }
    private var composedPrompt: String {
        guard let note else { return "" }
        return store.composition(note: note, style: style, candidates: candidates, selection: selection).prompt
    }
    private var needsUpdate: Bool { !loading && generatedPrompt != composedPrompt }
    private var tooManyImages: Bool { selection.imageCount > ContextSelection.maximumImages }

    /// At most 800 points tall, and never taller than the screen: on a 13-inch display the body scrolls and the
    /// assistant choice and the send buttons stay visible.
    private static var height: CGFloat { min(800, max(460, (NSScreen.main?.visibleFrame.height ?? 900) - 70)) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Prepare your question").font(.title2.weight(.semibold))
                    Text("Choose the help and the context, then review the exact draft.").foregroundStyle(.secondary)
                }
                Spacer()
                Button("Assistants…") { store.showQuestion = false; DispatchQueue.main.async { store.showBrowserSetup = true } }
            }.padding(.horizontal, 26).padding(.top, 22).padding(.bottom, 12)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(alignment: .top, spacing: 16) {
                        if let note, let image = store.image(for: note.anchor) {
                            Image(nsImage: image).resizable().scaledToFit().frame(width: 210, height: 92).padding(6).background(.white, in: RoundedRectangle(cornerRadius: 5))
                        }
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Source A · PDF page \((note?.anchor.pageIndex ?? 0) + 1)").font(.headline)
                            Picker("Kind of help", selection: $style) {
                                ForEach(QuestionStyle.allCases) { value in Text(value.label).tag(value) }
                            }.pickerStyle(.menu).fixedSize()
                            Text("\(selection.imageCount) of \(ContextSelection.maximumImages) images · only the ticked context and the draft below are shared.")
                                .font(.caption).foregroundStyle(tooManyImages ? Color.red : Color.secondary).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    contextList
                    HStack {
                        Text("Draft").font(.headline)
                        Spacer()
                        if needsUpdate {
                            Text("Update the edited draft to apply your choices.").font(.caption).foregroundStyle(.secondary)
                            Button("Update draft", action: regenerate)
                        }
                    }
                    TextEditor(text: $prompt).font(.body).frame(height: 230)
                        .padding(6).background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 6)).accessibilityLabel("Prepared question text")
                    HStack {
                        Button("Copy text") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(prompt, forType: .string) }
                        Button("Copy source image", action: store.copySource)
                    }
                }.padding(.horizontal, 26).padding(.vertical, 14)
            }
            Divider()
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 10) {
                    Picker("Assistant", selection: $providerName) {
                        ForEach(QuestionProvider.allCases) { Text($0.label).tag($0.rawValue) }
                    }.pickerStyle(.menu).fixedSize()
                    Spacer()
                    Button("Cancel") { store.showQuestion = false }.keyboardShortcut(.cancelAction)
                    Group {
                        if provider == .chatGPTWeb { Button("Review in Lemma") { handoff(.draft) }.controlSize(.large) }
                        Button("Ask and save") { handoff(.askAndSave) }.buttonStyle(.borderedProminent).controlSize(.large)
                    }.disabled(loading || prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || needsUpdate || tooManyImages || missingKey)
                }
                Text(sendingCaption).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }.padding(.horizontal, 26).padding(.vertical, 14)
        }.frame(width: 760, height: Self.height)
            .task { store.questions.refreshKeys(); await load() }
            .onChange(of: style) { _, _ in refreshIfUnedited() }
            .onChange(of: selection) { _, _ in refreshIfUnedited() }
    }

    /// An API assistant without a saved key cannot answer; the sheet says so instead of failing after the click.
    private var missingKey: Bool { provider.kind == .api && store.questions.keyPresence[provider] == false }

    private var sendingCaption: String {
        if missingKey { return "Add your \(provider.company) API key in Assistants › Connections first. It is kept in your Keychain." }
        return switch provider.kind {
        case .web: "Review in Lemma prepares the draft in the embedded ChatGPT page for you to send; Ask and save sends it once. Lemma saves the completed answer to this source note."
        case .cli: "Ask and save runs your installed \(provider.label) with this draft and the ticked images, and saves the answer to this source note. You can keep reading in Lemma."
        case .api: "Ask and save sends this draft and the ticked images to \(provider.company) with your API key, and saves the answer to this source note. You can keep reading in Lemma."
        }
    }

    private var contextList: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Context").font(.headline)
                if loading { ProgressView().controlSize(.small); Text("Finding cited equations and figures…").font(.caption).foregroundStyle(.secondary) }
            }
            VStack(alignment: .leading, spacing: 10) {
                group("From the book") {
                    row(isOn: $selection.sourceText, title: "Text of the passage",
                        detail: candidates.sourceText.isEmpty ? "No text layer; the image carries the passage." : "\(candidates.sourceText.count) characters from the PDF text layer")
                        .disabled(candidates.sourceText.isEmpty)
                    if let section = candidates.section { row(isOn: $selection.section, title: "Section", detail: section) }
                    ForEach(candidates.cited) { item in
                        row(isOn: member(item.id, \.cited), title: item.target.key.spokenTitle,
                            detail: "Cited in the passage · PDF page \(item.target.pageIndex + 1)", image: NSImage(data: item.png))
                    }
                }
                if !candidates.glossary.isEmpty {
                    group("Your glossary · names, notation and scope only") {
                        ForEach(candidates.glossary) { entry in
                            row(isOn: member(entry.id, \.glossary), title: entry.title,
                                detail: [entry.notation, entry.scope].filter { !$0.isEmpty }.joined(separator: " · ").ifEmpty("PDF page \(entry.anchor.pageIndex + 1)"))
                        }
                    }
                }
                if !candidates.links.isEmpty {
                    group("Linked notes · their source crops") {
                        ForEach(candidates.links) { item in
                            row(isOn: member(item.id, \.links), title: "\(item.link.kind.label): \(item.note.title)",
                                detail: item.link.usage.isEmpty ? "PDF page \(item.note.anchor.pageIndex + 1)" : item.link.usage, image: store.image(for: item.note.anchor))
                        }
                    }
                }
                if !candidates.pins.isEmpty {
                    group("Pinned references") {
                        ForEach(candidates.pins) { pin in
                            row(isOn: member(pin.id, \.pins), title: pin.label, detail: "PDF page \(pin.anchor.pageIndex + 1)", image: store.image(for: pin.anchor))
                        }
                    }
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func group<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.caption.weight(.medium)).foregroundStyle(.secondary)
            content()
        }
    }

    private func row(isOn: Binding<Bool>, title: String, detail: String, image: NSImage? = nil) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Toggle(isOn: isOn) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.callout.weight(.medium)).lineLimit(2)
                    Text(detail).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                }
            }.toggleStyle(.checkbox).frame(maxWidth: .infinity, alignment: .leading)
            if let image { Image(nsImage: image).resizable().scaledToFit().frame(width: 170, height: 46).background(.white) }
        }
    }

    private func member<ID: Hashable>(_ id: ID, _ path: WritableKeyPath<ContextSelection, Set<ID>>) -> Binding<Bool> {
        Binding(get: { selection[keyPath: path].contains(id) }, set: { value in
            if value { selection[keyPath: path].insert(id) } else { selection[keyPath: path].remove(id) }
        })
    }

    private func load() async {
        let preset = store.questionPreset
        store.questionPreset = nil
        noteID = store.selectedNoteID
        guard let note else { loading = false; return }
        if let preset, preset.noteID == note.id {
            style = preset.style; candidates = preset.candidates; selection = preset.selection
            candidates.links = store.workspace?.outgoingLinks(from: note.id).compactMap { link in
                store.workspace?.notes.first { $0.id == link.targetNoteID }.map { LinkedContext(link: link, note: $0) }
            } ?? []
            // A prepared draft (the Lab's failing cell) is shown as written; Update draft still rebuilds it from the choices.
            if let draft = preset.prompt {
                loading = false
                generatedPrompt = composedPrompt; prompt = draft
                return
            }
        } else {
            candidates = QuestionContextCandidates(sourceText: note.anchor.quote.trimmingCharacters(in: .whitespacesAndNewlines), pins: store.workspace?.pins ?? [])
            selection = .defaults(for: candidates)
            regenerate()
            let full = await store.contextCandidates(pageIndex: note.anchor.pageIndex, region: note.anchor.region, quote: note.anchor.quote, noteID: note.id)
            let edited = prompt != generatedPrompt
            candidates = full
            let previousPins = selection.pins, previousText = selection.sourceText
            selection = .defaults(for: full)
            selection.pins = previousPins; selection.sourceText = previousText
            loading = false
            if !edited { regenerate() }
            return
        }
        loading = false
        regenerate()
    }

    private func regenerate() { generatedPrompt = composedPrompt; prompt = generatedPrompt }
    private func refreshIfUnedited() { if prompt == generatedPrompt { regenerate() } }
    private func handoff(_ mode: WebQuestionMode) {
        guard let note else { return }
        do {
            store.askWeb(mode: mode, content: try store.questionContent(note: note, style: style, candidates: candidates, selection: selection, prompt: prompt), noteID: note.id, provider: provider)
            store.showQuestion = false
        } catch { store.error = "Could not prepare the question: \(error.localizedDescription)" }
    }
}

private extension String {
    func ifEmpty(_ replacement: String) -> String { isEmpty ? replacement : self }
}

@MainActor
extension StudyStore {
    func image(for anchor: SourceAnchor) -> NSImage? {
        guard let workspace else { return nil }
        return NSImage(contentsOf: repository.assetURL(workspaceID: workspace.id, name: anchor.imageName))
    }
}

