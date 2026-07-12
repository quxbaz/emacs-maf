# maf

An alternative UX over Emacs Calc: contextual commands that resolve point
and calc state into a target (home, entry, selection, subexpr, equation)
and commit results back to the right place.

## Initialization (every session)

Development and testing happen in a dedicated live Emacs instance with a
private server named `maf-dev`, operated jointly with the user. As your
first action, ensure it is running:

```sh
emacsclient -s maf-dev --eval t   # error => not running
```

If it is not, launch it from the repo root:

```sh
nohup emacs -title maf-dev -l debug/maf-dev-init.el >/dev/null 2>&1 &
```

Full workflow, properties, and pitfalls: `docs/memory/dev-instance.md`.
General techniques for piloting a live Emacs: `docs/memory/piloting-emacs.md`.

## Rules

- After every edit to an `.el` file, immediately load it into the maf-dev
  instance (`emacsclient -s maf-dev --eval '(load-file "...")'`) without
  being asked. The user tests in that instance; an unloaded edit means
  they exercise stale code.
- Never test in the user's main Emacs session (the default `server`
  socket). Kill Emacs processes only by exact PID — `pkill -f`
  self-matches your own shell.
- Known upstream calc behavior maf deliberately mirrors:
  `docs/memory/calc-selection-quirks.md`.
