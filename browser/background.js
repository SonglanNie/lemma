/* Local native messaging only. No provider API, credentials, or page network requests. */
importScripts("arxiv.js");
let port;
let nextCall = 0;
const pending = new Map();

function connection() {
  if (port) return port;
  port = chrome.runtime.connectNative("com.lemma.browser");
  port.onMessage.addListener(response => {
    const callback = pending.get(response.callID);
    if (!callback) return;
    pending.delete(response.callID);
    callback(response);
  });
  port.onDisconnect.addListener(() => {
    const error = chrome.runtime.lastError?.message || "The Lemma connection closed.";
    port = undefined;
    for (const callback of pending.values()) callback({ok: false, error});
    pending.clear();
  });
  return port;
}

function nativeCall(message, reply) {
  const callID = ++nextCall;
  pending.set(callID, reply);
  try { connection().postMessage({...message, callID}); }
  catch (error) { pending.delete(callID); reply({ok: false, error: error.message}); }
}

// Clicking the companion on an arXiv abstract, PDF or HTML page adds that exact paper to Lemma.
chrome.action.onClicked.addListener(tab => {
  const id = LemmaArxiv.identifier(tab.url || "");
  if (!id) {
    chrome.action.setBadgeText({tabId: tab.id, text: "?"});
    chrome.action.setTitle({tabId: tab.id, title: "Open an arXiv paper, then click to add it to Lemma. ChatGPT study actions start in Lemma."});
    return;
  }
  chrome.action.setBadgeText({tabId: tab.id, text: "…"});
  nativeCall({operation: "arxiv", arxivID: id}, response => {
    chrome.action.setBadgeText({tabId: tab.id, text: response.ok ? "✓" : "!"});
    chrome.action.setBadgeBackgroundColor({tabId: tab.id, color: response.ok ? "#355C37" : "#8C2F2F"});
    chrome.action.setTitle({tabId: tab.id, title: response.ok ? `arXiv:${id} sent to Lemma` : `Could not add the paper: ${response.error}`});
  });
});

chrome.runtime.onMessage.addListener((message, sender, reply) => {
  if (!sender.tab || new URL(sender.url).origin !== "https://chatgpt.com") return false;
  if (!["packet", "image", "result"].includes(message?.operation)) return false;
  if (!/^[0-9a-f]{8}(-[0-9a-f]{4}){3}-[0-9a-f]{12}$/i.test(message.requestID || "")) return false;
  nativeCall(message, reply);
  return true;
});
