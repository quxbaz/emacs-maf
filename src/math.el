;; -*- lexical-binding: t; -*-
;;
;; math.el
;;
;; Pure formula helpers: functions that compute over calc formulas
;; without touching buffers, context, or the stack.

(require 'calc)
(require 'cl-lib)

;; Defined in lazily-loaded calc modules; calc-ext's autoload registry
;; resolves them at runtime, but the byte compiler needs declarations.
(declare-function calcFunc-pgcd "calc-poly")

(defun maf--sum-terms (expr)
  "Return a flat list of the additive terms in EXPR.
Flattens +, -, and unary negation, negating terms under the latter two,
so the returned terms sum back to EXPR: 6 x - 12 gives (6 x, -12) and
-(a + b) gives (-a, -b)."
  (pcase (car-safe expr)
    ('+ (append (maf--sum-terms (nth 1 expr))
                (maf--sum-terms (nth 2 expr))))
    ('- (append (maf--sum-terms (nth 1 expr))
                (mapcar #'math-neg (maf--sum-terms (nth 2 expr)))))
    ('neg (mapcar #'math-neg (maf--sum-terms (nth 1 expr))))
    (_ (list expr))))

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

(defun maf--float-fracs (expr)
  "Float the fractions in EXPR, leaving integers exact.
Unlike `calcFunc-pfloat', which pervasively floats every number
\(6 x + 8:3 becomes 6. x + 2.67), only the non-integer exact numbers
convert: 6 x + 8:3 becomes 6 x + 2.67."
  (cond
   ((eq (car-safe expr) 'frac) (math-float expr))
   ((consp expr) (cons (car expr) (mapcar #'maf--float-fracs (cdr expr))))
   (t expr)))

(defun maf--flip-relation-op (op)
  "Return relation OP with its direction reversed: lt <-> gt, leq <-> geq.
Symmetric operators (eq, neq) return unchanged."
  (or (cdr (assq op '((calcFunc-lt  . calcFunc-gt)
                      (calcFunc-gt  . calcFunc-lt)
                      (calcFunc-leq . calcFunc-geq)
                      (calcFunc-geq . calcFunc-leq))))
      op))

(provide 'maf-math)
