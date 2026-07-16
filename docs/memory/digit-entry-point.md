# Digit entry destroys point context (and the no-align fix)

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
