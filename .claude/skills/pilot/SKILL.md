---
name: pilot
description: Drive and inspect a live Emacs over emacsclient — send real keypresses, evaluate elisp in the right window/frame, verify visibly. Use when reproducing interactive bugs, exercising keymaps, or confirming a fix that batch mode can't reproduce.
---

# Piloting a live Emacs

Full techniques and pitfalls: `docs/memory/piloting-emacs.md` — read it
before nontrivial piloting. For maf work, always target the `maf-dev`
socket (`emacsclient -s maf-dev ...`), never the default `server`
socket. See the `maf-dev` skill for instance management.

## Core rules

1. `--eval` runs in the internal ` *server*` buffer, not the user's
   buffer. Wrap actions explicitly:

   ```elisp
   (with-selected-window (get-buffer-window "*Calculator*") ...)
   ```

2. Each `--eval` is a fresh call — buffer/selection state does not
   persist between invocations. Put dependent sequences in one `--eval`
   or re-establish context each time.

3. To exercise keymaps as the user would, dispatch real keypresses
   instead of calling command functions:

   ```elisp
   (with-selected-window (get-buffer-window "*Calculator*")
     (execute-kbd-macro (kbd "SPC")))
   ```

   Use `unread-command-events` when a full command-loop round trip is
   needed.

4. Reload edited `.el` files before re-testing (see the `maf-dev`
   skill). When in doubt, inspect the loaded definition, not the file:
   `(symbol-function 'maf-step-next)`, `(macroexpand '(...))`.

## Verification loop

Edit → `load-file` into the instance → drive real keypresses in the
right window → read state back with `--eval` → only then conclude.
