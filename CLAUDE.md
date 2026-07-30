# maf

An alternative UX over Emacs Calc: contextual commands that resolve point
and calc state into a target (home, entry, selection, subexpr, equation)
and commit results back to the right place.

## Initialization (every session)

Development and testing happen in a dedicated live Emacs instance with a
private server, operated jointly with the user. The server name is
per-session (the `emacs` skill's argument; default `#emacs`), so
multiple sessions — e.g. in separate worktrees — can each run their own
instance. As your first action, ensure this session's instance is
running:

```sh
emacsclient -s '#emacs' --eval t   # error => not running
```

If it is not, launch it from the repo root:

```sh
MAF_SERVER_NAME='#emacs' \
  nohup emacs -title '#emacs' -l agent/emacs-init.el >/dev/null 2>&1 &
```

In a dev container (`$MAF_CONTAINER` set), the instance is already
running under tmux, in a pane beside your shell, and its server name is
the default `#emacs` — do not launch Emacs, just use it. Setup:
`docker/README.md`.

Full workflow, properties, and pitfalls: `docs/memory/dev-instance.md`.
General techniques for piloting a live Emacs: `docs/memory/piloting-emacs.md`.

## Rules

- After every edit to an `.el` file, immediately load it into the dev
  instance (`emacsclient -s <name> --eval '(load-file "...")'`) without
  being asked. The user tests in that instance; an unloaded edit means
  they exercise stale code.
- Never test in the user's main Emacs session (the default `server`
  socket), and never touch another session's instance. Kill Emacs
  processes only by exact PID — `pkill -f` self-matches your own shell.
- Known upstream calc behavior maf deliberately mirrors:
  `docs/memory/calc-selection-quirks.md`.
- `tests/` is the suite — every file is expected to pass against current
  `main`, and a landing feature puts its step test there. `sandbox/` is
  scratch: same `maf-step` form, but nothing sweeps it, so a file there
  may drive a renamed command or assert an answer that is no longer
  given. Never cite a sandbox file as evidence of current behavior
  without running it. Details, and when a draft has earned a move into
  `tests/`: `tests/README.md`.
