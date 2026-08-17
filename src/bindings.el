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

;; A second key for the square root, beside Q (mafcmd-sqrt in the
;; table): the root is reached for far more often than integer
;; division, whose key this was — calc's \ is shadowed, and the idiv
;; row in maf-cmds.el keeps no key.
(define-key maf-mode-map (kbd "\\") #'mafcmd-sqrt)
;; The square on a key of its own: I Q reaches mafcmd-sqr through the
;; inverse flag, and W is free in both maps. The next key over from
;; Q, and the shape of the two square-root keys' inverse.
(define-key maf-mode-map (kbd "W") #'mafcmd-sqr)
;; Shadows calc-stirling's key; the contextual stirling pair
;; (mafcmd-stir1/stir2) cedes it — see the table in maf-cmds.el.
(define-key maf-mode-map (kbd "k s") #'mafcmd-complete-square)
;; Shadows calc-double-factorial's key; mafcmd-dfact cedes it — see
;; the table in maf-cmds.el.
(define-key maf-mode-map (kbd "k d") #'mafcmd-factor-powers)
(define-key maf-mode-map (kbd "l f") #'mafcmd-factor-by)
(define-key maf-mode-map (kbd "l F") #'mafcmd-factor-gcd)
(define-key maf-mode-map (kbd "l t") #'mafcmd-collect-fractions)
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
;; Map a formula over the target: each element of a vector, both sides
;; of an equation. # prompts for the formula, $ takes it from the top
;; of the stack. $ shadows calc-auto-algebraic-entry — starting an
;; algebraic entry with the stack top is rare enough to give up, and
;; maf's own entry reaches it other ways; # gives up its digit-starter
;; role (radix entry still types 16#FF fine once begun with a digit).
;; Calc's a M keeps the operator prompt (mafcmd-mapeq in the table),
;; which stays the escape hatch. M is the map flag, below.
(define-key maf-mode-map (kbd "#") #'mafcmd-map)
(define-key maf-mode-map (kbd "$") #'mafcmd-map-stack)
;; The map flag: the next command — not a formula — maps over the
;; target, one run per vector element or equation side. A fancy prefix
;; like calc's K/I/H, so it chains with them; M shadows
;; calc-more-recursion-depth.
(define-key maf-mode-map (kbd "M") #'mafcmd-map-flag)
;; Shift the term under point through its associative chain. Lowercase
;; j l / j r (calc binds the shifts to capital j L / j R, left reachable).
(define-key maf-mode-map (kbd "j l") #'maf-commute-left)
(define-key maf-mode-map (kbd "j r") #'maf-commute-right)
;; Move the term under point across the = (or !=) it sits in. Lowercase
;; j e, beside the shifts above, for the same reason: calc keeps the
;; jump on the capital j E, which stays reachable and unshadowed for
;; the plain = -only behavior that leaves its selection standing.
;; Shadows calc-enable-selections, whose toggle maf has no use for —
;; every maf command resolves its subject from point.
(define-key maf-mode-map (kbd "j e") #'maf-jump-equals)
;; Spread the formula around the target inward over its parts, and the
;; reverse. These take calc's own keys rather than a lowercase twin:
;; unlike the jump and the shifts above, the contextual versions have
;; no behavior worth reaching past them for — calc's differ only in
;; requiring the selection to be made first and leaving it standing,
;; both of which maf supplies from point instead.
(define-key maf-mode-map (kbd "j D") #'maf-distribute)
(define-key maf-mode-map (kbd "j M") #'maf-merge)
;; Inside digit entry j is a jump of its own: `maf-digit-jump'
;; (src/minibuffer.el) ends the entry and sends point to the stack
;; level the number named, the prefix's reading one level out.
;; Shadows calc-call-last-kbd-macro.
(define-key maf-mode-map (kbd "X") #'mafcmd-log-exp)
;; A single-key alias for expand, which also keeps its table key a x.
;; Shadows calc-execute-extended-command.
(define-key maf-mode-map (kbd "x") #'mafcmd-expand)
;; The reciprocal. It sat on i until the prompted solve took that key
;; back, and takes o in turn from the home motion below; its table key
;; & went to the big-language toggle next, so this is now its only
;; key. Shadows calc-realign, whose bare press only undoes horizontal
;; scrolling; M-x calc-realign still reaches that and the prefixed
;; home motion both.
(define-key maf-mode-map (kbd "o") #'mafcmd-inv)
;; Toggle calc's Big 2D display language. Takes &, the key the
;; reciprocal cedes above (see the inv row in maf-cmds.el); calc's own
;; & is calc-inv, which mafcmd-inv subsumes, so nothing is lost to the
;; shadow. The toggle held G until maf-go-home took it (below); calc's
;; own d B / d N stay the one-way switches.
(define-key maf-mode-map (kbd "&") #'maf-toggle-big-language)
;; Send point home, the one motion the buffer needs a key for: every
;; other command already leaves it there. Pressed at home it returns to
;; the mark instead — its own trip out left one, as every maf command
;; that homes point does — so the key is the whole round trip: out for
;; a command that wants the entry, back for one that wants the term.
;; It sat on o until the reciprocal above took that key. Takes calc's
;; G, which mafcmd-arg cedes (see the table in maf-cmds.el);
;; `maf-toggle-big-language' held G before and now sits on & (above).
(define-key maf-mode-map (kbd "G") #'maf-go-home)
;; A toggle between pair members is its own inverse, so both directions
;; run the same command.
(define-key maf-mode-map (kbd "S-<up>") #'mafcmd-toggle-op)
(define-key maf-mode-map (kbd "S-<down>") #'mafcmd-toggle-op)
(define-key maf-mode-map (kbd ",") #'maf-quick-variable)
;; Recall a variable by picking it off a list of values. Shadows
;; calc-precision, whose only key this is: a mode setting that is set
;; once and then left alone, reachable by name afterwards, giving up
;; its key to something pressed while working.
(define-key maf-mode-map (kbd "p") #'maf-browse-variables)
;; Literal recall: what was stored is what lands, unsimplified. r 0-9
;; shadow calc's quick recall, which renormalizes under the current
;; modes on the way out; r r is unbound in calc itself (its prompt
;; recall lives on s r, which keeps its key and its simplifying push).
(define-key maf-mode-map (kbd "r r") #'maf-recall-variable)
(dotimes (i 10)
  (define-key maf-mode-map (kbd (format "r %d" i)) #'maf-recall-quick))
;; The in-place editing entry keys (SPC / ` / C-o / "(") are
;; installed by the edit module when it is enabled (see
;; modules/edit.el), not here. ` shadows calc-edit, the command the
;; whole module replaces.
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
;; Yank, completing the kill-ring trio. Shadows calc-yank to read a
;; number written with digit-group commas ("1,234,567") as one number
;; rather than three comma-separated entries; otherwise identical,
;; radix prefix included.
(define-key maf-mode-map (kbd "C-y") #'maf-yank)
;; Shadows calc's TAB with the contextual swap. Bind both the terminal
;; and GUI events.
(define-key maf-mode-map (kbd "TAB") #'maf-swap-up)
(define-key maf-mode-map (kbd "<tab>") #'maf-swap-up)
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
(define-key maf-mode-map (kbd "C-M-<backspace>") #'maf-roll-to-bottom)
(define-key maf-mode-map (kbd "C-M-DEL") #'maf-roll-to-bottom)
(define-key maf-mode-map (kbd "C-M-h") #'maf-roll-to-bottom)
;; Restack: the entry at point travels to the top, point riding along.
;; The long-range move up, beside the bury it mirrors. It sits on
;; S-<return>, the key the edit module's add-entry-below gave up (see
;; the RET family below); the shift-backspace it used to share with the
;; bury is unbound, and the decode entry that made that key reach a
;; terminal is gone with it. A terminal folds Shift-RET back to plain
;; RET, so this is a GUI key: on a tty the restack is reachable by name.
(define-key maf-mode-map (kbd "S-<return>") #'maf-roll-to-top)
;; Carry the entry at point one line up or down the screen, point
;; riding along — the stack's version of moving a line in a text
;; buffer, and the one-step counterpart of the backspace pair above,
;; which sends an entry to either end. Calc binds neither key, and the
;; arrows are already the buffer's motion keys; S-<up>/S-<down> next to
;; them toggle the operator at point. A prefix argument counts lines.
(define-key maf-mode-map (kbd "M-<up>") #'maf-carry-up)
(define-key maf-mode-map (kbd "M-<down>") #'maf-carry-down)
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
;; its own — the RET family is full (M-RET below, C-RET on
;; `mafcmd-let', S-RET on the restack) and W is the only unbound
;; single key left in the buffer, too scarce to spend on where point
;; lands. Contextual dup has no
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
;; S-<return> is the restack (bound above, beside the bury). It was the
;; edit module's add-entry-below, which is unbound now and reachable by
;; name: C-o opens an entry above point, and above the entry below point
;; is where add-entry-below opened, so the gesture survives one line
;; down — with ` still opening at the bottom.

;; Equate gets both = (shadowing calc-evaluate) and e (shadowing the
;; e-notation digit start). Inside digit entry e reaches the same
;; command: `maf-digit-equal-to' (src/minibuffer.el) ends the entry on
;; it and the number becomes the argument.
(define-key maf-mode-map (kbd "=") #'mafcmd-equal-to)
(define-key maf-mode-map (kbd "e") #'mafcmd-equal-to)
;; The other direction: drop the relation, keep a side. M-. is unbound
;; in calc itself; a . is calc's own key for the operation, which the
;; table in maf-cmds.el no longer claims.
(define-key maf-mode-map (kbd "M-.") #'mafcmd-remove-equal)
(define-key maf-mode-map (kbd "a .") #'mafcmd-remove-equal)

;; The simplification toggle takes @ from the digit-entry starters
;; below; inside digit entry @ still means degrees, since the entry
;; minibuffer is calc's own but for the keys src/minibuffer.el takes
;; there (; : and n P e SPC j).
(define-key maf-mode-map (kbd "@") #'maf-toggle-simplify)

;; Session reset, and the modes-only half beside it. Both keys are
;; unbound in calc itself; whatever the global map puts there
;; (erase-buffer, `reposition-window', a magit command) has no business
;; in a stack buffer, and C-M-k is exactly the destructive global these
;; shadow — one fingerslip away from wiping the wrong buffer.
(define-key maf-mode-map (kbd "C-M-k") #'maf-reset)
(define-key maf-mode-map (kbd "C-M-l") #'maf-reset-settings)

;; Auto-solve: solve the entry for a variable, cycling through them on
;; repeat. The entry is the subject wherever point sits within it — the
;; sub-formula targeting lives on j i below, so this key means the same
;; thing from anywhere on the line. M-i is unbound in calc itself.
(define-key maf-mode-map (kbd "M-i") #'mafcmd-auto-solve)
;; The same solve, targeting the sub-expression under point: isolate it,
;; falling back to the variable solve when there is nothing to isolate.
;; Lowercase j i, where calc keeps the operation on the capital j I
;; (calc-sel-isolate) — the same trade maf makes for the commute shifts
;; (j l / j r) and the equals jump (j e), leaving calc's own command
;; unshadowed and its key reachable.
(define-key maf-mode-map (kbd "j i") #'mafcmd-isolate)
;; The same solve again, with the variable named rather than picked.
;; It held i before, yielded the key to the reciprocal, and takes it
;; back now that the reciprocal sits on o — the naming solve is the
;; everyday one, so it gets the single key while the auto-solve keeps
;; the meta. Shadows calc-info, which stays reachable on calc's own
;; help prefix (h i) and as M-x calc-info; calc's own key for the
;; operation, a S, stays with `mafcmd-solve' (see the table in
;; maf-cmds.el), which takes its variable from the stack.
(define-key maf-mode-map (kbd "i") #'mafcmd-solve-for)
;;
;; Invert the function at point, beside the solve commands. l v is
;; unbound in calc itself (its l prefix is the logarithmic units).
(define-key maf-mode-map (kbd "l v") #'mafcmd-inverse-function)
;; Split an absolute-value inequality into a compound one — a solve of
;; sorts, so it sits with the solving keys. a k is unbound in calc
;; itself (a is its algebra prefix).
(define-key maf-mode-map (kbd "a k") #'mafcmd-abs-ineq)
;; Substitution, on calc's own key for it: mafcmd-substitute shadows
;; calc-substitute, keeping the two prompts and adding a default for
;; the first, a contextual subject, and $ for the stack.
(define-key maf-mode-map (kbd "a b") #'mafcmd-substitute)
;; Quick substitution: apply an assignment from the stack to the
;; contextual subject. C-<return> is the one-hand chord a substitution
;; is worth, and the edit module's quick-add gave the key up for it
;; (`, C-o and "(" remain, and ` opens the same bottom entry C-RET
;; used to, as a trip home). It replaces C-c C-c, the conventional
;; mode-specific
;; "apply this" gesture, which had been the command's only key and is
;; unbound again — two hands and four keys for something reached this
;; often, where the leaf is a control character calc's fancy prefix
;; would rather not carry (K C-c C-c is what `maf--fancy-prefix-keep's
;; provisional path was written for; see src/stack.el). During digit
;; entry C-<return> is calc's own map, where it stays
;; `maf-digit-commit-here' (src/minibuffer.el).
(define-key maf-mode-map (kbd "C-<return>") #'mafcmd-let)
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

;; Keep only the part point names: it becomes the whole entry, the
;; formula around it discarded. j j is unbound in calc itself — its j
;; prefix is the selection commands, which have no j of their own — and
;; the command belongs with them, working as it does on the part point
;; picks out. "Raise" is `raise-sexp's operation, the form at point
;; replacing the form around it; the word "isolate" is spoken for here
;; by `mafcmd-auto-solve', which isolates a sub-expression by solving
;; the relation for it.
(define-key maf-mode-map (kbd "j j") #'mafcmd-raise)

;; Group a vector's elements N at a time, N from the stack. l g is
;; unbound in calc itself — its l prefix is the logarithmic units,
;; which has no g — and it joins maf's other l bindings above.
(define-key maf-mode-map (kbd "l g") #'mafcmd-unique-groups)
;; Surround the target with vector brackets: the one-operand vector
;; builder, on the control twin of the | key that concatenates two
;; entries into one. Calc binds neither C-| nor anything else on the
;; control side of |, and the pairing is the whole point — | joins two
;; things into a vector, C-| wraps one.
(define-key maf-mode-map (kbd "C-|") #'mafcmd-bracket)
;; Flatten the target vector. Takes calc's v L from calc-lud (LU
;; decomposition), which the table in maf-cmds.el gives up its key for;
;; mafcmd-lud is still reachable by name. Flattening earns the vector
;; key: it is the everyday shape fix after a map or a pack leaves
;; rows where a plain list was wanted, and it sits a keystroke from
;; mafcmd-arrange (v a), the N-column form it degenerates from.
(define-key maf-mode-map (kbd "v L") #'mafcmd-flatten)

;; The right triangle, all three keys together. f h keeps calc's own
;; hypotenuse key, for a command that answers where calc's gives up (see
;; `mafcmd-hypot'); f l is unbound in calc itself; f L takes the key from
;; calc-lnp1, which mafcmd-lnp1 cedes — see the table in maf-cmds.el,
;; where lnp1 keeps its place as expm1's Inverse variant (I f E) and
;; stays reachable by name. mafcmd-cath and mafcmd-hypot are each other's
;; Inverse variant, so I f l is the hypotenuse and I f h the leg.
(define-key maf-mode-map (kbd "f h") #'mafcmd-hypot)
(define-key maf-mode-map (kbd "f l") #'mafcmd-cath)
(define-key maf-mode-map (kbd "f L") #'mafcmd-unit-cath)

;; Absolute value, on calc's own key for it. The command left the table
;; in maf-cmds.el for the reason f h did: its vector-norm case needs the
;; expression raw, before a row's normalize can float an exact entry —
;; see `mafcmd-abs'.
(define-key maf-mode-map (kbd "A") #'mafcmd-abs)

;; Coordinate naming, cycling the name sets on repeat. Shadows
;; calc-copy-as-kill; maf-copy (M-w) copies the region or the entry,
;; and maf-kill (C-k) kills the whole entry onto the kill ring.
(define-key maf-mode-map (kbd "M-k") #'mafcmd-coordinate-toggle)

;; The digit-entry starters, mirroring calc-mode-map's calcDigit-start
;; set minus @, which maf-toggle-simplify shadows, and minus #, which
;; mafcmd-map takes.
(mapc (lambda (x)
        (define-key maf-mode-map (char-to-string x) #'maf-digit-start))
      "_0123456789.")

;; Entry-beginning motion. Shadows calc's own M-m prefix, whose two
;; sequences (M-m t, M-m M-t) stay reachable as m t and m M-t.
(define-key maf-mode-map (kbd "M-m") #'maf-beginning-of-entry)

;; Motion by noun — the next or previous number, variable, or function
;; name — on the keys the global map gives `forward-word' and
;; `backward-word', which calc leaves alone. The same gesture over the
;; formula rather than over prose: word motion stops on the level number
;; in the line prefix, which is margin rather than term, and it lands
;; past the word rather than on it — where point names nothing to
;; resolve.
(define-key maf-mode-map (kbd "M-f") #'maf-forward-noun)
(define-key maf-mode-map (kbd "M-b") #'maf-backward-noun)

;; Horizontal scrolling, on calc's own two keys with the commands
;; swapped. Calc names the direction the text slides — < is
;; `calc-scroll-left', which slides the line left and so uncovers its
;; right end — leaving each bracket pointing away from what it brings
;; into view. Swapped, the bracket points at what it reveals: > walks
;; out to the right end of an entry too wide for the window, < back
;; toward its left.
(define-key maf-mode-map (kbd ">") #'calc-scroll-left)
(define-key maf-mode-map (kbd "<") #'calc-scroll-right)

;; Step out to the enclosing sub-formula, taking the key the global map
;; gives `backward-up-list' — the same gesture, over the formula rather
;; than over the printed parens. Calc leaves C-M-u unbound, so nothing
;; of its own is shadowed. `backward-up-list' itself only reaches the
;; ancestors calc prints parens for, which leaves out the ones its
;; precedence rules let it drop (from b in sin(a b + c)^2 it lands on
;; the sin call, and never on a b or a b + c), and it reads the buffer
;; text, so a Big-language rendering leaves it nothing to walk.
(define-key maf-mode-map (kbd "C-M-u") #'maf-up-expression)

;; The module toggle buffer. m is calc's mode prefix (m m saves the
;; modes, m d is degrees mode), which is where turning maf's own
;; features on and off belongs; m c is unbound in calc itself. This one
;; lives here rather than in a module's toggle body —
;; `maf-list-modules' is core (core/maf-module.el), and the buffer that
;; toggles the modules cannot be a module itself.
(define-key maf-mode-map (kbd "m c") #'maf-list-modules)

;; The `t d' stack-timeline binding is installed by the maf-timeline
;; module when it is enabled (see modules/maf-timeline.el), and the
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

(provide 'maf-bindings)
