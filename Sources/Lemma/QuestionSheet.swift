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
    @Environment(\.theme) private var theme
    @State private var themes = ThemeManager.shared
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
            WorkbenchSheetHeader(codicon: "comment-discussion", symbol: "text.bubble", title: "Prepare your question") {
                EmptyView()
            } actions: {
                Button("Assistants…") { store.showQuestion = false; DispatchQueue.main.async { store.showBrowserSetup = true } }.workbenchButton()
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Choose the help and the context, then review the exact draft.").font(.ui(13)).foregroundStyle(theme[.descriptionForeground])
                    HStack(alignment: .top, spacing: 16) {
                        if let note, let image = store.image(for: note.anchor) {
                            Image(nsImage: image).resizable().scaledToFit().frame(width: 210, height: 92).padding(6).background(.white, in: RoundedRectangle(cornerRadius: 4))
                        }
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Source A · PDF page \((note?.anchor.pageIndex ?? 0) + 1)").font(.ui(13, weight: .semibold))
                            HStack(spacing: 8) {
                                Text("Kind of help").font(.ui(13)).foregroundStyle(theme[.descriptionForeground])
                                if themes.style == .vscode {
                                    VSDropdown(options: QuestionStyle.allCases.map { ($0, $0.label) }, selection: $style).accessibilityLabel("Kind of help")
                                } else {
                                    Picker("Kind of help", selection: $style) {
                                        ForEach(QuestionStyle.allCases) { value in Text(value.label).tag(value) }
                                    }.pickerStyle(.menu).labelsHidden().fixedSize()
                                }
                            }
                            Text("\(selection.imageCount) of \(ContextSelection.maximumImages) images · only the ticked context and the draft below are shared.")
                                .font(.ui(12)).foregroundStyle(tooManyImages ? theme[.errorForeground] : theme[.descriptionForeground]).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    contextList
                    HStack {
                        Text("Draft").font(.ui(13, weight: .semibold))
                        Spacer()
                        if needsUpdate {
                            Text("Update the edited draft to apply your choices.").font(.ui(12)).foregroundStyle(theme[.descriptionForeground])
                            Button("Update Draft", action: regenerate).workbenchButton()
                        }
                    }
                    TextEditor(text: $prompt).font(.body).frame(height: 230).scrollContentBackground(.hidden)
                        .padding(6).workbenchInputBox().accessibilityLabel("Prepared question text")
                    HStack(spacing: 8) {
                        Button("Copy Text") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(prompt, forType: .string) }.workbenchButton()
                        Button("Copy Source Image", action: store.copySource).workbenchButton()
                    }
                }.padding(.horizontal, 24).padding(.vertical, 16)
            }
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Text("Assistant").font(.ui(13)).foregroundStyle(theme[.descriptionForeground])
                    if themes.style == .vscode {
                        VSDropdown(options: QuestionProvider.allCases.map { ($0.rawValue, $0.label) }, selection: $providerName).accessibilityLabel("Assistant")
                    } else {
                        Picker("Assistant", selection: $providerName) {
                            ForEach(QuestionProvider.allCases) { Text($0.label).tag($0.rawValue) }
                        }.pickerStyle(.menu).labelsHidden().fixedSize()
                    }
                    Spacer()
                    Button("Cancel") { store.showQuestion = false }.keyboardShortcut(.cancelAction).workbenchButton()
                    Group {
                        if provider == .chatGPTWeb { Button("Prepare in ChatGPT") { handoff(.draft) }.workbenchButton() }
                        Button("Ask and save") { handoff(.askAndSave) }.workbenchButton(.primary)
                    }.disabled(loading || prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || needsUpdate || tooManyImages || missingKey)
                }
                Text(sendingCaption).font(.ui(12)).foregroundStyle(missingKey ? theme[.editorWarningForeground] : theme[.descriptionForeground]).fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 24).padding(.vertical, 14)
            .background(theme[.sideBarBackground])
            .overlay(alignment: .top) { Rectangle().fill(theme.hairline(.sideBarBorder)).frame(height: 1) }
        }
        .frame(width: 760, height: Self.height)
        .foregroundStyle(theme[.foreground])
        .background(theme[.editorBackground])
            .task { store.questions.refreshKeys(); await load() }
            .onChange(of: style) { _, _ in refreshIfUnedited() }
            .onChange(of: selection) { _, _ in refreshIfUnedited() }
    }

    /// An API assistant without a saved key cannot answer; the sheet says so instead of failing after the click.
    private var missingKey: Bool { provider.kind == .api && store.questions.keyPresence[provider] == false }

    private var sendingCaption: String {
        if missingKey { return "Add your \(provider.company) API key in Assistants › Connections first. It is kept in your Keychain." }
        return switch provider.kind {
        case .web: "Prepare in ChatGPT puts the draft in Lemma's ChatGPT page for you to check and send; Ask and save sends it at once. Lemma saves the completed answer to this source note."
        case .cli: "Ask and save runs your installed \(provider.label) with this draft and the ticked images, and saves the answer to this source note. You can keep reading in Lemma."
        case .api: "Ask and save sends this draft and the ticked images to \(provider.company) with your API key, and saves the answer to this source note. You can keep reading in Lemma."
        }
    }

    private var contextList: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Context").font(.ui(13, weight: .semibold))
                if loading { ProgressView().controlSize(.small); Text("Finding cited equations and figures…").font(.ui(12)).foregroundStyle(theme[.descriptionForeground]) }
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
            Text(title).font(.ui(11.5, weight: .medium)).foregroundStyle(theme[.descriptionForeground])
            content()
        }
    }

    private func row(isOn: Binding<Bool>, title: String, detail: String, image: NSImage? = nil) -> some View {
        HStack(alignment: .center, spacing: 12) {
            if themes.style == .vscode {
                // VS Code's checkbox, the whole row toggling it, as the Ask widget's context rows do.
                Button { isOn.wrappedValue.toggle() } label: {
                    HStack(alignment: .center, spacing: 9) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 3).fill(theme[.checkboxBackground])
                            RoundedRectangle(cornerRadius: 3).stroke(theme[.checkboxBorder], lineWidth: 1)
                            if isOn.wrappedValue { Codicon("check", size: 13).foregroundStyle(theme[.checkboxForeground]) }
                        }.frame(width: 16, height: 16)
                        rowText(title, detail)
                    }.contentShape(Rectangle())
                }
                .buttonStyle(.plain).frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityLabel("\(title), \(detail)").accessibilityValue(isOn.wrappedValue ? "included" : "left out")
            } else {
                Toggle(isOn: isOn) { rowText(title, detail) }.toggleStyle(.checkbox).frame(maxWidth: .infinity, alignment: .leading)
            }
            if let image { Image(nsImage: image).resizable().scaledToFit().frame(width: 170, height: 46).background(.white) }
        }
    }

    private func rowText(_ title: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.ui(13, weight: .medium)).lineLimit(2)
            Text(detail).font(.ui(11.5)).foregroundStyle(theme[.descriptionForeground]).lineLimit(2)
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

