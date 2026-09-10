// stacky-diff: a stack before and after a command.
//
// The data is a plain object:
//
//   { before: <stacky stack>, after: <stacky stack>, keys: 'a x', command: 'mafcmd-expand',
//     caption: '<b>a x</b> expands only that side', reveal: false, result: false,
//     show: { before: { cursor: true, blink: false, highlight: true, home: true, header: true, change: false },
//             after: { cursor: false, blink: false, highlight: false, home: true, header: true, change: true } } }
//
// Two panes side by side, or with `result` one pane: the stack before, and on
// a last line after "=>" the entry the command produced (the home dot and
// the highlight hidden unless asked for). The line above is `caption`, any HTML; without one it is
// the keys and the command's name. `show` says whether each pane draws the
// cursor and whether it blinks, the highlight, the home line and the header
// line, and whether it
// outlines the part of the stack that differs between the two (`change`);
// the defaults above apply to whatever it leaves out. With `reveal`, the
// after pane (or the result line) starts empty and the caption is a button
// that shows it; clicking again empties it.
//
// fromScene() derives the stacks, keys and command from a showy scene:
// `before` is the stack as it stands when the scene's first keys step
// begins, `after` the stack at the end, and the keys and command are that
// step's. mountAll() mounts every element with data-diff="name", the name of
// a scene: its content, if any, is the caption, data-reveal and data-result
// set those flags.

import * as stacky from './stacky.js'
import { walk } from './showy.js'

export const SHOW = Object.freeze({
  before: Object.freeze({ cursor: true, blink: false, highlight: true, home: true, header: true, change: false }),
  after: Object.freeze({ cursor: false, blink: false, highlight: false, home: true, header: true, change: true }),
})

export const showOf = (ab, side) => ({ ...SHOW[side], ...(ab.result && side === 'before' ? { home: false, highlight: false } : {}), ...(ab.show?.[side] ?? {}) })

export function fromScene(scene, { caption, show = {}, reveal = false, result = false } = {}) {
  const steps = walk(scene)
  const i = steps.findIndex(({ step }) => 'keys' in step)
  if (i < 0) throw new Error('stacky-diff: the scene has no keys step')
  const before = (i > 0 ? steps[i - 1] : { state: { stack: stacky.stack() } }).state.stack
  const after = steps[steps.length - 1].state.stack
  const { keys, command = '' } = steps[i].step
  return { before, after, keys, command, caption, show, reveal, result }
}

// The part of `to` that differs from `from`, as a highlight on `to`: the
// changed span of the lowest level whose entry differs, or the whole top
// entry when the stacks differ in depth. Null when nothing changed.
export function change(from, to) {
  const n = Math.min(stacky.depth(from), stacky.depth(to))
  for (let level = 1; level <= n; level++) {
    const a = stacky.entry(from, level), b = stacky.entry(to, level)
    if (a === b) continue
    let pre = 0
    while (pre < a.length && pre < b.length && a[pre] === b[pre]) pre++
    let suf = 0
    while (suf < a.length - pre && suf < b.length - pre && a[a.length - 1 - suf] === b[b.length - 1 - suf]) suf++
    return { level, from: pre, to: b.length - suf }
  }
  if (stacky.depth(to) > 0 && stacky.depth(from) !== stacky.depth(to)) return { level: 1, from: 0, to: stacky.entry(to, 1).length }
  return null
}

// The entry the command produced: the one that changed, else the top.
export function result(ab) {
  const c = change(ab.before, ab.after)
  return c ? stacky.entry(ab.after, c.level) : stacky.entry(ab.after, 1) ?? ''
}

// A side's stack and display options as drawn: with `change`, the outline is
// the changed part rather than the stack's own highlight.
function shown(ab, side) {
  const show = showOf(ab, side)
  const other = side === 'before' ? 'after' : 'before'
  const stack = show.change ? stacky.setHighlight(ab[side], change(ab[other], ab[side])) : ab[side]
  return { stack, show: show.change ? { ...show, highlight: true } : show }
}

const escape = t => t.replace(/[&<>"]/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]))

// The line above the pair: the caption as given, else the keys and the
// command's name.
export function captionHtml({ caption, keys = '', command }) {
  if (caption) return caption
  const kbds = keys.split(' ').filter(Boolean).map(k => `<kbd>${escape(k)}</kbd>`).join(' ')
  return `<span class="keys">${kbds}</span>` + (command ? ` <span class="command">(${escape(command)})</span>` : '')
}

export function mount(el, ab) {
  el.classList.add('stacky-diff')
  el.classList.toggle('result', !!ab.result)
  el.innerHTML = ''
  el.style.setProperty('--rows', Math.max(stacky.depth(ab.before), stacky.depth(ab.after)) + 1)
  const caption = document.createElement(ab.reveal ? 'button' : 'div'); caption.className = 'caption'; caption.innerHTML = captionHtml(ab)
  if (ab.reveal) caption.type = 'button'
  el.append(caption)
  const b = shown(ab, 'before')
  let show
  if (ab.result) {
    const pane = document.createElement('div'); pane.className = 'side before'
    el.append(pane)
    const draw = stacky.pane(pane, undefined, b.show)
    const full = stacky.setResult(b.stack, result(ab))
    show = on => draw(on ? full : b.stack)
  } else {
    const before = document.createElement('div'); before.className = 'side before'
    const arrow = document.createElement('div'); arrow.className = 'arrow'
    const after = document.createElement('div'); after.className = 'side after'
    el.append(before, arrow, after)
    stacky.pane(before, b.stack, b.show)
    const a = shown(ab, 'after')
    const draw = stacky.pane(after, undefined, a.show)
    show = on => draw(on ? a.stack : stacky.stack())
  }
  let revealed = !ab.reveal
  const set = on => { revealed = on; show(on); caption.setAttribute('aria-pressed', String(on)) }
  set(revealed)
  if (ab.reveal) caption.addEventListener('click', () => set(!revealed))
  return { ab, reveal: () => set(true), hide: () => set(false) }
}

export function mountAll(scenes, root = document) {
  return [...root.querySelectorAll('[data-diff]')].map(el => {
    const caption = el.innerHTML.trim() || undefined
    const reveal = 'reveal' in el.dataset, result = 'result' in el.dataset
    return mount(el, fromScene(scenes[el.dataset.diff], { caption, reveal, result }))
  })
}
