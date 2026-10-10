# Work across books and resume the workbench

Consulted 2 October 2026 while resuming the unfinished local formula reader and extending Lemma 1.0. Sources informed three concrete priorities: continuity, customization, and research across documents.

## Evidence and decisions

| Source | Observation | Lemma 1.1 decision |
| --- | --- | --- |
| [VS Code: custom layout](https://code.visualstudio.com/docs/configure/custom-layout) | An editor lets its user arrange views, sidebar placement and editor groups around the task. | Native left/right explorer, pane widths, visible views, chrome density and Reading/Study/Research/Lab presets. |
| [VS Code: profiles](https://code.visualstudio.com/docs/configure/profiles) | Different tasks can use different editor configurations. | Four explicit layout presets and durable local preferences. Named user profiles remain optional future work. |
| [Zotero: collections and tags](https://www.zotero.org/support/collections_and_tags) | A library item can belong to several collections organised by project, course or topic. | Projects refer to existing library books; collecting a passage does not create another copy of the book. |
| [Zotero forum: recovering closed tabs](https://forums.zotero.org/discussion/118379/recovering-closed-tabs-on-desktop-software) | A September 2024 reader reports losing open PDF tabs after a restart; the discussion describes saved session state. | Book order and each book's side editors, selected note and notebook section survive restart. |
| [Obsidian community: academic literature workflows](https://www.reddit.com/r/ObsidianMD/comments/1jm2kqg/what_is_your_academic_literature_workflow/) | The March 2025 discussion describes writing across papers with references back to the sources. | A personal synthesis beside the PDF, a source ledger with original crops, and clickable citations back into each book. |

Forum posts are individual reports, not a representative user study. These features also have established precedents in editors and reference managers. This increment does not establish novelty, adoption or a measured improvement in research outcomes.

## A reproduced local problem

In 1.0, presenting a book cleared `sideEditors` and `activeSideEditorID`. The existing notes and notebooks remained on disk, but the reader's open editor group was lost. The new book-specific session records stable editor IDs and restores valid editors without running Python code. Projects have their own local manifest and source assets, separate from book workspaces.

The final native restart also exposed a reading-position shift: the page and zoom survived, but the destination moved within the page. A hosted SwiftUI/PDFKit regression test reproduced the failure. The reader now chooses its display mode first and restores the saved destination after the workbench has laid out the PDF pane. This protects the existing reading-position contract.

## Completing the formula reader

`PageInk.swift`, `FormulaSymbols.swift` and `FormulaReader.swift` existed after the last handoff but were not connected to a usable app flow. A duplicate `PageLines` type prevented compilation. The resumed reader now opens from a selection, an equation's Symbols context menu or its reference preview. It shows the original passage, editable LaTeX and a typeset preview, then lets the reader copy the result or create a source-linked derivation.

The test fixture is a real PDF compiled from [formula-layout.tex](../Tests/LemmaCoreTests/Fixtures/formula-layout.tex), covering scripts, accents, sums, derivatives, fractions, a matrix, an integral, a root and a nested fraction. The native flow was also exercised on ESL equation (2.3), the residual sum of squares.

The reconstruction is geometric and heuristic. A count of recognized glyphs does not validate their arrangement. It does not read arbitrary scanned formulas, guarantee unfamiliar font mappings, resolve a symbol's mathematical meaning or prove an equation. The visible comparison and correction step is part of using it.

## Scope kept bounded

Projects provide questions, book membership, collected crops and annotations, a Markdown/LaTeX synthesis, scoped search, export, and reversible archiving. They do not add cloud synchronization, a citation-manager database, an automatic literature-review writer, a general plugin system or a scientific knowledge graph. These would need separate evidence and product decisions.
