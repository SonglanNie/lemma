import SwiftUI
import AppKit
import PDFKit
import UniformTypeIdentifiers
import LemmaCore

// MARK: - Notebook editor

/// A Lab notebook in the side editor: the passage it came from, then code and text cells with their outputs.
/// Code runs in a local Python process only when the reader runs a cell.
struct LabEditor: View {
    @Bindable var store: StudyStore
    let notebookID: UUID
    @State private var renaming = false
    @State private var title = ""
    @State private var showSource = true

    private var session: LabSession? { store.lab.sessions[notebookID] }

    var body: some View {
        if let notebook = store.lab(notebookID) {
            VStack(spacing: 0) {
                header(notebook)
                Divider()
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 12) {
                            if let source = notebook.source {
                                LabSourceCard(store: store, source: source, expanded: $showSource)
                            }
                            ForEach(notebook.cells) { cell in
                                LabCellView(store: store, notebookID: notebookID, cell: cell, session: session).id(cell.id)
                            }
                            addBar(after: notebook.cells.last?.id)
                        }
                        .padding(.horizontal, 14).padding(.vertical, 12)
                    }
                    .onChange(of: store.lab.focusRequest?.token) { _, _ in
                        if let id = store.lab.focusRequest?.cellID { withAnimation(.easeOut(duration: 0.15)) { proxy.scrollTo(id, anchor: .center) } }
                    }
                }
                if let message = session?.message { messageBar(message) }
            }
            .frame(minWidth: 340, maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(nsColor: .textBackgroundColor))
            .sheet(isPresented: $renaming) { renameSheet }
        } else {
            PaneEmptyState(symbol: "flask", title: "Notebook closed", message: "This notebook belongs to another book or was deleted.")
        }
    }

    private func header(_ notebook: LabNotebook) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "flask").font(.system(size: 11, weight: .medium)).foregroundStyle(Color.lemmaOlive)
            Text(notebook.title).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                .onTapGesture(count: 2) { title = notebook.title; renaming = true }
                .help("Double-click to rename")
            if let source = notebook.source {
                Text(store.shortPageText(source.pageIndex)).font(.system(size: 11).monospacedDigit()).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 4)
            LabKernelPill(session: session, interpreter: store.lab.interpreter, discovering: store.lab.isDiscovering, problem: store.lab.interpreterProblem)
            Button { store.runAllLabCells(notebookID) } label: { Image(systemName: "forward.end.alt") }
                .help("Run all cells").accessibilityLabel("Run all cells")
            Button { store.interruptLab(notebookID) } label: { Image(systemName: "stop.fill") }
                .disabled(session?.state != .busy).help("Interrupt the running cell").accessibilityLabel("Interrupt")
            Button { store.restartLabKernel(notebookID) } label: { Image(systemName: "arrow.clockwise") }
                .help("Restart Python: clears variables").accessibilityLabel("Restart Python")
            Menu {
                Button("Rename…") { title = notebook.title; renaming = true }
                Button("Clear All Outputs") { store.clearLabOutputs(notebookID) }
                Button("Export as Jupyter Notebook…") { store.exportLab(notebookID) }
                Divider()
                Button("Stop Python") { store.stopLabKernel(notebookID) }.disabled(session?.kernel == nil)
                Button("Delete Notebook", role: .destructive) { store.deleteLab(notebookID) }
            } label: { Image(systemName: "ellipsis") }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).frame(width: 20).accessibilityLabel("Notebook actions")
            Button { store.closeLabEditor() } label: { Image(systemName: "xmark") }
                .help("Close the notebook (Python keeps its variables until the book closes)").accessibilityLabel("Close notebook")
        }
        .buttonStyle(.borderless).font(.system(size: 11, weight: .medium))
        .padding(.horizontal, 10).frame(height: 28)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func addBar(after cellID: UUID?) -> some View {
        HStack(spacing: 10) {
            Button { store.addLabCell(notebookID, kind: .code, after: cellID) } label: { Label("Code", systemImage: "plus") }
            Button { store.addLabCell(notebookID, kind: .text, after: cellID) } label: { Label("Text", systemImage: "plus") }
            Spacer()
            Text("⇧↩ run and go on · ⌘↩ run · ⌥↩ run and add").font(.caption).foregroundStyle(.tertiary)
        }
        .buttonStyle(.borderless).font(.callout)
        .padding(.top, 2)
    }

    private func messageBar(_ message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "info.circle").foregroundStyle(Color.lemmaOlive)
            Text(message).font(.caption).lineLimit(3).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            if session?.offersSetup == true {
                Button("Set Up Python for the Lab…") { store.showPythonSetup() }.font(.caption)
            } else if message.contains("Restart") {
                Button("Restart") { store.restartLabKernel(notebookID) }.font(.caption)
            }
            Button { session?.show(nil) } label: { Image(systemName: "xmark").font(.system(size: 9, weight: .bold)) }.buttonStyle(.borderless)
        }
        .padding(.horizontal, 12).padding(.vertical, 7)
        .background(Color.lemmaOlive.opacity(0.08))
        .overlay(alignment: .top) { Divider() }
    }

    private var renameSheet: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Notebook title").font(.title2.weight(.semibold))
            TextField("Title", text: $title).textFieldStyle(.roundedBorder)
            HStack {
                Spacer()
                Button("Cancel") { renaming = false }.keyboardShortcut(.cancelAction)
                Button("Rename") {
                    let value = title.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !value.isEmpty { store.updateLab(notebookID) { $0.title = value } }
                    renaming = false
                }.keyboardShortcut(.defaultAction)
            }
        }.padding(24).frame(width: 360)
    }
}

