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
  text, pause). `timeline()` turns a scene into timed redux actions and
  `play()` dispatches them; `mount()` does both in an element.
- `stacky-diff.js`: a stack before and after a command, side by side, the keys and
  command above them. Each pane can show or hide the cursor, the
  highlight and the header line, and can outline the part that changed
  instead; by default the after pane hides the cursor and outlines the
  change. The line above
  the pair is the keys and command, or any HTML given as the caption: for an
  element mounted from the page, its own content. With `reveal` (`data-reveal`
  on the page) the after pane starts as an empty stack and the caption is a
  button that shows the result. Takes explicit before and after stacks, or derives them
  from a showy scene so the two views of one example cannot drift. An element
  with `data-diff="name"` shows the scene of that name this way.
- `scenes.js`: the scenes the pages show, as data. An element with
  `data-scene="name"` plays the scene of that name.
- `vendor/`: redux 5.0.1 (ESM) and MathJax 3.2.2.

Scenes should use the columns and highlight ranges maf really produces; check
them in a live calc buffer.

## Data

The generators under `gen/` write `data/`; see `gen/README.md`.
