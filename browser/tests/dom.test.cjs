const {test} = require('node:test');
const assert = require('node:assert/strict');
const {JSDOM} = require('jsdom');
const dom = require('../dom.js');
const composer = '<form data-chatgpt-composer><div contenteditable="true" role="textbox" aria-label="Ask ChatGPT"><p></p></div><div data-composer-attachments hidden></div></form>';

test('compares the multiline question with Chrome paragraphs without losing line breaks', () => {
  const document = new JSDOM(composer).window.document;
  const editor = dom.composer(document);
  const prompt = 'Source A: PDF page 31.\n\nQuestion:\nWhy is RSS(beta) convex?\n\nMy reasoning so far:\nEach residual is squared.';
  // Chrome's insertText creates one paragraph per line, including blank lines.
  editor.innerHTML = '<p>Source A: PDF page 31.</p><p data-empty-paragraph="true"><br class="ProseMirror-trailingBreak"></p><p>Question:</p><p>Why is RSS(beta) convex?</p><p data-empty-paragraph="true"><br class="ProseMirror-trailingBreak"></p><p>My reasoning so far:</p><p>Each residual is squared.</p>';
  assert.equal(dom.composerText(editor).trim(), prompt.trim());
  editor.querySelectorAll('p')[3].textContent = 'Why is RSS(beta) concave?';
  assert.notEqual(dom.composerText(editor).trim(), prompt.trim());
  editor.textContent = 'A single-line question.';
  assert.equal(dom.composerText(editor), 'A single-line question.');
});

test('keeps an existing draft, attachment, or conversation intact', () => {
  for (const extra of [
    '<div data-user-message-bubble="true">Earlier question</div>',
    '<div data-markdown-text-style="assistant-message">Earlier answer</div>'
  ]) {
    const document = new JSDOM(composer + extra).window.document;
    assert.throws(() => dom.assertEmpty(document), /empty chat/);
  }
  const document = new JSDOM(composer).window.document;
  dom.composer(document).textContent = 'An unsent personal question';
  assert.throws(() => dom.assertEmpty(document), /already contains a draft/);
  dom.composer(document).textContent = '';
  const attachments = document.querySelector('[data-composer-attachments]');
  attachments.hidden = false;
  attachments.innerHTML = '<span>previous.png</span>';
  assert.throws(() => dom.assertEmpty(document), /already has attachments/);
});

test('retains LaTeX exactly once instead of flattened KaTeX text', () => {
  const document = new JSDOM('<div><p><strong>Full rank</strong> gives <span data-math-display="false" data-math-source="X^\\top X"><span>duplicated visible and accessible text</span></span>.</p><span data-math-display="true" data-math-source="\\hat\\beta=(X^\\top X)^{-1}X^\\top y"></span></div>').window.document;
  const result = dom.markdown(document.body.firstElementChild);
  assert.match(result, /\*\*Full rank\*\*/);
  assert.ok(result.includes('$X^\\top X$'));
  assert.ok(result.includes('$$\n\\hat\\beta='));
  assert.ok(!result.includes('duplicated'));
});

test('returns one completed answer only, never an unfinished or ambiguous reply', () => {
  const document = new JSDOM('<div class="group flex flex-col"><div><div class="group flex min-w-0 flex-col"><div data-markdown-text-style="assistant-message"><p>Answer.</p></div></div></div></div>').window.document;
  assert.equal(dom.completedAnswer(document), null);
  const button = document.createElement('button'); button.setAttribute('aria-label', 'Copy');
  document.body.firstElementChild.append(button);
  assert.equal(dom.completedAnswer(document), 'Answer.');
  document.body.append(document.querySelector('[data-markdown-text-style]').cloneNode(true));
  assert.equal(dom.completedAnswer(document), null);
});

test('October embedded composer and answer controls preserve KaTeX and require completion', () => {
  const document = new JSDOM('<form><div id="prompt-textarea" contenteditable="true" role="textbox" aria-label="Chat with ChatGPT"></div><button aria-label="Send message"></button></form><article><div data-message-author-role="assistant"><div class="markdown"><p>Use <span class="katex"><span>duplicated text</span><math><annotation encoding="application/x-tex">X^\\top X</annotation></math></span>.</p></div></div><button aria-label="Copy response"></button></article>').window.document;
  assert.ok(dom.composer(document));
  assert.match(dom.completedAnswer(document), /Use \$X\^\\top X\$\./);
  assert.ok(!dom.completedAnswer(document).includes('duplicated'));
  const stop = document.createElement('button'); stop.setAttribute('aria-label', 'Stop streaming'); document.body.append(stop);
  assert.equal(dom.completedAnswer(document), null);
});

test('finds the composer, send, stop and completion controls by structure in any interface language', () => {
  // A French interface: no English label matches, the test ids and roles do.
  const document = new JSDOM('<form><div id="prompt-textarea" contenteditable="true" role="textbox" aria-label="Discuter avec ChatGPT"></div><button data-testid="send-button" aria-label="Envoyer le message"></button></form><article><div data-message-author-role="assistant"><div class="markdown"><p>Réponse.</p></div></div><button data-testid="copy-turn-action-button" aria-label="Copier"></button></article>').window.document;
  assert.ok(dom.composer(document));
  assert.equal(dom.send(document).getAttribute('aria-label'), 'Envoyer le message');
  assert.equal(dom.completedAnswer(document), 'Réponse.');
  const stop = document.createElement('button'); stop.setAttribute('data-testid', 'stop-button'); stop.setAttribute('aria-label', 'Arrêter');
  document.body.append(stop);
  assert.equal(dom.stop(document), stop);
  assert.equal(dom.completedAnswer(document), null, 'A reply still streaming is never returned.');
});

