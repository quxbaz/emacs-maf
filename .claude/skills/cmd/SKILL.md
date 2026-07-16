---
name: cmd
description: Write a new maf command end to end — definition, binding, verification, tests, docs. Use when asked to add, create, or write a new command (contextual or plain) for maf, including the given prompt's behavior spec.
---

# Writing a new maf command

Take the requested behavior and carry it through every step below; a
command isn't done when the defun exists. Related skills: `ref` for
upstream Calc facts, `emacs` for the dev instance, `drive` for
keypress-level checks, `test` for the step-test convention, `port`
when the source is a `my/calc-*` feature.

## 1. Scope it first

- **Check for an existing counterpart.** The command may already exist
  as a `maf-cmds.el` table row, a `src/stack.el` command, or be one
  `:inv`/`:hyp` link away. Extend rather than duplicate.
- **Check upstream.** If the command mirrors a calc command, read the
  real implementation and manual first (`ref` skill) — flag semantics
  (I/H variants, prefix args) and the exact calcFunc split are easy to
  guess wrong.

## 2. Define the command

Pick the home that matches its shape:

- **Table row in `src/maf-cmds.el`** — the command is a pure
  application of one calcFunc: `(SUFFIX ARITY FUNC [KEY] [:inv S]
  [:hyp S] [:invhyp S] [:map -1])`. Suffix = the calcFunc name.
- **`maf-defcmd` in `src/stack.el`** — composite logic with no single
  calcFunc equivalent. Bindings are `(expr arg commit)`; name the arg
  `_arg` for unary commands. `:arity` is required; `:prefix` is the
  trail label.
- **Plain command** — only when the contextual machinery doesn't apply
  (e.g. `maf-undo`); wrap point handling in `maf--preserve-point`.

Decisions to make deliberately, not by default:

- **`:map -1`?** Commands that consume or produce relations opt out of
  per-side equation mapping; everything else gets per-side for free.
- **Degenerate inputs**: prefer committing the expression unchanged
  over erroring when a no-op is sensible (an equation side that
  doesn't apply must not abort the whole command); `user-error` for
  invalid interactive input.
- **Simplification**: bodies control normalization. Commit under
  `calc-simplify-mode 'none` when the built structure must survive
  (e.g. an undistributed product); compute with `calc-prefer-frac` when
  exact ratios must not detour through floats.
- **Prompts** read their input before touching any calc state, so C-g
  aborts cleanly.

## 3. Set the default binding

- Table rows carry their key in the row.
- Everything else binds in `src/bindings.el` on `maf-mode-map`.
- Match calc's own key when shadowing a calc command; the `l` prefix
  is the home for maf-specific commands.

## 4. Build hygiene

- Every lazily-loaded calc function the file calls needs its own
  `declare-function` (they are per compilation unit; the second arg is
  the *defining* file).
- Gate with warnings as errors and clean up:
  `emacs --batch -L src -L core -L debug --eval '(setq byte-compile-error-on-warn t)' -f batch-byte-compile FILE` then `rm -f` the `.elc`s.
- Docstrings: single space after periods; describe the contextual
  behavior (what it does at home / subexpr / equation); no provenance
  mentions.

## 5. Load and verify live

- Load the edited files into this session's dev instance immediately
  (`emacs` skill). If `maf-defcmd` itself changed, also reload
  `maf-cmds.el` and `stack.el` so commands re-expand.
- Exercise it in the instance across the contexts it claims: home,
  subexpr under point, entry margin, equation (per side), selection,
  keep-args, and the I/H variants if declared.
- Drive the new binding with real keypresses (`drive` skill) — a
  direct `call-interactively` can't catch keymap mistakes.
- Reset calc state between probes with `calc-pop`; restore the sample
  entries when done.

## 6. Test

- Write a step test in `tests/` covering the command's distinct input
  shapes and contexts, including the degenerate ones (`test` skill).
  Assert on what the user sees (`math-format-value`, point position),
  and on raw structure when non-alteration is the contract.
- Run the new test, then the full `tests/` suite — resolve/commit
  changes ripple.

## 7. Close out

- Docs: a new concept or context key goes in
  `docs/reference/concepts.org` (re-export the HTML); tick any
  covered checkbox in `docs/Todo.org` / `docs/maf.org`.
- Report what was decided along the way — deviations from the request,
  upstream quirks found, degenerate-case policy — and leave the work
  uncommitted for the user's `*`.
