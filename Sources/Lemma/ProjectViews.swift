import SwiftUI
import AppKit
import LemmaCore

/// An explorer of research questions and their books, rather than a second copy of the library.
struct ProjectsSidebar: View {
    @Bindable var store: StudyStore
    @State private var expanded: Set<UUID> = []

    var body: some View {
        VStack(spacing: 0) {
            searchField("Find a project", text: $store.projectQuery).padding(14)
            if store.activeProjects.isEmpty {
                PaneEmptyState(symbol: "folder", title: "Follow a question across books",
                    message: "Create a project, collect passages as you read, and write a synthesis with links to every source.",
                    action: ("New Research Project", { store.newProject() }))
            }
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(store.activeProjects.filter { store.projectQuery.isEmpty || $0.title.localizedStandardContains(store.projectQuery) || $0.question.localizedStandardContains(store.projectQuery) }) { project in
                        projectRow(project)
                    }
                    let archived = store.projects.filter(\.archived)
                    if !archived.isEmpty {
                        DisclosureGroup("Archived (\(archived.count))") {
                            ForEach(archived) { project in
                                HStack {
                                    Text(project.title).font(.callout).lineLimit(1)
                                    Spacer()
                                    Button("Restore") { store.archiveProject(project.id, archived: false) }.buttonStyle(.borderless).font(.caption)
                                }.padding(.vertical, 5)
                            }
                        }.font(.caption).foregroundStyle(.secondary).padding(14)
                    }
                }
            }
        }
        .onAppear { if let id = store.selectedProjectID { expanded.insert(id) } }
        .onChange(of: store.selectedProjectID) { _, id in if let id { expanded.insert(id) } }
    }

    private func projectRow(_ project: ResearchProject) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            DisclosureGroup(isExpanded: Binding(get: { expanded.contains(project.id) }, set: { value in
                if value { expanded.insert(project.id) } else { expanded.remove(project.id) }
            })) {
                VStack(alignment: .leading, spacing: 8) {
                    if !project.question.isEmpty {
                        Text(project.question).font(.caption).foregroundStyle(.secondary).lineLimit(3)
                    }
                    Button { store.openProject(project.id) } label: {
                        Label("Synthesis · \(project.passages.count) sources", systemImage: "doc.text")
                            .font(.system(size: 12)).frame(maxWidth: .infinity, alignment: .leading)
                    }.buttonStyle(.plain).padding(.vertical, 3)
                    ForEach(project.bookIDs, id: \.self) { id in
                        if let book = store.library.first(where: { $0.id == id }) {
                            Button { store.reopen(book) } label: {
                                HStack(spacing: 7) {
                                    Image(systemName: "book.closed").font(.system(size: 10)).foregroundStyle(.secondary)
                                    Text(book.title).font(.system(size: 12)).lineLimit(1)
                                    Spacer(minLength: 0)
                                    let count = project.passages.filter { $0.bookID == id }.count
                                    if count > 0 { Text("\(count)").font(.caption.monospacedDigit()).foregroundStyle(.secondary) }
                                }.contentShape(Rectangle())
                            }.buttonStyle(.plain).padding(.vertical, 3)
                            .contextMenu {
                                Button("Open") { store.reopen(book) }
                                Button("Remove Book from Project") { store.removeBookFromProject(id, projectID: project.id) }
                            }
                        }
                    }
                    ProjectBookMenu(store: store, projectID: project.id)
                    HStack(spacing: 14) {
                        Button("Search Books") { store.searchProject(project.id) }
                        Button("Export…") { store.exportProject(project.id) }
                    }.buttonStyle(.borderless).font(.caption).padding(.top, 2)
                }.padding(.leading, 17).padding(.vertical, 8)
            } label: {
                Button { store.openProject(project.id) } label: {
                    Label(project.title, systemImage: "folder.fill")
                        .font(.system(size: 12.5, weight: .semibold)).lineLimit(1)
                        .foregroundStyle(store.selectedProjectID == project.id ? Color.lemmaOlive : Color.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }.buttonStyle(.plain)
            }
            .padding(12)
            .background(store.selectedProjectID == project.id ? Color.lemmaOlive.opacity(0.09) : .clear)
            .contextMenu {
                Button("Open Synthesis") { store.openProject(project.id) }
                Button("Add Current Book", action: { if let id = store.workspace?.id { store.addBookToProject(id, projectID: project.id) } })
                    .disabled(store.workspace == nil)
                Button("Export…") { store.exportProject(project.id) }
                Divider()
                Button("Archive Project") { store.archiveProject(project.id, archived: true) }
            }
            .dropDestination(for: String.self) { values, _ in
                guard let value = values.first, value.hasPrefix("lemma-book:"),
                      let book = store.library.first(where: { $0.id == String(value.dropFirst("lemma-book:".count)) }) else { return false }
                store.addBookToProject(book.id, projectID: project.id); return true
            }
            Divider()
        }
    }
}

