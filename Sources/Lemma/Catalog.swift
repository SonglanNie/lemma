import SwiftUI
import AppKit
import LemmaCore

/// Downloads of PDFs the reader asked for: a book of the catalog, an arXiv paper, a cited work. Each is checked to be
/// a PDF before it is opened; nothing is downloaded without a click.
@MainActor @Observable
final class PDFDownloads {
    var progress: [String: Double] = [:]
    var failures: [String: String] = [:]
    @ObservationIgnored private var tasks: [String: URLSessionDownloadTask] = [:]

    func isDownloading(_ id: String) -> Bool { progress[id] != nil }

    /// Downloads to `destination` (replacing nothing until the file is complete and checked).
    func download(id: String, from url: URL, to destination: URL) async throws -> URL {
        if FileManager.default.fileExists(atPath: destination.path) { return destination }
        failures[id] = nil
        progress[id] = 0
        defer { progress[id] = nil; tasks[id] = nil }
        var request = URLRequest(url: url, timeoutInterval: 60)
        request.setValue(PaperLookup.userAgent, forHTTPHeaderField: "User-Agent")
        let (temporary, response): (URL, URLResponse) = try await withCheckedThrowingContinuation { continuation in
            let task = URLSession.shared.downloadTask(with: request) { location, response, error in
                if let error { continuation.resume(throwing: error); return }
                guard let location, let response else { continuation.resume(throwing: URLError(.badServerResponse)); return }
                // The file at `location` is removed when this handler returns: move it first.
                let kept = FileManager.default.temporaryDirectory.appendingPathComponent("lemma-\(UUID().uuidString).pdf")
                do { try FileManager.default.moveItem(at: location, to: kept); continuation.resume(returning: (kept, response)) }
                catch { continuation.resume(throwing: error) }
            }
            tasks[id] = task
            task.resume()
            Task { @MainActor [weak self, weak task] in
                while let task, task.state == .running {
                    let fraction = task.countOfBytesExpectedToReceive > 0 ? Double(task.countOfBytesReceived) / Double(task.countOfBytesExpectedToReceive) : task.progress.fractionCompleted
                    self?.progress[id] = max(0, min(1, fraction))
                    try? await Task.sleep(for: .milliseconds(250))
                }
            }
        }
        defer { try? FileManager.default.removeItem(at: temporary) }
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) { throw DownloadError.status(http.statusCode) }
        let handle = try FileHandle(forReadingFrom: temporary)
        let head = try handle.read(upToCount: 1024) ?? Data()
        try handle.close()
        guard head.range(of: Data("%PDF".utf8)) != nil else { throw DownloadError.notPDF }
        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.moveItem(at: temporary, to: destination)
        return destination
    }

    func cancel(_ id: String) { tasks[id]?.cancel() }

    enum DownloadError: LocalizedError {
        case status(Int), notPDF
        var errorDescription: String? {
            switch self {
            case let .status(code): "The server answered \(code)."
            case .notPDF: "The server sent a web page instead of the PDF (it may ask for a confirmation or limit downloads). Open the book's page instead."
            }
        }
    }
}

@MainActor
extension StudyStore {
    var downloadedBooksFolder: URL { repository.root.appendingPathComponent("Books", isDirectory: true) }
    var downloadedPapersFolder: URL { repository.root.appendingPathComponent("Papers", isDirectory: true) }

    /// The downloaded copy, named after the book so its tab and library entry read well.
    func catalogFile(_ book: CatalogBook) -> URL {
        // Books that share a title (the two Probabilistic Machine Learning volumes, ISL with R and with Python) are told
        // apart by their subtitle or edition; other books keep the plain title their earlier downloads used.
        var name = book.title
        if BookCatalog.books.contains(where: { $0.id != book.id && $0.title == book.title }) {
            name += " – " + (book.subtitle ?? book.edition ?? book.id)
        }
        return downloadedBooksFolder.appendingPathComponent(StudyStore.fileName(name) + ".pdf")
    }

