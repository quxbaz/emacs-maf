// The brace beside the fold's examples, drawn as one path so that it is
// one stroke at any device scale: a curl at the top, the stem, the cusp
// level with the lede's panel, the stem again, a curl at the bottom, and
// a line from the panel's edge to the cusp. The cusp's height is the
// panel's middle, which only the layout knows, so the path is written
// from measurement, on load and whenever anything in the column changes
// size: the brace itself, or any layer of prose, since one growing
// above the panel moves it without resizing it. The cusp is held within
// the stem, for a layout where the panel's middle lies past either end.
//
// Coordinates are the stroke's center, in the brace's own pixels. The
// stem stands 36px from the examples, the curls and the cusp are 10px
// arcs, and the curls' tips sit 1px in from the edges so the 2px stroke
// ends flush with them.

const STEM = 36, R = 10

function draw(svg, lede) {
  const b = svg.getBoundingClientRect(), l = lede.getBoundingClientRect()
  if (!b.width || !b.height) return
  const w = b.width, h = b.height
  const x = Math.round(w - STEM) + 1
  const mid = Math.round((l.top + l.bottom) / 2 - b.top)
  const cy = Math.max(1 + 2 * R, Math.min(h - 1 - 2 * R, mid))
  svg.querySelector('path').setAttribute('d', [
    `M${x + R} 1A${R} ${R} 0 0 0 ${x} ${1 + R}`,
    `V${cy - R}A${R} ${R} 0 0 1 ${x - R} ${cy}A${R} ${R} 0 0 1 ${x} ${cy + R}`,
    `V${h - 1 - R}A${R} ${R} 0 0 0 ${x + R} ${h - 1}`,
    `M0 ${cy}H${x - R}`,
  ].join(''))
}

export function mount() {
  const svg = document.querySelector('.intro .brace svg'), lede = document.querySelector('.intro .lede')
  if (!svg || !lede) return
  const redraw = () => draw(svg, lede)
  const watch = new ResizeObserver(redraw)
  watch.observe(svg)
  for (const layer of document.querySelectorAll('.intro .col > .layer')) watch.observe(layer)
  document.fonts?.ready.then(redraw)
  redraw()
}
