# Contributing to Lemma

Thank you for helping. Lemma is a native macOS app written in Swift (SwiftUI and AppKit, PDFKit), built with the Swift Package Manager. It is free software under the GNU General Public License, version 3: contributions are accepted under the same licence.

## Build and run

Requirements: macOS 15 or later and Xcode 16 or later (its command-line tools are enough).

```sh
git clone https://github.com/SonglanNie/lemma.git
cd lemma
scripts/build-app.sh          # optimized build: build/Lemma.app
open build/Lemma.app
```

`scripts/build-app.sh --universal` builds for Apple silicon and Intel. During development, `swift build` and `swift run Lemma` work too; resources are then read from SwiftPM's bundle beside the executable.

## Tests

```sh
swift test                            # everything (a few minutes)
swift test --filter LemmaCoreTests    # the analysis, references, derivations, libraries
swift test --filter WorkbenchTests    # one class of the app's tests
```

Tests never touch your real data: the app's tests use temporary folders through `LEMMA_SUPPORT_DIR`. Some tests that need a local Python or an installed command-line tool skip themselves when it is missing.

## Layout

- `Sources/LemmaCore`: everything that does not draw: reading a book's structure (statements, proofs, references, index, bibliography, notation), the derivation checker, libraries, the Lab kernel, assistants' protocols. Most logic belongs here, with tests.
- `Sources/Lemma`: the app. `Workbench/` is the editor-style interface, `Classic/` the native one, `Library/` the library tree, `Tutorial/` the Lemma Tour, `Theme/` colour themes and controls.
- `Sources/LemmaIndexer`: a helper process for heavy, one-off work on a book (analysis, page text, indexing), so the reader stays light.
- `Sources/LemmaBrowserHost` and `browser/`: the optional Chrome companion.
- `docs/`: how features work and why they were designed so.

## Style

- Match the surrounding code: dense, readable lines; a doc comment on each type and on functions whose *why* is not obvious; no comment that only repeats the code.
- Keep the main thread for drawing: anything that reads a whole book, the disk or the network runs elsewhere, at utility priority when the reader is not waiting for it.
- Nothing may repeat forever while idle: no repeating SwiftUI animations, no polling timers without work to watch. Measure CPU at rest after a change to the window.
- Network access only on an explicit action that says where it goes (see `PRIVACY.md`).
- Interface text: plain English, sentence case for descriptions and title case for menu items and buttons, no em dashes.
- Every change to saved data must load files written by earlier versions.

## Driving the app in tests and reviews

A development copy launched with `LEMMA_QA_DIR=<folder>` answers `com.lemma.qa` distributed notifications (see `Sources/Lemma/QAHooks.swift`): it takes snapshots of its own windows, writes state as JSON and runs named actions. Release builds with the bundle identifier `com.lemma.app` never listen. Use a separate bundle identifier starting with `com.lemma.app.qa` and `LEMMA_SUPPORT_DIR` for such copies.

## Reporting problems

Use **Help › Report an Issue…** in the app (it fills in your Lemma and macOS versions), or open an issue on GitHub. For security problems, see `SECURITY.md`.
