import SwiftUI
import AppKit
import LemmaCore

/// What needs attention in a book, as an editor's Problems panel lists errors and warnings: steps of a derivation
/// that fail (errors), passages marked “?” (warnings), exercises attempted but not solved and notes due (information).
struct ProblemItem: Identifiable {
    enum Severity: Int { case error, warning, info }
    let id: String
    let severity: Severity
    let title: String
    let detail: String
    let location: String
    let open: @MainActor () -> Void
}

@MainActor
extension StudyStore {
    var problemItems: [ProblemItem] {
        var items: [ProblemItem] = []
        for (derivation, line) in derivationProblems {
            items.append(ProblemItem(id: "derivation-\(derivation.id)-\(line.line)-\(line.range.location)", severity: .error, title: line.message,
                                     detail: line.detail ?? "", location: "\(derivation.title) · line \(line.line + 1)") { [self] in
                openDerivation(derivation.id)
                derivationFocus = (derivation.id, line.line, UUID())
            })
        }
        for mark in openMarks {
            let quote = mark.anchor.quote.split(whereSeparator: \.isWhitespace).joined(separator: " ")
            items.append(ProblemItem(id: "mark-\(mark.id)", severity: .warning, title: quote.isEmpty ? "A passage you did not follow" : "“\(String(quote.prefix(90)))”",
                                     detail: "Marked “?” · write your question or ask about it", location: shortPageText(mark.anchor.pageIndex)) { [self] in
                reader.go(to: mark.anchor)
                reader.flash(mark.anchor.region.rect, onPage: mark.anchor.pageIndex)
            })
        }
        for exercise in (workspace?.exercises ?? []).filter({ $0.status == .attempted }) {
            let key = ReferenceKey(kind: .exercise, number: exercise.number)
            let page = references?.knownTarget(key).map { shortPageText($0.pageIndex) } ?? ""
            items.append(ProblemItem(id: "exercise-\(exercise.number)", severity: .info, title: "Exercise \(exercise.number) attempted, not solved",
                                     detail: "Attempted \(exercise.updatedAt.formatted(date: .abbreviated, time: .omitted))", location: page) { [self] in goToKey(key) })
        }
        for note in (workspace?.notes ?? []).filter({ $0.isDue() }) {
            items.append(ProblemItem(id: "due-\(note.id)", severity: .info, title: "Due for recall: \(note.title)", detail: note.kind.label,
                                     location: shortPageText(note.anchor.pageIndex)) { [self] in
                selectNote(note.id); revealStudy(); studySection = .review
            })
        }
        return items
    }

    var problemCounts: (errors: Int, warnings: Int, infos: Int) {
        let derivations = derivationProblems.count
        let marks = openMarks.count
        let exercises = (workspace?.exercises ?? []).filter { $0.status == .attempted }.count
        let due = (workspace?.notes ?? []).filter { $0.isDue() }.count
        return (derivations, marks, exercises + due)
    }

    func showProblems() {
        if focusMode { toggleFocus() }
        checkAllDerivations()
        panelTab = .problems; showPanel = true
    }
}

struct ProblemsPanel: View {
    @Bindable var store: StudyStore
    @State private var collapsed: Set<Int> = []

    var body: some View {
        let items = store.problemItems
        if items.isEmpty {
            PaneEmptyState(symbol: "checkmark.seal", title: "No problems",
                           message: "Failing steps of your derivations, passages marked “?”, exercises in progress and notes due for recall appear here.")
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach([ProblemItem.Severity.error, .warning, .info], id: \.rawValue) { severity in
                        let group = items.filter { $0.severity == severity }
                        if !group.isEmpty {
                            groupHeader(severity, count: group.count)
                            if !collapsed.contains(severity.rawValue) {
                                ForEach(group) { item in row(item) }
                            }
                        }
                    }
                }
                .padding(.vertical, 4)
            }
            .onAppear { store.checkAllDerivations() }
        }
    }

    private func groupHeader(_ severity: ProblemItem.Severity, count: Int) -> some View {
        Button {
            if collapsed.contains(severity.rawValue) { collapsed.remove(severity.rawValue) } else { collapsed.insert(severity.rawValue) }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "chevron.right").font(.system(size: 8.5, weight: .bold))
                    .rotationEffect(.degrees(collapsed.contains(severity.rawValue) ? 0 : 90))
                ProblemIcon(severity: severity)
                Text(title(severity)).font(.system(size: 11, weight: .semibold))
                Text("\(count)").font(.system(size: 10, weight: .semibold).monospacedDigit())
                    .padding(.horizontal, 5).background(Color.primary.opacity(0.08), in: Capsule())
                Spacer()
            }
            .padding(.horizontal, 10).frame(height: 22).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func title(_ severity: ProblemItem.Severity) -> String {
        switch severity {
        case .error: "Failing steps"
        case .warning: "Passages marked “?”"
        case .info: "In progress"
        }
    }

    private func row(_ item: ProblemItem) -> some View {
        Button { item.open() } label: {
            HStack(alignment: .firstTextBaseline, spacing: 7) {
                ProblemIcon(severity: item.severity).frame(width: 14)
                VStack(alignment: .leading, spacing: 1) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(item.title).font(.system(size: 11.5)).lineLimit(1)
                        Text(item.location).font(.system(size: 10.5).monospacedDigit()).foregroundStyle(.tertiary).lineLimit(1)
                    }
                    if !item.detail.isEmpty { Text(item.detail).font(.system(size: 10.5).monospaced()).foregroundStyle(.secondary).lineLimit(1) }
                }
                Spacer(minLength: 0)
            }
            .padding(.leading, 30).padding(.trailing, 10).padding(.vertical, 3)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(item.detail.isEmpty ? item.title : "\(item.title)\n\(item.detail)")
    }
}

struct ProblemIcon: View {
    let severity: ProblemItem.Severity
    var body: some View {
        switch severity {
        case .error: Image(systemName: "xmark.circle.fill").foregroundStyle(Color.red).font(.system(size: 11))
        case .warning: Image(systemName: "questionmark.circle.fill").foregroundStyle(Color.orange).font(.system(size: 11))
        case .info: Image(systemName: "info.circle.fill").foregroundStyle(Color.blue).font(.system(size: 11))
        }
    }
}
