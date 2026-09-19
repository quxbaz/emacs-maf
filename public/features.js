// The feature stage: the screenshot, title and summary of the feature
// clicked, or stepped to with the stage's own buttons, or chosen with
// the arrow keys while a tab has focus, or named by the page's hash; the
// first feature until then. Pointing at a tab
// does nothing, so the stage holds still while the pointer crosses the
// rows. The stage holds every shot and shows one; each feature's tab
// holds its summary.
export function mount(root = document) {
  const overview = root.querySelector(".feature-overview")
  const tabs = overview && overview.querySelector(".feature-tabs")
  if (!tabs) return
  const entries = [...tabs.querySelectorAll("section[id]")]
  const shots = [...overview.querySelectorAll(".feature-stage img")]
  const caption = overview.querySelector(".feature-stage figcaption")
  const title = caption && caption.querySelector("strong")
  const summary = caption && caption.querySelector("span")
  let current = -1
  const select = (i) => {
    current = i
    const entry = entries[i]
    for (const e of entries) e.classList.toggle("is-selected", e === entry)
    for (const s of shots) s.classList.toggle("is-shown", s.dataset.for === entry.id)
    if (title) title.textContent = entry.querySelector("h4").textContent
    if (summary) summary.innerHTML = entry.querySelector("p").innerHTML
  }
  entries.forEach((e, i) => e.addEventListener("click", () => select(i)))
  // The buttons wrap around the ends; the arrow keys stop at them, so
  // focus never jumps across the menu.
  const step = (d) => select((current + d + entries.length) % entries.length)
  const prev = overview.querySelector(".feature-stage .step.prev")
  const next = overview.querySelector(".feature-stage .step.next")
  if (prev) prev.addEventListener("click", () => step(-1))
  if (next) next.addEventListener("click", () => step(1))
  tabs.addEventListener("keydown", (ev) => {
    if (ev.key === "ArrowRight" || ev.key === "ArrowLeft") {
      ev.preventDefault()
      const i = Math.min(entries.length - 1, Math.max(0, current + (ev.key === "ArrowRight" ? 1 : -1)))
      select(i)
      entries[i].focus({ preventScroll: true })
    }
  })
  const fromHash = () => {
    const i = entries.findIndex(e => e.id === location.hash.slice(1))
    if (i >= 0) select(i)
  }
  addEventListener("hashchange", fromHash)
  if (entries.length) select(0)
  fromHash()
  // The hidden shots are lazy; fetch them once the page is idle so the
  // first click does not wait on the network.
  const warm = () => shots.forEach(s => { s.loading = "eager" })
  if ("requestIdleCallback" in window) requestIdleCallback(warm); else setTimeout(warm, 1500)
}
