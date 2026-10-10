import SwiftUI
import AppKit
import LemmaCore

struct DefinitionLookupRequest: Identifiable, Equatable {
    let id = UUID()
    let workspaceID: String
    let query: String
    let pageIndex: Int
    let region: CGRect?
}

/// Present directly from PDFKit so the native source view supplies the anchor.
@MainActor
final class DefinitionLookupPopover: NSObject, NSPopoverDelegate {
    let popover = NSPopover()
    private weak var store: StudyStore?
    private let requestID: UUID

    init(store: StudyStore, request: DefinitionLookupRequest) {
        self.store = store; self.requestID = request.id
        super.init()
        popover.contentViewController = NSHostingController(rootView: DefinitionLookupPane(store: store, request: request).tint(.lemmaOlive))
        popover.behavior = .transient
        popover.animates = false
        popover.delegate = self
    }

    func popoverDidClose(_ notification: Notification) {
        if store?.definitionLookup?.id == requestID { store?.definitionLookup = nil }
    }
}

@MainActor
extension RegionPDFView {
    func presentDefinitionLookup(_ request: DefinitionLookupRequest, store: StudyStore) {
        guard window?.isVisible == true else { return }
        dismissDefinitionLookup()
        var anchor = CGRect(x: bounds.maxX - 24, y: isFlipped ? bounds.minY + 24 : bounds.maxY - 24, width: 1, height: 1)
        if let region = request.region, let page = document?.page(at: request.pageIndex) {
            let source = convert(region, from: page).intersection(bounds)
            if !source.isNull { anchor = source }
        }
        let presentation = DefinitionLookupPopover(store: store, request: request)
        definitionPopover = presentation
        presentation.popover.show(relativeTo: anchor, of: self, preferredEdge: .maxX)
    }

    func dismissDefinitionLookup() {
        if definitionPopover?.popover.isShown == true { definitionPopover?.popover.close() }
        definitionPopover = nil
    }
}

struct DefinitionLookupPane: View {
    @Bindable var store: StudyStore
    let request: DefinitionLookupRequest
    @State private var query: String
    @State private var inspectedID: UUID?
    /// Where the other books treat the query, found off the main thread a moment after the last keystroke.
    @State private var libraryHits: [LibraryGlossary.Hit] = []
    @FocusState private var queryFocused: Bool

    init(store: StudyStore, request: DefinitionLookupRequest) {
        self.store = store; self.request = request
        _query = State(initialValue: request.query)
    }

    /// What the query finds in this book, searched once per drawing (each section used to search again), over the
    /// book's terms and index folded once (`LibraryGlossary.prepared`).
    private struct Found {
        var notes: [DefinitionMatch] = []
        var symbols: [SymbolDefinition] = []
        var terms: [DefinedTerm] = []
        var index: [BookIndexSearch.Match] = []
    }

    private func find(_ query: String) -> Found {
        var found = Found()
        found.symbols = symbolMatches(query)
        guard store.workspace?.id == request.workspaceID else { return found }
        found.notes = DefinitionLookup.find(query, in: store.workspace?.notes ?? [], near: request.pageIndex)
        if let analysis = store.analysis?.analysis {
            let prepared = store.libraryGlossary.prepared(analysis, id: request.workspaceID)
            if !prepared.terms.isEmpty { found.terms = BookTermSearch.find(query, in: prepared.terms, limit: 4) }
            if !prepared.index.isEmpty { found.index = BookIndexSearch.find(query, in: prepared.index, limit: 6) }
        }
        return found
    }

