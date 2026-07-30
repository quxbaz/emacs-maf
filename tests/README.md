# step-tests

Step-through tests for maf, run by hand in a live Emacs session (not headless).

Each file contains a `maf-step` block and may define a command with
`maf-defcmd` when the command itself is part of the test. Loading the file
(e.g. `eval-buffer`, or your `f4` loader) opens the `*maf-step*` cockpit
against a fresh calc: step forward with `j`/`SPC`, back with `k`, restart with
`r`, show help with `?`, quit with `q`. Each form's return value, `*Messages*`
output, and any error render beneath it; the header shows progress and the
calc flag states.

A test **passes if no error is raised** — the `cl-assert` forms simply signal on
failure, surfacing as a `;;!` line and `ERROR` in the header.

## tests/ vs sandbox/

Both hold `maf-step` blocks, so they look alike. The difference is what
they are for, and it decides where a file belongs.

**`tests/` is the suite.** Every file here is expected to pass against
current `main`, forever. A landing feature puts its file here; a change
that breaks one is a regression until argued otherwise. Sweeping the
directory is how the suite gets run:

```sh
for f in tests/*.el; do
  emacsclient -s '#emacs' --eval "(progn (load-file \"$f\") (maf-step-last)
    (list \"$f\" maf--step-total maf--step-errored))"
done
```

**`sandbox/` is scratch.** Files here are drafts kept while a command is
being worked out — a place to drive something before it has a shape worth
keeping. Nothing sweeps them, so they rot silently: a sandbox file may
target a command that has since been renamed, or assert an answer the
command no longer gives. Do not treat a sandbox file as a statement about
current behavior without running it first.

A draft that has grown into a real check belongs in `tests/`: it passes,
it names its expectations, and it covers something no other file does.
Move it (`git mv`) rather than copying, so there is one home per check.
Two files may cover one command from different angles — `del.el` on where
point lands after a deletion, `del-targets.el` on what each target
actually removes; the test is whether each says something the other does
not.
