const {test} = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const arxiv = require('../arxiv.js');

test('Quick Add accepts arXiv abstract, PDF and HTML URLs and keeps the chosen version', () => {
  assert.equal(arxiv.identifier('https://arxiv.org/abs/1706.03762v7'), '1706.03762v7');
  assert.equal(arxiv.identifier('https://arxiv.org/pdf/math/0406456v2.pdf'), 'math/0406456v2');
  assert.equal(arxiv.identifier('https://arxiv.org/html/2401.12345v2#section'), '2401.12345v2');
  for (const url of ['https://arxiv.org.evil.test/abs/1706.03762', 'https://arxiv.org/search/?query=1706.03762', 'file:///1706.03762', 'https://arxiv.org/abs/1706.03762;open']) {
    assert.equal(arxiv.identifier(url), null);
  }
});

test('Toolbar click sends only the identifier over the existing native bridge', () => {
  let clicked, nativeResponse;
  const messages = [], badges = [];
  const context = {
    URL, LemmaArxiv: arxiv, importScripts() {},
    chrome: {
      action: {onClicked: {addListener(f) {clicked = f;}}, setBadgeText(value) {badges.push(value);}, setTitle() {}, setBadgeBackgroundColor() {}},
      runtime: {
        onMessage: {addListener() {}},
        connectNative(name) {
          assert.equal(name, 'com.lemma.browser');
          return {onMessage: {addListener(f) {nativeResponse = f;}}, onDisconnect: {addListener() {}}, postMessage(message) {messages.push(message);}};
        }
      }
    }
  };
  vm.runInNewContext(fs.readFileSync(require.resolve('../background.js'), 'utf8'), context);
  clicked({id: 3, url: 'https://arxiv.org/pdf/1706.03762v7'});
  assert.equal(messages.length, 1);
  assert.equal(messages[0].operation, 'arxiv'); assert.equal(messages[0].arxivID, '1706.03762v7');
  assert.deepEqual(Object.keys(messages[0]).sort(), ['arxivID', 'callID', 'operation']);
  nativeResponse({callID: messages[0].callID, ok: true});
  assert.equal(badges.at(-1).text, '✓');
  clicked({id: 4, url: 'https://example.test/private'});
  assert.equal(messages.length, 1, 'Unrelated tabs never reach the native host');
});
