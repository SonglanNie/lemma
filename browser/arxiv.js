/* Only a user-invoked tab URL is read. Versions are preserved and only arXiv hosts are accepted. */
(function (root) {
  function identifier(address) {
    try {
      const url = new URL(address);
      if (!["https:", "http:"].includes(url.protocol) || !["arxiv.org", "www.arxiv.org", "export.arxiv.org"].includes(url.hostname)) return null;
      const match = url.pathname.match(/^\/(?:abs|pdf|html)\/(.+?)(?:\.pdf)?$/);
      if (!match) return null;
      const id = decodeURIComponent(match[1]);
      return /^(?:\d{4}\.\d{4,5}|[a-z][a-z-]*(?:\.[A-Z]{2})?\/\d{7})(?:v[1-9]\d*)?$/.test(id) ? id : null;
    } catch { return null; }
  }
  const api = {identifier};
  root.LemmaArxiv = api;
  if (typeof module === "object") module.exports = api;
})(globalThis);
