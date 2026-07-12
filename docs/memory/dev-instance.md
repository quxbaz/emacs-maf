# The maf-dev instance

How development of maf is structured: all interactive development and
testing happens in a **dedicated Emacs instance** with a private server
named `maf-dev`, operated jointly by the user and the AI assistant. The
user types in its frame; the assistant drives and inspects it over
`emacsclient -s maf-dev`. Written for a future AI assistant working in
this repo; general piloting techniques are in
[piloting-emacs.md](piloting-emacs.md).

## Initialization (start of a working session)

Check whether it is already running:

```sh
emacsclient -s maf-dev --eval t   # error => not running
```

If not, launch it (this is part of session initialization):

```sh
cd /home/david/lab/emacs-maf && \
  nohup emacs -title maf-dev -l debug/maf-dev-init.el >/dev/null 2>&1 &
```

Properties, all deliberate:

- **No `-Q`** — the user's full config loads; behavior must be tested
  against the real config, not a sterile one.
- **Launched from the project root**, so every buffer's
  `default-directory` is the repo.
- **Private server name** `maf-dev` — the default `server` socket
  belongs to the user's main session (`emacs_d-1`); never test there, and
  never kill it. Verify socket ownership with `lsof` before touching
  anything.
- `debug/maf-dev-init.el` loads the repo's `maf.el` fresh and opens calc
  with `maf-mode` (and therefore the mafcmd keymap) enabled.

## Working loop

1. Edit `.el` files in the repo.
2. Load every edited file into the instance **immediately after editing
   it** — do this unprompted, as part of the edit itself. Editing disk
   does not change the running Emacs (piloting-emacs.md pitfall 3), and
   an unloaded edit means the next joint test silently exercises stale
   code: `emacsclient -s maf-dev --eval '(load-file "src/maf-hl.el")'`
   (relative paths resolve against the repo root).
3. Exercise the change: the user types in the frame, or the assistant
   drives real keypresses (`execute-kbd-macro`, or `unread-command-events`
   for a full command-loop round trip) and reads state back with `--eval`.
4. For highlight work, `debug/maf-hl-verify.el` and `debug/maf-hl-sweep.el`
   run inside this instance.

Reset calc state between tests with `calc-pop` — note the stack survives
`kill-buffer` of `*Calculator*` (calc keeps it in global state), so
popping is the reliable reset.

## Cleanup / restart

Kill by exact PID only (`pkill -f` self-matches the assistant's shell):

```sh
pgrep -x emacs -a | grep maf-dev | awk '{print $1}' | xargs -r kill
```

Restart with the launch command above (e.g. after config-level changes
that a `load-file` cannot apply cleanly).