test('prefers the structural composer when an English-labelled field comes first in the page', () => {
  const document = new JSDOM('<div contenteditable="true" role="textbox" aria-label="Ask ChatGPT" id="other"></div><form><div id="prompt-textarea" contenteditable="true" role="textbox"></div></form>').window.document;
  assert.equal(dom.composer(document).id, 'prompt-textarea');
});

// October 2026: the page as Lemma finds it now (see fixtures/chatgpt-2026-10.cjs).
const page = require('./fixtures/chatgpt-2026-10.cjs');

test('October 2026 page: the composer, its image input and its submit control are found by structure', () => {
  const document = new JSDOM(page.turn('complete', '<p>Earlier.</p>') + page.composer).window.document;
  const editor = dom.composer(document);
  assert.equal(editor.getAttribute('aria-label'), 'Poser une question à ChatGPT', 'not the editable code box of a reply');
  const form = dom.form(editor);
  assert.equal(dom.fileInput(form).id, '_r_7_', 'several images at once, never the camera input');
  assert.equal(dom.send(form).getAttribute('type'), 'submit');
});

test('October 2026 replies: headings, emphasis, links, math, lists, quotes, tables and code survive as Markdown', () => {
  const document = new JSDOM(page.turn('complete', page.reply)).window.document;
  const answer = dom.completedAnswer(document);
  assert.equal(answer, page.replyMarkdown);
  assert.ok(!/Exécuter|Python\n/.test(answer), 'the code header and its buttons are not part of the answer');
});

test('a reply is complete only when its turn says so, even when a code block already shows its Copy button', () => {
  const streaming = new JSDOM(page.turn('in_progress', page.reply) + page.composer).window.document;
  assert.equal(dom.completedAnswer(streaming), null);
  assert.ok(dom.busy(streaming));
  // While a reply is written, the submit control is Stop, whatever it is called.
  assert.equal(dom.stop(streaming), streaming.querySelector('form button[type="submit"]'));
  assert.match(dom.partialAnswer(streaming), /^## Overview/);
  const done = new JSDOM(page.turn('complete', page.reply) + page.composer).window.document;
  assert.equal(dom.stop(done), null);
  assert.ok(!dom.busy(done));
});

test('a thinking model can split its reply: every part in the question\'s turn is kept, in order', () => {
  const document = new JSDOM(page.turn('complete', '<p>Part one.</p></div></div><div data-markdown-text-style="assistant-message"><div><p>Part two.</p>')).window.document;
  assert.equal(dom.completedAnswer(document), 'Part one.\n\nPart two.');
});

test('code inside a list item stays indented with the item', () => {
  const document = new JSDOM(page.turn('complete', '<ol><li><p>Run:</p><div><div>Bash</div><button>Copy</button><div data-language="bash" contenteditable="true" role="textbox"><div>echo one</div><div>echo two</div></div></div></li></ol>')).window.document;
  assert.equal(dom.completedAnswer(document), '1. Run:\n   ```bash\n   echo one\n   echo two\n   ```');
});

test('typed text compares equal through smart quotes, dashes, ellipses and whitespace, but not through changed words', () => {
  const prompt = 'Text layer:\n"""\nIt isn\'t -- quite... x = 1\n"""';
  assert.ok(dom.sameText('Text layer:\n“”"\nIt isn’t — quite…  x = 1\n“”"', prompt));
  assert.ok(!dom.sameText(prompt.replace('quite', 'quiet'), prompt));
  assert.ok(!dom.sameText(prompt.slice(0, -10), prompt));
});

test('recognises an unsent question Lemma prepared earlier, and nothing else', () => {
  assert.ok(dom.isLemmaDraft('I am studying ISLP, in the section “4.4.1”.\nSource A: PDF page 157, shown in attached image 1.'));
  assert.ok(dom.isLemmaDraft('Book: ISLP\nSource A: PDF page 12 (printed page 2), attached image 1.'));
  assert.ok(!dom.isLemmaDraft('My own half-written question about page 12'));
});

test('clearing the composer selects its text, deletes it and removes attached files', () => {
  const {window} = new JSDOM(page.composer);
  const {document} = window;
  const editor = dom.composer(document);
  editor.innerHTML = '<p>I am studying a book.</p><p>Source A: PDF page 3.</p>';
  const area = document.querySelector('[data-composer-attachments]');
  area.hidden = false;
  area.innerHTML = '<div><img src="blob:a"><button aria-label="Supprimer source-1.png"></button><img src="blob:b"><button aria-label="Supprimer source-2.png"></button></div>';
  let removed = 0;
  for (const button of area.querySelectorAll('button')) button.onclick = () => { removed++; };
  document.execCommand = command => {
    if (command !== 'delete') return false;
    const range = document.getSelection().getRangeAt(0);
    range.deleteContents();
    return true;
  };
  assert.equal(dom.attachmentCount(dom.form(editor)), 1);
  assert.ok(dom.clearComposer(editor, dom.form(editor)));
  assert.equal(editor.textContent, '');
  assert.equal(removed, 2);
});
