# step-tests

Step-through tests for maf, run by hand in a live Emacs session (not headless).

Each file defines a command with `maf-defcmd` and a `maf-step` block. Loading
the file (e.g. `eval-buffer`, or your `f4` loader) opens the `*maf-step*`
cockpit against a fresh calc: step forward with `l`/`j`/`SPC`, back with
`h`/`k`, restart with `r`, quit with `q`. Each form's return value, `*Messages*`
output, and any error render beneath it; the header shows progress and the calc
flag states.

A test **passes if no error is raised** — the `cl-assert` forms simply signal on
failure, surfacing as a `;;!` line and `ERROR` in the header.
