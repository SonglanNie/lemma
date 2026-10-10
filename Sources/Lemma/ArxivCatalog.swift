import SwiftUI
import AppKit
import LemmaCore

enum CatalogMode: String { case books, arxiv }

@MainActor
extension StudyStore {
    func searchArxiv(more: Bool = false) {
        let query = arxivQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return }
        arxivSearchTask?.cancel()
        let start: Int
        if more {
            guard arxivPage?.hasMore == true, query == arxivSubmittedQuery, arxivSort == arxivSubmittedSort else { return }
            start = (arxivPage?.start ?? 0) + (arxivPage?.papers.count ?? 0)
        } else {
            start = 0; arxivResults = []; arxivPage = nil
            arxivSubmittedQuery = query; arxivSubmittedSort = arxivSort
        }
        let sort = arxivSubmittedSort
        arxivSearching = true; arxivSearchError = nil
        arxivSearchTask = Task { [weak self] in
            do {
                guard let self else { return }
                let page = try await ArxivClient.shared.search(query: query, start: start, sort: sort, cacheFolder: repository.root.appendingPathComponent("ArxivCache"))
                guard !Task.isCancelled else { return }
                let existing = Set(arxivResults.map(\.id))
                arxivResults += page.papers.filter { !existing.contains($0.id) }
                arxivPage = page; arxivSearching = false
            } catch {
                guard !Task.isCancelled else { return }
                self?.arxivSearchError = "arXiv could not be reached: \(error.localizedDescription)"
                self?.arxivSearching = false
            }
        }
    }
}

struct ArxivCatalogView: View {
    @Bindable var store: StudyStore
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                TextField("Title, author, topic, arXiv ID or URL", text: $store.arxivQuery).textFieldStyle(.roundedBorder)
                    .font(.system(size: 12)).onSubmit { submit() }
                    .accessibilityLabel("Search arXiv")
                HStack {
                    Picker("Sort", selection: $store.arxivSort) { ForEach(ArxivSort.allCases, id: \.self) { Text($0.label).tag($0) } }.labelsHidden()
                    Spacer(minLength: 4)
                    if store.arxivSearching {
                        ProgressView().controlSize(.small)
                        Button("Cancel") { store.arxivSearchTask?.cancel(); store.arxivSearching = false }.controlSize(.small)
                    } else { Button("Search", action: submit).controlSize(.small).disabled(store.arxivQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) }
                }
                if let id = ArxivIdentifier.parse(store.arxivQuery) {
                    Button("Add arXiv:\(id)") { store.importArxiv(id) }.controlSize(.small)
                        .disabled(store.arxivImports.contains(id))
                    if let failure = store.downloads.failures["arxiv:" + id] { Text(failure).font(.caption).foregroundStyle(.red) }
                }
            }.padding(10)
            Divider()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if let error = store.arxivSearchError {
                        Text(error).font(.callout).foregroundStyle(.secondary).padding(12)
                        Button("Try Again") { store.searchArxiv() }.padding(.horizontal, 12)
                    }
                    if store.arxivResults.isEmpty && !store.arxivSearching && store.arxivSearchError == nil {
                        Text(store.arxivPage == nil ? "Search arXiv’s remote catalogue, then choose a paper to download and study. You can also paste its identifier or address." : "No paper matches. Try fewer words or an author's name.")
                            .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true).padding(12)
                        if store.arxivPage == nil {
                            Text("Advanced queries: au:Vaswani, ti:regression, cat:q-fin.ST").font(.caption).foregroundStyle(.secondary).padding(.horizontal, 12)
                        }
                    }
                    if let page = store.arxivPage {
                        Text("\(store.arxivResults.count) of \(page.total) results").font(.caption).foregroundStyle(.secondary).padding(10)
                    }
                    ForEach(store.arxivResults) { paper in ArxivResultRow(store: store, paper: paper); Divider() }
                    if store.arxivPage?.hasMore == true {
                        Button("More Results") { store.searchArxiv(more: true) }.disabled(store.arxivSearching || store.arxivQuery.trimmingCharacters(in: .whitespacesAndNewlines) != store.arxivSubmittedQuery || store.arxivSort != store.arxivSubmittedSort).padding(10)
                    }
                }
            }
            Divider()
            VStack(alignment: .leading, spacing: 5) {
                Text("Only your search is sent to arXiv. PDFs download when you choose Add and stay available offline.")
                    .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Button("Quick Add from Chrome…") { store.showBrowserSetup = true }.buttonStyle(.link).font(.system(size: 11))
            }.padding(10)
        }
    }
    private func submit() { store.searchArxiv() }
}

private struct ArxivResultRow: View {
    @Bindable var store: StudyStore
    let paper: ArxivPaper
    @State private var showAbstract = false
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(paper.title).font(.system(size: 12, weight: .semibold)).fixedSize(horizontal: false, vertical: true)
            Text(paper.authors.joined(separator: ", ")).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(2)
            Text("\(paper.id) · \(String(paper.published.prefix(10))) · \(paper.categories.prefix(2).joined(separator: ", "))")
                .font(.system(size: 10.5)).foregroundStyle(.secondary).lineLimit(2)
            DisclosureGroup("Abstract", isExpanded: $showAbstract) {
                Text(paper.summary).font(.system(size: 11)).foregroundStyle(.secondary).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
            }.font(.system(size: 11))
            HStack {
                if let progress = store.downloads.progress["arxiv:" + paper.id] {
                    ProgressView(value: progress).frame(maxWidth: 80).controlSize(.mini)
                    Button("Cancel") { store.downloads.cancel("arxiv:" + paper.id) }.controlSize(.small)
                } else {
                    Button(store.localArxivFile(paper.id) == nil ? "Add to Lemma" : "Open") { store.importArxiv(paper.id, paper: paper) }
                        .controlSize(.small).disabled(store.arxivImports.contains(paper.id))
                }
                Spacer(minLength: 4)
                Button("arXiv ↗") { NSWorkspace.shared.open(paper.pageURL) }.buttonStyle(.link)
            }.font(.system(size: 11))
            if let failure = store.downloads.failures["arxiv:" + paper.id] { Text(failure).font(.caption).foregroundStyle(.red) }
        }.padding(10)
    }
}
