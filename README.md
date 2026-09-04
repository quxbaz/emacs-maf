# maf

An alternative UX over Emacs Calc. One key does the right thing wherever point is: on the home line, on a stack entry, on a sub-expression, on a calc selection, on one side of an equation, or on a region of a sum. The result goes back where it came from, and point stays put.

Website: the `public/` directory holds a static site with an overview, a five-minute intro, worked examples, the modules, a key bindings cheat sheet with hover help and optional LaTeX rendering, and the additions and changes both compiled by subject and listed commit by commit. Open `public/index.html` in a browser.

## What "contextual" means

A stock Calc command takes its operand from the top of the stack. A maf command first *resolves* point and the calc state into a target, runs its body on exactly that, then *commits* the result to the same place. The targets, in priority order:

| Target | When it fires | Operates on |
|---|---|---|
| region | An active region inside one entry | The run of terms it covers in a `+` or `*` chain |
| selection | A calc selection exists | The selected sub-formula |
| home | Point is on the `.` line | The top stack entry |
| subexpr | Point is inside a formula | The sub-formula under point |
| equation | Point is on a relation | Each side, the body running once per side |
| entry | Point is on an entry's edge | The whole formula |

With `x^2 + 2 x + 1 = 4` on the stack, `a f` with point on the left side factors that side in place. At home, it factors the whole entry.

Calc's `I` and `H` prefixes route each command to a sibling, so `I S` takes the arcsine of the resolved sub-expression. maf adds a third flag, `M`: the next command maps over its subject, once per element of a vector or once per side of a relation. `M r` and `M c` choose rows or columns of a matrix.

## Features

- **About 220 contextual commands** covering arithmetic, algebra and rewriting, equations and solving, calculus, trig and angles, logs, complex numbers, combinatorics, special functions, vectors and sets, statistics, binary and finance, and dates. Each command's targeting policy is a variable you can retune.
- **Live highlight of the target.** The innermost sub-formula under point is highlighted as you move.
- **Regions over chains.** Calc has no node for `b + c` inside `a + b + c + d`. maf carves the run out, rewrites it, and splices it back.
- **Entry and editing are one gesture.** `SPC` opens the stack as editable text, wdired style; type a new formula or change one, and `RET` commits. Newlines split and join entries. A handwriting dialect reads `2xy` as `2 x y`. In-entry shortcuts wrap, retype, and duplicate groups.
- **The map flag and combinators.** `M` maps any contextual command. Fold, accumulate, apply, outer and inner products read their operation from the next key.
- **Three key profiles.** `calc` keeps Calc's layout and swaps in maf's commands. `native`, the default, is maf's own layout. `vim` puts it under `h j k l` motions. Your own bindings sit above and are never rewritten.
- **Discoverability.** `l b` lists every bound command with a proper name and a worked example. `?` shows all of Calc's settings in one table. `m c` is the module menu. `s o` opens a formula library.
- **History and persistence.** `M-h` browses every past stack state beside the log that produced it. An opt-in module restores the stack across sessions.
- **Previews and typesetting.** A panel follows point showing the entry in Calc's two-dimensional display. With RaTeX, `G` typesets the entry as an SVG.
- **Plotting three ways.** gnuplot embedded as an SVG, Desmos in the browser, or an interactive gnuplot window.
- **Paper-style output.** Toggleable modules keep polynomials in descending order, write `exp(x)` as `e^x`, and add general-base log identities.
- **Upstream fixes included.** Two Calc selection bugs are fixed on the way through. See `docs/memory/calc-selection-quirks.md`.

## Install

Requires Emacs 28.1 or later. Nothing else is required.

```
M-x package-vc-install RET https://github.com/quxbaz/emacs-maf RET
```

Or clone and add the directory to the load path. `maf.el` adds its own subdirectories.

```elisp
(add-to-list 'load-path "~/src/emacs-maf")
(require 'maf)
(add-hook 'calc-mode-hook #'maf-mode)
```

With use-package on Emacs 30:

```elisp
(use-package maf
  :vc (:url "https://github.com/quxbaz/emacs-maf")
  :hook (calc-mode . maf-mode))
```

Pick a profile with `(setq maf-bindings-profile 'vim)` before loading, or `M-x maf-bindings-set-profile` in a session. Modules start according to `maf-modules`; `maf-persist` and `maf-pretty` are off by default.

```elisp
(with-eval-after-load 'maf
  (add-to-list 'maf-modules 'maf-persist t)
  (maf-modules-apply))
```

### Optional dependencies

| What | Needed by | Notes |
|---|---|---|
| posframe | maf-preview | Child-frame preview panel on graphical displays. Falls back to an in-window panel. |
| [RaTeX](https://github.com/erweixin/RaTeX) `render-svg` | maf-pretty | Prebuilt CLI archives on the [releases page](https://github.com/erweixin/RaTeX/releases). Put `render-svg` on the exec path or in `~/pkgs/ratex`, or set `maf-pretty-program`. |
| gnuplot | maf-plot | Embedded SVG plot and interactive plot window. |
| A browser | maf-plot | The Desmos plot. |

## Modules

| Module | On by default | What it does |
|---|---|---|
| maf-hl | yes | Highlights the sub-formula under point |
| maf-edit | yes | In-place editing of the stack as text on `SPC` |
| maf-editplus | yes | In-entry shortcuts for edit sessions |
| maf-editvars | yes | Handwriting dialect: `2xy` reads as `2 x y` |
| maf-recall | yes | A ring of typed entries on `M-p` and `M-n` |
| maf-preview | yes | A panel showing the entry at point in Big display |
| maf-pretty | no | Typeset preview through RaTeX |
| maf-formulas | yes | Saved-formula library on `s o` |
| maf-history | yes | Browsable log of past stack states on `M-h` |
| maf-persist | no | Saves and restores the stack per session |
| maf-selplus | yes | Header-line badge while a selection exists |
| maf-poly-order | yes | Polynomials in descending degree |
| maf-plot | yes | gnuplot, Desmos, and interactive plotting |
| maf-e-power | yes | Writes `exp(x)` as `e^x` |
| maf-log-power | yes | General-base log identities |
| maf-options | yes | All of Calc's settings in one buffer on `?` |
| maf-keys | yes | Bindings help buffer on `l b` |
| maf-bindings | yes | The key profile registry and compiler |

## Layout

- `maf.el` is the entry point.
- `core/` holds the machinery: target resolution, commit, the `maf-defcmd` macro, chains, selections, modules, bindings.
- `src/` holds the command table, the stack commands, digit entry, and the profile declarations.
- `modules/` holds the feature modules.
- `pkg/` holds two in-repo libraries meant to stand alone: `dial`, a buffer for browsing and setting options, and `filter-view`, a filterable grouped menu.
- `tests/` is the suite: step tests run against a live Emacs, every file expected to pass on `main`. See `tests/README.md`.
- `docs/reference/concepts.org` is the architectural overview for developers.
- `public/` is the website.

## Status

Version 0.1.0. Under active development; the public API is unstable.

## License

MIT. See `LICENSE`.
