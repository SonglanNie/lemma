import SwiftUI
import LemmaCore

/// The tour, six steps on the reader's own window, then the guides that go deeper, a few steps each.
@MainActor
enum TutorialContent {
    static let guides: [TutorialGuide] = [tour, window, reading, proofs, derive, lab, notes, ask, remember, personalize]

    private static func tip(_ text: String, _ keys: String) -> TutorialTip { TutorialTip(text: text, keys: keys) }

    private static func showStudy(_ section: StudySection) -> @MainActor (StudyStore) -> Void {
        { store in store.revealStudy(); store.studySection = section }
    }

    private static func showPanel(_ tab: PanelTab) -> @MainActor (StudyStore) -> Void {
        { store in store.panelTab = tab; if !store.showPanel { store.togglePanel() } }
    }

    private static func showSideBar(_ section: NavigatorSection) -> @MainActor (StudyStore) -> Void {
        { store in store.reveal(section) }
    }

    // MARK: The tour

    static let tour = TutorialGuide("tour", "The Lemma Tour", summary: "Your library, Go to, links, the selection bar, your notes and the activity bar, lit up on your own window.",
                                    icon: "rocket", steps: [
        TutorialStep(id: "library", title: "Start with a book",
            body: "Your books live in the Library. Open a PDF or drop one on the window; a folder you add keeps itself up to date. No book yet? The Catalog has 45 free textbooks.",
            classicBody: "Your books live in the sidebar. Open a PDF or drop one on the window; a folder you add keeps itself up to date. No book yet? The Catalog has 45 free textbooks.",
            tips: [tip("Open a PDF", "⌘O")],
            scene: .library, target: .sideBar, reveal: showSideBar(.library),
            actions: [TutorialAction(title: "Open a PDF…", icon: "file-pdf") { $0.choosePDF() },
                      TutorialAction(title: "Free Textbooks", icon: "extensions", after: .stay) { $0.catalogMode = .books; $0.reveal(.catalog) }]),
        TutorialStep(id: "goTo", title: "Go anywhere by typing",
            body: "Click here or press ⌘P, then type a page (`124`), an equation (`(3.41)`), a section or part of a note. ⇧⌘P runs any command by its name.",
            tips: [tip("Go to", "⌘P"), tip("Command palette", "⇧⌘P")],
            scene: .goTo, target: .commandCenter,
            actions: [TutorialAction(title: "Try Go To", icon: "go-to-file") { $0.showPalette(.goTo) }]),
        TutorialStep(id: "links", title: "References are links",
            body: "Lemma underlines the book's references, such as (3.41), Figure 3.8 or Lemma 4.2. Rest the pointer on one to preview it; click it to peek without leaving your page.",
            tips: [tip("Back after a jump", "⌥⌘←")],
            scene: .hover, target: .page),
        TutorialStep(id: "select", title: "Select, then act",
            body: "Select a passage, or capture a region around an equation. This bar then offers Ask, Note, Lab, Derive, LaTeX, Look Up and more for it.",
            tips: [tip("Ask about the selection", "⌘K"), tip("Capture a region", "⇧⌘S")],
            scene: .selection, target: .selectionBar,
            actions: [TutorialAction(title: "Capture a Region", icon: "inspect", requires: .book) { $0.reader.regionMode = true }]),
        TutorialStep(id: "notebook", title: "Your notebook",
            body: "Notes keep the passage they came from, beside your reasoning. The notebook also holds what the page defines, your glossary, pinned passages and your review.",
            tips: [tip("New note from the selection", "⌘N"), tip("Show or hide", "⌥⌘B")],
            scene: .note, target: .secondarySideBar, reveal: showStudy(.notes)),
        TutorialStep(id: "views", title: "Every tool has a view",
            body: "Explorer, Search, Structure, Run and Debug, Testing, Lab, Projects, Marks and the Catalog: each icon opens its view. The guides walk through each one.",
            classicBody: "Books, Outline, Results, Search, Lab, Marks, Catalog, Run and Debug and more: each icon opens its view in the sidebar. The guides walk through each one.",
            tips: [tip("Explorer", "⌥⌘1"), tip("Run and Debug", "⇧⌘D")],
            scene: .workbench(.activityBar), target: .activityBar)
    ])

