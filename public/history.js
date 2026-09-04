// Renders the additions and changes pages from data/commits.js.
(function () {
  const D = window.MAF_COMMITS, mode = document.body.dataset.mode; // "additions" | "changes"
  const $ = s => document.querySelector(s);
  const list = $("#list"), q = $("#q"), count = $("#count"), statsEl = $("#stats"), barsEl = $("#bars"), typesEl = $("#types");
  const GH = "https://github.com/quxbaz/emacs-maf/commit/";
  const TYPES = ["addition", "change", "fix", "refactor", "docs", "tests", "revert"];
  const isAddition = c => c.type === "addition" || c.commands_added.length || c.modules_added.length;
  const commits = D.commits.filter(c => c.type !== "note" && c.type !== "merge").filter(c => mode === "additions" ? isAddition(c) : true).reverse();

  // Stats
  const nCmds = commits.reduce((n, c) => n + c.commands_added.length, 0);
  const nMods = commits.reduce((n, c) => n + c.modules_added.length, 0);
  const nTests = commits.reduce((n, c) => n + c.tests_added.length, 0);
  const stats = mode === "additions"
    ? [[commits.length, "commits adding something"], [nCmds, "commands added"], [nMods, "modules added"], [nTests, "step tests added"]]
    : [[commits.length, "commits, notes and merges aside"], [D.summary.total, "commits in all"], [D.summary.first + " → " + D.summary.last, "span"]];
  statsEl.innerHTML = stats.map(([n, l]) => '<div class="stat"><b>' + esc(n) + "</b><span>" + esc(l) + "</span></div>").join("");

  // Month bars
  const months = {};
  commits.forEach(c => { const m = c.date.slice(0, 7); months[m] = (months[m] || 0) + 1; });
  const keys = Object.keys(months).sort(), max = Math.max(...Object.values(months), 1);
  barsEl.innerHTML = keys.map(m => '<div class="bar" title="' + m + ": " + months[m] + '"><i style="height:' + Math.round(100 * months[m] / max) + '%"></i><span>' + m.slice(2) + "</span></div>").join("");

  // Type filters (changes page only)
  const enabled = new Set(TYPES);
  if (typesEl) {
    const counts = {}; commits.forEach(c => { counts[c.type] = (counts[c.type] || 0) + 1; });
    typesEl.innerHTML = TYPES.filter(t => counts[t]).map(t => '<label><input type="checkbox" data-t="' + t + '" checked> <span class="pill ' + t + '">' + t + "</span> " + counts[t] + "</label>").join("");
    typesEl.addEventListener("change", e => { const t = e.target.dataset.t; if (!t) return; e.target.checked ? enabled.add(t) : enabled.delete(t); filter(); });
  }

  function chips(c) {
    const out = [];
    c.commands_added.forEach(x => out.push("<code>" + esc(x) + "</code>"));
    c.modules_added.forEach(x => out.push('<code title="new module">' + esc(x.replace(/^.*\//, "").replace(/\.el$/, "")) + "</code>"));
    if (c.tests_added.length) out.push('<span class="pill tests">' + c.tests_added.length + " test" + (c.tests_added.length > 1 ? "s" : "") + "</span>");
    return out.length ? '<div class="meta added">' + out.join(" ") + "</div>" : "";
  }
  function row(c) {
    const hay = [c.subject, c.body, c.date, c.short, c.commands_added.join(" "), c.modules_added.join(" "), c.areas.join(" "), c.type].join(" ").toLowerCase();
    return '<div class="commit" data-t="' + c.type + '" data-hay="' + esc(hay) + '"><div class="date">' + c.date + "</div><div>" +
      '<div class="subj"><a href="' + GH + c.hash + '" title="' + c.short + '">' + esc(c.subject) + "</a>" +
      (c.tag ? ' <span class="pill tag">' + esc(c.tag) + "</span>" : "") + "</div>" +
      '<div class="meta"><span class="pill ' + c.type + '">' + c.type + "</span>" + c.areas.map(a => '<span class="pill area">' + esc(a) + "</span>").join("") +
      '<span class="muted" style="font-size:.8rem">+' + c.stat.insertions + " −" + c.stat.deletions + "</span></div>" +
      chips(c) +
      (c.body ? '<details><summary>Why</summary><div class="body">' + esc(c.body) + "</div></details>" : "") +
      "</div></div>";
  }
  const byMonth = {};
  commits.forEach(c => { const m = c.date.slice(0, 7); (byMonth[m] = byMonth[m] || []).push(c); });
  list.innerHTML = Object.keys(byMonth).sort().reverse().map(m => {
    const d = new Date(m + "-15"), name = d.toLocaleString("en", { month: "long", year: "numeric" });
    return '<section class="month" data-m="' + m + '"><h2>' + name + '<span class="count">' + byMonth[m].length + "</span></h2>" + byMonth[m].map(row).join("") + "</section>";
  }).join("");

  function filter() {
    const needle = q.value.trim().toLowerCase();
    let n = 0;
    list.querySelectorAll(".commit").forEach(el => {
      const ok = (!needle || el.dataset.hay.includes(needle)) && enabled.has(el.dataset.t);
      el.classList.toggle("hidden", !ok); if (ok) n++;
    });
    list.querySelectorAll(".month").forEach(m => { const k = m.querySelectorAll(".commit:not(.hidden)").length; m.style.display = k ? "" : "none"; m.querySelector(".count").textContent = k; });
    count.textContent = n + " of " + commits.length + " shown";
  }
  q.addEventListener("input", filter);
  filter();
})();
