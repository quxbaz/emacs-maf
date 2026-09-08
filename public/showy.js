// showy: an animated, step-by-step presentation of maf at work.
//
// A scene is plain data, a list of steps:
//
//   { stack: ['(x + 1)^2 = 9'] }                  set the stack; point goes home unless `point` is given
//   { point: { level: 1, col: 7 }, highlight: r }  walk the cursor there one cell at a time, then highlight r
//   { keys: 'a x', command: 'mafcmd-expand' }      echo the keys one by one, then name the command and hold
//   { entry: { level: 1, text }, point, highlight } replace an entry, the result of the command; it flashes
//   { push: 'x + 1' } / { pop: 1 }                  change the stack
//   { insert: 'x^2' }                               type text at point, one character at a time
//   { pause: 600 }                                  wait
//
// timeline() turns a scene into a list of { at, action } pairs, absolute
// milliseconds and redux actions, threading the state through the reducer so
// each step can see where the previous one left things. play() dispatches
// them on schedule to a store; mount() does the whole thing in an element.

import { createStore } from './vendor/redux/redux.mjs'
import * as stacky from './stacky.js'

// Actions

export const STACK = 'showy/stack'          // { stack }
export const ENTRY = 'showy/entry'          // { level, text }
export const PUSH = 'showy/push'            // { text }
export const POP = 'showy/pop'              // { n }
export const POINT = 'showy/point'          // { point }
export const HIGHLIGHT = 'showy/highlight'  // { highlight }
export const FRESH = 'showy/fresh'          // { level }
export const INSERT = 'showy/insert'        // { text }
export const ECHO = 'showy/echo'            // { keys: [...], command }
export const RESET = 'showy/reset'          // { state }: replace the whole state

export const initialState = { stack: stacky.stack(), echo: { keys: [], command: '' } }

export function reducer(state = initialState, action) {
  const withStack = stack => ({ ...state, stack })
  switch (action.type) {
    case STACK: return withStack(action.stack)
    case ENTRY: return withStack(stacky.setEntry(state.stack, action.level, action.text))
    case PUSH: return withStack(stacky.push(state.stack, action.text))
    case POP: return withStack(stacky.pop(state.stack, action.n ?? 1))
    case POINT: return withStack(stacky.setPoint(state.stack, action.point))
    case HIGHLIGHT: return withStack(stacky.setHighlight(state.stack, action.highlight))
    case FRESH: return withStack(stacky.setFresh(state.stack, action.level))
    case INSERT: return withStack(stacky.insert(state.stack, action.text))
    case ECHO: return { ...state, echo: { keys: action.keys ?? [], command: action.command ?? '' } }
    case RESET: return action.state
    default: return state
  }
}

export const createShowyStore = (state = initialState) => createStore(reducer, state)

// Timing, in milliseconds. `cursor` is one cell of cursor travel; `key` one
// keypress in the echo line; `command` how long the command's name stays up
// before its result appears; `char` one typed character; `fresh` how long a
// changed entry stays lit.
export const TIMING = { cursor: 70, key: 280, command: 900, char: 90, fresh: 900 }

// Steps to actions. Each returns [{ delay, action }], delay being the wait
// before that action; a null action is a pure wait.

const wait = delay => ({ delay, action: null })
const now = action => ({ delay: 0, action })

function cursorPath(stack, target) {
  const row0 = stacky.rowOf(stack, stack.point), col0 = stacky.colOf(stack.point)
  const row1 = stacky.rowOf(stack, target), col1 = stacky.colOf(target)
  const path = []
  let row = row0
  while (row !== row1) { row += Math.sign(row1 - row); path.push(stacky.pointAt(stack, row, col0)) }
  let col = stacky.colOf(path.length ? path[path.length - 1] : stack.point)
  while (col !== col1) { col += Math.sign(col1 - col); path.push(stacky.pointAt(stack, row, col)) }
  return path
}