/// The passage a notebook came from, rendered from the original page, with a way back to it.
struct LabSourceCard: View {
    @Bindable var store: StudyStore
    let source: LabSource
    @Binding var expanded: Bool
    /// A smaller crop, where the card sits above an editor that needs the height (a derivation).
    var compact = false
    @State private var image: NSImage?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Button { withAnimation(.easeOut(duration: 0.12)) { expanded.toggle() } } label: {
                    Image(systemName: "chevron.right").font(.system(size: 9, weight: .bold)).rotationEffect(.degrees(expanded ? 90 : 0))
                }.buttonStyle(.borderless).accessibilityLabel(expanded ? "Hide source" : "Show source")
                Image(systemName: "text.quote").font(.system(size: 10)).foregroundStyle(.secondary)
                Text(source.label).font(.system(size: 11.5, weight: .semibold)).lineLimit(1).layoutPriority(-1)
                Text(store.pageText(source.pageIndex)).font(.system(size: 11).monospacedDigit()).foregroundStyle(.secondary).lineLimit(1).fixedSize()
                Spacer()
                Button("Go to source") {
                    if let region = source.region, let page = store.document?.page(at: source.pageIndex) {
                        store.reader.view?.go(to: region.rect, on: page)
                        store.reader.flash(region.rect, onPage: source.pageIndex)
                    } else { store.reader.goToPage(source.pageIndex + 1) }
                }.buttonStyle(.link).font(.caption)
            }
            if expanded, let image {
                Image(nsImage: image).resizable().scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: compact ? 84 : 130, alignment: .leading)
                    .padding(8).background(Color.white, in: RoundedRectangle(cornerRadius: 5))
                    .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color(nsColor: .separatorColor), lineWidth: 0.5))
                    .accessibilityLabel("Source passage from the book")
            }
        }
        .padding(10)
        .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 8))
        .task(id: "\(source.pageIndex)-\(source.region?.x ?? 0)-\(source.region?.y ?? 0)") { render() }
    }

    private func render() {
        guard let region = source.region, let page = store.document?.page(at: source.pageIndex),
              let data = try? PDFRegionRenderer.png(page: page, region: region) else { image = nil; return }
        image = NSImage(data: data)
    }
}

/// The kernel's state as a small pill: Python version, idle or running.
struct LabKernelPill: View {
    let session: LabSession?
    let interpreter: LabInterpreter?
    let discovering: Bool
    /// Why Settings › Lab › Python Path is not used, when it is not.
    var problem: String? = nil
    @Environment(\.theme) private var theme

    var body: some View {
        let state = session?.state ?? .stopped
        HStack(spacing: 5) {
            if state == .busy || state == .starting || (discovering && session == nil) {
                ProgressView().controlSize(.mini).scaleEffect(0.8).frame(width: 10, height: 10)
            } else {
                Circle().fill(state == .idle ? theme[.notebookStatusSuccessIconForeground] : theme[.descriptionForeground]).frame(width: 7, height: 7)
            }
            Text(text(state)).font(.system(size: 10.5).monospacedDigit()).lineLimit(1)
        }
        .foregroundStyle(theme[.foreground])
        .padding(.horizontal, 7).frame(height: 18)
        .background(theme[.foreground].opacity(0.07), in: Capsule())
        .help((interpreter.map { "\($0.summary)\n\($0.path)" } ?? "Python for the Lab") + (problem.map { "\n\n\($0)" } ?? ""))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Python: \(text(state))")
    }