    static func fileName(_ title: String) -> String {
        let cleaned = title.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: " –").replacingOccurrences(of: "_", with: " ")
        return String(cleaned.prefix(90)).trimmingCharacters(in: .whitespaces)
    }
    func isInLibrary(_ book: CatalogBook) -> Bool { FileManager.default.fileExists(atPath: catalogFile(book).path) }

    /// Downloads a book of the catalog (once) and opens it in a new tab.
    func getCatalogBook(_ book: CatalogBook) {
        Task {
            do {
                status = "Downloading \(book.title)…"
                let url = try await downloads.download(id: book.id, from: book.pdf, to: catalogFile(book))
                // Downloads go to the Books library's folder, which may have been created just now.
                libraries.refresh()
                open(url)
                status = "\(book.title) is in your library. Lemma reads it once in the background."
            } catch {
                downloads.failures[book.id] = error.localizedDescription
                status = "Could not download \(book.title)."
            }
        }
    }

    /// Opens an arXiv paper from its identifier or address.
    func openArxiv(_ text: String) {
        guard let id = ArxivIdentifier.parse(text) else { status = "Type an arXiv identifier such as 1706.03762 or its address."; return }
        importArxiv(id)
    }

    func localArxivFile(_ id: String) -> URL? {
        let stem = "arXiv " + id.replacingOccurrences(of: "/", with: "-")
        return (try? FileManager.default.contentsOfDirectory(at: downloadedPapersFolder, includingPropertiesForKeys: nil))?
            .first { $0.pathExtension.lowercased() == "pdf" && ($0.deletingPathExtension().lastPathComponent == stem || $0.deletingPathExtension().lastPathComponent.hasSuffix("(\(stem))")) }
    }

    func importArxiv(_ id: String, paper: ArxivPaper? = nil) {
        guard ArxivIdentifier.parse(id) == id else { return }
        if let existing = localArxivFile(id) { open(existing); return }
        guard arxivImports.insert(id).inserted else { return }
        Task {
            defer { arxivImports.remove(id) }
            do {
                status = "Downloading arXiv:\(id)…"
                let metadata: ArxivPaper?
                if let paper { metadata = paper }
                else {
                    metadata = try? await ArxivClient.shared.search(query: id, cacheFolder: repository.root.appendingPathComponent("ArxivCache")).papers.first
                }
                let file = downloadedPapersFolder.appendingPathComponent("arXiv " + id.replacingOccurrences(of: "/", with: "-") + ".pdf")
                let url = try await downloads.download(id: "arxiv:" + id, from: URL(string: "https://arxiv.org/pdf/\(id)")!, to: file)
                open(url)
                if let metadata, workspace?.sourcePath == url.path {
                    workspace?.title = metadata.title
                    if let tab = tabs.firstIndex(where: { $0.id == workspace?.id }) { tabs[tab].title = metadata.title }
                    flush()
                    if let encoded = try? WorkspaceRepository.encoder.encode(metadata) {
                        try? encoded.write(to: file.deletingPathExtension().appendingPathExtension("json"), options: .atomic)
                    }
                }
                libraries.refresh()
                status = "arXiv:\(id) opened."
            } catch {
                downloads.failures["arxiv:" + id] = error.localizedDescription
                self.error = "Could not download arXiv:\(id): \(error.localizedDescription)"
            }
        }
    }

    /// Opens the open PDF of a cited work in a new tab.
    func openPaper(_ paper: PaperCandidate) {
        guard let pdf = paper.pdfURL else { if let page = paper.pageURL { NSWorkspace.shared.open(page) }; return }
        let file = downloadedPapersFolder.appendingPathComponent(StudyStore.fileName(paper.title.isEmpty ? (paper.arxivID ?? paper.doi ?? "Paper") : paper.title) + ".pdf")
        Task {
            do {
                status = "Downloading “\(paper.title)”…"
                let url = try await downloads.download(id: paper.id, from: pdf, to: file)
                referencePeek = nil
                open(url)
            } catch {
                downloads.failures[paper.id] = error.localizedDescription
                status = "Could not download the paper: \(error.localizedDescription)"
            }
        }
    }
}