struct ProjectBookMenu: View {
    @Bindable var store: StudyStore
    let projectID: UUID

    var body: some View {
        Menu {
            let ids = Set(store.project(projectID)?.bookIDs ?? [])
            let available = store.library.filter { !ids.contains($0.id) }
            ForEach(available) { book in
                Button(book.title) { store.addBookToProject(book.id, projectID: projectID) }
            }
            if available.isEmpty { Text("Every library book is already in this project") }
            Divider()
            Button("Open a PDF…", action: store.choosePDF)
        } label: { Label("Add Book", systemImage: "plus") }
            .menuStyle(.borderlessButton).fixedSize().font(.caption)
    }
}

/// A writing surface above a source ledger. Both remain useful in a narrow side editor.
struct ProjectEditor: View {
    @Bindable var store: StudyStore
    let projectID: UUID
    @State private var preview = false
    @State private var expanded: Set<UUID> = []
    @FocusState private var titleFocused: Bool

    var body: some View {
        if let project = store.project(projectID) {
            VStack(spacing: 0) {
                header(project)
                Divider()
                VStack(alignment: .leading, spacing: 6) {
                    Text("Research question").font(.caption.weight(.medium)).foregroundStyle(.secondary)
                    TextField("What are you trying to understand?", text: field(\.question), axis: .vertical)
                        .textFieldStyle(.plain).font(.system(size: 13)).lineLimit(1...4)
                        .accessibilityLabel("Project research question")
                }.padding(14)
                Divider()
                ResizablePair(store: store, id: "project.panes", axis: .horizontal, minimumFirst: 170, minimumSecond: 140) {
                    synthesis(project).frame(maxHeight: .infinity)
                } second: {
                    sources(project).frame(maxHeight: .infinity)
                }
                Divider()
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle").foregroundStyle(.secondary)
                    Text(store.projectsDirty ? "Unsaved changes · Markdown & LaTeX" : "Saved locally · Markdown & LaTeX")
                    Spacer(minLength: 0)
                    Text("\(project.synthesis.split(whereSeparator: \.isWhitespace).count) words").monospacedDigit()
                }.font(.system(size: 10.5)).foregroundStyle(.secondary).padding(.horizontal, 12).frame(height: 25)
            }
            .background(Color(nsColor: .textBackgroundColor))
            .onAppear { titleFocused = project.title == "Untitled Project" }
            .onDisappear { store.flushProjects() }
        } else {
            PaneEmptyState(symbol: "folder", title: "Project closed", message: "Open a project from the Projects explorer.")
        }
    }

    private func field(_ keyPath: WritableKeyPath<ResearchProject, String>) -> Binding<String> {
        Binding(get: { store.project(projectID)?[keyPath: keyPath] ?? "" }, set: { value in
            store.updateProject(projectID) { $0[keyPath: keyPath] = value }
        })
    }

    private func header(_ project: ResearchProject) -> some View {
        HStack(spacing: 9) {
            Image(systemName: "folder").font(.system(size: 17)).foregroundStyle(Color.lemmaOlive)
            TextField("Project name", text: field(\.title)).textFieldStyle(.plain).font(.system(size: 16, weight: .semibold))
                .focused($titleFocused).accessibilityLabel("Project name")
            Menu {
                Button("Search Project Books") { store.searchProject(projectID) }
                Button("Export Project…") { store.exportProject(projectID) }
                Button("Reveal Project Files") { NSWorkspace.shared.activateFileViewerSelecting([store.projectRepository.directory(projectID)]) }
                Divider()
                Button("Archive Project") { store.archiveProject(projectID, archived: true) }
            } label: { Image(systemName: "ellipsis") }.menuStyle(.borderlessButton).menuIndicator(.hidden).frame(width: 20)
                .accessibilityLabel("Project actions")
        }.padding(.horizontal, 14).frame(height: 48)
    }

    private func synthesis(_ project: ResearchProject) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Synthesis").font(.system(size: 12, weight: .semibold))
                Spacer()
                Picker("Synthesis view", selection: $preview) { Text("Write").tag(false); Text("Preview").tag(true) }
                    .pickerStyle(.segmented).labelsHidden().frame(width: 138).controlSize(.small)
            }.padding(.horizontal, 14).frame(height: 36)
            Divider()
            if preview {
                ScrollView {
                    if project.synthesis.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text("Your synthesis will appear here, with typeset mathematics and clickable source citations.")
                            .font(.callout).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading).padding(16)
                    } else { MathPreview(text: project.synthesis, onOpenLink: store.openLink).padding(16) }
                }
            } else {
                TextEditor(text: field(\.synthesis)).font(.system(size: 12.5, design: .monospaced))
                    .scrollContentBackground(.hidden).padding(9).accessibilityLabel("Project synthesis")
                    .overlay(alignment: .topLeading) {
                        if project.synthesis.isEmpty {
                            Text("Write what the sources tell you.\nAppend a citation from a source below.")
                                .font(.system(size: 12.5, design: .monospaced)).foregroundStyle(.secondary)
                                .padding(.leading, 14).padding(.top, 10).allowsHitTesting(false)
                        }
                    }
            }
        }
    }

    private func sources(_ project: ResearchProject) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Text("Sources").font(.system(size: 12, weight: .semibold))
                Text("\(project.passages.count)").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                Spacer()
                Button { store.collectSelection(projectID: projectID) } label: { Label("Collect", systemImage: "plus") }
                    .buttonStyle(.borderless).font(.caption).disabled(!store.reader.hasSelection)
                    .help("Collect the selected passage in this project · ⇧⌘C")
            }.padding(.horizontal, 14).frame(height: 34)
            Divider()
            if project.passages.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Build the evidence as you read.").font(.callout.weight(.medium))
                    Text("Select a passage in any book, then choose Collect (⇧⌘C). Its original crop, text and page stay with this project.")
                        .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    ProjectBookMenu(store: store, projectID: projectID)
                }.padding(18).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(project.passages) { source in
                            ProjectSourceRow(store: store, projectID: projectID, source: source,
                                expanded: Binding(get: { expanded.contains(source.id) }, set: { value in
                                    if value { expanded.insert(source.id) } else { expanded.remove(source.id) }
                                }))
                            Divider()
                        }
                    }
                }
            }
        }
        .background(Color.lemmaSidebar)
    }
}

