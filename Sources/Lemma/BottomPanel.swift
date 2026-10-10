import SwiftUI
import AppKit
import PDFKit
import LemmaCore

/// The panel under the page (⌘J): references to an object, questions sent to an assistant, and every note, as tables.
struct BottomPanel: View {
    @Bindable var store: StudyStore
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(spacing: 0) {
            if ThemeManager.shared.style == .classic {
            HStack(spacing: 2) {
                ForEach(PanelTab.allCases) { tab in
                    Button { store.panelTab = tab } label: {
                        HStack(spacing: 5) {
                            Text(tab.title).font(.system(size: 11.5, weight: .semibold))
                            if let count = count(for: tab), count > 0 {
                                Text("\(count)").font(.system(size: 9.5, weight: .semibold).monospacedDigit())
                                    .padding(.horizontal, 4).background(Color.primary.opacity(0.1), in: Capsule())
                            }
                        }
                        .foregroundStyle(store.panelTab == tab ? Color.primary : Color.secondary)
                        .padding(.horizontal, 8).frame(height: 30)
                        .overlay(alignment: .bottom) { if store.panelTab == tab { Rectangle().fill(Color.lemmaOlive).frame(height: 1.5).padding(.horizontal, 6) } }
                        .contentShape(Rectangle())
                    }.buttonStyle(.plain).accessibilityAddTraits(store.panelTab == tab ? .isSelected : [])
                }
                Spacer()
                Button { store.showPanel = false } label: { Image(systemName: "xmark").font(.system(size: 10, weight: .semibold)) }
                    .buttonStyle(.borderless).help("Hide the panel · ⌘J").accessibilityLabel("Hide panel").padding(.trailing, 10)
            }
            .padding(.leading, 6)
            Divider()
            } else {
            HStack(spacing: 0) {
                ForEach(PanelTab.allCases) { tab in PanelTitleTab(store: store, tab: tab, count: count(for: tab)) }
                Spacer(minLength: 8)
                HStack(spacing: 2) {
                    VSIconButton(icon: store.panelMaximized ? "chevron-down" : "chevron-up", help: store.panelMaximized ? "Restore Panel Size" : "Maximize Panel Size") {
                        store.panelMaximized.toggle()
                    }
                    VSIconButton(icon: "close", help: "Hide Panel (⌘J)") { store.showPanel = false; store.panelMaximized = false }
                }.padding(.trailing, 8)
            }
            .padding(.leading, 8)
            .frame(height: VSMetrics.panelTitleHeight)
            }
            Group {
                switch store.panelTab {
                case .problems: ProblemsPanel(store: store)
                case .references: ReferencesPanel(store: store)
                case .hierarchy: HierarchyPanel(store: store)
                case .questions: QuestionsPanel(store: store)
                case .notes: NotesPanel(store: store)
                case .console: ConsolePanel(store: store)
                }
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(ThemeManager.shared.style == .classic ? Color(nsColor: .controlBackgroundColor) : theme[.panelBackground])
        .vsBorder(.top, .panelBorder, theme: theme)
    }

    private func count(for tab: PanelTab) -> Int? {
        switch tab {
        case .problems: { let c = store.problemCounts; return c.errors + c.warnings + c.infos }()
        case .references, .hierarchy: nil
        case .questions: store.workspace?.notes.filter { $0.kind == .question }.count
        case .notes: store.workspace?.notes.count
        case .console: nil
        }
    }
}

/// A panel tab title, as VS Code's: uppercase 11 pt, a 1 pt accent line under the active one.
private struct PanelTitleTab: View {
    @Bindable var store: StudyStore
    @Environment(\.theme) private var theme
    let tab: PanelTab
    let count: Int?
    @State private var hovering = false
    var body: some View {
        let active = store.panelTab == tab
        HStack(spacing: 5) {
            Text(tab.title.uppercased()).font(.ui(11))
            if let count, count > 0 { VSBadge(count: count) }
        }
        .foregroundStyle(theme[active || hovering ? .panelTitleActiveForeground : .panelTitleInactiveForeground])
        .padding(.horizontal, 2)
        .frame(maxHeight: .infinity)
        .overlay(alignment: .bottom) { if active { Rectangle().fill(theme[.panelTitleActiveBorder]).frame(height: 1).padding(.bottom, 6) } }
        .padding(.horizontal, 8)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture { store.panelTab = tab }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(active ? [.isSelected, .isButton] : .isButton)
    }
}

/// One line of a references list: where, and the words around the mention.
struct ReferenceRow: Identifiable {
    let id: String
    let pageIndex: Int
    var range: NSRange?
    let before: String
    let match: String
    let after: String
    var isDefinition = false
}

struct ReferencesPanel: View {
    @Bindable var store: StudyStore

