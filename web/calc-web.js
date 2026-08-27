// calc-web.js — WebSocket client and stack renderer.
//
// The browser is a dumb terminal: every keydown is translated to a calc
// key description and sent as {"key": "..."}; Emacs answers with the
// whole state — LaTeX stack (top first), pending number entry, pending
// chord, modifier flags, trail tail, error — and this file renders it.
// No state is kept here beyond the socket and the typeset cache.

const PORT = 7070;
// Shown beside the connection status; bump on client changes so a
// stale cached page is visible at a glance.
const VERSION = 6;

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
  ArrowUp: "<up>",
  ArrowDown: "<down>",
  ArrowLeft: "<left>",
  ArrowRight: "<right>",
  // Pre-standard names some engines still report.
  Up: "<up>",
  Down: "<down>",
  Left: "<left>",
  Right: "<right>",
};

let ws = null;

function connect() {
  ws = new WebSocket(`ws://localhost:${PORT}`);
  ws.onopen = () => { statusEl.textContent = `connected · v${VERSION}`; };
  ws.onclose = () => {
    statusEl.textContent = `disconnected — retrying · v${VERSION}`;
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
    // A formula MathJax cannot typeset falls back to its TeX source
    // rather than taking the whole render down with it. Failures are
    // not cached: they are cheap to reproduce and may be transient
    // (an extension still loading).
    try {
      svg = MathJax.tex2svg(tex, { display: true });
    } catch {
      return document.createTextNode(tex);
    }
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

function row(labelText, content, cls, line, col) {
  const div = document.createElement("div");
  div.className = cls ? `entry ${cls}` : "entry";
  const label = document.createElement("span");
  label.className = "label";
  label.textContent = labelText;
  const body = document.createElement("span");
  body.className = "body";
  const expr = document.createElement("span");
  expr.className = "expr";
  if (typeof content === "string") {
    expr.classList.add("mono");
    expr.textContent = content;
  } else {
    expr.append(content);
  }
  body.append(expr);
  if (line != null) {
    // The buffer line behind the typeset formula, caret at point's
    // column — the browser's exact view of where point stands.
    const src = document.createElement("span");
    src.className = "srcline";
    const caret = document.createElement("span");
    caret.className = "tcaret";
    src.append(line.slice(0, col), caret, line.slice(col));
    body.append(src);
  }
  div.append(label, body);
  return div;
}

// The maf-edit line: raw buffer text with a caret at the edit column.
function editRow(text, col) {
  const div = document.createElement("div");
  div.className = "entry typing current";
  const label = document.createElement("span");
  label.className = "label";
  label.textContent = "edit";
  const expr = document.createElement("span");
  expr.className = "expr mono";
  const caret = document.createElement("span");
  caret.className = "tcaret";
  expr.append(text.slice(0, col), caret, text.slice(col));
  div.append(label, expr);
  return div;
}

function render(state) {
  lastState = state;
  if (!mjReady) return;
  const { stack = [], cursor = 0, entry, edit, editCol = 0, line,
          col = 0, prompt, minibuf, pending, flags = {}, trail = [],
          error } = state;

  // stack[0] is the top (level 1); calc shows levels descending, the
  // top on the last line, then calc's home line — replaced by the
  // number entry while one is being typed. The row point stands on
  // (level `cursor`, home when 0) carries the caret. During a
  // maf-edit session that row shows the buffer line being edited —
  // the serialized value behind it is stale until the commit.
  const frag = document.createDocumentFragment();
  stack
    .map((tex, i) =>
      edit != null && cursor === i + 1
        ? editRow(edit, editCol)
        : row(`${i + 1}:`, texNode(tex),
              cursor === i + 1 ? "current" : null,
              cursor === i + 1 ? line : null, col))
    .reverse()
    .forEach((r) => frag.append(r));
  if (prompt != null) {
    // A blocked command's minibuffer, mirrored: prompt, what has been
    // typed at it, caret at the end. Keys go straight to it.
    frag.append(editRow(`${prompt}${minibuf ?? ""}`, `${prompt}${minibuf ?? ""}`.length));
  } else if (edit != null && cursor === 0) {
    frag.append(editRow(edit, editCol));
  } else if (entry != null) {
    frag.append(row(">", entry, "typing current"));
  } else {
    frag.append(row(".", "", cursor === 0 ? "home current" : "home"));
  }
  stackEl.replaceChildren(frag);
  stackEl.scrollTop = stackEl.scrollHeight;

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
