// stacky: a calc stack buffer as data.
//
// A stack is a plain object, never mutated:
//
//   { entries:   ['x + 1', '(x + 1)^2 = 9'],  // entries[0] is level 1, the top of the stack
//     point:     HOME | { level: 1, col: 7 },  // col counts from the start of the entry text
//     highlight: null | { level: 1, from: 0, to: 9 },  // a range of an entry's text, `to` excluded
//     fresh:     null | 1,                     // a level whose entry just changed
//     result:    null | 'x^2 + 2 x + 1 = 9'    // an answer shown under the buffer, after "=>"
//                | { text: 'x^2 + 2 x + 1 = 9', changed: { from: 0, to: 13 } } }  // with the part to set off
//
// lines() lays the stack out the way calc does: one numbered line per entry,
// highest level first, then the home line, an indented dot; a result, which
// calc has no such line for, goes last. text() gives the buffer as a string
// and html() as markup; render() puts it in an element.

export const HOME = Object.freeze({ home: true })
export const INDENT = '    '  // width of a level prefix ("1:  "), and the home line's indent
export const DOT = '.'
export const RESULT = '=>  '  // the result line's prefix, as wide as a level's

export function stack(entries = [], { point = HOME, highlight = null, fresh = null, result = null } = {}) {
  return { entries: [...entries], point, highlight, fresh, result }
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
export const setResult = (s, result) => ({ ...s, result })

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

// The header line calc puts above the buffer: the banner centered between
// runs of dashes, for a header `width` columns wide. Built the way calc does
// it: a shorter title when the long one does not fit, the same fill on both
// sides, and a space separating each fill from the title.
export const BANNER = 'Emacs Calculator Mode'
export const BANNER_SHORT = 'Emacs Calc'
export function banner(width, long = BANNER, short = BANNER_SHORT, fudge = -3) {
  const title = width > long.length + fudge ? long : short
  const size = Math.max(Math.floor((width - title.length) / 2), 0)
  const fill = '-'.repeat(size)
  const pre = fill.replace(/.$/, ' '), post = fill.replace(/^./, ' ')
  return pre + title + post
}

// Buffer geometry. Row 0 is the highest level; the home line is the last row.
export const rowOf = (s, point) => isHome(point) ? depth(s) : depth(s) - point.level
export const colOf = point => INDENT.length + (isHome(point) ? 0 : point.col)
export function pointAt(s, row, col) {
  if (row >= depth(s)) return HOME
  const level = depth(s) - row
  const len = entry(s, level).length
  return { level, col: Math.max(0, Math.min(len, col - INDENT.length)) }
}

// Display options: whether to show the cursor and whether it blinks, and
// whether to show the highlight, the home line, and (in a pane) the header.
export const SHOW = Object.freeze({ cursor: true, blink: false, highlight: true, home: true, header: true })

export function lines(s, show = SHOW) {
  const out = []
  for (let level = depth(s); level >= 1; level--) {
    const text = entry(s, level)
    const cursor = show.cursor && !isHome(s.point) && s.point.level === level ? s.point.col : null
    const mark = show.highlight && s.highlight && s.highlight.level === level ? { from: s.highlight.from, to: s.highlight.to } : null
    out.push({ level, prefix: prefix(level), text, cursor, blink: show.blink, mark, fresh: s.fresh === level })
  }
  if (show.home) out.push({ home: true, prefix: INDENT, text: DOT, cursor: show.cursor && isHome(s.point) ? 0 : null, blink: show.blink, mark: null, fresh: false })
  if (s.result != null) {
    const { text, changed = null } = typeof s.result === 'string' ? { text: s.result } : s.result
    out.push({ result: true, prefix: RESULT, text, cursor: null, mark: null, changed, fresh: false })
  }
  return out
}

export const text = s => lines(s).map(l => l.prefix + l.text).join('\n') + '\n'

const escape = t => t.replace(/[&<>"]/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]))

export function lineHtml(l) {
  let out = `<span class="prefix">${escape(l.prefix)}</span>`
  const cursorTag = l.blink ? 'cursor' : 'cursor steady'
  // The mark and the changed span each wrap a run of characters; the mark
  // opens first and closes last, so one must contain the other if both fall
  // on a line.
  let inMark = false, inChanged = false
  const chars = [...l.text]
  chars.forEach((c, i) => {
    const marked = l.mark && i >= l.mark.from && i < l.mark.to
    const changed = l.changed && i >= l.changed.from && i < l.changed.to
    if (!changed && inChanged) { out += '</span>'; inChanged = false }
    if (!marked && inMark) { out += '</mark>'; inMark = false }
    if (marked && !inMark) { out += '<mark>'; inMark = true }
    if (changed && !inChanged) { out += '<span class="changed">'; inChanged = true }
    out += l.cursor === i ? `<span class="${cursorTag}">${escape(c)}</span>` : escape(c)
  })
  if (inChanged) out += '</span>'
  if (inMark) out += '</mark>'
  if (l.cursor !== null && l.cursor >= chars.length) out += `<span class="${cursorTag}"> </span>`
  const cls = ['line', l.home ? 'home' : l.result ? 'result' : 'entry', l.fresh ? 'fresh' : ''].filter(Boolean).join(' ')
  return `<span class="${cls}">${out}</span>`
}

export const html = (s, show = SHOW) => lines(s, show).map(lineHtml).join('\n') + '\n'

export function render(el, s, show = SHOW) { el.innerHTML = html(s, show) }

// Fill a header element with the banner for as many columns as fit in it.
export function fitBanner(header) {
  const probe = document.createElement('span')
  probe.textContent = 'x'.repeat(20)
  header.textContent = ''
  header.appendChild(probe)
  const cell = probe.getBoundingClientRect().width / 20
  const style = getComputedStyle(header)
  const inner = header.clientWidth - parseFloat(style.paddingLeft) - parseFloat(style.paddingRight)
  header.textContent = banner(cell > 0 ? Math.floor(inner / cell) : 40)
}

// Turn an element into a calc buffer pane: the header line, if shown, above
// the buffer text. Returns a function that redraws it from a stack.
export function pane(el, s, show = SHOW) {
  el.classList.add('calcbuf')
  if (show.header) {
    const header = document.createElement('div'); header.className = 'header'
    el.append(header)
    fitBanner(header)
    if (typeof ResizeObserver !== 'undefined') new ResizeObserver(() => fitBanner(header)).observe(el)
  }
  const buffer = document.createElement('pre'); buffer.className = 'buffer'
  el.append(buffer)
  const draw = s => render(buffer, s, show)
  if (s) draw(s)
  return draw
}