    var body: some View {
        if let query = store.referencesQuery {
            let rows = rows(for: query)
            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    Text(query.title).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                    Text(summary(rows, query: query)).font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("Clear") { store.referencesQuery = nil }.buttonStyle(.borderless).font(.caption)
                }.padding(.horizontal, 12).frame(height: 28)
                Divider()
                if rows.isEmpty {
                    Text("No references in the text layer. Search the book with ⌘F to find other spellings.").font(.callout).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading).padding(14)
                } else {
                    List {
                        ForEach(grouped(rows), id: \.title) { group in
                            Section {
                                ForEach(group.rows) { row in line(row) }
                            } header: {
                                Text(group.title).font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
                            }
                        }
                    }.listStyle(.inset).environment(\.defaultMinListRowHeight, 20)
                }
            }
        } else {
            PaneEmptyState(symbol: "arrow.triangle.branch", title: "Find all references",
                           message: "Right-click an equation, figure or citation and choose Find All References, or click a count under an equation label. Index terms list their pages here too.")
        }
    }

    private func summary(_ rows: [ReferenceRow], query: ReferencesQuery) -> String {
        let mentions = rows.filter { !$0.isDefinition }.count
        if case .indexEntry = query { return "\(Set(rows.map(\.pageIndex)).count) pages" }
        return "\(mentions) \(mentions == 1 ? "place" : "places") · \(Set(rows.filter { !$0.isDefinition }.map(\.pageIndex)).count) pages"
    }

    private func line(_ row: ReferenceRow) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(row.isDefinition ? "def." : store.shortPageText(row.pageIndex)).font(.system(size: 11).monospacedDigit())
                .foregroundStyle(row.isDefinition ? Color.lemmaOlive : Color.secondary).frame(width: 52, alignment: .trailing)
            (Text(row.before).foregroundColor(.secondary) + Text(row.match).fontWeight(.semibold).foregroundColor(.primary) + Text(row.after).foregroundColor(.secondary))
                .font(.system(size: 12)).lineLimit(1).truncationMode(.tail)
            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
        .onTapGesture { open(row, side: NSEvent.modifierFlags.contains(.option)) }
        .contextMenu {
            Button("Go There") { open(row, side: false) }
            Button("Open to the Side") { open(row, side: true) }
        }
        .help("\(store.pageText(row.pageIndex)) · PDF page \(row.pageIndex + 1) · ⌥-click opens it to the side")
    }

    private func open(_ row: ReferenceRow, side: Bool) {
        if side { store.openToSide(page: row.pageIndex, title: row.match); return }
        if let range = row.range { store.goToMention(pageIndex: row.pageIndex, range: range, expected: row.match) }
        else if case let .indexEntry(entry)? = store.referencesQuery { store.goToTerm(entry.term, onPage: row.pageIndex) }
        else if row.isDefinition, case let .object(key)? = store.referencesQuery, let target = store.references?.knownTarget(key) { store.goToReference(target) }
        else { store.reader.goToPage(row.pageIndex + 1) }
    }

    private func rows(for query: ReferencesQuery) -> [ReferenceRow] {
        guard let analysis = store.analysis else { return [] }
        switch query {
        case let .object(key):
            var rows: [ReferenceRow] = []
            if key.kind == .citation, let entry = analysis.bibliographyEntry(key) {
                rows.append(ReferenceRow(id: "definition", pageIndex: entry.pageIndex, before: "", match: entry.shortTitle, after: " · " + String(entry.text.prefix(140)), isDefinition: true))
                for (offset, record) in (analysis.analysis?.citations(of: entry.id) ?? []).enumerated() {
                    rows.append(ReferenceRow(id: "c\(offset)", pageIndex: record.pageIndex, range: record.range, before: record.before, match: record.text, after: record.after))
                }
                return rows
            }
            if let target = analysis.definitionsByKey[key] {
                rows.append(ReferenceRow(id: "definition", pageIndex: target.pageIndex, before: "", match: key.spokenTitle, after: " · defined here", isDefinition: true))
            }
            for (offset, record) in analysis.references(to: key).enumerated() {
                rows.append(ReferenceRow(id: "m\(offset)", pageIndex: record.pageIndex, range: record.range, before: record.before, match: record.match, after: record.after))
            }
            return rows
        case let .indexEntry(entry):
            var rows: [ReferenceRow] = []
            for span in entry.locators {
                guard let first = store.pageIndex(forPrinted: span.first) else { continue }
                let last = span.last.flatMap { store.pageIndex(forPrinted: $0) } ?? first
                for pageIndex in first...max(first, min(last, first + 24)) {
                    let text = store.document?.page(at: pageIndex)?.string ?? ""
                    if let range = StudyStore.occurrence(of: entry.term, in: text) {
                        let context = BookAnalyzer.contextAround(range, in: text as NSString)
                        rows.append(ReferenceRow(id: "\(span.text)-\(pageIndex)", pageIndex: pageIndex, range: range, before: context.before,
                                                 match: TextRepair.repaired((text as NSString).substring(with: range)), after: context.after))
                    } else {
                        rows.append(ReferenceRow(id: "\(span.text)-\(pageIndex)", pageIndex: pageIndex, before: "", match: "", after: "Page \(span.text) · the term is not in this page's text layer"))
                    }
                }
            }
            return rows
        }
    }

    private struct Group { let title: String; var rows: [ReferenceRow] }

    /// Rows under their chapter, in reading order, with the definition first.
    private func grouped(_ rows: [ReferenceRow]) -> [Group] {
        let chapters = store.outline.compactMap { entry in entry.pageIndex.map { (entry.title, $0) } }
        var groups: [Group] = []
        for row in rows.filter(\.isDefinition) + rows.filter({ !$0.isDefinition }).sorted(by: { $0.pageIndex < $1.pageIndex }) {
            let title = row.isDefinition ? "Definition" : (chapters.last { $0.1 <= row.pageIndex }?.0 ?? "Front matter")
            if groups.last?.title == title { groups[groups.count - 1].rows.append(row) } else { groups.append(Group(title: title, rows: [row])) }
        }
        return groups
    }
}

