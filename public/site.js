// Shared navigation, section links, and footer.
(function () {
  const sections = [
    { title: "Get started", pages: [["install.html", "Install"], ["quick.html", "Quick walkthrough"]] },
    { title: "Guide", pages: [["basics.html", "Worked examples"], ["additions.html", "Compared with Calc"], ["additions-verbose.html", "Addition history"]] },
    { title: "Reference", pages: [["keys.html", "Key bindings"], ["modules.html", "Modules"]] },
    { title: "What’s new", pages: [["changes.html", "Feature summary"], ["changes-verbose.html", "Commit history"]] }
  ];
  const here = location.pathname.split("/").pop() || "index.html";
  const section = sections.find(s => s.pages.some(([file]) => file === here));
  const nav = document.getElementById("nav"), main = document.querySelector("main");
  if (main) {
    main.id = "main";
    main.tabIndex = -1;
    const skip = document.createElement("a");
    skip.href = "#main"; skip.className = "skip-link"; skip.textContent = "Skip to content";
    document.body.prepend(skip);
  }
  if (nav) {
    nav.setAttribute("aria-label", "Main navigation");
    nav.innerHTML = '<div class="wrap nav-row"><a class="brand" href="index.html"' + (here === "index.html" ? ' aria-current="page"' : '') + '>maf</a><div class="nav-links">' +
      sections.map(s => '<a class="link' + (s === section ? " active" : "") + '"' + (s === section ? ' aria-current="' + (s.pages[0][0] === here ? "page" : "true") + '"' : '') + ' href="' + s.pages[0][0] + '">' + s.title + '</a>').join("") +
      '<a class="link github" href="https://github.com/quxbaz/emacs-maf">GitHub ↗</a></div></div>';
    if (section) {
      const sub = document.createElement("nav");
      sub.className = "subnav"; sub.setAttribute("aria-label", section.title);
      sub.innerHTML = '<div class="wrap">' + section.pages.map(([file, title]) => '<a href="' + file + '"' + (file === here ? ' aria-current="page"' : '') + '>' + title + '</a>').join("") + '</div>';
      nav.after(sub);
    }
    const measure = () => document.documentElement.style.setProperty("--nav-height", nav.offsetHeight + "px");
    new ResizeObserver(measure).observe(nav);
    measure();
    const toolbar = document.querySelector(".toolbar");
    if (toolbar) new ResizeObserver(() => {
      document.documentElement.style.setProperty("--toolbar-height", toolbar.offsetHeight + "px");
    }).observe(toolbar);
  }
  const foot = document.getElementById("foot");
  if (foot) {
    const version = window.MAF_BINDINGS && window.MAF_BINDINGS.version;
    foot.innerHTML = 'maf' + (version ? ' v' + esc(version) : '') + ' · An alternative UX for Emacs Calc by David Yeung. ' +
      '<a href="https://github.com/quxbaz/emacs-maf">Source and issues</a> · <a href="changes.html">What’s new</a>';
  }

  let content, toc;
  if (main && main.hasAttribute("data-toc")) {
    content = document.createElement("div"); content.className = "page-content";
    while (main.firstChild) content.appendChild(main.firstChild);
    const aside = document.createElement("aside"); aside.className = "page-sidebar";
    aside.innerHTML = '<details class="toc"><summary>On this page</summary><nav aria-label="On this page"></nav></details>';
    toc = aside.querySelector(".toc");
    const desktop = matchMedia("(min-width: 1000px)");
    const resize = () => { toc.open = desktop.matches; };
    desktop.addEventListener("change", resize); resize();
    toc.addEventListener("click", e => { if (e.target.closest("a") && !desktop.matches) toc.open = false; });
    main.classList.add("page-layout"); main.append(aside, content);
  }

  window.refreshContents = function () {
    if (!content) return;
    const headings = [...content.querySelectorAll("h2")];
    headings.forEach(h => {
      if (!h.id) {
        const label = h.cloneNode(true);
        label.querySelectorAll(".count, .pill, .muted").forEach(el => el.remove());
        const base = slug(label.textContent), used = document.getElementById(base);
        let id = base, n = 2;
        if (used) while (document.getElementById(id)) id = base + "-" + n++;
        h.id = id;
      }
      if (!h.querySelector(".heading-link")) {
        const a = document.createElement("a"); a.className = "heading-link"; a.href = "#" + h.id;
        a.setAttribute("aria-label", "Link to " + h.textContent.trim()); a.textContent = "#"; h.append(a);
      }
    });
    toc.querySelector("nav").innerHTML = headings.filter(h => h.getClientRects().length).map(h => {
      const label = h.cloneNode(true);
      label.querySelectorAll(".count, .pill, .muted, .heading-link").forEach(el => el.remove());
      return '<a href="#' + h.id + '">' + esc(label.textContent.trim()) + '</a>';
    }).join("");
    toc.hidden = !toc.querySelector("nav").children.length;
  };
  refreshContents();
  // Dynamic pages finish rendering before DOMContentLoaded.
  document.addEventListener("DOMContentLoaded", () => {
    refreshContents();
    if (location.hash) {
      const target = document.getElementById(decodeURIComponent(location.hash.slice(1)));
      if (target) target.scrollIntoView();
    }
  });
})();
function slug(s) { return s.toLowerCase().trim().replace(/[^a-z0-9]+/g, "-").replace(/^-|-$/g, "") || "section"; }
function esc(s) { return String(s == null ? "" : s).replace(/[&<>"]/g, c => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" }[c])); }
function kbdKeys(keys) { return (keys || []).map(k => "<kbd>" + esc(k) + "</kbd>").join(" "); }