    // MARK: Guides

    static let window = TutorialGuide("window", "Your Window", summary: "Layouts, Zen Mode, the split editor, the panel and the status bar.",
                                      icon: "layout", steps: [
        TutorialStep(id: "layouts", title: "Arrange the window",
            body: "These controls show or hide the side bars and the panel. Layouts arrange the window for Reading, Study, Research or the Lab, and Zen Mode hides the side bars, the panel and the activity bar.",
            classicBody: "The Layout menu in the toolbar arranges the window for Reading, Study, Research or the Lab. Zen Mode hides the sidebars, the panel and the activity bar.",
            tips: [tip("Zen Mode", "⌥⌘Z"), tip("Show or hide the side bar", "⌘B")],
            scene: .layouts, target: .layoutControls,
            actions: [TutorialAction(title: "Try Zen Mode", icon: "screen-full", requires: .book) { $0.toggleFocus() }]),
        TutorialStep(id: "split", title: "The same book, twice",
            body: "Each book opens in its own tab. Split the editor to keep Theorem 4.2 in view while you read its proof, or drag a PDF from the Library to the right edge of the page.",
            tips: [tip("Split the editor", "⌘\\"), tip("Next book", "⌃⇥")],
            scene: .split, target: .editorTabs,
            actions: [TutorialAction(title: "Split the Editor", icon: "split-horizontal", requires: .book) { if $0.split == nil { $0.toggleSplit() } }]),
        TutorialStep(id: "panel", title: "The panel",
            body: "Below the page sit Problems, References, the Hierarchy of a statement, your Questions and Notes, and the Python Console.",
            tips: [tip("Show or hide the panel", "⌘J"), tip("Python console", "⌃`")],
            scene: .workbench(.panel), target: .panel, reveal: { store in
                // The console looks for Python when it appears: the tour shows another tab.
                if !store.showPanel { if store.panelTab == .console { store.panelTab = .problems }; store.togglePanel() }
            }),
        TutorialStep(id: "statusBar", title: "The status bar",
            body: "Your mode, the book's analysis, problems, your position, today's reading time and a note for next time. Most items open something when clicked.",
            classicBody: "Your mode, the book's analysis, the current section, today's reading time, due recalls, a note for next time and your position. Most items open something when clicked.",
            scene: .workbench(.statusBar), target: .statusBar)
    ])

    static let reading = TutorialGuide("reading", "Reading", summary: "Go to anything, previews and peeks, definitions, the reading ruler.",
                                       icon: "book", steps: [
        TutorialStep(id: "goTo", title: "Go to anything",
            body: "Type a printed page (`124`), a PDF page (`pdf 143`), an equation (`(3.41)`), a figure (`fig 3.8`), a section (`3.4.1`), a line (`64:12`) or part of a note.",
            tips: [tip("Go to", "⌘P"), tip("Open the result beside the page", "⌥↩")],
            scene: .goTo, target: .commandCenter,
            actions: [TutorialAction(title: "Try Go To", icon: "go-to-file") { $0.showPalette(.goTo) }]),
        TutorialStep(id: "peek", title: "Preview, peek, come back",
            body: "Rest the pointer on a reference to preview it; click it to peek at its page under the line. Find All References lists every place that cites it.",
            tips: [tip("Back", "⌥⌘←"), tip("Forward", "⌥⌘→")],
            scene: .peek, target: .page),
        TutorialStep(id: "lookUp", title: "Look up a term",
            body: "⌘-click a term to see where the book defines it, its index entries, your glossary and your other books. Rest the pointer on a symbol such as λ for its meaning at that point.",
            tips: [tip("Look up the word under the pointer", "⌘-click"), tip("Look up the selection", "⇧⌘L")],
            scene: .lookUp, target: .page),
        TutorialStep(id: "ruler", title: "Read line by line",
            body: "The ruler lights one line and veils the rest; ↓ and ↑ move it. When a line makes no sense, mark it “?” and keep reading: Problems keeps the list for later.",
            tips: [tip("Reading ruler", "⌥⌘R"), tip("Mark a line “?”", "⌥⌘/")],
            scene: .ruler, target: .page,
            actions: [TutorialAction(title: "Turn On the Ruler", icon: "eye", requires: .book) { $0.reader.rulerMode = true }])
    ])

