/* Supports the inspected September companion and October 2026 embedded page.
   Structural markers (ids, data-testid, message roles) are tried first: they do not depend on the language of
   ChatGPT's interface. English accessibility labels remain only as fallbacks. */
(() => {
  const selectors = {
    composer: ['#prompt-textarea[contenteditable="true"]', '[data-testid="composer-text-input"][contenteditable="true"]',
               'div[contenteditable="true"][role="textbox"][aria-label="Ask ChatGPT"]', 'div[contenteditable="true"][role="textbox"][aria-label="Chat with ChatGPT"]'],
    form: 'form[data-chatgpt-composer], form',
    fileInput: 'input[type="file"]',
    send: ['button[data-testid="send-button"]', 'button#composer-submit-button', 'button[aria-label="Send"]', 'button[aria-label="Send message"]'],
    stop: ['button[data-testid="stop-button"]', 'button[aria-label="Stop streaming"]', 'button[aria-label="Stop generating"]'],
    copy: ['button[data-testid="copy-turn-action-button"]', 'button[aria-label="Copy"]', 'button[aria-label="Copy response"]'],
    answers: '[data-message-author-role="assistant"] .markdown, [data-markdown-text-style="assistant-message"]',
    userMessages: '[data-message-author-role="user"], [data-user-message-bubble="true"]'
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
  function send(root) { return first(root, selectors.send); }
  function stop(root) { return first(root, selectors.stop); }
  function composerText(editor) {
    // Chrome represents inserted newlines as paragraphs; textContent joins them.
    return Array.from(editor.childNodes, (node, index) => {
      const lineBreak = index > 0 && node.nodeType === 1 && node.tagName === "P" ? "\n" : "";
      return lineBreak + node.textContent;
    }).join("");
  }
  function answers(document) {
    const nodes = Array.from(document.querySelectorAll(selectors.answers));
    return nodes.filter(node => !nodes.some(other => other !== node && other.contains(node)));
  }
  function assertEmpty(document) {
    const editor = composer(document);
    if (!editor) throw new Error("Open ChatGPT and sign in before preparing the question.");
    if (editor.textContent.trim()) throw new Error("The composer already contains a draft. Keep it, and prepare this question in an empty chat.");
    if (answers(document).length || document.querySelector(selectors.userMessages)) {
      throw new Error("Prepare this question in a new empty chat so its answer stays linked to the right note.");
    }
    const attachments = document.querySelector('[data-composer-attachments]');
    if (attachments && !attachments.hidden && attachments.children.length) {
      throw new Error("The composer already has attachments. Prepare this question in an empty chat.");
    }
    return editor;
  }

  function markdown(node) {
    if (node.nodeType === 3) return node.textContent;
    if (node.nodeType !== 1) return "";
    if (node.classList.contains("katex") || node.classList.contains("katex-display")) {
      const source = node.querySelector('annotation[encoding="application/x-tex"]')?.textContent;
      if (source) return node.classList.contains("katex-display") ? `\n\n$$\n${source}\n$$\n\n` : `$${source}$`;
    }
    if (node.hasAttribute("data-math-source")) {
      const block = node.getAttribute("data-math-display") === "true";
      const formula = node.getAttribute("data-math-source");
      return block ? `\n\n$$\n${formula}\n$$\n\n` : `$${formula}$`;
    }
    const children = Array.from(node.childNodes).map(markdown).join("");
    switch (node.tagName) {
      case "P": return `${children}\n\n`;
      case "BR": return "\n";
      case "STRONG": case "B": return `**${children}**`;
      case "EM": case "I": return `*${children}*`;
      case "PRE": return `\n\n\`\`\`\n${node.textContent.trim()}\n\`\`\`\n\n`;
      case "CODE": return `\`${children}\``;
      case "LI": return `- ${children.trim()}\n`;
      case "UL": case "OL": return `\n${children}\n`;
      case "H1": case "H2": case "H3": case "H4": return `${"#".repeat(Number(node.tagName[1]))} ${children}\n\n`;
      case "A": return `[${children}](${node.getAttribute("href") || ""})`;
      case "BLOCKQUOTE": return `${children.trim().split("\n").map(line => `> ${line}`).join("\n")}\n\n`;
      default: return children;
    }
  }

  function completedAnswer(document) {
    const list = answers(document);
    // A new, dedicated question receives exactly one assistant answer.
    if (list.length !== 1) return null;
    const root = list[0];
    let turn = root.parentElement;
    // Completion controls belong to the enclosing turn, whose CSS classes can change.
    while (turn && !first(turn, selectors.copy)) {
      turn = turn.parentElement;
      if (turn === document.body) return null;
    }
    if (!turn || stop(document)) return null;
    const text = markdown(root).trim();
    return text ? text : null;
  }

  const api = {selectors, first, composer, send, stop, composerText, answers, assertEmpty, markdown, completedAnswer};
  if (typeof module !== "undefined" && module.exports) module.exports = api;
  else window.LemmaDOM = api;
})();
