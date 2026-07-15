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

Contextual like every mafcmd: with point on a sub-formula it swaps just
that sub-formula's operands; on an equation it swaps the two sides, so
x = y gives y = x; at home it operates on the top entry."
  :arity unary
  :prefix "comm"
  :map -1
  ;; Math-primp screens out atoms and primitive composites (frac, var,
  ;; ...) whose slots aren't operands; intv slips through it but its
  ;; first slot is the endpoint mask, so exclude it too. The swapped
  ;; list is built literally — no normalize — so committing it never
  ;; evaluates: 2 (3 + x) commutes to (3 + x) 2 without distributing.
  (commit (if (and (not (Math-primp expr))
                   (not (eq (car expr) 'intv))
                   (>= (length expr) 3))
              (append (list (car expr) (nth 2 expr) (nth 1 expr))
                      (nthcdr 3 expr))
            expr)))

(defun maf-undo (n)
  "Like `calc-undo', but keep point in place instead of jumping home."
  (interactive "p")
  (maf--preserve-point (calc-undo n)))

(defun maf-redo (n)
  "Like `calc-redo', but keep point in place instead of jumping home."
  (interactive "p")
  (maf--preserve-point (calc-redo n)))

(provide 'maf-stack)
