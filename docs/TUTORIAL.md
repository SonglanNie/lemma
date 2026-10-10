# The Lemma Tour

Since 2.5 the Lemma Tour is six steps on the reader's own window, about two minutes, and nine short guides go deeper on one subject each, three or four steps at a time. Every step lights up the part of the real window it explains and points at it; a step whose part is not on screen (the page, before a book is open) shows its animation instead. The 2.2 tour, eighteen chapters and a hundred steps on a card over the window, is gone.

## Opening it

- **First launch:** the tour opens by itself, once, on a welcome page that also chooses the **interface** (VS Code or Classic, switched live behind the page), then a page for the **colours** (Lemma's own themes when the build has them, the reader's VS Code theme, a few favourites with a live preview on hover, or the Classic appearances; accent; page theme), then the six steps and a last page. The flag `tutorial.shown` is set as soon as it opens, so it never opens by itself again, even if Lemma quits during the tour.
- **Afterwards:** **Help › Lemma Tour** starts the tour where it was left (from the beginning once it has all been seen). **Help › Lemma Guides** opens the guides at a glance, or one guide directly. The command palette has `Help: Lemma Tour`, `Help: Lemma Guides` and `Help: Lemma Guide › <guide>`; the gear menu of the activity bar has Lemma Tour and Lemma Guides; the tour's card on the Welcome page (VS Code) and on the library home (Classic) offers the tour, then the guides once the tour has been seen.
- The offer to use the reader's VS Code theme, made once after the update to 2.0, waits until the tour closes on a first launch (the colour page offers the same theme).

## The tour

1. **Start with a book:** the Library in the side bar; Open a PDF… and Free Textbooks.
2. **Go anywhere by typing:** the command center (⌘P, ⇧⌘P); Try Go To.
3. **References are links:** the page; hover to preview, click to peek, ⌥⌘← to come back.
4. **Select, then act:** the selection bar (⌘K, ⇧⌘S); Capture a Region.
5. **Your notebook:** the secondary side bar, on Notes (⌘N, ⌥⌘B).
6. **Every tool has a view:** the activity bar (⌥⌘1, ⇧⌘D); the guides go on from there.

Then **You're ready**: six shortcuts worth keeping, Explore the Guides, and Open a PDF… or Free Textbooks when no book is open (Start Reading otherwise).

## The guides

- **Your Window:** layouts and Zen Mode (the layout controls), the same book twice (the tabs), the panel, the status bar.
- **Reading:** Go to anything (its syntax), preview, peek and come back, look up a term and a symbol, the reading ruler and “?” marks.
- **Proofs:** Results (the side bar), folding a proof, what it uses and what uses it (the Hierarchy panel, the map), stepping through a proof (Run and Debug).
- **Checked Derivations:** starting one, every line checked, checking an answer and reading a formula as LaTeX.
- **The Lab:** a notebook beside the page, running cells gently, the Python console, figures beside the book's.
- **Notes and Your Edition:** notes keep their source (the notebook), highlights and margin notes, the glossary and pins, drawing on My Edition.
- **Ask an Assistant:** asking about a passage, the context sent, ChatGPT Web, Codex and Claude Code.
- **Remember and Research:** Review, searching every book, research projects, where your data lives.
- **Make It Yours:** colour themes, the two interfaces, Settings and Keyboard Shortcuts.

## What it looks like

