import SwiftUI
import AppKit
import LemmaCore

/// A recall test: a note in Review, or a statement of the book that could become one.
struct RecallTest: Identifiable {
    enum Status { case passed, failed, due, scheduled, unset
        var icon: String {
            switch self { case .passed: "pass-filled"; case .failed: "error"; case .due: "history"; case .scheduled: "pass"; case .unset: "circle-large-outline" }
        }
        var color: TC {
            switch self { case .passed, .scheduled: .testingIconPassed; case .failed: .testingIconFailed; case .due: .testingIconQueued; case .unset: .testingIconUnset }
        }
        var label: String {
            switch self { case .passed: "Passed"; case .failed: "Failed"; case .due: "Due"; case .scheduled: "Passed, scheduled"; case .unset: "Not tested" }
        }
    }
    let id: String
    let title: String
    let detail: String
    let chapter: String
    let status: Status
    let note: StudyNote?
    let key: ReferenceKey?
    let pageIndex: Int
}

@MainActor
extension StudyStore {
    /// Statements of the book and notes in Review, as tests grouped by chapter.
    func recallTests() -> [RecallTest] {
        guard let workspace else { return [] }
        var tests: [RecallTest] = []
        var used = Set<UUID>()
        let reviewNotes = workspace.notes.filter(\.isInReview)
        func status(_ note: StudyNote?) -> RecallTest.Status {
            guard let note, let review = note.review else { return .unset }
            if note.isDue() { return review.lastGrade == .again ? .failed : review.lastGrade == nil ? .due : .due }
            switch review.lastGrade {
            case .again?: return .failed
            case .hard?, .good?, .easy?: return .scheduled
            case nil: return .due
            }
        }
        func chapter(of pageIndex: Int) -> String {
            outline.last { ($0.pageIndex ?? .max) <= pageIndex }?.title ?? "Notes"
        }
        if let statements = analysis?.structure.statements {
            for statement in statements where Self.isRecallable(statement.key) {
                let note = reviewNotes.first { Self.question($0.question, isAbout: statement.key.title) }
                if let note { used.insert(note.id) }
                let page = analysis?.target(for: statement.key)?.pageIndex ?? statement.start.pageIndex
                tests.append(RecallTest(id: "statement-\(statement.key.title)", title: statement.key.title, detail: statement.title ?? "",
                                        chapter: chapter(of: page), status: status(note), note: note, key: statement.key, pageIndex: page))
            }
        }
        for note in reviewNotes where !used.contains(note.id) {
            tests.append(RecallTest(id: "note-\(note.id)", title: note.title, detail: note.kind.label, chapter: chapter(of: note.anchor.pageIndex),
                                    status: status(note), note: note, key: nil, pageIndex: note.anchor.pageIndex))
        }
        return tests
    }

    /// Definitions and results worth recalling; examples, remarks and exercises are not tests.
    nonisolated static func isRecallable(_ key: ReferenceKey) -> Bool {
        let recallable: Set<String> = ["Definition", "Theorem", "Lemma", "Proposition", "Corollary", "Claim", "Fact", "Principle", "Law", "Axiom", "Property"]
        return key.kind == .theorem && recallable.contains(key.name ?? "Theorem")
    }

    /// Whether a recall card's question is about the statement titled `title`: “Theorem 2.1” or “Theorem 2.1 (Name)”,
    /// not “Theorem 2.10”.
    nonisolated static func question(_ question: String, isAbout title: String) -> Bool {
        guard question.hasPrefix(title) else { return false }
        let rest = question.dropFirst(title.count)
        guard let next = rest.first else { return true }
        return !next.isNumber && !next.isLetter && next != "."
            || (next == "." && !(rest.dropFirst().first?.isNumber ?? false))
    }

    /// Opens Review on the notes that are due.
    func runDueTests() {
        revealStudy(); studySection = .review
        if reviewNotes.isEmpty { notify("No tests are due. Add statements from the Testing view or the Results view.", source: "Testing") }
    }

    /// Adds the current chapter's definitions and results to Review, then runs the due ones.
    func runChapterTests() {
        guard let structure = analysis?.structure else { notify("Lemma is still reading the book.", source: "Testing"); return }
        let chapter = breadcrumb().first
        let start = chapter?.pageIndex ?? 0
        let next = outline.first { ($0.pageIndex ?? -1) > start }?.pageIndex ?? Int.max
        let keys = structure.statements.filter { statement in
            let page = analysis?.target(for: statement.key)?.pageIndex ?? statement.start.pageIndex
            return Self.isRecallable(statement.key) && page >= start && page < next
        }.map(\.key)
        guard !keys.isEmpty else { notify("No numbered definitions or results in this chapter.", source: "Testing"); return }
        addStatementsToReview(keys)
        runDueTests()
    }

    /// Runs one test: its note in Review, or a new recall note for the statement.
    func runTest(_ test: RecallTest) {
        if let note = test.note {
            if !note.isDue() { updateNote(id: note.id) { $0.review?.dueAt = .now } }
            selectedNoteID = note.id
        } else if let key = test.key {
            addStatementToReview(key)
        }
        revealStudy(); studySection = .review
        WalkthroughStep.markDone(.test)
    }
}

/// VS Code's Testing view for recall: tests by chapter with their last result, a summary and a filter.
struct TestingSidebar: View {
    @Bindable var store: StudyStore
    @Environment(\.theme) private var theme
    @State private var filter = ""
    @State private var collapsed: Set<String> = []

