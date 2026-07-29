;; -*- lexical-binding: t; -*-
;;
;; bindings.el
;;
;; Default maf-mode-map key bindings. The mafcmd table in maf-cmds.el
;; binds its own keys from row data; this file collects every binding
;; made outside the table.

(require 'maf-stack "stack")
(require 'maf-minibuffer "minibuffer")

;; Also defvar'd in maf.el and maf-cmds.el; whichever file loads first
;; creates the map, the rest are no-ops.
(defvar maf-mode-map (make-sparse-keymap)
  "Keymap for `maf-mode'.")

;; Shadows calc-stirling's key; the contextual stirling pair
;; (mafcmd-stir1/stir2) cedes it — see the table in maf-cmds.el.
(define-key maf-mode-map (kbd "k s") #'mafcmd-complete-square)
;; Shadows calc-double-factorial's key; mafcmd-dfact cedes it — see
;; the table in maf-cmds.el.
(define-key maf-mode-map (kbd "k d") #'mafcmd-factor-powers)
(define-key maf-mode-map (kbd "l f") #'mafcmd-factor-by)
(define-key maf-mode-map (kbd "l F") #'mafcmd-factor-gcd)
(define-key maf-mode-map (kbd "l l") #'mafcmd-float)
(define-key maf-mode-map (kbd "l c") #'mafcmd-frac)
;; Numeric evaluation; k k is unbound in calc itself. I k k routes to
;; mafcmd-identify, the closed-form match for a float.
(define-key maf-mode-map (kbd "k k") #'mafcmd-evaluate)
(define-key maf-mode-map (kbd "l d") #'mafcmd-to-degrees)
(define-key maf-mode-map (kbd "l r") #'mafcmd-to-radians)
;; M-o is unbound in calc itself; H M-o runs the mod-180 variant.
(define-key maf-mode-map (kbd "M-o") #'mafcmd-mod-360)
;; Reference angle. M-l is unbound in calc itself (it shadows the global
;; downcase-word, which has no place in the stack buffer).
(define-key maf-mode-map (kbd "M-l") #'mafcmd-ref-angle)
;; M-s is unbound in calc itself; it shadows the global `search-map'
;; prefix, which calc buffers have no use for.
(define-key maf-mode-map (kbd "M-s") #'mafcmd-supplement)
;; The supplement's twin. M-c is unbound in calc itself; it shadows the
;; global `capitalize-dwim', which has no place in the stack buffer.
(define-key maf-mode-map (kbd "M-c") #'mafcmd-complement)
(define-key maf-mode-map (kbd "O") #'mafcmd-commute)
;; Balanced negation, beside calc's own n (mafcmd-neg in the table,
;; which flips the sign and lets the value change with it). Shadows
;; calc-eval-num; N is also one of the two V M operator codes that are
;; not real keys, so nothing contextual claims it — see maf-cmds.el.
(define-key maf-mode-map (kbd "N") #'mafcmd-negate)
;; Shift the term under point through its associative chain. Lowercase
;; j l / j r (calc binds the shifts to capital j L / j R, left reachable).
(define-key maf-mode-map (kbd "j l") #'maf-commute-left)
(define-key maf-mode-map (kbd "j r") #'maf-commute-right)
;; Shadows calc-call-last-kbd-macro.
(define-key maf-mode-map (kbd "X") #'mafcmd-log-exp)
;; A single-key alias for expand, which also keeps its table key a x.
;; Shadows calc-execute-extended-command.
(define-key maf-mode-map (kbd "x") #'mafcmd-expand)
;; A single-key alias for the reciprocal, which also keeps its table
;; key &. Shadows calc-realign: point already returns home after every
;; command, and M-x calc-realign still reaches its other two jobs
;; (undo horizontal scrolling, prefix-arg jump to a stack element).
(define-key maf-mode-map (kbd "o") #'mafcmd-inv)
;; A toggle between pair members is its own inverse, so both directions
;; run the same command.
(define-key maf-mode-map (kbd "S-<up>") #'mafcmd-toggle-op)
(define-key maf-mode-map (kbd "S-<down>") #'mafcmd-toggle-op)
(define-key maf-mode-map (kbd ",") #'maf-quick-variable)
;; The in-place editing entry keys (SPC / C-RET / S-RET / "(") are
;; installed by the edit module when it is enabled (see
;; modules/edit.el), not here.
(define-key maf-mode-map (kbd "U") #'maf-undo)
(define-key maf-mode-map (kbd "D") #'maf-redo)
;; Catch every key that dispatches to undo/redo, so point handling
;; never depends on which undo key was pressed. Remapping is a single
;; step: calc-mode-map already remaps undo to calc-undo, and a key
;; resolved through that chain is never re-remapped — so the plain
;; Emacs commands must be remapped here too, and the minor-mode map
;; wins over calc's.
(define-key maf-mode-map [remap undo] #'maf-undo)
(define-key maf-mode-map [remap undo-redo] #'maf-redo)
(define-key maf-mode-map [remap calc-undo] #'maf-undo)
(define-key maf-mode-map [remap calc-redo] #'maf-redo)
;; Contextual delete; C-d is unbound in calc itself, and backspace
;; shadows calc-pop, whose behavior maf-del keeps at home.
(define-key maf-mode-map (kbd "C-d") #'maf-del)
(define-key maf-mode-map (kbd "DEL") #'maf-del)
;; Line-based kill: the whole entry at point, onto the kill ring.
;; Shadows calc-kill, keeping its whole-entry semantics.
(define-key maf-mode-map (kbd "C-k") #'maf-kill)
;; Copy, the non-destructive counterpart of C-k: the region when there
;; is one, else the entry at point. Shadows calc-copy-region-as-kill,
;; which rounds a region out to whole display lines, prefixes included;
;; maf-copy takes the region verbatim, as M-w does everywhere else.
;; Pressed twice it recopies as LaTeX.
(define-key maf-mode-map (kbd "M-w") #'maf-copy)
;; Shadows calc's TAB with the contextual swap. Bind both the terminal
;; and GUI events.
(define-key maf-mode-map (kbd "TAB") #'maf-swap-up)
(define-key maf-mode-map (kbd "<tab>") #'maf-swap-up)
;; Send the entry at point all the way down the stack, the long-range
;; counterpart of TAB's one-step swap. Reaching this key on a terminal
;; needs the decode entry installed at the end of this file, and a
;; terminal that sends the sequence — see docs/memory/dev-instance.md.
;; A terminal that does not send it falls back to ESC 0x08, which
;; arrives as C-M-h; bind that as the terminal stand-in, as the edit
;; module does with C-j for S-<return>. It shadows only mark-defun,
;; which has no use in a calc buffer, at the cost of Ctrl+Alt+h
;; rolling too.
(define-key maf-mode-map (kbd "C-M-<backspace>") #'maf-roll-to-bottom)
(define-key maf-mode-map (kbd "C-M-h") #'maf-roll-to-bottom)
;; Restack: the entry at point travels to the top, point riding along.
;; The long-range move up, sharing the backspace key with the bury
;; above — one base key for both ends of the stack, the modifier
;; picking the end. Bind the GUI event and the DEL form both:
;; `function-key-map' rewrites <backspace> to DEL, and an unbound
;; modified function key falls back to that translation with the
;; modifier kept, so shift-backspace can arrive either way. Neither
;; shadows anything in calc; plain DEL stays `maf-del' above.
;; Terminals need the decode entry installed at the end of this file.
(define-key maf-mode-map (kbd "S-<backspace>") #'maf-roll-to-top)
(define-key maf-mode-map (kbd "S-DEL") #'maf-roll-to-top)
;; Contextual duplicate, shadowing calc-enter. At home it dups the top
;; as calc-enter does; elsewhere it pushes a copy of the resolved item.
;; With a selection active the same key clears the selections instead —
;; the way back out of the sub-formula it drilled into — so the
;; duplicate is one step away rather than the escape being a prefix key.
;; During digit/algebraic entry RET stays calc's own (the entry
;; minibuffer terminates), as with e / = / @.
;;
;; C-u RET is the keep-point variant (`maf-dup-here'): same push, point
;; stays on the target instead of homing, so the next command still
;; resolves there. It rides RET's prefix argument rather than a key of
;; its own — the RET family is full (M-RET below, C-RET and S-RET in the
;; edit module) and W is the only unbound single key left in the buffer,
;; too scarce to spend on where point lands. Contextual dup has no
;; numeric reading to conflict with; cf. `maf-swap-up', whose prefix
;; likewise switches mode rather than counting. The prefix reaches the
;; duplicate only: with a selection active the key clears, which has
;; nothing for a prefix to vary.
(define-key maf-mode-map (kbd "RET") #'maf-dup-or-clear-selections)
;; M-RET duplicates the whole entry into the slot just below it, the
;; in-place counterpart of RET's copy onto the top. Bind the GUI event
;; and the terminal form both, as calc has no M-RET.
;;
;; `maf-dup-here' — the keep-point variant of RET's duplicate — held
;; this key until the entry-duplicate took it; it now rides RET's prefix
;; argument (C-u RET), and stays reachable by name.
(define-key maf-mode-map (kbd "M-<return>") #'maf-dup-below)
(define-key maf-mode-map (kbd "M-RET") #'maf-dup-below)
;; S-<return> is the edit module's add-entry-below (see
;; modules/maf-edit.el), installed there with the rest of its entry
;; keys. The restack it used to carry now sits on S-<backspace>, beside
;; the bury it pairs with.

;; Equate gets both = (shadowing calc-evaluate) and e (shadowing the
;; e-notation digit start; inside digit entry e still means exponent,
;; since the entry minibuffer is calc's own).
(define-key maf-mode-map (kbd "=") #'mafcmd-equal-to)
(define-key maf-mode-map (kbd "e") #'mafcmd-equal-to)
;; The other direction: drop the relation, keep a side. M-. is unbound
;; in calc itself; a . is calc's own key for the operation, which the
;; table in maf-cmds.el no longer claims.
(define-key maf-mode-map (kbd "M-.") #'mafcmd-remove-equal)
(define-key maf-mode-map (kbd "a .") #'mafcmd-remove-equal)

;; The simplification toggle takes @ from the digit-entry starters
;; below; inside digit entry @ still means degrees, since the entry
;; minibuffer is calc's own (cf. e and mafcmd-equal-to).
(define-key maf-mode-map (kbd "@") #'maf-toggle-simplify)

;; Big-language display toggle. mafcmd-arg cedes calc's G — see the
;; table in maf-cmds.el.
(define-key maf-mode-map (kbd "G") #'maf-toggle-big-language)

;; Session reset, and the modes-only half beside it. Both keys are
;; unbound in calc itself; whatever the global map puts there
;; (erase-buffer, `reposition-window', a magit command) has no business
;; in a stack buffer, and C-M-k is exactly the destructive global these
;; shadow — one fingerslip away from wiping the wrong buffer.
(define-key maf-mode-map (kbd "C-M-k") #'maf-reset)
(define-key maf-mode-map (kbd "C-M-l") #'maf-reset-settings)

;; Auto-solve: solve or isolate at point, cycling through the variables
;; on repeat. M-i is unbound in calc itself.
(define-key maf-mode-map (kbd "M-i") #'mafcmd-auto-solve)
;; Solve for a variable read from the minibuffer, beside the automatic
;; solve on M-i. Shadows calc-info, which stays reachable on calc's own
;; help prefix (h i) and as M-x calc-info.
(define-key maf-mode-map (kbd "i") #'mafcmd-solve-for)
;; Invert the function at point, beside the two solve commands. l v is
;; unbound in calc itself (its l prefix is the logarithmic units).
(define-key maf-mode-map (kbd "l v") #'mafcmd-inverse-function)
;; Substitution, on calc's own key for it: mafcmd-substitute shadows
;; calc-substitute, keeping the two prompts and adding a default for
;; the first, a contextual subject, and $ for the stack.
(define-key maf-mode-map (kbd "a b") #'mafcmd-substitute)
;; mafcmd-let — apply an assignment from the stack — is deliberately
;; unbound for now; reachable as M-x mafcmd-let. The natural key is
;; s SPC, beside the s : that builds the assignment (mafcmd-assign, in
;; the table in maf-cmds.el); it is unbound in calc itself, and the
;; command it generalizes, calc-let, keeps its own s l either way.
;; Polynomial roots by factoring, with multiplicity. M-r is unbound in
;; calc itself.
(define-key maf-mode-map (kbd "M-r") #'mafcmd-poly-roots)
;; Polynomial LCM, beside calc's own polynomial GCD on a g
;; (mafcmd-pgcd, from the table in maf-cmds.el). a L is unbound in
;; calc itself.
(define-key maf-mode-map (kbd "a L") #'mafcmd-poly-lcm)

;; Swap two variables, read from the minibuffer. l x is unbound in calc
;; itself (l is its logarithmic-units prefix).
(define-key maf-mode-map (kbd "l x") #'mafcmd-swap-vars)

;; Unwrap the target into its parts. M-u is unbound in calc itself (it
;; shadows the global upcase-dwim, which has no place in the stack
;; buffer). The other two are calc's own unpack keys, and mafcmd-unpack
;; subsumes both commands: v u is calc-unpack, which spreads a whole
;; entry's parts over the stack, and j U (with its j M-U alias) is
;; calc-sel-unpack, which replaces a selected one-argument call with
;; its argument. Shadowing both keeps one unpack behavior in the
;; buffer — left alone, j U would still signal on the multi-part
;; sub-formulas the contextual command commits unchanged.
(define-key maf-mode-map (kbd "M-u") #'mafcmd-unpack)
(define-key maf-mode-map (kbd "v u") #'mafcmd-unpack)
(define-key maf-mode-map (kbd "j U") #'mafcmd-unpack)
(define-key maf-mode-map (kbd "j M-U") #'mafcmd-unpack)

;; Group a vector's elements N at a time, N from the stack. l g is
;; unbound in calc itself — its l prefix is the logarithmic units,
;; which has no g — and it joins maf's other l bindings above.
(define-key maf-mode-map (kbd "l g") #'mafcmd-unique-groups)
;; Flatten the target vector. Takes calc's v L from calc-lud (LU
;; decomposition), which the table in maf-cmds.el gives up its key for;
;; mafcmd-lud is still reachable by name. Flattening earns the vector
;; key: it is the everyday shape fix after a map or a pack leaves
;; rows where a plain list was wanted, and it sits a keystroke from
;; mafcmd-arrange (v a), the N-column form it degenerates from.
(define-key maf-mode-map (kbd "v L") #'mafcmd-flatten)

;; Coordinate naming, cycling the name sets on repeat. Shadows
;; calc-copy-as-kill; maf-copy (M-w) copies the region or the entry,
;; and maf-kill (C-k) kills the whole entry onto the kill ring.
(define-key maf-mode-map (kbd "M-k") #'mafcmd-coordinate-toggle)

;; The digit-entry starters, mirroring calc-mode-map's calcDigit-start
;; set minus @, which maf-toggle-simplify shadows.
(mapc (lambda (x)
        (define-key maf-mode-map (char-to-string x) #'maf-digit-start))
      "_0123456789.#")

;; Entry-beginning motion. Shadows calc's own M-m prefix, whose two
;; sequences (M-m t, M-m M-t) stay reachable as m t and m M-t.
(define-key maf-mode-map (kbd "M-m") #'maf-beginning-of-entry)

;; The `t d' stack-timeline binding is installed by the maf-timeline
;; module when it is enabled (see modules/maf-timeline.el), not here.

;; A terminal cannot say "backspace with a modifier" as a character:
;; backspace is ASCII 127 and the modifiers have nowhere to go. One
;; that supports modifyOtherKeys spells the key out instead, but
;; term/xterm.el decodes that form from a hardcoded table of
;; modifier/keycode pairs with no entry for keycode 127 under any
;; modifier — so the sequence falls through undecoded and its tail
;; self-inserts, which in a calc buffer means junk on the stack.
;; term/tmux.el defers to the same table and inherits the gap. Supply
;; the missing entries in both of the formats xterm.el generates. The
;; modifier number is 1 plus the bitmask (shift 1, alt 2, ctrl 4): 7
;; for the bury's Ctrl+Alt, 2 for the restack's Shift.
(defun maf--tty-setup-keys ()
  "Decode terminal sequences for keys maf binds and `term/xterm.el' omits."
  (define-key input-decode-map "\e[27;7;127~" [C-M-backspace])
  (define-key input-decode-map "\e[127;7u" [C-M-backspace])
  (define-key input-decode-map "\e[27;2;127~" [S-backspace])
  (define-key input-decode-map "\e[127;2u" [S-backspace]))

;; `input-decode-map' is terminal-local, so this runs once per tty
;; rather than once at load.
(add-hook 'tty-setup-hook #'maf--tty-setup-keys)
;; The hook has already run for a terminal that exists by now.
(unless (display-graphic-p)
  (maf--tty-setup-keys))

(provide 'maf-bindings)
