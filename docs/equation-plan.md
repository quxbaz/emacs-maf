# Plan: equation target per-side iteration

The last remaining target. Big enough that it's worth picking up cold from this
plan rather than re-deriving from conversation.

For context, see [concepts.org](concepts.org) (target system overview) and
[walkthrough.org](walkthrough.org) (a concrete command end-to-end).

## Goal

When point is on a stack entry that is a relation (`=`, `!=`, `<`, `<=`, `>`, `>=`)
and the user invokes a `maf-defcmd` command, the body should run *once per side* —
once with `:expr = lhs`, once with `:expr = rhs`. The two results are reassembled
into a new relation `(rel-op new-lhs new-rhs)` and pushed as a single entry.

Reference behaviour to mirror: `my/calc-replace-expr-dwim`'s equation branch
in `~/.emacs.d/my/calc/lib.el` (search for "Branch 5: equation").

## Confirmed design decisions

1. **Body is not side-aware.** No `:side` binding. The user writes one body; the
   macro handles the per-side iteration internally. Body sees `:expr` rebound
   between calls.
2. **Binary commands share one `:arg` across both sides.** For `x = 5` + arg `3`
   + binary `+`, the result is `x+3 = 5+3`. The arg is consumed *once total*
   (a single `:post-pop-n`), not once per side. Mirrors reference's
   `pop-forms` firing outside the per-side loop.
3. **`m=1 + binary` errors.** The relation is at the top; arg would come from
   `calc-top 1` which is the relation itself. No coherent semantics. Reject
   in resolve, same shape as selection's error.

## API (user-facing — unchanged)

The user writes the same `maf-defcmd` they'd write for any target:

```elisp
(maf-defcmd maf-foo (expr arg commit)
  "..."
  :arity unary
  :prefix "foo"
  (commit (calcFunc-foo expr)))
```

When this command fires on an equation, the body runs twice — once with
`expr` bound to the LHS, once with `expr` bound to the RHS. The user
doesn't write anything special.

## Architecture: where the iteration happens

The `maf-defcmd` macro is the natural place. Its expanded `defun` already
holds:

- the `maf--resolve-context` call
- the `let*` that destructures `:expr`, `:arg`
- the `cl-flet` that defines `commit`
- the body

For equation, instead of running the body once, the macro should generate
code that:

1. Reads `:target` from context.
2. If `:target` is `equation`, run the body twice in a loop, each time
   rebinding `expr` to `:lhs` or `:rhs`, and capturing what `commit` was
   called with on each side.
3. Then invoke a single equation-commit with `(new-lhs, new-rhs)` bundled.
4. Else (any other target), run the body once and call `commit` directly
   as it does now.

This means `commit` behaves differently depending on whether we're in the
equation branch or not. Two ways to wire that up:

- **(A)** Inside the equation branch, override `commit` via `cl-flet` to
  capture into local `g-lhs` and `g-rhs` rather than calling
  `maf--commit`. After both sides, call `maf--commit` once with the
  reassembled relation.
- **(B)** Add a flag/binding that `commit` reads to decide between "commit
  immediately" and "capture for later." Less clean.

**Prefer (A).** Reference uses this pattern: per-side
`cl-flet ((replace-expr (e) (setq g-lhs e)))` and `setq g-rhs e`, then a
single `calc-pop-push-record-list` after.

## Resolve changes — `maf--resolve-target-equation`

Currently:

```elisp
(defun maf--resolve-target-equation (opts)
  "..."
  (ignore opts)
  (maf--with-calc-buffer
    (let* ((m    (calc-locate-cursor-element (point)))
           (expr (calc-top m 'full)))
      `((:target . equation)
        (:expr   . ,expr)
        (:lhs    . ,(nth 1 expr))
        (:rhs    . ,(nth 2 expr))
        (:m      . ,m)))))
