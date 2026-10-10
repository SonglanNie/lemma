# Libraries and arXiv

Lemma lists PDFs from watched folders in the Explorer's **Library** section and in the Classic library (2.1), and since 2.4 organises them as a tree you can rename and rearrange. A new PDF appears after the filesystem reports it, usually within a few seconds. Nested folders are included and shown as a tree.

Renaming a PDF or a watched folder in Finder updates its source path automatically, including PDFs added individually. Lemma keeps the book in its collection and preserves its notes, selected note and reading position. The source links survive an app restart; a PDF excluded from one library stays excluded after a rename. Removed or inaccessible sources are still reported in **Manage Sources** and the collection.

## Default libraries

A new Lemma has two libraries:

| Library | Source | Fills up when |
| --- | --- | --- |
| Books | Lemma's `Books` folder (`~/Library/Application Support/Lemma/Books`) | you **Get** a free textbook from the Catalog |
| Papers | Lemma's `Papers` folder | you add an arXiv paper |

Add your own with **Add a Folder of PDFs…** on the Welcome page, **File › New Library…**, **File › Manage Library Sources…**, or by dropping a folder from Finder on the empty space under the Library's rows. A library can watch several folders and single PDFs; nested folders are included and shown as a tree. Discovery reads file metadata only: Lemma does not open or analyse every PDF it lists. Selecting a PDF opens the original and creates or restores its study workspace. Download a cloud-only file (iCloud Drive, OneDrive, Dropbox) in its app if its contents are unavailable when opened; folder watching follows local sync changes and never contacts the cloud service.

## Use and manage a library

Lemma 2.4 shows the Library as a tree, in both interfaces: libraries, the sections that group them, their watched folders as on disk (folders first), then PDFs. Click anywhere on a row to open it: a library, section or folder opens or closes, and a PDF opens in the reader. The chevron still works on its own. **Filter libraries and PDFs** searches names and folder paths and highlights the matches, revealing them across closed folders. Go to (⌘P) also finds discovered PDFs. A PDF already studied restores its notes and reading position.

Each row shows what it holds: libraries, sections and folders count their PDFs; a PDF shows its reading progress (a ring, then a check when finished), a badge for notes due for recall, and its filename beside a name given in Lemma. Books open in tabs are drawn slightly bolder. The Library follows the book in front: opening a book selects its row and opens the libraries and folders around it (**Reveal Book in Library** does it on demand).

The keyboard works as in Finder and VS Code once a row is selected: ↑ and ↓ move, → and ← open and close or go to the parent, typing letters jumps to a name, Space opens a PDF and keeps the keyboard in the Library, ⌘↓ opens it and moves to the page, Return renames, ⌘⌫ moves to the Trash and Escape clears the selection. ⌘-click adds a row to the selection and ⇧-click selects a range; actions then apply to every selected row. From the filter field, ↓ moves into the tree.

The view's “…” menu (beside the filter, and in the **LIBRARY** header) creates a library, sorts PDFs by name, recently opened or reading progress, collapses everything, reveals the book in front, refreshes and opens **Manage Sources**. **File › Manage Library Sources…** remains the place to see every source path, stop watching one, or create a library with its type and folders.

## Organise the Library

### Rename

Select a row and press **Return**, or right-click and choose **Rename…**. A field replaces the name; Return saves it, Escape cancels and clicking elsewhere keeps what you typed. For a PDF, choose what the rename changes:

- **Lemma**: the name Lemma shows in the Library, tabs and Go to. The file keeps its name. A PDF never opened keeps this name until it is opened, then it becomes the book's title.
- **File**: the PDF's filename on disk (`.pdf` is kept). Its notes, reading position and library follow it. A book whose name in Lemma was still its filename takes the new name too; a name you gave in Lemma stays.
- **Both**: the same new name for Lemma and the file. Characters a filename cannot hold (“/” and “:”) become “-” in the file only.

Lemma remembers the last choice. A name already used in the folder, an empty name or a name containing “/” or “:” is refused before anything changes, with the reason under the field. **Rename File on Disk…** in the context menu opens the field directly on File. Renaming a library or a section changes only its label; renaming a folder renames it on disk, and the books inside it follow.

### Move PDFs, folders and libraries

