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

(defun maf-undo (n)
  "Like `calc-undo', but keep point in place instead of jumping home."
  (interactive "p")
  (maf--preserve-point (calc-undo n)))

(defun maf-redo (n)
  "Like `calc-redo', but keep point in place instead of jumping home."
  (interactive "p")
  (maf--preserve-point (calc-redo n)))

(provide 'maf-stack)
