// The feature list's floating picture: the slot of the entry the
// pointer is on, or the focused one, placed beside the entry on
// whichever side of its column has more room, level with the entry
// and kept within the viewport. It ignores the pointer, so the entries
// under it stay live. A slot holds a scene (data-play, a name in
// scenes.js), a diff (data-diff, mounted by stacky-diff's own pass),
// or a screenshot; a scene is mounted when first shown and plays on
// every show, and stops when put away.

import * as showy from "./showy.js"
import * as scenes from "./scenes.js"

export function mount(root = document) {
  const overview = root.querySelector(".feature-overview")
  const peek = overview && overview.querySelector(".feature-peek")
  if (!peek) return
  const entries = [...overview.querySelectorAll(".feature-group section[id]")]
  const slots = [...peek.querySelectorAll(".slot")]
  const players = new Map()
  let current = null, slot = null
  const player = (s) => {
    if (!players.has(s)) {
      const scene = scenes[s.dataset.play]
      players.set(s, scene ? showy.mount(s, scene, { autoplay: false }) : null)
    }
    return players.get(s)
  }
  const place = (entry) => {
    const r = entry.getBoundingClientRect()
    const col = entry.closest(".feature-group").getBoundingClientRect()
    const w = peek.offsetWidth, h = peek.offsetHeight
    const gap = 18, margin = 12
    const right = innerWidth - col.right, left = col.left
    let x = right >= left ? col.right + gap : col.left - gap - w
    x = Math.max(margin, Math.min(innerWidth - margin - w, x))
    let y = (r.top + r.bottom) / 2 - h / 2
    y = Math.max(margin, Math.min(innerHeight - margin - h, y))
    peek.style.left = `${x}px`
    peek.style.top = `${y}px`
  }
  const show = (entry) => {
    current = entry
    for (const s of slots) {
      const on = s.dataset.for === entry.id
      s.classList.toggle("is-shown", on)
      if (on) slot = s
      else if (s.dataset.play && players.has(s)) players.get(s).stop()
    }
    for (const e of entries) e.classList.toggle("is-peeked", e === entry)
    peek.hidden = false
    place(entry)
    if (slot.dataset.play) player(slot).replay()
  }
  const hide = () => {
    if (slot && slot.dataset.play && players.has(slot)) players.get(slot).stop()
    current = null
    peek.hidden = true
    for (const e of entries) e.classList.remove("is-peeked")
  }
  // The pointer must rest on an entry a moment before its picture
  // opens, so a sweep across the list opens nothing.
  let timer = null
  for (const e of entries) {
    // A tap focuses the entry, which shows; a tap elsewhere blurs it.
    e.addEventListener("pointerenter", (ev) => {
      if (ev.pointerType === "touch") return
      clearTimeout(timer)
      timer = setTimeout(() => show(e), 160)
    })
    e.addEventListener("pointerleave", (ev) => {
      if (ev.pointerType === "touch") return
      clearTimeout(timer)
      hide()
    })
    e.addEventListener("focus", () => show(e))
    e.addEventListener("blur", hide)
  }
  addEventListener("keydown", (ev) => { if (ev.key === "Escape" && current) { current.blur(); hide() } })
  addEventListener("scroll", () => { if (current) place(current) }, { passive: true })
  addEventListener("resize", () => { if (current) place(current) })
  // The shots are lazy; fetch them once the page is idle so the first
  // hover does not wait on the network.
  const shots = [...peek.querySelectorAll("img")]
  const warm = () => shots.forEach(s => { s.loading = "eager" })
  if ("requestIdleCallback" in window) requestIdleCallback(warm); else setTimeout(warm, 1500)
}
