// The verbose additions and changes pages: every commit, grouped by subject area rather than date.
(function () {
  const D = window.MAF_COMMITS, B = window.MAF_BINDINGS, mode = document.body.dataset.mode;
  const $ = s => document.querySelector(s);
  const list = $("#list"), q = $("#q"), count = $("#count"), statsEl = $("#stats"), typesEl = $("#types");
  const GH = "https://github.com/quxbaz/emacs-maf/commit/";
  const TYPES = ["addition", "change", "fix", "refactor", "docs", "tests", "revert"];
  const isAddition = c => c.type === "addition" || c.commands_added.length || c.modules_added.length || c.tests_added.length;
  const cutoff = document.getElementById("cutoff");
  if (cutoff) cutoff.innerHTML = "<code>" + esc(D.summary.head) + "</code> on " + esc(D.summary.last) + ", when this data was generated";
  const commits = D.commits.filter(c => c.type !== "note" && c.type !== "merge").filter(c => mode === "additions" ? isAddition(c) : true).reverse();

  // A command's group in the keys taxonomy, for filing a commit under the subject it touched.
  const cmdGroup = {};
  B.profiles[0].groups.forEach(g => g.items.forEach(it => { cmdGroup[it.cmd] = g.title; }));
  const MODULE = /^(?:modules\/maf-([\w-]+)\.el|pkg\/([\w-]+)\/)/;
  function subject(c) {
    const files = c.files.added.concat(c.files.modified, c.files.deleted);
    for (const cmd of c.commands_added) if (cmdGroup[cmd]) return cmdGroup[cmd];
    const mods = new Set(); let cmds = false, bind = false, core = false;
    for (const p of files) {
      const m = MODULE.exec(p);
      if (m) { mods.add(m[1] ? "maf-" + m[1] : m[2]); continue; }
      if (p === "src/bindings.el" || p === "core/maf-bindings.el") { bind = true; continue; }
      if (p.startsWith("src/")) { cmds = true; continue; }
      if (p.startsWith("core/") || p === "maf.el") core = true;
    }
    if (mods.size === 1) return "Module " + [...mods][0];
    if (mods.size > 1) return "Modules";
    // A subject naming a command files under that command's group.
    const m = /(mafcmd-[a-z0-9-]+|maf-[a-z0-9-]+)/.exec(c.subject);
    if (m && cmdGroup[m[1]]) return cmdGroup[m[1]];
    if (bind) return "Bindings and profiles";
    if (cmds) return "Commands";
    if (core) return "Core";
    return "Other";
  }
  const ORDER = B.profiles[0].groups.map(g => g.title).concat(["Commands", "Bindings and profiles", "Core", "Modules"]);
  const byGroup = {};
  commits.forEach(c => { const g = subject(c); (byGroup[g] = byGroup[g] || []).push(c); });
  const groups = Object.keys(byGroup).sort((a, b) => {
    const ia = ORDER.indexOf(a), ib = ORDER.indexOf(b);
    const ka = ia < 0 ? (a.startsWith("Module ") ? 1000 : 2000) : ia, kb = ib < 0 ? (b.startsWith("Module ") ? 1000 : 2000) : ib;
    return ka - kb || a.localeCompare(b);
  });

  const nCmds = commits.reduce((n, c) => n + c.commands_added.length, 0);
  const nMods = commits.reduce((n, c) => n + c.modules_added.length, 0);
  const stats = mode === "additions"
    ? [[commits.length, "commits adding something"], [nCmds, "commands added"], [nMods, "modules added"], [groups.length, "subjects"]]
    : [[commits.length, "commits, notes and merges aside"], [D.summary.total, "commits in all"], [groups.length, "subjects"], [D.summary.first + " to " + D.summary.last, "span"]];
  statsEl.innerHTML = stats.map(([n, l]) => '<div class="stat"><b>' + esc(n) + "</b><span>" + esc(l) + "</span></div>").join("");

  const enabled = new Set(TYPES);
  if (typesEl) {
    const counts = {}; commits.forEach(c => { counts[c.type] = (counts[c.type] || 0) + 1; });
    typesEl.innerHTML = TYPES.filter(t => counts[t]).map(t => '<label><input type="checkbox" data-t="' + t + '" checked> <span class="pill ' + t + '">' + t + "</span> " + counts[t] + "</label>").join("");
    typesEl.addEventListener("change", e => { const t = e.target.dataset.t; if (!t) return; e.target.checked ? enabled.add(t) : enabled.delete(t); filter(); });
  }
  function chips(c) {
    const out = [];
    const shown = c.commands_added.slice(0, 12), more = c.commands_added.length - shown.length;
    shown.forEach(x => out.push("<code>" + esc(x) + "</code>"));
    if (more > 0) out.push('<details class="more"><summary>+' + more + " more</summary>" + c.commands_added.slice(12).map(x => "<code>" + esc(x) + "</code>").join(" ") + "</details>");
    c.modules_added.forEach(x => out.push('<code title="new module">' + esc(x.replace(/^.*\//, "").replace(/\.el$/, "")) + "</code>"));
    if (c.tests_added.length) out.push('<span class="pill tests">' + c.tests_added.length + " test" + (c.tests_added.length > 1 ? "s" : "") + "</span>");
    return out.length ? '<span class="added">' + out.join(" ") + "</span>" : "";
  }
  function row(c) {
    const hay = [c.subject, c.body, c.date, c.short, c.commands_added.join(" "), c.modules_added.join(" "), c.areas.join(" "), c.type].join(" ").toLowerCase();
    return '<div class="commit" data-t="' + c.type + '" data-hay="' + esc(hay) + '"><div class="date" title="' + c.short + '">' + c.date + "</div><div>" +
      '<div class="subj"><a href="' + GH + c.hash + '" title="open the commit on GitHub">' + fmt(c.subject) + "</a>" +
      (c.tag ? ' <span class="pill tag">' + esc(c.tag) + "</span>" : "") + "</div>" +
      '<div class="meta"><span class="pill ' + c.type + '">' + c.type + "</span>" + chips(c) +
      (c.body ? '<details><summary>Why</summary><div class="body">' + fmt(c.body) + "</div></details>" : "") + "</div></div></div>";
  }
  list.innerHTML = groups.map(g => '<section class="month" data-g="' + esc(g) + '"><h2>' + esc(g) + '<span class="count">' + byGroup[g].length + "</span></h2>" + byGroup[g].map(row).join("") + "</section>").join("");

  function filter() {
    const needle = q.value.trim().toLowerCase(); let n = 0;
    list.querySelectorAll(".commit").forEach(el => { const ok = (!needle || el.dataset.hay.includes(needle)) && enabled.has(el.dataset.t); el.classList.toggle("hidden", !ok); if (ok) n++; });
    list.querySelectorAll(".month").forEach(m => { const k = m.querySelectorAll(".commit:not(.hidden)").length; m.style.display = k ? "" : "none"; m.querySelector(".count").textContent = k; });
    count.textContent = n + " of " + commits.length + " shown";
  }
  q.addEventListener("input", filter); filter();
})();
