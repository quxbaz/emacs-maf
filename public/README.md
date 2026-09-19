# The site

Static HTML, CSS and ES modules under this directory; no build step. Serve it
from the repository root with a reloading server while working:

    npx live-server public --port=8080 --no-browser

## Modules

- `stacky.js`: a calc stack buffer as data. Entries by level, point, a
  highlight range, and a layout that matches calc's: numbered lines, highest
  level first, then the home line's indented dot, under calc's header-line
  banner built for a given width. `text()` gives the buffer as
  a string, `html()` as markup.
- `showy.js`: an animated presentation of maf at work, on top of stacky and a
  vanilla redux store. A scene is a list of plain steps (set the stack, walk
  the cursor somewhere, echo keys and a command name, replace an entry, type
  text, show a picture under the pane — what a plot command drew, an SVG
  under `media/` — pause). `timeline()` turns a scene into timed redux actions and
  `play()` dispatches them; `mount()` does both in an element, with a
  control above the pane that resets a playing scene and replays a finished
  one, and a step-by-step toggle: on, the scene advances one step per
  press of next, and prev walks it back. A step may carry a `note`, a
  sentence on what is happening mathematically, shown under the pane
  from the moment the step begins.
- `stacky-diff.js`: a stack before and after a command, side by side, the keys and
  command above them. Each pane can show or hide the cursor, the
  highlight and the header line, and can outline the part that changed
  instead; by default the after pane hides the cursor and outlines the
  change. The line above
  the pair is the keys and command, or any HTML given as the caption: for an
  element mounted from the page, its own content. With `reveal` (`data-reveal`
  on the page) the after pane starts as an empty stack and the caption is a
  button that shows the result. With `result` (`data-result`) there is one
  pane, the stack before with the produced entry on a last line after `=>`. Takes explicit before and after stacks, or derives them
  from a showy scene so the two views of one example cannot drift. An element
  with `data-diff="name"` shows the scene of that name this way.
- `scenes.js`: the scenes the pages show, as data. An element with
  `data-scene="name"` plays the scene of that name.
- `features.js`: the feature panel. The three categories stack on the left;
  the open one lists its entries under its heading, and the entry clicked
  there, or named by the page's hash, has its slot shown on the stage at the
  right: a scene played by showy (`data-play`), a stacky-diff (`data-diff`),
  or a screenshot. A scene plays when its entry is chosen and when the stage
  first scrolls into view.
- `demo.html`: every component variant on one scene, with the markup that
  produces each; the reference for choosing which fits an example.
- `vendor/`: redux 5.0.1 (ESM) and MathJax 3.2.2.

Scenes should use the columns and highlight ranges maf really produces; check
them in a live calc buffer. A plot a scene shows is gnuplot's SVG of the
curve data maf samples, drawn in the calc pane's palette (`.calcbuf` in
`style.css`) rather than the live instance's theme.

## Data

The generators under `gen/` write `data/`; see `gen/README.md`. The
screenshots under `media/screens/` — a PNG and a fontified HTML per
feature — come from `gen/screens.el`, run in the live dev instance.
