const {test} = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const {JSDOM} = require('jsdom');

test('embedded ChatGPT sends once, transfers the chosen image and returns the answer to Lemma', async () => {
  const instance = new JSDOM(`<form data-chatgpt-composer><div contenteditable="true" role="textbox" aria-label="Ask ChatGPT"></div><input type="file" aria-label="Attach files"><div data-composer-attachments hidden></div><button type="button" aria-label="Send">Send</button></form>`, {url: 'https://chatgpt.com/', runScripts: 'outside-only'});
  const {window} = instance;
  const calls = [];
  let sends = 0, files;
  window.DataTransfer = class { constructor() { this.files = []; this.items = {add: file => this.files.push(file)}; } };
  Object.defineProperty(window.document.querySelector('input'), 'files', {set(value) { files = value; }});
  window.document.querySelector('input').addEventListener('change', () => { window.document.querySelector('[data-composer-attachments]').hidden = false; });
  window.document.execCommand = (_, __, text) => { window.document.querySelector('[contenteditable]').textContent = text; return true; };
  const id = 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee';
  const prompt = 'Question:\nWhy full rank?\n\nExplain using the image.';
  window.LemmaNativeRPC = async message => {
    calls.push(message);
    assert.equal(message.requestID, id);
    if (message.operation === 'packet') return {ok: true, packet: {id, mode: 'askAndSave', prompt, images: [{name: 'source-1.png', byteCount: 4}]}};
    if (message.operation === 'image') return {ok: true, data: Buffer.from([1, 2, 3, 4]).toString('base64'), done: true};
    return {ok: true};
  };
  window.document.querySelector('[aria-label="Send"]').onclick = () => {
    sends++;
    assert.equal(window.document.querySelector('[contenteditable]').textContent, prompt);
    const turn = window.document.createElement('div');
    turn.className = 'group flex flex-col';
    turn.innerHTML = '<div data-markdown-text-style="assistant-message"><p>Full rank gives uniqueness.</p></div><button aria-label="Copy">Copy</button>';
    window.document.body.append(turn);
  };
  window.eval(fs.readFileSync(require.resolve('../dom.js'), 'utf8'));
  window.eval(fs.readFileSync(require.resolve('../content.js'), 'utf8'));
  window.LemmaStart(id); window.LemmaStart(id);
  for (let count = 0; count < 50 && !calls.some(x => x.status === 'complete'); count++) await new Promise(resolve => setTimeout(resolve, 10));
  assert.equal(sends, 1);
  assert.equal(files.length, 1); assert.equal(files[0].size, 4);
  const results = calls.filter(x => x.operation === 'result' && x.status === 'complete');
  assert.equal(results.length, 1); assert.equal(results[0].answer, 'Full rank gives uniqueness.');
  assert.equal(results[0].conversationURL, 'https://chatgpt.com/');
  assert.ok(!window.document.body.textContent.includes('Save answer to note'), 'No companion panel is added to the embedded page.');
  instance.window.close();
});

test('embedded review mode waits for the user to send, then saves automatically', async () => {
  const instance = new JSDOM(`<form data-chatgpt-composer><div contenteditable="true" role="textbox" aria-label="Ask ChatGPT"></div><button type="button" aria-label="Send">Send</button></form>`, {url: 'https://chatgpt.com/', runScripts: 'outside-only'});
  const {window} = instance;
  let sends = 0, completed;
  window.DataTransfer = class { constructor() { this.items = {add() {}}; } };
  window.document.execCommand = (_, __, text) => { window.document.querySelector('[contenteditable]').textContent = text; };
  window.LemmaNativeRPC = async message => {
    if (message.operation === 'packet') return {ok: true, packet: {mode: 'draft', prompt: 'A public question', images: []}};
    if (message.status === 'complete') completed = message.answer;
    return {ok: true};
  };
  window.document.querySelector('button').onclick = () => {
    sends++;
    const turn = window.document.createElement('div'); turn.className = 'group flex flex-col';
    turn.innerHTML = '<div data-markdown-text-style="assistant-message">Reviewed answer.</div><button aria-label="Copy">Copy</button>';
    window.document.body.append(turn);
  };
  window.eval(fs.readFileSync(require.resolve('../dom.js'), 'utf8'));
  window.eval(fs.readFileSync(require.resolve('../content.js'), 'utf8'));
  window.LemmaStart('aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee');
  await new Promise(resolve => setTimeout(resolve, 20));
  assert.equal(sends, 0); assert.equal(completed, undefined);
  window.document.querySelector('button').click();
  await new Promise(resolve => setTimeout(resolve, 20));
  assert.equal(sends, 1); assert.equal(completed, 'Reviewed answer.');
  instance.window.close();
});
