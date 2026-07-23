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