export function expandStep(step, state, timing = TIMING) {
  const acts = []
  if ('pause' in step) acts.push(wait(step.pause))
  if ('stack' in step) {
    acts.push(now({ type: STACK, stack: stacky.stack(step.stack, { point: step.point ?? stacky.HOME, highlight: step.highlight ?? null }) }))
    acts.push(now({ type: ECHO, keys: [], command: '' }))
    return acts
  }
  if ('push' in step) acts.push(now({ type: PUSH, text: step.push }))
  if ('pop' in step) acts.push(now({ type: POP, n: step.pop }))
  if ('entry' in step) {
    acts.push(now({ type: ENTRY, level: step.entry.level, text: step.entry.text }))
    acts.push(now({ type: HIGHLIGHT, highlight: step.highlight ?? null }))
    if (step.point) acts.push(now({ type: POINT, point: step.point }))
    acts.push(now({ type: FRESH, level: step.entry.level }))
    acts.push({ delay: timing.fresh, action: { type: FRESH, level: null } })
  } else if ('point' in step) {
    for (const p of cursorPath(state.stack, step.point)) acts.push({ delay: timing.cursor, action: { type: POINT, point: p } })
    if ('highlight' in step) acts.push(now({ type: HIGHLIGHT, highlight: step.highlight }))
  }
  if ('keys' in step) {
    const keys = step.keys.split(' ')
    keys.forEach((_, i) => acts.push({ delay: timing.key, action: { type: ECHO, keys: keys.slice(0, i + 1), command: '' } }))
    if (step.command) {
      acts.push({ delay: timing.key, action: { type: ECHO, keys, command: step.command } })
      acts.push(wait(timing.command))
    }
  }
  if ('insert' in step) {
    for (const c of step.insert) acts.push({ delay: timing.char, action: { type: INSERT, text: c } })
  }
  return acts
}

export function timeline(scene, state = initialState, timing = TIMING) {
  const out = []
  let at = 0
  for (const step of scene) {
    for (const { delay, action } of expandStep(step, state, timing)) {
      at += delay
      if (action) { out.push({ at, action }); state = reducer(state, action) }
    }
  }
  return out
}

// The state after each step of a scene: [{ step, state }].
export function walk(scene, state = initialState, timing = TIMING) {
  return scene.map(step => {
    for (const { action } of expandStep(step, state, timing)) if (action) state = reducer(state, action)
    return { step, state }
  })
}

// Every state the timeline passes through, in order, starting from `state`.
export function states(tl, state = initialState) {
  return tl.reduce((acc, { action }) => (acc.push(reducer(acc[acc.length - 1], action)), acc), [state])
}

export function play(store, tl, { onDone } = {}) {
  let i = 0, timer = null, stopped = false
  const start = performance.now()
  const next = () => {
    if (stopped) return
    if (i >= tl.length) { onDone?.(); return }
    const { at, action } = tl[i++]
    timer = setTimeout(() => { store.dispatch(action); next() }, Math.max(0, at - (performance.now() - start)))
  }
  next()
  return { stop() { stopped = true; clearTimeout(timer) } }
}

// Rendering

const escape = t => t.replace(/[&<>"]/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]))

export function echoHtml(echo) {
  const keys = echo.keys.map(k => `<kbd>${escape(k)}</kbd>`).join(' ')
  const command = echo.command ? `<span class="command">${escape(echo.command)}</span>` : ''
  return keys + (keys && command ? ' ' : '') + command
}

export function mount(el, scene, { timing = TIMING, autoplay = true } = {}) {
  const store = createShowyStore()
  const tl = timeline(scene, initialState, timing)
  const rows = Math.max(...states(tl).map(s => stacky.depth(s.stack))) + 1
  el.classList.add('showy')
  el.style.setProperty('--rows', rows)
  el.innerHTML = ''
  // The opening picture: everything the timeline does at time zero.
  const start = states(tl.filter(({ at }) => at === 0)).pop()
  const controls = document.createElement('div'); controls.className = 'controls'
  const button = document.createElement('button'); button.className = 'replay'; button.type = 'button'; button.hidden = true
  controls.append(button)
  const pane = document.createElement('div')
  el.append(controls, pane)
  const drawStack = stacky.pane(pane)
  const echo = document.createElement('div'); echo.className = 'echo'
  pane.append(echo)
  const draw = () => { const s = store.getState(); drawStack(s.stack); echo.innerHTML = echoHtml(s.echo) }
  store.subscribe(draw)
  draw()
  let player = null
  const label = playing => { button.textContent = playing ? 'reset' : 'replay'; button.hidden = false }
  const run = () => {
    player?.stop()
    label(true)
    player = play(store, tl, { onDone: () => label(false) })
  }
  const reset = () => {
    player?.stop()
    player = null
    store.dispatch({ type: RESET, state: start })
    label(false)
  }
  button.addEventListener('click', () => (player && button.textContent === 'reset' ? reset : run)())
  if (autoplay) run(); else label(false)
  return { store, timeline: tl, replay: run, reset, stop: () => player?.stop() }
}

// Mount every element carrying data-scene from a table of scenes.
export function mountAll(scenes, root = document) {
  return [...root.querySelectorAll('[data-scene]')].map(el => mount(el, scenes[el.dataset.scene]))
}
