# Assistants inside Lemma (3.0)

Select a passage and press **⌘K**, or prepare a saved note's question with **⌘E**. Choose one of six assistants: **ChatGPT Web**, **Codex**, **Claude Code**, the **OpenAI API**, the **Anthropic API** or the **Gemini API**. ChatGPT Web is the default. The choice is remembered and is also available in Settings → Questions → Assistant.

The selected crop, the ticked context images and the exact draft go to the chosen assistant. Every answer is saved to the original note, even if you select another note or open another book while waiting. The original PDF is not modified. Existing explanations remain until a complete new answer arrives.

## What is sent, and where

Nothing leaves the Mac until you click **Ask and save** or **Review in Lemma** (or **Check** for an API key). Opening Assistants › Connections loads nothing from chatgpt.com until you click **Connect ChatGPT**.

| Assistant | How Lemma reaches it | What is sent, and to whom | Credentials |
| --- | --- | --- | --- |
| ChatGPT Web | chatgpt.com in an embedded WebKit page | The ticked images and the draft, to chatgpt.com under your ChatGPT account | WebKit's own cookie store, separate from Safari and Chrome |
| Codex | Your installed `codex` CLI | The images and the draft, to OpenAI through Codex | Codex's own sign-in (ChatGPT account or API key); Lemma never reads it |
| Claude Code | Your installed `claude` CLI | The images and the draft, to Anthropic, or to the cloud provider you set up for Claude Code | Claude Code's own sign-in; Lemma never reads it |
| OpenAI API | HTTPS from Lemma | The images and the draft, to `api.openai.com` (Responses API, `store: false`) | Your key, in the Keychain |
| Anthropic API | HTTPS from Lemma | The images and the draft, to `api.anthropic.com` (Messages API) | Your key, in the Keychain |
| Gemini API | HTTPS from Lemma | The images and the draft, to `generativelanguage.googleapis.com` | Your key, in the Keychain |

Usage is billed to your own account with each provider; Lemma has no account or server of its own. Google's Gemini API terms differ between the free and paid tiers. Each provider's own data policy applies to what it receives.

## ChatGPT Web

Open **Assistants…** from Study, Help or the activity bar, then **Connections → ChatGPT Web**, and click **Connect ChatGPT**. Sign in to ChatGPT inside this panel with your email address: Google and Apple sign-in may refuse to work inside an embedded browser. This is a separate WebKit session from Safari and Chrome: Lemma does not copy their cookies or credentials. The embedded browser keeps the signed-in session between launches. The user's normal ChatGPT account, model selection and limits apply.

- **Ask and save** prepares the images and text, clicks Send once, and saves the completed answer automatically.
- **Review in Lemma** prepares the same draft in the embedded ChatGPT page. You review or edit it and press the site's Send button. The completed answer is then saved automatically.

Each question loads a new chat in full (never a `#fragment` change of the page already shown, which WebKit treats as same-document navigation without a load event). If the page loads without starting the adapter, Lemma starts it directly; a page that fails to load, or whose WebKit process ends, reports an error and keeps the note. **Close page** unloads chatgpt.com; Lemma also unloads the page and releases its web view 90 seconds after the last question ends or the panel closes, so an idle WebKit process does not keep using memory and CPU. You stay signed in.

The Web page remains available in the Questions panel while a question runs. **Continue reading** closes the panel without ending the question. Use Assistants or **Show** on the source note to return to it. **Cancel question** ends local collection and clicks the site's Stop control if generation is still running. ChatGPT may already have processed a cancelled request.

One ChatGPT question runs at a time in its embedded page. Lemma does not replace an existing draft or continue an unrelated conversation. Sign-in popups are kept in the same Lemma panel. A CAPTCHA or verification step belongs to the user.

The adapter operates the ordinary Web composer. It finds the composer, Send, Stop and Copy controls by their ids and `data-testid` attributes first, so a ChatGPT interface in another language works; English accessibility labels are fallbacks only. It does not call a private ChatGPT endpoint or read authentication cookies. ChatGPT can change its page structure; preparation failures appear in Lemma and keep the source note. There is no automatic retry or switch to a different provider. The old Chrome companion is still supported for previously prepared handoffs and arXiv Quick Add; it is no longer required for normal questions.

## Codex and Claude Code

