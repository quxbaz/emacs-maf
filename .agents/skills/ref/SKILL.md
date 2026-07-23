---
name: ref
description: Execute the given prompt using the local Emacs Calc source and manual as reference. Use when a task or question depends on how upstream Calc actually works — calcFunc-* definitions, stack/selection internals, documented behavior — rather than on maf's own code.
---

# Working from the Calc references

Execute the prompt as given; the point of this skill is that any claim
about Calc behavior gets checked against the actual source or manual,
not guessed. Both are local, git-ignored copies under `calc-ref/` in
the project root:

- `calc-ref/calc-src/` — the Emacs Calc Lisp source. Grep here for the real
  definition of any `calc-*` / `calcFunc-*` / `math-*` symbol, stack
  and selection internals, etc.
- `calc-ref/calc-manual/gnu-emacs-calc-manual.html` — the full GNU Calc
  manual as a single HTML file. Grep for user-facing, documented
  behavior.

`calc-ref/` is read-only reference, never the edit target — requested
changes land in maf's own code.

If either copy is missing, tell the user rather than substituting web
sources — these copies match the Emacs version being developed against.

Quirks maf deliberately mirrors instead of fixing are catalogued in
`docs/memory/calc-selection-quirks.md`; check there before treating an
odd Calc behavior as a maf bug.

## Examples

### [EXAMPLE 1] /ref add a maf-log command; a prefix arg should supply the base

```sh
# find the real implementation first, then build maf against it
grep -rn "defun calcFunc-log" calc-ref/calc-src/
grep -n "Logarithm" calc-ref/calc-manual/gnu-emacs-calc-manual.html
```

Read the definition found (here `calc-ref/calc-src/calc-math.el`) to learn
how `calcFunc-log` takes an optional base argument, confirm the
documented behavior in the manual section, then implement the command
in maf's own code.

### [EXAMPLE 2] /ref why does calc keep selections after this command?

```sh
grep -rn "calc-keep-selection" calc-ref/calc-src/
```

Answer from the definitions found, quoting the relevant code; check
`docs/memory/calc-selection-quirks.md` for known intentional oddities.
