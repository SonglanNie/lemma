/* How Lemma reads ChatGPT's Web page (checked against the signed-in page on 11 October 2026, and the September
   companion page). Structure comes first: the composer form's data attribute, roles, file inputs, the turn's state
   attribute and the reply's markdown-style attribute do not depend on the language of ChatGPT's interface. English
   accessibility labels remain only as fallbacks for older pages. */
(() => {
  const selectors = {
    composer: ['form[data-chatgpt-composer] [contenteditable="true"][role="textbox"]', 'form[data-chatgpt-composer] .ProseMirror[contenteditable="true"]',
               '#prompt-textarea[contenteditable="true"]', '[data-testid="composer-text-input"][contenteditable="true"]',
               'div[contenteditable="true"][role="textbox"][aria-label="Ask ChatGPT"]', 'div[contenteditable="true"][role="textbox"][aria-label="Chat with ChatGPT"]'],
    form: 'form[data-chatgpt-composer], form',
    fileInput: 'input[type="file"]',
    send: ['button[data-testid="send-button"]', 'button#composer-submit-button', 'button[type="submit"]', 'button[aria-label="Send"]', 'button[aria-label="Send message"]'],
    stop: ['button[data-testid="stop-button"]', 'button[aria-label="Stop"]', 'button[aria-label="Stop streaming"]', 'button[aria-label="Stop generating"]'],
    copy: ['button[data-testid="copy-turn-action-button"]', 'button[aria-label="Copy"]', 'button[aria-label="Copy response"]'],
    answers: '[data-markdown-text-style="assistant-message"], [data-message-author-role="assistant"] .markdown',
    userMessages: '[data-user-message-bubble="true"], [data-message-author-role="user"]',
    attachments: '[data-composer-attachments]',
    signedOut: 'form[data-logged-out], [data-testid="login-button"]'
  };

  /* The first selector, in order of preference, that matches inside `root`. */
  function first(root, list) {
    for (const selector of list) {
      const found = root.querySelector(selector);
      if (found) return found;
    }
    return null;
  }
  function composer(document) { return first(document, selectors.composer); }
  function form(editor) { return editor.closest('form[data-chatgpt-composer]') || editor.closest('form'); }
  function signedOut(document) { return !composer(document) && !!document.querySelector(selectors.signedOut); }

  /* The attribute that carries a conversation turn's state ("in_progress", "complete"); its prefix changes between
     deployments, so any name ending in "turn-state" counts. */
  function stateName(element) { return element.getAttributeNames().find(name => /(^|-)turn-state$/.test(name)); }
  function turnOf(node) {
    for (let element = node; element && element.nodeType === 1; element = element.parentElement) if (stateName(element)) return element;
    return null;
  }
  function turnState(node) { const turn = turnOf(node); return turn ? turn.getAttribute(stateName(turn)) : null; }
  const finishedState = /^(complete|completed|done|finished|idle)$/i;
  /* A reply is still being written: its turn says so, or an older page shows a labelled Stop control. */
  function busy(document) {
    const last = [...document.querySelectorAll(`${selectors.answers}, ${selectors.userMessages}`)].at(-1);
    const state = last ? turnState(last) : null;
    return state ? !finishedState.test(state) : !!first(document, selectors.stop);
  }
  /* While a reply is written, the composer's submit control is Stop, whatever its label says. */
  function stop(document) {
    const labelled = first(document, selectors.stop);
    if (labelled) return labelled;
    if (!busy(document)) return null;
    const editor = composer(document);
    return editor ? form(editor)?.querySelector('button[type="submit"]') ?? null : null;
  }
  function send(root) {
    const button = first(root, selectors.send);
    return button && !selectors.stop.some(selector => button.matches(selector)) ? button : null;
  }
  /* An image input that takes several files, not the camera's. */
  function fileInput(root) {
    const inputs = [...root.querySelectorAll(selectors.fileInput)];
    const images = input => !input.hasAttribute("capture") && (!input.accept || /(^|,)\s*image\/(\*|png)/.test(input.accept));
    return inputs.find(input => images(input) && input.multiple) || inputs.find(images) || inputs[0] || null;
  }

  function composerText(editor) {
    // Inserted lines become paragraphs; textContent alone would join them.
    return Array.from(editor.childNodes, (node, index) => {
      const lineBreak = index > 0 && node.nodeType === 1 && node.tagName === "P" ? "\n" : "";
      return lineBreak + node.textContent;
    }).join("");
  }
  /* The same words and symbols, whatever whitespace, quotes, dashes or ellipses the page or macOS's text
     substitutions produced. */
  function comparable(text) {
    return text.normalize("NFC").replace(/\u2026/g, "...").replace(/[\s"'`\u00AB\u00BB\u2018-\u201F\u2032\u2033\u2010-\u2015\u2212-]/g, "");
  }
  function sameText(a, b) { return comparable(a) === comparable(b); }
  /* Lemma's own earlier question, left unsent by an interrupted preparation (ChatGPT restores drafts). */
  function isLemmaDraft(text) { return /Source A: PDF page \d+/.test(text) || /^\s*I am studying /.test(text); }

  function attachments(root) { return root.querySelector(selectors.attachments); }
  function attachmentCount(root) {
    const area = attachments(root);
    return area && !area.hidden ? area.children.length : 0;
  }
  /* Every image shows in the composer: as a thumbnail, or by its file name in a label or the text. */
  function attachmentsShown(root, images) {
    if (!images.length) return true;
    const area = attachments(root);
    if (area && !area.hidden && area.querySelectorAll("img").length >= images.length) return true;
    const names = [...root.querySelectorAll('[aria-label], [title]')].map(node => `${node.getAttribute('aria-label') || ''} ${node.getAttribute('title') || ''}`).join(' ');
    return images.every(image => `${root.textContent} ${names}`.includes(image.name));
  }

  function answers(document) {
    const nodes = Array.from(document.querySelectorAll(selectors.answers));
    return nodes.filter(node => !nodes.some(other => other !== node && other.contains(node)));
  }

  /* What already occupies a new chat: a draft, attachments, or an earlier conversation. */
  function draft(document) {
    const editor = composer(document);
    if (!editor) return null;
    const box = form(editor) || document;
    return {editor, form: box, text: composerText(editor).trim(), attachments: attachmentCount(box),
            conversation: answers(document).length > 0 || !!document.querySelector(selectors.userMessages)};
  }
  function assertEmpty(document) {
    const state = draft(document);
    if (!state) throw new Error("Open ChatGPT and sign in before preparing the question.");
    if (state.text) throw new Error("The composer already contains a draft. Keep it, and prepare this question in an empty chat.");
    if (state.conversation) throw new Error("Prepare this question in a new empty chat so its answer stays linked to the right note.");
    if (state.attachments) throw new Error("The composer already has attachments. Prepare this question in an empty chat.");
    return state.editor;
  }

  function insertText(editor, text) {
    editor.focus();
    return editor.ownerDocument.execCommand("insertText", false, text);
  }
  /* Empties the composer the way a reader would (select all, delete), so ChatGPT forgets the stored draft too, and
     removes attached files through their own remove buttons. */
  function clearComposer(editor, box) {
    const document = editor.ownerDocument;
    editor.focus();
    const range = document.createRange(); range.selectNodeContents(editor);
    const selection = document.getSelection(); selection.removeAllRanges(); selection.addRange(range);
    document.execCommand("delete");
    const area = attachments(box);
    if (area) for (const button of area.querySelectorAll("button")) if (/\.\w{2,5}\b/.test(button.getAttribute("aria-label") || "")) button.click();
    return !composerText(editor).trim();
  }

  /* Markdown with LaTeX from a rendered reply. Works on a copy, so the page is never changed. */
  function markdown(node) {
    const root = node.cloneNode(true);
    const code = [];
    for (const block of codeBlocks(root)) {
      const index = code.push(fence(block.text, block.language)) - 1;
      block.root.replaceWith(root.ownerDocument.createTextNode(`\n\n\u0000${index}\u0000\n\n`));
    }
    const text = render(root, 0).replace(/[ \t]+\n/g, "\n").replace(/\n{3,}/g, "\n\n").trim();
    // A code block inside a list item keeps the item's indentation on every line.
    return text.replace(/^([ \t]*)(.*?)\u0000(\d+)\u0000/gm, (_, indent, before, index) =>
      indent + before + code[Number(index)].split("\n").map((line, row) => row ? indent + " ".repeat(before.length) + line : line).join("\n"));
  }

  /* Code blocks: ChatGPT's code viewer (an editable box with one line per row, under a header naming the language
     with Copy and Run buttons), or an older <pre>. Each is replaced whole, header included. */
  function codeBlocks(root) {
    const found = [];
    for (const viewer of root.querySelectorAll('[data-language][contenteditable], [data-language][role="textbox"]')) {
      const rows = [...viewer.children];
      const text = rows.length && rows.every(row => row.tagName === "DIV") ? rows.map(row => row.textContent).join("\n") : viewer.textContent;
      found.push({root: codeRoot(viewer, root), text, language: viewer.getAttribute("data-language") || ""});
    }
    for (const pre of root.querySelectorAll("pre")) {
      if (found.some(block => block.root.contains(pre) || pre.contains(block.root))) continue;
      const element = pre.querySelector("code") || pre;
      const language = (element.className.match(/language-([\w+#.-]+)/) || [])[1] || pre.getAttribute("data-language") || "";
      found.push({root: pre, text: element.textContent.replace(/\n$/, ""), language});
    }
    return found;
  }
  /* The largest ancestor of a code viewer that holds nothing else of the reply: its header and the viewer. */
  function codeRoot(viewer, limit) {
    let block = viewer;
    while (block.parentElement && block.parentElement !== limit) {
      const parent = block.parentElement;
      if (parent.querySelectorAll('[data-language][contenteditable], [data-language][role="textbox"]').length > 1) break;
      const content = [...parent.querySelectorAll('[data-d-component], p, ul, ol, table, blockquote, h1, h2, h3, h4, h5, h6, .katex')];
      if (content.some(element => !block.contains(element))) break;
      block = parent;
    }
    return block;
  }
  function fence(text, language) {
    const ticks = "`".repeat(Math.max(3, ...[...text.matchAll(/`+/g)].map(match => match[0].length + 1)));
    return `${ticks}${language.toLowerCase()}\n${text.replace(/\s+$/, "")}\n${ticks}`;
  }

  function bold(element) {
    return ["STRONG", "B"].includes(element.tagName) || element.hasAttribute("data-d-default-strong") ||
      /^(bold|semibold|[6-9]00)$/i.test(element.getAttribute("data-d-font-weight") || "");
  }
  function italic(element) { return ["EM", "I"].includes(element.tagName) || element.getAttribute("data-d-font-style") === "italic"; }
  function wrap(text, mark) {
    const match = text.match(/^(\s*)([\s\S]*?)(\s*)$/);
    return match[2] ? `${match[1]}${mark}${match[2]}${mark}${match[3]}` : text;
  }
  /* An element's content on one line (headings, links, table cells). */
  function inline(element, depth) { return Array.from(element.childNodes, child => render(child, depth)).join("").replace(/\s*\n+\s*/g, " ").trim(); }

  function render(node, depth) {
    if (node.nodeType === 3) return node.textContent;
    if (node.nodeType !== 1) return "";
    const element = node, tag = element.tagName.toUpperCase();
    if (["BUTTON", "SVG", "STYLE", "SCRIPT", "TEMPLATE", "IMG", "INPUT", "TEXTAREA"].includes(tag) || element.hidden) return "";
    const classes = typeof element.className === "string" ? element.className : "";
    if (/(^|\s)katex-display(\s|$)/.test(classes) || /(^|\s)katex(\s|$)/.test(classes)) {
      const source = element.querySelector('annotation[encoding="application/x-tex"]')?.textContent;
      if (source) return /katex-display/.test(classes) ? `\n\n$$\n${source.trim()}\n$$\n\n` : `$${source.trim()}$`;
    }
    if (element.hasAttribute("data-math-source")) {
      const formula = element.getAttribute("data-math-source");
      return element.getAttribute("data-math-display") === "true" ? `\n\n$$\n${formula}\n$$\n\n` : `$${formula}$`;
    }
    if (element.getAttribute("aria-hidden") === "true" || /(^|\s)sr-only(\s|$)/.test(classes)) return "";
    const component = element.getAttribute("data-d-component") || "";
    const children = () => Array.from(element.childNodes, child => render(child, depth)).join("");
    switch (tag) {
      case "P": return `\n\n${children()}\n\n`;
      case "BR": return "\n";
      case "HR": return "\n\n---\n\n";
      case "H1": case "H2": case "H3": case "H4": case "H5": case "H6": return `\n\n${"#".repeat(Number(tag[1]))} ${inline(element, depth)}\n\n`;
      case "CODE": return code(element.textContent);
      case "A": {
        const href = element.getAttribute("href") || "";
        const label = inline(element, depth);
        return /^(https?:|mailto:)/i.test(href) && label ? `[${label}](${href})` : label;
      }
      case "UL": case "OL": return `\n\n${list(element, depth)}\n\n`;
      case "BLOCKQUOTE": {
        const quoted = children().replace(/[ \t]+\n/g, "\n").replace(/\n{3,}/g, "\n\n").trim();
        return `\n\n${quoted.split("\n").map(line => `> ${line}`.trimEnd()).join("\n")}\n\n`;
      }
      case "TABLE": return `\n\n${table(element, depth)}\n\n`;
      case "DEL": case "S": return wrap(children(), "~~");
    }
    if (component === "divider") return "\n\n---\n\n";
    if (component === "code") return code(element.textContent);
    let text = children();
    if (bold(element) && italic(element)) return wrap(text, "***");
    if (bold(element)) return wrap(text, "**");
    if (italic(element)) return wrap(text, "*");
    return text;
  }
  function code(text) {
    const ticks = "`".repeat(Math.max(1, ...[...text.matchAll(/`+/g)].map(match => match[0].length + 1)));
    return ticks.length > 1 ? `${ticks} ${text} ${ticks}` : `\`${text}\``;
  }
  function list(element, depth) {
    const ordered = element.tagName.toUpperCase() === "OL";
    let number = Number(element.getAttribute("start") || 1);
    return Array.from(element.children).filter(item => item.tagName.toUpperCase() === "LI").map(item => {
      const marker = ordered ? `${number++}.` : "-";
      const body = render(item, depth + 1).replace(/[ \t]+\n/g, "\n").replace(/\n{2,}/g, "\n").trim();
      const pad = " ".repeat(marker.length + 1);
      return `${marker} ${body.split("\n").map((line, index) => index ? pad + line : line).join("\n")}`;
    }).join("\n");
  }
  function table(element, depth) {
    const rows = Array.from(element.querySelectorAll("tr")).map(row =>
      Array.from(row.children).filter(cell => /^T[HD]$/i.test(cell.tagName))
        .map(cell => inline(cell, depth).replace(/\|/g, "\\|")));
    if (!rows.length) return "";
    const width = Math.max(...rows.map(row => row.length));
    const line = row => `| ${Array.from({length: width}, (_, index) => row[index] ?? "").join(" | ")} |`;
    return [line(rows[0]), `| ${Array(width).fill("---").join(" | ")} |`, ...rows.slice(1).map(line)].join("\n");
  }

  /* The reply in the question's own turn, once ChatGPT marks the turn complete. Older pages without a turn state:
     the turn's own Copy control (not a code block's) and no Stop control. */
  function completedAnswer(document) {
    const list = answers(document);
    if (!list.length) return null;
    const turn = turnOf(list[0]);
    if (turn) {
      if (!finishedState.test(turn.getAttribute(stateName(turn)) || "")) return null;
      const text = list.filter(node => turnOf(node) === turn).map(markdown).filter(Boolean).join("\n\n");
      return text || null;
    }
    if (list.length !== 1) return null;
    const root = list[0];
    let container = root.parentElement;
    const ownCopy = element => selectors.copy.some(selector => [...element.querySelectorAll(selector)].some(button => !root.contains(button)));
    while (container && container !== document.body && !ownCopy(container)) container = container.parentElement;
    if (!container || container === document.body || first(document, selectors.stop)) return null;
    const text = markdown(root);
    return text || null;
  }
  /* The reply so far, for progress shown in Lemma. */
  function partialAnswer(document) {
    const list = answers(document);
    if (!list.length) return "";
    const turn = turnOf(list[0]);
    return (turn ? list.filter(node => turnOf(node) === turn) : list.slice(-1)).map(markdown).filter(Boolean).join("\n\n");
  }

  const api = {selectors, first, composer, form, signedOut, send, stop, busy, fileInput, composerText, sameText, isLemmaDraft,
               attachmentCount, attachmentsShown, answers, draft, assertEmpty, insertText, clearComposer, markdown, turnState,
               completedAnswer, partialAnswer};
  if (typeof module !== "undefined" && module.exports) module.exports = api;
  else window.LemmaDOM = api;
})();