    static let proofs = TutorialGuide("proofs", "Proofs", summary: "Results, folded proofs, what uses what, and stepping through a proof.",
                                      icon: "debug-alt", steps: [
        TutorialStep(id: "results", title: "Results, like a symbol outline",
            body: "Results lists every definition, theorem and lemma by chapter, with how many places use it and whether you understood it. ⌥-click opens one beside the page.",
            tips: [tip("Go to a symbol", "⌘T")],
            scene: .results, target: .sideBar, reveal: showSideBar(.results)),
        TutorialStep(id: "fold", title: "Fold a proof, try it first",
            body: "A folded proof hides behind a panel that says how long it is: try it yourself, then click to unfold. A header keeps the statement in view while you read the proof.",
            tips: [tip("Fold or unfold every proof", "⌥⌘[")],
            scene: .fold, target: .page,
            actions: [TutorialAction(title: "Fold All Proofs", icon: "fold", requires: .analysis) { store in
                if store.proofs.isEmpty { store.notify("Lemma found no proofs in this book.", source: "Lemma Guides") }
                else if !store.allProofsFolded { store.toggleAllProofs() }
            }]),
        TutorialStep(id: "uses", title: "What it uses, what uses it",
            body: "The Hierarchy panel shows what a statement relies on and what relies on it, level by level, read from the book's references. The map lays out a chapter, prerequisites first.",
            tips: [tip("Hierarchy", "⇧⌥⌘H"), tip("Dependency map", "⌥⌘G")],
            scene: .hierarchy, target: .panel, reveal: showPanel(.hierarchy),
            actions: [TutorialAction(title: "Open the Map", icon: "graph", requires: .analysis) { $0.showMap() }]),
        TutorialStep(id: "debug", title: "Step through a proof",
            body: "Put your reading position in a proof and press F5. F10 steps to the next line, F11 into the result a line cites and ⇧F11 back out, with the goal and the symbols in view here.",
            tips: [tip("Start debugging", "F5"), tip("Step over", "F10")],
            scene: .debugStep, target: .sideBar, reveal: showSideBar(.debug),
            actions: [TutorialAction(title: "Start Debugging", icon: "debug-start", requires: .analysis) { $0.startDebugging() }])
    ])

    static let derive = TutorialGuide("derive", "Checked Derivations", summary: "Work through the steps a book calls “easily seen”, checked line by line.",
                                      icon: "symbol-operator", steps: [
        TutorialStep(id: "start", title: "Work through a step",
            body: "Select a step you do not follow and choose Derive. A derivation opens beside the page: write one step per line, in LaTeX or as Unicode pasted from a PDF.",
            tips: [tip("Derive from the selection", "⌥⌘E")],
            scene: .derivation(.start),
            actions: [TutorialAction(title: "New Derivation", icon: "symbol-operator", requires: .book) { $0.newDerivation() }]),
        TutorialStep(id: "check", title: "Every line, checked",
            body: "Each line is tested on random values of its symbols: numbers, vectors, matrices of matching sizes. A wrong step shows a counterexample and names the slip, such as a sign or a factor of 2.",
            scene: .derivation(.check)),
        TutorialStep(id: "answer", title: "Check an answer, read a formula",
            body: "An assistant's answer saved in a note gets Check n steps: its equations are tested on this Mac, which finds wrong steps but proves nothing. LaTeX turns a selected formula into editable source.",
            scene: .derivation(.answer))
    ])