- **Onto a library**: drag PDFs or folders there to file them in that library. The files stay where they are; Lemma lists them in the new library and no longer in the old one (a watched folder excludes them). Hold **⌥** to keep them in both. **Move to Library** and **Also List In** in the context menu do the same without dragging, and **Remove from Library** stops listing a PDF or folder while keeping the file.
- **Onto a folder**: drag PDFs or folders there to move the files on disk, into that folder. Lemma asks first (“Do not ask again” is offered) and their notes follow.
- **Libraries**: drag a library onto another one to put it inside, or near the top or bottom of a row to place it before or after. A library inside another is named after the group it belongs to, so sub-libraries follow when their library is renamed. Sections (such as **School**) move as a whole. **Move To** in a library's context menu also puts it in a section, at the top level or in a **New Section…**.
- **Other PDFs**: drag the row onto a library to file every book in it at once.
- **From Finder**: drop PDFs or folders on a library to add them where they are (folders are watched), PDFs on a folder to copy them there, or a folder on the empty space under the rows to make it a new library.
- **Out of Lemma**: drag a PDF to the right edge of the page to read it beside the current one, onto a project to add it, or to Finder or another app to copy the file.

While dragging, a banner at the bottom of the Library says what a drop will do.

### Libraries, folders and the Trash

**New Library…** (the folder button beside the filter, the view's “…” menu or File › New Library…) opens a name field where the library will appear; PDFs and folders can then be dropped on it. **New Library from This Folder** turns a folder of a library into a library of its own, and **New Library from Folder…** makes one from a folder you choose. **Library Type** switches between Books / Novels, Studying Library and Papers, which changes its icon. **Remove Library…** asks first; the files, notes and reading positions stay on this Mac.

**Move to Trash…** (⌘⌫) asks first, then moves the files to the macOS Trash. Lemma keeps the books' notes and reading positions.

**Edit › Undo (⌘Z)** undoes every Library change: a rename in Lemma or on disk, a move between libraries or folders, a new or removed library, a change of order or type, and Move to Trash (the files come back). Redo applies it again.

### Where this is saved

Libraries, their order, sections, types and exclusions are in `~/Library/Application Support/Lemma/Libraries.json`. Names given in Lemma to PDFs not opened yet are in `LibraryTitles.json` beside it; a studied book's name is in its workspace. What is open or closed in the tree and the sort order are kept in Lemma's preferences.

Removing a source only stops watching it. Original PDFs, notes and reading positions remain. Previously studied PDFs outside the current sources appear under **Other PDFs**; files sent to the Trash do not. Workspace schema remains 10.

## Read two PDFs side by side

Drag a PDF from **Library** onto the right edge of the reader. The highlighted **Open to the Side** area opens a second PDF pane; dropping elsewhere in the main reader opens the PDF in its main tab. Drop onto an existing side pane to open another tab there. Both VS Code and Classic support this, including PDFs you have not opened before.

Drag the current PDF to the side to read two places in the same file. Each view scrolls and zooms independently, and side tabs keep their own page, zoom and position across tab switches and restarts. Dropping the same PDF again selects its existing side tab. **Open to the Side** in a Library row's context menu offers the same action without dragging.

The notebook temporarily steps aside in a narrow window to make room for both PDFs, and returns when the last wide side editor closes. Drag the divider between the PDF panes to resize them. Use the side tab's **×** to close it, or **⌘\\** while its PDF is active. With no main PDF open yet, the first dropped PDF opens in the main reader.

## Find and download an arXiv paper

Open **Catalog** (⇧⌘X), select **arXiv Papers**, enter a title, author, topic, identifier or arXiv URL, and choose **Search**. Results show authors, dates, categories and an expandable abstract. **Newest** changes sorting; **More Results** loads the next page. Advanced queries such as `au:Vaswani`, `ti:regression` and `cat:q-fin.ST` are accepted.

Choose **Add to Lemma** to download and open a paper. Pasting an identifier or URL also exposes a direct **Add arXiv:…** button. Downloads go to `~/Library/Application Support/Lemma/Papers` and remain readable offline. Re-adding an already downloaded identifier opens its existing copy. An explicit `v6` or `v7` stays separate; an unversioned identifier requests arXiv's current version when first downloaded.

Only the entered search and requested paper identifier are sent to arXiv. Local PDF contents and notes are not uploaded. Search requires the remote service unless that query has a cached response. Responses are cached for one day; requests are spaced by at least three seconds, following the [arXiv API guide](https://info.arxiv.org/help/api/user-manual.html).

## Quick Add from Chrome

Use the existing Chrome companion connection described in the [README](../README.md#connect-chrome-once). After upgrading it to 0.2, reload the extension in `chrome://extensions`.

Open an arXiv abstract, PDF or HTML page. In Chrome's Extensions menu, click **Lemma, reading companion**, or click its pinned button. It sends the page's arXiv identifier through the local bridge; Lemma opens or downloads that exact paper into **Papers**. A check badge means the request reached Lemma; download failures are shown in the app. Other sites show a question badge and send no import request.

The new permission is Chrome's [activeTab](https://developer.chrome.com/docs/extensions/develop/concepts/activeTab), granted when the button is clicked. The companion has no persistent access to every arXiv page and needs no ChatGPT login for Quick Add.
