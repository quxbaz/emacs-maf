;; -*- lexical-binding: t; -*-
;;
;; bindings.el
;;
;; Default maf-mode-map key bindings. The mafcmd table in maf-cmds.el
;; binds its own keys from row data; this file collects every binding
;; made outside the table.

(require 'maf-stack "stack")
(require 'maf-minibuffer "minibuffer")
(require 'maf-bindings)

;; The one command declared here that lives in a module: the preview
;; peek on G, bound whether or not its module is on (see the G row).
;; Modules load after this file; a declaration only records the symbol.
(declare-function maf-preview-show "maf-preview")

;; Also defvar'd in maf.el and maf-cmds.el; whichever file loads first
;; creates the map, the rest are no-ops. The map itself stays empty:
;; it is the stable dispatcher, and everything lives in the parent the
;; bindings module composes (see core/maf-bindings.el).
(defvar maf-mode-map (make-sparse-keymap)
  "Keymap for `maf-mode'.")

;; The three built-in profiles, declared through the same public API a
;; user's own profile would use. This file is the *native* layout:
;; a declaration names calc as well only when it is genuinely
;; profile-agnostic — a maf sibling on calc's own key. vim never
;; needs naming: it derives from native (below), so the whole native
;; set reaches it at compile time, its own motions displacing what
;; they overlap.
(maf-bindings-defprofile 'calc :description
  "Calc's own layout, maf's commands: siblings on the keys calc uses.")
(maf-bindings-defprofile 'native :description
  "maf's opinionated layout — the default.")
;; vim derives from native: at every compile its effective defaults
;; are native's whole set beneath its own declarations, so native's
;; layout — table keys, shadowing, additions — flows through without
;; each declaration naming vim, and the motions below displace what
;; they overlap (a motion on j drops the inherited j family whole).
;; See `maf-bindings--effective-defaults'; the displaced families'
;; new homes are the relocation table (profile:vim in
;; docs/bindings.org).
(maf-bindings-defprofile 'vim :derive 'native :description
  "maf's layout under vim's navigation keys.")

;; The mafcmd table's key column, declared here where the profile
;; defaults are owned: reloading this file rebuilds the whole set.
;; Not vim: the table reaches it through the derivation, where the
;; motions prune the k and b rows.
(pcase-dolist (`(,key . ,command) maf-cmds--table-keys)
  (maf-bindings-define '(calc native) key command))

;; A second key for the square root, beside Q (mafcmd-sqrt in the
;; table): the root is reached for far more often than integer
;; division, whose key this was — calc's \ is shadowed, and the idiv
;; row in maf-cmds.el keeps no key.
(maf-bindings-define '(native) "\\" #'mafcmd-sqrt)
;; The square on a key of its own: I Q reaches mafcmd-sqr through the
;; inverse flag, and W is free in both maps. The next key over from
;; Q, and the shape of the two square-root keys' inverse.
(maf-bindings-define '(native) "W" #'mafcmd-sqr)
;; And an unshifted key beside it, the pairing an edit session already
;; makes: : and W both raise to a power there, so the stack answers
;; the same way. Displaces calc's fraction divide, which the mafcmd
;; table keeps no key for.
(maf-bindings-define '(native) ":" #'mafcmd-sqr)

;; The combinators, on calc's own keys for them: each reads its
;; operation from the next key press, as calc's V R and V O do, but
;; looks it up among maf's commands instead of calc's fixed operator
;; table (see `maf--read-operation'). They left the mafcmd table
;; because a row cannot express an argument that is an operation —
;; see the note in maf-cmds.el.
(maf-bindings-define '(calc native) "v R" #'mafcmd-reduce)
(maf-bindings-define '(calc native) "v U" #'mafcmd-accum)
(maf-bindings-define '(calc native) "v A" #'mafcmd-apply)
(maf-bindings-define '(calc native) "v O" #'mafcmd-outer)
(maf-bindings-define '(calc native) "v I" #'mafcmd-inner)
;; A second key for the reduce, beside its v R: the fold is the
;; combinator reached for most, and it already spends a key on the
;; operation it reads, so the prefix is the one worth dropping.
;; Displaces floor's table key in native — floor keeps no key — while
;; the calc profile keeps F = floor, calc's own layout.
(maf-bindings-define '(native) "F" #'mafcmd-reduce)
;; A second key for multiplication, beside the table's *: the
;; most-struck binary operator gains a home-row shift where * is a
;; reach to shift-8. Displaces conj's table key J in native — conj
;; rides its family key l j (below) — while the calc profile keeps
;; J = conj, calc's own layout.
(maf-bindings-define '(native) "J" #'mafcmd-mul)
;; Shadows calc-stirling's key; the contextual stirling pair
;; (mafcmd-stir1/stir2) cedes it — see the table in maf-cmds.el.
(maf-bindings-define '(native) "k s" #'mafcmd-complete-square)
;; Shadows calc-double-factorial's key; mafcmd-dfact cedes it — see
;; the table in maf-cmds.el.
(maf-bindings-define '(native) "k d" #'mafcmd-factor-powers)
;; Permutations on p, beside its sibling choose (k c, the table): calc
;; leaves perm on the hyperbolic flag alone (H k c), and nPr is struck
;; often enough beside nCr to want a key of its own. A custom-prefix
;; claim under the k/l policy: calc-prime-test cedes the key.
(maf-bindings-define '(native) "k p" #'mafcmd-perm)
;; And a second key for it on t, for the count of arrangements the
;; permutation is: p and t both fall under the same hand as k c.
;; mafcmd-totient cedes it — see the table in maf-cmds.el.
(maf-bindings-define '(native) "k t" #'mafcmd-perm)
;; A second key for the factor, beside its table key a f: the whole
;; factoring family already gathers under k and l (k d, l f, l F, l D),
;; and f is factor's letter. mafcmd-prfac cedes it — see the table in
;; maf-cmds.el.
(maf-bindings-define '(native) "k f" #'mafcmd-factor)
(maf-bindings-define '(native) "l f" #'mafcmd-factor-by)
(maf-bindings-define '(native) "l F" #'mafcmd-factor-gcd)
;; c for collect. The key returns to service after the float/frac
;; toggle freed it: frac kept its name and flags, and t said nothing.
(maf-bindings-define '(native) "l c" #'mafcmd-collect-fractions)
;; Collect's inverse beside it: a redundant second key for apart (the
;; table's a a), splitting a fraction into partial fractions the way
;; l c gathers them. t freed when poly-roots left the key; the roots
;; keep the family on its capital, l T.
(maf-bindings-define '(native) "l t" #'mafcmd-apart)
;; The float/frac toggle: any float in the target converts toward
;; exact, otherwise fractions float — see `mafcmd-float-frac'. The
;; fixed directions stay reachable through it: I forces the float, H
;; the pervasive float-all, and frac's tolerance rides the prefix arg.
(maf-bindings-define '(native) "l l" #'mafcmd-float-frac)
;; The extended simplify on the doubled k, beside its table key a s:
;; the most-reached-for command takes the cheapest chord. k k is
;; unbound in calc itself; evaluate, which held it, moved to k v.
(maf-bindings-define '(native) "k k" #'mafcmd-esimplify)
;; Numeric evaluation; k v is unbound in calc itself. I k v routes to
;; mafcmd-identify, the closed-form match for a float.
(maf-bindings-define '(native) "k v" #'mafcmd-evaluate)
;; Another key for the extended simplify beside k k and its table key
;; a s. C-c C-c is the mode's slice of the C-c convention — unbound
;; here, safe from user C-c <letter> keys — and carries its
;; Emacs-wide "do the obvious thing" reflex: on a stack entry, that
;; is cleaning it up.
(maf-bindings-define '(native) "C-c C-c" #'mafcmd-esimplify)
(maf-bindings-define '(native) "l d" #'mafcmd-to-degrees)
(maf-bindings-define '(native) "l r" #'mafcmd-to-radians)
;; M-o is unbound in calc itself; H M-o runs the mod-180 variant.
(maf-bindings-define '(native) "M-o" #'mafcmd-mod-360)
;; And a family key on w, for wrapping the angle into range — which
;; the vim mirror carries as o w, the command's home there since
;; vim's M-o is the float/frac toggle. l w is unbound in calc's
;; log-units prefix; nothing cedes anything.
(maf-bindings-define '(native) "l w" #'mafcmd-mod-360)
;; The conjugate on its initial, l j — which the vim mirror carries
;; as o j, the command's home there since vim's J is the relocated
;; selection/structure family. l j is unbound in calc's log-units
;; prefix. Conj's table key J is ceded to the second multiply key
;; (above), making this conj's native home; the calc profile keeps
;; J = conj.
(maf-bindings-define '(native) "l j" #'mafcmd-conj)
;; Complete the square on its letter — which the vim mirror carries
;; as o s, the command's home there since vim's k is a motion; k s
;; stays in native. A custom-prefix claim under the k/l policy:
;; calc-spn cedes the key.
(maf-bindings-define '(native) "l s" #'mafcmd-complete-square)
;; Factor by power identities on D, for the difference of squares —
;; which the vim mirror carries as o D, the command's home there
;; since vim's k is a motion; k d stays in native. l D is unbound in
;; calc's log-units prefix.
(maf-bindings-define '(native) "l D" #'mafcmd-factor-powers)
;; Reference angle. M-l is unbound in calc itself (it shadows the global
;; downcase-word, which has no place in the stack buffer).
(maf-bindings-define '(native) "M-l" #'mafcmd-ref-angle)
;; M-s is unbound in calc itself; it shadows the global `search-map'
;; prefix, which calc buffers have no use for.
(maf-bindings-define '(native) "M-s" #'mafcmd-supplement)
;; The supplement's twin. M-c is unbound in calc itself; it shadows the
;; global `capitalize-dwim', which has no place in the stack buffer.
(maf-bindings-define '(native) "M-c" #'mafcmd-complement)
(maf-bindings-define '(native) "O" #'mafcmd-commute)
;; Nudge the target a step down or up — plain ±1, a prefix for more.
;; < and > read as less/more. They displace the horizontal scrolling
;; the keys used to carry (maf's swapped reading of calc's own pair);
;; an entry too wide for the window still slides with C-x < and
;; C-x >. Calc's own f [ / f ] (mafcmd-decr/incr in the table) keep
;; the ulp-stepping originals, and [ ] stay calc's vector delimiters.
(maf-bindings-define '(native) "<" #'mafcmd-decrement)
(maf-bindings-define '(native) ">" #'mafcmd-increment)
;; The same step under a modifier, for the run of them a nudge invites:
;; the hand holds meta and taps rather than releasing between steps. A
;; terminal delivers these, unlike C-< / C->, so they work on a tty as
;; the unmodified pair does. They shadow the global `beginning-of-buffer'
;; / `end-of-buffer', whose trip to the ends of the stack buffer the
;; stack's own motions already make in the terms it is read in.
(maf-bindings-define '(native) "M-<" #'mafcmd-decrement)
(maf-bindings-define '(native) "M->" #'mafcmd-increment)
;; Balanced negation, beside calc's own n (mafcmd-neg in the table,
;; which flips the sign and lets the value change with it). Shadows
;; calc-eval-num; N is also one of the two V M operator codes that are
;; not real keys, so nothing contextual claims it — see maf-cmds.el.
(maf-bindings-define '(native) "N" #'mafcmd-negate)
;; The map flag: the next command — not a formula — maps over the
;; target, one run per vector element or equation side. A fancy prefix
;; like calc's K/I/H, so it chains with them; M shadows
;; calc-more-recursion-depth. The formula-mapping commands live one
;; keypress behind it (`maf--map-flag-keys'): M : prompts for the
;; formula (mafcmd-map), M $ takes it from the top of the stack
;; (mafcmd-map-stack) — $ alone keeps calc's own command, and
;; # its digit-starter role. Calc's a M keeps the operator prompt
;; (mafcmd-mapeq in the table), which stays the escape hatch.
(maf-bindings-define '(native) "M" #'mafcmd-map-flag)
;; Shift the term under point through its associative chain. Lowercase
;; j l / j r (calc binds the shifts to capital j L / j R, left reachable).
(maf-bindings-define '(native) "j l" #'maf-commute-left)
(maf-bindings-define '(native) "j r" #'maf-commute-right)
;; The same two on the shifted arrows, which say the direction the term
;; travels and repeat without leaving the key. They join the S-arrow
;; family the stack already reads as "act on what is under point":
;; S-<up>/S-<down> toggle its operator (below), and the plain arrows
;; stay the buffer's motion keys, so shift is the modifier that moves
;; the formula rather than the cursor. Calc binds neither key; outside
;; calc S-<left> is a global transpose, which this shadows only in the
;; calc buffer.
(maf-bindings-define '(native) "S-<left>" #'maf-commute-left)
(maf-bindings-define '(native) "S-<right>" #'maf-commute-right)
;; Move the term under point across the = (or !=) it sits in. Lowercase
;; j e, beside the shifts above, for the same reason: calc keeps the
;; jump on the capital j E, which stays reachable and unshadowed for
;; the plain = -only behavior that leaves its selection standing.
;; Shadows calc-enable-selections, whose toggle maf has no use for —
;; every maf command resolves its subject from point.
(maf-bindings-define '(native) "j e" #'maf-jump-equals)
;; Spread the formula around the target inward over its parts, and the
;; reverse. These take calc's own keys rather than a lowercase twin:
;; unlike the jump and the shifts above, the contextual versions have
;; no behavior worth reaching past them for — calc's differ only in
;; requiring the selection to be made first and leaving it standing,
;; both of which maf supplies from point instead.
(maf-bindings-define '(native) "j D" #'maf-distribute)
(maf-bindings-define '(native) "j M" #'maf-merge)
;; Inside digit entry j is a jump of its own: `maf-digit-jump'
;; (src/minibuffer.el) ends the entry and sends point to the stack
;; level the number named, the prefix's reading one level out.
;; Shadows calc-call-last-kbd-macro.
(maf-bindings-define '(native) "X" #'mafcmd-log-exp)
;; And a family key on its initials, l e — which the vim mirror
;; carries as o e, the command's home there since vim's X is the
;; relocated expand. l e is unbound in calc's log-units prefix.
(maf-bindings-define '(native) "l e" #'mafcmd-log-exp)
;; A single-key alias for expand, which also keeps its table key a x.
;; Shadows calc-execute-extended-command.
(maf-bindings-define '(native) "x" #'mafcmd-expand)
;; The reciprocal. It sat on i until the prompted solve took that key
;; back, and takes o in turn from the home motion, which held o before
;; going unbound (below). A second key beside its own & (the inv row in
;; maf-cmds.el, calc's key for it). Shadows calc-realign, whose bare
;; press only undoes horizontal scrolling; M-x calc-realign still
;; reaches that and the prefixed home motion both.
(maf-bindings-define '(native) "o" #'mafcmd-inv)
;; Preview the entry at point: one panel over the top-right of the
;; window, showing the entry in calc's 2D Big display, and gone again at
;; the next command. Takes calc's G, which mafcmd-arg cedes (see the
;; table in maf-cmds.el).
;;
;; Declared here rather than by the preview module (modules/), where
;; every other key of a module's is declared, because it is not a key
;; the module owns: the panel that *follows point* is the module, and
;; this is one look asked for by hand, which reads an entry the same
;; way whether the module is on, off, or not enabled at all. A key that
;; came and went with the toggle would take with it the very way of
;; working — no panel underfoot, a peek when wanted — that having the
;; toggle off is for.
(maf-bindings-define '(native) "G" #'maf-preview-show)
;; Two commands that held keys here are now bound by nothing, both
;; because that preview does their work better:
;;
;; - `maf-toggle-big-language', which had &, switched the whole stack
;;   into 2D and back to read one entry; the preview shows that entry
;;   in 2D with the stack left alone. & goes back to the reciprocal,
;;   calc's own command for the key (the inv row in maf-cmds.el), and
;;   calc's d B / d N stay the one-way switches.
;;
;; - `maf-go-home', which had G, is the round trip between an entry and
;;   the . line — out for a command that wants the entry, back for one
;;   that wants the term. C-u C-SPC still walks the marks the round
;;   trip left.
;;
;; Both commands are still defined and still reachable by name, so a
;; key here (or in a user map) brings either back.
;; A toggle between pair members is its own inverse, so both directions
;; run the same command.
(maf-bindings-define '(native) "S-<up>" #'mafcmd-toggle-op)
(maf-bindings-define '(native) "S-<down>" #'mafcmd-toggle-op)
(maf-bindings-define '(native) "," #'maf-quick-variable)
;; Contextual pi, shadowing calc-pi on its own key: the target is
;; multiplied by the symbolic constant; at home with no selection the
;; command defers to calc-pi's push. I/H reach gamma, e, and phi
;; through the flags, as in calc.
(maf-bindings-define '(calc native) "P" #'maf-pi)
;; Recall a variable by picking it off a list of values. Shadows
;; calc-precision, whose only key this is: a mode setting that is set
;; once and then left alone, reachable by name afterwards, giving up
;; its key to something pressed while working.
(maf-bindings-define '(native) "p" #'maf-browse-variables)
;; Literal recall: what was stored is what lands, unsimplified. r 0-9
;; shadow calc's quick recall, which renormalizes under the current
;; modes on the way out; r r is unbound in calc itself (its prompt
;; recall lives on s r, which keeps its key and its simplifying push).
(maf-bindings-define '(native) "r r" #'maf-recall-variable)
(dotimes (i 10)
  (maf-bindings-define '(calc native) (format "r %d" i)
                       #'maf-recall-quick))
;; The in-place editing entry keys (SPC / ` / C-o) are installed by the
;; edit module when it is enabled (see modules/edit.el), not here. `
;; shadows calc-edit, the command the whole module replaces. The
;; module's fourth key, "(" for a blank vector, is native's relation
;; motion below and reaches the module through it; the module still
;; declares its own plain "(" for the calc profile.
(maf-bindings-define '(calc native) "U" #'maf-undo)
(maf-bindings-define '(calc native) "D" #'maf-redo)
;; Catch every key that dispatches to undo/redo, so point handling
;; never depends on which undo key was pressed. Remapping is a single
;; step: calc-mode-map already remaps undo to calc-undo, and a key
;; resolved through that chain is never re-remapped — so the plain
;; Emacs commands must be remapped here too, and the minor-mode map
;; wins over calc's.
(define-key maf-bindings-base-map [remap undo] #'maf-undo)
(define-key maf-bindings-base-map [remap undo-redo] #'maf-redo)
(define-key maf-bindings-base-map [remap calc-undo] #'maf-undo)
(define-key maf-bindings-base-map [remap calc-redo] #'maf-redo)
;; Contextual delete; C-d is unbound in calc itself, and backspace
;; shadows calc-pop, whose behavior maf-del keeps at home.
(maf-bindings-define '(calc native) "C-d" #'maf-del)
(maf-bindings-define '(calc native) "DEL" #'maf-del)
;; Line-based kill: the whole entry at point, onto the kill ring.
;; Shadows calc-kill, keeping its whole-entry semantics.
(maf-bindings-define '(calc native) "C-k" #'maf-kill)
;; Copy, the non-destructive counterpart of C-k: the region when there
;; is one, else the entry at point. Shadows calc-copy-region-as-kill,
;; which rounds a region out to whole display lines, prefixes included;
;; maf-copy takes the region verbatim, as M-w does everywhere else.
;; Pressed twice it recopies as LaTeX.
(maf-bindings-define '(calc native) "M-w" #'maf-copy)
;; Yank, completing the kill-ring trio. Shadows calc-yank to read a
;; number written with digit-group commas ("1,234,567") as one number
;; rather than three comma-separated entries; otherwise identical,
;; radix prefix included.
(maf-bindings-define '(calc native) "C-y" #'maf-yank)
;; Shadows calc's TAB with the contextual swap. Bind both the terminal
;; and GUI events.
(maf-bindings-define '(calc native) "TAB" #'maf-swap-up)
(maf-bindings-define '(calc native) "<tab>" #'maf-swap-up)
;; C-t as a second key for the swap, on transpose-chars' mnemonic.
;; Shadows only the global transpose-chars, useless in a calc buffer.
(maf-bindings-define '(calc native) "C-t" #'maf-swap-up)
;; Send the entry at point all the way down the stack, the long-range
;; counterpart of TAB's one-step swap. Reaching this key on a terminal
;; needs the decode entry installed at the end of this file, and a
;; terminal that sends the sequence — see docs/memory/dev-instance.md.
;; A terminal that does not send it falls back to ESC 0x08, which
;; arrives as C-M-h; bind that as the terminal stand-in. It shadows
;; only mark-defun, which has no use in a calc buffer, at the cost of
;; Ctrl+Alt+h rolling too. Bind the DEL form as well: `function-key-map'
;; rewrites <backspace> to DEL, and an unbound modified function key
;; falls back to that translation with the modifier kept, so the key can
;; arrive either way. Neither shadows anything in calc; plain DEL stays
;; `maf-del' above.
(maf-bindings-define '(native) "C-M-<backspace>" #'maf-roll-to-bottom)
(maf-bindings-define '(native) "C-M-DEL" #'maf-roll-to-bottom)
(maf-bindings-define '(native) "C-M-h" #'maf-roll-to-bottom)
;; Restack: the entry at point travels to the top, point riding along.
;; The long-range move up, beside the bury it mirrors. It sits on
;; S-<return>, the key the edit module's add-entry-below gave up (see
;; the RET family below); the shift-backspace it used to share with the
;; bury is unbound, and the decode entry that made that key reach a
;; terminal is gone with it. A terminal folds Shift-RET back to plain
;; RET, so this is a GUI key: on a tty the restack is reachable by name.
(maf-bindings-define '(native) "S-<return>" #'maf-roll-to-top)
;; Carry the entry at point one line up or down the screen, point
;; riding along — the stack's version of moving a line in a text
;; buffer, and the one-step counterpart of the backspace pair above,
;; which sends an entry to either end. Calc binds neither key, and the
;; arrows are already the buffer's motion keys; S-<up>/S-<down> next to
;; them toggle the operator at point. A prefix argument counts lines.
(maf-bindings-define '(native) "M-<up>" #'maf-carry-up)
(maf-bindings-define '(native) "M-<down>" #'maf-carry-down)
;; Contextual duplicate, shadowing calc-enter. At home it dups the top
;; as calc-enter does; elsewhere it pushes a copy of the resolved item.
;; With a selection active the same key clears the selections instead —
;; the way back out of the sub-formula it drilled into — so the
;; duplicate is one step away rather than the escape being a prefix key.
;; During algebraic entry RET stays calc's own (the entry minibuffer
;; terminates), as with e / = / @; during digit entry it is the
;; contextual commit (`maf-digit-commit-contextual', src/minibuffer.el).
;;
;; C-u RET is the keep-point variant (`maf-dup-here'): same push, point
;; stays on the target instead of homing, so the next command still
;; resolves there. C-RET below is that same variant on a key, so the
;; prefix is the spelling for a terminal that cannot deliver the GUI
;; event. Contextual dup has no numeric reading to conflict with; cf.
;; `maf-swap-up', whose prefix likewise switches mode rather than
;; counting. The prefix reaches the duplicate only: with a selection
;; active the key clears, which has nothing for a prefix to vary.
(maf-bindings-define '(calc native) "RET" #'maf-dup-or-clear-selections)
;; C-RET is the keep-point duplicate: RET's own push, with point staying
;; on what it copied instead of parking home, so the next command still
;; resolves there (`maf-dup-here-or-clear-selections' — the dispatcher
;; with its keep-point argument set, which is what C-u RET runs). Where
;; point lands is the whole of the difference: a C-RET that homed too
;; would be RET with a modifier held down. A selection still clears, as
;; it does on RET; the hold has nothing to vary there.
;;
;; It matches the key's promise in the digit-entry minibuffer, where
;; C-<return> is `maf-digit-commit-here' (src/minibuffer.el): push the
;; number, keep point. `maf-dup-go', the traveling duplicate whose point
;; rides to the copy on top, held this key from the swap with
;; `mafcmd-let' until 2026-08-24; it stays reachable by name, and on
;; M-RET in the calc profile below.
(maf-bindings-define '(native) "C-<return>" #'maf-dup-here-or-clear-selections)
;; The swap was a native-layout opinion, and so is the keep-point key
;; that replaced it: the calc profile keeps the traveling duplicate on
;; M-RET, its pre-swap home. The GUI event and the
;; terminal form both, as calc itself binds only the terminal form
;; (calc-last-args).
(maf-bindings-define '(calc) "M-<return>" #'maf-dup-go)
(maf-bindings-define '(calc) "M-RET" #'maf-dup-go)
;; S-<return> is the restack (bound above, beside the bury). It was the
;; edit module's add-entry-below, which is unbound now and reachable by
;; name: C-o opens an entry above point, and above the entry below point
;; is where add-entry-below opened, so the gesture survives one line
;; down — with ` still opening at the bottom.

;; Equate lives on e (shadowing the e-notation digit start) and its
;; typographic twin =. The calc profile leaves = to calc-evaluate.
;; Inside digit entry e reaches the same command through
;; `maf-digit-equal-to' (src/minibuffer.el), which ends the entry on it
;; and makes the number the argument; = takes calc's ordinary
;; command-key handoff to the stack binding.
(maf-bindings-define '(native) "e" #'mafcmd-equal-to)
(maf-bindings-define '(native) "=" #'mafcmd-equal-to)
;; The other direction: drop the relation, keep a side. M-. is unbound
;; in calc itself; a . is calc's own key for the operation, which the
;; table in maf-cmds.el no longer claims.
(maf-bindings-define '(native) "M-." #'mafcmd-remove-equal)
(maf-bindings-define '(calc native) "a ." #'mafcmd-remove-equal)

;; The simplification toggle takes @ from the digit-entry starters
;; below; inside digit entry @ still means degrees, since the entry
;; minibuffer is calc's own but for the keys src/minibuffer.el takes
;; there (; : and n P e SPC j).
(maf-bindings-define '(native) "@" #'maf-toggle-simplify)

;; Session reset, and the modes-only half beside it. Both keys are
;; unbound in calc itself; whatever the global map puts there
;; (erase-buffer, `reposition-window', a magit command) has no business
;; in a stack buffer, and C-M-k is exactly the destructive global these
;; shadow — one fingerslip away from wiping the wrong buffer.
(maf-bindings-define '(native) "C-M-k" #'maf-reset)
(maf-bindings-define '(native) "C-M-l" #'maf-reset-settings)

;; Auto-solve: solve the entry for a variable, cycling through them on
;; repeat. The entry is the subject wherever point sits within it — the
;; sub-formula targeting lives on j j below, so this key means the same
;; thing from anywhere on the line. M-i is unbound in calc itself.
(maf-bindings-define '(native) "M-i" #'mafcmd-auto-solve)
;; The same solve, targeting the sub-expression under point: isolate it,
;; falling back to the variable solve when there is nothing to isolate.
;; The doubled prefix key, as k k is for the extended simplify: the
;; family's most-reached-for member takes its cheapest chord. Calc
;; leaves j j unbound — its j prefix is the selection commands, which
;; have no j of their own — and keeps the operation on the capital
;; j I (calc-sel-isolate), unshadowed and reachable either way. The
;; literal sense of the word is next door on j i (mafcmd-raise).
(maf-bindings-define '(native) "j j" #'mafcmd-isolate)
;; The same solve again, with the variable named rather than picked.
;; It held i before, yielded the key to the reciprocal, and takes it
;; back now that the reciprocal sits on o — the naming solve is the
;; everyday one, so it gets the single key while the auto-solve keeps
;; the meta. Shadows calc-info, which stays reachable on calc's own
;; help prefix (h i) and as M-x calc-info; calc's own key for the
;; operation, a S, stays with `mafcmd-solve' (see the table in
;; maf-cmds.el), which takes its variable from the stack.
(maf-bindings-define '(native) "i" #'mafcmd-solve-for)
;;
;; Invert the function at point, beside the solve commands. l v is
;; unbound in calc itself (its l prefix is the logarithmic units).
(maf-bindings-define '(native) "l v" #'mafcmd-inverse-function)
;; Split an absolute-value inequality into a compound one — a solve of
;; sorts, so it sits with the solving keys. a k is unbound in calc
;; itself (a is its algebra prefix).
(maf-bindings-define '(native) "a k" #'mafcmd-abs-ineq)
;; Substitution, on calc's own key for it: mafcmd-substitute shadows
;; calc-substitute, keeping the two prompts and adding a default for
;; the first, a contextual subject, and $ for the stack.
(maf-bindings-define '(calc native) "a b" #'mafcmd-substitute)
;; Quick substitution: apply an assignment from the stack to the
;; contextual subject. On the RET family's meta member since the swap
;; with the traveling duplicate (above); shadows calc-last-args, as
;; the duplicate did before it. The command's earlier keys:
;; C-c C-c first — the conventional mode-specific "apply this"
;; gesture, two hands and four keys for something reached this often,
;; whose control-character leaf calc's fancy prefix would rather not
;; carry (K C-c C-c is what `maf--fancy-prefix-keep's provisional path
;; was written for; see src/stack.el) — then C-RET, which the edit
;; module's quick-add had given up for it (`, C-o and "(" remain,
;; though ` now opens the bottom entry for editing rather than adding
;; one below it, still as a trip home). Bind the GUI event
;; and the terminal form both.
(maf-bindings-define '(native) "M-<return>" #'mafcmd-let)
(maf-bindings-define '(native) "M-RET" #'mafcmd-let)
;; Polynomial roots by factoring, with multiplicity. In the l family
;; on a free capital the log-units prefix never claimed, beside the
;; family's other capitals. Being in the family, the vim mirror
;; carries it as o T. It sat on l t until 2026-08-23, on l a until
;; 2026-08-25, on k R for part of that day, and on l b until
;; 2026-08-25; before 2026-08-20 it was M-r. Those keys fall through
;; to calc, and M-r to whatever the global map holds.
(maf-bindings-define '(native) "l T" #'mafcmd-poly-roots)
;; The prompting form of the roots vector beside its stock a P (the
;; roots row in maf-cmds.el): the variable is read from the minibuffer
;; as i reads it, the subject's priority variable as the default. a l
;; is unbound in calc itself; the same key held calc-poly-roots in the
;; my/calc config this layout grew from.
(maf-bindings-define '(native) "a l" #'mafcmd-roots-for)
;; Polynomial LCM, beside calc's own polynomial GCD on a g
;; (mafcmd-pgcd, from the table in maf-cmds.el). a L is unbound in
;; calc itself.
(maf-bindings-define '(native) "a L" #'mafcmd-poly-lcm)

;; Swap two variables, read from the minibuffer. l x is unbound in calc
;; itself (l is its logarithmic-units prefix).
(maf-bindings-define '(native) "l x" #'mafcmd-swap-vars)

;; Unwrap the entry at point into its parts. M-u is unbound in calc
;; itself (it shadows the global upcase-dwim, which has no place in the
;; stack buffer); v u is calc-unpack, whose whole-entry behavior
;; mafcmd-unpack matches. Both keys keep the entry-scoped command.
(maf-bindings-define '(native) "M-u" #'mafcmd-unpack)
(maf-bindings-define '(calc native) "v u" #'mafcmd-unpack)
;; j U (with its j M-U alias) is calc-sel-unpack, which replaces a
;; selected one-argument call with its argument. That is the narrowing
;; reading of unwrapping, so the key takes mafcmd-unwrap: inside a
;; formula it peels the wrapper around point in place, and on a whole
;; entry it spreads the parts as M-u does.
;; In vim these arrive by derivation and the j motion prunes them —
;; the unpack keeps M-u and v u there until the relocation table
;; rehomes the j family (profile:vim in docs/bindings.org).
(maf-bindings-define '(calc native) "j U" #'mafcmd-unwrap)
(maf-bindings-define '(calc native) "j M-U" #'mafcmd-unwrap)

;; Push an index vector [1..n], the size prompted for — the legacy
;; config's v RET. The contextual mafcmd-index keeps v x; this is the
;; push-only sibling, and RET was free under calc's v prefix.
(maf-bindings-define '(native) "v RET" #'maf-index)

;; Keep only the part point names: it becomes the whole entry, the
;; formula around it discarded. On i for the plainest reading of
;; "isolate" — this is the one that isolates a sub-formula literally,
;; lifting it out of what surrounded it, where `mafcmd-isolate' next
;; door on j j isolates a variable by solving for it. "Raise" is the
;; name because it is `raise-sexp's operation, the form at point
;; replacing the form around it. j i is unbound in calc itself — its
;; j prefix is the selection commands, which have no i of their own,
;; keeping isolation on the capital j I — and the command belongs with
;; them, working as it does on the part point picks out.
(maf-bindings-define '(native) "j i" #'mafcmd-raise)

;; Group a vector's elements N at a time, N from the stack. l g is
;; unbound in calc itself — its l prefix is the logarithmic units,
;; which has no g — and it joins maf's other l bindings above.
(maf-bindings-define '(native) "l g" #'mafcmd-unique-groups)
;; Surround the target with vector brackets: the one-operand vector
;; builder, on the control twin of the | key that concatenates two
;; entries into one. Calc binds neither C-| nor anything else on the
;; control side of |, and the pairing is the whole point — | joins two
;; things into a vector, C-| wraps one.
(maf-bindings-define '(native) "C-|" #'mafcmd-bracket)
;; Flatten the target vector. Takes calc's v L from calc-lud (LU
;; decomposition), which the table in maf-cmds.el gives up its key for;
;; mafcmd-lud is still reachable by name. Flattening earns the vector
;; key: it is the everyday shape fix after a map or a pack leaves
;; rows where a plain list was wanted, and it sits a keystroke from
;; mafcmd-arrange (v a), the N-column form it degenerates from.
(maf-bindings-define '(native) "v L" #'mafcmd-flatten)
;; A second key for the sort, beside the table's v S: the key the
;; legacy config bound, kept for the muscle memory and the spared
;; shift. v o is unbound in calc itself, and the flag prefixes route
;; through it as through v S — I v o is the descending sort.
(maf-bindings-define '(native) "v o" #'mafcmd-sort)

;; The right triangle, all three keys together. f h keeps calc's own
;; hypotenuse key, for a command that answers where calc's gives up (see
;; `mafcmd-hypot'); f l is unbound in calc itself; f L takes the key from
;; calc-lnp1, which mafcmd-lnp1 cedes — see the table in maf-cmds.el,
;; where lnp1 keeps its place as expm1's Inverse variant (I f E) and
;; stays reachable by name. mafcmd-cath and mafcmd-hypot are each other's
;; Inverse variant, so I f l is the hypotenuse and I f h the leg.
(maf-bindings-define '(calc native) "f h" #'mafcmd-hypot)
(maf-bindings-define '(native) "f l" #'mafcmd-cath)
(maf-bindings-define '(native) "f L" #'mafcmd-unit-cath)

;; Absolute value, on calc's own key for it. The command left the table
;; in maf-cmds.el for the reason f h did: its vector-norm case needs the
;; expression raw, before a row's normalize can float an exact entry —
;; see `mafcmd-abs'.
(maf-bindings-define '(calc native) "A" #'mafcmd-abs)

;; Coordinate naming, cycling the name sets on repeat. Shadows
;; calc-copy-as-kill; maf-copy (M-w) copies the region or the entry,
;; and maf-kill (C-k) kills the whole entry onto the kill ring.
(maf-bindings-define '(native) "M-k" #'mafcmd-coordinate-toggle)

;; The digit-entry starters, mirroring calc-mode-map's calcDigit-start
;; set minus @, which maf-toggle-simplify shadows.
(mapc (lambda (x)
        (maf-bindings-define '(calc native)
                             (char-to-string x) #'maf-digit-start))
      "_0123456789.#")

;; Entry-beginning motion. Shadows calc's own M-m prefix, whose two
;; sequences (M-m t, M-m M-t) stay reachable as m t and m M-t.
(maf-bindings-define '(native) "M-m" #'maf-beginning-of-entry)

;; Motion by noun — the next or previous number, variable, or function
;; name — on the keys the global map gives `forward-word' and
;; `backward-word', which calc leaves alone. The same gesture over the
;; formula rather than over prose: word motion stops on the level number
;; in the line prefix, which is margin rather than term, and it lands
;; past the word rather than on it — where point names nothing to
;; resolve.
(maf-bindings-define '(native) "M-f" #'maf-forward-noun)
(maf-bindings-define '(native) "M-b" #'maf-backward-noun)

;; Motion by operand — the next place point names a sub-formula, so
;; repeated presses offer every target of the entry in turn. On M-e
;; and M-a, beside the noun motions on M-f and M-b: the meta row is
;; where maf's motions over an entry live, and the two pairs read
;; alike, forward on the right hand's key and back on the left's. The
;; shifted spaces they were (S-SPC, M-S-SPC) cost a terminal decode
;; table to say at all — xterm.el carries keycode 32 under alt and
;; ctrl+alt only — where a meta letter needs nothing.
;;
;; Calc binds neither key, so what is displaced is the global map's:
;; the sentence motions in stock Emacs, whose sentences a stack buffer
;; does not have. Stack mode only, deliberately: an edit session swaps
;; the local map and turns maf-mode off, and no editplus key carries
;; this motion into the editable text — the stack's targets are what
;; it walks. A prefix argument counts operands, backward when negative.
(maf-bindings-define '(native) "M-e" #'maf-forward-operand)
(maf-bindings-define '(native) "M-a" #'maf-backward-operand)

;; Step out to the enclosing sub-formula, taking the key the global map
;; gives `backward-up-list' — the same gesture, over the formula rather
;; than over the printed parens. Calc leaves C-M-u unbound, so nothing
;; of its own is shadowed. `backward-up-list' itself only reaches the
;; ancestors calc prints parens for, which leaves out the ones its
;; precedence rules let it drop (from b in sin(a b + c)^2 it lands on
;; the sin call, and never on a b or a b + c), and it reads the buffer
;; text, so a Big-language rendering leaves it nothing to walk.
(maf-bindings-define '(native) "C-M-u" #'maf-up-expression)

;; Cross the relation: one key to the whole left side, one to the whole
;; right — the largest formula there is on each, where the climb above
;; would arrive a level at a time. The parens for the shape a relation
;; has, two halves around a middle, and because calc's own use for them
;; is already gone in this layout: ( is the edit module's blank-vector
;; key and ) is unbound, both shadowing calc's complex-number
;; delimiters, which maf's algebraic entry supplies instead. The
;; vector-add keeps the key at home, where there is no entry to move
;; within and the motion has nothing to do — see `maf--goto-side'; the
;; edit module keeps its own plain "(" in the calc profile, whose
;; layout these motions are no part of.
(maf-bindings-define '(native) "(" #'maf-goto-left-side)
(maf-bindings-define '(native) ")" #'maf-goto-right-side)

;; The module toggle buffer. m is calc's mode prefix (m m saves the
;; modes, m d is degrees mode), which is where turning maf's own
;; features on and off belongs; m c is unbound in calc itself. Bound in
;; the escape map, not declared to profiles: every profile inherits it
;; through the base map, and it is the one key that stays when the
;; bindings module is off — the deliberate exception to the calc
;; profile's untouched-layout promise and to off's no-keys promise,
;; because this buffer is where profiles and modules are turned back
;; on; anywhere less durable and the way back is M-x by name. It also
;; lives here rather than in a module's toggle body —
;; `maf-list-modules' is core (core/maf-module.el), and the buffer that
;; toggles the modules cannot be a module itself.
(define-key maf-bindings-escape-map (kbd "m c") #'maf-list-modules)

;; The `M-h' stack-history binding is installed by the maf-history
;; module when it is enabled (see modules/maf-history.el), and the
;; `s o' formula menu by maf-formulas the same way — not here.

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
;; for the bury's Ctrl+Alt. The restack's Shift-backspace was decoded
;; here too until the restack moved to S-<return>.
;;
;; The bracket's C-| has the same gap for a different reason: control
;; plus a printable character has no ASCII form either, and xterm.el's
;; table stops at keycode 63 for the shifted punctuation (it lists
;; C-! through C-?, and | is 124). Which modifier the terminal reports
;; depends on whether it counts the shift that produced the | — take
;; both 6 (ctrl+shift) and 5 (ctrl alone).
(defun maf--tty-setup-keys ()
  "Decode terminal sequences for keys maf binds and `term/xterm.el' omits."
  (define-key input-decode-map "\e[27;7;127~" [C-M-backspace])
  (define-key input-decode-map "\e[127;7u" [C-M-backspace])
  (define-key input-decode-map "\e[27;6;124~" [?\C-\|])
  (define-key input-decode-map "\e[124;6u" [?\C-\|])
  (define-key input-decode-map "\e[27;5;124~" [?\C-\|])
  (define-key input-decode-map "\e[124;5u" [?\C-\|]))

;; `input-decode-map' is terminal-local, so this runs once per tty
;; rather than once at load.
(add-hook 'tty-setup-hook #'maf--tty-setup-keys)
;; The hook has already run for a terminal that exists by now.
(unless (display-graphic-p)
  (maf--tty-setup-keys))

;;; The vim profile's motions

;; Vim's navigation keys over maf's commands (profile:vim in
;; docs/bindings.org): each key does what its Emacs cousin does —
;; fine motion on h/l as C-b/C-f, vertical on j/k as C-n/C-p, noun
;; motion on w/b as M-f/M-b, which stay bound too. Everything else is
;; native's, by derivation; these own claims displace the inherited
;; families they overlap, whose new homes await the relocation table.
(maf-bindings-define '(vim) "h" #'backward-char)
(maf-bindings-define '(vim) "l" #'forward-char)
(maf-bindings-define '(vim) "j" #'next-line)
(maf-bindings-define '(vim) "k" #'previous-line)
(maf-bindings-define '(vim) "w" #'maf-forward-noun)
(maf-bindings-define '(vim) "b" #'maf-backward-noun)
;; And vim's delete reflex: x does what C-d does. Displaces the
;; inherited single-key expand, which keeps its table key a x and
;; its name.
(maf-bindings-define '(vim) "x" #'maf-del)
;; The displaced expand moves up a case: X, whose inherited resident
;; mafcmd-log-exp cedes the key — reachable by name in vim; its
;; native home is untouched.
(maf-bindings-define '(vim) "X" #'mafcmd-expand)
;; maf's custom-letter family — native's l prefix — rides o in vim,
;; where l is a motion: the same second letters, o l float-frac where
;; native says l l. Mirrored from native's registered l declarations
;; at this point in the load, so a key added to the family above
;; lands in both profiles without naming vim.
(pcase-dolist (`(,key . ,command)
               (plist-get (maf-bindings--profile 'native) :defaults))
  ;; Minus the doubled l l: the toggle's vim home is M-o (below),
  ;; and a spare o l would only shadow the finger slip it invites.
  (when (and (string-prefix-p "l " key)
             (not (equal key "l l")))
    (maf-bindings-define '(vim) (concat "o " (substring key 2)) command)))
;; The family displaces the inherited commands on o's case pair, and
;; they trade places one step over: the commute (native's O) takes
;; the family's free doubled slot o o (native binds no l o), and the
;; displaced reciprocal takes the capital O the commute vacates.
(maf-bindings-define '(vim) "o o" #'mafcmd-commute)
(maf-bindings-define '(vim) "O" #'mafcmd-inv)
;; The float/frac toggle, the family's daily key, gets a single
;; chord: M-o, meta of the family's letter, tappable in a hold the
;; way native's l l is — its only vim home; the mirror above skips
;; l l. Displaces the inherited mod-360, which rides the family on
;; o w instead (l w above).
(maf-bindings-define '(vim) "M-o" #'mafcmd-float-frac)
;; The selection/structure family — native's j prefix — rides its
;; capital in vim, where the lowercase is a motion: the same second
;; letters one shift over (J i isolate, J x distribute, J f merge,
;; J e jump-equals), mirrored from native's registered j declarations
;; so a key added to the family lands in both profiles. Displaces the
;; inherited mafcmd-conj from J; it rides the custom-letter family on
;; its initial instead — o j, native's l j through the mirror above.
(pcase-dolist (`(,key . ,command)
               (plist-get (maf-bindings--profile 'native) :defaults))
  (when (string-prefix-p "j " key)
    (maf-bindings-define '(vim) (concat "J " (substring key 2)) command)))
;; Numeric evaluation, homeless here since k became a motion, spends
;; the last weak single letter: y, whose calc-copy-to-buffer beneath
;; has no reflex use. The heaviest homeless command takes the
;; cheapest key; I y still reaches mafcmd-identify through the
;; command's own flag route.
(maf-bindings-define '(vim) "y" #'mafcmd-evaluate)
;; Vim's line-edge reflex: $ to the end of the line, and from the end
;; a bounce to the entry's start, M-m's landing. Shadows the $-seeded
;; algebraic entry, which ' still opens.
(maf-bindings-define '(vim) "$" #'maf-end-of-line-bounce)

;; Everything declared; compile, and apply when the module is live.
(maf-bindings--refresh)

(provide 'maf-bindings-decls)
