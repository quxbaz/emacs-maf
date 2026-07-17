;; -*- lexical-binding: t; -*-
;;
;; stack.el
;;
;; Hand-written contextual stack commands: composites with no single
;; calcFunc equivalent.

(require 'maf-defcmd)
(require 'maf-math "math")

;; These live in lazily-loaded calc modules; calc-ext's autoload registry
;; resolves them at runtime, but the byte compiler needs declarations.
(declare-function calcFunc-mul "calc-arith")
(declare-function calcFunc-div "calc-arith")
(declare-function calcFunc-nrat "calc-poly")
(declare-function calcFunc-expand "calc-poly")
(declare-function math-simplify "calc-alg")
(declare-function calc-undo "calc-undo")
(declare-function calc-redo "calc-undo")
(declare-function math-looks-negp "calc-misc")
(declare-function calc-push "calc-ext")
(declare-function calcFunc-pfloat "calc-stuff")
(declare-function calc-roll-down "calc-misc")
(declare-function calc-locate-cursor-element "calc-yank")

(maf-defcmd mafcmd-factor-by (expr arg commit)
  "Factor the resolved expression by the top-of-stack argument.
Divides EXPR by ARG, normalizes the quotient (expand -> nrat -> expand ->
simplify), and commits ARG * quotient with the product left undistributed:
6 x + 12 factored by 6 gives 6 (x + 2), not 6 x + 12 back.

Contextual like every mafcmd: with point on a sub-formula it factors just
that sub-formula; on an equation it factors each side; at home it factors
stack level 2 by level 1."
  :arity binary
  :prefix "fctr"
  (let ((quotient (math-simplify
                   (calcFunc-expand
                    (calcFunc-nrat
                     (calcFunc-expand (calcFunc-div expr arg)))))))
    ;; Build the product literally; commit pushes structurally, so the
    ;; factored form survives without calc-normalize distributing it.
    (commit (let ((calc-simplify-mode 'none))
              (calcFunc-mul arg quotient)))))

(maf-defcmd mafcmd-factor-gcd (expr _arg commit)
  "Factor the resolved expression by the GCD of its additive terms.
Computes the GCD across all terms and pulls it out, keeping the product
undistributed: 6 x + 12 gives 6 (x + 2). When the leading term is
negative, the negated GCD is pulled out instead, so -3 x + 3 gives
-3 (x - 1). With nothing to pull out — a single term, or GCD 1 with a
positive leading term — the expression is committed unchanged, so
equation sides that don't factor pass through quietly.

Contextual like every mafcmd: with point on a sub-formula it factors
just that sub-formula; on an equation it factors each side; at home it
factors the top entry."
  :arity unary
  :prefix "fctr"
  (let* ((terms (let ((calc-simplify-mode nil)
                      (calc-prefer-frac t))
                  ;; Normalize each term: a shape like 2 (-x) hides its
                  ;; sign from math-looks-negp until it becomes -2 x, and
                  ;; pgcd wants canonical coefficients. Default simplify
                  ;; mode so this works even with simplification off;
                  ;; fractions preferred so exact ratios like (/ 3 4)
                  ;; don't detour through float noise.
                  (mapcar #'math-normalize (maf--sum-terms expr))))
         ;; pgcd rejects float coefficients ("Coefficients must be
         ;; rational") — treat that as nothing to pull out.
         (factor (let ((calc-simplify-mode nil)
                       (calc-prefer-frac t))
                   (condition-case nil (maf--terms-gcd terms) (error nil)))))
    (when factor
      ;; Canonicalize the GCD positive, then pull a negative factor out
      ;; when the leading term is negative.
      (when (math-looks-negp factor) (setq factor (math-neg factor)))
      (when (math-looks-negp (car terms)) (setq factor (math-neg factor))))
    (if (or (null factor) (null (cdr terms)) (equal factor 1))
        (commit expr)
      (let ((quotient (let ((calc-prefer-frac t))
                        (math-simplify
                         (calcFunc-expand
                          (calcFunc-nrat
                           (calcFunc-expand (calcFunc-div expr factor))))))))
        ;; Build the product literally; commit pushes structurally, so the
        ;; factored form survives without calc-normalize distributing it.
        (commit (let ((calc-simplify-mode 'none))
                  (calcFunc-mul factor quotient)))))))

(maf-defcmd mafcmd-commute (expr _arg commit)
  "Swap the first two operands of the resolved expression.
a + b gives b + a. The swap is structural and nothing is simplified, so
it also flips non-commutative operators (a - b gives b - a) and works
on any function call (log(x, b) gives log(b, x)); operands past the
second stay in place. With nothing to swap — an atom, a unary call, an
interval — the expression is committed unchanged.

A binary relation keeps its meaning: the sides swap and the operator's
direction reverses with them, so x = y gives y = x and x < y gives
y > x, never y < x.

Contextual like every mafcmd: with point on a sub-formula it swaps just
that sub-formula's operands; on an equation it swaps the two sides; at
home it operates on the top entry."
  :arity unary
  :prefix "comm"
  :map -1
  ;; Math-primp screens out atoms and primitive composites (frac, var,
  ;; ...) whose slots aren't operands; intv slips through it but its
  ;; first slot is the endpoint mask, so exclude it too. The swapped
  ;; list is built literally — no normalize — so committing it never
  ;; evaluates: 2 (3 + x) commutes to (3 + x) 2 without distributing.
  (commit (cond
           ;; Binary relation: reverse the operator along with the swap
           ;; so the relationship is preserved. Chained relations (a <
           ;; b < c) fall through to the generic swap — no single
           ;; operator flip keeps a chain's meaning.
           ((and (maf--relation-p expr) (= (length expr) 3))
            (list (maf--flip-relation-op (car expr))
                  (nth 2 expr) (nth 1 expr)))
           ((and (not (Math-primp expr))
                 (not (eq (car expr) 'intv))
                 (>= (length expr) 3))
            (append (list (car expr) (nth 2 expr) (nth 1 expr))
                    (nthcdr 3 expr)))
           (t expr))))

(maf-defcmd mafcmd-float (expr _arg commit)
  "Float the resolved expression's fractions, leaving integers exact.
6 x + 8:3 gives 6 x + 2.67 with the 6 untouched, and a whole number is
a noop — unlike calc's pervasive float, which converts every number.
With the Hyperbolic flag, `mafcmd-float-all' gives that pervasive
behavior (6. x + 2.67); the Inverse flag routes to `mafcmd-frac'.

Contextual like every mafcmd: with point on a sub-formula it floats
just that sub-formula; on an equation it floats each side; at home it
operates on the top entry."
  :arity unary
  :prefix "flt"
  :hyperbolic mafcmd-float-all
  :inverse mafcmd-frac
  (commit (maf--float-fracs expr)))

(maf-defcmd mafcmd-float-all (expr _arg commit)
  "Float every number in the resolved expression, integers included.
The pervasive variant of `mafcmd-float' (its Hyperbolic route):
6 x + 8:3 gives 6. x + 2.66666666667.

Contextual like every mafcmd: with point on a sub-formula it floats
just that sub-formula; on an equation it floats each side; at home it
operates on the top entry."
  :arity unary
  :prefix "flt"
  (commit (math-normalize (list 'calcFunc-pfloat expr))))

(maf-defcmd mafcmd-frac (expr _arg commit)
  "Convert the resolved expression's floats to fractions.
0.75 x + 2 gives 3:4 x + 2; exact numbers are untouched, and a whole
number is a noop. A numeric prefix argument gives the tolerance, as in
calc's pfrac: a positive integer N makes each fraction correct to N
significant figures (C-u 3 on 3.14159 gives 22:7), a float gives an
absolute tolerance, and no argument converts exactly within the
current precision. The take-tolerance-from-stack form of a zero
prefix argument is not supported; 0 converts exactly too.

Contextual like every mafcmd: with point on a sub-formula it converts
just that sub-formula; on an equation it converts each side; at home
it operates on the top entry. The Inverse flag routes back to
`mafcmd-float'."
  :arity unary
  :prefix "frac"
  :inverse mafcmd-float
  (commit (math-normalize
           (list 'calcFunc-pfrac expr
                 (prefix-numeric-value (or current-prefix-arg 0))))))

(defvar maf--quick-variable nil
  "Variable read by `maf-quick-variable', for the contextual body.")

(maf-defcmd mafcmd--quick-variable-mul (expr _arg commit)
  "Multiply the resolved expression by `maf--quick-variable'.
Internal: `maf-quick-variable' reads the variable, binds it, and
dispatches here when point is on an expression."
  :arity unary
  :prefix "qvar"
  (commit (calcFunc-mul maf--quick-variable expr)))

(defun maf-quick-variable ()
  "Read a letter and apply it as a variable, contextually.
At home with no selection active, push the variable as a new stack
entry. Anywhere else, multiply the resolved expression by it — the
selection, the sub-formula at point, each side of an equation, or the
whole entry from its margin: with point on the a of a + 2, entering x
gives x a + 2."
  (interactive)
  (let ((char (read-char-from-minibuffer "Variable: ")))
    (unless (or (<= ?a char ?z) (<= ?A char ?Z))
      (user-error "Invalid variable '%c'; must be a letter" char))
    (let ((var (list 'var
                     (intern (char-to-string char))
                     (intern (concat "var-" (char-to-string char))))))
      (if (and (maf--at-home-p) (not (maf--sel-any-p)))
          (calc-wrapper (calc-push var))
        (let ((maf--quick-variable var))
          (mafcmd--quick-variable-mul))))))

(defvar maf-toggle-op-pairs
  '((+ . -)
    (* . /)
    (calcFunc-ln . calcFunc-exp)
    (calcFunc-log . ^)
    (calcFunc-lt . calcFunc-gt)
    (calcFunc-leq . calcFunc-geq)
    (calcFunc-eq . calcFunc-neq)
    ;; Trig pairs with its inverse, like ln/exp. Upstream has no
    ;; arcsec/arccsc/arccot, so sec/csc/cot stay unpaired.
    (calcFunc-sin . calcFunc-arcsin)
    (calcFunc-cos . calcFunc-arccos)
    (calcFunc-tan . calcFunc-arctan)
    (calcFunc-sinh . calcFunc-arcsinh)
    (calcFunc-cosh . calcFunc-arccosh)
    (calcFunc-tanh . calcFunc-arctanh))
  "Operator pairs toggled by `mafcmd-toggle-op'.
Each pair toggles in both directions. Operands stay in place; only the
operator changes, so log(a, b) toggles to a^b and back, and a < b flips
to a > b without touching either side.")

(maf-defcmd mafcmd-toggle-op (expr _arg commit)
  "Toggle the top operator of the resolved expression to its counterpart.
Pairs come from `maf-toggle-op-pairs': a + b gives a - b, a * b gives
a / b, ln(x) gives exp(x), log(a, b) gives a^b — and each back again.
Relations flip the same way with both sides untouched: a < b gives
a > b, x = y gives x != y. The swap is structural: operands stay in
place and nothing is simplified. With no toggle for the operator — an
atom, an unpaired operator, a log(x) with no explicit base — the
expression is committed unchanged.

Contextual like every mafcmd: with point on a sub-formula it toggles
that sub-formula's operator; at home it operates on the top entry. A
relation is toggled whole rather than mapped per side — put point on
an operator inside a side to toggle there."
  :arity unary
  :prefix "togl"
  :map -1
  (let* ((op (car-safe expr))
         (to (or (cdr (assq op maf-toggle-op-pairs))
                 (car (rassq op maf-toggle-op-pairs)))))
    ;; A 1-arg log has no ^ counterpart (nothing to use as the base);
    ;; leave it alone rather than build a malformed (^ x).
    (commit (if (and to (not (and (eq op 'calcFunc-log) (= (length expr) 2))))
                (cons to (cdr expr))
              expr))))

(defun maf-swap-up (n)
  "Swap the stack entry at point with the one above it on screen.
With point on a stack entry at level M, entries M and M+1 exchange
places while point stays put — same line, same column: the entry at
point moves up the screen and its upper neighbor lands on the line at
point. When that neighbor is shorter than point's column, point clamps
to its end of line; at end of line it stays at end of line. At home
the top two entries swap. Selections travel with their entries. With
the entry at point already the highest, or with fewer than two
entries, there is nothing to swap and the command does nothing.

A prefix argument N bypasses the contextual swap and rolls the top N
entries by one, as calc's TAB does."
  (interactive "P")
  (maf--with-calc-buffer
    (if n
        (maf--preserve-point (calc-roll-down n))
      (let ((m (max (calc-locate-cursor-element (point)) 1)))
        (when (< m (calc-stack-size))
          ;; Point is a screen position here, not a formula position:
          ;; restore it by line and column, not buffer offset — the two
          ;; lines change length, so `maf--preserve-point's pos-first
          ;; restore would land unpredictably.
          (let ((home (maf--at-home-p))
                (line (line-number-at-pos))
                (col  (current-column))
                (eol  (eolp)))
            (calc-wrapper
             ;; Both lists run deepest-first, so reversing the pair of
             ;; values swaps the two levels; the selections travel along.
             (let ((vals (calc-top-list 2 m))
                   (sels (calc-top-list 2 m 'sel)))
               (calc-pop-push-list 2 (list (nth 1 vals) (nth 0 vals))
                                   m
                                   (list (nth 1 sels) (nth 0 sels)))))
            ;; Calc parks point at home after the rewrite; that is
            ;; already right for a home invocation.
            (unless home
              (goto-char (point-min))
              (forward-line (1- line))
              ;; move-to-column stops at end of line, clamping for free.
              (if eol (end-of-line) (move-to-column col)))))))))

(defun maf-equal-to ()
  "Join two adjacent stack entries into one equation, contextually.
With point on a stack entry, the entry above it on screen (level M+1)
becomes the left side, the entry at point the right side, and the
equation takes the pair's place on the stack. At home, or with the
entry at point already the highest on screen, the pairing shifts to
the nearest pair: the top two entries at home, the top two lines when
point is on the deepest entry. Both sides are committed structurally
intact — nothing simplifies or evaluates, so equating 3 with 3 yields
the equation 3 = 3, not 1.

With the Inverse flag, builds != instead of =. With keep-args, the two
entries stay put and the equation is pushed on top. Signals an error
with fewer than two entries."
  (interactive)
  (maf--with-calc-buffer
    (when (< (calc-stack-size) 2)
      (user-error "Two stack entries are needed to equate"))
    (let* ((level (calc-locate-cursor-element (point)))
           ;; Pair (m+1, m): home resolves to the top pair, and on the
           ;; deepest entry — no upper neighbor — the pair shifts down.
           (m (min (max level 1) (1- (calc-stack-size))))
           (keep calc-keep-args-flag)
           (func (if calc-inverse-flag 'calcFunc-neq 'calcFunc-eq))
           (prefix (if calc-inverse-flag "neq" "eq"))
           (commit
            (lambda ()
              (calc-wrapper
               ;; The list runs deepest-first: nth 0 is the entry above
               ;; point — the upper line — which reads as the left side.
               (let* ((vals (mapcar #'maf--strip-encasing
                                    (calc-top-list 2 m)))
                      (result (list func (nth 0 vals) (nth 1 vals))))
                 ;; Explicit nil sels keep the commit on the plain
                 ;; pop/push path; selections elsewhere on the stack stay
                 ;; untouched, and the operands' own selections end with
                 ;; them.
                 (if keep
                     (calc-pop-push-record-list 0 prefix (list result)
                                                1 (list nil))
                   (calc-pop-push-record-list 2 prefix (list result)
                                              m (list nil))))))))
      (if (or keep (= level 0))
          ;; Nothing under point moved (keep) or point is at home:
          ;; keeping it in place is the right restore.
          (maf--preserve-point (funcall commit))
        ;; The equation takes the pair's upper line while point was on
        ;; the lower one, so a line-based restore would drift onto the
        ;; entry below; follow the equation instead, landing at its EOL
        ;; — the entry margin, ready for further entry commands.
        (funcall commit)
        (calc-cursor-stack-index m)
        (end-of-line)))))

(defvar maf-undo--chain-point nil
  "Point snapshot saved by the last `maf-undo'/`maf-redo' in a chain.
Holds where point stood just before that command changed the buffer —
i.e. its position in the state the next chained undo/redo returns to.")

(defun maf--undo-redo (fn n)
  "Run undo/redo FN with N, managing point across undo/redo chains.
In an uninterrupted run of `maf-undo'/`maf-redo' commands, each command
restores the point snapshot its predecessor saved: that snapshot was
taken in the very state this command returns to, so toggling undo/redo
bounces point along with the stack. Any other command in between breaks
the chain — the user has repositioned point deliberately — and point is
simply kept in place as `maf--preserve-point' does."
  (let ((snapshot (maf--point-snapshot))
        (chained (and (memq last-command '(maf-undo maf-redo))
                      maf-undo--chain-point)))
    (if chained
        (progn (funcall fn n)
               (maf--point-restore maf-undo--chain-point))
      (maf--preserve-point (funcall fn n)))
    (setq maf-undo--chain-point snapshot)))

(defun maf-undo (n)
  "Like `calc-undo', but keep point in place instead of jumping home.
In an undo/redo chain, restore point to where it was in the state being
returned to (see `maf--undo-redo')."
  (interactive "p")
  (maf--undo-redo #'calc-undo n))

(defun maf-redo (n)
  "Like `calc-redo', but keep point in place instead of jumping home.
In an undo/redo chain, restore point to where it was in the state being
returned to (see `maf--undo-redo')."
  (interactive "p")
  (maf--undo-redo #'calc-redo n))

(provide 'maf-stack)