    static let lab = TutorialGuide("lab", "The Lab", summary: "Python notebooks beside the page, run on your Mac when you run them.",
                                   icon: "notebook", steps: [
        TutorialStep(id: "notebook", title: "A notebook beside the page",
            body: "Select an equation and choose Lab: a Python notebook opens beside the page, with the passage on top. It uses the Python already on your Mac.",
            tips: [tip("Send the selection to the Lab", "⌥⌘L")],
            scene: .notebook,
            actions: [TutorialAction(title: "New Notebook", icon: "notebook", requires: .book) { $0.newLab() }]),
        TutorialStep(id: "cells", title: "Run cells, gently",
            body: "Output, values and Matplotlib figures appear under each cell. Code runs only when you run it, at low priority with two math threads, to keep the Mac cool.",
            tips: [tip("Run and move on", "⇧↩"), tip("Run", "⌘↩")],
            scene: .cells),
        TutorialStep(id: "console", title: "The Python console",
            body: "The Console computes beside the page, like an editor's terminal. With a notebook open it shares its variables; ↑ recalls earlier input and Tab completes.",
            tips: [tip("Python console", "⌃`")],
            scene: .console, target: .panel,
            actions: [TutorialAction(title: "Open the Console", icon: "terminal", requires: .book, perform: showPanel(.console))]),
        TutorialStep(id: "figure", title: "Your figure beside the book's",
            body: "Pin a notebook's figure beside the page, next to the passage it illustrates. Export notebooks for Jupyter; a failing cell can ask an assistant, with its code and error.",
            scene: .marginFigure)
    ])

    static let notes = TutorialGuide("notes", "Notes and Your Edition", summary: "Notes that keep their source, marks, a glossary and your own edition.",
                                     icon: "edit", steps: [
        TutorialStep(id: "note", title: "Notes keep their source",
            body: "A note keeps the passage it came from beside your reasoning. Save it as a question, a definition, notation or a theorem; Markdown and LaTeX are typeset.",
            tips: [tip("New note from the selection", "⌘N")],
            scene: .note, target: .secondarySideBar, reveal: showStudy(.notes)),
        TutorialStep(id: "marks", title: "Highlight, underline, comment",
            body: "Highlight or underline the selection in the colour you choose, or write a note in the margin beside its line. Highlights also show in the minimap and as change bars.",
            tips: [tip("Highlight", "⇧⌘H"), tip("Margin note", "⌥⌘M")],
            scene: .highlight, target: .page),
        TutorialStep(id: "glossary", title: "Your glossary",
            body: "Save a selection as a definition and it joins your glossary, which Look Up searches too. Pin a passage to keep it in Context while you read on.",
            tips: [tip("Save as definition", "⌥⌘S"), tip("Pin the selection", "⌥⌘P")],
            scene: .glossary, target: .secondarySideBar, reveal: showStudy(.glossary)),
        TutorialStep(id: "ink", title: "Draw on your edition",
            body: "Draw on My Edition with a pen, in several colours and widths, with Undo. Export My Edition as PDF for a copy with your ink and notes; the original file never changes.",
            tips: [tip("Draw", "⌥⇧⌘D")],
            scene: .ink,
            actions: [TutorialAction(title: "Start Drawing", icon: "edit", requires: .book) { $0.reader.inkMode = true }])
    ])

    static let ask = TutorialGuide("ask", "Ask an Assistant", summary: "ChatGPT, Codex or Claude Code, with exactly the context you choose.",
                                   icon: "comment-discussion", steps: [
        TutorialStep(id: "ask", title: "Ask about a passage",
            body: "Select a passage, type what you do not understand, or nothing, and pick a style: Explain, Hint, Next step, Intuition, Example and more. Return asks.",
            tips: [tip("Ask about the selection", "⌘K")],
            scene: .ask,
            actions: [TutorialAction(title: "Ask About the Selection", icon: "comment-discussion", requires: .selection) { $0.prepareQuickAsk() }]),
        TutorialStep(id: "context", title: "Context you can see",
            body: "Lemma adds the passage, its section and the equations it cites, as images, and matching glossary entries. Each item has a checkbox, and Full draft shows the exact text.",
            scene: .askContext),
        TutorialStep(id: "providers", title: "Your assistant, inside Lemma",
            body: "ChatGPT opens inside Lemma; Codex and Claude Code run your installed CLI with its own sign-in; OpenAI, Anthropic and Gemini take your API key. The answer returns to its note, typeset, and Check n steps can test it.",
            scene: .chrome,
            actions: [TutorialAction(title: "Connect Assistants…", icon: "plug") { $0.showBrowserSetup = true }])
    ])

