// The standard additions and changes pages: a compiled, deduplicated list grouped by feature area.
(function () {
  const D = window.MAF_COMPILED, mode = document.body.dataset.mode;
  const groups = D[mode];
  const list = document.getElementById("list"), q = document.getElementById("q"), count = document.getElementById("count");
  // A module's section is titled "What it does (maf-name)"; the name becomes a module tag.
  function title(t) {
    const m = /^(.*?)\s*\((maf-[\w-]+|dial|filter-view)\)$/.exec(t);
    return m ? esc(m[1]) + ' <span class="pill area">module ' + esc(m[2]) + "</span>" : esc(t);
  }
  // Sections fall into three bands, vertically separated: core, the command groups, and the modules.
  function band(t) {
    if (/\((maf-[\w-]+|dial|filter-view)\)$/.test(t)) return "Modules";
    if (t === "Core" || t === "Targeting and commit" || t === "Navigation and point") return "Core";
    return "Commands";
  }
  const section = (g, gi) => '<section class="cgroup" data-g="' + gi + '"><h2>' + title(g.group) + "</h2><ul>" +
    g.items.map(it => '<li data-hay="' + esc(it.toLowerCase()) + '">' + fmt(it) + "</li>").join("") + "</ul></section>";
  // New commands with no Calc counterpart, from the bindings data, lead the additions page.
  function newCommands() {
    const B = window.MAF_BINDINGS; if (!B || mode !== "additions") return "";
    const prof = B.profiles.find(p => p.name === B.default_profile);
    const gs = prof.groups.map(g => ({ title: g.title, items: g.items.filter(i => i.new) })).filter(g => g.items.length && !/^Unbound/.test(g.title));
    return '<div class="band"><h2 class="bandtitle">New commands <span class="muted" style="font-size:.8rem;font-weight:400">no counterpart in stock Calc, by group; hover them on the <a href="keys.html">keys</a> page</span></h2><div class="cols">' +
      gs.map((g, gi) => '<section class="cgroup"><h2>' + esc(g.title) + "</h2><ul>" +
        g.items.map(i => '<li data-hay="' + esc((i.cmd + " " + (i.title || "") + " " + g.title).toLowerCase()) + '">' + (i.keys.length ? kbdKeys(i.keys) + " " : "") + esc(i.title ? i.title[0].toUpperCase() + i.title.slice(1) : i.cmd) + "</li>").join("") +
        "</ul></section>").join("") + "</div></div>";
  }
  const bands = {};
  groups.forEach((g, gi) => { (bands[band(g.group)] = bands[band(g.group)] || []).push([g, gi]); });
  list.innerHTML = newCommands() + ["Core", "Commands", "Modules"].filter(b => bands[b]).map(b =>
    '<div class="band"><h2 class="bandtitle">' + b + '</h2><div class="cols">' + bands[b].map(([g, gi]) => section(g, gi)).join("") + "</div></div>").join("");
  const total = list.querySelectorAll("li").length;
  function filter() {
    const needle = q.value.trim().toLowerCase(); let n = 0;
    list.querySelectorAll("li").forEach(li => { const ok = !needle || li.dataset.hay.includes(needle); li.classList.toggle("hidden", !ok); if (ok) n++; });
    list.querySelectorAll(".cgroup").forEach(s => { s.style.display = s.querySelector("li:not(.hidden)") ? "" : "none"; });
    list.querySelectorAll(".band").forEach(b => { b.style.display = b.querySelector("li:not(.hidden)") ? "" : "none"; });
    count.textContent = n + " of " + total;
  }
  q.addEventListener("input", filter); filter();
})();
