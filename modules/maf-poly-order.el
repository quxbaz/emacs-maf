;; -*- lexical-binding: t; -*-
;;
;; modules/maf-poly-order.el
;;
;; Polynomial term ordering: single-variable polynomial sums kept in
;; descending degree, the way they are written on paper.
;;
;; Calc has no canonical order for a sum's terms. Simplification tends
;; to leave polynomials ascending — `a s' on 1 + x + x^2 gives
;; x + x^2 + 1, and expanding (x + 1)^2 or collecting terms can land in
;; any order the rewrite happened to produce. Every such result then
;; reads against the convention that puts the leading term first.
;;
;; The fix is a piece of :filter-return advice that takes each sum
;; coming out of normalization and, when the sum is a polynomial in
;; exactly one variable, reorders its terms by descending degree.
;; Terms of equal degree keep their order (the sort is stable), and
;; multi-variable sums are left untouched — with several variables
;; there is no one right order to impose. The reordering is purely
;; structural: the terms are the same values, so nothing about the
;; formula's meaning moves.
;;
;; The advice sits on two functions, and both are needed.
;; `math-normalize' is the funnel every internally computed formula
;; passes through — but under `calc-simplify-mode' 'alg or 'units,
;; `calc-normalize' routes a committed result through `math-simplify'
;; instead, whose final rewrite does not necessarily hand the whole
;; sum back to `math-normalize', and the top level comes out in
;; whatever order the last rewrite left it. Advising `calc-normalize'
;; too closes that hole at the point every stack commit funnels
;; through, whatever the simplify mode. (The sort is idempotent, so a
;; result both catch is sorted once and merely re-checked.)
;;
;; Two states hold the advice back. `calc-simplify-mode' 'none means
;; hands off — both for the user's m O and for code that binds it
;; precisely to keep a structure calc would otherwise rearrange (the
;; legacy poly-lcm relied on that to protect a factored form). And a
;; guard variable keeps the advice from re-entering itself should the
;; sort ever normalize on its own.
;;
;; The feature is `maf-use-poly-order-mode', a global minor mode
;; registered with the module system as `maf-poly-order' (see
;; `maf-modules').

(require 'calc)
(require 'maf-conf "conf")   ; the `maf' customize group
(require 'maf-math "math")   ; maf--sum-terms, maf--solve-sorted-vars

;; Defined in lazily-loaded calc modules; calc-ext's autoload registry
;; resolves them at runtime, but the byte compiler needs declarations.
(declare-function math-looks-negp "calc-misc")

(defvar maf-poly-order--sorting nil
  "Non-nil while the sort itself is running, to bar re-entry.
The sort is pure list work today, but a future degree test that calls
into calc could normalize, and the advice must not fire on its own
output.")

(defun maf-poly-order--degree (term var)
  "Return TERM's degree as a monomial in VAR.
VAR itself is degree 1, an integer power of VAR its exponent; degrees
add across a product and subtract across a division, so x/2 is degree
1 and 1/x degree -1. Negation is transparent. Anything else — a
constant, another variable's power, a symbolic exponent — counts 0."
  (cond
   ((equal term var) 1)
   ((and (eq (car-safe term) '^)
         (equal (nth 1 term) var)
         (integerp (nth 2 term)))
    (nth 2 term))
   ((eq (car-safe term) '*)
    (+ (maf-poly-order--degree (nth 1 term) var)
       (maf-poly-order--degree (nth 2 term) var)))
   ((eq (car-safe term) '/)
    (- (maf-poly-order--degree (nth 1 term) var)
       (maf-poly-order--degree (nth 2 term) var)))
   ((eq (car-safe term) 'neg)
    (maf-poly-order--degree (nth 1 term) var))
   (t 0)))

(defun maf-poly-order--build-sum (terms)
  "Rebuild a sum formula from TERMS, a list of additive terms.
The inverse of `maf--sum-terms': negative terms fold in as
subtractions, so the result reads x^2 - x + 1 rather than
x^2 + -x + 1.

Negative means `math-looks-negp', not `math-negp'. The latter only
knows literal negative numbers, and the terms needing the fold mostly
are not: `maf--sum-terms' negates with `math-neg', which pushes the
sign into a coefficient or a numerator rather than wrapping the term,
so a subtracted 2 x arrives as -2 x and a subtracted 1:2 / (x + 1) as
-1:2 / (x + 1). Both read as negative and neither is a negative
number, which is how x^2 + -2 x + 4 used to come back out. Wrapped
negations fold too — `math-neg' unwraps them — so this one test covers
every shape."
  (let ((sum (car terms)))
    (dolist (term (cdr terms) sum)
      (setq sum (if (math-looks-negp term)
                    (list '- sum (math-neg term))
                  (list '+ sum term))))))

(defun maf-poly-order--sort (expr)
  "Sort EXPR's terms by descending degree if it is a one-variable sum.
Any other EXPR — several variables, none — comes back unchanged."
  (let ((vars (maf--solve-sorted-vars expr)))
    (if (and vars (null (cdr vars)))
        (let ((var (car vars)))
          (maf-poly-order--build-sum
           (sort (maf--sum-terms expr)
                 (lambda (a b)
                   (> (maf-poly-order--degree a var)
                      (maf-poly-order--degree b var))))))
      expr)))

(defun maf-poly-order--normalize (result)
  "Reorder RESULT's terms when it is a one-variable polynomial sum.
Filter-return advice on `math-normalize' and `calc-normalize',
installed by `maf-use-poly-order-mode'. Stands aside under
`calc-simplify-mode' 'none — the user's m O, or code binding it to
keep a structure calc would rearrange — and while its own sort is
running."
  (if (and (not maf-poly-order--sorting)
           (not (eq calc-simplify-mode 'none))
           (memq (car-safe result) '(+ -)))
      (let ((maf-poly-order--sorting t))
        (maf-poly-order--sort result))
    result))

;;; The module

;;;###autoload
(define-minor-mode maf-use-poly-order-mode
  "Global minor mode keeping polynomial sums in descending degree.
Enabled, every sum `math-normalize' produces that is a polynomial in
exactly one variable has its terms reordered leading-term first, so
1 + x + x^2 always reads x^2 + x + 1. Multi-variable sums and
everything under `calc-simplify-mode' 'none are left alone. Disabled,
formulas keep whatever order calc produced; already-sorted entries on
the stack stay as they are either way.

The reordering rides one filter on `math-normalize' — the funnel for
internally computed formulas — and on `calc-normalize', which catches
the top level of a commit under the fancy simplify modes ('alg,
'units) where `math-simplify' can hand a sum back without a final
normalize. This is the `maf-poly-order' module (see `maf-modules')."
  :global t
  :group 'maf
  (if maf-use-poly-order-mode
      (progn
        (advice-add 'math-normalize :filter-return #'maf-poly-order--normalize)
        (advice-add 'calc-normalize :filter-return #'maf-poly-order--normalize))
    (advice-remove 'math-normalize #'maf-poly-order--normalize)
    (advice-remove 'calc-normalize #'maf-poly-order--normalize)))

;; Register with the module system when it is present; the mode above
;; works on its own without it.
(when (require 'maf-module nil t)
  (maf-register-module 'maf-poly-order #'maf-use-poly-order-mode
                       "Keep one-variable polynomial sums in descending degree."))

(provide 'maf-poly-order)