    private func text(_ state: LabKernelState) -> String {
        let version = session?.python ?? interpreter?.version
        switch state {
        case .stopped: return version.map { "Python \($0)" } ?? (discovering ? "Finding Python…" : "No Python")
        case .starting: return "Starting…"
        case .idle: return "Ready"
        case .busy: return "Running…"
        }
    }
}

// MARK: - Cells

struct LabCellView: View {
    @Bindable var store: StudyStore
    let notebookID: UUID
    let cell: LabCell
    let session: LabSession?
    @State private var hovering = false
    @State private var editingText = false

    private var selected: Bool { store.lab.selectedCellID == cell.id }
    private var running: Bool { session?.runningCellID == cell.id }
    private var queued: Bool { session?.isPending(cell.id) == true }

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            gutter.frame(width: 38)
            VStack(alignment: .leading, spacing: 0) {
                if cell.kind == .code { codeBody } else { textBody }
            }
            .background(cell.kind == .code ? Color.primary.opacity(0.045) : Color.clear, in: RoundedRectangle(cornerRadius: 7))
            .overlay(RoundedRectangle(cornerRadius: 7).stroke(selected ? Color.lemmaOlive.opacity(0.7) : (cell.kind == .code ? Color(nsColor: .separatorColor).opacity(0.7) : .clear), lineWidth: selected ? 1.2 : 0.5))
            .overlay(alignment: .topTrailing) { if hovering || selected { cellToolbar.offset(y: -11).padding(.trailing, 10) } }
        }
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture { store.lab.selectedCellID = cell.id }
    }

    @ViewBuilder private var gutter: some View {
        VStack(spacing: 4) {
            if cell.kind == .code {
                if running {
                    ProgressView().controlSize(.small).frame(height: 22)
                } else if hovering || selected {
                    Button { store.runLabCell(notebookID, cellID: cell.id) } label: {
                        Image(systemName: "play.fill").font(.system(size: 10)).frame(width: 22, height: 22)
                            .background(Color.lemmaOlive.opacity(0.14), in: Circle())
                    }.buttonStyle(.plain).foregroundStyle(Color.lemmaOlive).help("Run this cell · ⌘↩").accessibilityLabel("Run cell")
                } else {
                    Text(queued ? "[*]" : cell.executionCount.map { "[\($0)]" } ?? "[ ]")
                        .font(.system(size: 10.5).monospacedDigit()).foregroundStyle(.tertiary).frame(height: 22)
                }
                if !running, let duration = cell.duration, cell.executionCount != nil, hovering || selected {
                    Text(duration < 1 ? "\(Int(duration * 1000)) ms" : String(format: "%.1f s", duration))
                        .font(.system(size: 9).monospacedDigit()).foregroundStyle(.tertiary)
                }
            }
        }
        .padding(.top, 4)
    }

    @ViewBuilder private var codeBody: some View {
        LabCodeEditor(text: Binding(
                get: { store.lab(notebookID)?.cells.first { $0.id == cell.id }?.source ?? "" },
                set: { value in store.updateLab(notebookID) { notebook in
                    if let index = notebook.cells.firstIndex(where: { $0.id == cell.id }) { notebook.cells[index].source = value }
                } }),
            focusToken: store.lab.focusRequest?.cellID == cell.id ? store.lab.focusRequest?.token ?? 0 : 0,
            onRun: { action in store.runLabCell(notebookID, cellID: cell.id, action: action) },
            onFocus: { store.lab.selectedCellID = cell.id },
            onMove: { delta in moveFocus(delta) },
            onComplete: { prefix, reply in
                Task { @MainActor in reply(await store.labCompletions(notebookID, prefix: prefix)) }
            })
        .frame(maxWidth: .infinity, alignment: .leading)
        if !cell.outputs.isEmpty {
            Divider().opacity(0.6)
            LabOutputsView(store: store, outputs: cell.outputs, executionCount: cell.executionCount,
                           askAboutError: { store.askAboutLabError(notebookID, cellID: cell.id) }, notebookID: notebookID)
                .padding(.horizontal, 10).padding(.vertical, 8)
        }
    }

    @ViewBuilder private var textBody: some View {
        if editingText || cell.source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            VStack(alignment: .trailing, spacing: 6) {
                TextEditor(text: Binding(
                    get: { store.lab(notebookID)?.cells.first { $0.id == cell.id }?.source ?? "" },
                    set: { value in store.updateLab(notebookID) { notebook in
                        if let index = notebook.cells.firstIndex(where: { $0.id == cell.id }) { notebook.cells[index].source = value }
                    } }))
                    .font(.system(size: 12).monospaced())
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 70, maxHeight: 260)
                    .padding(6)
                    .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 6))
                    .accessibilityLabel("Text cell, Markdown and LaTeX")
                Button("Done") { editingText = false }.font(.caption).buttonStyle(.borderless).help("Show the formatted text")
            }.padding(4)
        } else {
            MathPreview(text: cell.source)
                .padding(.horizontal, 4)
                .contentShape(Rectangle())
                .onTapGesture(count: 2) { editingText = true }
                .help("Double-click to edit · Markdown and LaTeX")
        }
    }

    private var cellToolbar: some View {
        HStack(spacing: 2) {
            if cell.kind == .text {
                toolbarButton(editingText ? "checkmark" : "pencil", help: editingText ? "Done" : "Edit text") { editingText.toggle() }
            }
            toolbarButton("arrow.up", help: "Move up") { store.moveLabCell(notebookID, cellID: cell.id, by: -1) }
            toolbarButton("arrow.down", help: "Move down") { store.moveLabCell(notebookID, cellID: cell.id, by: 1) }
            toolbarButton("plus", help: "Add a code cell below") { store.addLabCell(notebookID, kind: .code, after: cell.id) }
            toolbarButton("trash", help: "Delete cell") { store.deleteLabCell(notebookID, cellID: cell.id) }
        }
        .padding(2)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color(nsColor: .separatorColor), lineWidth: 0.5))
    }

    private func toolbarButton(_ symbol: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: symbol).font(.system(size: 10, weight: .medium)).frame(width: 20, height: 18) }
            .buttonStyle(.borderless).help(help).accessibilityLabel(help)
    }

    private func moveFocus(_ delta: Int) {
        guard let cells = store.lab(notebookID)?.cells, let index = cells.firstIndex(where: { $0.id == cell.id }) else { return }
        let target = index + delta
        guard cells.indices.contains(target), cells[target].kind == .code else { return }
        store.lab.requestFocus(cells[target].id)
    }
}

