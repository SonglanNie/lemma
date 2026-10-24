import AppKit
import PDFKit
import LemmaCore

@MainActor
extension StudyStore {
    var currentProject: ResearchProject? { selectedProjectID.flatMap { project($0) } }
    var activeProjects: [ResearchProject] { projects.filter { !$0.archived } }
    func project(_ id: UUID) -> ResearchProject? { projects.first { $0.id == id } }

    @discardableResult
    func newProject(title: String = "Untitled Project", question: String = "") -> UUID? {
        guard app.projectsWritable else { return nil }
        let project = ResearchProject(title: title, question: question, bookIDs: workspace.map { [$0.id] } ?? [])
        projects.insert(project, at: 0); app.projectsDirty = true
        app.flushProjects(); openProject(project.id); reveal(.projects)
        return project.id
    }

    func openProject(_ id: UUID) {
        guard project(id)?.archived == false else { return }
        selectedProjectID = id
        if focusMode { toggleFocus() }
        showSideEditor(.project(id))
    }

    func addBookToProject(_ bookID: String, projectID: UUID) {
        app.updateProject(projectID) { if !$0.bookIDs.contains(bookID) { $0.bookIDs.append(bookID) } }
        app.flushProjects()
    }

    func removeBookFromProject(_ bookID: String, projectID: UUID) {
        app.updateProject(projectID) { $0.bookIDs.removeAll { $0 == bookID } }
        app.flushProjects()
    }

    /// Archive is reversible and leaves the project's text and all its source images on disk.
    func archiveProject(_ id: UUID, archived: Bool) {
        app.updateProject(id) { $0.archived = archived }; app.flushProjects()
        if archived {
            closeSideEditor("project:\(id)")
            if selectedProjectID == id { selectedProjectID = nil }
        } else { openProject(id) }
        saveWorkbench()
    }

    /// Capture into the project rather than creating a question note in the book.
    func collectSelection(projectID: UUID? = nil) {
        guard let book = workspace, let document, let (pageIndex, rectangle, quote) = reader.selection,
              let page = document.page(at: pageIndex), app.projectsWritable else { return }
        let id = projectID ?? selectedProjectID ?? newProject()
        guard let id, let project = project(id) else { return }
        do {
            let data = try PDFRegionRenderer.png(page: page, region: PageRegion(rectangle))
            let name = "\(UUID().uuidString).png"
            try app.projectRepository.saveImage(data, projectID: id, name: name)
            let title = labLabel(pageIndex: pageIndex, region: rectangle, page: page)
            let anchor = SourceAnchor(pageIndex: pageIndex, pageLabel: printedLabel(for: pageIndex) ?? String(pageIndex + 1),
                                      region: PageRegion(rectangle), quote: quote, imageName: name)
            let source = ProjectPassage(number: project.nextSourceNumber, bookID: book.id, bookTitle: book.title,
                title: title, section: breadcrumb().last?.title ?? "", anchor: anchor)
            app.updateProject(id) { $0.collect(source) }; app.flushProjects()
            openProject(id)
            status = "\(source.sourceLabel) collected in \(project.title)."
        } catch { self.error = "Could not collect the passage: \(error.localizedDescription)" }
    }

    func collectNote(_ note: StudyNote, projectID: UUID) {
        guard let book = workspace, let project = project(projectID), app.projectsWritable else { return }
        do {
            let data = try Data(contentsOf: repository.assetURL(workspaceID: book.id, name: note.anchor.imageName))
            let name = "\(UUID().uuidString).png"
            try app.projectRepository.saveImage(data, projectID: projectID, name: name)
            var anchor = note.anchor; anchor.imageName = name
            anchor.pageLabel = printedLabel(for: anchor.pageIndex) ?? anchor.pageLabel
            let source = ProjectPassage(number: project.nextSourceNumber, bookID: book.id, bookTitle: book.title,
                title: note.title, section: "", anchor: anchor, annotation: note.body)
            app.updateProject(projectID) { $0.collect(source) }; app.flushProjects(); openProject(projectID)
        } catch { self.error = "Could not collect the note's source: \(error.localizedDescription)" }
    }

    func appendProjectCitation(_ source: ProjectPassage, projectID: UUID) {
        app.updateProject(projectID) { $0.synthesis += ($0.synthesis.isEmpty ? "" : "\n\n") + source.citation + " " }
    }

    func removeProjectPassage(_ passageID: UUID, projectID: UUID, undoManager: UndoManager? = nil) {
        guard let source = project(projectID)?.passages.first(where: { $0.id == passageID }),
              let index = project(projectID)?.passages.firstIndex(where: { $0.id == passageID }) else { return }
        let undoManager = undoManager ?? mainWindow?.undoManager
        app.updateProject(projectID) { $0.passages.removeAll { $0.id == passageID } }; app.flushProjects()
        undoManager?.registerUndo(withTarget: self) { store in
            MainActor.assumeIsolated {
                store.app.updateProject(projectID) { $0.passages.insert(source, at: min(index, $0.passages.count)) }
                store.app.flushProjects()
                // Undoing registers the removal again, so Redo removes the passage once more.
                undoManager?.registerUndo(withTarget: store) { store in
                    MainActor.assumeIsolated { store.removeProjectPassage(passageID, projectID: projectID, undoManager: undoManager) }
                }
                undoManager?.setActionName("Remove Collected Passage")
            }
        }
        undoManager?.setActionName("Remove Collected Passage")
    }

    /// Keep the dossier beside the source when following a source into another book.
    func openProjectPassage(_ source: ProjectPassage, projectID: UUID) {
        guard let book = library.first(where: { $0.id == source.bookID }) else {
            error = "This source's book is not in the library on this Mac. The saved crop is still in the project."; return
        }
        let show = { (store: StudyStore) in
            guard store.workspace?.id == source.bookID else { return }
            store.openProject(projectID)
            // Once the page view shows the source's book (its file may take a moment to be read), never inside another one.
            store.whenShowing(source.bookID) { $0.reader.go(to: source.anchor) }
        }
        if workspace?.id == source.bookID { show(self) } else { reopenBook(book) { store in if let store { show(store) } } }
    }

    /// The books a search reads, each book in front of a window as it is now (its library row follows it at a distance).
    func booksForSearch(_ scope: PageSearchScope) -> [StudyWorkspace] {
        let current = app.current
        switch scope {
        case .library: return library.map(current)
        case .current: return workspace.map { [$0] } ?? []
        case .project:
            let ids = Set(currentProject?.bookIDs ?? [])
            return library.filter { ids.contains($0.id) }.map(current)
        }
    }

    func searchProject(_ id: UUID) {
        selectedProjectID = id; noteSearchScope = .project; pageSearchScope = .project
        searchNotes = true; searchIndexed = false; reveal(.search); searchNoteMeaning()
        saveWorkbench()
    }

    func exportProject(_ id: UUID) {
        guard let project = project(id) else { return }
        app.flushProjects()
        let panel = NSOpenPanel(); panel.canChooseDirectories = true; panel.canChooseFiles = false
        panel.canCreateDirectories = true; panel.prompt = "Export"
        panel.message = "Choose a folder for the project's Markdown, source images and project data."
        if panel.runModal() == .OK, let destination = panel.url {
            let folder = destination.appendingPathComponent("Lemma Research \(ISO8601DateFormatter().string(from: .now).replacingOccurrences(of: ":", with: "-"))")
            do { try app.projectRepository.export(project, to: folder); lastExportURL = folder; status = "Project exported with its sources." }
            catch { self.error = "Could not export the project: \(error.localizedDescription)" }
        }
    }
}
