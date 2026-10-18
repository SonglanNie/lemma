import SwiftUI
import AppKit
import LemmaCore

/// UserDefaults keys for reader preferences; every flag defaults to on.
enum LemmaPreferences {
    static let referenceLinks = "referenceLinks"
    static let referenceCounts = "referenceCounts"
    static let hoverPreviews = "hoverPreviews"
    static let quickAskMode = "quickAskMode"
    static let questionProvider = "questions.provider"
    static let contextText = "context.text"
    static let contextSection = "context.section"
    static let contextCited = "context.cited"
    static let contextGlossary = "context.glossary"
    static let contextPins = "context.pins"
    static let pageTheme = "pageTheme"
    static let lineNumbers = "lineNumbers"
    static let pageGap = "pageGap"

    static func flag(_ key: String) -> Bool { UserDefaults.standard.object(forKey: key) as? Bool ?? true }

    /// Points between consecutive pages in every PDF view (PDFView.setPageGap).
    static let pageGapDefault = 8.0

    /// Quick questions send at once unless the reader chose Review (ChatGPT Web only): one default for Settings,
    /// the settings editor and the quick-question popover.
    static let quickAskModeDefault = WebQuestionMode.askAndSave
}

struct SettingsView: View {
    var store: StudyStore? = nil
    @AppStorage(LemmaPreferences.referenceLinks) private var referenceLinks = true
    @AppStorage(LemmaPreferences.referenceCounts) private var referenceCounts = true
    @AppStorage(LemmaPreferences.hoverPreviews) private var hoverPreviews = true
    @AppStorage(LemmaPreferences.quickAskMode) private var quickAskMode = LemmaPreferences.quickAskModeDefault.rawValue
    @AppStorage(LemmaPreferences.questionProvider) private var questionProvider = QuestionProvider.chatGPTWeb.rawValue
    @AppStorage(LemmaPreferences.contextText) private var includeText = true
    @AppStorage(LemmaPreferences.contextSection) private var includeSection = true
    @AppStorage(LemmaPreferences.contextCited) private var includeCited = true
    @AppStorage(LemmaPreferences.contextGlossary) private var includeGlossary = true
    @AppStorage(LemmaPreferences.contextPins) private var includePins = true
    @AppStorage(LemmaPreferences.pageTheme) private var pageTheme = PageTheme.paper.rawValue
    @AppStorage(LemmaPreferences.lineNumbers) private var lineNumbers = true
    @AppStorage(LemmaPreferences.pageGap) private var pageGap = LemmaPreferences.pageGapDefault

    var body: some View {
        TabView {
            if let store { WorkbenchAppearanceView(store: store).tabItem { Label("Workbench", systemImage: "slider.horizontal.3") } }
            Form {
                Section {
                    Toggle("Link equation, figure and section references", isOn: $referenceLinks)
                    Text("References such as “(2.3)”, “Figure 2.1”, “Ex. 2.8” or “Rudin (1976)” are underlined. Click one to preview it beside your page; Go to moves there and ⌥⌘← comes back.")
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    Toggle("Preview references on hover", isOn: $hoverPreviews)
                    Text("Rest the pointer on an underlined reference to see the equation, figure or cited work without clicking.")
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    Toggle("Show reference counts beside equations and figures", isOn: $referenceCounts)
                    Text("After Lemma has read the book, each equation and figure shows how often the text refers to it. Click the count to list the places.")
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                } header: { Text("References") }
                Section {
                    Picker("Page", selection: Binding(get: { pageTheme }, set: { value in
                        pageTheme = value
                        if let theme = PageTheme(rawValue: value) { store?.pageTheme = theme }
                    })) {
                        ForEach(PageTheme.allCases) { theme in Text(theme.label).tag(theme.rawValue) }
                    }
                    Text("Night shows light text on a dark page and keeps the hues of colours; Sepia warms the paper. Captures, questions and exports always use the original page. ⌃⌘T cycles.")
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    Toggle("Line numbers beside the page", isOn: Binding(get: { lineNumbers }, set: { value in
                        lineNumbers = value
                        store?.reader.showLineNumbers = value
                    }))
                    Text("Click a number to select its line; type “64:12” in Go to. Bars beside a line mark your highlights, notes, “?” marks and drawings. ⌃⌘L.")
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    LabeledContent("Gap between pages") {
                        HStack {
                            Slider(value: $pageGap, in: 0...32, step: 1).frame(width: 180)
                            Text("\(Int(pageGap)) pt").monospacedDigit().frame(width: 40, alignment: .trailing)
                        }
                    }
                    Text("Space between pages in the reader, the side view and reference previews; open books follow at once. 0 runs the pages together.")
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                } header: { Text("Page") }
            }.formStyle(.grouped).tabItem { Label("Reading", systemImage: "book") }

            Form {
                Section {
                    Picker("Assistant", selection: $questionProvider) {
                        ForEach(QuestionProvider.allCases) { Text($0.label).tag($0.rawValue) }
                    }
                    if let store { Button("Connect assistants…") { store.showBrowserSetup = true } }
                    Picker("Quick questions to ChatGPT", selection: $quickAskMode) {
                        Text("Send now").tag(WebQuestionMode.askAndSave.rawValue)
                        Text("Review first").tag(WebQuestionMode.draft.rawValue)
                    }
                    Text("ChatGPT Web opens inside Lemma. Codex and Claude Code run your installed CLI with the sign-in it already has. The OpenAI, Anthropic and Gemini APIs use your own API key, kept in your Keychain. Only the ticked context and the draft are sent, and only to the assistant you choose. Every answer is saved with its source; you can keep reading while it arrives.")
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                } header: { Text("Sending") }
                Section {
                    Toggle("Text of the passage", isOn: $includeText)
                    Toggle("Current section title", isOn: $includeSection)
                    Toggle("Equations and figures cited in the passage", isOn: $includeCited)
                    Toggle("Matching entries from my glossary (names, notation, scope)", isOn: $includeGlossary)
                    Toggle("Pinned references", isOn: $includePins)
                    Text("These are the starting choices; each question still lists its context so you can change it before sending. Linked notes are always opt-in.")
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                } header: { Text("Include by default") }
            }.formStyle(.grouped).tabItem { Label("Questions", systemImage: "text.bubble") }

            if let store { LabSettings(lab: store.lab, store: store).tabItem { Label("Lab", systemImage: "flask") } }
        }
        .frame(width: 610, height: 610)
        .tint(.lemmaOlive)
    }
}

