# Calc selection quirks (upstream)

Drift in calc's own sub-formula resolution, discovered 2026-07-11 by
sweeping `maf-hl-mode` against calc's selection renderer
(`debug/maf-hl-sweep.el`); it affects stock calc too (try `j s` at the
positions below). The largest item — dropped denominator parens — is
diagnosed and **fixed in maf** as of 2026-08-23; the remaining ones are
still mirrored.

## Selection compositions dropped denominator parens (fixed)

Originally misdiagnosed here as "synthesized parens invisible to the
selection walker" — parens emitted by the renderer that the walker
counted as zero-width. The real cause is upstream dropping an argument:
the tag/selection branch (the first `cond` arm) of `math-compose-expr`
in `calccomp.el` recurses as `(math-compose-expr a prec)`, losing the
third argument DIV. DIV is what brackets a product standing as a
denominator — implicit multiplication outranks `/`, so precedence alone
never adds those parens — and it is the only paren source the branch
loses; PREC rides through. So every composition built for the selection
machinery (`calc-prepare-selection` with `math-comp-tagged`, and
selected-entry re-renders) was genuinely two characters short per
bracketed denominator. The walkers were never wrong; they walked a
wrong composition.

One cause, several faces, all confirmed on `y = 8 / (3 x^3) - 5:3`:

- Cursor→sub-formula resolution shifted by 2 past the `(`: the `(`
  resolved the inner `3`, the `-` resolved the trailing frac.
- The entry's last two columns (`:` and final `3` of `5:3`) resolved to
  nothing at all — RET signaled "Could not resolve target at point",
  `j e` silently did nothing.
- The whole-formula selection extent came out 2 columns short (the
  doc's old `(e f)` table was this same shift).
- A re-render from the cached composition (`calc-change-current-selection`,
  which runs after any selection rewrite, `j e` included) wrote the
  paren-less text — `8 / 3 x^3` — into the buffer until the next
  refresh.

The fix is `maf--comp-compose-keep-div` in `core/maf-comp.el`: `:around`
advice on `math-compose-expr` that re-runs exactly the dropped-DIV case
with DIV passed through, replicating the branch's own bookkeeping. All
consumers read the one cached composition, so resolution
(`calc-find-selected-part` and maf's resolve layer), highlight extents
(`maf--comp-flat-term`), anchors, and selection-time re-renders
corrected together — the old fear that highlighter and resolve path had
to be fixed in tandem dissolved, since they share the data structure
that was wrong. Loading maf also un-quirks stock calc's `j s` in that
session. Regression test: `tests/sel-comp-parens.el`. The bug is worth
reporting upstream to Emacs.

## Remaining quirks (still mirrored)

maf targets what `calc-prepare-selection` / `calc-find-selected-part`
answer, so these stand until fixed at the source like the above.

### Line-break gap

At the trailing space where a wrapped entry breaks to the next line,
resolution answers the enclosing sum spanning the break (a real node,
verified 2026-08-23), but highlight geometry at the gap stays
approximate — the sweep classifies divergence at line-break gaps as
`:quirks`, not failures.

### A matrix's rows cannot be picked by point

In the multi-line matrix rendering, calc maps every structural
character — the rows' brackets and commas included — to the whole
matrix: `calc-find-selected-part` answers the full `[[1, 2], [3, 4]]`
wherever point sits short of an actual element. So no cursor position
names an inner row, and any point-targeted command (the `j l` / `j r`
element shifts, for one) can act on a row's elements or on the whole
matrix, but never on a row as a unit. A *non*-matrix nested vector
renders flat, and there an inner vector's own comma resolves to it —
`[[1, 2], [3, 4, 9], [5]]` moves whole sub-vectors fine.

## How it's tested

`debug/maf-hl-sweep.el` sweeps every cursor position of many expression
types and compares `maf-hl` against calc's resolver (presence) and
calc's selection renderer (extent). Its `:synth-parens` classifier
(rendered length vs walker length) should find nothing now that the
composition carries its parens; with the fix in place the old extent
quirks on `(a + b)^(c - d) / (e f)` are gone from the report.

Note (2026-08-23): the sweep is not currently clean on `main` even
aside from all this — every expression reports a uniform set of
mismatches at the line-prefix columns and EOL, where `maf-hl` now
highlights the whole entry (the margin → entry target) while the
sweep's oracle answers nil. That maf-hl behavior postdates the sweep;
the oracle needs updating before `:problem-exprs nil` means clean
again. Predates the parens fix (verified by an advice-removed baseline
run; the two reports' mismatch sets are identical).

The walker maf uses for highlight/anchor coordinates is
`maf--comp-flat-term` in `core/maf-comp.el` (this doc used to name it
`maf-hl--flat-term` in `modules/maf-hl.el`; it moved).
