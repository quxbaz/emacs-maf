---
name: calc-ref
description: Look up Emacs Calc internals — source code, data structures, calcFunc-* functions, selection machinery, or documented behavior. Use when a maf question depends on how upstream Calc actually works rather than on maf's own code.
---

# Calc reference material

Both locations are git-ignored local copies; consult them before
guessing at Calc behavior:

- `calc-src/` — the Emacs Calc Lisp source. Grep here for the real
  definition of any `calc-*` / `calcFunc-*` / `math-*` symbol, stack
  and selection internals, etc.
- `docs/gnu-emacs-calc-manual/gnu-emacs-calc-manual.html` — the full
  GNU Calc manual as a single HTML file. Grep for user-facing,
  documented behavior.

If either is missing, tell the user rather than substituting web
sources — these copies match the Emacs version being developed against.

Quirks maf deliberately mirrors instead of fixing are catalogued in
`docs/memory/calc-selection-quirks.md`; check there before treating an
odd Calc behavior as a maf bug.