/// The catalog of free books, as an editor's extensions view: search, a subject filter, and one click to get a book.
struct CatalogSidebar: View {
    @Bindable var store: StudyStore
    @Environment(\.theme) private var theme
    @State private var query = ""
    @State private var subject: String?
    @State private var arxiv = ""

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                modeTab("Free Books", .books)
                modeTab("arXiv Papers", .arxiv)
            }
            .padding(3)
            .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(theme[.inputBackground]))
            .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(theme.border(.inputBorder), lineWidth: 1))
            .padding(.horizontal, 12).padding(.top, 10).padding(.bottom, 4)
            if store.catalogMode == .arxiv { ArxivCatalogView(store: store) }
            else { bookCatalog }
        }
    }

    private func modeTab(_ title: String, _ mode: CatalogMode) -> some View {
        let selected = store.catalogMode == mode
        return Button { store.catalogMode = mode } label: {
            Text(title).font(.ui(12, weight: selected ? .semibold : .regular))
                .foregroundStyle(selected ? theme[.foreground] : theme[.descriptionForeground])
                .frame(maxWidth: .infinity).frame(height: 24)
                .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(selected ? theme[.listActiveSelectionBackground] : .clear))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    @ViewBuilder private var bookCatalog: some View {
        let books = BookCatalog.search(query).filter { subject == nil || $0.subject == subject }
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                VSTextField(placeholder: "Search free books: lasso, Bayes, proofs…", text: $query, icon: "search")
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 5) {
                        chip("All", selected: subject == nil) { subject = nil }
                        ForEach(BookCatalog.subjects, id: \.self) { name in chip(name, selected: subject == name) { subject = subject == name ? nil : name } }
                    }
                }
                VSTextField(placeholder: "arXiv paper: 1706.03762 or its address", text: $arxiv, icon: "cloud-download",
                            onSubmit: { store.openArxiv(arxiv) })
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            Rectangle().fill(theme.border(.sideBarSectionHeaderBorder)).frame(height: 1)
            if books.isEmpty {
                VSWelcomeView(message: "No book matches. Try another word, or clear the subject filter.") {
                    Button("Clear Filters") { query = ""; subject = nil }.buttonStyle(.vsSecondary)
                }
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(books) { book in CatalogRow(store: store, book: book) }
                    }
                    .padding(.vertical, 4)
                }
            }
            Text("\(BookCatalog.books.count) books their authors or publishers give away as PDFs. Lemma downloads one only when you click Get, from its official address, and keeps it in your library.")
                .font(.ui(11)).foregroundStyle(theme[.descriptionForeground]).fixedSize(horizontal: false, vertical: true)
                .padding(12)
        }
    }

    private func chip(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.ui(11, weight: selected ? .semibold : .regular))
                .padding(.horizontal, 9).frame(height: 21)
                .background(Capsule().fill(selected ? theme.accent.opacity(theme.isDark ? 0.22 : 0.16) : theme[.inputBackground]))
                .overlay(Capsule().strokeBorder(selected ? theme.accent.opacity(0.55) : theme.border(.inputBorder), lineWidth: 1))
                .foregroundStyle(selected ? theme[.foreground] : theme[.descriptionForeground])
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

private struct CatalogRow: View {
    @Bindable var store: StudyStore
    @Environment(\.theme) private var theme
    let book: CatalogBook
    @State private var hovering = false

    var body: some View {
        let downloaded = store.isInLibrary(book)
        let progress = store.downloads.progress[book.id]
        HStack(alignment: .top, spacing: 12) {
            GeneratedBookCover(title: book.title, subtitle: book.subtitle, authors: book.authorLine, subject: book.subject, width: 54)
            VStack(alignment: .leading, spacing: 3) {
                Text(book.title).font(.ui(12.5, weight: .semibold)).foregroundStyle(theme[.foreground]).lineLimit(2)
                Text("\(book.authorLine) · \(String(book.year))").font(.ui(11)).foregroundStyle(theme[.descriptionForeground]).lineLimit(1)
                Text(book.summary).font(.ui(11)).foregroundStyle(theme[.descriptionForeground]).lineLimit(hovering ? 5 : 2)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 6) {
                    Text(book.level).font(.ui(10, weight: .medium)).foregroundStyle(theme[.descriptionForeground])
                        .padding(.horizontal, 6).frame(height: 16)
                        .background(Capsule().fill(theme[.badgeBackground].opacity(0.55)))
                    if let size = book.sizeText { Text(size).font(.ui(10)).monospacedDigit().foregroundStyle(theme[.descriptionForeground].opacity(0.8)) }
                    Spacer(minLength: 4)
                    if let progress {
                        ProgressView(value: progress).progressViewStyle(.linear).frame(width: 60).controlSize(.mini).tint(theme.accent)
                        VSIconButton(icon: "close", help: "Cancel the download", size: 13) { store.downloads.cancel(book.id) }
                    } else if downloaded {
                        Button("Open") { store.open(store.catalogFile(book)) }.buttonStyle(VSButtonStyle(kind: .secondary, compact: true))
                    } else {
                        Button("Get") { store.getCatalogBook(book) }.buttonStyle(VSButtonStyle(kind: .primary, compact: true))
                            .help("Download the PDF from \(book.pdf.host ?? "the authors' site") and open it")
                    }
                }
                .padding(.top, 2)
                if let failure = store.downloads.failures[book.id] {
                    Text(failure).font(.ui(10.5)).foregroundStyle(theme[.errorForeground]).fixedSize(horizontal: false, vertical: true)
                    VSLinkButton(title: "Open the book's page ↗") { NSWorkspace.shared.open(book.homepage) }
                }
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 9)
        .background(hovering ? theme[.listHoverBackground] : .clear)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .help("\(book.title)\(book.subtitle.map { ": " + $0 } ?? "")\n\(book.edition ?? "")\n\(book.license)")
        .contextMenu {
            Button("Open the Book's Page ↗") { NSWorkspace.shared.open(book.homepage) }
            Button("Copy PDF Address") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(book.pdf.absoluteString, forType: .string) }
            if downloaded { Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([store.catalogFile(book)]) } }
        }
    }
}

