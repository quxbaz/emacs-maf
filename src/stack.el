;; -*- lexical-binding: t; -*-
;;
;; stack.el
;;
;; Hand-written contextual stack commands: composites with no single
;; calcFunc equivalent.

(require 'maf-defcmd)

;; These live in lazily-loaded calc modules; calc-ext's autoload registry
;; resolves them at runtime, but the byte compiler needs declarations.
(declare-function calcFunc-mul "calc-arith")
(declare-function calcFunc-div "calc-arith")
(declare-function calcFunc-nrat "calc-poly")
(declare-function calcFunc-expand "calc-poly")
(declare-function math-simplify "calc-alg")
(declare-function calc-undo "calc-undo")
(declare-function calc-redo "calc-undo")
(declare-function calcFunc-pgcd "calc-poly")
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

(defun maf--terms-gcd (terms)
  "Return the GCD of TERMS via `calcFunc-pgcd', iterated to a fixpoint.
A single reduce can overshoot when both arguments carry variables the
other lacks — calc's pgcd(10 x y, 15 x z) yields 10 x, not 5 x — but
against the bare candidate it computes correctly (pgcd(10 x, 15 x z)
is 5 x), so folding the candidate back in and re-reducing converges on
the true common factor."
  (let ((f (cl-reduce #'calcFunc-pgcd terms)))
    (cl-loop repeat 8
             for g = (cl-reduce #'calcFunc-pgcd terms :initial-value f)
             until (equal g f)
             do (setq f g))
    f))

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

(defun maf-undo (n)
  "Like `calc-undo', but keep point in place instead of jumping home."
  (interactive "p")
  (maf--preserve-point (calc-undo n)))

(defun maf-redo (n)
  "Like `calc-redo', but keep point in place instead of jumping home."
  (interactive "p")
  (maf--preserve-point (calc-redo n)))

(provide 'maf-stack)
