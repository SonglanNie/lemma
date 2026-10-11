// The signed-in chatgpt.com page as inspected on 11 October 2026, reduced to the structure Lemma reads: ids, roles,
// data attributes and labels as the page had them (class names and styling removed). Labels are in French where
// the page labels a control, since Lemma must not depend on English ones.

// The home composer: four file inputs (the first is the camera's), the attachments area, the ProseMirror editor
// with its placeholder paragraph, and the submit control (Send, or Stop while a reply is written).
exports.composer = `<form data-chatgpt-composer="" data-composer-placement="home">
  <input type="file" accept="image/*" capture="environment" id="_r_5_">
  <input type="file" accept="image/*,video/*" multiple id="_r_7_">
  <input type="file" accept="image/*" multiple id="_r_6_">
  <input type="file" multiple id="_r_4_">
  <div data-composer-attachments="" hidden></div>
  <div contenteditable="true" role="textbox" aria-multiline="true" class="ProseMirror" data-composer-markdown="" aria-label="Poser une question à ChatGPT"><p data-empty-paragraph="true" class="placeholder"><br class="ProseMirror-trailingBreak"></p></div>
  <button type="button" aria-label="Ajouter des fichiers et plus"></button>
  <button type="submit" aria-label="Envoyer" disabled></button>
</form>`;

// A finished reply rendered by the October design system: data-d-component markers, bold and italic as attributes,
// KaTeX with its TeX annotation, a table, a divider and a code viewer (an editable box, one row per line, under a
// header with the language, Copy and Run).
exports.reply = `<h2 data-d-component="title">Overview</h2>
<p data-d-component="text"><span>This </span><span>paragraph </span><span data-d-component="text" data-d-default-strong="" data-d-inline="">bold text</span><span>, </span><span data-d-component="text" data-d-font-style="italic" data-d-inline="">italic text</span><span>, inline code </span><code data-d-component="code">x_k</code><span>, a link to </span><span data-d-component="box"><span data-d-component="popover-trigger" role="presentation"><a href="https://example.com"><span data-d-component="text">example.com</span><span><svg></svg></span></a></span></span><span>, and inline math: </span><span data-d-component="math"><span class="katex"><span class="katex-mathml"><math><semantics><mrow><mi>Var</mi></mrow><annotation encoding="application/x-tex">\\operatorname{Var}(X)=\\mathbb{E}[(X-\\mu)^2]</annotation></semantics></math></span><span class="katex-html" aria-hidden="true">Var(X)=E[(X−μ)2]</span></span></span><span>.</span></p>
<ol data-d-component="list"><li data-d-component="list-item"><div><div><p data-d-component="text">First numbered item.</p></div></div></li><li data-d-component="list-item"><div><div><p data-d-component="text">Second numbered item.</p><ul data-d-component="list"><li data-d-component="list-item"><div><div><p data-d-component="text">Nested bullet point.</p></div></div></li></ul></div></div></li></ol>
<blockquote data-d-component="blockquote"><p data-d-component="text">This is a blockquote.</p></blockquote>
<p data-d-component="text">The normal density:</p>
<div data-d-component="math"><span class="katex-display"><span class="katex"><span class="katex-mathml"><math display="block"><semantics><mrow></mrow><annotation encoding="application/x-tex">f(x)=\\frac{1}{\\sigma\\sqrt{2\\pi}}e^{-\\frac{(x-\\mu)^2}{2\\sigma^2}}</annotation></semantics></math></span><span class="katex-html" aria-hidden="true">f(x)=…</span></span></span></div>
<div data-d-component="table"><table><tbody><tr data-d-component="table-row"><th data-d-component="table-cell"><p data-d-component="text">Column A</p></th><th data-d-component="table-cell"><p data-d-component="text">Column B</p></th></tr><tr data-d-component="table-row"><td data-d-component="table-cell"><p data-d-component="text">1</p></td><td data-d-component="table-cell"><p data-d-component="text">a | b</p></td></tr></tbody></table></div>
<div data-d-component="divider"></div>
<div><div><div><div><svg></svg><div>Python</div><div><div><span><button aria-label="Retour à la ligne"><svg></svg></button></span><span><button aria-label="Copier"><svg></svg></button></span><button aria-label="Exécuter le code"><svg></svg>Exécuter</button></div></div></div><div><div><div class="text-size-code"><div class="chatgpt-code-scrollport"><div spellcheck="false" contenteditable="true" role="textbox" aria-label="Modifier le code" data-language="python"><div><span>x</span> <span>=</span> <span>42</span></div><div><br></div><div><span>print</span>(<span>x</span>)</div></div></div></div><button aria-label="Défiler vers le bas"><svg></svg></button></div></div></div></div>
<p data-d-component="text">This is the final sentence.</p>`;

exports.replyMarkdown = String.raw`## Overview

This paragraph **bold text**, *italic text*, inline code ` + '`x_k`' + String.raw`, a link to [example.com](https://example.com), and inline math: $\operatorname{Var}(X)=\mathbb{E}[(X-\mu)^2]$.

1. First numbered item.
2. Second numbered item.
   - Nested bullet point.

> This is a blockquote.

The normal density:

$$
f(x)=\frac{1}{\sigma\sqrt{2\pi}}e^{-\frac{(x-\mu)^2}{2\sigma^2}}
$$

| Column A | Column B |
| --- | --- |
| 1 | a \| b |

---

` + '```python\nx = 42\n\nprint(x)\n```' + `

This is the final sentence.`;

// One conversation turn: the reader's question and the reply, in a container whose state attribute ChatGPT sets to
// "in_progress" while it writes and "complete" when done. The reply's own action bar follows it.
exports.turn = (state, reply, question = 'Question?') => `<div data-talvt-turn-state="${state}">
  <h4 class="sr-only">Vous avez dit :</h4>
  <div data-user-message-bubble="true"><div data-markdown-text-tone="user-message"><p>${question}</p></div></div>
  <h4 class="sr-only">ChatGPT a dit :</h4>
  <div data-markdown-text-style="assistant-message"><div hidden=""></div><div>${reply}</div></div>
  ${state === 'complete' ? '<div><button aria-label="Copier"></button><button aria-label="Bonne réponse"></button></div>' : ''}
</div>`;
