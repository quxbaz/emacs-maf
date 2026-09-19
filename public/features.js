// The feature panel: the three categories stacked on the left, the open
// one's entries listed under its heading; the chosen entry's slot shown
// on the stage at the right, a curve drawn from the entry to the stage.
// Pointing at an entry chooses it, as does a click. A slot holds a scene (data-play, a name in scenes.js), a
// diff (data-diff, mounted by stacky-diff's own pass), or a screenshot.
// A scene is mounted when first shown and plays then, again on every
// later choice, and when the stage first comes into view; it stops when
// its slot is hidden. Each category remembers its last chosen entry.

import * as showy from "./showy.js"
import * as scenes from "./scenes.js"

export function mount(root = document) {
  const overview = root.querySelector(".feature-overview")
  if (!overview) return
  const groups = [...overview.querySelectorAll(".feature-group")]
  const cats = groups.map(g => g.querySelector(".cat"))
  const stage = overview.querySelector(".feature-stage")
  const panel = overview.querySelector(".feature-panel")
  const link = overview.querySelector(".feature-link")
  const slots = [...overview.querySelectorAll(".feature-stage .slot")]
  const entries = groups.map(g => [...g.querySelectorAll("section[id]")])
  const chosen = entries.map(es => es[0] && es[0].id)
  const players = new Map()
  let seen = false, current = null, entry = null
  // The curve: from the entry's card edge, level with the entry's
  // middle, to the stage's edge, level with the stage's middle, an
  // S-curve with level ends, and a dot where it leaves the entry.
  const drawLink = () => {
    if (!link || !entry || !stage) return
    const p = panel.getBoundingClientRect(), s = stage.getBoundingClientRect()
    const e = entry.getBoundingClientRect(), card = entry.closest(".feature-group").getBoundingClientRect()
    const x0 = card.right - p.left, y0 = (e.top + e.bottom) / 2 - p.top
    const x1 = s.left - p.left, y1 = (s.top + s.bottom) / 2 - p.top
    const xm = (x0 + x1) / 2
    link.innerHTML = `<path d="M${x0} ${y0}C${xm} ${y0} ${xm} ${y1} ${x1} ${y1}"/><circle cx="${x0}" cy="${y0}" r="3.5"/>`
  }
  const player = (slot) => {
    if (!players.has(slot)) {
      const scene = scenes[slot.dataset.play]
      players.set(slot, scene ? showy.mount(slot, scene, { autoplay: false }) : null)
    }
    return players.get(slot)
  }
  const show = (id) => {
    for (const s of slots) {
      const on = s.dataset.for === id
      s.classList.toggle("is-shown", on)
      if (on) current = s
      else if (s.dataset.play && players.has(s)) players.get(s).stop()
    }
    if (current && current.dataset.play) {
      const p = player(current)
      if (seen) p.replay(); else p.reset()
    }
  }
  const select = (g, id) => {
    chosen[g] = id
    groups.forEach((el, i) => {
      el.classList.toggle("is-active", i === g)
      cats[i].setAttribute("aria-expanded", i === g)
    })
    for (const es of entries) for (const e of es) {
      e.classList.toggle("is-selected", e.id === id)
      if (e.id === id) entry = e
    }
    show(id)
    drawLink()
  }
  cats.forEach((c, g) => c.addEventListener("click", () => select(g, chosen[g])))
  entries.forEach((es, g) => es.forEach(e => {
    e.addEventListener("click", () => select(g, e.id))
    e.addEventListener("mouseenter", () => { if (e !== entry) select(g, e.id) })
  }))
  if (panel && "ResizeObserver" in window) new ResizeObserver(drawLink).observe(panel)
  document.fonts?.ready.then(drawLink)
  const fromHash = () => {
    const id = location.hash.slice(1)
    const g = entries.findIndex(es => es.some(e => e.id === id))
    if (g >= 0) select(g, id)
  }
  addEventListener("hashchange", fromHash)
  if (chosen[0]) select(0, chosen[0])
  fromHash()
  if (stage && "IntersectionObserver" in window) {
    const io = new IntersectionObserver((hits) => {
      if (!hits.some(h => h.isIntersecting)) return
      seen = true
      io.disconnect()
      if (current && current.dataset.play) player(current).replay()
    }, { threshold: .5 })
    io.observe(stage)
  } else seen = true
  // The hidden shots are lazy; fetch them once the page is idle so the
  // first click does not wait on the network.
  const shots = [...overview.querySelectorAll(".feature-stage img")]
  const warm = () => shots.forEach(s => { s.loading = "eager" })
  if ("requestIdleCallback" in window) requestIdleCallback(warm); else setTimeout(warm, 1500)
}