/// A cell's outputs: text streams, the value of the last expression, figures and errors.
struct LabOutputsView: View {
    @Bindable var store: StudyStore
    let outputs: [LabOutput]
    let executionCount: Int?
    var askAboutError: (() -> Void)? = nil
    var notebookID: UUID? = nil
    /// In the console, outputs read as the interpreter prints them: no Out[n], tracebacks as text.
    var console = false
    @State private var expanded: Set<Int> = []
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: console ? 2 : 8) {
            ForEach(Array(outputs.enumerated()), id: \.offset) { offset, output in
                switch output.kind {
                case .stdout, .stderr, .result:
                    textOutput(output, offset: offset)
                case .error:
                    if console { consoleError(output) } else { errorOutput(output, offset: offset) }
                case .image:
                    if let name = output.imageName, let workspaceID = store.workspace?.id,
                       let image = store.lab.image(named: name, workspaceID: workspaceID, repository: store.repository) {
                        LabFigure(image: image, name: name, store: store, notebookID: notebookID)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func textOutput(_ output: LabOutput, offset: Int) -> some View {
        let limit = 6000
        let long = output.text.count > limit && !expanded.contains(offset)
        let text = long ? String(output.text.prefix(limit)) : output.text
        return VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                if output.kind == .result && !console {
                    Text("Out[\(executionCount.map(String.init) ?? " ")]").font(.system(size: 10).monospacedDigit())
                        .foregroundStyle(theme.rgba(.terminalAnsiCyan).readable(on: theme.rgba(.terminalBackground)).color)
                }
                Text(text.hasSuffix("\n") ? String(text.dropLast()) : text)
                    .font(Font(console ? LabCodeStyle.font : LabCodeStyle.outputFont))
                    .foregroundStyle(theme[output.kind == .stderr ? .editorWarningForeground : (console ? .terminalForeground : .editorForeground)])
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if long {
                Button("Show all \(output.text.count.formatted()) characters") { expanded.insert(offset) }.buttonStyle(.link).font(.caption)
            }
        }
    }

    /// `Traceback (most recent call last):`, the frames, then the exception line in the error colour.
    private func consoleError(_ output: LabOutput) -> some View {
        let detail = (output.detail ?? "").trimmingCharacters(in: .newlines)
        var text = AttributedString(detail.isEmpty ? output.text : "Traceback (most recent call last):\n" + detail)
        text.foregroundColor = theme[.errorForeground]
        return Text(text).font(Font(LabCodeStyle.font))
            .textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
    }

    private func errorOutput(_ output: LabOutput, offset: Int) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline) {
                Label(output.text, systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 12, weight: .medium)).foregroundStyle(theme[.errorForeground])
                    .textSelection(.enabled)
                Spacer(minLength: 8)
                if let ask = askAboutError, !output.text.hasPrefix("KeyboardInterrupt"), !output.text.hasPrefix("Stopped") {
                    Button("Ask an assistant…", action: ask).buttonStyle(.link).font(.caption)
                        .help("Prepare a question with this cell's code, the error and the passage, and review it before sending it to the assistant you choose. The answer returns to a note, and its corrected cell can come back here.")
                }
            }
            if let detail = output.detail, !detail.isEmpty {
                DisclosureGroup(isExpanded: Binding(get: { expanded.contains(offset) }, set: { if $0 { expanded.insert(offset) } else { expanded.remove(offset) } })) {
                    Text(detail).font(Font(LabCodeStyle.outputFont)).foregroundStyle(theme[.descriptionForeground]).textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true).padding(.top, 4)
                } label: { Text("Traceback").font(.caption).foregroundStyle(theme[.foreground]) }
            }
        }
        .padding(8)
        .background(theme[.errorForeground].opacity(0.07), in: RoundedRectangle(cornerRadius: 6))
    }
}

