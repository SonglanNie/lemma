const test = require('node:test');
const assert = require('node:assert/strict');
const { JSDOM } = require('jsdom');
const fs = require('node:fs');
const path = require('node:path');

function preview(markdown) {
  const dom = new JSDOM('<!doctype html><article id="content"></article>', { runScripts: 'outside-only' });
  const directory = path.join(__dirname, '../../Sources/Lemma/Resources/Math');
  for (const name of ['katex.min.js', 'marked.js', 'purify.min.js', 'study.js']) dom.window.eval(fs.readFileSync(path.join(directory, name), 'utf8'));
  dom.window.document.getElementById('content').innerHTML = dom.window.renderStudyHTML(markdown);
  return dom;
}

test('saved Markdown/LaTeX keeps subscripts, backslashes and display math', () => {
  const dom = preview(String.raw`Writing $\mathrm{RSS}(\beta)=\|y-X\beta\|_2^2$, its Hessian is

$$
\nabla^2 \mathrm{RSS}(\beta)=2X^\top X.
$$

**Full column rank** gives a unique minimizer. Also \(X \in \mathbb{R}^{n \times p}\).`);
  const document = dom.window.document;
  assert.equal(document.querySelectorAll('.katex').length, 3);
  assert.equal(document.querySelectorAll('.katex-display').length, 1);
  assert.equal(document.querySelectorAll('.katex-error').length, 0);
  assert.match(document.querySelector('annotation').textContent, /_2\^2/);
  assert.equal(document.querySelector('strong').textContent, 'Full column rank');
  dom.window.close();
});

test('math stays literal in code and malformed LaTeX remains readable', () => {
  const dom = preview('`$x_1$`\n\n```tex\n$$a_b$$\n```\n\n$\\frac{1}{$');
  const document = dom.window.document;
  assert.equal(document.querySelectorAll('.katex').length, 0);
  assert.equal(document.querySelector('code').textContent, '$x_1$');
  assert.match(document.querySelector('pre').textContent, /\$\$a_b\$\$/);
  assert.match(document.querySelector('.katex-error').textContent, /frac/);
  dom.window.close();
});

test('saved answers cannot embed scripts, remote images, or active HTML', () => {
  const dom = preview('<script>window.compromised=true</script><img src="https://example.com/private" onerror="alert(1)"><iframe src="https://example.com"></iframe>\n\n[unsafe](javascript:alert(1))\n\n$\\href{javascript:alert(1)}{x}$');
  const document = dom.window.document;
  assert.equal(document.querySelectorAll('script,img,iframe,[onerror]').length, 0);
  assert.equal(document.querySelectorAll('a[href^="javascript:"]').length, 0);
  assert.equal(dom.window.compromised, undefined);
  dom.window.close();
});

test('source citations keep their exact Lemma page while executable links are stripped', () => {
  const dom = preview('[S2](lemma://open?book=book-b&page=83)\n\n[unsafe](javascript:alert(1))');
  const document = dom.window.document;
  assert.equal(document.querySelector('a').getAttribute('href'), 'lemma://open?book=book-b&page=83');
  assert.equal(document.querySelectorAll('a[href^="javascript:"]').length, 0);
  dom.window.close();
});