/// Python for the Lab: which interpreter runs the notebooks, and how gently.
struct LabSettings: View {
    @Bindable var lab: LabRuntime
    var store: StudyStore? = nil
    @AppStorage(LabPreferences.gentle) private var gentle = true

    var body: some View {
        Form {
            Section {
                // The runtime applies a choice at once: notebooks use it from their next run.
                Picker("Python", selection: Binding(get: { lab.preferredPath }, set: { lab.setPreferredInterpreter($0) })) {
                    Text(lab.interpreters.first.map { "Automatic (\($0.path))" } ?? "Automatic").tag("")
                    ForEach(lab.interpreters) { interpreter in
                        Text("\(interpreter.path) (\(interpreter.version))").tag(interpreter.path)
                    }
                    if !lab.preferredPath.isEmpty, !lab.interpreters.contains(where: { $0.path == lab.preferredPath }) {
                        Text(lab.preferredPath).tag(lab.preferredPath)
                    }
                }
                if lab.setup.isRunning {
                    Text("Setting up Lemma's Python… \(Int(lab.setup.progress.fraction * 100)) %").font(.caption).foregroundStyle(.secondary)
                } else if let interpreter = lab.interpreter {
                    Text(interpreter.summary).font(.caption).foregroundStyle(.secondary)
                    if !interpreter.isScientific {
                        Text("NumPy and Matplotlib are missing: Set Up Python for the Lab installs them in Lemma's own environment.")
                            .font(.caption).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
                    }
                } else if lab.isDiscovering {
                    Text("Looking for Python…").font(.caption).foregroundStyle(.secondary)
                } else {
                    Text("No Python 3 found. Set Up Python for the Lab shows how to install it.").font(.caption).foregroundStyle(.secondary)
                }
                if let problem = lab.interpreterProblem {
                    Text(problem).font(.caption).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
                }
                HStack {
                    Button("Choose an Interpreter…") { choose() }
                    Button("Look Again") { Task { await lab.discover(force: true) } }.disabled(lab.isDiscovering)
                    Spacer()
                    if let store { Button("Set Up Python for the Lab…") { store.showPythonSetup() } }
                }
                Text("Lemma looks in the usual places (python.org, Homebrew, conda, pyenv, and its own environment) and prefers an interpreter with NumPy and Matplotlib. Set Up Python for the Lab makes Lemma's own environment with NumPy, SciPy, Matplotlib, SymPy and pandas. A change applies when a notebook next runs a cell.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            } header: { Text("Interpreter") }
            Section {
                Toggle("Run code gently", isOn: $gentle)
                Text("Gentle runs Python at utility priority with at most two math threads, so long experiments keep the Mac cool and the battery healthy; they take longer. Applies when Python next starts.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            } header: { Text("Execution") }
            Section {
                Text("Cells run only when you run them, on this Mac, in a separate Python process per notebook with its own folder. Code from assistant answers is copied into cells for you to read first. Outputs and figures are saved with the book and exported as Jupyter notebooks.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            } header: { Text("Safety") }
        }
        .formStyle(.grouped)
        .task { if let store { await store.discoverPython() } else { await lab.discover() } }
    }

    private func choose() {
        let panel = NSOpenPanel()
        panel.message = "Choose a python3 executable"
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        // A virtual environment's python3 is a symlink to its base interpreter: resolving it would lose the environment.
        panel.resolvesAliases = false
        panel.directoryURL = Self.startingDirectory(current: lab.interpreter?.path)
        panel.treatsFilePackagesAsDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task { _ = await lab.choose(path: url.path) }
    }

    /// The current interpreter's folder, or where Python usually is: Homebrew on Apple silicon, then python.org's links.
    static func startingDirectory(current: String?) -> URL {
        if let current { return URL(fileURLWithPath: current).deletingLastPathComponent() }
        let folder = ["/opt/homebrew/bin", "/usr/local/bin", "/Library/Frameworks/Python.framework/Versions/Current/bin"]
            .first { FileManager.default.fileExists(atPath: $0) } ?? "/usr/local/bin"
        return URL(fileURLWithPath: folder, isDirectory: true)
    }
}
