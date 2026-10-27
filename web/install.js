// Keeps the browser's "install this app" offer so the Install App button in
// Settings can show it later (Chrome, Brave and Edge only offer it once).
window.peInstall = { offer: null };
window.addEventListener('beforeinstallprompt', function (e) {
  e.preventDefault();
  window.peInstall.offer = e;
});
window.addEventListener('appinstalled', function () {
  window.peInstall.offer = null;
});

// Remembers whether Ctrl (or Cmd) is held for the key being pressed, so
// Ctrl+A (save) works even when a keyboard or remote tool sends it without
// a separate Ctrl press. Registered before the app loads, so it runs first.
window.peCtrl = false;
function peNoteCtrl(e) { window.peCtrl = !!(e.ctrlKey || e.metaKey); }
window.addEventListener('keydown', peNoteCtrl, true);
window.addEventListener('keyup', peNoteCtrl, true);
