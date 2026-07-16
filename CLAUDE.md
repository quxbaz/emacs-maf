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
  nohup emacs -title '#emacs' -l debug/maf-dev-init.el >/dev/null 2>&1 &
```

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
