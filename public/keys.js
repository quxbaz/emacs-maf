(function () {
  const D = window.MAF_BINDINGS;
  const $ = s => document.querySelector(s);
  const profileSel = $("#profile"), q = $("#q"), ctxonly = $("#ctxonly"), flagsonly = $("#flagsonly"), newonly = $("#newonly"), latex = $("#latex"), groupsEl = $("#groups"), pop = $("#pop"), count = $("#count");
  try { latex.checked = localStorage.getItem("maf-keys-latex") === "1"; } catch (e) {}
  if (new URLSearchParams(location.search).get("latex") === "1") latex.checked = true;
  latex.addEventListener("change", () => { try { localStorage.setItem("maf-keys-latex", latex.checked ? "1" : "0"); } catch (e) {} if (!pop.hidden && current) show(current); });
  let current = null;
  // An example as a stack: its inputs on numbered levels, the last one level 1, then the result.
  // With the toggle on and a LaTeX form available, each line is typeset by MathJax.
  function example(it, cls) {
    if (!it.example) return "";
    const p = it.example_parts, tex = latex.checked && p && p.inputs_latex;
    if (!p) return '<div class="' + cls + ' mono">' + esc(it.example) + "</div>";
    const wrap = (s, t) => tex ? "\\(" + esc(t) + "\\)" : esc(s);
    const lines = p.inputs.map((s, i) => '<span class="lv">' + (p.inputs.length - i) + ":</span>  " + wrap(s, p.inputs_latex[i]));
    lines.push('<span class="lv arrow">=></span>  ' + wrap(p.result, p.result_latex));
    return '<pre class="' + cls + ' stack' + (tex ? " tex" : "") + '">' + lines.join("\n") + "</pre>";
  }
  // Typesetting calls are chained: MathJax refuses a second call while one is running.
  let chain = Promise.resolve();
  function typeset() {
    if (!(latex.checked && !pop.hidden && window.MathJax && MathJax.typesetPromise)) return;
    chain = chain.then(() => MathJax.typesetPromise([pop])).catch(() => {});
  }
  window.addEventListener("mathjax-ready", typeset);
  let profile, byCmd = {}, pinned = null;

  D.profiles.forEach(p => {
    const o = document.createElement("option");
    o.value = p.name; o.textContent = p.name + (p.name === D.default_profile ? " (default)" : "") + " — " + p.description;
    profileSel.appendChild(o);
  });
  profileSel.value = new URLSearchParams(location.search).get("profile") || D.default_profile;

  function lookup(cmd) {
    if (!cmd) return null;
    return byCmd[cmd] || (D.variants && D.variants[cmd]) || { cmd, title: null, example: null, doc: "" };
  }
  function titleOf(it) { return it.title ? it.title[0].toUpperCase() + it.title.slice(1) : it.cmd; }

  function render() {
    profile = D.profiles.find(p => p.name === profileSel.value);
    byCmd = {};
    profile.groups.forEach(g => g.items.forEach(it => { byCmd[it.cmd] = it; }));
    groupsEl.innerHTML = profile.groups.map((g, gi) => {
      const chips = g.items.map((it, ii) => {
        const flags = [it.inv && "I", it.hyp && "H", it.invhyp && "IH"].filter(Boolean).map(f => "<i>" + f + "</i>").join("");
        const hay = [it.cmd, it.title, it.example, it.doc, g.title].concat(it.keys).join(" ").toLowerCase();
        return '<button class="chip" data-g="' + gi + '" data-i="' + ii + '" data-hay="' + esc(hay) + '" data-ctx="' + (it.contextual ? 1 : 0) + '" data-flags="' + (flags ? 1 : 0) + '" data-new="' + (it.new ? 1 : 0) + '">' +
          (it.contextual ? '<span class="ctx" title="contextual"></span>' : '') +
          '<span class="keys">' + (it.keys.length ? kbdKeys(it.keys) : '<span class="muted">M-x</span>') + '</span>' +
          '<span class="title">' + esc(titleOf(it)) + '</span>' + (it.new ? '<span class="new" title="new in maf, no counterpart in stock Calc">✦</span>' : '') +
          (flags ? '<span class="flags">' + flags + '</span>' : '') + '</button>';
      }).join("");
      return '<section class="group" data-g="' + gi + '"><h2>' + esc(g.title) + ' <span class="count">' + g.items.length + '</span></h2><div class="chips">' + chips + '</div></section>';
    }).join("");
    filter();
  }

  function filter() {
    const needle = q.value.trim().toLowerCase();
    let shown = 0;
    groupsEl.querySelectorAll(".chip").forEach(ch => {
      let ok = !needle || ch.dataset.hay.includes(needle);
      if (ok && ctxonly.checked && ch.dataset.ctx !== "1") ok = false;
      if (ok && flagsonly.checked && ch.dataset.flags !== "1") ok = false;
      if (ok && newonly.checked && ch.dataset.new !== "1") ok = false;
      ch.classList.toggle("hidden", !ok);
      if (ok) shown++;
    });
    groupsEl.querySelectorAll(".group").forEach(g => {
      g.style.display = g.querySelector(".chip:not(.hidden)") ? "" : "none";
    });
    const total = profile.groups.reduce((n, g) => n + g.items.length, 0);
    count.textContent = shown + " of " + total + " commands";
    hide();
  }

  function flagRow(label, cmd) {
    if (!cmd) return "";
    const v = lookup(cmd);
    return "<tr><td>" + label + "</td><td><b>" + esc(titleOf(v)) + "</b> <span class=\"sym mono\">" + esc(v.cmd) + "</span>" +
      example(v, "muted") +
      (v.doc ? '<div class="muted">' + esc(v.doc) + "</div>" : "") + "</td></tr>";
  }

  function show(chip) {
    current = chip;
    const g = profile.groups[+chip.dataset.g], it = g.items[+chip.dataset.i];
    const flags = flagRow("<kbd>I</kbd>", it.inv) + flagRow("<kbd>H</kbd>", it.hyp) + flagRow("<kbd>I</kbd><kbd>H</kbd>", it.invhyp);
    pop.innerHTML = '<div class="head"><b>' + esc(titleOf(it)) + "</b> " + kbdKeys(it.keys) + ' <span class="sym mono">' + esc(it.cmd) + "</span></div>" +
      example(it, "ex") +
      '<div class="doc">' + esc(it.doc) + "</div>" +
      (flags ? "<table>" + flags + "</table>" : "") +
      (it.new ? '<div class="note"><span class="new">✦</span> New in maf: no counterpart in stock Calc.</div>' : "") +
      (it.contextual ? '<div class="note">Contextual: resolves point and the calc state into a target and commits the result back to it. Answers <kbd>M</kbd> by mapping over a vector or the sides of a relation.</div>' : "") +
      (it.docfull && it.docfull.trim() !== it.doc.trim() ? '<details class="full"><summary>Full documentation</summary><pre>' + esc(it.docfull) + "</pre></details>" : "");
    pop.hidden = false;
    typeset();
    const r = chip.getBoundingClientRect(), pw = pop.offsetWidth, ph = pop.offsetHeight;
    let left = r.left + window.scrollX, top = r.bottom + window.scrollY + 6;
    if (left + pw > window.scrollX + document.documentElement.clientWidth - 12) left = window.scrollX + document.documentElement.clientWidth - pw - 12;
    if (r.bottom + ph + 12 > window.innerHeight && r.top - ph - 6 > 0) top = r.top + window.scrollY - ph - 6;
    pop.style.left = Math.max(8, left) + "px"; pop.style.top = top + "px";
  }
  function hide() { if (pinned) return; pop.hidden = true; }

  groupsEl.addEventListener("mouseover", e => { const c = e.target.closest(".chip"); if (c && !pinned) show(c); });
  groupsEl.addEventListener("mouseout", e => { const c = e.target.closest(".chip"); if (c && !pinned && !pop.contains(e.relatedTarget)) hide(); });
  groupsEl.addEventListener("focusin", e => { const c = e.target.closest(".chip"); if (c && !pinned) show(c); });
  groupsEl.addEventListener("click", e => {
    const c = e.target.closest(".chip"); if (!c) return;
    if (pinned === c) { pinned.classList.remove("pinned"); pinned = null; hide(); return; }
    if (pinned) pinned.classList.remove("pinned");
    pinned = c; c.classList.add("pinned"); show(c);
  });
  document.addEventListener("click", e => {
    if (pinned && !e.target.closest(".chip") && !pop.contains(e.target)) { pinned.classList.remove("pinned"); pinned = null; hide(); }
  });
  document.addEventListener("keydown", e => { if (e.key === "Escape") { if (pinned) pinned.classList.remove("pinned"); pinned = null; hide(); } });
  pop.addEventListener("mouseleave", () => { if (!pinned) hide(); });

  q.addEventListener("input", filter);
  ctxonly.addEventListener("change", filter);
  flagsonly.addEventListener("change", filter);
  newonly.addEventListener("change", filter);
  profileSel.addEventListener("change", () => { history.replaceState(null, "", "?profile=" + profileSel.value); render(); });
  render();
  // Deep link: keys.html?cmd=mafcmd-pow pins that command's popover on load.
  const want = new URLSearchParams(location.search).get("cmd");
  if (want) {
    const chip = Array.from(groupsEl.querySelectorAll(".chip")).find(c => profile.groups[+c.dataset.g].items[+c.dataset.i].cmd === want);
    if (chip) { chip.scrollIntoView({ block: "center" }); pinned = chip; chip.classList.add("pinned"); show(chip); }
  }
})();
