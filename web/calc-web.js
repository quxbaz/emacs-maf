// calc-web.js — WebSocket client and stack renderer.
//
// The browser is a dumb terminal: every keydown is translated to a calc
// key description and sent as {"key": "..."}; Emacs answers with the
// whole state — LaTeX stack (top first), pending number entry, modifier
// flags, error — and this file renders it. No state is kept here beyond
// the socket itself.

const PORT = 7070;

const stackEl = document.getElementById("stack");
const statusEl = document.getElementById("status");
const errorEl = document.getElementById("error");
const flagEls = {
  hyp: document.getElementById("flag-hyp"),
  inv: document.getElementById("flag-inv"),
  opt: document.getElementById("flag-opt"),
};

// Browser key names that differ from Emacs key descriptions. Keys
// missing here and longer than one character (arrows, F-keys, ...) are
// left to the browser.
const KEYMAP = {
  Enter: "RET",
  Backspace: "DEL",
  Delete: "DEL",
  Escape: "ESC",
  Tab: "TAB",
  " ": "SPC",
};

let ws = null;

function connect() {
  ws = new WebSocket(`ws://localhost:${PORT}`);
  ws.onopen = () => { statusEl.textContent = "connected"; };
  ws.onclose = () => {
    statusEl.textContent = "disconnected — retrying";
    setTimeout(connect, 1000);
  };
  ws.onmessage = ({ data }) => render(JSON.parse(data));
}

document.addEventListener("keydown", (ev) => {
  if (ev.ctrlKey || ev.metaKey || ev.altKey) return; // browser's own chords
  const key = KEYMAP[ev.key] ?? (ev.key.length === 1 ? ev.key : null);
  if (!key || ws?.readyState !== WebSocket.OPEN) return;
  ev.preventDefault(); // calc owns "/", "*", "'", Backspace, ...
  ws.send(JSON.stringify({ key }));
});

function render({ stack = [], entry, flags = {}, error }) {
  if (stack !== undefined) {
    // stack[0] is the top (level 1); calc shows levels descending, the
    // top on the last line, with any in-progress number entry below it.
    const lines = stack.map(
      (tex, i) => `<div class="entry">
        <span class="label">${i + 1}:</span>
        <span class="expr">\\(${tex}\\)</span>
      </div>`,
    ).reverse();
    if (entry != null) {
      lines.push(`<div class="entry typing">
        <span class="label">&gt;</span>
        <span class="expr mono">${entry}</span>
      </div>`);
    }
    stackEl.innerHTML = lines.join("");
    if (window.MathJax?.typesetPromise) MathJax.typesetPromise([stackEl]);
  }
  for (const [name, el] of Object.entries(flagEls)) {
    el.classList.toggle("on", flags[name] === true);
  }
  errorEl.textContent = error ?? "";
}

connect();