/// A figure produced by a cell, on white like the page, with Copy and Save.
struct LabFigure: View {
    let image: NSImage
    let name: String
    let store: StudyStore
    var notebookID: UUID?
    @State private var hovering = false

    var body: some View {
        Image(nsImage: image).resizable().interpolation(.high).scaledToFit()
            .frame(maxWidth: min(image.size.width, 640), maxHeight: 460, alignment: .leading)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 4))
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .overlay(alignment: .topTrailing) {
                if hovering, let notebookID {
                    Button { store.pinLabFigure(name, notebookID: notebookID) } label: {
                        Label("Pin beside the page", systemImage: "pin").font(.caption)
                    }
                    .buttonStyle(.bordered).controlSize(.small).padding(6)
                    .help("Keep this figure in the book's margin, beside the passage it illustrates")
                }
            }
            .onHover { hovering = $0 }
            .contextMenu {
                if let notebookID { Button("Pin Beside the Page") { store.pinLabFigure(name, notebookID: notebookID) } }
                Button("Copy Figure") { NSPasteboard.general.clearContents(); NSPasteboard.general.writeObjects([image]) }
                Button("Save Figure…") { store.saveLabFigure(name, notebookID: notebookID) }
            }
            .accessibilityLabel("Figure output")
    }
}

// MARK: - Sidebar

