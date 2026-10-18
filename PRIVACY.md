# Privacy

Lemma reads your books on your Mac. It has no account, no analytics, no crash reporting and no advertising, and it never uploads your library, notes or reading history. It contacts a network service only when you click something that says where it goes, and the list below is complete.

## What stays on your Mac

- Your PDFs stay where they are. Lemma reads them in place and never modifies them (exports such as **Export My Edition as PDF** write new files).
- Everything Lemma makes is local: notes, highlights, drawings, reading positions, analyses of books, search indexes, Lab notebooks, derivations, research projects and settings. It lives in `~/Library/Application Support/Lemma` and in Lemma's preferences.
- Book analysis, page search, OCR (Apple's Vision framework) and the Lab's Python run on your Mac, in Lemma's own processes or yours.
- API keys you enter for OpenAI, Anthropic or Google are stored in your macOS Keychain, never in files or settings.

## When Lemma uses the network, and what it sends

| You click | Service | What is sent |
| --- | --- | --- |
| **Get** on a free textbook (Catalog) | The book's official website (authors or publisher) | A download request for that PDF. |
| **Search arXiv**, **Add arXiv:…**, open an arXiv link | arXiv (export.arxiv.org, arxiv.org) | Your search words or the paper's identifier. |
| **Find the Paper** in a citation's peek | Crossref, Semantic Scholar, arXiv | The printed text of that one reference. |
| **Ask** (⌘K) or **Get help…** with ChatGPT Web | chatgpt.com, in a browser view inside Lemma, under your own ChatGPT account | The question you prepared: the passage you selected (text and an image of it), the context you chose (cited equations, your notation and glossary entries, the book's title and section). |
| **Ask** with Codex or Claude Code | OpenAI or Anthropic, through the official command-line tool you installed and signed in to | The same question. |
| **Ask** with an API key (OpenAI, Anthropic, Google Gemini) | That company's API | The same question, with your key. |
| **Check for Updates…** (or once a day, if you agreed to automatic checks) | GitHub (github.com and its download servers) | A request for the public description of the latest release, which names Lemma's version. Nothing is downloaded: you download the new version from the release page if you want it. Nothing that identifies you or your Mac. |
| **Report an Issue…**, **Lemma on GitHub**, a book's page, a DOI, Google Scholar | Your web browser opens the page | Nothing until you submit something there yourself. |

What you send to an assistant is shown before it leaves when you use **Review**, and the assistant's own terms and privacy policy apply to it. University libraries generally allow sending short excerpts of licensed books to such services, but not whole books: Lemma only ever sends the passage and context you chose.

## Other programs Lemma starts

- The **Lab** runs the Python 3 installed on your Mac (or the environment **Set Up Python for the Lab** creates in Lemma's folder), only when you run a cell.
- **Codex** and **Claude Code** are run as installed, with their own sign-in; Lemma does not read or store their credentials. Signing in opens the provider's page in your browser.
- The optional **Chrome companion** (for adding arXiv papers from Chrome) talks only to Lemma on your Mac.

## Removing Lemma's data

Quit Lemma, then delete `~/Library/Application Support/Lemma`, `~/Library/Preferences/com.lemma.app.plist` and, if you used ChatGPT Web, `~/Library/WebKit/com.lemma.app`. API keys can be removed in **Settings › Assistants** or with Keychain Access (items named "Lemma Assistant Keys").

Questions: open an issue at https://github.com/SonglanNie/lemma/issues.
