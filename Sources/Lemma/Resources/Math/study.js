/* Local-only Markdown/LaTeX preview. Source remains editable in the native pane. */
(function (root) {
  function mathHTML(text, displayMode) {
    return root.katex.renderToString(text, { displayMode, throwOnError: false, trust: false, maxExpand: 1000, maxSize: 20, output: 'htmlAndMathml' });
  }
  root.marked.use({ extensions: [
    {
      name: 'studyBlockMath', level: 'block',
      start(src) { return src.search(/\$\$|\\\[/); },
      tokenizer(src) {
        const match = /^(?:\$\$([\s\S]+?)\$\$|\\\[([\s\S]+?)\\\])(?:\n|$)/.exec(src);
        if (match) return { type: 'studyBlockMath', raw: match[0], text: (match[1] || match[2]).trim() };
      },
      renderer(token) { return mathHTML(token.text, true); }
    },
    {
      name: 'studyInlineMath', level: 'inline',
      start(src) { return src.search(/\$|\\[([]/); },
      tokenizer(src) {
        const match = /^(?:\$\$([\s\S]+?)\$\$|\$([^$\n]+?)\$|\\\(([\s\S]+?)\\\)|\\\[([\s\S]+?)\\\])/.exec(src);
        if (match) return { type: 'studyInlineMath', raw: match[0], text: (match[1] || match[2] || match[3] || match[4]).trim(), display: !!(match[1] || match[4]) };
      },
      renderer(token) { return mathHTML(token.text, token.display); }
    }
  ] });
  root.renderStudyHTML = function (markdown) {
    return root.DOMPurify.sanitize(root.marked.parse(markdown), {
      USE_PROFILES: { html: true, mathMl: true },
      ADD_TAGS: ['semantics', 'annotation'],
      ADD_ATTR: ['encoding'],
      // Source citations use Lemma's own page links; executable schemes remain forbidden.
      ALLOWED_URI_REGEXP: /^(?:(?:https?|mailto|lemma):|[^a-z]|[a-z+.\-]+(?:[^a-z+.\-:]|$))/i,
      FORBID_TAGS: ['img', 'svg', 'iframe', 'form', 'input', 'button', 'video', 'audio', 'style'],
      FORBID_ATTR: ['src', 'srcset']
    });
  };
  // The workbench theme's colours, as CSS variables (see study.css); an empty object returns to the defaults.
  root.setStudyTheme = function (colours) {
    const style = document.documentElement.style;
    for (const name of ['text', 'link', 'code-text', 'code-bg', 'quote-bg', 'rule']) {
      if (colours && colours[name]) style.setProperty('--' + name, colours[name]); else style.removeProperty('--' + name);
    }
  };
  root.renderStudy = function (markdown, colours) {
    root.setStudyTheme(colours);
    const content = document.getElementById('content');
    content.innerHTML = root.renderStudyHTML(markdown);
    fitDisplays();
    document.fonts.ready.then(() => { fitDisplays(); reportHeight(); });
    reportHeight();
  };
  // A displayed equation wider than the column is set smaller, down to 72 %, so that it and its number fit side by side:
  // KaTeX centres the equation over the whole width and pins the number to the right edge, where it covered the end of a
  // wide equation. Narrower still, the equation scrolls sideways with its number after it.
  function fitDisplays() {
    document.querySelectorAll('#content .katex-display').forEach(display => {
      const katex = display.querySelector(':scope > .katex');
      const html = katex && katex.querySelector(':scope > .katex-html');
      if (!html || display.closest('.step')) return;
      katex.style.fontSize = '';
      display.classList.remove('wide');
      const width = display.clientWidth - 4;
      const tag = html.querySelector(':scope > .tag');
      let equation = 0;
      for (const part of html.children) if (part !== tag) equation += part.getBoundingClientRect().width;
      const needed = equation + (tag ? 2 * (tag.getBoundingClientRect().width + 12) : 0);
      if (width <= 0 || needed <= width) return;
      const scale = width / needed;
      katex.style.fontSize = (1.06 * Math.max(0.72, scale)).toFixed(3) + 'em';
      if (scale < 0.72) display.classList.add('wide');
    });
  }
  let fittedWidth = 0;
  root.addEventListener('resize', () => {
    if (document.documentElement.clientWidth === fittedWidth) return;
    fittedWidth = document.documentElement.clientWidth;
    fitDisplays();
  });
  // A derivation's steps, typeset one per row with the verdict in the gutter, as an editor's preview.
  function escapeText(text) {
    return String(text).replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
  }
  const marks = { holds: '✓', fails: '✗', error: '!', unchecked: '?', given: '●', definition: '≔', declaration: '∈', comment: '' };
  root.renderSteps = function (steps) {
    const content = document.getElementById('content');
    const rows = steps.map(step => {
      const status = escapeText(step.status);
      let body;
      if (step.status === 'comment') body = `<div class="step-comment">${escapeText(step.text)}</div>`;
      else if (step.status === 'error') body = `<code class="step-source">${escapeText(step.text)}</code>`;
      else body = mathHTML(step.latex, true);
      const note = step.message && !['holds', 'comment', 'declaration'].includes(step.status)
        ? `<div class="step-message">${escapeText(step.message)}${step.detail ? `<div class="step-detail">${escapeText(step.detail)}</div>` : ''}</div>` : '';
      return `<div class="step step-${status}" data-line="${step.line}"><div class="step-gutter"><span class="step-number">${step.line + 1}</span><span class="step-mark">${marks[step.status] || ''}</span></div><div class="step-body">${body}${note}</div></div>`;
    });
    content.innerHTML = rows.join('') || '<p class="step-empty">Steps appear here, typeset and checked, as you type them.</p>';
    content.querySelectorAll('.step').forEach(row => row.addEventListener('click', () => {
      root.webkit?.messageHandlers?.stepClicked?.postMessage(Number(row.dataset.line));
    }));
    document.fonts.ready.then(reportHeight);
    reportHeight();
  };
  function reportHeight() {
    const height = document.getElementById('content')?.getBoundingClientRect().height || 1;
    root.webkit?.messageHandlers?.studyHeight?.postMessage(Math.ceil(height));
  }
  if (root.ResizeObserver) new ResizeObserver(reportHeight).observe(document.getElementById('content'));
})(window);
