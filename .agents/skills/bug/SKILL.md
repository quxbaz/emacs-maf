---
name: bug
description: Reproduce and diagnose a bug the user has captured as a keyboard macro in the dev instance — examine the recorded keys, replay them, compare the result against the reported symptom, isolate the failing step. Use when invoked as `/bug <symptom>`; the prompt describes what goes wrong, the last recorded macro is the repro.
---

# Bug repro from a recorded kbd macro

The user records a keyboard macro in this session's dev instance that
reproduces a bug, then invokes `/bug <symptom>`. The macro is the
repro; the prompt is the symptom. Diagnose and report the root cause —
fix only when asked, and then the macro doubles as verification. All
`emacsclient` calls use this session's socket (chosen at `emacs`,
default `#emacs` — examples use it).

## Flow

1. **Fetch the macro:**

   ```sh
   emacsclient -s '#emacs' --eval '(key-description last-kbd-macro)'
   ```

   nil or void => nothing recorded; ask the user to record one and
   stop. If the user says the last macro isn't the repro, older ones
   are on `kmacro-ring`.

2. **Examine before playing.** Resolve each key to its command in the
   buffer the macro targets:

   ```sh
   emacsclient -s '#emacs' --eval '(with-current-buffer "*Calculator*"
     (key-binding (kbd "C-c d")))'
   ```

   Work out which maf commands run, what starting state the macro
   assumes (does it push its own operands, or operate on what's
   already on the stack / at point?), and what the correct result
   would be.

3. **Establish the starting state.** The current state is the
   aftermath of the user's buggy run — don't replay on top of it
   blindly. If the macro is self-contained, reset calc first
   (`(calc-pop (calc-stack-size))`); otherwise recreate the state it
   assumes from the keys and the symptom description.

4. **Play it** per the `drive` skill's rules — graphical frame, the
   window the user recorded it in (default: the frame's selected
   window, since the user was just there):

   ```sh
   emacsclient -s '#emacs' --eval '(let ((gframe (seq-find (lambda (f) (frame-parameter f (quote window-system))) (frame-list))))
     (with-selected-frame gframe
       (with-selected-window (frame-selected-window gframe)
         (execute-kbd-macro last-kbd-macro))
       (with-current-buffer "*Calculator*"
         (buffer-substring-no-properties (point-min) (point-max)))))'
   ```

   Read back what the user would see — buffer text, stack, highlights
   — and state expected vs actual. If the symptom doesn't reproduce,
   say so; a wrong starting state is the usual culprit.

5. **Isolate.** Replay prefixes of the key sequence
   (`(execute-kbd-macro (kbd "..."))` with leading keys from the
   `key-description`), resetting state between replays, until the
   step where behavior diverges. Then read that command's source and
   report the cause.

When asked to fix: edit → load the file (`emacs` skill) → reset state
→ replay the macro → confirm the correct result.

## Examples

Each example is a `/bug` prompt followed by the action it should
produce.

### [EXAMPLE 1] /bug multiplies instead of divides

```sh
emacsclient -s '#emacs' --eval '(key-description last-kbd-macro)'
# => "8 RET 2 C-c d"
```

`C-c d` in `*Calculator*` resolves to (say) `mafcmd-div`. The macro
pushes its own operands, so it's self-contained: reset calc, replay,
read the stack. Top shows `16`, expected `4` — reproduced. Read
`mafcmd-div`'s definition, report where it multiplies.

### [EXAMPLE 2] /bug wrong subexpr gets selected

```sh
emacsclient -s '#emacs' --eval '(key-description last-kbd-macro)'
# => "C-c s"   — no operands pushed: not self-contained
```

The macro assumes an expression already on the stack with point
somewhere in it. Recreate that state (push the expression the user
was working with; ask if the keys and symptom don't pin it down),
replay in the calc window, and read back the selection/highlight the
user would see, not just `(calc-top 1)`.

### [EXAMPLE 3] /bug

No symptom given: examine and replay the macro as above, then report
what it does and what looks wrong in the result.
