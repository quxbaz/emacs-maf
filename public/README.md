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
- `scenes.js`: the scenes the pages show, as data. An element with
  `data-scene="name"` plays the scene of that name.
- `vendor/`: redux 5.0.1 (ESM) and MathJax 3.2.2.

Scenes should use the columns and highlight ranges maf really produces; check
them in a live calc buffer.

## Data

The generators under `gen/` write `data/`; see `gen/README.md`.