private struct ProjectSourceRow: View {
    @Bindable var store: StudyStore
    let projectID: UUID
    let source: ProjectPassage
    @Binding var expanded: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 8) {
                Button { expanded.toggle() } label: {
                    Image(systemName: expanded ? "chevron.down" : "chevron.right").font(.system(size: 9, weight: .semibold)).frame(width: 12, height: 19)
                }.buttonStyle(.plain).foregroundStyle(.secondary).accessibilityLabel("\(expanded ? "Collapse" : "Expand") \(source.sourceLabel)")
                Text(source.sourceLabel).font(.system(size: 10.5, weight: .semibold, design: .monospaced)).foregroundStyle(Color.lemmaOlive)
                    .padding(.horizontal, 5).padding(.vertical, 3).background(Color.lemmaOlive.opacity(0.09), in: RoundedRectangle(cornerRadius: 3))
                VStack(alignment: .leading, spacing: 3) {
                    Text(source.title).font(.system(size: 12, weight: .medium)).lineLimit(expanded ? nil : 2)
                    Text("\(source.bookTitle) · p. \(source.anchor.pageLabel)").font(.system(size: 10.5)).foregroundStyle(.secondary).lineLimit(1)
                }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle()).onTapGesture { expanded.toggle() }
                Button { store.openProjectPassage(source, projectID: projectID) } label: { Image(systemName: "arrow.up.forward") }
                    .buttonStyle(.borderless).help("Open the exact source beside this project").accessibilityLabel("Open \(source.sourceLabel) in the book")
            }
            if expanded {
                if let image = NSImage(contentsOf: store.projectRepository.imageURL(projectID, name: source.anchor.imageName)) {
                    Image(nsImage: image).resizable().scaledToFit().frame(maxWidth: .infinity, maxHeight: 220)
                        .background(.white).accessibilityLabel("Original crop of \(source.sourceLabel)")
                }
                if !source.anchor.quote.isEmpty {
                    DisclosureGroup("Extracted text") {
                        Text(source.anchor.quote).font(.system(size: 11.5)).textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading).padding(.top, 5)
                    }.font(.caption).foregroundStyle(.secondary)
                }
                TextField("Why this source matters…", text: Binding(get: {
                    store.project(projectID)?.passages.first { $0.id == source.id }?.annotation ?? ""
                }, set: { value in
                    store.updateProject(projectID) { project in
                        if let index = project.passages.firstIndex(where: { $0.id == source.id }) { project.passages[index].annotation = value }
                    }
                }), axis: .vertical).textFieldStyle(.plain).font(.callout).lineLimit(2...8)
                    .accessibilityLabel("Annotation for \(source.sourceLabel)")
                HStack {
                    Button("Append citation") { store.appendProjectCitation(source, projectID: projectID) }
                    Button("Copy citation") {
                        NSPasteboard.general.clearContents(); NSPasteboard.general.setString(source.citation, forType: .string)
                    }
                    Spacer()
                    Button { store.removeProjectPassage(source.id, projectID: projectID) } label: { Image(systemName: "minus.circle") }
                        .help("Remove passage · ⌘Z to undo").accessibilityLabel("Remove \(source.sourceLabel)")
                }.buttonStyle(.borderless).font(.caption)
            }
        }.padding(12)
    }
}
