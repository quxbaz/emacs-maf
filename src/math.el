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
(declare-function math-polynomial-base "calc-alg")
(declare-function math-polynomial-p "calc-alg")
(declare-function math-is-polynomial "calc-alg")

;; Polynomial-recognizer knobs, defvar'd in lazily-loaded calc-ext;
;; declared here so the let bindings below stay dynamic even when that
;; module hasn't loaded yet.
(defvar math-poly-base-variable)
(defvar math-poly-neg-powers)
(defvar math-poly-mult-powers)
(defvar math-poly-frac-powers)

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

(defun maf--quadratic-base (expr)
  "Return the base EXPR is a quadratic in, or nil if there is none.
The base is the leftmost sub-expression in which EXPR is a polynomial
of degree exactly 2 — usually a variable, but any sub-formula
qualifies: sin(y)^2 + 2 sin(y) is a quadratic in sin(y)."
  (math-polynomial-base
   expr (lambda (base) (eq (math-polynomial-p expr base) 2))))

(defun maf--quadratic-coeffs (expr base)
  "Return EXPR's coefficients as a quadratic in BASE: a list (C B A).
The list is constant-first, as calc's polynomial routines return it,
and A is never zero. Nil when EXPR is not a polynomial of degree 2 in
BASE. Exact coefficients stay exact: integer division yields
fractions, not floats."
  (let ((calc-prefer-frac t)
        ;; Pin the recognizer to plain integer powers of BASE; these
        ;; are its defaults, but calc's own callers rebind them and
        ;; the recognizer setqs some of them while it works.
        (math-poly-base-variable nil)
        (math-poly-neg-powers nil)
        (math-poly-mult-powers 1)
        (math-poly-frac-powers nil))
    (let ((coeffs (math-is-polynomial expr base 2)))
      (and (= (length coeffs) 3) coeffs))))

(defun maf--vertex-form (coeffs base)
  "Build the vertex form A (BASE + h)^2 + k from COEFFS, a list (C B A).
h is B/(2 A) and k is C - B^2/(4 A), so the result expands back to
A BASE^2 + B BASE + C. Exact inputs give exact h and k: fractions,
not floats. This is the output shape of `mafcmd-complete-square';
to change or extend the transformation, change this function."
  (pcase-let ((`(,c ,b ,a) coeffs))
    (let* ((calc-prefer-frac t)
           (h (math-div b (math-mul 2 a)))
           (k (math-sub c (math-div (math-mul b b) (math-mul 4 a))))
           (square (list '^ (math-add base h) 2)))
      (math-add (math-mul a square) k))))

(defun maf--flip-relation-op (op)
  "Return relation OP with its direction reversed: lt <-> gt, leq <-> geq.
Symmetric operators (eq, neq) return unchanged."
  (or (cdr (assq op '((calcFunc-lt  . calcFunc-gt)
                      (calcFunc-gt  . calcFunc-lt)
                      (calcFunc-leq . calcFunc-geq)
                      (calcFunc-geq . calcFunc-leq))))
      op))

(provide 'maf-math)
