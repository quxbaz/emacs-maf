;; Behavior snapshot of maf's key bindings, taken 2026-08-18 before the
;; bindings-profile refactor (docs/bindings.org phase 1). Every entry of
;; maf-mode-map (flattened), maf's calc-digit-map overrides, a few
;; deliberate fall-throughs to calc, and one module toggle's key effect
;; are pinned as real key-binding answers in the calc buffer. The
;; refactor must keep every answer identical. Eight answers have moved
;; since deliberately: j U and j M-U took mafcmd-unwrap, the narrowing
;; sibling of mafcmd-unpack, when the contextual unwrap landed; the
;; parens became the relation motions maf-goto-left-side and
;; maf-goto-right-side, ( displacing maf-edit-add-vector, which the
;; motion still reaches at home and which keeps the key outright in the
;; calc profile; F is a second key for mafcmd-fold in native, floor,
;; whose table key it was, keeping no key there; and : left the
;; fall-throughs for mafcmd-sqr, the unshifted key beside W, calc's
;; fdiv keeping the key in the calc profile; and & and G left the two
;; commands that had borrowed them when the preview panel took over
;; what both were for — & back to mafcmd-inv, calc's own command for
;; the key, and G to maf-preview-show, which is bound whether or not
;; the preview module is on.

(defvar maf--snapshot-stack-rows
  '(("!" . mafcmd-fact) ("#" . maf-digit-start)  ("%" . mafcmd-mod) ("&" . mafcmd-inv) ("(" . maf-goto-left-side) (")" . maf-goto-right-side) ("*" . mafcmd-mul) ("+" . mafcmd-add) ("," . maf-quick-variable) ("-" . mafcmd-sub) ("." . maf-digit-start) ("/" . mafcmd-div) ("0" . maf-digit-start) ("1" . maf-digit-start) ("2" . maf-digit-start) ("3" . maf-digit-start) ("4" . maf-digit-start) ("5" . maf-digit-start) ("6" . maf-digit-start) ("7" . maf-digit-start) ("8" . maf-digit-start) ("9" . maf-digit-start) (":" . mafcmd-sqr) ("<" . mafcmd-decrement) ("<f5>" . my/maf-seed-calc) ("<remap> <calc-redo>" . maf-redo) ("<remap> <calc-undo>" . maf-undo) ("<remap> <undo-redo>" . maf-redo) ("<remap> <undo>" . maf-undo) ("<tab>" . maf-swap-up) (">" . mafcmd-increment) ("?" . maf-options) ("@" . maf-toggle-simplify) ("A" . mafcmd-abs) ("B" . mafcmd-log) ("C" . mafcmd-cos) ("C-<return>" . maf-dup-here-or-clear-selections) ("C-M-<backspace>" . maf-roll-to-bottom) ("C-M-DEL" . maf-roll-to-bottom) ("C-M-h" . maf-roll-to-bottom) ("C-M-k" . maf-reset) ("C-M-l" . maf-reset-settings) ("C-M-u" . maf-up-expression) ("C-b" . maf-backward-char) ("C-c C-c" . mafcmd-esimplify) ("C-d" . maf-del) ("C-k" . maf-kill) ("C-o" . maf-goto-other-side) ("C-y" . maf-yank) ("C-|" . mafcmd-bracket) ("D" . maf-redo) ("DEL" . maf-del) ("E" . mafcmd-exp) ("F" . mafcmd-fold) ("G" . maf-preview-show) ("J" . mafcmd-mul) ("L" . mafcmd-ln) ("M" . mafcmd-map-flag) ("M-." . mafcmd-remove-equal) ("M-a" . maf-backward-operand) ("M-e" . maf-forward-operand) ("M-<down>" . maf-carry-down) ("M-<return>" . mafcmd-let) ("M-<up>" . maf-carry-up) ("M-RET" . mafcmd-let) ("M-b" . maf-backward-noun) ("M-c" . mafcmd-complement) ("M-f" . maf-forward-noun) ("M-h" . maf-history) ("M-i" . mafcmd-auto-solve) ("M-k" . mafcmd-coordinate-toggle) ("M-l" . mafcmd-ref-angle) ("M-m" . maf-beginning-of-entry) ("M-n" . maf-recall-next) ("M-o" . mafcmd-mod-360) ("M-p" . maf-recall-previous) ("M-s" . mafcmd-supplement) ("M-u" . mafcmd-unpack) ("M-w" . maf-copy) ("N" . mafcmd-negate) ("O" . mafcmd-commute) ("P" . maf-pi) ("Q" . mafcmd-sqrt) ("R" . mafcmd-round) ("RET" . maf-dup-or-clear-selections) ("S" . mafcmd-sin) ("S-<down>" . mafcmd-toggle-op) ("S-<return>" . maf-roll-to-top) ("S-<up>" . mafcmd-toggle-op) ("SPC" . maf-edit) ("T" . mafcmd-tan) ("TAB" . maf-swap-up) ("U" . maf-undo) ("W" . mafcmd-sqr) ("X" . mafcmd-log-exp)  ("\\" . mafcmd-sqrt)  ("^" . mafcmd-pow) ("_" . maf-digit-start) ("`" . maf-edit-entry-at-home) ("a !" . mafcmd-lnot) ("a #" . mafcmd-neq) ("a %" . mafcmd-prem) ("a &" . mafcmd-land) ("a ." . mafcmd-remove-equal) ("a /" . mafcmd-pdivrem) ("a <" . mafcmd-lt) ("a =" . mafcmd-eq) ("a >" . mafcmd-gt) ("a L" . mafcmd-poly-lcm) ("a M" . mafcmd-mapeq) ("a P" . mafcmd-roots) ("a S" . mafcmd-solve) ("a [" . mafcmd-leq) ("a \\" . mafcmd-pdiv) ("a ]" . mafcmd-geq) ("a _" . mafcmd-subscr) ("a a" . mafcmd-apart) ("a b" . mafcmd-substitute) ("a c" . mafcmd-collect) ("a d" . mafcmd-deriv) ("a e" . mafcmd-simplify) ("a f" . mafcmd-factor) ("a g" . mafcmd-pgcd) ("a i" . mafcmd-integ) ("a k" . mafcmd-abs-ineq) ("a l" . mafcmd-roots-for) ("a m" . mafcmd-match) ("a n" . mafcmd-nrat) ("a r" . mafcmd-rewrite) ("a s" . mafcmd-esimplify) ("a x" . mafcmd-expand) ("a {" . mafcmd-in) ("a |" . mafcmd-lor) ("b %" . mafcmd-relch) ("b I" . mafcmd-irr) ("b L" . mafcmd-ash) ("b N" . mafcmd-npv) ("b R" . mafcmd-rash) ("b a" . mafcmd-and) ("b c" . mafcmd-clip) ("b d" . mafcmd-diff) ("b l" . mafcmd-lsh) ("b n" . mafcmd-not) ("b o" . mafcmd-or) ("b p" . mafcmd-vpack) ("b r" . mafcmd-rsh) ("b t" . mafcmd-rot) ("b u" . mafcmd-vunpack) ("b x" . mafcmd-xor) ("c d" . mafcmd-deg) ("c h" . mafcmd-hms) ("c r" . mafcmd-rad) ("e" . mafcmd-equal-to) ("f A" . mafcmd-abssqr) ("f E" . mafcmd-expm1) ("f G" . mafcmd-gammaP) ("f I" . mafcmd-ilog) ("f L" . mafcmd-unit-cath) ("f M" . mafcmd-mant) ("f Q" . mafcmd-isqrt) ("f S" . mafcmd-scf) ("f T" . mafcmd-arctan2) ("f X" . mafcmd-xpon) ("f [" . mafcmd-decr) ("f ]" . mafcmd-incr) ("f b" . mafcmd-beta) ("f e" . mafcmd-erf) ("f g" . mafcmd-gamma) ("f h" . mafcmd-hypot) ("f i" . mafcmd-im) ("f j" . mafcmd-besJ) ("f l" . mafcmd-cath) ("f n" . mafcmd-min) ("f r" . mafcmd-re) ("f s" . mafcmd-sign) ("f x" . mafcmd-max) ("f y" . mafcmd-besY) ("h 1" . mafcmd-nth-element) ("h 2" . mafcmd-nth-element) ("h 3" . mafcmd-nth-element) ("h 4" . mafcmd-nth-element) ("h 5" . mafcmd-nth-element) ("h 6" . mafcmd-nth-element) ("h 7" . mafcmd-nth-element) ("h 8" . mafcmd-nth-element) ("h 9" . mafcmd-nth-element) ("h h" . mafcmd-head) ("h l" . mafcmd-rtail) ("i" . mafcmd-solve-for) ("j D" . maf-distribute) ("j M" . maf-merge) ("j M-U" . mafcmd-unwrap) ("j U" . mafcmd-unwrap) ("j e" . maf-jump-equals) ("j j" . mafcmd-isolate) ("j k" . mafcmd-raise) ("j l" . maf-commute-left) ("j r" . maf-commute-right) ("k C" . mafcmd-utpc) ("k F" . mafcmd-prfac) ("k P" . mafcmd-utpp) ("k T" . mafcmd-utpt) ("k b" . mafcmd-bern) ("k c" . mafcmd-choose) ("k d" . mafcmd-factor-powers) ("k e" . mafcmd-euler) ("k f" . mafcmd-factor) ("k g" . mafcmd-gcd) ("k h" . mafcmd-shuffle) ("k k" . mafcmd-esimplify) ("k l" . mafcmd-lcm) ("k m" . mafcmd-moebius) ("k n" . mafcmd-nextprime) ("k p" . mafcmd-perm) ("k r" . mafcmd-random) ("k s" . mafcmd-complete-square) ("k t" . mafcmd-perm) ("k v" . mafcmd-evaluate) ("l D" . mafcmd-factor-powers) ("l F" . mafcmd-factor-gcd) ("l R" . maf-saved-stacks) ("l S" . maf-save-stack) ("l a" . mafcmd-poly-roots) ("l b" . maf-keys) ("l c" . mafcmd-collect-fractions) ("l d" . mafcmd-to-degrees) ("l e" . mafcmd-log-exp) ("l f" . mafcmd-factor-by) ("l g" . mafcmd-unique-groups) ("l j" . mafcmd-conj) ("l l" . mafcmd-float-frac) ("l r" . mafcmd-to-radians) ("l s" . mafcmd-complete-square) ("l t" . mafcmd-apart) ("l v" . mafcmd-inverse-function) ("l w" . mafcmd-mod-360) ("l x" . mafcmd-swap-vars) ("m c" . maf-list-modules) ("n" . mafcmd-neg) ("o" . mafcmd-inv) ("p" . maf-browse-variables) ("r 0" . maf-recall-quick) ("r 1" . maf-recall-quick) ("r 2" . maf-recall-quick) ("r 3" . maf-recall-quick) ("r 4" . maf-recall-quick) ("r 5" . maf-recall-quick) ("r 6" . maf-recall-quick) ("r 7" . maf-recall-quick) ("r 8" . maf-recall-quick) ("r 9" . maf-recall-quick) ("r r" . maf-recall-variable) ("s :" . mafcmd-assign) ("s =" . mafcmd-evalto) ("s o" . maf-formulas) ("t D" . mafcmd-date) ("t I" . mafcmd-incmonth) ("t J" . mafcmd-julian) ("t M" . mafcmd-newmonth) ("t U" . mafcmd-unixtime) ("t W" . mafcmd-newweek) ("t Y" . mafcmd-newyear) ("u C" . mafcmd-vcov) ("u G" . mafcmd-vgmean) ("u M" . mafcmd-vmean) ("u N" . mafcmd-vmin) ("u R" . mafcmd-rms) ("u S" . mafcmd-vsdev) ("u X" . mafcmd-vmax) ("v #" . mafcmd-vcard) ("v +" . mafcmd-rdup) ("v -" . mafcmd-vdiff) ("v :" . mafcmd-vspan) ("v A" . mafcmd-apply) ("v C" . mafcmd-cross) ("v D" . mafcmd-det) ("v E" . mafcmd-venum) ("v F" . mafcmd-vfloor) ("v G" . mafcmd-grade) ("v H" . mafcmd-histogram) ("v I" . mafcmd-inner) ("v L" . mafcmd-flatten) ("v N" . mafcmd-cnorm) ("v O" . mafcmd-outer) ("v R" . mafcmd-fold) ("v RET" . maf-index) ("v S" . mafcmd-sort) ("v T" . mafcmd-tr) ("v U" . mafcmd-accum) ("v V" . mafcmd-vunion) ("v X" . mafcmd-vxor) ("v ^" . mafcmd-vint) ("v a" . mafcmd-arrange) ("v b" . mafcmd-cvec) ("v c" . mafcmd-mcol) ("v d" . mafcmd-diag) ("v e" . mafcmd-vexp) ("v f" . mafcmd-find) ("v h" . mafcmd-head) ("v k" . mafcmd-cons) ("v l" . mafcmd-vlen) ("v m" . mafcmd-vmask) ("v n" . mafcmd-rnorm) ("v o" . mafcmd-sort) ("v p" . mafcmd-pack) ("v r" . mafcmd-mrow) ("v t" . mafcmd-trn) ("v u" . mafcmd-unpack) ("v v" . mafcmd-rev) ("v x" . mafcmd-index) ("v ~" . mafcmd-vcompl) ("x" . mafcmd-expand) ("|" . mafcmd-vconcat))
  "Flattened (KEY-DESCRIPTION . COMMAND) rows of maf-mode-map.")

(defvar maf--snapshot-digit-rows
  '((":" . maf-digit-sqr) (";" . maf-digit-colon) ("C-<return>" . maf-digit-commit-here) ("C-g" . maf-digit-quit) ("P" . maf-digit-pi) ("RET" . maf-digit-commit-contextual) ("e" . maf-digit-equal-to) ("j" . maf-digit-jump) ("n" . maf-digit-pi) ("o" . maf-digit-mod-360))
  "maf's calc-digit-map overrides, plus C-g.")

(defun maf--snapshot-mismatches (rows)
  "Rows of ROWS whose live `key-binding' answer differs."
  (let (bad)
    (dolist (row rows)
      (let ((got (key-binding (kbd (car row)))))
        (unless (eq got (cdr row))
          (push (list (car row) :want (cdr row) :got got) bad))))
    (nreverse bad)))

(maf-step
  ;; The whole stack map, one answer per key, from inside the calc buffer.
  (cl-assert (null (maf--snapshot-mismatches maf--snapshot-stack-rows)))

  ;; Digit-entry overrides answer from calc-digit-map.
  (let (bad)
    (dolist (row maf--snapshot-digit-rows)
      (unless (eq (lookup-key calc-digit-map (kbd (car row))) (cdr row))
        (push (car row) bad)))
    (cl-assert (null bad)))

  ;; The native layout now takes Calc's evaluation key for equating too.
  (cl-assert (eq (key-binding "=") 'mafcmd-equal-to))

  ;; Deliberate fall-throughs to calc stay calc's.
  (cl-assert (eq (key-binding "'") 'calc-algebraic-entry))
  (cl-assert (eq (key-binding "$") 'calc-auto-algebraic-entry))
  (cl-assert (eq (key-binding "[") 'calc-begin-vector))
  (cl-assert (eq (key-binding "]") 'calc-end-vector))

  ;; A module's key comes and goes with its toggle.
  (cl-assert (eq (key-binding "?") 'maf-options))
  (unwind-protect
      (progn (maf-use-options-mode -1)
             (cl-assert (not (eq (key-binding "?") 'maf-options))))
    (maf-use-options-mode 1))
  (cl-assert (eq (key-binding "?") 'maf-options)))