```

Needs to grow into the same shape as other targets: `:arg`, `:push-m`,
`:push-n`, `:post-pop-n`, plus the `m=1+binary` error.

Target shape:

```elisp
(defun maf--resolve-target-equation (opts)
  "..."
  (maf--with-calc-buffer
    (let* ((arity (alist-get :arity opts))
           (m     (calc-locate-cursor-element (point)))
           (keep  calc-keep-args-flag)
           (expr  (calc-top m 'full)))
      (when (and (eq arity 'binary) (= m 1))
        (error "Binary commands on equation require the relation below the top"))
      `((:target     . equation)
        (:expr       . ,expr)                  ; the whole relation
        (:rel-op     . ,(car expr))            ; calcFunc-eq/neq/lt/leq/gt/geq
        (:lhs        . ,(nth 1 expr))
        (:rhs        . ,(nth 2 expr))
        (:arg        . ,(pcase arity ('unary nil) ('binary (calc-top 1 'full))))
        (:m          . ,m)
        (:push-m     . ,(if keep 1 m))
        (:push-n     . ,(if keep 0 1))
        (:post-pop-n . ,(if keep 0 (pcase arity ('unary 0) ('binary 1))))))))
```

Notes:

- `:lhs` and `:rhs` are clean sub-formulas (no encasing — `at-equation-p`
  doesn't call `calc-prepare-selection`).
- `:rel-op` holds the relation symbol so commit can reassemble without
  re-parsing `:expr`.
- No `:expr-ref` needed — commit doesn't splice into a parent formula
  (it replaces the whole relation entry with a fresh `(rel-op lhs rhs)`
  list, no eq-based splice involved).
- `:reselect` omitted — no sub-formula selection to preserve.

## Macro changes — `maf-defcmd`

Current expansion (simplified):

```elisp
(defun ,name ()
  ...
  (let* ((context ...)
         (expr (alist-get :expr context))
         (arg  (alist-get :arg context)))
    (cl-flet ((commit (val) (maf--commit val context)))
      ,@body)))
```

Equation-aware expansion:

```elisp
(defun ,name ()
  ...
  (let* ((context ...)
         (arg (alist-get :arg context)))
    (if (eq (alist-get :target context) 'equation)
        ;; Equation branch: run body twice, capture into locals, reassemble.
        (let (g-lhs g-rhs)
          (cl-flet ((commit (val) (setq g-lhs val)))
            (let ((expr (alist-get :lhs context)))
              ,@body))
          (cl-flet ((commit (val) (setq g-rhs val)))
            (let ((expr (alist-get :rhs context)))
              ,@body))
          ;; Hand the reassembled relation to commit.
          (maf--commit (list (alist-get :rel-op context) g-lhs g-rhs)
                       context))
      ;; Normal branch: body runs once, commit goes straight through.
      (let ((expr (alist-get :expr context)))
        (cl-flet ((commit (val) (maf--commit val context)))
          ,@body)))))
```

Things to think about during implementation:

- **gensym hygiene.** `g-lhs` and `g-rhs` must be gensyms in the macro
  expansion to avoid clashing with anything the body might define. Same
  pattern as the existing `context` gensym in `maf-defcmd`.
- **body is inlined twice.** The body's code appears in two `cl-flet`
  blocks. Generally fine, but if the body has side effects beyond
  calling `commit`, they'll happen twice. Document this constraint
  (commands should be pure modulo the `commit` call).
- **`arg` is bound once, outside the per-side loop.** Both sides see the
  same arg, consistent with the decision above.
- **Validate that the body called `commit`.** If a side doesn't call it,
  `g-lhs` or `g-rhs` stays nil and the assembled relation has nils. Add
  a guard or just let it explode loudly — the latter is fine.

## Commit changes — `maf--commit`

Add an equation branch. It receives the already-assembled relation as
`val` and behaves like the entry target's commit (push at `:push-m`, post-pop
for binary):

```elisp
('equation
 (maf--commit-push push-n prefix val push-m nil post-pop-n))
```

That's it. The reassembly happens in the macro; commit just pushes the
result. The TODO marker can come off this branch.

## Schema doc updates

In `maf-resolve.el`'s top-of-file schema doc, add:

- `:rel-op` — Relation operator symbol for the equation target.
  Used by the macro to reassemble after per-side iteration.
- `:lhs` and `:rhs` — clean sub-formulas of the relation (equation
  target only). The body sees them via the per-side `expr` rebind.

Update `:m`'s description if needed (equation is the only other target
besides selection/subexpr that has it).

## Test plan

Add step-tests:

1. `human-test-square-at-equation.el` — entry like `x = 5`, unary square,
   expected `x^2 = 25`.
2. `human-test-mult-at-equation.el` — entry like `x = 5`, plus stack arg
   2, binary mult, expected `x*2 = 5*2` → `x*2 = 10` (after
   normalization).
3. `human-test-square-at-equation-keep.el` — same as #1 but with
   keep-args; verify the original equation stays and the result lands
   on top.
4. **Edge case**: binary on equation at `m=1` — expect the error.

Run them via `M-x load-file` or the existing `f4` test loader.

## Order of operations (for the future-me actually doing this)

1. Read this plan + skim [concepts.org](concepts.org) +
   [walkthrough.org](walkthrough.org) to reload the model.
2. Open the reference: `~/.emacs.d/my/calc/lib.el` "Branch 5: equation"
   — that's the prior art. Don't re-derive from scratch.
3. Implement in this order:
   1. `maf--resolve-target-equation` — fill out the schema fields.
   2. Schema doc update at the top of `maf-resolve.el`.
   3. `maf-defcmd` macro — add the equation branch in the expansion.
      Use gensyms for the per-side locals.
   4. `maf--commit`'s equation branch — push the reassembled val.
   5. Remove the TODO markers (`grep -rn "equation per-side iteration"`).
4. Write one human test (`human-test-square-at-equation.el`). Run it.
   Iterate until green.
5. Then the other tests (binary, keep, error).
6. Commit per file (this repo's convention).

## Open questions to revisit

- **Does `calc-prepare-selection` need to be called for equation?** I think
  no — equation operates on the whole relation, doesn't need sub-formula
  picking. But verify by tracing what `calc-top m 'full` returns and
  whether the body's operations work cleanly on it.
- **Equation containing duplicate atoms?** E.g., `1 + 1 = 2`. If lhs is
  `(+ 1 1)` and rhs is `2`, no eq-distinguishing concerns since we're
  splicing whole sides, not sub-formulas within them. Should be fine
  without encasing.
- **What about an equation as the body's `commit` val?** E.g., a command
  that computes `(calcFunc-eq lhs rhs)` and commits it. Unusual but
  legal. The per-side loop would call body twice and assemble
  `(rel-op (eq ...) (eq ...))`. Weird but not broken. Worth a test? Up
  to you.