/// What a search for a cited work found, kept while the book is open.
enum PaperLookupState: Equatable { case searching, found([PaperCandidate]), failed }

@MainActor
extension StudyStore {
    /// Looks a reference up online, once per entry while the book is open.
    func findPaper(_ entry: BibliographyEntry) {
        if case .found? = paperLookups[entry.id] { return }
        paperLookups[entry.id] = .searching
        Task {
            let papers = await PaperLookup.find(entry: entry.text, authors: entry.authors, year: entry.year)
            paperLookups[entry.id] = papers.isEmpty ? .failed : .found(papers)
        }
    }
}

/// Finds the cited work online and offers to open it: shown in a citation's peek after a click.
struct PaperLookupView: View {
    @Bindable var store: StudyStore
    let entry: BibliographyEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            switch store.paperLookups[entry.id] {
            case nil:
                Button { store.findPaper(entry) } label: { Label("Find the Paper", systemImage: "doc.text.magnifyingglass") }
                    .buttonStyle(.borderless)
                    .help("Look the work up in Crossref, Semantic Scholar and arXiv (only the reference's text is sent) and open it in a new tab when a free PDF exists")
            case .searching?:
                HStack(spacing: 6) { ProgressView().controlSize(.small); Text("Searching Crossref, Semantic Scholar and arXiv…").font(.caption).foregroundStyle(.secondary) }
            case .failed?:
                Text("No match found online. Search Scholar instead.").font(.caption).foregroundStyle(.secondary)
            case let .found(papers)?:
                ForEach(papers) { paper in card(paper) }
            }
        }
        .font(.callout)
    }

    private func card(_ paper: PaperCandidate) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(paper.title).font(.system(size: 12.5, weight: .semibold)).lineLimit(3).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 4)
                Text(paper.confidence >= 0.6 ? "Likely" : "Possible").font(.system(size: 9.5, weight: .semibold))
                    .padding(.horizontal, 5).frame(height: 15)
                    .background((paper.confidence >= 0.6 ? Color.green : Color.orange).opacity(0.15), in: Capsule())
                    .foregroundStyle(paper.confidence >= 0.6 ? Color.green : Color.orange)
                    .help("How well the authors, year and title match this reference")
            }
            Text([paper.authorLine, paper.year.map(String.init), paper.venue].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · "))
                .font(.caption).foregroundStyle(.secondary).lineLimit(1)
            if let abstract = paper.abstract, !abstract.isEmpty {
                Text(abstract).font(.caption).foregroundStyle(.secondary).lineLimit(4).fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 12) {
                if paper.pdfURL != nil {
                    if let progress = store.downloads.progress[paper.id] {
                        ProgressView(value: progress).frame(width: 80).controlSize(.mini)
                    } else {
                        Button("Open in a New Tab") { store.openPaper(paper) }.buttonStyle(.borderedProminent).tint(.lemmaOlive).controlSize(.small)
                    }
                }
                if let page = paper.pageURL { Button(paper.arxivID != nil && paper.doi == nil ? "arXiv ↗" : "Publisher ↗") { NSWorkspace.shared.open(page) }.buttonStyle(.link) }
                if let citations = paper.citationCount, citations > 0 { Text("cited \(citations)×").font(.caption).foregroundStyle(.tertiary) }
            }
            if let failure = store.downloads.failures[paper.id] { Text(failure).font(.caption).foregroundStyle(.red) }
        }
        .padding(8)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 7))
    }
}
