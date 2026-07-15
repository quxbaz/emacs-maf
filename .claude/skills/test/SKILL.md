---
name: test
description: Write and/or run a maf step test — the project's test convention using maf-defcmd plus a maf-step block, stepped through interactively in the maf-dev instance. Use when adding tests for a maf command, verifying a change, or asked to write tests. A newly written test is always run immediately; bare /test reruns the last test.
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

- `tests/` (a.k.a. step-tests) — durable tests, executed repeatedly and
  sometimes as part of a suite; stepped through by hand with the
  `*maf-step*` cockpit (`f4` loader; `l`/`j`/`SPC` forward, `h`/`k`
  back, `r` restart, `q` quit).
- `agent-sandbox/` — semi-permanent sandbox area for the agent,
  used for a flexible number of purposes including testing. Write
  agent verification tests here; do not mix them into `tests/`.

## Running a test as the AI

Load the file into the maf-dev instance and check the cockpit runs
clean (`maf-step` machinery is in `debug/maf-step.el`):

```sh
emacsclient -s maf-dev --eval '(load-file "agent-sandbox/foo.el")'
```

Then step through it with real keypresses in the `*maf-step*` window
(one `SPC` per form; see the `drive` skill) and read the buffer back.
Success is `[N/N] ##### DONE` in the header with no `ERROR`; a failing
form renders a `;;!` line beneath it. No manual calc reset is needed —
`maf-step` creates a fresh calc per session.

Invoked bare (`/test` with no prompt): rerun the last test — press `r`
(`maf-step-restart`) in the `*maf-step*` window and step through again;
if the cockpit is gone, reload the last test file that was run.

Known upstream calc behavior that maf deliberately mirrors (don't
"fix" it in tests): `docs/memory/calc-selection-quirks.md`.

## Examples

Each example is a `/test` prompt followed by the action it should
produce.

### [EXAMPLE 1] /test test mafcmd-factor-gcd; make sure it works with a wide variety of expressions

The command already exists in maf, so no `maf-defcmd` is needed. Write
`agent-sandbox/factor-gcd-variety.el` with a `maf-step` block covering
distinct expression shapes — one commented case per shape, `calc-pop`
between cases (cf. the user's `tests/factor-gcd.el`):

```elisp
(maf-step
  ;; Basic: pull the GCD out of a sum.
  (maf-push "6 x + 12")
  (call-interactively 'mafcmd-factor-gcd)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "6 (x + 2)"))
  (calc-pop (calc-stack-size))

  ;; ... more cases: subtraction nodes, negative leading terms,
  ;; coprime/single-term pass-throughs, multivariate expressions.
  )
```

"Wide variety" means distinct shapes, not many similar inputs. Then
load and step it as in the next example.

### [EXAMPLE 2] /test write a test for an addition command at home

Write `agent-sandbox/add-at-home.el` in the format above (a `maf-defcmd`
for `maf-add` committing `calcFunc-add`, then a `maf-step` block
pushing 3 and 4 and asserting the top is 7), then load and step it:

```sh
emacsclient -s maf-dev --eval '(load-file "agent-sandbox/add-at-home.el")'
# one SPC per form, then read the cockpit back
emacsclient -s maf-dev --eval '(with-selected-window (get-buffer-window "*maf-step*" t)
  (execute-kbd-macro (kbd "SPC SPC SPC SPC SPC"))
  (buffer-substring-no-properties (point-min) (point-max)))'
```

```
;; maf-step: add-at-home.el
;; [5/5] ##### DONE          <- pass: DONE, no ERROR
;; flags: [option=0] [hyper=0] [keep=0]

(calc-push 3)  ;; => nil
...
```

### [EXAMPLE 3] /test run mult-at-home

Same flow against the user's existing test:

```sh
emacsclient -s maf-dev --eval '(load-file "tests/mult-at-home.el")'
```

Step with `SPC` as above; report pass/fail from the header and quote
any `;;!` failure lines.

### [EXAMPLE 4] /test

No prompt — rerun the last test:

```sh
emacsclient -s maf-dev --eval '(with-selected-window (get-buffer-window "*maf-step*" t)
  (execute-kbd-macro (kbd "r SPC SPC SPC SPC SPC"))
  (buffer-substring-no-properties (point-min) (point-max)))'
```