/// The Lab view in the sidebar: Python's status and the book's notebooks.
struct LabSidebar: View {
    @Bindable var store: StudyStore

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            pythonCard.padding(12)
            HStack(spacing: 8) {
                Button { store.newLab() } label: { Label("Notebook", systemImage: "plus") }
                    .disabled(store.workspace == nil).help("A Python notebook beside the page")
                Button { store.deriveSelection() } label: { Label("Derivation", systemImage: "plus") }
                    .disabled(store.workspace == nil).help("A derivation checked step by step · ⌥⌘E")
                Spacer()
                if store.reader.hasSelection {
                    Button { store.sendSelectionToLab() } label: { Label("Selection", systemImage: "arrow.right.doc.on.clipboard") }
                        .help("Send the selected passage to the Lab")
                }
            }
            .buttonStyle(.borderless).font(.callout)
            .padding(.horizontal, 14).padding(.bottom, 8)
            Divider()
            if store.workspace?.labs.isEmpty != false && store.workspace?.derivations.isEmpty != false {
                PaneEmptyState(symbol: "flask", title: "Experiment with the book",
                               message: "Select an equation or a passage and choose Lab to try it in Python, or Derive to work it through step by step; every line you write is checked as you type.")
            } else {
                List {
                    if let derivations = store.workspace?.derivations, !derivations.isEmpty {
                        Section("Derivations") { ForEach(derivations) { derivation in derivationRow(derivation) } }
                    }
                    if let labs = store.workspace?.labs, !labs.isEmpty {
                        Section("Notebooks") { ForEach(labs) { notebook in row(notebook) } }
                    }
                }.listStyle(.sidebar).scrollContentBackground(.hidden)
            }
        }
        .task { await store.discoverPython() }
    }

    private var pythonCard: some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: "terminal").font(.system(size: 13)).foregroundStyle(Color.lemmaOlive).frame(width: 18)
            VStack(alignment: .leading, spacing: 3) {
                let setup = store.lab.setup
                if setup.isRunning {
                    Text("Setting up Python…").font(.callout.weight(.medium))
                    ProgressView(value: setup.progress.fraction).controlSize(.small)
                    Button("Show Progress") { store.showPythonSetup() }.buttonStyle(.link).font(.caption)
                } else if store.lab.isDiscovering && store.lab.interpreters.isEmpty {
                    Text("Looking for Python…").font(.callout)
                } else if let interpreter = store.lab.interpreter {
                    Text("Python \(interpreter.version)").font(.callout.weight(.medium))
                    Text(packageLine(interpreter)).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    if let problem = store.lab.interpreterProblem {
                        Text(problem).font(.caption).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
                    }
                    if !interpreter.isScientific {
                        Text("NumPy and Matplotlib are missing from this Python.").font(.caption).foregroundStyle(.orange)
                            .fixedSize(horizontal: false, vertical: true)
                        Button("Set Up Python for the Lab…") { store.showPythonSetup() }.buttonStyle(.link).font(.caption)
                    }
                } else {
                    Text("No Python 3 found").font(.callout.weight(.medium))
                    Text("Lemma's notebooks need Python 3 with NumPy and Matplotlib.").font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Button("Set Up Python for the Lab…") { store.showPythonSetup() }.buttonStyle(.link).font(.caption)
                }
                SettingsLink { Text("Lab settings…") }.buttonStyle(.link).font(.caption)
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
    }

    private func packageLine(_ interpreter: LabInterpreter) -> String {
        let names = ["numpy", "scipy", "matplotlib", "pandas", "sklearn", "sympy", "statsmodels"].filter { interpreter.packages[$0] != nil }
        let gentle = store.lab.gentle ? " · gentle" : ""
        return (names.isEmpty ? "No scientific packages" : names.joined(separator: " · ")) + gentle
    }

    private func derivationRow(_ derivation: Derivation) -> some View {
        let open = store.openDerivationID == derivation.id
        let report = store.derivationReports[derivation.id]
        return Button { store.openDerivation(derivation.id) } label: {
            HStack(alignment: .top, spacing: 9) {
                Image(systemName: "function").font(.system(size: 12)).foregroundStyle(open ? Color.lemmaOlive : .secondary).padding(.top, 1)
                VStack(alignment: .leading, spacing: 3) {
                    Text(derivation.title).font(.system(size: 12, weight: open ? .semibold : .regular)).lineLimit(2)
                    HStack(spacing: 6) {
                        if let origin = derivation.origin { Text(store.shortPageText(origin.pageIndex)).monospacedDigit() }
                        if let report {
                            if report.fails > 0 { Label("\(report.fails)", systemImage: "xmark.circle.fill").foregroundStyle(.red) }
                            Label("\(report.holds)", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                        }
                        Text(derivation.updatedAt.formatted(.relative(presentation: .named)))
                    }.font(.caption).foregroundStyle(.secondary).lineLimit(1).labelStyle(.titleAndIcon)
                }
                Spacer(minLength: 0)
            }.padding(.vertical, 3).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .listRowBackground(open ? Color.lemmaOlive.opacity(0.12) : Color.clear)
        .task(id: derivation.id) { if store.derivationReports[derivation.id] == nil { store.checkDerivation(derivation.id, delay: 0) } }
        .contextMenu {
            Button("Open") { store.openDerivation(derivation.id) }
            if let origin = derivation.origin { Button("Go to Source") { store.reader.goToPage(origin.pageIndex + 1) } }
            Divider()
            Button("Delete Derivation", role: .destructive) { store.deleteDerivation(derivation.id) }
        }
    }

    private func row(_ notebook: LabNotebook) -> some View {
        let open = store.openLabID == notebook.id
        let session = store.lab.sessions[notebook.id]
        return Button { store.openLabNotebook(notebook.id) } label: {
            HStack(alignment: .top, spacing: 9) {
                Image(systemName: "flask").font(.system(size: 12)).foregroundStyle(open ? Color.lemmaOlive : .secondary).padding(.top, 1)
                VStack(alignment: .leading, spacing: 3) {
                    Text(notebook.title).font(.system(size: 12, weight: open ? .semibold : .regular)).lineLimit(2)
                    HStack(spacing: 6) {
                        if let source = notebook.source { Text(store.shortPageText(source.pageIndex)).monospacedDigit() }
                        Text("\(notebook.cells.count) \(notebook.cells.count == 1 ? "cell" : "cells")")
                        Text(notebook.updatedAt.formatted(.relative(presentation: .named)))
                        if session?.state == .busy { Image(systemName: "circle.dotted").foregroundStyle(Color.lemmaOlive) }
                    }.font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 0)
            }.padding(.vertical, 3).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .listRowBackground(open ? Color.lemmaOlive.opacity(0.12) : Color.clear)
        .contextMenu {
            Button("Open") { store.openLabNotebook(notebook.id) }
            if let source = notebook.source { Button("Go to Source") { store.reader.goToPage(source.pageIndex + 1) } }
            Button("Export as Jupyter Notebook…") { store.exportLab(notebook.id) }
            Divider()
            Button("Delete Notebook", role: .destructive) { store.deleteLab(notebook.id) }
        }
    }
}

// MARK: - Console

/// A local Python console in the manner of the interactive interpreter: one monospaced transcript with `>>>` and
/// `...` prompts, and the live prompt at its end. Return runs complete input; ⇧↩ adds a line; ↑/↓ recall history;
/// Tab completes.
struct ConsolePanel: View {
    @Bindable var store: StudyStore
    @Environment(\.theme) private var theme
    @State private var input = ""
    @State private var focus = 1
    @State private var historyIndex: Int?

    private static let promptID = "console-prompt"

    private var promptColor: Color {
        theme.rgba(.terminalAnsiCyan).readable(on: theme.rgba(.terminalBackground)).color
    }

    var body: some View {
        if store.workspace == nil {
            PaneEmptyState(symbol: "terminal", title: "Python console", message: "Open a book to compute beside it.")
        } else if let sessionID = store.consoleTarget {
            let entries = store.lab.consoles[sessionID] ?? []
            let session = store.lab.sessions[sessionID]
            VStack(spacing: 0) {
                toolbar(sessionID: sessionID, session: session, hasEntries: !entries.isEmpty)
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 0) {
                            banner(session: session)
                            LazyVStack(alignment: .leading, spacing: 0) {
                                ForEach(entries) { entry in
                                    ConsoleEntryRow(store: store, entry: entry, promptColor: promptColor)
                                        .padding(.bottom, 2)
                                        .id(entry.id)
                                }
                            }
                            prompt(sessionID: sessionID, busy: session?.state == .busy)
                                .id(Self.promptID)
                        }
                        .padding(.horizontal, 14).padding(.top, 6).padding(.bottom, 10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .scrollBounceBehavior(.basedOnSize)
                    // As in a terminal, a click anywhere in the transcript's empty space returns to the prompt.
                    .background(Color.clear.contentShape(Rectangle()).onTapGesture { focus += 1 })
                    .onChange(of: entries.last?.outputs) { _, _ in proxy.scrollTo(Self.promptID, anchor: .bottom) }
                    .onChange(of: entries.count) { _, _ in proxy.scrollTo(Self.promptID, anchor: .bottom) }
                }
            }
            .foregroundStyle(theme[.terminalForeground])
            .background(theme[.terminalBackground])
            .onAppear { focus += 1 }
            .task { _ = await store.discoverPython() }
        }
    }

    /// Session and actions in one quiet line, like a terminal's title: no status badge while Python is idle.
    private func toolbar(sessionID: UUID, session: LabSession?, hasEntries: Bool) -> some View {
        let busy = session?.state == .busy
        return HStack(spacing: 6) {
            Text("Python · " + (store.openLab?.title ?? "Book session"))
                .font(.system(size: 11)).foregroundStyle(theme[.descriptionForeground]).lineLimit(1)
                .help(store.openLab == nil ? "Variables stay available for this book while Lemma is open" : "Shares the open notebook's variables")
            Spacer(minLength: 8)
            if busy || session?.state == .starting {
                Text(busy ? "Running…" : "Starting…").font(.system(size: 11)).foregroundStyle(theme[.descriptionForeground])
            }
            VSIconButton(icon: "debug-stop", help: "Interrupt Python (⌃C)", enabled: busy) {
                store.interruptLab(sessionID)
            }
            VSIconButton(icon: "clear-all", help: "Clear console output (keep variables)", enabled: hasEntries) {
                store.clearConsole()
            }
        }
        .padding(.leading, 14).padding(.trailing, 8).frame(height: 26)
    }

    /// The interpreter's greeting, as `python3` prints it on start.
    private func banner(session: LabSession?) -> some View {
        let version = session?.python ?? store.lab.interpreter?.version
        let first: String
        if let version {
            first = "Python \(version)" + (store.lab.interpreter.map { " (\($0.path))" } ?? "") + " on darwin"
        } else {
            first = store.lab.isDiscovering ? "Looking for Python…" : "No Python found. Set it up for the Lab, or choose an interpreter in Settings › Lab."
        }
        let second = store.openLab == nil
            ? "# Variables persist for this book while Lemma is open."
            : "# Shares the variables of the open notebook."
        let offerSetup = !store.lab.isDiscovering && store.lab.hasDiscovered && store.lab.interpreter?.isScientific != true && !store.lab.setup.isRunning
        return VStack(alignment: .leading, spacing: 4) {
            Text(first + "\n" + second)
                .font(Font(LabCodeStyle.outputFont)).foregroundStyle(theme[.descriptionForeground])
                .textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
            if offerSetup {
                Button("Set Up Python for the Lab…") { store.showPythonSetup() }.buttonStyle(.link).font(.caption)
            }
        }
        .padding(.bottom, 6)
    }

    private func prompt(sessionID: UUID, busy: Bool) -> some View {
        let lines = max(1, input.components(separatedBy: "\n").count)
        return HStack(alignment: .top, spacing: 0) {
            Text((0..<lines).map { $0 == 0 ? ">>> " : "... " }.joined(separator: "\n"))
                .font(Font(LabCodeStyle.font))
                .foregroundStyle(busy ? theme[.descriptionForeground] : promptColor)
                .accessibilityHidden(true)
            LabCodeEditor(text: $input, focusToken: focus,
                          onRun: { _ in submit() },
                          onMove: { delta in recall(delta) },
                          onTerminalKey: { key in terminalKey(key, sessionID: sessionID) },
                          onComplete: { prefix, reply in
                              Task { @MainActor in reply(await store.labCompletions(sessionID, prefix: prefix)) }
                          },
                          submitsOnReturn: true,
                          inset: .zero, linePadding: 0)
                .frame(maxWidth: .infinity, alignment: .leading)
                .help("Return runs · ⇧Return adds a line · ↑↓ history · Tab completes · ⌃L or clear clears · ⌃C interrupts · ⌃D or exit() ends the session")
        }
    }

    private func submit() {
        let code = input
        guard !code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        input = ""
        historyIndex = nil
        store.submitConsole(code)
    }

    private func terminalKey(_ key: LabTerminalKey, sessionID: UUID) {
        switch key {
        case .clear: store.clearConsole()
        case .interrupt:
            if store.lab.sessions[sessionID]?.state == .busy { store.interruptLab(sessionID) } else { input = ""; historyIndex = nil }
        case .exit: store.endConsoleSession(echo: nil)
        }
    }

    private func recall(_ delta: Int) {
        let history = store.lab.history
        guard !history.isEmpty else { return }
        var index = (historyIndex ?? history.count) + delta
        index = min(max(index, 0), history.count)
        historyIndex = index
        input = index < history.count ? history[index] : ""
    }
}

/// An input echoed after its prompts, then whatever it printed, as the interpreter shows them.
private struct ConsoleEntryRow: View {
    @Bindable var store: StudyStore
    let entry: ConsoleEntry
    let promptColor: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(echo).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
            if !entry.outputs.isEmpty {
                LabOutputsView(store: store, outputs: entry.outputs, executionCount: entry.count, console: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The highlighted code with `>>> ` before its first line and `... ` before the others.
    private var echo: AttributedString {
        var result = AttributedString()
        for (index, line) in entry.code.components(separatedBy: "\n").enumerated() {
            var prompt = AttributedString((index == 0 ? "" : "\n") + (index == 0 ? ">>> " : "... "))
            prompt.font = Font(LabCodeStyle.font)
            prompt.foregroundColor = promptColor
            result += prompt
            result += LabCodeStyle.attributed(line)
        }
        return result
    }
}