Lemma runs your installed, unmodified CLI with the sign-in it already has. Every method the CLI supports works as you set it up: for Claude Code a Claude account, a Claude Console account, an API key (`ANTHROPIC_API_KEY` or an `apiKeyHelper`), an OAuth token, or a cloud provider such as Amazon Bedrock, Google Cloud's Agent Platform or Microsoft Foundry; for Codex a ChatGPT account or an API key. Lemma does not remove credentials or provider settings from the CLI's environment, adds none, never forces a login method and accepts every account type. (Variables exported only in shell start-up files are not seen by apps opened from the Finder; Claude Code's `settings.json` `env` block works.)

**Connections** shows how the CLI reports its sign-in, for example “Signed in · API key”. When the status command fails, the panel shows the command, its exit code and the end of its error output, such as `codex login status exited with code 127: env: node: No such file or directory.`

**Sign-in** runs the CLI's own command: **Sign in with Claude account** (`claude auth login`), **Sign in with Claude Console** (`claude auth login --console`), **Sign in with ChatGPT** (`codex login`) or **Use a device code** (`codex login --device-auth`, which must first be enabled in ChatGPT's security settings). The CLI opens the provider's own page in your default browser, where sign-in completes. Lemma shows the CLI's output as it arrives, offers **Open sign-in page** if the browser did not open, and passes on a code you paste if the page shows one. Lemma never sees a password or token, and the CLI stores its own credentials. The same command can be copied and run in Terminal instead. Closing the panel cancels an unfinished sign-in.

**Finding the CLI.** An app opened from the Finder starts with launchd's minimal PATH. Lemma asks your login shell for its PATH once per launch (`zsh -ilc`, or your login shell if it is bash, sh, ksh or dash; the value is written to a file, with a 4 second timeout) and adds Homebrew, `~/.local/bin`, Volta, the newest nvm Node, fnm, asdf, mise, `~/.npm-global/bin` and `~/.bun/bin`; Codex.app's bundled CLI is the last resort. The executable's own folder comes first on PATH, so a `#!/usr/bin/env node` CLI installed under nvm, Volta, fnm or asdf finds the Node it was installed with. The optional **Executable** field accepts a path, `~/…`, a folder or a command name; the optional **Model** field requests a model the account supports. Leave them empty for automatic discovery and the CLI's default model.

**Invocation.** Codex runs `codex exec --ignore-user-config --skip-git-repo-check --ephemeral --sandbox read-only --json --color never -c approval_policy="never" -c features.shell_tool=false`, with `--image` per attachment and the prompt on stdin (`--ignore-user-config` skips `config.toml`; authentication still uses `CODEX_HOME`). Claude Code runs `claude --safe-mode --strict-mcp-config --mcp-config {"mcpServers":{}} --tools "" --disable-slash-commands --permission-mode dontAsk --no-session-persistence --print --input-format stream-json --output-format stream-json --verbose --include-partial-messages`, with text and base64 PNG blocks in the same input message. Safe mode skips CLAUDE.md, hooks, plugins, skills and MCP servers but keeps authentication and settings. Bare mode is not used: it skips the CLI's own sign-in. Codex runs read-only; Claude has no tools. The process runs in the prepared question directory, not in the reader's project. Neither starts a terminal window.

These options follow the current documentation of each CLI. An older CLI that refuses one of the hardening options (“unknown option” or “unexpected argument”) is asked again without it; the options that keep tools off (`--tools ""`, `--sandbox read-only`) are never dropped. Lemma writes the question to the CLI's stdin with `F_SETNOSIGPIPE`: a CLI that exits before reading it produces an error message, never a crash, and output is read as it is printed. Account restrictions, usage limits and unavailable models are reported in Lemma. No quota bypass or particular usage accounting is claimed.

