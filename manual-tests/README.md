# manual-tests

Scripts for manually observing maf behavior in a live Emacs session.
These are not part of any automated test suite and are not meant to be run headlessly.

Each file sets up a calc buffer, executes a command via `maf-defcmd`, and produces a
visible result for a human to inspect. Load a file with `eval-buffer` while Emacs is
running to exercise the scenario.