    /// What the book says a symbol stands for, latest meaning first at the place it was looked up.
    private func symbolMatches(_ query: String) -> [SymbolDefinition] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count == 1, let character = trimmed.first, Notation.isSymbolCharacter(character),
              let notation = store.analysis?.notation else { return [] }
        let all = notation.meanings(of: trimmed)
        guard let current = notation.definition(of: trimmed, at: TextPoint(pageIndex: request.pageIndex, location: Int.max))?.definition else { return all }
        return [current] + all.filter { $0 != current }
    }

    private func bookNotation(_ symbolMatches: [SymbolDefinition]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Notation in the book").font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
            ForEach(Array(symbolMatches.prefix(5).enumerated()), id: \.offset) { offset, definition in
                Button { store.definitionLookup = nil; store.goToSymbolDefinition(definition) } label: {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(definition.symbol).font(.system(size: 15, design: .serif)).italic().frame(width: 20)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(definition.meaning).font(.callout.weight(offset == 0 ? .medium : .regular)).lineLimit(2).multilineTextAlignment(.leading)
                            Text((offset == 0 ? "In force here · " : "") + store.shortPageText(definition.pageIndex)).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                    }.padding(6).frame(maxWidth: .infinity, alignment: .leading)
                        .background(offset == 0 ? Color.lemmaOlive.opacity(0.08) : Color.clear, in: RoundedRectangle(cornerRadius: 6))
                }.buttonStyle(.plain).help("Go to the sentence that defines it")
            }
        }
    }

    var body: some View {
        let found = find(query)
        let matches = found.notes
        let inspectedNote = matches.first { $0.id == inspectedID }?.note ?? matches.first?.note
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Look up").font(.headline)
                    Text(found.terms.isEmpty && found.index.isEmpty && found.symbols.isEmpty ? "From your saved glossary" : "Where the book defines it, its index and your glossary").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button { store.definitionLookup = nil } label: { Image(systemName: "xmark") }
                    .buttonStyle(.borderless).accessibilityLabel("Close definition lookup").keyboardShortcut(.cancelAction)
            }
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Term or symbol", text: $query).textFieldStyle(.plain).focused($queryFocused)
                    .accessibilityLabel("Definition lookup query")
                if !query.isEmpty {
                    Button { query = "" } label: { Image(systemName: "xmark.circle.fill") }
                        .buttonStyle(.borderless).accessibilityLabel("Clear definition lookup")
                }
            }.padding(9).background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 6))

            if !found.symbols.isEmpty { bookNotation(found.symbols) }
            if !found.terms.isEmpty { bookTerms(found.terms) }
            if !found.index.isEmpty { bookIndex(found.index) }
            LibraryLookupSection(store: store, hits: libraryHits)
            if matches.isEmpty && (!found.index.isEmpty || !found.terms.isEmpty || !found.symbols.isEmpty) {
                Spacer(minLength: 0)
                Text("No entry in your glossary yet. Capture the defining passage and save it as a Definition to keep your own notes on it.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            } else if matches.isEmpty {
                Spacer(minLength: 0)
                VStack(alignment: .leading, spacing: 10) {
                    Text(query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Build your glossary" : "No saved entry for this name").font(.headline)
                    Text("Capture the defining passage and save a Definition, Notation, or Theorem. Add the term’s spelling under Lookup names to find it here.")
                        .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    Text("You can also edit the search above. Scanned pages need a typed term.").font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            } else {
                Text(matches.count == 1 ? "1 saved entry" : "\(matches.count) entries · check the local scope")
                    .font(.caption).foregroundStyle(.secondary)
                ScrollView {
                    VStack(spacing: 2) {
                        ForEach(matches) { match in
                            Button { inspectedID = match.id } label: {
                                HStack(alignment: .top, spacing: 8) {
                                    Image(systemName: match.note.kind.symbol).frame(width: 18).padding(.top, 2)
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(match.note.title).font(.callout.weight(.medium)).lineLimit(2)
                                        Text("PDF page \(match.note.anchor.pageIndex + 1)" + (match.note.scope.isEmpty ? "" : " · \(match.note.scope)"))
                                            .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                    }
                                    Spacer(minLength: 0)
                                }.multilineTextAlignment(.leading).padding(8).frame(maxWidth: .infinity, alignment: .leading)
                                    .background(match.id == inspectedNote?.id ? Color.lemmaOlive.opacity(0.1) : Color.clear, in: RoundedRectangle(cornerRadius: 6))
                            }.buttonStyle(.plain).accessibilityLabel("Inspect \(match.note.title), PDF page \(match.note.anchor.pageIndex + 1)")
                        }
                    }
                }.frame(height: min(CGFloat(matches.count) * 62, 132))
                Divider()
                if let note = inspectedNote {
                    ScrollView {
                        inspection(note).padding(.trailing, 4)
                    }.frame(maxHeight: .infinity)
                    Divider()
                    HStack {
                        Button("Open note") { store.definitionLookup = nil; store.openLinkedNote(note.id) }
                        Spacer()
                        Button("Go to source") { store.definitionLookup = nil; store.reader.go(to: note.anchor) }
                    }.font(.callout)
                }
            }
        }.padding(16).frame(width: 420, height: 560)
            .onAppear {
                queryFocused = true
                store.libraryGlossary.load(library: store.library, root: store.repository.root)
            }
            // The other books are searched off the main thread, a moment after the last keystroke (and again once
            // their analyses are read).
            .task(id: "\(store.libraryGlossary.books.count)|\(query)") {
                try? await Task.sleep(for: .milliseconds(120))
                guard !Task.isCancelled else { return }
                let books = Array(store.libraryGlossary.books.values), excluded = store.workspace?.id, query = query
                let worker = Task.detached(priority: .userInitiated) { LibraryGlossary.hits(for: query, in: books, excluding: excluded) }
                let hits = await withTaskCancellationHandler(operation: { await worker.value }, onCancel: { worker.cancel() })
                if !Task.isCancelled, hits != libraryHits { libraryHits = hits }
            }
    }

    /// Where the book introduces the term, found from its italic or bold type: click to go there, ⌥-click to open it to the side.
    private func bookTerms(_ termMatches: [DefinedTerm]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Defined in the book", systemImage: "text.book.closed").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            ForEach(termMatches) { term in
                Button {
                    let side = NSEvent.modifierFlags.contains(.option)
                    store.definitionLookup = nil
                    store.goToDefinedTerm(term, side: side)
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text(term.surface).italic().font(.callout.weight(.semibold)).lineLimit(1)
                            Text(store.shortPageText(term.pageIndex)).font(.system(size: 11).monospacedDigit()).foregroundStyle(Color.lemmaOlive)
                            if term.definitional { Text("definition").font(.system(size: 9.5, weight: .medium)).foregroundStyle(.secondary)
                                .padding(.horizontal, 4).background(Color.primary.opacity(0.07), in: Capsule()) }
                            Spacer(minLength: 0)
                        }
                        (Text(Self.leading(term.before)) + Text(term.surface).bold() + Text(Self.trailing(term.after)))
                            .font(.caption).foregroundStyle(.secondary).lineLimit(2).multilineTextAlignment(.leading)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Go to where the book introduces “\(term.surface)” (Back returns) · ⌥-click opens it to the side")
            }
        }
        .padding(10).frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.lemmaOlive.opacity(0.05), in: RoundedRectangle(cornerRadius: 7))
    }

    /// Context with one ellipsis where it was cut.
    static func leading(_ text: String) -> String {
        let trimmed = text.drop { $0 == "." || $0 == "…" || $0 == " " }
        return trimmed.isEmpty ? "" : "…" + trimmed
    }
    static func trailing(_ text: String) -> String {
        var trimmed = text
        while let last = trimmed.last, last == "." || last == "…" || last == " " { trimmed.removeLast() }
        return trimmed + "…"
    }

    /// The book's own index entries for the term, with their printed pages: click one to go there, ⌥-click to open it to the side.
    private func bookIndex(_ indexMatches: [BookIndexSearch.Match]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("In the book's index", systemImage: "character.book.closed").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            ForEach(indexMatches, id: \.entry.id) { match in
                let entry = match.entry
                VStack(alignment: .leading, spacing: 3) {
                    Button(entry.title) { store.definitionLookup = nil; store.openIndexEntry(entry) }
                        .buttonStyle(.plain).font(.callout.weight(match.rank <= 1 ? .semibold : .regular)).lineLimit(1)
                        .help("List every page in the panel below")
                    if !entry.see.isEmpty {
                        Text("see \(entry.see.joined(separator: "; "))").font(.caption).italic().foregroundStyle(.secondary)
                    }
                    FlowLayout(spacing: 4) {
                        ForEach(entry.locators.prefix(8), id: \.self) { span in
                            Button(span.text) {
                                guard let page = store.pageIndex(forPrinted: span.first) else { return }
                                let side = NSEvent.modifierFlags.contains(.option)
                                store.definitionLookup = nil
                                store.goToTerm(entry.term, onPage: page, inSplit: side)
                            }
                            .buttonStyle(.plain).font(.system(size: 11).monospacedDigit())
                            .padding(.horizontal, 5).frame(height: 18)
                            .background(Color.lemmaOlive.opacity(0.12), in: RoundedRectangle(cornerRadius: 4))
                            .foregroundStyle(Color.lemmaOlive)
                            .help("Printed page \(span.text) · ⌥-click opens it to the side")
                        }
                    }
                }
            }
        }
        .padding(10).frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.lemmaOlive.opacity(0.05), in: RoundedRectangle(cornerRadius: 7))
    }

    private func inspection(_ note: StudyNote) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Source · PDF page \(note.anchor.pageIndex + 1) · label \(note.anchor.pageLabel)")
                .font(.caption).foregroundStyle(.secondary)
            if let image = NSImage(contentsOf: store.repository.assetURL(workspaceID: request.workspaceID, name: note.anchor.imageName)) {
                Image(nsImage: image).resizable().scaledToFit().frame(maxWidth: .infinity, maxHeight: 110)
                    .padding(6).background(.white, in: RoundedRectangle(cornerRadius: 4)).accessibilityLabel("Saved definition source crop")
            }
            if !note.notation.isEmpty { text("Notation & dimensions", note.notation) }
            if !note.scope.isEmpty { text("Local scope", note.scope) }
            if !note.assumptions.isEmpty { text("Reader assumptions", note.assumptions) }
            if !note.body.isEmpty {
                Text("My understanding").font(.callout.weight(.medium))
                MathPreview(text: note.body)
            }
            if !note.anchor.quote.isEmpty {
                DisclosureGroup(note.sourceTextOrigin == .ocr ? "Recognized source text · OCR" : "Extracted source text") {
                    Text(note.anchor.quote).font(.callout).textSelection(.enabled).padding(.top, 4)
                }.font(.caption).foregroundStyle(.secondary)
            }
            if let explanation = note.explanation {
                DisclosureGroup("Saved explanation") { MathPreview(text: explanation.body).padding(.top, 4) }
                    .font(.callout.weight(.medium))
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    private func text(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption.weight(.medium)).foregroundStyle(.secondary)
            Text(value).font(.callout).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
        }
    }
}
