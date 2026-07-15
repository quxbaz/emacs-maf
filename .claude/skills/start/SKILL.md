---
name: start
description: Manage the dedicated maf-dev Emacs instance — check it's running, launch it, load edited .el files into it, reset calc state, or restart it. Use at session start, after editing any .el file, or when the instance is stale, wedged, or needs a clean restart.
---

# Start a maf coding session

All interactive development and testing happens in a dedicated Emacs
instance with a private server named `maf-dev`, shared with the user.
Canonical reference: `docs/memory/dev-instance.md` — read it if anything
here is insufficient.

## Kickoff checklist (do this now)

1. Check whether the instance is already running:

   ```sh
   emacsclient -s maf-dev --eval t   # error => not running
   ```

2. If not running — or if this is a restart for a clean slate — launch
   it from the repo root (no `-Q`; the user's full config must load):

   ```sh
   cd /home/david/lab/emacs-maf && \
     nohup emacs -title maf-dev -l debug/maf-dev-init.el >/dev/null 2>&1 &
   ```

3. Confirm it responds, then tell the user the session is ready.

## Working agreement (in force for the rest of the session)

- **Load after every edit, unprompted.** Editing disk does not change
  the running Emacs. Immediately after every edit to an `.el` file:

  ```sh
  emacsclient -s maf-dev --eval '(load-file "src/maf-hl.el")'
  ```

  Relative paths resolve against the repo root. An unloaded edit means
  the user's next test silently exercises stale code.

- **All testing happens in maf-dev.** Never test in the user's main
  session (the default `server` socket). Driving and inspecting the
  instance is covered by the `pilot` skill; the test convention by the
  `step-test` skill.

- **Reset calc state between tests with `calc-pop`.** The stack
  survives `kill-buffer` of `*Calculator*` (calc keeps it in global
  state), so popping is the reliable reset.

## Restarting for a clean slate

Needed after config-level changes that a `load-file` cannot apply
cleanly, or whenever the user asks for a fresh start. Kill by exact PID
only — never `pkill -f` (it self-matches your own shell), and never
touch the default `server` socket:

```sh
pgrep -x emacs -a | grep maf-dev | awk '{print $1}' | xargs -r kill
```

Then relaunch with the kickoff command above.
