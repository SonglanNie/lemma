import SwiftUI
import LemmaCore

struct PageSearchPane: View {
    @Bindable var store: StudyStore

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                Picker("Indexed search scope", selection: $store.pageSearchScope) {
                    ForEach(PageSearchScope.allCases) { scope in Text(scope.label).tag(scope).disabled(scope == .project && store.currentProject == nil) }
                }.pickerStyle(.segmented).labelsHidden()
                HStack(spacing: 6) {
                    searchField("Find in indexed pages", text: $store.pageSearchQuery).onSubmit { store.searchIndexedPages() }
                    Button(action: store.searchIndexedPages) { Image(systemName: "arrow.right") }.buttonStyle(.borderless).accessibilityLabel("Search indexed pages")
                }
                Toggle("Related meaning", isOn: $store.searchByMeaning).toggleStyle(.checkbox).font(.callout)
                indexControls
                if store.searchByMeaning {
                    Text("Local text similarity suggests passages in the query’s language. Check the original; formulas and logical validity are not inferred.")
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }.padding(14)
            Divider()
            if store.isSearchingPages {
                HStack { ProgressView().controlSize(.small); Text("Searching local passages…").font(.callout); Spacer() }.padding(16)
                Spacer()
            } else if !store.pageSearchResults.isEmpty {
                if store.searchByMeaning && !store.semanticSearchAvailable {
                    Text("No local sentence model for this query. Showing text matches.").font(.caption).foregroundStyle(.secondary).padding(14)
                }
                List(store.pageSearchResults) { result in
                    Button { store.openPageResult(result) } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(result.text).font(.callout).lineLimit(5).multilineTextAlignment(.leading)
                            Text("\(store.library.first { $0.id == result.workspaceID }?.title ?? "Document") · PDF page \(result.pageIndex + 1)")
                                .font(.caption.weight(.medium)).foregroundStyle(.secondary).lineLimit(2)
                            Text("\(result.origin == .ocr ? "OCR · check against page" : "PDF text") · \(result.exact ? "Text match" : "Related meaning")")
                                .font(.caption).foregroundStyle(.secondary)
                        }.padding(.vertical, 7).frame(maxWidth: .infinity, alignment: .leading)
                    }.buttonStyle(.plain).accessibilityLabel("Open passage on PDF page \(result.pageIndex + 1): \(result.text)")
                        .contextMenu {
                            Button("Go to page") { store.openPageResult(result) }
                            if result.origin == .ocr { Button("Review OCR text…") { store.prepareIndexReview(result) } }
                        }
                }.listStyle(.sidebar).scrollContentBackground(.hidden)
            } else {
                PaneEmptyState(symbol: "text.viewfinder", title: store.pageSearchQuery.isEmpty ? "Make scans searchable" : "No indexed matches",
                    message: store.pageSearchQuery.isEmpty
                    ? "Index this PDF once. Text pages are extracted; image-only pages use local OCR. Completed pages stay available offline."
                    : store.searchByMeaning && !store.semanticSearchAvailable
                    ? "No local sentence model is available for this query. Try a source term, or finish indexing the document."
                    : "Try another phrase or finish indexing. Library search covers documents you have indexed.")
            }
        }
        .onChange(of: store.pageSearchScope) { _, _ in store.searchIndexedPages() }
        .onChange(of: store.searchByMeaning) { _, _ in store.searchIndexedPages() }
        .onChange(of: store.pageSearchQuery) { _, text in
            store.pageSearchTask?.cancel(); store.pageSearchResults = []; store.isSearchingPages = false
            if text.isEmpty { store.searchIndexedPages() }
        }
    }

    private var indexControls: some View {
        VStack(alignment: .leading, spacing: 7) {
            if let progress = store.indexProgress {
                Text("\(progress.completedPages) of \(progress.totalPages) pages indexed").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                if progress.status == .running {
                    ProgressView(value: Double(progress.completedPages), total: Double(max(1, progress.totalPages)))
                    HStack {
                        Text(PageIndexer.shared.pause?.label ?? "Low priority · pauses on battery and when the Mac is hot")
                            .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        Spacer(); Button("Stop", action: store.stopIndexing).buttonStyle(.borderless).font(.caption)
                    }
                } else if progress.status != .complete {
                    if let message = progress.message { Text(message).font(.caption).foregroundStyle(.secondary).lineLimit(3) }
                    Button("Resume indexing", action: store.startIndexing).font(.callout)
                }
            } else {
                Button("Index this PDF…", action: store.startIndexing).font(.callout)
                Text("Local OCR and sentence models, at low priority. Indexing pauses on battery and when the Mac is hot.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }.disabled(store.isLaunchingIndex || store.workspace == nil)
    }
}