/// Every question note, with its answer's state: asked, waiting, or not yet asked.
struct QuestionsPanel: View {
    @Bindable var store: StudyStore
    @State private var selection: UUID?

    private var questions: [StudyNote] {
        (store.workspace?.notes ?? []).filter { $0.kind == .question }
            .sorted { ($0.explanation?.savedAt ?? $0.createdAt) > ($1.explanation?.savedAt ?? $1.createdAt) }
    }

    var body: some View {
        if questions.isEmpty {
            PaneEmptyState(symbol: "text.bubble", title: "No questions yet", message: "Select a passage and press ⌘K. Each question keeps its source, and the answer returns to it.")
        } else {
            Table(questions, selection: $selection) {
                TableColumn("") { note in
                    Image(systemName: note.pendingRequestID != nil ? "clock" : note.explanation != nil ? "checkmark.bubble" : "bubble.left")
                        .foregroundStyle(note.explanation != nil ? Color.lemmaOlive : Color.secondary)
                        .help(note.pendingRequestID != nil ? "Waiting for the assistant" : note.explanation != nil ? "Answered" : "Not asked yet")
                }.width(22)
                TableColumn("Question") { note in Text(note.title).lineLimit(1) }
                TableColumn("Page") { note in Text(store.shortPageText(note.anchor.pageIndex)).monospacedDigit().foregroundStyle(.secondary) }.width(56)
                TableColumn("Answer") { note in
                    Text(note.explanation.map { String($0.body.split(whereSeparator: \.isNewline).first ?? "") } ?? "-").lineLimit(1).foregroundStyle(.secondary)
                }
                TableColumn("Date") { note in
                    Text((note.explanation?.savedAt ?? note.createdAt).formatted(date: .abbreviated, time: .omitted)).foregroundStyle(.secondary)
                }.width(84)
            }
            .font(.system(size: 12))
            .contextMenu(forSelectionType: UUID.self) { ids in
                if let id = ids.first, let note = store.workspace?.notes.first(where: { $0.id == id }) {
                    Button("Open Note") { store.selectNote(id) }
                    Button("Go to Source") { store.reader.go(to: note.anchor) }
                    if let raw = note.explanation?.conversationURL, let url = URL(string: raw) { Button("Open Conversation") { store.questions.showConversation(url); store.showBrowserSetup = true }.disabled(store.questions.webBusy) }
                    Button("Ask Again…") { store.selectNote(id); store.showQuestion = true }.disabled(note.pendingRequestID != nil)
                }
            } primaryAction: { ids in
                if let id = ids.first, let note = store.workspace?.notes.first(where: { $0.id == id }) { store.selectNote(id); store.reader.go(to: note.anchor) }
            }
        }
    }
}