- **A step** is a callout of 352 pt in the theme's widget colours (`editorWidget.background`, its border or a hairline, `widget.shadow`), with a beak on the edge that faces the part it explains: beside a tall part (right, then left), under or over a wide one, inside a part that leaves no room around it (the page). The rest of the window is dimmed (black at 42 % in dark themes, 26 % in light ones) around a rounded hole outlined in the button colour made readable; the hole glides from one part to the next. The window stays usable under the tour: the reader can hover a reference on the lit page.
- **Without its part on screen** (no book, a hidden minimap, Zen Mode's hidden bars) the step is a card of 560 pt in the middle, over a lighter dim, with the step's animation on top and Replay; a step about the page says that it lights up once a book is open, with Open a PDF…. In the Classic interface the command center and the layout controls sit in the toolbar, above what the tour draws over: the callout points up at them from the top of the window, and the toolbar is the only part left undimmed.
- **Show Me is automatic.** Entering a step shows its part if it is hidden (the Library, Results, Run and Debug, Search, Projects in the side bar; the panel; the notebook on Notes, Glossary or Review; Zen Mode is left) and lights it. Closing the tour hides again what it showed, unless the reader changed that part since. The console is never opened by the tour itself (it looks for Python when it appears): its step has an Open the Console button.
- **Inside the callout:** a strip of one segment per step (each opens its step), the title (15 pt semibold), one or two sentences (13 pt), at most two shortcuts as key caps, the step's actions (Try Go To, Open a PDF…, Start Debugging…), and Skip Tour or All Guides, Back and Next (Finish on the tour's last step, Done on a guide's).
- **Try It:** an action runs on the real window and the tour waits in a pill at the bottom (Resume, close). Actions that create something say so in their title and run only when clicked; actions that need a book, a selection or the book's analysis are disabled until there is one.
- **Pages** (welcome, colours, the guides at a glance, the last page) are cards of 520 to 720 pt over the dimmed window, sized to their content, scrolling inside a small window. The guides at a glance list the tour first (Take the Tour, Continue, Take It Again), then the nine guides with their steps seen, and a search field over every step.
- **Keys:** while nothing else in the window has the keyboard, ← and → move, Return continues and Escape closes; moving through the tour takes the keys back. A shortcut with ⌘, ⌥ or ⌃, or a function key, reaches the window and the tour waits in its pill so its effect shows (⌥⌘← and ⌥⌘→ navigate the reader).
- **Motion:** the hole and the callout move together on a spring; text changes fade. Each animation plays once when its card appears and then rests; nothing repeats forever, and the tour costs no CPU while it is open and idle. Reduce Motion shows each animation's last frame at once.

## Code

- `Sources/Lemma/Tutorial/TutorialModel.swift`: targets (`TutorialTarget`, reported with `.tutorialAnchor(_:)`, which keeps the anchors of the parts inside it), steps, guides, actions, `TutorialLayout` (what the tour showed, to hide it again) and `TutorialCenter`: the screens (welcome, colours, guides, a step, the last page), the pill, persistence (`tutorial.shown`, `tutorial.seen`, `tutorial.position`) and keys.
- `TutorialContent.swift`: the tour and the guides. A step has an id, a title, a body (and a `classicBody` where the Classic interface differs), up to two shortcuts, an animation, an optional target with a `reveal` closure, and actions.
- `TutorialOverlay.swift`: the overlay over both interfaces (`overlayPreferenceValue` in `ReaderWindow`), `TutorialCoachLayout` (where the callout goes and where its beak points, a pure function), the callout, the progress strip, the spotlight and the pill.
- `TutorialIntro.swift`: the welcome, the colours, the guides at a glance, the last page, and the tour's card for the Welcome page and the Classic home.
- `TutorialKit.swift`: surfaces, `CoachBubble` (the callout's shape with its beak), buttons drawn as the workbench's, key caps, prose, `ScenePlayer` (plays an animation once) and the demonstration pointer.
- `TutorialScenes*.swift`: the animations, drawn at 640 × 320 pt and scaled to the card, in the theme's colours, including `MiniWorkbench`, the window in miniature in either interface.
- `TutorialQA.swift`: the QA actions below.

To add a step, append a `TutorialStep` to its guide, give it a `TutorialScene` (a case and its view in `TutorialSceneView`), and for Show Me a target that some view reports with `.tutorialAnchor`. Keep a guide to three to five steps and a body to two sentences.

## Checking it

`swift test --filter TutorialTests` checks the content (a tour of at most seven steps that all light up the window, guides of three to five steps, unique ids, no em dashes, bodies that fit the callout, at most two shortcuts), key caps, the first launch, the tour to its last page, guides resuming and closing, search, Show Me revealing a part and closing hiding it again, actions and the pill, where the callout goes, keys, and that every page and step draws in both interfaces.

A QA copy launched with `LEMMA_QA_DIR` keeps the tour closed unless `LEMMA_SHOW_TUTORIAL=1` is set; with `LEMMA_QA_CHANNEL=<name>` it listens on `com.lemma.qa.<name>`, so two QA copies can run at once. QA actions: `tutorial` (the guides at a glance), `tutorialTour`, `tutorialGuide id=…`, `tutorialStep id=…`, `tutorialScreen value=welcome|look|home|finish`, `tutorialNext`, `tutorialBack`, `tutorialPause`, `tutorialResume`, `tutorialClose`, `tutorialReplay`, `tutorialAction index=…`, `tutorialQuery value=…`, `tutorialWindowSize value=960x640`, `tutorialFirstLaunch` and `tutorialState` (the screen and step, and for a step whether it is lit, carded or pointing at the toolbar, with the frames of the callout and the lit part).
