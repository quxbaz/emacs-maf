// Shared helpers: nav, escaping, footer.
(function () {
  const pages = [["index.html", "Overview"], ["quick.html", "Quick intro"], ["basics.html", "Basics"], ["modules.html", "Modules"], ["keys.html", "Keys"], ["additions.html", "Additions"], ["changes.html", "Changes"], ["install.html", "Install"]];
  const here = (location.pathname.split("/").pop() || "index.html").replace("-verbose", "");
  const nav = document.getElementById("nav");
  if (nav) {
    const v = (window.MAF_BINDINGS && window.MAF_BINDINGS.version) || "";
    nav.innerHTML = '<div class="wrap"><a class="brand" href="index.html">maf' + (v ? '<span>v' + v + '</span>' : '') + '</a>' +
      pages.map(([f, t]) => '<a class="link' + (f === here ? " active" : "") + '" href="' + f + '">' + t + '</a>').join("") +
      '<span class="spacer"></span><a class="link" href="https://github.com/quxbaz/emacs-maf">GitHub</a></div>';
  }
  const foot = document.getElementById("foot");
  if (foot) {
    const gen = (window.MAF_COMMITS && window.MAF_COMMITS.generated) || (window.MAF_BINDINGS && window.MAF_BINDINGS.generated) || "";
    foot.innerHTML = 'maf is an alternative UX over Emacs Calc by David Yeung. ' +
      (gen ? 'Data generated from the repository on ' + gen + '. ' : '') +
      'Source and issues on <a href="https://github.com/quxbaz/emacs-maf">GitHub</a>.';
  }
})();
function esc(s) { return String(s == null ? "" : s).replace(/[&<>"]/g, c => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" }[c])); }
function kbdKeys(keys) { return (keys || []).map(k => "<kbd>" + esc(k) + "</kbd>").join(" "); }
