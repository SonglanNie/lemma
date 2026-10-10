# Chrome companion (legacy question connection and arXiv Quick Add)

Since Lemma 2.3, normal study questions use the [Assistants panel](ASSISTANTS.md): ChatGPT Web is embedded in Lemma, and Codex / Claude Code use their official subscription CLI. The Chrome companion remains available for arXiv Quick Add and collecting earlier Chrome handoffs. It is not required for the new question experience.

The historical companion setup and protocol are retained below.

# ChatGPT Web connection

Lemma's Chrome companion transfers a reviewed study question into the visible ChatGPT Web composer. It offers a prepared draft and an explicit send-and-save mode. The implementation was inspected and tested against the logged-in page on 30 September 2026; the Web interface may change.

## Setup

Build with `scripts/build-app.sh`, open `build/Lemma.app`, and use **Chrome companion → Prepare connection**. This registers the packaged `LemmaBrowserHost` executable in:

```text
~/Library/Application Support/Google/Chrome/NativeMessagingHosts/com.lemma.browser.json
```

Alternatively run `python3 scripts/install-chrome-host.py build/Lemma.app` from the repository. The registration accepts only the companion's fixed extension ID, `jkdnfdclkogopbhlihppdodgkfkhfpkc`.

In `chrome://extensions`, enable Developer mode and load `build/Chrome Companion` with **Load unpacked**. This is an ordinary directory next to the app, because Chrome's folder picker does not expose app bundle contents as ordinary folders. Sign in to ChatGPT yourself. No credentials are copied into Lemma.

Keep the app path stable. If the app moves, prepare the connection again. After a companion code update, use **Reload** on the extension card; already open handoff tabs retain their earlier script, so start a fresh question after reloading.

## Normal use

Create a source note, write its question, and add any useful pins. Choose **Ask** and inspect the editable text and all crop previews. This version includes all current pins; remove unwanted ones before preparing the question.

- **Prepare in Chrome** opens an empty chat, inserts the text, and attaches the PNGs. It does not press Send. After you send and receive a completed answer, choose **Save answer to note** in the small Lemma panel.
- **Ask and save** performs one Send click after preparing the same material. It waits for a completed assistant turn, saves its text and conversation URL locally, and returns the explanation to the original note.

Keep Lemma running for immediate return. Pending request identifiers are persisted, so an answer already returned by the companion can also be collected when its document is reopened. The Chrome panel's **End handoff** stops that handoff while keeping the draft or conversation in Chrome. Lemma also exposes **End browser handoff** for a pending note.

The answer remains editable. Formula source exposed by ChatGPT is saved as Markdown LaTeX; Lemma currently shows that text in an editor rather than typesetting it. The saved conversation link provides the rendered Web version.

## Transfer and scope

The app writes a packet containing a request UUID, original note UUID, chosen mode, prompt, image names and sizes, and timestamp. The new tab's URL contains only `#lemma=<UUID>`. The companion reads that local packet through Chrome native messaging, then fills the ordinary page controls. PNG bytes travel in 96 KiB chunks and are checked against the prepared sizes.

The helper serves image names listed in an unexpired prepared packet, rejects path traversal, and accepts result links only from HTTPS on `chatgpt.com`. The Chrome background worker accepts requests only from its content script on that origin. There is no arbitrary local-file browsing endpoint, exposed HTTP port, hidden ChatGPT endpoint, or authentication-cookie reader.

The installed permissions are `nativeMessaging`, `activeTab` for the clicked arXiv Quick Add action, and access to `https://chatgpt.com/*`. As with other page extensions, the ChatGPT permission grants access to matching pages. The implemented content script immediately exits unless a Lemma handoff UUID is present. It rejects an existing draft, attachments, or previous conversation before insertion, rather than mixing sources with an unrelated chat. [Quick Add](LIBRARIES.md#quick-add-from-chrome) sends only an arXiv identifier through the local bridge; it has no persistent arXiv host permission.

Question packets and returned results remain local under `~/Library/Application Support/Lemma/Browser`. Packets expire after one hour for further transfers; the page wait stops after thirty minutes. Expiry does not delete the local files. A stored complete result can still be collected by Lemma later.

## Limits and recovery

The companion selects the visible **Chat** mode. It makes no native subscription inference or provider API call. The site's account limits, model availability, uploads, authentication, and response correctness remain outside Lemma's control. Usage accounting was not isolated or measured by these tests; the integration is not a quota bypass.

If no Lemma panel appears, verify the extension is enabled and start a fresh question. If Chrome reports the native host unavailable, prepare the connection again and check the app path. If the composer is already occupied, retain it and prepare a fresh empty chat. If sending or answer collection fails, review the visible page and use the explicit copy/paste actions; the app does not silently switch providers.

For manual fallback, **Copy text** and **Copy source image** operate separately. Paste the prompt and crop into ChatGPT, then copy the useful explanation and invoke **Paste explanation** on the intended note. Pins remain visible in Lemma and are included by the automatic connection; the manual copy-image button copies the primary source crop.

To disconnect, disable or remove **Lemma Chrome Companion** in Chrome. The specific `com.lemma.browser.json` registration can be removed separately. Workspaces and their saved explanations are independent of the browser connection.
