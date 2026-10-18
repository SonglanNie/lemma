<p align="center"><img src="docs/images/icon.png" width="128" alt="Lemma's icon: a white λ on an olive tile"></p>

<h1 align="center">Lemma</h1>

<p align="center"><b>An IDE for reading mathematics.</b><br>
A free, open-source PDF reader for the Mac that understands textbooks and papers the way an editor understands code.</p>

<p align="center"><a href="https://github.com/SonglanNie/lemma/releases/latest"><b>Download for macOS</b></a> · macOS 15 or later, Apple silicon and Intel</p>

<p align="center"><img src="docs/images/demo.gif" width="900" alt="Lemma reading its sample book: hovering “Theorem 1.3” previews it, clicking opens a peek beside the line, ⌘K asks about a proof with the equations it cites, proofs fold, and a derivation's wrong step is caught as a sign error, then fixed"></p>

Open any mathematics, statistics or computer science PDF. Lemma reads it once, on your Mac, and the page becomes navigable: “Theorem 2.3”, “(3.44)”, “Figure 5”, “[12]” and index entries turn into links you can preview, peek at and follow without losing your place.

## About this fork

This is a modified version of [Lemma](https://github.com/fus3r/lemma) by its contributors, based on Lemma 3.2.1. It was changed by Songlan Nie, starting on 18 October 2026, and remains free software under the GNU GPL v3. The commit history records every change. In brief:

- **Gap between pages.** Pages are 8 pt apart by default, and **Settings › Reading › Gap between pages** sets the gap from 0 to 32 pt. Open books follow at once, including the side view and reference previews.
- **Right panel.** The notebook panel has a close button, in both the classic and the VS Code-style workbench.
- **Reference previews.** The floating preview can be dragged off its line. It opens at the page's width and no longer selects the referenced text, which looked wrong when the PDF's text layer was misaligned.
- **Go to.** Following a reference keeps your zoom and horizontal position, and scrolls sideways only when the item would be off screen. The box that flashes around an equation fits the equation and its label instead of reaching into the text around it, and a reference to an equation with lettered parts, such as (15) for (15a)–(15c), goes to all of them.
- **Reference counts.** A citation written directly after a word, such as "and(24a)" in some PDFs' text, is now counted. Citations after a function name, such as "f(2)", still are not.
- **Find.** ⌘F puts the cursor in the find field even when the page-number field had it, and pressing Return in the page-number field gives the keyboard back to the page.
- **Updates.** This fork's build has no Sparkle update feed, so an upstream release never installs over it. **Lemma › Check for Updates…** reports a newer release of this fork and opens its page. **Help › Report an Issue…** opens an issue here.

Releases of this fork are named after the upstream version they are based on, with a number of their own: `v3.2.1-fork.1`, `v3.2.1-fork.2`, and so on. Pushing such a tag makes GitHub Actions build the app for Apple silicon and Intel and publish it as a release with its disk image ([release.yml](.github/workflows/release.yml)); the tag must match `CFBundleShortVersionString` in [package-app.py](scripts/package-app.py). This copy is still called Lemma and uses the same app identifier, so installing it replaces the original Lemma, keeping your library and settings.

A build with only the Command Line Tools (no Xcode) works for Apple silicon with `swift build -c release --disable-keychain && scripts/build-app.sh`.

## What Lemma does

**References you never have to hunt for.** Hover a reference to preview it, click to peek at it beside the line you are reading, ⌘-click a term to look up its definition. Back (⌥⌘←) returns you to where you were. Citations open their entry in the bibliography and can find the paper online when you ask.

**The structure of the text.** An outline of the book's definitions, theorems and proofs; proofs you can fold to try them yourself first; what a result uses and what uses it; a map of a chapter's dependencies; the notation in force on each line; and a header that tells you which statement you are in.

**Proofs, stepped through like a debugger.** Put the reading line in a proof and press F5: step over lines, step into the result a line cites, step out again, with the statement being proved and the symbols in scope beside you.

**Derivations checked as you write them.** Select a step the book calls "easily seen", press ⌥⌘E and write the missing lines in LaTeX. Each line is checked at once with random values of the right shapes (scalars, vectors, matrices), so a wrong step comes with a counterexample and a name: sign error, factor of 2, transposed.

**Python beside the page.** Send an equation to a notebook and run it on your Mac's own Python, gently on the battery. Figures can be pinned in the margin.

**Your work, kept with the source.** Notes, highlights, margin notes and handwriting stay linked to the exact passage. Recall definitions and theorems on a spaced schedule, collect passages from several books into research projects, and export everything: Markdown, Anki decks, Jupyter notebooks, or your annotated edition as a PDF.

**Questions with the right context.** Select a passage and press ⌘K. Lemma assembles the passage, the equations it cites and your notation, shows you the draft, and asks ChatGPT, Codex, Claude Code, or OpenAI, Anthropic or Google with your own API key. Answers return to the note that asked; their algebra can be checked step by step.

**Everything else a reader needs.** Find in the book (⌘F) and search across your whole library, OCR for scanned pages, 45 free textbooks one click away, arXiv search, a minimap of your pages, Paper, Sepia and Night pages, and the choice between a VS Code-style workbench (Lemma's own themes, more than 80 VS Code themes, or any VS Code theme you install) and a classic Mac window.

<p align="center"><img src="docs/images/reading.png" width="900" alt="Lemma reading its sample book: the outline, the page with its references underlined, a peek at Theorem 1.3 opened from the proof that cites it, and the equations defined on the page"></p>

<p align="center"><img src="docs/images/welcome.png" width="900" alt="Lemma's Welcome page: open or drop a PDF, or start with a free textbook"></p>

## Install

Download `Lemma-<version>.dmg` from the [latest release](https://github.com/SonglanNie/lemma/releases/latest), open it and drag Lemma into Applications. Lemma runs on macOS 15 (Sequoia) or later, on Apple silicon and Intel Macs.

This build is not yet notarized by Apple, so the first time you open it macOS says it cannot verify it. Click **Done**, then open **System Settings › Privacy & Security** and click **Open Anyway** next to Lemma (or run `xattr -dr com.apple.quarantine /Applications/Lemma.app`). You only do this once.

To see what Lemma does without a PDF at hand, choose **Help › Open the Sample Book**: a twelve-page book on least squares, written to show the links, the structure, the proof debugger and the derivation checker.

**Lemma › Check for Updates…** tells you when a newer release is out and opens its page; install it the same way. Settings › Updates can check once a day.

## Privacy

Lemma has no account, no analytics and no tracking. Your books, notes and reading history stay on your Mac. It goes online only when you click something that says where it goes: downloading a free book, searching arXiv, looking up a cited paper, asking an assistant, checking for updates. [PRIVACY.md](PRIVACY.md) lists every case and what is sent.

## Build it yourself

```sh
git clone https://github.com/SonglanNie/lemma.git && cd lemma
scripts/build-app.sh && open build/Lemma.app
```

You need macOS 15 and Xcode 16 or later. [CONTRIBUTING.md](CONTRIBUTING.md) explains the layout of the code, the tests and how to contribute.

## Learn more

- [Using Lemma](docs/GUIDE.md): reading, notes, OCR, recall, questions and exports in detail.
- [Libraries](docs/LIBRARIES.md): folders, renames, drag and drop, arXiv.
- [Assistants](docs/ASSISTANTS.md): ChatGPT, Codex, Claude Code and API keys, and what each receives.
- [The Lemma Tour](docs/TUTORIAL.md), [design notes](DESIGN.md), [changelog](CHANGELOG.md) and [history](docs/HISTORY.md).

Found a bug or have an idea? Use **Help › Report an Issue…** in Lemma or [open an issue](https://github.com/SonglanNie/lemma/issues).

## License

Lemma is free software under the [GNU General Public License, version 3](LICENSE). It bundles Codicons (CC BY 4.0), colour themes from VS Code and their community authors (MIT, Apache 2.0), KaTeX (MIT) and its fonts (SIL Open Font License 1.1), Marked (MIT), DOMPurify (Apache 2.0) and Sparkle (MIT), which this fork's builds do not use for updates; **Help › Acknowledgements** shows every licence. Free textbooks in the catalog are downloaded from their authors' or publishers' sites and remain under their own terms.