    var body: some View {
        if store.workspace == nil {
            VSWelcomeView(message: "Open a book to test what you remember of its definitions and results.") { EmptyView() }
        } else {
            let tests = store.recallTests().filter { test in
                if filter.isEmpty { return true }
                if filter.hasPrefix("@") {
                    switch filter.dropFirst().lowercased() {
                    case "failed": return test.status == .failed
                    case "due": return test.status == .due || test.status == .failed
                    case "passed": return test.status == .passed || test.status == .scheduled
                    case "untested": return test.status == .unset
                    default: return true
                    }
                }
                return "\(test.title) \(test.detail)".localizedCaseInsensitiveContains(filter)
            }
            VStack(spacing: 0) {
                VSTextField(placeholder: "Filter (e.g. text, @failed, @due, @untested)", text: $filter, icon: "filter").padding(.horizontal, 10).padding(.vertical, 6)
                summary(tests)
                if tests.isEmpty {
                    VSWelcomeView(message: store.workspace == nil ? "Open a book: its numbered definitions and results become tests."
                                  : store.analysis?.analysis == nil ? "Lemma is still reading the book; its numbered definitions and results appear here as tests."
                                  : "This book numbers no definitions or theorems that Lemma can turn into tests. Add a note to Review (from a passage you want to remember) and it appears here.") { EmptyView() }
                } else {
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(groups(tests), id: \.chapter) { group in
                                VSRow(action: { toggle(group.chapter) }) {
                                    VSTwistie(expandable: true, expanded: !collapsed.contains(group.chapter)) { toggle(group.chapter) }
                                    Codicon(groupStatus(group.tests).icon, size: 16).foregroundStyle(theme[groupStatus(group.tests).color]).padding(.trailing, 6)
                                    Text(group.chapter).font(.ui(13)).lineLimit(1)
                                    Spacer(minLength: 4)
                                    Text("\(group.tests.filter { $0.status == .passed || $0.status == .scheduled }.count)/\(group.tests.count)")
                                        .font(.ui(12)).monospacedDigit().foregroundStyle(theme[.descriptionForeground])
                                }
                                if !collapsed.contains(group.chapter) {
                                    ForEach(group.tests) { test in TestRow(store: store, test: test) }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private func toggle(_ chapter: String) { if collapsed.contains(chapter) { collapsed.remove(chapter) } else { collapsed.insert(chapter) } }

    private func summary(_ tests: [RecallTest]) -> some View {
        let passed = tests.filter { $0.status == .passed || $0.status == .scheduled }.count
        let failed = tests.filter { $0.status == .failed }.count
        let due = tests.filter { $0.status == .due }.count
        return HStack(spacing: 10) {
            Label("\(passed)", systemImage: "checkmark.circle.fill").foregroundStyle(theme[.testingIconPassed])
            Label("\(failed)", systemImage: "xmark.circle.fill").foregroundStyle(theme[.testingIconFailed])
            Label("\(due)", systemImage: "clock").foregroundStyle(theme[.testingIconQueued])
            Spacer()
            Text("\(passed)/\(tests.count) passed").foregroundStyle(theme[.descriptionForeground])
        }
        .font(.ui(12)).monospacedDigit()
        .padding(.horizontal, 12).frame(height: 22)
    }

    private func groups(_ tests: [RecallTest]) -> [(chapter: String, tests: [RecallTest])] {
        var result: [(String, [RecallTest])] = []
        for test in tests.sorted(by: { $0.pageIndex < $1.pageIndex }) {
            if let index = result.firstIndex(where: { $0.0 == test.chapter }) { result[index].1.append(test) } else { result.append((test.chapter, [test])) }
        }
        return result
    }

    private func groupStatus(_ tests: [RecallTest]) -> RecallTest.Status {
        if tests.contains(where: { $0.status == .failed }) { return .failed }
        if tests.contains(where: { $0.status == .due }) { return .due }
        if tests.allSatisfy({ $0.status == .passed || $0.status == .scheduled }) { return .passed }
        return .unset
    }
}

private struct TestRow: View {
    @Bindable var store: StudyStore
    @Environment(\.theme) private var theme
    let test: RecallTest
    @State private var hovering = false
    var body: some View {
        VSRow(depth: 2, action: { store.reader.goToPage(test.pageIndex + 1) }) {
            Codicon(test.status.icon, size: 16).foregroundStyle(theme[test.status.color]).padding(.leading, 16).padding(.trailing, 6)
            if let key = test.key { KindBadge(key: key, size: 13).padding(.trailing, 4) }
            Text(test.title).font(.ui(13)).lineLimit(1)
            if !test.detail.isEmpty { Text(test.detail).font(.ui(12)).foregroundStyle(theme[.descriptionForeground]).lineLimit(1).padding(.leading, 4) }
            Spacer(minLength: 4)
            if hovering {
                VSIconButton(icon: "play", help: "Run Test: recall it now", size: 14, tint: theme[.testingRunAction]) { store.runTest(test) }
                VSIconButton(icon: "go-to-file", help: "Go to Source", size: 14) { store.reader.goToPage(test.pageIndex + 1) }
            } else {
                Text(store.shortPageText(test.pageIndex)).font(.ui(12)).monospacedDigit().foregroundStyle(theme[.descriptionForeground])
            }
        }
        .onHover { hovering = $0 }
        .help("\(test.title) · \(test.status.label)")
        .contextMenu {
            Button("Run Test") { store.runTest(test) }
            Button("Go to Source") { store.reader.goToPage(test.pageIndex + 1) }
            if let note = test.note { Button("Remove from Review") { store.removeFromReview(id: note.id) } }
        }
    }
}
