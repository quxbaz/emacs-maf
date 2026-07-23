---
name: drive
description: Test a change or feature in a live Emacs, preferring contexts close to human operation — real keypresses through the keymaps, the right window/frame, visible output. Use when testing or demonstrating a change interactively, reproducing an interactive bug, or confirming a fix batch mode can't reproduce.
---

# Driving a live Emacs

Prefer operating the way the user would: real keypresses through the
active keymaps, in the window the user would be in, judged by what
appears on screen. This is a preference, not a requirement — call
functions directly when that's necessary or just useful, and don't let
fidelity concerns block the actual task. Inspection and evaluation are
always direct calls.

Full techniques and pitfalls: `docs/memory/piloting-emacs.md` — read it
before nontrivial piloting. For maf work, always target this session's
dev-instance socket (`emacsclient -s <name> ...`; the name is chosen at
`emacs`, default `#emacs` — examples below use it), never the default
`server` socket. See the `emacs` skill for instance management.

## Core rules

1. To exercise keymaps as the user would, prefer real keypresses over
   calling command functions — they catch binding/precedence bugs a
   direct call would miss:

   ```elisp
   (with-selected-window (get-buffer-window "*Calculator*")
     (execute-kbd-macro (kbd "SPC")))
   ```

   Use `unread-command-events` when a full command-loop round trip is
   needed.

2. `--eval` runs in the internal `*server*` buffer, not the user's
   buffer. Wrap actions explicitly:

   ```elisp
   (with-selected-window (get-buffer-window "*Calculator*") ...)
   ```

   If the target buffer isn't in any window, display it first as a user
   would (`calc`, `pop-to-buffer`) rather than operating on it
   invisibly.

3. Each `--eval` is a fresh call — buffer/selection state does not
   persist between invocations. Put dependent sequences in one `--eval`
   or re-establish context each time.

4. Reload edited `.el` files before re-testing (see the `emacs`
   skill). When in doubt, inspect the loaded definition, not the file:
   `(symbol-function 'maf-step-next)`, `(macroexpand '(...))`.

## Verification loop

Edit → `load-file` into the instance → drive real keypresses in the
right window → read the result back with `--eval` → only then conclude.
Check what the user would see — buffer text, overlays/highlights, point
position — not just internal state like `(calc-top 1)`.

## Examples

Each example is a `/drive` prompt followed by the action it should
produce.

### [EXAMPLE 1] /drive open calc and do some arithmetic

```sh
# keys through the keymaps (rule 1), one --eval (rule 3),
# frame/window established explicitly (rule 2)
emacsclient -s '#emacs' --eval '(let ((gframe (seq-find (lambda (f) (frame-parameter f (quote window-system))) (frame-list))))
  (with-selected-frame gframe
    (calc)  ; ensure *Calculator* has a window
    (with-selected-window (get-buffer-window "*Calculator*")
      (execute-kbd-macro (kbd "1 2 RET 3 4 + 2 *")))
    (with-current-buffer "*Calculator*"
      (buffer-substring-no-properties (point-min) (point-max)))))'
```

```
"1:  92\n    .\n"     ; (12 + 34) * 2 visible at stack level 1
```

### [EXAMPLE 2] /drive what's on the calc stack?

```sh
# pure inspection — direct calls, no keypresses
emacsclient -s '#emacs' --eval '(with-current-buffer "*Calculator*"
  (list (calc-stack-size) (calc-top 1 (quote full))))'
```

### [EXAMPLE 3] /drive remove stale buffers

```sh
# maintenance — direct calls; find buffers visiting deleted files,
# then kill them
emacsclient -s '#emacs' --eval '(delq nil (mapcar (lambda (b)
    (let ((f (buffer-file-name b)))
      (and f (not (file-exists-p f)) (buffer-name b))))
  (buffer-list)))'
```

### [EXAMPLE 4] /drive is the latest maf-mult loaded?

```sh
# inspect the loaded definition, not the file (rule 4)
emacsclient -s '#emacs' --eval '(symbol-function (quote maf-mult))'
```
