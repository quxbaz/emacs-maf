---
name: port
description: Port a command, function, feature, or object from the user's legacy Calc config (~/.emacs.d/my/calc/) into this package. Use when asked to port, migrate, or bring over a my/calc-* feature into maf.
---

# Porting from ~/.emacs.d/my/calc

The user's previous Calc customization lives in `~/.emacs.d/my/calc/`
(`stack.el`, `edit.el`, `rewrite.el`, `bindings.el`, `lib.el`, ...),
with functions named `my/calc-*`. Given a feature name, find it there
and port it into maf:

```sh
grep -rn "factor-by-gcd" ~/.emacs.d/my/calc/
```

Grep loosely — the requested name may not match the old name exactly.
Pull in everything the feature needs: helper functions, variables, and
its keybinding in `~/.emacs.d/my/calc/bindings.el`.

## Rules

- **The original is a draft, not a spec.** Do not assume the feature is
  100% correct and working as is. Read it critically; fix bugs and
  handle missed edge cases as part of the port, and mention what you
  changed.
- **Re-implement in maf conventions, don't transplant.** Commands
  become contextual `maf-defcmd`s (`mafcmd-*`) that resolve point/calc
  state into a target and commit back; helpers are `maf--*`. Match the
  style of the destination file in `src/`; bindings go in
  `src/bindings.el` on `maf-mode-map`.
- **Check for an existing maf counterpart first.** Part of the feature
  may already be ported or superseded; extend rather than duplicate.
- Claims about upstream Calc behavior get checked against the local
  source/manual (see the `ref` skill).

## Verify

After porting: load the file into #emacs (see the `emacs` skill),
write and run a step test in `agent-sandbox/` covering the feature's
distinct input shapes (see the `test` skill), and exercise any new
binding with real keypresses (see the `drive` skill).

## Examples

### [EXAMPLE 1] /port factor-by-gcd

```sh
grep -rn "factor-by-gcd" ~/.emacs.d/my/calc/
```

Finds `my/calc-factor-by-gcd` in `stack.el` plus its binding in
`bindings.el`. Read it and its helpers, note weaknesses (e.g. no
handling of negative leading terms), then write `mafcmd-factor-gcd` as
a `maf-defcmd` in `src/stack.el` fixing them, bind it in
`src/bindings.el`, load, and test with a variety of expression shapes.

### [EXAMPLE 2] /port the calc debug buffer

Not a command but a feature: `debug.el` defines `my/calc-debug-mode`
and a `*calc-debug*` buffer. Port the mode, its buffer machinery, and
helpers as a coherent unit into an appropriate `src/` file, adapting
names and any stale assumptions about buffer-local calc state.