/// Every note of the book in one table, like an IDE's problems list.
struct NotesPanel: View {
    @Bindable var store: StudyStore
    @State private var selection: UUID?
    @State private var filter: NotesPanelFilter = .all

    enum NotesPanelFilter: String, CaseIterable, Identifiable {
        case all, open, revisit, due, glossary
        var id: String { rawValue }
        var title: String { switch self { case .all: "All"; case .open: "Open"; case .revisit: "Revisit"; case .due: "Due"; case .glossary: "Glossary" } }
        func includes(_ note: StudyNote) -> Bool {
            switch self {
            case .all: true
            case .open: note.state == .open
            case .revisit: note.state == .revisit
            case .due: note.isDue()
            case .glossary: note.kind.isGlossary
            }
        }
    }

    private var notes: [StudyNote] {
        (store.workspace?.notes ?? []).filter(filter.includes).sorted { $0.anchor.pageIndex == $1.anchor.pageIndex ? $0.createdAt < $1.createdAt : $0.anchor.pageIndex < $1.anchor.pageIndex }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Picker("Show", selection: $filter) { ForEach(NotesPanelFilter.allCases) { Text($0.title).tag($0) } }
                    .pickerStyle(.segmented).labelsHidden().controlSize(.small).fixedSize()
                Spacer()
                Text("\(notes.count) of \(store.workspace?.notes.count ?? 0)").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }.padding(.horizontal, 12).frame(height: 30)
            Divider()
            if notes.isEmpty {
                PaneEmptyState(symbol: "list.bullet.rectangle", title: "Nothing here", message: "Notes you add from a passage appear in reading order, with their state and next review.")
            } else {
                Table(notes, selection: $selection) {
                    TableColumn("") { note in Image(systemName: note.kind.symbol).foregroundStyle(.secondary) }.width(22)
                    TableColumn("Note") { note in Text(note.title).lineLimit(1) }
                    TableColumn("Page") { note in Text(store.shortPageText(note.anchor.pageIndex)).monospacedDigit().foregroundStyle(.secondary) }.width(56)
                    TableColumn("State") { note in Label(note.state.label, systemImage: note.state.symbol).foregroundStyle(.secondary) }.width(96)
                    TableColumn("Review") { note in
                        Text(reviewText(note)).foregroundStyle(note.isDue() ? Color.lemmaOlive : Color.secondary)
                    }.width(96)
                }
                .font(.system(size: 12))
                .contextMenu(forSelectionType: UUID.self) { ids in
                    if let id = ids.first, let note = store.workspace?.notes.first(where: { $0.id == id }) {
                        Button("Open Note") { store.selectNote(id) }
                        Button("Go to Source") { store.reader.go(to: note.anchor) }
                        Button("Open Source to the Side") { store.openToSide(page: note.anchor.pageIndex, title: note.title) }
                    }
                } primaryAction: { ids in
                    if let id = ids.first, let note = store.workspace?.notes.first(where: { $0.id == id }) { store.selectNote(id); store.reader.go(to: note.anchor) }
                }
            }
        }
    }

    private func reviewText(_ note: StudyNote) -> String {
        guard note.isInReview else { return "-" }
        if note.isDue() { return "Due" }
        return (note.reviewDueAt ?? .now).formatted(.relative(presentation: .numeric))
    }
}
