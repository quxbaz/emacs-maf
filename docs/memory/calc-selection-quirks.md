# Calc selection quirks (upstream)

Known drift in calc's own sub-formula resolution that maf deliberately
mirrors. Discovered 2026-07-11 by sweeping `maf-hl-mode` against calc's
selection renderer (`debug/maf-hl-sweep.el`); affects stock calc too (try
`j s` at the positions below).

## Synthesized parens are invisible to the selection walker

Calc renders some parentheses without putting them in the composition: the
flat renderer emits `(`/`)` from `(set LEVEL ...)`/`(break LEVEL)` markers
(see `math-comp-to-string-flat-term` in `calccomp.el`). The selection
walker `math-comp-sel-flat-term` — and maf's clone `maf-hl--flat-term` in
`modules/maf-hl.el` — treats `set`/`break` as **zero-width**, so from the first
synthesized paren onward, cursor columns map to shifted formula positions.

Example: `(a + b)^(c - d) / (e f)`. The numerator's parens are literal
strings in the composition; the denominator's are synthesized. Result:

| cursor on | calc resolves |
|-----------|---------------|
| `(` of `(e f)` | `e` |
| `e`            | `e f` (the product) |
| space          | `f` |
| `f`            | nothing |

The whole-formula selection also comes out 2 columns short (the overlay
ends at `(e ` instead of `f)`).

A related off-by-one: at the trailing space where a wrapped entry breaks to
the next line, calc resolves the term *before* the break, so the highlight
does not cover point there.

## Why maf mirrors it instead of fixing it

The highlight's contract is "show what a contextual command will operate
on", and maf's resolve layer targets whatever `calc-prepare-selection` /
`calc-find-selected-part` resolve. Fixing the walk only in `maf-hl` would
make the highlight disagree with the commands. A real fix must correct the
coordinate accounting (advance positions for renderer-emitted parens, i.e.
replicate the `math-comp-level` bookkeeping) in **both** the highlighter's
walker and the selection/resolve path together.

## How it's tested

`debug/maf-hl-sweep.el` sweeps every cursor position of many expression
types and compares `maf-hl` against calc's resolver (presence) and calc's
selection renderer (extent). Entries whose rendered length differs from the
walker's length contain synthesized parens; divergence there (and at
line-break gaps) is classified as `:quirks`, not failures. A clean run
returns `:problem-exprs nil` with a handful of `:calc-quirks`.
