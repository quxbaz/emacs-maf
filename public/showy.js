// showy: an animated, step-by-step presentation of maf at work.
//
// A scene is plain data, a list of steps:
//
//   { stack: ['(x + 1)^2 = 9'] }                  set the stack; point goes home unless `point` is given
//   { point: { level: 1, col: 7 }, highlight: r }  walk the cursor there one cell at a time, then highlight r
//   { keys: 'x', command: 'mafcmd-expand' }      echo the keys one by one, then name the command and hold;
//                                                 `label` says what they do in words, for stacky-diff's keys line
//   { entry: { level: 1, text }, point, highlight } replace an entry, the result of the command; it flashes
//   { push: 'x + 1' } / { pop: 1 }                  change the stack; a pop applies first, so
//                                                   { pop: 1, entry: {...} } consumes and replaces
//   { insert: 'x^2' }                               type text at point, one character at a time
//   { image: 'media/plot.svg', alt }                show a picture under the pane, what a plot command drew
//   { pause: 600 }                                  wait
//
// Any step may carry `note`, a sentence on what is happening
// mathematically — not which key does it — shown under the pane from
// the moment the step begins until another step's note replaces it.
//
// timeline() turns a scene into a list of { at, action } pairs, absolute
// milliseconds and redux actions, threading the state through the reducer so
// each step can see where the previous one left things. play() dispatches
// them on schedule to a store; mount() does the whole thing in an element,
// with a step-by-step mode beside the replay control: the scene then
// advances one step per press of next, and prev walks it back (beats()).

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
export const IMAGE = 'showy/image'          // { image: { src, alt } | null }
export const NOTE = 'showy/note'            // { note: string | null }
export const RESET = 'showy/reset'          // { state }: replace the whole state

export const initialState = { stack: stacky.stack(), echo: { keys: [], command: '' }, image: null, note: null }

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
    case IMAGE: return { ...state, image: action.image ?? null }
    case NOTE: return { ...state, note: action.note ?? null }
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
    acts.push(now({ type: IMAGE, image: null }))
    acts.push(now({ type: NOTE, note: step.note ?? null }))
    return acts
  }
  if ('note' in step) acts.push(now({ type: NOTE, note: step.note }))
  // A pop goes before a push or an entry in the same step, so one step
  // can consume entries and put the result in their place.
  if ('pop' in step) acts.push(now({ type: POP, n: step.pop }))
  if ('push' in step) acts.push(now({ type: PUSH, text: step.push }))
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
  if ('image' in step) acts.push(now({ type: IMAGE, image: { src: step.image, alt: step.alt ?? '' } }))
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

// The scene as steps to take by hand: [{ step, state, index }], one per
// step that is not a bare pause, `state` being where the scene stands
// once that step is done. An entry a step produced stays lit until the
// next step, where the timeline would let it fade.
export function beats(scene, state = initialState, timing = TIMING) {
  const out = []
  scene.forEach((step, index) => {
    if (Object.keys(step).every(k => k === 'pause')) return
    state = reducer(state, { type: FRESH, level: null })
    for (const { action } of expandStep(step, state, timing)) {
      if (action && !(action.type === FRESH && action.level === null)) state = reducer(state, action)
    }
    out.push({ step, state, index })
  })
  return out
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
  const command = echo.command ? `<span class="command">(${escape(echo.command)})</span>` : ''
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
  // Step-by-step mode: a toggle, and while it is on, prev and next
  // with a count, in place of the replay.
  const stepper = document.createElement('div'); stepper.className = 'stepper'
  const prev = document.createElement('button'); prev.className = 'step'; prev.type = 'button'; prev.textContent = '\u2039 prev'
  const next = document.createElement('button'); next.className = 'step'; next.type = 'button'; next.textContent = 'next \u203a'
  const count = document.createElement('span'); count.className = 'count'
  stepper.append(prev, count, next); stepper.hidden = true
  const toggle = document.createElement('label'); toggle.className = 'stepmode'
  const check = document.createElement('input'); check.type = 'checkbox'
  toggle.append(check, document.createTextNode(' step by step'))
  controls.append(toggle, stepper, button)
  const pane = document.createElement('div')
  el.append(controls, pane)
  const drawStack = stacky.pane(pane)
  const echo = document.createElement('div'); echo.className = 'echo'
  pane.append(echo)
  // The picture a plot command draws, under the echo; absent until a
  // step shows one, and gone again when the stack is reset.
  const image = document.createElement('img'); image.className = 'plot'; image.hidden = true
  pane.append(image)
  const drawImage = im => {
    image.hidden = !im
    if (im && image.getAttribute('src') !== im.src) { image.src = im.src; image.alt = im.alt }
  }
  const note = document.createElement('div'); note.className = 'note'
  pane.append(note)
  const draw = () => {
    const s = store.getState()
    drawStack(s.stack); echo.innerHTML = echoHtml(s.echo); drawImage(s.image)
    note.textContent = s.note ?? ''; note.hidden = !s.note
  }
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
  // Stepping: the beats of the scene, shown one at a time.
  const steps = beats(scene, initialState, timing)
  let at = 0
  const showBeat = i => {
    at = Math.max(0, Math.min(steps.length - 1, i))
    store.dispatch({ type: RESET, state: steps[at].state })
    count.textContent = `${at + 1} / ${steps.length}`
    prev.disabled = at === 0
    next.disabled = at === steps.length - 1
  }
  prev.addEventListener('click', () => showBeat(at - 1))
  next.addEventListener('click', () => showBeat(at + 1))
  const setStepMode = on => {
    player?.stop(); player = null
    stepper.hidden = !on
    button.hidden = on
    el.classList.toggle('stepping', on)
    if (on) showBeat(0); else run()
  }
  check.addEventListener('change', () => setStepMode(check.checked))
  if (autoplay) run(); else label(false)
  return { store, timeline: tl, beats: steps, replay: run, reset, stop: () => player?.stop(),
           step: showBeat, stepMode: on => { check.checked = on; setStepMode(on) } }
}

// Mount every element carrying data-scene from a table of scenes.
export function mountAll(scenes, root = document) {
  return [...root.querySelectorAll('[data-scene]')].map(el => mount(el, scenes[el.dataset.scene]))
}