See the official [Codex non-interactive documentation](https://learn.chatgpt.com/docs/non-interactive-mode), [Codex authentication](https://learn.chatgpt.com/docs/auth), the [Claude Code CLI reference](https://code.claude.com/docs/en/cli-reference), [Claude Code authentication](https://code.claude.com/docs/en/authentication) and Anthropic's [terms for products that run Claude Code](https://code.claude.com/docs/en/legal-and-compliance). Lemma names Claude Code and Codex in plain text only; neither name is part of a Lemma feature name.

## OpenAI, Anthropic and Gemini APIs

**Keys.** Paste a key in **Connections** (a secure field) and click **Save**; **Get an API key** opens the provider's key page ([OpenAI](https://platform.openai.com/api-keys), [Anthropic](https://platform.claude.com/settings/keys), [Google AI Studio](https://aistudio.google.com/apikey)). Keys are stored as generic passwords in your login Keychain, in items named “Lemma Assistant Keys” (service `Lemma Assistant Keys`, account `openAI`, `anthropic` or `gemini`). They are never written to settings, study files, question packets or logs, and text shaped like a key is removed from provider messages before Lemma shows or saves them. **Remove** deletes the Keychain item. macOS may ask once whether Lemma may use the item; builds that are not signed with a stable Developer ID ask again after an update.

**Check** sends one request that reads the model's description (`GET /v1/models/{model}` on OpenAI and Anthropic, `GET /v1beta/models/{model}` on Gemini). It needs a valid key and an available model but generates nothing and costs nothing. Lemma sends it only when you click Check.

**Models.** The model field is editable, with a short pick list (as of October 2026):

| Provider | Default | Also offered |
| --- | --- | --- |
| OpenAI | `gpt-6.1-sol` | `gpt-6-astra` (most capable, highest price), `gpt-6-luna` (fastest, least expensive) |
| Anthropic | `claude-opus-5-5` | `claude-sonnet-5-5`, `claude-haiku-5-5`, `claude-fable-5-1` (most capable, highest price) |
| Gemini | `gemini-3.8-flash` | `gemini-3.1-pro-preview`, `gemini-3.5-flash-lite` |

The same fields are in the settings editor under Questions › API Keys.

**Requests.** Each provider receives the same instruction and draft as the CLIs, with each image after a short “Image n: label” line so the numbering in the draft matches the attachments: OpenAI's Responses API with images as data URLs (`detail: high`) and `store: false`; Anthropic's Messages API (`anthropic-version: 2023-06-01`, `max_tokens` 64000, `effort: high` on models that accept it) with images before the text; Gemini's `streamGenerateContent` with inline PNG data and the key in the `x-goog-api-key` header, never in the URL. For Claude Opus 5.5 and 5, Sonnet 5.5 and Fable 5.1, Lemma opts into Anthropic's server-side refusal fallback (`fallbacks: "default"`): a request a safety classifier declines is retried on Anthropic's recommended model in the same call, and the model that answered is recorded. An account without that beta gets a plain request instead.

Answers stream over server-sent events into the Questions panel, which updates a few times a second; **Cancel question** cancels the HTTP request. Reasoning and thinking parts are never kept. Errors are reported as what to do: a rejected key, no credit or quota left, a rate limit (with the provider's wait time), a model the key cannot use, access refused (for example in an unsupported region), an overloaded or failing service, no internet connection, no response for 5 minutes (30 minutes overall), or a refusal or blocked prompt. An answer cut off at the provider's output limit is saved with a note saying so.

## Answers, recovery and local data

The Questions panel shows progress, partial public answer text when available and the completed explanation. Reasoning events and tool output are not imported. **Go to source note** opens the originating note. Provider and model metadata are saved with the explanation, shown in the note and included in exports. Answers from the API providers record the provider under a `service` key, which Lemma 2.x ignores, so a book stays readable by an older version. Older workspaces without those optional fields still load.

Cancellation keeps the source, personal reasoning and previous explanation. A late result cannot overwrite a cancelled or newer request. Quitting Lemma stops its running CLI and API requests. A response already received is saved locally before its note is updated, so a temporary workspace save failure can be retried without resending the question. After a crash or interruption, an unreturned question is not silently sent again: cancel its pending state from the note and ask again.

“Ask an assistant…” on a failing Lab cell saves a question note with the cell's code and the error and opens the question sheet with a prepared draft and the passage image; nothing is sent until you choose an assistant and send it.

Packets, selected images and receipts are local under `<Lemma support>/Browser/<request UUID>`. CLI setup state is under `<Lemma support>/Assistants`; Web sign-in belongs to WebKit, CLI credentials belong to the provider's CLI, and API keys belong to the Keychain. The normal support folder is `~/Library/Application Support/Lemma`. The source note's current request UUID is the correlation boundary; changing the selected book or note does not change its destination.

## Validation on 10 October 2026

Automated checks cover, for all three API providers, request building (endpoint, method, headers, JSON body with base64 images, model defaults and validation), streaming parsing over a stub URL protocol (text, model, Anthropic fallback switch, thinking and reasoning parts left out, truncation, refusals, blocked prompts, stream errors), HTTP error mapping (invalid key, quota, rate limit with Retry-After, missing model, access, overload), offline and timeout reporting, cancellation of the HTTP request, Check, key handling and redaction, and a full question through StudyStore to a saved note with provenance. CLI checks cover the unchanged environment (keys and provider variables kept), invocation options, status parsing for every account type and failure, retry without a refused option, the login-shell PATH (with a stand-in shell and a timeout), nvm and tilde discovery, a `#!/usr/bin/env node` CLI that fails without its folder on PATH and runs with it, output arriving while a process runs, and a CLI exiting before reading a 4 MB question (which killed the test runner with SIGPIPE before the fix). Decoding tests show that an explanation from an API provider still decodes with Lemma 2.4's three-provider enum. The ChatGPT adapter's node tests include a French interface.

Native QA (a QA copy with stand-in CLIs and an in-memory key store) showed the Connections list and panes, “Signed in · API key” for a stand-in Claude Code, a stand-in sign-in whose page address appeared with **Open sign-in page**, the exit code and stderr of a CLI missing Node, a saved key, ChatGPT Web not loading before Connect, and the question sheet fitting a 1440 × 900 screen with its send buttons visible. Not verified here: real requests to the OpenAI, Anthropic and Gemini APIs (no keys were used), real CLI sign-in flows, and a signed-in ChatGPT round trip.
