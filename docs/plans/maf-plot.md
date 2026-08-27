# Plan: maf-plot

Plotting for maf, replacing the legacy `~/.emacs.d/my/calc/plot.el`
(`my/calc-graph-quick`) — the one feature the port audit found missing.
Not yet implemented. Both rendering backends were prototyped live on
2026-08-27 against real stack entries; the pitfalls below come from those
runs, not speculation.

## Goal

One module, `modules/maf-plot.el`. Two gestures: plot the entry at point,
plot all entries. Three interchangeable surfaces behind a dial. Stock calc
graphing untouched when the module is off.

## The switch

Standard module contract plus a backend option:

- **Module off** — inert. Calc's own `g`-prefix graphing (`calc-graph.el`)
  works exactly as stock.
- **Module on** — maf-plot owns the entire `g` prefix (clobbering stock
  `g` keys is fine — decided), and a 3-way backend option selects the
  surface:
  - `gnuplot-external` — interactive gnuplot window (qt/x11). Mouse zoom,
    readout, 3D rotation. Closest to stock calc behavior.
  - `gnuplot-embed` — gnuplot renders SVG, displayed in a split buffer
    (`*maf-plot*`, via `display-buffer`). Themed from the live faces.
  - `desmos` — fire-and-forget browser launch of a local static page
    embedding the Desmos calculator. Requires network.

Dial reads: `off / gnuplot-external / gnuplot-embed / desmos`.

## Confirmed design decisions

1. **Target is the whole entry.** Point anywhere in an entry plots that
   entry; subexpr and selection are ignored. Point inside a term is how
   you reach an entry, not a request to graph `3y` out of context.
2. **Two commands, not one.** `g g` plots the entry at point. `g a`
   plots all stack entries in a single plot (overlay on gnuplot
   backends, one shared canvas on desmos).
3. **Never translate syntax for gnuplot.** Calc samples the expression
   numerically (`math-expr-subst` + `math-evaluate-expr`) and gnuplot
   receives plain data files. Anything calc can evaluate can be
   plotted. This is how upstream `calc-graph-format-data` works too;
   the legacy plot.el's regex translation is the road not taken.
4. **Send the formula, not samples, to desmos.** Interactive graphers
   resample on zoom; fixed samples would waste the interactivity. Calc's
   own LaTeX formatter (`maf--latex-string`, already in maf-pretty) is
   the entire translation layer.
5. **Relation entries plot.** `y = f(x)`: gnuplot backends sample the
   rhs; desmos receives the equation whole (it graphs equations,
   including implicit ones, natively).
6. **Range: never prompt, x only.** y always autoscales. Default x
   range: expressions containing trig get one period around 0,
   angle-mode-aware (±360 in degrees, ±2π in radians); everything else
   gets a `defcustom` default (-10..10). `C-u` prompts for an explicit
   range; the last explicit range is sticky for the session. For
   overlays the trig rule fires if any curve is trig, and a prompted
   range governs the whole plot.
7. **Shared axes, no y2 auto-promotion.** Silently reassigning a curve
   to a second axis changes what the picture means; a squashed curve is
   honestly squashed. The dual-axis render (verified working) stays in
   the back pocket as a possible explicit toggle.
8. **Desmos is fire-and-forget.** No live updates, no page
   regeneration, no server. Every invocation is an independent
   snapshot; the URL is the graph.
9. **Desmos stays light-themed.** No Emacs-theme coupling (decided
   after comparing). The embed backend is the themed surface — it pulls
   background/foreground/accent from the live faces at render time.

## gnuplot pipeline (both gnuplot backends)

Per curve: resolve entry → take rhs if relation → sample n points over
the x range → write `x y` lines to a data file → generate a small script
→ run gnuplot. The backends differ only in the terminal line:
`set terminal svg` + display in `*maf-plot*`, vs an interactive terminal.

Overlay = one data file per curve, comma-separated plot clauses with
per-curve color and a legend title (the entry's formatted text), same
x range for all.

Sampling requirements, all hit during prototyping:

- **Bind `calc-symbolic-mode` to nil** around evaluation. Symbolic mode
  (which leaks in via calc-settings-file) leaves `sin(1.5)` unevaluated
  and every sample gets rejected — while plain arithmetic still
  evaluates, so the breakage is per-expression and confusing.
- **Filter with `Math-realp`** and simply skip non-real samples.
  Singularities and complex regions become gaps, which gnuplot renders
  correctly.
- **Respect the angle mode.** Evaluation happens in the calc buffer, so
  `calc-angle-mode` applies; the range default must match (a ±7 range
  on a degrees-mode sine is a flat line).
- Numbers formatted by `math-format-value` (including `30.` and sci
  notation) are read by gnuplot as-is.

Embed display: `create-image` + `insert-image` into `*maf-plot*`;
`image-flush` before re-render, since the SVG file path is reused.

## desmos pipeline

Ships one static asset, `maf-plot.html`: a div, the Desmos API script
tag, and ~10 lines of JS that parse `location.hash` and call
`setExpression`. The fragment is the whole contract — a URI-encoded JSON
object:

```
{e: [latex, ...], d: degreeMode}
```

Elisp side: `maf--latex-string` per entry → build JSON → hexify → append
as fragment → launch browser. Nothing is generated per plot.

- **Launch the browser binary directly** (`browse-url-generic` with the
  user's browser). `browse-url-default-browser` goes through `xdg-open`,
  which resolves `file://` URLs to paths and silently drops the
  fragment — the calculator opens empty. Found the hard way.
- **`degreeMode` comes from `calc-angle-mode`.** Desmos defaults to
  radians; without this the graph lies relative to the calc session.
- **API key is a `defcustom`** defaulting to Desmos's published demo
  key. The calculator.js bundle loads from their CDN at page-open; it
  cannot be vendored (ToS), so maf distributes only the HTML page.
- Fragments never leave the browser; URL size is a non-issue for tens
  of kilobytes of expressions.

## Bindings

Module claims the `g` prefix wholesale when on:

- `g g` — plot entry at point
- `g a` — plot all entries

The rest of the prefix is free for future subgestures (explicit range
key, escape-to-interactive-window from the embed pane).

## Test plan

Rendering is verified by eye, but everything up to the render is
step-testable:

1. Sampling: known entry → data file contents (count, endpoints, a
   known value; a symbolic-mode instance must still produce points).
2. Range selection: trig vs non-trig, degrees vs radians, sticky
   explicit range, `C-u` prompt path.
3. Relation handling: rhs extraction for gnuplot; equation passed whole
   in the desmos URL.
4. Desmos URL construction: fragment decodes back to the expected JSON
   for a stack of entries.
5. Dial/bindings: `g` prefix stock when off, claimed when on, per
   backend dispatch.

## Open questions

- Selection at point: presumed ignored like subexpr (same rationale);
  confirm.
- `g a` on a stack with unplottable entries (constants are fine as
  horizontal lines; entries with two-plus free variables are not) —
  skip silently, or message?
- Plot variable: prototypes assumed `x`. Detect the single free
  variable and use it? Error on two-plus?
- Vector entry `[f(x), g(x)]` as one-curve-per-element — calc-native
  way to build an overlay by hand. Worth it?
- The `o` escape from the embed pane to an interactive window (same
  data, different terminal — cheap).
- 3D (`splot`): `gnuplot-external` is the natural home (rotation);
  out of scope for v1.
