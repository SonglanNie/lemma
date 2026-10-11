# Changelog

The detailed notes written for each version before 3.0 are in [docs/HISTORY.md](docs/HISTORY.md).

## 3.1.0 (October 2026)

**Updates inside Lemma.** **Lemma › Check for Updates…** shows what is new in a release, installs it and relaunches Lemma: no more downloading a disk image. If you agree (Lemma asks once, at its second launch), it also checks once a day, and it can download and install an update on its own when you quit (**Settings › Updates**). Updates are signed with the project's key, so Lemma installs only versions its maintainers published.

- The updating is done by Sparkle (MIT licence), listed in **Help › Acknowledgements**.
- Your choice of a daily check in Lemma 3.0 carries over.

## 3.0.0, the first public release (October 2026)

**A look of its own.** Lemma Dark and Lemma Light are the new default themes: warm graphite and paper with an olive accent, following macOS light and dark. A new icon. A new Welcome page: open a PDF, drop one, add a folder of PDFs, pick a free textbook from a shelf of covers, or continue a book where you left it. The catalog's 45 free textbooks get covers. The Lemma Tour lets new readers choose between the VS Code-style workbench and the classic Mac window. A sample book, **Least Squares in Twelve Pages**, shows what Lemma does without a PDF at hand (Help › Open the Sample Book).

**Reading.**
- Find in the book (⌘F), as in an editor, with Match Case and Match Whole Word: the matches are highlighted on the page, and ⌘G, ⇧⌘G, Return and ⇧Return move between them from where you are reading.
- PDFs open from Finder (Open With), from the Dock and from other apps.
- Books take their title from the PDF's metadata when it has a real one.
- ⌘C copies a passage as running text: the PDF's line breaks and words hyphenated across lines are joined.
- ⌥-click a reference to open it beside the page, as the hover and the peek say.
- Lemma launches, scrolls, switches books and searches faster, and does nothing while idle: no timers, polling or redraws.
- Notes follow a PDF whose file changed on disk (annotated in Preview, downloaded again), and password-protected PDFs open.

**Assistants.** OpenAI, Anthropic and Google Gemini with your own API key, stored in the Keychain, join ChatGPT, Codex and Claude Code. The command-line tools use whatever sign-in you set up, signing in happens in your browser, and ChatGPT's page loads only when you connect it.

**Lab.** **Set Up Python for the Lab…** creates a private Python environment with NumPy, SciPy, Matplotlib, SymPy and pandas. Notebooks' Python processes always stop when Lemma quits.

**Trust.** Lemma is free software (GNU GPL v3) on GitHub. **Help** has Report an Issue, Privacy and Acknowledgements; **Lemma › Check for Updates…** asks GitHub for a newer release, only when you ask or once a day if you turn it on. New readers start with two libraries, Books and Papers. Search indexing runs in Lemma's own helper at low priority and pauses on battery, in Low Power Mode and when the Mac is hot. The statistics experiments (ridge, Lasso, nearest neighbours) appear only for statistical-learning books. OCR uses your languages.

**Changed shortcuts**, because macOS takes the old ones: Save Definition is ⌥⌘S, Resume at the First “?” is ⌥⌘J, and Show What This Statement Uses is ⇧⌥⌘H.

**Fixed.**
- Two catalog books that share a title no longer download over each other.
- Equation previews no longer take in the line above in books set in 11 or 12 pt; each book is read again once, in the background, after the update.
- References a PDF links by their number only (“Theorem 1.3”, “(2.1)”) are named in full in peeks and counted with what they cite.
- Peeks and hovers stay inside the window.
- High-contrast themes now apply to menus and peeks.
- Return no longer reopens the last book in the Classic home.
- The Classic panel can't grow taller than the window.
- Lemma can no longer be stopped by a command-line tool that quits early.
- Quit works while a sheet is open.
- Close Others and Close All close at once instead of opening each book on the way, and ⌘W passes over a book whose PDF is missing.
- A damaged book file no longer hides the rest of the Library, and Lemma never overwrites it.
- Search results, links and project passages wait for their book to open before moving the page.
- Redo works for collected passages, and the Lab's processes never outlive Lemma.

## Earlier versions

- **2.5** (October 2026): the Lemma Tour shortened to six steps on your own window, with short guides for each part.
- **2.4**: the Library as an editor's tree: renames in Lemma or on disk, drag and drop, Undo.
- **2.3**: assistants inside Lemma (ChatGPT Web, Codex, Claude Code); visible highlight controls; Back and Forward on ⌥⌘← and ⌥⌘→.
- **2.2**: the first-launch Lemma Tour.
- **2.1**: libraries of watched folders, arXiv search, the Chrome companion's Quick Add; PDFs dropped beside the reader; faster minimap and saves.
- **2.0**: the VS Code-style workbench, 84 colour themes, Run and Debug for proofs, Testing for recall, the minimap, search across the library.
- **1.1**: research projects across books, a durable editor session, workbench themes and layouts, formulas read as LaTeX.
- **1.0**: derivations checked as you type, editor groups, the Problems panel, line numbers, page themes, the free textbook catalog, Find the Paper.
- **0.9**: the structure of a mathematical text: results, folded proofs, what-uses-what, the dependency map, the reading ruler, notation hovers.
- **0.8**: the Lab (Python notebooks), hover previews, the page inspector, reading progress.
- **0.7**: the workbench: command palette, tabs, breadcrumbs, split editor, panel and overview ruler.
- **0.1 to 0.6**: the reader, source-linked notes and questions, references as links, recall, OCR, drawing on your edition.
