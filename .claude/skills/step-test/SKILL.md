---
name: step-test
description: Write or run a maf step test — the project's test convention using maf-defcmd plus a maf-step block, stepped through interactively in the maf-dev instance. Use when adding tests for a maf command, verifying a change, or asked to write tests.
---

# Step tests

A step test is a single `.el` file containing a `maf-defcmd` definition
and a `maf-step` block of forms with `cl-assert` checks. The test passes
if no form signals an error. Format reference: `tests/README.md`;
existing examples: `tests/*.el` (e.g. `tests/mult-at-home.el`).

```elisp
(maf-defcmd maf-mult (expr arg commit)
  "Multiplication command."
  :arity binary
  :prefix "mult"
  (commit (calcFunc-mul expr arg)))

(maf-step
  (calc-push 3)
  (calc-push 2)
  (call-interactively 'maf-mult)
  (cl-assert (= (calc-stack-size) 1))
  (cl-assert (equal (calc-top 1 'full) 6)))
```

## Where tests live

- `tests/` (a.k.a. step-tests) — the user's interactive tests, stepped
  through by hand with the `*maf-step*` cockpit (`f4` loader; `l`/`j`/
  `SPC` forward, `h`/`k` back, `r` restart, `q` quit).
- `ai-tests/` — where the AI writes its own verification tests. Create
  it if it does not exist; do not mix AI scratch tests into `tests/`.

## Running a test as the AI

Load the file into the maf-dev instance and check the cockpit runs
clean (`maf-step` machinery is in `debug/maf-step.el`):

```sh
emacsclient -s maf-dev --eval '(load-file "ai-tests/foo.el")'
```

Then step it or read back the `*maf-step*` buffer state via `--eval`
(see the `pilot` skill). Reset calc between tests with `calc-pop` — the
stack survives killing `*Calculator*`.

Known upstream calc behavior that maf deliberately mirrors (don't
"fix" it in tests): `docs/memory/calc-selection-quirks.md`.
