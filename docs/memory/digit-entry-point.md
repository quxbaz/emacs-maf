# Digit entry: point context and undo granularity

Two symptoms of the same seam — a minibuffer digit entry completed by
a command key is one gesture to the user, but calc treats the push and
the command as unrelated events.

Discovered 2026-07-16 via a `1 +` kbd macro run with point at the EOL of
a stack entry: the add targeted the top of the stack instead of the
entry at point.

## The problem

Typing a digit in calc starts a minibuffer numeric entry. When the entry
completes, the push runs through `calc-do`, whose epilogue calls
`calc-align-stack-window` and parks point at home (`calc.el:1664` in the
calc source — skipped only when `no-align` is in `calc-command-flags`).
A command key like `+` that terminates the entry is re-dispatched *after*
that, so a contextual command resolves home, not the position the user
was on:

    2:  6 x + 12      <- point here, type "1 +"
    1:  x = y

    expected: 6 x + 13 committed to the entry
    actual:   1 added to `x = y` (home target: expr = top 2, arg = top 1)

Any `<digit>... <op>` sequence from an entry or subexpr position
mistargets this way.

## The fix (src/minibuffer.el)

`maf--digit-entry-keep-point`, a `:before` advice on
`calcDigit-nondigit`, sets the `no-align` command flag so the entry's
push never moves point. The entry's *row* survives the push — only its
level number changes (`2:` -> `3:`) — so the terminating command
resolves the same formula the user was standing on.

Point still goes home when:

- it already was at home (normal RPN flow unchanged), or
- RET or SPC completed the entry (a deliberate "push at home"), or
- `maf-mode` is off in the calc buffer (stock calc untouched).

Ported from the user's pre-maf config (`~/.emacs.d/my/calc/`
minibuffer.el), which carried the same advice unconditionally; the
maf-mode gate is new.

## Undo granularity: the hanging arg (2026-07-16)

The push is also its own undo unit, so `1 + U` on an entry reverted
the add but left the `1` stranded on the stack. Fix: the
`calcDigit-nondigit' advice records how the entry completed in
`maf--digit-entry-handoff` (t for a command key, nil for RET/SPC —
self-clearing on every entry), and every *binary* defcmd calls
`maf--undo-amalgamate-digit-entry` (core/maf-lib.el) after its
`calc-wrapper`: when the handoff flag is set and `last-command` is
still one of the calcDigit-* entry commands, the push's undo group is
folded into the command's on `calc-undo-list`. One `U` then reverts
the whole gesture, and one `D` replays it — merged groups survive
undo/redo cycles because calc moves groups wholesale.

Deliberate pushes keep their own unit: `1 RET` clears the flag, so a
later `+` undoes classically (operands restored to the stack).

Beware: `last-command` after a digit entry is `calcDigit-key` (or
`calcDigit-start` for a single-digit entry) — not the key that
terminated the entry.

## Testing

Not covered by a step test: the behavior lives in the minibuffer
round-trip (`calcDigit-start` -> `calcDigit-nondigit` -> re-dispatched
command), which the `*maf-step*` cockpit cannot exercise faithfully.
Verify live with real keypresses: place point at an entry's EOL, run
`execute-kbd-macro (kbd "1 +")` in the calc window, and check the entry
changed in place, the stack size is back to its starting value, and
point is still on the entry's line. Also check the exemptions: `5 RET`
from an entry line and any digit entry at home must both leave point at
home.

For the undo amalgamation: `1 + U` at an entry must leave the stack
size unchanged with no stranded `1`, a following `D` must replay the
whole gesture, and `7 RET 1 RET + U` must still restore both operands
(separate units).
