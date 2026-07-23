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
(declare-function calcFunc-mul "calc-arith")
(declare-function math-looks-negp "calc-misc")
(declare-function math-polynomial-base "calc-alg")
(declare-function math-polynomial-p "calc-alg")
(declare-function math-is-polynomial "calc-alg")
(declare-function math-const-var "calc-ext")

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

(defun maf--solve-sorted-vars (expr)
  "Return EXPR's distinct non-constant variables in solve-priority order.
The conventional unknowns x, y, z, t come first, in that order; any
other variables follow alphabetically. Used to pick which variable to
solve or find roots for."
  (let (vars)
    (cl-labels ((collect (e)
                  (cond ((and (eq (car-safe e) 'var) (not (math-const-var e)))
                         (cl-pushnew e vars :test #'equal))
                        ((consp e) (mapc #'collect (cdr e))))))
      (collect expr))
    (let ((priority '("x" "y" "z" "t")))
      (sort vars
            (lambda (a b)
              (let* ((na (symbol-name (nth 1 a)))
                     (nb (symbol-name (nth 1 b)))
                     (pa (or (cl-position na priority :test #'string=) 999))
                     (pb (or (cl-position nb priority :test #'string=) 999)))
                (or (< pa pb) (and (= pa pb) (string< na nb)))))))))

(defun maf--contains-float-p (expr)
  "Return t if EXPR contains a float anywhere.
Unlike `math-floatp', which only looks inside number types (complex,
intervals, dates), this walks whole formulas: 1.5 x + 2 contains one."
  (or (eq (car-safe expr) 'float)
      (and (consp expr)
           (cl-some #'maf--contains-float-p (cdr expr))
           t)))

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

(defun maf--expr-vars (expr)
  "Return the variables occurring in EXPR, as a list of var nodes.
Duplicates are kept; callers only test membership."
  (cond ((eq (car-safe expr) 'var) (list expr))
        ((Math-primp expr) nil)
        (t (mapcan #'maf--expr-vars (cdr expr)))))

(defun maf--term-root (term n)
  "Return (ROOT . RADICANDS), an N-th root of TERM.
ROOT satisfies ROOT^N = TERM structurally: powers divide their
exponent, products and quotients root their parts, and perfect
numeric powers extract exactly. Whatever resists comes back under a
radical — sqrt(...) when N is 2, a (frac 1 N) power otherwise — and
RADICANDS collects those resisting sub-expressions, nil when the root
is exact. TERM must not be negative-looking; callers handle signs.
Assumes `calc-symbolic-mode' is bound non-nil so non-perfect numeric
roots stay symbolic instead of floating."
  (cl-flet ((radical (x pow)
              (if (and (= n 2) (= pow 1))
                  (list 'calcFunc-sqrt x)
                (list '^ x (list 'frac pow n)))))
    (cond
     ((Math-realp term)
      (let ((r (math-pow term (list 'frac 1 n))))
        (if (Math-realp r)
            (cons r nil)
          (cons (radical term 1) (list term)))))
     ((memq (car-safe term) '(* /))
      (let ((ra (maf--term-root (nth 1 term) n))
            (rb (maf--term-root (nth 2 term) n))
            (op (if (eq (car term) '*) #'math-mul #'math-div)))
        (cons (funcall op (car ra) (car rb))
              (append (cdr ra) (cdr rb)))))
     ((and (eq (car-safe term) '^) (integerp (nth 2 term)))
      ;; Floor division splits the exponent into an exact whole part
      ;; and a positive fractional remainder, so odd powers extract
      ;; what they can: x^5 roots to x^2 sqrt(x).
      (let* ((base (nth 1 term))
             (q (floor (nth 2 term) n))
             (r (mod (nth 2 term) n)))
        (cond ((zerop r) (cons (if (= q 1) base (list '^ base q)) nil))
              ((zerop q) (cons (radical base r) (list base)))
              (t (cons (math-mul (list '^ base q) (radical base r))
                       (list base))))))
     ;; Anything else — a variable, a call — roots as a whole radical.
     (t (cons (radical term 1) (list term))))))

(defun maf--factor-powers (t1 t2)
  "Factor the binomial T1 + T2 by a square or cube product identity.
T1 and T2 are signed additive terms. Candidates, most exact first:
difference of squares (u + v)(u - v), sum/difference of cubes
\(u + v)(u^2 - u v + v^2) with signed cube roots, and complex
conjugates for sums of squares. Sums prefer cubes over conjugates;
differences prefer squares over cubes. Radicals may appear in a root
when the other term's root is exact and non-numeric, and a variable
never goes under a radical while also occurring outside it in the
other term. Returns nil when no candidate qualifies. This is the
transformation behind `mafcmd-factor-powers'; to change, reorder, or
extend the identities, change this function."
  (let* ((calc-symbolic-mode t)
         (calc-prefer-frac t)
         (calc-simplify-mode nil)
         (neg1 (math-looks-negp t1))
         (neg2 (math-looks-negp t2))
         (p1 (if neg1 (math-neg t1) t1))
         (p2 (if neg2 (math-neg t2) t2))
         (sq1 (maf--term-root p1 2))
         (sq2 (maf--term-root p2 2))
         (cb1 (maf--term-root p1 3))
         (cb2 (maf--term-root p2 3))
         (i '(var i var-i)))
    (cl-labels
        ((vars-clash-p (radicands other)
           (let ((ov (maf--expr-vars other)))
             (seq-some (lambda (rad)
                         (seq-intersection (maf--expr-vars rad) ov #'equal))
                       radicands)))
         ;; 0 = both roots exact; 1 = radicals over numbers only;
         ;; 2 = radicals over variables; nil = disqualified. A radical
         ;; needs the other side exact with a variable in it (so x - 9
         ;; never becomes (sqrt(x) + 3)(sqrt(x) - 3)), and no variable
         ;; under a radical may recur in the other term (so x^2 - x
         ;; stays put while x^2 - y factors).
         (grade (r1 r2)
           (let ((rads (append (cdr r1) (cdr r2))))
             (cond ((null rads) 0)
                   ((not (or (and (null (cdr r1)) (maf--expr-vars p1))
                             (and (null (cdr r2)) (maf--expr-vars p2))))
                    nil)
                   ((or (vars-clash-p (cdr r1) p2)
                        (vars-clash-p (cdr r2) p1))
                    nil)
                   ((seq-some #'maf--expr-vars rads) 2)
                   (t 1))))
         (squares ()  ; mixed signs; the positive term's root leads
           (pcase-let ((`(,u . ,v) (if neg2
                                       (cons (car sq1) (car sq2))
                                     (cons (car sq2) (car sq1)))))
             (calcFunc-mul (math-add u v) (math-sub u v))))
         (cubes ()  ; signed roots make one identity cover both signs
           (let ((u (if neg1 (math-neg (car cb1)) (car cb1)))
                 (v (if neg2 (math-neg (car cb2)) (car cb2))))
             (calcFunc-mul (math-add u v)
                           (math-add (math-sub (math-mul u u)
                                               (math-mul u v))
                                     (math-mul v v)))))
         (conjugates ()  ; u^2 + v^2 = (v + u i)(v - u i); negated pair
           (let* ((u (car sq1)) (v (car sq2)) (ui (math-mul u i)))
             (if neg1
                 (calcFunc-mul (math-add ui v) (math-sub ui v))
               (calcFunc-mul (math-add v ui) (math-sub v ui))))))
      (let* ((gsq (grade sq1 sq2))
             (gcb (grade cb1 cb2))
             (candidates
              (if (eq (not neg1) (not neg2))
                  ;; Same sign, a (possibly negated) sum: cubes give the
                  ;; real factorization, conjugates are the fallback.
                  (list (cons gcb #'cubes) (cons gsq #'conjugates))
                (list (cons gsq #'squares) (cons gcb #'cubes))))
             best)
        (dolist (c candidates)
          (when (and (car c) (or (null best) (< (car c) (car best))))
            (setq best c)))
        (and best (funcall (cdr best)))))))

(defun maf--flip-relation-op (op)
  "Return relation OP with its direction reversed: lt <-> gt, leq <-> geq.
Symmetric operators (eq, neq) return unchanged."
  (or (cdr (assq op '((calcFunc-lt  . calcFunc-gt)
                      (calcFunc-gt  . calcFunc-lt)
                      (calcFunc-leq . calcFunc-geq)
                      (calcFunc-geq . calcFunc-leq))))
      op))

(provide 'maf-math)
