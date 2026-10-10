import SwiftUI
import AppKit
import PDFKit
import LemmaCore

/// First-page covers for the library, kept beside the workspaces (`Covers/<id>.png`). They are rendered off the main
/// thread by `CoverThumbnails`: a view asking for a cover not ready yet gets nil (its placeholder) and is redrawn when the
/// cover arrives, so tabs and lists never open a PDF while SwiftUI draws.
@MainActor
final class LibraryCovers {
    let root: URL

    init(root: URL) { self.root = root.appendingPathComponent("Covers", isDirectory: true) }

    func cover(for book: StudyWorkspace) -> NSImage? {
        CoverThumbnails.shared.image(for: book, folder: root.deletingLastPathComponent())
    }
}

struct BookCover: View {
    let image: NSImage?
    var width: CGFloat = 36
    var body: some View {
        Group {
            if let image {
                Image(nsImage: image).resizable().scaledToFit()
            } else {
                Image(systemName: "book.closed").font(.system(size: width * 0.45, weight: .light)).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity).background(Color.secondary.opacity(0.1))
            }
        }
        .frame(width: width, height: width * 4 / 3)
        .background(.white)
        .clipShape(RoundedRectangle(cornerRadius: 3))
        .overlay(RoundedRectangle(cornerRadius: 3).stroke(Color.secondary.opacity(0.3), lineWidth: 0.5))
        .shadow(color: .black.opacity(0.15), radius: 1.5, y: 1)
        .accessibilityHidden(true)
    }
}

/// Progress, notes and due recalls for one book.
struct BookSummary: View {
    let book: StudyWorkspace
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let progress = book.progress {
                // A thin bar in the book's own colour; the system progress view would take the macOS accent.
                Capsule().fill(Color.primary.opacity(0.12)).frame(width: 140, height: 4)
                    .overlay(alignment: .leading) { Capsule().fill(Color.lemmaOlive).frame(width: max(4, 140 * progress), height: 4) }
                    .accessibilityElement().accessibilityLabel("Reading position").accessibilityValue("\(Int(progress * 100)) percent")
            }
            HStack(spacing: 6) {
                Text(pageText).monospacedDigit()
                if let read = book.readFraction, read > 0 { Text("· \(max(1, Int((read * 100).rounded()))) % read").monospacedDigit() }
                if !book.labs.isEmpty { Text("· \(book.labs.count) \(book.labs.count == 1 ? "lab" : "labs")") }
                if !book.notes.isEmpty { Text("· \(book.notes.count) \(book.notes.count == 1 ? "note" : "notes")") }
                let due = book.notes.filter { $0.isDue() }.count
                if due > 0 { Text("· \(due) due").foregroundStyle(Color.lemmaOlive) }
            }.font(.caption).foregroundStyle(.secondary).lineLimit(1)
        }
    }
    private var pageText: String {
        if let count = book.pageCount { return "p. \(book.reading.pageIndex + 1) of \(count)" }
        return "p. \(book.reading.pageIndex + 1)"
    }
}

