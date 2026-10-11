const {test} = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const {JSDOM} = require('jsdom');
const fixtures = require('./fixtures/chatgpt-2026-10.cjs');

const id = 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee';
const lemmaPrompt = 'I am studying ISLP, in the section “4.4.1 Linear Discriminant Analysis for p = 1”.\nSource A: PDF page 157, shown in attached image 1.\n\nText layer of Source A:\n"""\nTaking the log of (4.17)\n"""\n\nQuestion:\nExplain this step.';

/* The October 2026 chatgpt.com composer in jsdom, behaving as the page does for what Lemma uses: typed text becomes
   one paragraph per line, attached images appear as thumbnails with remove buttons, Send starts a turn that ChatGPT
   marks in_progress and then complete, and the submit control is Stop meanwhile. `typing` stands for what the
   browser does to typed text (macOS smart quotes in WebKit). */
function chatgpt({draft = '', attached = 0, packet, typing = text => text, reply = '<p>Full rank gives uniqueness.</p>', answerAfter = 30} = {}) {
  const instance = new JSDOM(fixtures.composer, {url: 'https://chatgpt.com/', runScripts: 'outside-only'});
  const {window} = instance, {document} = window;
  const form = document.querySelector('form'), editor = form.querySelector('[contenteditable]');
  const submit = form.querySelector('button[type="submit"]'), area = form.querySelector('[data-composer-attachments]');
  const state = {sends: 0, stops: 0, files: [], calls: [], results: [], instance, window, document, editor, form, submit};
  const escape = text => text.replace(/&/g, '&amp;').replace(/</g, '&lt;');
  const setText = text => {
    editor.innerHTML = text ? text.split('\n').map(line => line ? `<p>${escape(line)}</p>` : '<p><br class="ProseMirror-trailingBreak"></p>').join('') : '<p class="placeholder"><br></p>';
    submit.disabled = !text && !state.files.length;
  };
  const showFiles = () => {
    area.hidden = !state.files.length;
    area.innerHTML = state.files.length ? `<div>${state.files.map(name => `<img src="blob:${name}"><button aria-label="Supprimer ${name}"></button>`).join('')}</div>` : '';
    for (const button of area.querySelectorAll('button')) button.onclick = () => {
      state.files = state.files.filter(name => !button.getAttribute('aria-label').endsWith(name)); showFiles();
    };
  };
  state.files = Array.from({length: attached}, (_, index) => `old-${index + 1}.png`);
  setText(draft); showFiles();
  window.DataTransfer = class { constructor() { this.files = []; this.items = {add: file => this.files.push(file)}; } };
  for (const input of form.querySelectorAll('input[type="file"]')) {
    Object.defineProperty(input, 'files', {set(list) { state.input = input.id; state.files.push(...list.map(file => file.name)); state.sizes = list.map(file => file.size); }});
    input.addEventListener('change', () => { showFiles(); submit.disabled = false; });
  }
  document.execCommand = (command, _, text) => {
    if (command === 'insertText') {
      const before = editor.textContent ? Array.from(editor.querySelectorAll('p'), p => p.textContent).join('\n') : '';
      setText(before + typing(text)); return true;
    }
    if (command === 'delete') { setText(''); return true; }
    return false;
  };
  form.addEventListener('submit', event => event.preventDefault());
  submit.addEventListener('click', () => {
    if (submit.getAttribute('aria-label') === 'Arrêter') { state.stops++; return; }
    state.sends++; state.sent = Array.from(editor.querySelectorAll('p'), p => p.textContent).join('\n');
    document.body.insertAdjacentHTML('afterbegin', fixtures.turn('in_progress', '<p>Full rank</p>', 'Question'));
    setText(''); state.files = []; showFiles();
    submit.setAttribute('aria-label', 'Arrêter'); submit.disabled = false;
    if (answerAfter !== null) setTimeout(() => {
      const turn = document.querySelector('[data-talvt-turn-state]');
      turn.querySelector('[data-markdown-text-style] > div:last-child').innerHTML = reply;
      turn.setAttribute('data-talvt-turn-state', 'complete');
      submit.setAttribute('aria-label', 'Envoyer'); submit.disabled = true;
    }, answerAfter);
  });
  window.LemmaNativeRPC = async message => {
    state.calls.push(message);
    assert.equal(message.requestID, id);
    if (message.operation === 'packet') return {ok: true, packet};
    if (message.operation === 'image') return {ok: true, data: Buffer.from([1, 2, 3, 4]).toString('base64'), done: true};
    if (message.operation === 'result') state.results.push(message);
    return {ok: true};
  };
  window.eval(fs.readFileSync(require.resolve('../dom.js'), 'utf8'));
  window.eval(fs.readFileSync(require.resolve('../content.js'), 'utf8'));
  state.until = async (test, limit = 3000) => {
    for (const end = Date.now() + limit; Date.now() < end && !test();) await new Promise(resolve => setTimeout(resolve, 10));
    return test();
  };
  state.last = () => state.results.filter(result => result.status === 'complete' || result.status === 'error').at(-1);
  return state;
}
const packet = (mode = 'askAndSave', prompt = lemmaPrompt, images = 2) => ({id, mode, prompt, images: Array.from({length: images}, (_, index) => ({name: `source-${index + 1}.png`, byteCount: 4}))});