    static let remember = TutorialGuide("remember", "Remember and Research", summary: "Spaced review, search across books, research projects, your data.",
                                        icon: "beaker", steps: [
        TutorialStep(id: "review", title: "Review on schedule",
            body: "Add a note or a statement to Review. Recall it while its source is hidden, then reveal and grade yourself; the schedule spaces the next recall. Testing runs the book's definitions and results as tests.",
            tips: [tip("Review notes", "⇧⌘R")],
            scene: .review, target: .secondarySideBar, reveal: showStudy(.review)),
        TutorialStep(id: "search", title: "Search every book",
            body: "Search the book in front or your whole library, with the words around each match, and your notes and scanned pages. A click opens the book at the match.",
            classicBody: "Search the book in front, your notes and the pages indexed from scans. Searching every book of the library belongs to the VS Code interface.",
            tips: [tip("Search", "⇧⌘F")],
            scene: .search, target: .sideBar, reveal: showSideBar(.search)),
        TutorialStep(id: "project", title: "Research across books",
            body: "A project gathers a question, the books that bear on it and your synthesis. Collected passages become sources (S1, S2…) that you cite and follow back to the page.",
            tips: [tip("Collect the selection", "⇧⌘C")],
            scene: .project, target: .sideBar, reveal: showSideBar(.projects),
            actions: [TutorialAction(title: "New Research Project", icon: "new-folder") { $0.newProject() }]),
        TutorialStep(id: "data", title: "Your data stays here",
            body: "Notes, marks and progress live on this Mac, and your PDFs are never modified. Lemma goes online only when you click, and says where. Export Study Notes takes it all with you.",
            tips: [tip("Export Study Notes", "⌥⇧⌘E")],
            scene: .privacy)
    ])

    static let personalize = TutorialGuide("personalize", "Make It Yours", summary: "Colour themes, the two interfaces, settings and keyboard shortcuts.",
                                           icon: "settings-gear", steps: [
        TutorialStep(id: "themes", title: "Colour themes",
            body: "Choose a colour theme, previewed as you move through the list, or drop a VS Code theme's `.json` or `.vsix` on the window. The page keeps its own Paper, Sepia or Night.",
            classicBody: "The Classic interface offers System, Light, Graphite and Midnight with four accents, in Customize Workbench. The page keeps its own Paper, Sepia or Night.",
            tips: [tip("Colour theme", "⌥⌘T"), tip("Page theme", "⌃⌘T")],
            scene: .themes,
            actions: [TutorialAction(title: "Browse Colour Themes", icon: "symbol-color") { $0.showThemePicker() }]),
        TutorialStep(id: "interface", title: "Two interfaces",
            body: "Switch between the VS Code workbench and the Classic Mac window whenever you like, in Settings or the command palette. Your books and study tools work in both.",
            scene: .interfaceStyle,
            actions: [TutorialAction(title: "Switch the Interface", icon: "arrow-swap", after: .stay) { _ in
                let themes = ThemeManager.shared
                themes.style = themes.style == .vscode ? .classic : .vscode
            }]),
        TutorialStep(id: "settings", title: "Settings and shortcuts",
            body: "Settings is a searchable editor that marks what you changed. Keyboard Shortcuts lists every command with its keys and when it applies.",
            classicBody: "Settings opens in its own window, and Customize Workbench in the Layout menu changes the appearance. Keyboard Shortcuts lists the main shortcuts by task.",
            tips: [tip("Settings", "⌘,"), tip("Keyboard Shortcuts", "⌘/")],
            scene: .settings,
            actions: [TutorialAction(title: "Open Settings", icon: "settings-gear") { $0.openSettingsEditor() }])
    ])
}
