# Lemma 2.0: a VS Code workbench, and what readers asked for

Consulted 2 October 2026, for a 2.0 that is a real IDE, inspired by VS Code's design and UI (buttons, font, layout), for students and researchers, informed by forums and posts; it also fixes one bug (the 1.1 Midnight theme did not apply). Settings lets the reader choose between the VS Code look and the previous version.

## VS Code's design, from its source

The workbench is modelled on VS Code's own code rather than screenshots. Its source, `microsoft/vscode`, was read at commit `6ac40e93521e5d9222fb09b6e1227dd2c85e915c` (main, 2 October 2026), and these values recorded with file and line:

| What | Value used in Lemma | Source in VS Code |
| --- | --- | --- |
| Title bar with the command center | 35 pt; window controls at (10, 9); command center 22 pt high, ≤ 600 pt wide, 6 pt corners, 12 pt text | `platform/window/common/window.ts`, `titlebarpart.css`, `windowImpl.ts` |
| Activity bar | 48 pt wide, 48 pt items, 24 pt codicons, 2 pt active bar on the left, badges at top 24 / right 8 | `activitybarPart.ts`, `activityaction.css` |
| Side bar title, pane headers, rows | 35 pt titles (11 pt uppercase, text at 20 pt); 22 pt pane headers (11 pt bold uppercase, 16 pt chevron); 22 pt rows, 8 pt indent, 16 pt twistie | `part.css`, `paneview.ts/.css`, `explorerViewer.ts`, `abstractTree.ts` |
| Editor tabs and breadcrumbs | 35 pt tabs, 10 pt padding, at least 120 pt wide, 28 pt close slot, 1 pt top border on the active tab; 22 pt breadcrumbs with 16 pt chevrons | `editorTabsControl.ts`, `multieditortabscontrol.css`, `breadcrumbsControl.ts` |
| Panel and status bar | 35 pt panel titles (11 pt uppercase, 1 pt active line); 22 pt status bar, 12 pt text, items padded 5 pt | `paneCompositePart.css`, `statusbarpart.css` |
| Quick input | min(62 % of the window, 600 pt) wide, 6 pt from the top over the title bar, 12 pt corners, 22 pt rows, bold matches, key caps | `quickInputController.ts`, `quickInput.css` |
| Buttons, inputs, checkboxes, key caps, badges | 26 pt buttons with 4 pt corners and 12 pt text; 28 pt inputs; 18 pt checkboxes; 18 pt key caps; 18 pt count badges | `button.css`, `inputBox.css`, `toggle.css`, `keybindingLabel.css`, `countBadge.css` |
| Fonts on macOS | the system font at 13 pt; Menlo 12 for code | `workbench/browser/media/style.css`, `editor/common/config/fontInfo.ts` |

The 497 colour ids Lemma reads carry VS Code's registered defaults for the dark, light and two high-contrast kinds (`platform/theme/common/colors/*.ts`, `workbench/common/theme.ts` and contributions). Lemma resolves a theme as VS Code does, the theme's colour, else the default expression evaluated with the same theme (`transparent`, `lighten`, `darken`, `oneOf`, `lessProminent`, `ifDefinedThenElse`, `mix`), and a test compares 1,988 resolved defaults with vectors computed by a port of VS Code's colour arithmetic.

**Themes.** The 19 built-in themes are flattened from the same commit (`extensions/theme-*`, MIT). Community themes come from the `tm-themes` 1.12.12 npm package (MIT; each theme's own licence is listed in `Sources/Lemma/Resources/Themes/LICENSES.md`, all MIT or Apache-2.0; Aurora X, GPL-3.0, was left out); Moonlight and Moonlight II come from the `atomiks.moonlight` 0.11.1 extension (MIT). The licence texts ship in `THIRD_PARTY_NOTICES.txt`. **Icons.** Codicons 0.0.46-42 (`@vscode/codicons`), CC BY 4.0, with the licence in `Resources/Codicons`.

**Observed choices.** VS Code 1.139.1's built-in themes include Dark 2026 and Light 2026, the current defaults, which Lemma used by default until 3.0's own themes. VS Code's experimental "Modern UI" (floating cards) is on by default only on main; Lemma follows the classic layout, which 1.139 shows.

## What readers of mathematics asked for (2024–2026)

Hacker News threads (through the Algolia API), Reddit (through the Arctic Shift archive), Zotero forums, Sioyek issues and published studies were read as well. Posts are self-selected; this is not a survey. Selected findings that shaped 2.0:

| Pain point | Example (verbatim) | Lemma 2.0 |
| --- | --- | --- |
| Flipping back to an earlier result and finding the way back | "I usually end up just opening multiple copies of the PDF: one for 'linear' reading, and the other(s) for backreferences.", r/math, 2026-03-18 ([link](https://www.reddit.com/r/math/comments/1rxdngj/why_is_learning_math_from_textbook_pdfs_so_painful/ob6bmq7/)) | Peek views, Step Into / Step Out with a call stack, another book beside this one |
| "It made sense while reading" | "It makes sense while I'm reading it, but afterward I often feel like I couldn't explain it properly or work through the reasoning on my own.", r/learnmath, 2026-08-01 ([link](https://www.reddit.com/r/learnmath/comments/1vcepug/)) | Run and Debug (goal, symbols in scope, uses), end-of-proof "Mark as Understood", Testing |
| Lean's proof state as the model | "This is already tremendously useful to students, and completely impractical to emulate on a blackboard or in print.", Massot, ITP 2024 ([paper](https://drops.dagstuhl.de/storage/00lipics/lipics-vol309-itp2024/LIPIcs.ITP.2024.27/LIPIcs.ITP.2024.27.pdf)) | The Variables pane is a reading-time analogue of an infoview |
| Forgetting what a symbol means | "When can we have a PDF reader where we can hover over a symbol and see its definition?", HN, 2024-03-21 ([link](https://news.ycombinator.com/item?id=39776708)) | Symbol hovers (since 0.9) and the symbols in scope while debugging |
| Juggling documents and resuming | "…tab groups which will allow me have papers open but grouped by project.", HN, 2026-07-12 ([link](https://news.ycombinator.com/item?id=48881237)) | Open Editors, the Timeline, library-wide Search, a second book in the side group |
| Distrust of LLM mathematics | "…to identify that it is wrong, you already have to have some understanding of maths.", r/learnmath, 2025-10-22 ([link](https://www.reddit.com/r/learnmath/comments/1odbfsl/does_chatgpt_really_suck_at_math/nksp190/)) | Checked derivations and Check n Steps on saved answers (since 1.0) |

Ideas the research ranked high that 2.0 does not yet implement, kept for later decisions: a derivation whose *goal* is the next displayed equation ("bridge the gap"), a "frontier" switch that limits a question's context to the pages already read and a hint ladder, a dependency map coloured like a Lean blueprint with a prerequisite check, citation lenses showing which references are already in a project, and equations read aloud.

## Limits

The look follows VS Code's metrics and colours; it is not VS Code, and Lemma uses AppKit and SwiftUI controls where VS Code draws its own (native menus, sheets, some popovers). The proof debugger reads the structure Lemma finds in the PDF (statements, proofs, citations, notation sentences); where that analysis misses a statement or a citation, stepping falls back to the next line. It does not verify a proof. Theme import reads VS Code colour themes (`colors`, `tokenColors`); semantic token colours and product icon themes are not used.