test('Ask and save attaches the images, types the question, sends once and returns the completed answer', async () => {
  const page = chatgpt({packet: packet()});
  page.window.LemmaStart(id); page.window.LemmaStart(id);
  assert.ok(await page.until(() => page.last()));
  assert.equal(page.sends, 1);
  assert.equal(page.input, '_r_7_', 'the multiple image input, not the camera');
  assert.deepEqual(page.sizes, [4, 4]);
  assert.equal(page.sent, lemmaPrompt);
  assert.equal(page.last().status, 'complete');
  assert.equal(page.last().answer, 'Full rank gives uniqueness.');
  assert.equal(page.last().conversationURL, 'https://chatgpt.com/');
  assert.ok(!page.document.body.textContent.includes('Save answer to note'), 'No companion panel in the embedded page.');
  page.instance.window.close();
});

test('Review first prepares the draft and waits for the reader to send, then saves automatically', async () => {
  const page = chatgpt({packet: packet('draft', 'A public question', 0)});
  page.window.LemmaStart(id);
  assert.ok(await page.until(() => page.results.some(result => /Review it/.test(result.message || ''))));
  await new Promise(resolve => setTimeout(resolve, 60));
  assert.equal(page.sends, 0); assert.equal(page.last(), undefined);
  page.submit.click();
  assert.ok(await page.until(() => page.last()));
  assert.equal(page.sends, 1);
  assert.ok(page.results.some(result => result.status === 'sent'), 'the reader’s Send is reported');
  assert.equal(page.last().answer, 'Full rank gives uniqueness.');
  page.instance.window.close();
});

test('WebKit’s smart quotes change """ while Lemma types: the question is still recognised and sent', async () => {
  const page = chatgpt({packet: packet(), typing: text => text.replace(/"""/g, '“”"').replace(/'/g, '’')});
  page.window.LemmaStart(id);
  assert.ok(await page.until(() => page.last()));
  assert.equal(page.sends, 1);
  assert.equal(page.last().status, 'complete');
  page.instance.window.close();
});

test('a question ChatGPT changed is never sent, and Lemma takes its text out of the composer again', async () => {
  const page = chatgpt({packet: packet(), typing: text => text.replace('Explain', 'Explian')});
  page.window.LemmaStart(id);
  assert.ok(await page.until(() => page.last()));
  assert.equal(page.sends, 0);
  assert.equal(page.last().status, 'error');
  assert.equal(page.last().reason, 'insert');
  assert.equal(page.editor.textContent, '', 'no draft left for ChatGPT to restore in the next chat');
  page.instance.window.close();
});

test('Lemma’s own unsent question, restored by ChatGPT in the new chat, is replaced', async () => {
  const page = chatgpt({packet: packet(), draft: lemmaPrompt.replace('157', '12'), attached: 1});
  page.window.LemmaStart(id);
  assert.ok(await page.until(() => page.last()));
  assert.equal(page.sends, 1);
  assert.equal(page.sent, lemmaPrompt);
  assert.equal(page.last().status, 'complete');
  page.instance.window.close();
});

test('the reader’s own draft is kept and reported, unless the reader chose to replace it', async () => {
  const kept = chatgpt({packet: packet(), draft: 'My own half-written question'});
  kept.window.LemmaStart(id);
  assert.ok(await kept.until(() => kept.last()));
  assert.equal(kept.sends, 0);
  assert.equal(kept.last().reason, 'draft');
  assert.equal(kept.editor.textContent, 'My own half-written question');
  kept.instance.window.close();
  const replaced = chatgpt({packet: packet(), draft: 'My own half-written question'});
  replaced.window.LemmaStart(id, {replaceDraft: true});
  assert.ok(await replaced.until(() => replaced.last()));
  assert.equal(replaced.sends, 1);
  assert.equal(replaced.sent, lemmaPrompt);
  replaced.instance.window.close();
});

test('cancelling stops a reply being written, and before sending removes Lemma’s draft', async () => {
  const running = chatgpt({packet: packet(), answerAfter: null});
  running.window.LemmaStart(id);
  assert.ok(await running.until(() => running.sends === 1 && running.results.some(result => result.status === 'sent')));
  running.window.LemmaCancel(id);
  assert.equal(running.stops, 1, 'the submit control, labelled Stop in any language, is clicked');
  running.instance.window.close();
  const review = chatgpt({packet: packet('draft')});
  review.window.LemmaStart(id);
  assert.ok(await review.until(() => review.results.some(result => /Review it/.test(result.message || ''))));
  review.window.LemmaCancel(id);
  assert.equal(review.stops, 0);
  assert.equal(review.editor.textContent, '');
  review.instance.window.close();
});

test('a reply with a code block is saved only once its turn is complete', async () => {
  const page = chatgpt({packet: packet(), reply: fixtures.reply, answerAfter: 400});
  page.window.LemmaStart(id);
  assert.ok(await page.until(() => page.sends === 1));
  // While writing: ChatGPT shows the code block (with its own Copy button) before the reply ends.
  const turn = page.document.querySelector('[data-talvt-turn-state]');
  turn.querySelector('[data-markdown-text-style] > div:last-child').innerHTML = fixtures.reply;
  await new Promise(resolve => setTimeout(resolve, 200));
  assert.equal(page.last(), undefined);
  assert.ok(await page.until(() => page.last()));
  assert.equal(page.last().answer, fixtures.replyMarkdown);
  page.instance.window.close();
});
