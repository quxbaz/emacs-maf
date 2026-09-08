// stacky: a calc stack buffer as data.
//
// A stack is a plain object, never mutated:
//
//   { entries:   ['x + 1', '(x + 1)^2 = 9'],  // entries[0] is level 1, the top of the stack
//     point:     HOME | { level: 1, col: 7 },  // col counts from the start of the entry text
//     highlight: null | { level: 1, from: 0, to: 9 },  // a range of an entry's text, `to` excluded
//     fresh:     null | 1 }                    // a level whose entry just changed
//
// lines() lays the stack out the way calc does: one numbered line per entry,
// highest level first, then the home line, an indented dot. text() gives the
// buffer as a string and html() as markup; render() puts it in an element.

export const HOME = Object.freeze({ home: true })
export const INDENT = '    '  // width of a level prefix ("1:  "), and the home line's indent
export const DOT = '.'

export function stack(entries = [], { point = HOME, highlight = null, fresh = null } = {}) {
  return { entries: [...entries], point, highlight, fresh }
}

export const depth = s => s.entries.length
export const entry = (s, level) => s.entries[level - 1]
export const isHome = point => point === HOME || point.home === true

export function setEntry(s, level, text) {
  const entries = [...s.entries]
  entries[level - 1] = text
  return { ...s, entries }
}
export const push = (s, text) => ({ ...s, entries: [text, ...s.entries] })
export const pop = (s, n = 1) => ({ ...s, entries: s.entries.slice(n) })
export const setPoint = (s, point) => ({ ...s, point })
export const setHighlight = (s, highlight) => ({ ...s, highlight })
export const setFresh = (s, fresh) => ({ ...s, fresh })

// Insert text at point; point moves past it. On the home line there is
// nothing to type into, so the stack is returned unchanged.
export function insert(s, text) {
  if (isHome(s.point)) return s
  const { level, col } = s.point
  const old = entry(s, level)
  const next = old.slice(0, col) + text + old.slice(col)
  return { ...setEntry(s, level, next), point: { level, col: col + text.length } }
}

// "1:  ", "10: "
export const prefix = level => (level + ':').padEnd(INDENT.length)

// Buffer geometry. Row 0 is the highest level; the home line is the last row.
export const rowOf = (s, point) => isHome(point) ? depth(s) : depth(s) - point.level
export const colOf = point => INDENT.length + (isHome(point) ? 0 : point.col)
export function pointAt(s, row, col) {
  if (row >= depth(s)) return HOME
  const level = depth(s) - row
  const len = entry(s, level).length
  return { level, col: Math.max(0, Math.min(len, col - INDENT.length)) }
}

export function lines(s) {
  const out = []
  for (let level = depth(s); level >= 1; level--) {
    const text = entry(s, level)
    const cursor = !isHome(s.point) && s.point.level === level ? s.point.col : null
    const mark = s.highlight && s.highlight.level === level ? { from: s.highlight.from, to: s.highlight.to } : null
    out.push({ level, prefix: prefix(level), text, cursor, mark, fresh: s.fresh === level })
  }
  out.push({ home: true, prefix: INDENT, text: DOT, cursor: isHome(s.point) ? 0 : null, mark: null, fresh: false })
  return out
}

export const text = s => lines(s).map(l => l.prefix + l.text).join('\n') + '\n'

const escape = t => t.replace(/[&<>"]/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]))

export function lineHtml(l) {
  let out = escape(l.prefix)
  let inMark = false
  const chars = [...l.text]
  chars.forEach((c, i) => {
    const marked = l.mark && i >= l.mark.from && i < l.mark.to
    if (marked && !inMark) { out += '<mark>'; inMark = true }
    if (!marked && inMark) { out += '</mark>'; inMark = false }
    out += l.cursor === i ? `<span class="cursor">${escape(c)}</span>` : escape(c)
  })
  if (inMark) out += '</mark>'
  if (l.cursor !== null && l.cursor >= chars.length) out += '<span class="cursor"> </span>'
  const cls = ['line', l.home ? 'home' : 'entry', l.fresh ? 'fresh' : ''].filter(Boolean).join(' ')
  return `<span class="${cls}">${out}</span>`
}

export const html = s => lines(s).map(lineHtml).join('\n') + '\n'

export function render(el, s) { el.innerHTML = html(s) }
