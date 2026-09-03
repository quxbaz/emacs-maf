# The maf dev instance

How development of maf is structured: all interactive development and
testing happens in a **dedicated Emacs instance** with a private server,
operated jointly by the user and the AI assistant. The user types in its
frame; the assistant drives and inspects it over `emacsclient -s <name>`.
Written for a future AI assistant working in this repo; general piloting
techniques are in [piloting-emacs.md](piloting-emacs.md).

The server name is chosen at session start (the `emacs` skill's
argument) and defaults to `#emacs`. Distinct names let multiple
sessions — e.g. in separate worktrees — each run their own instance side
by side. Examples below use `#emacs`; substitute the session's name.

## Initialization (start of a working session)

Check whether it is already running:

```sh
emacsclient -s '#emacs' --eval t   # error => not running
```

If not, launch it from the session's repo root (this is part of session
initialization). `MAF_SERVER_NAME` sets the server name; omit it for the
default `#emacs`:

```sh
cd "$(git rev-parse --show-toplevel)" && \
  MAF_SERVER_NAME='#emacs' \
  nohup emacs -title '#emacs' -l agent/emacs-init.el >/dev/null 2>&1 &
```

Properties, all deliberate:

- **No `-Q`** — the user's full config loads; behavior must be tested
  against the real config, not a sterile one.
- **Launched from the project root**, so every buffer's
  `default-directory` is the repo.
- **Private server name** (from `MAF_SERVER_NAME`, default `#emacs`) —
  the default `server` socket belongs to the user's main session
  (`emacs_d-1`); never test there, and never kill it. Other sessions'
  instances are equally off-limits. Verify socket ownership with `lsof`
  before touching anything.
- `agent/emacs-init.el` only makes joint agent/human operation
  work: it names and starts the private server. The project-level setup
  — loading `maf.el`, opening calc with `maf-mode` (and therefore the
  mafcmd keymap) enabled, seeding, window layout — comes from
  `project-init.el`, which the user's config loads.

## Working loop

1. Edit `.el` files in the repo.
2. Load every edited file into the instance **immediately after editing
   it** — do this unprompted, as part of the edit itself. Editing disk
   does not change the running Emacs (piloting-emacs.md pitfall 3), and
   an unloaded edit means the next joint test silently exercises stale
   code: `emacsclient -s '#emacs' --eval '(load-file "modules/maf-hl.el")'`
   (relative paths resolve against the repo root).
3. Exercise the change: the user types in the frame, or the assistant
   drives real keypresses (`execute-kbd-macro`, or `unread-command-events`
   for a full command-loop round trip) and reads state back with `--eval`.
4. For highlight work, `debug/maf-hl-verify.el` and `debug/maf-hl-sweep.el`
   run inside this instance.

`load-file` does not restyle a `defface` the instance already has:
`custom-declare-face` keeps the existing face and only refreshes it for
a face it has never seen. After editing a face spec, force it:

```sh
emacsclient -s '#emacs' --eval '(progn (put (quote maf-history-separator) (quote face-defface-spec) nil)
  (load-file "modules/maf-history.el")
  (face-spec-set (quote maf-history-separator)
                 (get (quote maf-history-separator) (quote face-defface-spec))))'
```

Reset calc state between tests with `calc-pop` — note the stack survives
`kill-buffer` of `*Calculator*` (calc keeps it in global state), so
popping is the reliable reset.

Copies made through `--eval` must not touch the X clipboard, and
`agent/emacs-init.el` binds `select-enable-clipboard` off around every
server eval to keep them from it. Emacs stamps a clipboard claim with
its last user-event time; an eval has none, so the stamp is stale, the X
server refuses the claim, and Emacs records itself as owner regardless.
From then on `C-y` never asks the server (`gui-last-cut-in-clipboard`
short-circuits it) and the user's yanks in this instance stop seeing
other apps' copies. If it happens anyway — an instance started before
the guard — clear it with
`emacsclient -s '#emacs' --eval '(x-disown-selection-internal (quote CLIPBOARD))'`.

## Cleanup / restart

Kill by exact PID only (`pkill -f` self-matches the assistant's shell);
the launch title makes the session's name greppable:

```sh
pgrep -x emacs -a | grep 'title #emacs' | awk '{print $1}' | xargs -r kill
```

Restart with the launch command above (e.g. after config-level changes
that a `load-file` cannot apply cleanly).
