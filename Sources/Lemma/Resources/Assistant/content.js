(() => {
  function start(requestID, options = {}) {
  if (window.LemmaActiveRequest === requestID) return;
  window.LemmaActiveRequest = requestID;
  const native = typeof window.LemmaNativeRPC === "function";
  const dom = window.LemmaDOM;
  let stopped = false;
  let observer;
  let timeout;
  let scheduled;
  let returning = false;
  let packet;
  // Lemma's text is in the composer and has not been sent: a failure or cancellation removes it again, since
  // ChatGPT would otherwise restore it in every new chat.
  let inserted = false;
  let sent = false;
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
  async function report(state, message, extra = {}) {
    await rpc({operation: "result", status: state, message, ...extra, conversationURL: location.href.split("#")[0]});
  }
  /* An error Lemma can act on: `reason` names the case (draft, conversation, signedOut, attach, insert, ready). */
  function failure(message, reason) { const error = new Error(message); error.reason = reason; return error; }
  function finish() { stopped = true; observer?.disconnect(); clearTimeout(timeout); clearTimeout(scheduled); }
  function withdraw() {
    if (!inserted || sent || document.querySelector(dom.selectors.userMessages)) return;
    const editor = dom.composer(document);
    if (editor) dom.clearComposer(editor, dom.form(editor) || document);
    inserted = false;
  }
  window.LemmaCancel = id => {
    if (id !== requestID) return;
    finish();
    if (sent) dom.stop(document)?.click(); else withdraw();
    panel.remove();
  };
  async function fail(error) {
    finish(); status.textContent = error.message; save.disabled = true;
    try { withdraw(); } catch (_) {}
    if (packet) { try { await report("error", error.message, error.reason ? {reason: error.reason} : {}); } catch (_) {} }
  }
  cancel.onclick = async () => { await fail(new Error("Browser handoff ended. Your draft and conversation remain in Chrome.")); panel.remove(); };

  async function waitFor(test, duration = 30000, message = "ChatGPT did not become ready. Check the page, then prepare the question again.", reason = "ready") {
    const end = Date.now() + duration;
    while (!stopped && Date.now() < end) {
      const result = test(); if (result) return result;
      await new Promise(resolve => setTimeout(resolve, 150));
    }
    throw failure(message, reason);
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
      await report("complete", "Explanation saved in Lemma.", {answer});
      finish(); status.textContent = "Explanation saved beside its source in Lemma.";
    } catch (error) { returning = false; await fail(error); }
  }
  save.onclick = returnAnswer;

  /* A new chat that already holds something: Lemma's own unsent question is replaced; anything else is the reader's
     and stays unless the reader chose to replace it in Lemma. */
  async function emptyChat() {
    let state = dom.draft(document);
    if (state.conversation) throw failure("Prepare this question in a new empty chat so its answer stays linked to the right note.", "conversation");
    if (!state.text && !state.attachments) return state;
    const ours = state.text && dom.isLemmaDraft(state.text);
    if (!(options.replaceDraft || ours) || !native) {
      throw failure(native ? "ChatGPT's composer already holds an unsent draft, and Lemma left it in place."
                           : "The composer already contains a draft. Keep it, and prepare this question in an empty chat.", "draft");
    }
    dom.clearComposer(state.editor, state.form);
    await waitFor(() => { state = dom.draft(document); return state && !state.text && !state.attachments; }, 8000,
                  "Lemma could not clear ChatGPT's earlier draft. Clear it in the page, then ask again.", "draft");
    return state;
  }

  function progress() {
    scheduled = undefined;
    if (stopped) return;
    if (native) {
      if (!sent && document.querySelector(dom.selectors.userMessages)) {
        sent = true;
        report("sent", "Question sent. Waiting for the answer in Lemma.").catch(() => {});
      }
      const text = dom.partialAnswer(document);
      if (text && text !== progress.last) {
        progress.last = text;
        rpc({operation: "progress", answer: text}).catch(() => {});
      }
    }
    const answer = dom.completedAnswer(document);
    save.disabled = !answer;
    if (answer && (native || packet.mode === "askAndSave")) returnAnswer();
    else if (answer) status.textContent = "Answer ready. Save it beside this source note when you choose.";
  }
  // A streaming reply changes the page many times a second; reading it a few times a second is enough.
  function schedule() { if (!scheduled && !stopped) scheduled = setTimeout(progress, 300); }

  async function begin() {
    try {
      status.textContent = "Connecting to your source note…";
      packet = (await rpc({operation: "packet"})).packet;
      await report("prepared", native ? "Opening an empty chat…" : "Companion connected. Preparing the source images…");
      let askedToSignIn = false;
      await waitFor(() => {
        if (native && !askedToSignIn && dom.signedOut(document)) {
          askedToSignIn = true;
          report("prepared", "Sign in to ChatGPT in this page. Lemma prepares the question once the chat is ready.").catch(() => {});
        }
        return dom.composer(document);
      }, native ? 10 * 60 * 1000 : 30000, "ChatGPT did not show its composer. Sign in or reload the page, then ask again.", "signedOut");
      await emptyChat();
      const chat = Array.from(document.querySelectorAll('button')).find(button => button.textContent.trim() === "Chat" && button.hasAttribute("aria-pressed"));
      if (!chat && !native) throw new Error("Chat mode is unavailable. Switch to Chat, then prepare the question again.");
      if (chat && chat.getAttribute("aria-pressed") !== "true") {
        chat.click(); await waitFor(() => chat.getAttribute("aria-pressed") === "true");
      }
      const editor = dom.composer(document);
      const form = dom.form(editor);
      const fileInput = form && dom.fileInput(form);
      if (!fileInput && packet.images.length) throw failure("ChatGPT offers no way to attach images in this page. Sign in, reload the page, then ask again from the note.", "attach");
      status.textContent = "Preparing source images…";
      const transfer = new DataTransfer();
      for (const image of packet.images) transfer.items.add(await imageFile(image));
      inserted = true;
      if (packet.images.length) {
        fileInput.files = transfer.files;
        fileInput.dispatchEvent(new Event("change", {bubbles: true}));
      }
      dom.insertText(editor, packet.prompt);
      const intact = dom.sameText(dom.composerText(dom.composer(document) || editor), packet.prompt);
      if (!intact && (packet.mode === "askAndSave" || !native)) {
        throw failure("ChatGPT changed the question while Lemma typed it, so Lemma did not send it. Ask again, or choose Review first to check the text.", "insert");
      }
      await waitFor(() => {
        const send = dom.send(form);
        return send && !send.disabled && dom.attachmentsShown(form, packet.images) ? send : null;
      }, 120000, "ChatGPT did not finish attaching the source images. Check the page, then ask again.", "attach");
      if (stopped) return;
      const review = intact ? "Draft ready. Review it, then press Send in the page below." : "Draft ready, but ChatGPT changed some characters: check it, then press Send in the page below.";
      await report("prepared", native ? review : "Question and source images prepared in Chrome.");
      observer = new MutationObserver(schedule);
      observer.observe(document.body, {subtree: true, childList: true, characterData: true, attributes: true});
      timeout = setTimeout(() => fail(failure("No complete answer arrived within an hour. The conversation stays in ChatGPT; copy the useful part into the note.", "timeout")), (native ? 60 : 30) * 60 * 1000);
      if (packet.mode === "askAndSave") {
        const send = dom.send(form);
        if (!send || send.disabled) throw failure("ChatGPT is not ready to send. Your draft remains in the composer.", "ready");
        // Only the explicit Ask and save packet authorizes this one click.
        send.click();
        sent = true;
        status.textContent = "Question sent. Waiting for the completed explanation…";
        await report("sent", native ? "Question sent. ChatGPT is answering…" : "Question sent in Chat mode. Waiting for its answer.");
      } else {
        status.textContent = native ? "Review and send below. The answer will be saved automatically in Lemma." : "Draft ready. Review and send in ChatGPT, then save the answer here.";
      }
      progress();
    } catch (error) { await fail(error); }
  }
  begin();
  }
  // Lemma's embedded Web view starts the same adapter through its local bridge.
  if (typeof window.LemmaNativeRPC === "function") window.LemmaStart = start;
  else {
    const match = location.hash.match(/^#lemma=([0-9a-f-]{36})$/i);
    if (match) start(match[1]);
  }
})();
