(() => {
  function start(requestID) {
  if (window.LemmaActiveRequest === requestID) return;
  window.LemmaActiveRequest = requestID;
  const native = typeof window.LemmaNativeRPC === "function";
  const dom = window.LemmaDOM;
  let stopped = false;
  let observer;
  let timeout;
  let returning = false;
  let packet;
  const panel = document.createElement("div");
  panel.style.cssText = "position:fixed;right:18px;bottom:18px;z-index:2147483647;padding:14px 16px;max-width:340px;background:#fafaf7;color:#24261b;border:1px solid #c7cbb8;border-radius:12px;box-shadow:0 4px 24px #0002;font:13px/1.45 -apple-system,BlinkMacSystemFont,sans-serif;";
  const title = document.createElement("strong"); title.textContent = "Lemma";
  const status = document.createElement("div"); status.style.margin = "6px 0 10px";
  const save = document.createElement("button"); save.textContent = "Save answer to note"; save.disabled = true;
  const cancel = document.createElement("button"); cancel.textContent = "End handoff"; cancel.style.marginLeft = "8px";
  for (const button of [save, cancel]) button.style.cssText += "padding:6px 9px;border:1px solid #adb49b;border-radius:6px;background:#fff;color:#303726;cursor:pointer;";
  panel.append(title, status, save, cancel);
  if (!native) document.documentElement.append(panel);

  async function rpc(message) {
    const response = await (native ? window.LemmaNativeRPC({...message, requestID}) : chrome.runtime.sendMessage({...message, requestID}));
    if (!response?.ok) throw new Error(response?.error || "The Chrome companion is not connected to Lemma.");
    return response;
  }
  async function report(state, message, answer) {
    await rpc({operation: "result", status: state, message, answer, conversationURL: location.href.split("#")[0]});
  }
  function finish() { stopped = true; observer?.disconnect(); clearTimeout(timeout); }
  window.LemmaCancel = id => {
    if (id !== requestID) return;
    finish();
    dom.stop(document)?.click();
    panel.remove();
  };
  async function fail(error) {
    finish(); status.textContent = error.message; save.disabled = true;
    if (packet) { try { await report("error", error.message); } catch (_) {} }
  }
  cancel.onclick = async () => { await fail(new Error("Browser handoff ended. Your draft and conversation remain in Chrome.")); panel.remove(); };

  async function waitFor(test, duration = 30000) {
    const end = Date.now() + duration;
    while (!stopped && Date.now() < end) {
      const result = test(); if (result) return result;
      await new Promise(resolve => setTimeout(resolve, 150));
    }
    throw new Error("ChatGPT did not become ready. Check the page, then prepare the question again.");
  }

  async function imageFile(image) {
    const chunks = [];
    for (let index = 0; ; index++) {
      const part = await rpc({operation: "image", name: image.name, index});
      chunks.push(Uint8Array.from(atob(part.data), character => character.charCodeAt(0)));
      if (part.done) break;
    }
    const file = new File(chunks, image.name, {type: "image/png"});
    if (file.size !== image.byteCount) throw new Error("The source image transfer was incomplete.");
    return file;
  }

  async function returnAnswer() {
    if (returning || stopped) return;
    const answer = dom.completedAnswer(document);
    if (!answer) return;
    returning = true; save.disabled = true;
    try {
      await report("complete", "Explanation saved in Lemma.", answer);
      finish(); status.textContent = "Explanation saved beside its source in Lemma.";
    } catch (error) { returning = false; await fail(error); }
  }
  save.onclick = returnAnswer;

  async function start() {
    try {
      status.textContent = "Connecting to your source note…";
      packet = (await rpc({operation: "packet"})).packet;
      await report("prepared", "Companion connected. Preparing the source images…");
      await waitFor(() => dom.composer(document), native ? 10 * 60 * 1000 : 30000);
      dom.assertEmpty(document);
      const chat = Array.from(document.querySelectorAll('button')).find(button => button.textContent.trim() === "Chat" && button.hasAttribute("aria-pressed"));
      if (!chat && !native) throw new Error("Chat mode is unavailable. Switch to Chat, then prepare the question again.");
      if (chat && chat.getAttribute("aria-pressed") !== "true") {
        chat.click(); await waitFor(() => chat.getAttribute("aria-pressed") === "true");
      }
      const editor = dom.assertEmpty(document);
      const form = editor.closest(dom.selectors.form);
      const fileInput = form?.querySelector(dom.selectors.fileInput);
      if (!fileInput && packet.images.length) throw new Error("Sign in to ChatGPT to attach the source images. If already signed in, reload the page and try again from Lemma.");
      status.textContent = "Preparing source images…";
      const transfer = new DataTransfer();
      for (const image of packet.images) transfer.items.add(await imageFile(image));
      if (packet.images.length) {
        fileInput.files = transfer.files;
        fileInput.dispatchEvent(new Event("change", {bubbles: true}));
      }
      editor.focus();
      document.execCommand("insertText", false, packet.prompt);
      if (dom.composerText(editor).trim() !== packet.prompt.trim()) {
        throw new Error("The question could not be inserted intact. Review the composer before sending.");
      }
      await waitFor(() => {
        const send = dom.send(form);
        const attachments = form.querySelector('[data-composer-attachments]');
        const names = [...form.querySelectorAll('[aria-label], [title]')].map(node => `${node.getAttribute('aria-label') || ''} ${node.getAttribute('title') || ''}`).join(' ');
        const shown = attachments && !attachments.hidden || packet.images.every(image => `${form.textContent} ${names}`.includes(image.name));
        return send && !send.disabled && (!packet.images.length || shown) ? send : null;
      }, 90000);
      if (stopped) return;
      await report("prepared", native ? "Draft ready in Lemma. Review it and press Send below." : "Question and source images prepared in Chrome.");
      let lastText = "";
      let reportedSent = packet.mode === "askAndSave";
      const check = () => {
        if (stopped) return;
        if (native) {
          if (!reportedSent && document.querySelector(dom.selectors.userMessages)) {
            reportedSent = true;
            report("sent", "Question sent. Waiting for the answer in Lemma.").catch(() => {});
          }
          const node = dom.answers(document).at(-1);
          const text = node ? dom.markdown(node).trim() : "";
          if (text && text !== lastText) {
            lastText = text;
            rpc({operation: "progress", answer: text}).catch(() => {});
          }
        }
        const answer = dom.completedAnswer(document);
        save.disabled = !answer;
        if (answer && (native || packet.mode === "askAndSave")) returnAnswer();
        else if (answer) status.textContent = "Answer ready. Save it beside this source note when you choose.";
      };
      observer = new MutationObserver(check);
      observer.observe(document.body, {subtree: true, childList: true, characterData: true, attributes: true, attributeFilter: ["disabled"]});
      timeout = setTimeout(() => fail(new Error("The handoff timed out. You can copy the useful explanation back into Lemma.")), 30 * 60 * 1000);
      if (packet.mode === "askAndSave") {
        const send = dom.send(form);
        if (!send || send.disabled) throw new Error("ChatGPT is not ready to send. Your draft remains in the composer.");
        // Only the explicit Ask and save packet authorizes this one click.
        send.click();
        status.textContent = "Question sent. Waiting for the completed explanation…";
        await report("sent", "Question sent in Chat mode. Waiting for its answer.");
      } else {
        status.textContent = native ? "Review and send below. The answer will be saved automatically in Lemma." : "Draft ready. Review and send in ChatGPT, then save the answer here.";
      }
      check();
    } catch (error) { await fail(error); }
  }
  start();
  }
  // Lemma's embedded Web view starts the same adapter through its local bridge.
  if (typeof window.LemmaNativeRPC === "function") window.LemmaStart = start;
  else {
    const match = location.hash.match(/^#lemma=([0-9a-f-]{36})$/i);
    if (match) start(match[1]);
  }
})();
