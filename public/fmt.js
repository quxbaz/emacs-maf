// Inline formatting shared by the history pages: keys become <kbd>, symbols and code become <code>.
const KEYTOK = /^(?:(?:C-|M-|S-|H-|C-M-|C-S-|M-S-)*(?:<[a-z0-9-]+>|RET|SPC|TAB|DEL|ESC|[^\s]))$/;
function isKeys(s) { const t = s.trim().split(/\s+/); return t.length <= 4 && t.every(x => KEYTOK.test(x)); }
function fmtSpan(k) { return isKeys(k) ? '<kbd class="k">' + k + "</kbd>" : "<code>" + k + "</code>"; }
// Backtick spans are explicit. Outside them, maf-, mafcmd- and calc- symbols are code.
function fmt(s) {
  s = esc(s);
  s = s.replace(/``\s?(.+?)\s?``/g, (m, k) => fmtSpan(k));
  const parts = s.split(/(`[^`]+`)/);
  return parts.map(p => p.startsWith("`") && p.endsWith("`") && p.length > 2 ? fmtSpan(p.slice(1, -1))
    : p.replace(/(?<![\w-])((?:maf|mafcmd|calc|calcFunc|math)-[a-z0-9-]*[a-z0-9])(?![\w-])/g, "<code>$1</code>")).join("");
}
