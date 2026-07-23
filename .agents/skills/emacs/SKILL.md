---
name: emacs
description: Manage a dedicated maf dev Emacs instance — check it's running, launch it, load edited .el files into it, reset calc state, or restart it. Accepts an optional server name (`/emacs maf-refactor`) so multiple sessions/worktrees can each run their own instance; default is `#emacs`. Use at session start, after editing any .el file, or when the instance is stale, wedged, or needs a clean restart.
---

# Start a maf coding session

All interactive development and testing happens in a dedicated Emacs
instance with a private server, shared with the user. Canonical
reference: `docs/memory/dev-instance.md` — read it if anything here is
insufficient.

## Server name

This skill takes an optional argument: the server name for this
session's instance (e.g. `/emacs maf-refactor`). If no name is given,
use `#emacs`. The chosen name — call it `<name>` below — identifies
both the server socket and the frame title (quote it in shell commands:
`-s '#emacs'` — an unquoted `#` starts a comment), and **every** `emacsclient`
call for the rest of the session (including those in the `drive`,
`test`, and `port` skills, whose examples show `#emacs`) must use
`-s <name>`. Distinct names let multiple sessions, e.g. in separate
worktrees, each run their own instance side by side.

## Kickoff checklist (do this now)

1. Check whether the instance is already running:

   ```sh
   emacsclient -s <name> --eval t   # error => not running
   ```

2. If not running — or if this is a restart for a clean slate — launch
   it from the repo root (no `-Q`; the user's full config must load):

   ```sh
   cd <repo-root> && \
     MAF_SERVER_NAME=<name> \
     nohup emacs -title <name> -l agent/emacs-init.el >/dev/null 2>&1 &
   ```

3. Confirm it responds, then tell the user the session is ready and
   which server name it uses.

## Working agreement (in force for the rest of the session)

- **Load after every edit, unprompted.** Editing disk does not change
  the running Emacs. Immediately after every edit to an `.el` file:

  ```sh
  emacsclient -s <name> --eval '(load-file "src/maf-hl.el")'
  ```

  Relative paths resolve against the repo root. An unloaded edit means
  the user's next test silently exercises stale code.

- **All testing happens in this session's instance.** Never test in the
  user's main session (the default `server` socket), and never touch
  another session's instance. Driving and inspecting the instance is
  covered by the `drive` skill; the test convention by the
  `test` skill.

- **Reset calc state between tests with `calc-pop`.** The stack
  survives `kill-buffer` of `*Calculator*` (calc keeps it in global
  state), so popping is the reliable reset.

## Restarting for a clean slate

Needed after config-level changes that a `load-file` cannot apply
cleanly, or whenever the user asks for a fresh start. Kill by exact PID
only — never `pkill -f` (it self-matches your own shell), and never
touch the default `server` socket or other sessions' instances. The
launch title makes the name greppable:

```sh
pgrep -x emacs -a | grep 'title <name>' | awk '{print $1}' | xargs -r kill
```

Then relaunch with the kickoff command above.