/// Shown in the editor when no book is open, like an editor's welcome page: start, recent books, and what Lemma can do.
struct LibraryHome: View {
    @Bindable var store: StudyStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 30) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 10) {
                        LemmaGlyph(size: 30).accessibilityHidden(true)
                        Text("Lemma").font(.system(size: 30, weight: .semibold))
                    }
                    Text("An IDE for reading mathematics: the book's references, index and citations become links, and your notes stay beside their source.")
                        .font(.title3).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true).frame(maxWidth: 620, alignment: .leading)
                }
                HStack(alignment: .top, spacing: 48) {
                    VStack(alignment: .leading, spacing: 28) {
                        section("Start") {
                            startRow("Open a PDF…", symbol: "folder", shortcut: "⌘O", action: store.choosePDF)
                            startRow("New research project", symbol: "folder.badge.plus", shortcut: nil) { store.newProject() }
                            startRow("Go to a book or command…", symbol: "magnifyingglass", shortcut: "⌘P") { store.showPalette(.goTo) }
                            startRow("Get a free textbook…", symbol: "square.grid.2x2", shortcut: nil) { store.reveal(.catalog) }
                            startRow("Open the sample book", symbol: "book", shortcut: nil) { store.openSampleBook() }
                            startRow("Watch library folders…", symbol: "folder.badge.gearshape", shortcut: nil) { store.showLibrarySources = true }
                            startRow("Search arXiv papers…", symbol: "doc.text.magnifyingglass", shortcut: nil) { store.catalogMode = .arxiv; store.reveal(.catalog) }
                            startRow("Keyboard shortcuts", symbol: "keyboard", shortcut: "⌘/") { store.showShortcuts = true }
                            startRow("Connect assistants…", symbol: "link", shortcut: nil) { store.showBrowserSetup = true }
                        }
                        section("Recent") {
                            if store.library.isEmpty {
                                Text("Books you open appear here with their reading position, notes and due recalls. Drop a PDF anywhere in this window.")
                                    .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                            } else {
                                ForEach(store.library.prefix(8)) { book in recentRow(book) }
                            }
                        }
                    }.frame(minWidth: 280, maxWidth: 380, alignment: .leading)
                    VStack(alignment: .leading, spacing: 28) {
                        TutorialPromoCard(store: store)
                        if !store.activeProjects.isEmpty {
                            section("Projects") {
                                ForEach(store.activeProjects.prefix(4)) { project in
                                    Button { store.openProject(project.id); store.reveal(.projects) } label: {
                                        VStack(alignment: .leading, spacing: 4) {
                                            Label(project.title, systemImage: "folder").font(.callout.weight(.medium))
                                            Text(project.question.isEmpty ? "\(project.bookIDs.count) books · \(project.passages.count) sources" : project.question)
                                                .font(.caption).foregroundStyle(.secondary).lineLimit(2)
                                        }.frame(maxWidth: .infinity, alignment: .leading)
                                    }.buttonStyle(.plain)
                                }
                            }
                        }
                        if let last = store.library.first { continueCard(last) }
                        readingCard
                        section("Walkthrough") {
                            tip("function", "Select a step you want to understand and choose Derive (⌥⌘E): write the missing steps one per line, and Lemma checks each one as you type: a ✗ with a counterexample, “off by a factor of 2”, or “solves line 3 for β”.")
                            tip("checkmark.seal", "Saved an assistant answer? “Check steps” opens its equations as a derivation, so its algebra is verified on this Mac.")
                            tip("list.number", "Line numbers sit beside the page as in an editor; click one to select its line, and type “64:12” in ⌘P to go there. ⌃⌘T turns the page to sepia or night.")
                            tip("doc.text.magnifyingglass", "In a citation's peek, Find the Paper looks the work up and opens its free PDF in a new tab.")
                            tip("checkmark.seal", "Results lists a book's definitions, theorems and lemmas. ⌥⌘[ folds every proof: read the statement, try the proof, then unfold it.")
                            tip("point.3.filled.connected.trianglepath.dotted", "⇧⌥⌘H shows what the statement you are reading uses and what uses it; ⌥⌘G maps the chapter, prerequisites on top.")
                            tip("text.line.first.and.arrowtriangle.forward", "⌥⌘R puts a ruler on one line: step through a proof with ↓ and ask “Why?” about the step you do not follow.")
                            tip("textformat.alt", "Rest the pointer on λ, X or β: Lemma says what the book defined it as, at that point of the book.")
                            tip("arrow.up.forward.square", "Click “(2.3)”, “Figure 2.1” or “Rudin (1976)” to peek at it without leaving your page; ⌥-click keeps it open to the side.")
                            tip("character.book.closed", "⌘-click a term such as “eigenvalue”: the book's own index lists its pages, and your glossary its definition.")
                            tip("function", "⌘T lists every equation, figure, table, algorithm and exercise; the numbers under a label count its references.")
                            tip("text.bubble", "Select a passage and press ⌘K to ask your assistant with its context; the answer returns to the note.")
                            tip("flask", "Select an equation and choose Lab: a Python notebook opens beside the page, with NumPy and Matplotlib. Ask an assistant to “Turn into code” and open its answer there.")
                            tip("arrow.clockwise", "Hide part of an equation and recall it later in Review.")
                        }
                    }.frame(minWidth: 280, maxWidth: 420, alignment: .leading)
                }
            }
            .padding(.horizontal, 48).padding(.vertical, 40)
            .frame(maxWidth: 980, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    /// The week's reading across every book, and the current streak.
    @ViewBuilder private var readingCard: some View {
        let logs = store.library.map(\.readingLog)
        let days = ReadingSummary.days(logs, count: 7)
        let total = days.map(\.seconds).reduce(0, +)
        if total > 0 {
            section("This week") {
                HStack(alignment: .firstTextBaseline, spacing: 16) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(ReadingLog.describe(total)).font(.system(size: 17, weight: .semibold).monospacedDigit())
                        Text("reading").font(.caption).foregroundStyle(.secondary)
                    }
                    let streak = ReadingSummary.streak(logs)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("\(streak) \(streak == 1 ? "day" : "days")").font(.system(size: 17, weight: .semibold).monospacedDigit())
                        Text("streak").font(.caption).foregroundStyle(.secondary)
                    }
                }
                ReadingBarChart(days: days).frame(height: 70)
            }
        }
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.headline)
            content()
        }
    }

    private func startRow(_ title: String, symbol: String, shortcut: String?, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: symbol).frame(width: 18).foregroundStyle(Color.lemmaOlive)
                Text(title)
                Spacer(minLength: 8)
                if let shortcut { Text(shortcut).font(.callout.monospaced()).foregroundStyle(.tertiary) }
            }.font(.callout).contentShape(Rectangle())
        }.buttonStyle(.plain)
    }

    private func recentRow(_ book: StudyWorkspace) -> some View {
        Button { store.reopen(book) } label: {
            HStack(alignment: .top, spacing: 10) {
                BookCover(image: store.covers.cover(for: book), width: 26)
                VStack(alignment: .leading, spacing: 3) {
                    Text(book.title).font(.callout.weight(.medium)).lineLimit(1)
                    BookSummary(book: book)
                }
                Spacer(minLength: 0)
            }.contentShape(Rectangle())
        }.buttonStyle(.plain).help(book.sourcePath)
    }

    private func tip(_ symbol: String, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: symbol).frame(width: 18).foregroundStyle(.secondary)
            Text(text).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func continueCard(_ book: StudyWorkspace) -> some View {
        HStack(alignment: .top, spacing: 16) {
            BookCover(image: store.covers.cover(for: book), width: 72)
            VStack(alignment: .leading, spacing: 8) {
                Text("Continue reading").font(.caption.weight(.medium)).foregroundStyle(.secondary)
                Text(book.title).font(.title3.weight(.semibold)).lineLimit(2)
                BookSummary(book: book)
                if !book.reading.returnNote.isEmpty {
                    Label(book.reading.returnNote, systemImage: "arrow.turn.down.right").font(.callout).foregroundStyle(.secondary).lineLimit(2)
                }
                Button("Continue") { store.reopen(book) }.buttonStyle(.borderedProminent)
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
    }
}
