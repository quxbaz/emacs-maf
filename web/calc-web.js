// calc-web.js — WebSocket client and stack renderer.
//
// The browser is a dumb terminal: every keydown is translated to a calc
// key description and sent as {"key": "..."}; Emacs answers with the
// whole state — LaTeX stack (top first), pending number entry, pending
// chord, modifier flags, trail tail, error — and this file renders it.
// No state is kept here beyond the socket and the typeset cache.

const PORT = 7070;

const stackEl = document.getElementById("stack");
const trailEl = document.getElementById("trail");
const statusEl = document.getElementById("status");
const pendingEl = document.getElementById("pending");
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

// Typeset once per distinct formula. Every push carries the whole
// stack, but most keystrokes move an entry rather than change it, so
// rendered SVG is cached by its TeX source and rows are rebuilt from
// clones — no flash of untypeset math, and MathJax runs only for
// formulas it has never seen.
const texCache = new Map();

function texNode(tex) {
  let svg = texCache.get(tex);
  if (!svg) {
    svg = MathJax.tex2svg(tex, { display: true });
    // Manual tex2svg leaves the page stylesheet stale; refresh it so
    // the new formula's characters get their font rules.
    MathJax.startup.document.updateDocument();
    if (texCache.size > 500) texCache.clear();
    texCache.set(tex, svg);
  }
  return svg.cloneNode(true);
}

// MathJax arrives from a CDN after the socket usually connects; hold
// the latest state until it is ready rather than dropping the push.
let mjReady = false;
let lastState = null;

window.addEventListener("mathjax-ready", () => {
  mjReady = true;
  if (lastState) render(lastState);
});

function row(labelText, content, cls) {
  const div = document.createElement("div");
  div.className = cls ? `entry ${cls}` : "entry";
  const label = document.createElement("span");
  label.className = "label";
  label.textContent = labelText;
  const expr = document.createElement("span");
  expr.className = "expr";
  if (typeof content === "string") {
    expr.classList.add("mono");
    expr.textContent = content;
  } else {
    expr.append(content);
  }
  div.append(label, expr);
  return div;
}

function render(state) {
  lastState = state;
  if (!mjReady) return;
  const { stack = [], entry, pending, flags = {}, trail = [], error } = state;

  // stack[0] is the top (level 1); calc shows levels descending, the
  // top on the last line, any in-progress number entry below it.
  const frag = document.createDocumentFragment();
  stack
    .map((tex, i) => row(`${i + 1}:`, texNode(tex)))
    .reverse()
    .forEach((r) => frag.append(r));
  if (entry != null) frag.append(row(">", entry, "typing"));
  stackEl.replaceChildren(frag);

  trailEl.replaceChildren(
    ...trail.map((line) => {
      const div = document.createElement("div");
      div.className = "trail-line";
      div.textContent = line;
      return div;
    }),
  );
  trailEl.scrollTop = trailEl.scrollHeight;

  for (const [name, el] of Object.entries(flagEls)) {
    el.classList.toggle("on", flags[name] === true);
  }
  pendingEl.textContent = pending ? `${pending} -` : "";
  errorEl.textContent = error ?? "";
}

connect();
