;; -*- lexical-binding: t; -*-
;;
;; math.el
;;
;; Pure formula helpers: functions that compute over calc formulas
;; without touching buffers, context, or the stack.

(require 'calc)
(require 'cl-lib)
(require 'maf-conf "conf")
(require 'maf-lib)    ; maf--literal

;; Defined in lazily-loaded calc modules; calc-ext's autoload registry
;; resolves them at runtime, but the byte compiler needs declarations.
(declare-function calcFunc-pgcd "calc-poly")
(declare-function calcFunc-pdivrem "calc-poly")
(declare-function calcFunc-expand "calc-poly")
(declare-function calcFunc-factor "calc-poly")
(declare-function math-simplify "calc-alg")
(declare-function calcFunc-gcd "calc-comb")
(declare-function calcFunc-lcm "calc-comb")
(declare-function calcFunc-mul "calc-arith")
(declare-function calcFunc-round "calc-arith")
(declare-function math-abs "calc-arith")
(declare-function math-floor "calc-misc")
(declare-function math-from-hms "calc-forms")
(declare-function math-looks-negp "calc-misc")
(declare-function math-negp "calc-misc")
(declare-function math-posp "calc-misc")
(declare-function math-zerop "calc-misc")
(declare-function math-simplify "calc-alg")
(declare-function math-polynomial-base "calc-alg")
(declare-function math-polynomial-p "calc-alg")
(declare-function math-is-polynomial "calc-alg")
(declare-function math-const-var "calc-ext")
(declare-function math-pi "calc-ext")
(declare-function math-vectorp "calc-ext")
(declare-function math-matrixp "calc-ext")
(declare-function math-lessp "calc-ext")
(declare-function math-equal "calc-ext")
(declare-function math-evaluate-expr "calc-ext")
(declare-function calcFunc-rmeq "calc-prog")
(declare-function calcFunc-finv "calcalg2")
(declare-function math-solve-eqn "calcalg2")
(declare-function math-expr-contains "calc-alg")

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

(defun maf--inverse-out-var (expr)
  "Return the variable naming the output of the bare function EXPR.
The conventional y, unless EXPR already uses that name — a parameter y
would otherwise be captured by the equation the inverse is committed as
— in which case y1, y2 and so on, the first name EXPR does not use."
  (let ((n 0) var)
    (while (progn
             (let ((name (if (zerop n) "y" (format "y%d" n))))
               (setq var (list 'var (intern name)
                               (intern (concat "var-" name)))))
             (math-expr-contains expr var))
      (setq n (1+ n)))
    var))

(defun maf--inverse-parts (expr)
  "Split EXPR into (OUT IN F), the pieces its inverse is built from.
OUT is what the inverted equation keeps on its left — the name of the
function's output; IN is the variable the function takes as its input;
F is the function's body, an expression in IN. Nil when EXPR names no
function of a variable.

Four shapes are recognized, in order:

  y = x + 1    a plain variable alone on one side and absent from the
               other: that variable is OUT, the other side is F —
               either way round, so x + 1 = y reads the same
  f(x) = ...   a call to a function Calc does not define (f, not sin)
               on one side: the call is OUT and its argument is IN, so
               f(k) = k^2 + x inverts in k rather than in x
  2 y = x + 1  neither side explicit: the equation is first solved for
               its output variable — y when it occurs, else the second
               of exactly two variables in `maf--solve-sorted-vars'
               order — and F is what that solve leaves
  x + 1        no relation at all: EXPR is F itself, and OUT is a fresh
               y (see `maf--inverse-out-var')

A relation other than an equation states a bound rather than a
function, and gives nil rather than being read as a bare body.

Except in the f(x) shape, where the call names it, IN is F's first
variable in `maf--solve-sorted-vars' order — x before y, then the
alphabet — so a body with parameters inverts in the conventional
unknown."
  (cl-flet ((in-var (fx out)
              (car (cl-remove out (maf--solve-sorted-vars fx) :test #'equal))))
    (if (not (eq (car-safe expr) 'calcFunc-eq))
        ;; Only an equation states a function. Another relation bounds
        ;; one, so there is no function to invert — and it must not fall
        ;; through to the bare-expression reading, which would take the
        ;; whole inequality for a body.
        (and (not (memq (car-safe expr) '(calcFunc-neq calcFunc-lt
                                          calcFunc-leq calcFunc-gt
                                          calcFunc-geq)))
             (let ((in (car (maf--solve-sorted-vars expr))))
               (and in (list (maf--inverse-out-var expr) in expr))))
      (let ((lhs (nth 1 expr))
            (rhs (nth 2 expr)))
        (cl-flet ((explicit (out fx)
                    ;; A variable naming the output must not also appear
                    ;; in the body: y = x + y is an implicit relation,
                    ;; not a function of x.
                    (and (eq (car-safe out) 'var)
                         (not (math-expr-contains fx out))
                         (let ((in (in-var fx out)))
                           (and in (list out in fx)))))
                  (call (out fx)
                    (and (maf--unknown-fn-call-p out 1)
                         (eq (car-safe (nth 1 out)) 'var)
                         (list out (nth 1 out) fx))))
          (or (explicit lhs rhs)
              (explicit rhs lhs)
              (call lhs rhs)
              (call rhs lhs)
              ;; Implicit: make the equation explicit by solving it for
              ;; the output variable, then invert what comes back.
              (let* ((vars (maf--solve-sorted-vars expr))
                     (out (cond ((member '(var y var-y) vars) '(var y var-y))
                                ((= (length vars) 2) (nth 1 vars))))
                     (solved (and out (math-solve-eqn expr out nil)))
                     (fx (and (eq (car-safe solved) 'calcFunc-eq)
                              (nth 2 solved)))
                     (in (and fx (in-var fx out))))
                (and in (list out in fx)))))))))

(defun maf--function-inverse (expr)
  "Return the inverse of the function EXPR as an equation, or nil.
EXPR is read as a function of one variable — an equation naming its
output, or a bare expression (see `maf--inverse-parts') — and the
result equates that same output name to the inverse function of the
same input variable: y = 2 x + 3 gives y = x / 2 - 3:2.

The inversion is calc's own `calcFunc-finv', which solves the body
against a fresh unknown and renames it back to the input variable, so
the input and output are swapped without any variable in the body being
captured. Symbolic and prefer-frac, so the inverse stays exact: a root
gives sqrt, a ratio 1:2.

Nil when EXPR names no invertible function: a shape
`maf--inverse-parts' does not recognize (an inequality, a variable-free
equation, an implicit relation in three unknowns), or a body calc
cannot solve. This is the transformation behind
`mafcmd-inverse-function'; to change it, change this function."
  (let ((calc-symbolic-mode t) (calc-prefer-frac t))
    (condition-case nil
        (pcase (maf--inverse-parts expr)
          (`(,out ,in ,fx)
           (let ((inv (calcFunc-finv fx in)))
             ;; A body calc cannot invert comes back as an unevaluated
             ;; finv call.
             (and (not (eq (car-safe inv) 'calcFunc-finv))
                  (list 'calcFunc-eq out inv)))))
      (error nil))))

(defun maf--contains-float-p (expr)
  "Return t if EXPR contains a float anywhere.
Unlike `math-floatp', which only looks inside number types (complex,
intervals, dates), this walks whole formulas: 1.5 x + 2 contains one."
  (or (eq (car-safe expr) 'float)
      (and (consp expr)
           (cl-some #'maf--contains-float-p (cdr expr))
           t)))

(defun maf--contains-pi-p (expr)
  "Return t if EXPR contains pi as a symbolic variable anywhere.
Only the unevaluated constant counts: 5 pi / 4 contains one, its float
value 3.92699081699 does not."
  (or (equal expr '(var pi var-pi))
      (and (consp expr)
           (cl-some #'maf--contains-pi-p (cdr expr))
           t)))

(defun maf--turn-complement (x part)
  "Return PART of a full turn less the angle X.
PART is the fraction of a turn X is taken away from: 1:2 gives X's
supplement, 1:4 its complement.

The turn follows the angle rather than the mode alone: symbolic pi
anywhere in X makes it 2 pi — pi / 6 supplements to 5:6 pi even in
degrees mode — and otherwise `calc-angle-mode' picks 2 pi for radians
and 360 for degrees. An hms form is degrees by construction, so it
takes the degree turn in any mode, with the angle mode pinned to deg so
that the plain number it meets is not read as radians and converted.

Exact angles stay exact, and a float switches a radian turn to numeric
pi, as in `mafcmd-to-degrees': the value has already forfeited
exactness, and a symbolic pi would linger as clutter. Nothing checks
that X is an angle at all, or that the difference stays in the first
turn — an obtuse angle has a negative complement, and a symbolic
expression just subtracts as it stands. This is the transformation
behind `mafcmd-supplement' and `mafcmd-complement'; to change it,
change this function."
  (let* ((hms (eq (car-safe x) 'hms))
         (calc-angle-mode (if hms 'deg calc-angle-mode))
         (radians (or (eq calc-angle-mode 'rad) (maf--contains-pi-p x)))
         (full-turn (cond ((not radians) 360)
                          ((maf--contains-float-p x) (math-mul 2 (math-pi)))
                          (t (math-mul 2 '(var pi var-pi)))))
         ;; Fractions preferred: the subtraction divides out a common
         ;; denominator, and at calc's default an exact pi - 2 pi / 3
         ;; would land on 0.333333333333 pi instead of pi / 3.
         (calc-prefer-frac t))
    (math-simplify (math-sub (math-mul part full-turn) x))))

(defun maf--ref-angle (x)
  "Return the reference angle of the angle X, or nil if it has no quadrant.
The reference angle is X's acute angle to the horizontal axis: X wraps
into one turn, then folds into quadrant I — 210 gives 30, and -45 gives
45.

X is measured against a half turn of pi when it reads as radians (it
contains pi symbolically, or `calc-angle-mode' is rad) and 180
otherwise; an hms form is degrees by construction and takes 180 either
way. The quadrant is decided on a numeric evaluation of X in half
turns, but the folding subtractions run on X itself, so exactness
survives: 100.7 gives 79.3 rather than a rounded 79.3000000001, and
5 pi / 4 gives pi / 4 rather than a float.

Nil comes back when that numeric evaluation is not a real number — a
free variable, a complex number, an interval — since nothing fixes
which quadrant such an X lies in. This is the transformation behind
`mafcmd-ref-angle'; to change it, change this function."
  (let* ((hms (eq (car-safe x) 'hms))
         ;; An hms form is degrees by construction, and calc's own hms
         ;; arithmetic is exact where a detour through a degree float
         ;; drifts (20@ 30' 15" comes back a millionth of a second off),
         ;; so the folding runs on the hms form — with the angle mode
         ;; pinned to deg, or the plain 180 it meets would be read as
         ;; radians and converted.
         (calc-angle-mode (if hms 'deg calc-angle-mode))
         (half-turn (if (or (eq calc-angle-mode 'rad) (maf--contains-pi-p x))
                        '(var pi var-pi)
                      180))
         ;; Exact ratios must not detour through floats: without this,
         ;; 300 / 180 floats and 300 folds to 59.9999999994.
         (calc-prefer-frac t))
    ;; Half turns of E as a plain number. Dividing an hms form yields a
    ;; smaller hms rather than a ratio, so those convert to degrees for
    ;; the measurement only.
    (cl-flet ((turns (e)
                (let ((calc-symbolic-mode nil))
                  (math-evaluate-expr
                   (math-div (if hms (math-from-hms e 'deg) e) half-turn)))))
      (let ((whole (turns x)))
        (when (Math-realp whole)
          (let* ((full (math-mul 2 half-turn))
                 ;; Wrap into [0, 2) half turns. Flooring the signed
                 ;; count is what turns a negative angle positive: -45
                 ;; wraps to 315, whose reference angle is 45.
                 (turn (math-floor (math-div whole 2)))
                 (r (if (math-zerop turn) x (math-sub x (math-mul turn full))))
                 (h (turns r)))
            ;; Quadrant boundaries belong to the quadrant above them, as
            ;; they must: at 90 and 270 the reference angle is 90, and
            ;; at 180 it is 0. The fold is simplified because a pi
            ;; subtraction does not collect on its own — 5 pi / 4 - pi
            ;; stays written out until it does.
            (math-simplify
             (cond ((not (math-lessp h '(frac 3 2))) (math-sub full r))
                   ((not (math-lessp h 1)) (math-sub r half-turn))
                   ((not (math-lessp h '(frac 1 2))) (math-sub half-turn r))
                   (t r)))))))))

(defun maf--cath (hyp leg)
  "Return the remaining leg of a right triangle with HYP and LEG.
The cathetus opposite LEG, by Pythagoras: sqrt(HYP^2 - LEG^2). This is
`calcFunc-hypot' run backwards — hypot builds the hypotenuse from two
legs, this recovers a leg from the hypotenuse and the other one.

Exact operands keep an exact answer: the root is taken in symbolic
mode, so 5 and 3 give 4, 2 and 1 give sqrt(3) rather than
1.73205080757, and sqrt(2) and 1 give 1 — the squaring undoes the
radical before the subtraction. A float in either operand has already
forfeited exactness, so the root evaluates numerically instead, as in
`mafcmd-to-degrees'. Symbolic operands stay written out:
sqrt(h^2 - a^2).

A LEG longer than HYP leaves a negative radicand, and calc's own sqrt
answers with the imaginary root rather than an error — the honest
reading of a triangle that does not close.

This is the transformation behind `mafcmd-cath' and `mafcmd-unit-cath';
to change it, change this function."
  (let* ((exact (not (or (maf--contains-float-p hyp)
                         (maf--contains-float-p leg))))
         (calc-symbolic-mode exact)
         (calc-prefer-frac exact))
    (math-normalize
     (list 'calcFunc-sqrt (list '- (list '^ hyp 2) (list '^ leg 2))))))

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

(defun maf--term-coefficient (term)
  "Return TERM's numeric coefficient, or 1 when it carries none.
TERM is one additive term of a normalized formula, where calc puts the
numeric factor first: 6 x gives 6, -12 gives -12, x y gives 1."
  (cond ((Math-realp term) term)
        ((and (eq (car-safe term) '*) (Math-realp (nth 1 term))) (nth 1 term))
        (t 1)))

(defun maf--poly-content (expr)
  "Return the content of EXPR: the GCD of its terms' numeric coefficients.
Always positive, and exact — rational coefficients give a rational
content, so 1:2 x + 1:3 has content 1:6 and dividing by it leaves
3 x + 2. A float coefficient has no exact content, so an expression
carrying one gives 1, as does one whose terms are coprime. Calc's own
`calcFunc-factor' leaves content in place (12 x + 12 factors to
itself), which is why `maf--poly-factorization' takes it out first."
  (let ((coeffs (mapcar (lambda (term)
                          (math-abs (maf--term-coefficient term)))
                        (mapcar #'math-normalize (maf--sum-terms expr)))))
    (if (and coeffs (cl-every #'Math-ratp coeffs))
        (let ((c (cl-reduce #'calcFunc-gcd coeffs)))
          ;; An all-zero sum gcds to 0; nothing to take out.
          (if (math-zerop c) 1 c))
      1)))

(defun maf--poly-leading-negp (expr)
  "Return t when EXPR's leading coefficient is negative.
Leading means the highest power of the variable calc reads EXPR as a
polynomial in, so 2 - x is negative-leading while x - 2 is not —
calc's own term order alone cannot tell them apart. An expression that
is no polynomial falls back to the sign of its first additive term.
Used to orient a factor before comparing it with another: a factor and
its negation are the same factor."
  (let* (;; Pin the recognizer to plain integer powers, as
         ;; `maf--quadratic-coeffs' does: these are its defaults, but
         ;; calc's own callers rebind them and it setqs some as it works.
         (math-poly-base-variable nil)
         (math-poly-neg-powers nil)
         (math-poly-mult-powers 1)
         (math-poly-frac-powers nil)
         (base (ignore-errors (math-polynomial-base expr)))
         (coeffs (and base (ignore-errors (math-is-polynomial expr base)))))
    (math-looks-negp (if coeffs
                         (car (last coeffs))
                       (car (maf--sum-terms expr))))))

(defun maf--poly-factorization (expr)
  "Return EXPR as a flat list of (BASE . EXPONENT) factors.
The factors multiply back to EXPR, with numeric bases left as numbers
and every exponent a nonzero integer. Products split, integer powers
distribute their exponent over the base's own factors — (x + 1)^2
gives x + 1 twice over, not the square as one opaque factor — a
quotient inverts its divisor's exponents, and a negation contributes
-1. A sum has its content taken out as a numeric factor and
`calcFunc-factor' applied to what remains, so 12 x + 12 gives 12 and
x + 1. Whatever resists — an irreducible sum, a variable, a symbolic
power — comes back as one factor with exponent 1."
  (cond
   ((Math-realp expr) (list (cons expr 1)))
   ((eq (car-safe expr) '*)
    (append (maf--poly-factorization (nth 1 expr))
            (maf--poly-factorization (nth 2 expr))))
   ((eq (car-safe expr) '/)
    (append (maf--poly-factorization (nth 1 expr))
            (mapcar (lambda (f) (cons (car f) (- (cdr f))))
                    (maf--poly-factorization (nth 2 expr)))))
   ((eq (car-safe expr) 'neg)
    (cons (cons -1 1) (maf--poly-factorization (nth 1 expr))))
   ((and (eq (car-safe expr) '^)
         (integerp (nth 2 expr))
         (/= (nth 2 expr) 0))
    (let ((e (nth 2 expr)))
      (mapcar (lambda (f) (cons (car f) (* (cdr f) e)))
              (maf--poly-factorization (nth 1 expr)))))
   ((memq (car-safe expr) '(+ -))
    (let* ((c (maf--poly-content expr))
           (prim (if (equal c 1) expr (math-div expr c)))
           ;; Factoring can signal on shapes calc's polynomial code
           ;; rejects (float or symbolic coefficients); the primitive
           ;; part then stands as its own factor.
           (factored (condition-case nil (calcFunc-factor prim) (error prim)))
           ;; Recurse only into a shape factoring actually opened up:
           ;; a sum that came back a sum is irreducible, and recursing
           ;; on it would factor it again forever.
           (parts (if (memq (car-safe factored) '(* / ^ neg))
                      (maf--poly-factorization factored)
                    (list (cons factored 1)))))
      (if (equal c 1) parts (cons (cons c 1) parts))))
   (t (list (cons expr 1)))))

(defun maf--poly-lcm-merge (a b)
  "Return a common multiple of A and B, factored: `maf--poly-lcm's merge.
Both operands are factored by `maf--poly-factorization', and the
result keeps every distinct factor at the higher of its two exponents,
with the LCM of the two numeric coefficients out front. Factors that
differ only in sign count as one — 2 - x is x - 2 with the sign moved
into the coefficient — so x^2 - 4 and 4 - x^2 share their factors
instead of stacking both orientations. The coefficient always comes
out positive, as calc's own lcm does; float coefficients, which have
no lcm, multiply instead. A zero operand gives 0.

The result is built as a literal product (`maf--literal'), so
committing it keeps the factored form rather than distributing the
coefficient back in. Merging is only as good as calc's factoring, so
`maf--poly-lcm' checks the result for minimality before returning it."
  (let ((calc-simplify-mode nil)
        (calc-prefer-frac t))
    (if (or (math-zerop a) (math-zerop b))
        0
      (let (table)                      ; rows of (BASE EXP-A EXP-B)
        (cl-labels
            ((absorb (expr slot)
               ;; Fold EXPR's factors into TABLE at SLOT, returning the
               ;; numeric coefficient they carry.
               (let ((coeff 1))
                 (dolist (factor (maf--poly-factorization expr) coeff)
                   (let ((base (car factor))
                         (e (cdr factor)))
                     (if (Math-realp base)
                         (setq coeff (math-mul coeff (math-pow base e)))
                       ;; Simplify the factor into calc's canonical
                       ;; shape — its terms ordered, its arithmetic
                       ;; folded — so two spellings of one factor match
                       ;; structurally below.
                       (setq base (math-simplify base))
                       ;; Then orient it positive-leading, the sign
                       ;; moving into the coefficient, so 2 - x and
                       ;; x - 2 are one factor and the LCM comes out
                       ;; reading forwards.
                       (when (maf--poly-leading-negp base)
                         (setq base (math-simplify (math-neg base)))
                         (setq coeff (math-mul coeff (math-pow -1 e))))
                       (let ((row (cl-find base table
                                           :key #'car :test #'math-equal)))
                         (unless row
                           ;; Recorded in the opposite orientation: reuse
                           ;; that row and move the sign into the
                           ;; coefficient, so (2 - x) folds onto (x - 2).
                           (setq row (cl-find (math-neg base) table
                                              :key #'car :test #'math-equal))
                           (when row
                             (setq coeff (math-mul coeff (math-pow -1 e)))))
                         (unless row
                           (setq row (list base 0 0))
                           (setq table (nconc table (list row))))
                         (cl-incf (nth slot row) e))))))))
          (let* ((ca (absorb a 1))
                 (cb (absorb b 2))
                 (coeff (math-abs (if (and (Math-ratp ca) (Math-ratp cb))
                                      (calcFunc-lcm ca cb)
                                    (math-mul ca cb))))
                 (factors
                  (cl-loop for row in table
                           for e = (max (nth 1 row) (nth 2 row))
                           unless (zerop e)
                           collect (if (= e 1) (car row) (list '^ (car row) e)))))
            ;; Nest the product to the right, as calc's own canonical
            ;; products are, so it prints as one flat juxtaposition
            ;; rather than a left-leaning pile of parentheses.
            (maf--literal
              (if (null factors)
                  coeff
                (cl-reduce #'calcFunc-mul
                           (if (equal coeff 1) factors (cons coeff factors))
                           :from-end t)))))))))

(defun maf--poly-exact-quotient (a b)
  "Return A / B when B divides A exactly, else nil.
The division is polynomial (calc's `calcFunc-pdivrem'), so the
quotient comes back a polynomial and a remainder disqualifies it.
Calc's rational simplifier is not usable here: `calcFunc-nrat' spins
forever on some of the shapes involved, ((-6 x - 6) (4 x + 4)) over
2 x + 2 among them."
  (let ((calc-simplify-mode nil)
        (calc-prefer-frac t))
    (ignore-errors
      (let ((dr (calcFunc-pdivrem (math-simplify (calcFunc-expand a)) b)))
        (and (eq (car-safe dr) 'vec)
             (math-zerop (math-simplify (nth 2 dr)))
             (math-simplify (nth 1 dr)))))))

(defun maf--poly-lcm-by-gcd (a b)
  "Return A B / pgcd(A, B), expanded, or nil when calc cannot compute it.
The textbook LCM, built from calc's own polynomial GCD. It is exact in
its factors but expanded, and its content can overshoot where pgcd's
does — calc's pgcd(10 x y, 15 x z) is 10 x, not 5 x — so
`maf--poly-lcm' uses it as a yardstick for the merged LCM rather than
as the answer. Nil when pgcd declines the operands (float
coefficients: \"Coefficients must be rational\") or the GCD is zero."
  (ignore-errors
    (let ((g (let ((calc-simplify-mode nil) (calc-prefer-frac t))
               (calcFunc-pgcd a b))))
      (and (not (math-zerop g))
           (maf--poly-exact-quotient (calcFunc-mul a b) g)))))

(defun maf--poly-lcm (a b)
  "Return the least common multiple of the polynomials A and B, factored.
The LCM is merged from the two factorizations by `maf--poly-lcm-merge'
— see there for how the factors, signs, and coefficient come out.

That merge is only as good as calc's factoring, which does not always
split a polynomial completely: x^10 - 1 factors to
(x + 1) (x - 1) (x^8 + x^6 + x^4 + x^2 + 1), burying the
x^4 + x^3 + x^2 + x + 1 that x^5 - 1 shares inside the last term, and
the merge would then carry that factor twice. So the merged result is
divided by `maf--poly-lcm-by-gcd', the LCM calc's polynomial GCD
gives: anything but a number left over means the merge overshot, and
the GCD-derived LCM is factored and returned in its place. Where the
comparison cannot be made — float coefficients, which pgcd rejects —
the merged result stands. A zero operand gives 0.

This is the transformation behind `mafcmd-poly-lcm'; to change it,
change this function."
  (let ((merged (maf--poly-lcm-merge a b)))
    (or (and (not (math-zerop merged))
             (let* ((least (maf--poly-lcm-by-gcd a b))
                    (excess (and least
                                 (not (math-zerop least))
                                 (maf--poly-exact-quotient merged least))))
               ;; Present the fallback through the same merge, so it
               ;; comes back factored like any other result.
               (and excess (not (Math-realp excess))
                    (maf--poly-lcm-merge least 1))))
        merged)))

(defun maf--fraction-parts (expr)
  "Return EXPR as a cons (NUMERATOR . DENOMINATOR).
The denominator is whatever EXPR divides by, however it is spelled: a
literal rational (Calc stores 8:3 as `(frac 8 3)'), an explicit
division, a negated one, or a product of any of those — 2 (x / 3)
gives (2 x . 3) and (x / 2) / (y / 3) gives (3 x . 2 y). Anything
else is its own numerator over a denominator of 1, so a term with
nothing to divide comes back untouched rather than restructured.

Nothing is simplified along the way: the parts are built literally so
the caller decides what to fold, and a numerator built here is not
expanded against its own factors."
  (pcase (car-safe expr)
    ('frac (cons (nth 1 expr) (nth 2 expr)))
    ('/ (let ((a (maf--fraction-parts (nth 1 expr)))
              (b (maf--fraction-parts (nth 2 expr))))
          (cons (math-mul (car a) (cdr b))
                (math-mul (cdr a) (car b)))))
    ('neg (let ((a (maf--fraction-parts (nth 1 expr))))
            (cons (math-neg (car a)) (cdr a))))
    ;; A negative integer power is a division calc has already folded:
    ;; the terms of 1 / x^2 + 1 / x^3 reach here as x^-2 and x^-3.
    ('^ (if (and (math-integerp (nth 2 expr)) (math-negp (nth 2 expr)))
            (cons 1 (list '^ (nth 1 expr) (math-neg (nth 2 expr))))
          (cons expr 1)))
    ('* (let ((parts (mapcar #'maf--fraction-parts (cdr expr))))
          ;; A product with no divisor anywhere keeps its original
          ;; shape: rebuilding it from the factors would reassociate
          ;; a b c for no gain.
          (if (cl-every (lambda (p) (equal (cdr p) 1)) parts)
              (cons expr 1)
            (cons (cl-reduce #'math-mul (mapcar #'car parts))
                  (cl-reduce #'math-mul (mapcar #'cdr parts))))))
    (_ (cons expr 1))))

(defun maf--stacked-division-p (expr)
  "Non-nil when EXPR is a division with a division inside it.
The shape one term can still collect: a numerator or divisor that
divides by something of its own, so the two stacked divisions fold
into one. Calc's literal rationals count — (8:3) / x^2 is 8 / (3 x^2)
— which is how an integer ratio over a symbolic divisor arises."
  (and (eq (car-safe expr) '/)
       (not (and (equal (cdr (maf--fraction-parts (nth 1 expr))) 1)
                 (equal (cdr (maf--fraction-parts (nth 2 expr))) 1)))))

(defun maf--collectible-fractions-p (expr)
  "Non-nil when EXPR has fractions to collect over a common denominator.
A sum qualifies once any of its terms divides by something; a lone
term only when its divisions are stacked
\(`maf--stacked-division-p'), so a fraction that is already single —
x / 2, or the literal 1:3 — is left as it is.

The `:widen' predicate for `mafcmd-collect-fractions', and the same
test `maf--collect-fractions' applies before transforming: point on
the y of 2^(y/3 - 1:3) names a node with nothing to collect, and the
command acts on the enclosing sum that has."
  (let ((terms (maf--sum-terms expr)))
    (if (cdr terms)
        (cl-some (lambda (term)
                   (not (equal (cdr (maf--fraction-parts term)) 1)))
                 terms)
      (maf--stacked-division-p expr))))

(defun maf--collect-fractions (expr)
  "Return EXPR's additive terms combined over their least common denominator.
Each term contributes its denominator (`maf--fraction-parts'), the LCD
is their LCM (`maf--poly-lcm', so numbers, variables, polynomials and
opaque factors like sqrt(2) all take part), and each numerator is
rescaled by the LCD over its own denominator before the sum is formed.
The sum is simplified — like denominators collect — but the result is
divided literally, so it commits as one fraction instead of being
distributed back over its terms.

Nil when there is nothing to do: nothing to collect in the first place
\(`maf--collectible-fractions-p'), or some term's denominator does not
divide the LCD exactly, which is the signal to leave EXPR alone rather
than commit a rearrangement that does not hold."
  (let* (;; Default simplify mode and exact fractions throughout, as in
         ;; `mafcmd-factor-gcd': the terms have to fold and the scaling
         ;; has to stay exact even with simplification switched off.
         ;; Symbolic too, so collecting over a sqrt(2) denominator does
         ;; not evaluate it into a float on the way past.
         (calc-simplify-mode nil)
         (calc-prefer-frac t)
         (calc-symbolic-mode t)
         (parts (mapcar #'maf--fraction-parts (maf--sum-terms expr)))
         (denoms (mapcar #'cdr parts)))
    (when (maf--collectible-fractions-p expr)
      (let ((lcd (ignore-errors (cl-reduce #'maf--poly-lcm denoms))))
        (when (and lcd (not (math-zerop lcd)))
          (let ((nums (cl-loop
                       for (num . den) in parts
                       for scale = (if (math-equal den lcd)
                                       1
                                     (maf--poly-exact-quotient lcd den))
                       ;; A denominator the LCD is not a multiple of
                       ;; means the LCD is not one: give up whole.
                       unless scale return nil
                       collect (math-mul num scale))))
            (when nums
              (let ((num (math-simplify (cl-reduce #'math-add nums))))
                ;; Terms that cancel give 0, not 0 over the LCD.
                (maf--literal
                  (if (math-zerop num) 0 (calcFunc-div num lcd)))))))))))

(defun maf--float-fracs (expr)
  "Float the fractions in EXPR, leaving integers exact.
Unlike `calcFunc-pfloat', which pervasively floats every number
\(6 x + 8:3 becomes 6. x + 2.67), only the non-integer exact numbers
convert: 6 x + 8:3 becomes 6 x + 2.67."
  (cond
   ((eq (car-safe expr) 'frac) (math-float expr))
   ((consp expr) (cons (car expr) (mapcar #'maf--float-fracs (cdr expr))))
   (t expr)))

(defun maf--remove-relation (expr)
  "Return the meaningful side of EXPR's relation, or EXPR when it has none.
`calcFunc-rmeq' decides which side that is: the right-hand side of a
relation (x = 5 gives 5, a < b gives b), except when the right side is
a bare variable and the left an object, where the object side wins
\(5 = x gives 5); the right side of an assignment and the left of an
evalto. A vector maps element-wise, keeping its shape, so a list of
equations gives a list of sides.

Whatever rmeq cannot strip — anything that is not a relation — comes
back unchanged rather than wrapped in an unevaluated rmeq() call."
  (if (eq (car-safe expr) 'vec)
      (cons 'vec (mapcar #'maf--remove-relation (cdr expr)))
    (let ((removed (calcFunc-rmeq expr)))
      ;; rmeq returns its own call unevaluated when there is nothing to
      ;; remove; that is the no-op signal.
      (if (eq (car-safe removed) 'calcFunc-rmeq) expr removed))))

(defun maf--float-rationals (expr)
  "Make EXPR's exact rational arithmetic inexact.
Fractions float, and a quotient whose divisor is a number becomes the
floated quotient — 1:3 gives 0.333333333333, and x / 3 gives
0.333333333333 x — so a numeric evaluation of the result reaches a
float instead of stopping at an exact rational or at a symbolic
division. Integers that divide nothing stay exact, so 2 + 3 still
evaluates to 5, and division by a non-number (1 / (x + 1)) is left
alone. Runs after the evaluation in `mafcmd-evaluate', finishing off
the exact rationals numeric evaluation leaves behind."
  (pcase expr
    (`(frac . ,_) (math-float expr))
    (`(/ ,a ,b)
     (let ((fa (maf--float-rationals a))
           (fb (maf--float-rationals b)))
       (cond
        ;; Nothing to reach for: the divisor has no numeric value.
        ((or (not (Math-realp fb)) (math-zerop fb)) (list '/ fa fb))
        ;; A wholly numeric quotient divides directly.
        ((Math-realp fa) (math-div (math-float fa) fb))
        ;; Otherwise the quotient becomes a floated coefficient. Let
        ;; calc reduce it first — 3 x / 6 is x / 2 — so the float is
        ;; rounded once: floating 1/6 and multiplying the 3 back in
        ;; would give 0.500000000001 x.
        (t (pcase (math-div fa fb)
             ((and `(/ ,qa ,qb) (guard (Math-realp qb)))
              (math-mul (math-float (math-div 1 qb)) qa))
             (q (maf--float-rationals q)))))))
    ((pred consp) (cons (car expr) (mapcar #'maf--float-rationals (cdr expr))))
    (_ expr)))

(defconst maf--identify-tolerance '(float 1 -8)
  "Absolute tolerance `maf--identify-expr' matches candidates within.
A candidate qualifies when its value differs from the target by less
than this — loose enough that a hand-typed 1.41421356 still identifies
as sqrt(2). Past a magnitude of 100 the tolerance grows with the
target, since calc's own precision cannot resolve a fixed 1e-8 there.")

(defun maf--identify-expr (x)
  "Return a simple closed form for the real number X, or nil if none fits.
Candidates are tried in this order, the first match winning: integer,
fraction p/q with q <= 20, (p/q) sqrt(n) for square-free n <= 30,
sqrt(n), n^(1/3), n^(1/4) for n <= 10000, (p/q) pi, (p/q) e, and ln(n)
for 2 <= n <= 1000. A candidate matches when its own value comes within
`maf--identify-tolerance' of X, so the float a closed form evaluates
to identifies back to it: 1.41421356237 gives sqrt(2).

The result is normalized in symbolic mode, so it stays exact instead
of collapsing back into the float it was matched against. X may be
negative; the search runs on its magnitude and the winner is negated.
This is the transformation behind `mafcmd-identify'; to change,
reorder, or extend the candidates, change this function."
  (let* ((calc-symbolic-mode nil)
         (neg (math-negp x))
         (ax (if neg (math-neg x) x))
         ;; Square-free integers 2..30 (no repeated prime factor). Keeps
         ;; the sqrt(n) candidates irreducible, so sqrt(6) is not
         ;; identified as (1/2) sqrt(24).
         (sqfree '(2 3 5 6 7 10 11 13 14 15 17 19 21 22 23 26 29 30)))
    (cl-flet* ((val (e) (math-evaluate-expr e))
               (sym (e) (let ((calc-symbolic-mode t)) (math-normalize e)))
               ;; Past a magnitude of 100 the tolerance scales with the
               ;; target: a flat 1e-8 is below what calc's 12-digit
               ;; precision can resolve there. It stays absolute below
               ;; that, since scaling it everywhere admits nonsense
               ;; matches — 12345.6789 is within a scaled tolerance of
               ;; sqrt(152415788).
               (near-p (a b)
                 (let ((m (math-abs b)))
                   (math-lessp (math-abs (math-sub a b))
                               (math-mul maf--identify-tolerance
                                         (if (math-lessp m 100)
                                             1
                                           (math-div m 100))))))
               (close-p (e) (near-p (val e) ax))
               ;; Rounding the target's power to a radicand is only
               ;; meaningful while that radicand stays small: root(n) for
               ;; a huge n is neither simple nor pinned down, since the
               ;; rounding moves the root itself by more than the
               ;; tolerance allows for.
               (radicand-p (n) (and (math-posp n) (math-lessp n 10001)))
               (signed (e) (sym (if neg (math-neg e) e)))
               (try-rat (af)  ; AF as an exact p/q with q <= 20, else nil
                 (cl-loop for q from 1 to 20 thereis
                          (let* ((pf (math-mul af q))
                                 (p (calcFunc-round pf)))
                            (and (near-p pf p)
                                 (math-normalize (list 'frac p q)))))))
      (or
       ;; Integer.
       (let ((n (calcFunc-round ax)))
         (and (close-p n) (signed n)))
       ;; Fraction p/q.
       (let ((r (try-rat ax)))
         (and r (signed r)))
       ;; (p/q) sqrt(n) for square-free n, which covers a bare sqrt(n)
       ;; too (the ratio comes back 1).
       (cl-loop for n in sqfree thereis
                (let ((r (try-rat (math-div ax (val (list 'calcFunc-sqrt n))))))
                  (and r (signed (list '* r (list 'calcFunc-sqrt n))))))
       ;; sqrt(n) for any n: the radicands the square-free search skips.
       (let ((n (calcFunc-round (math-mul ax ax))))
         (and (radicand-p n)
              (close-p (list 'calcFunc-sqrt n))
              (signed (list 'calcFunc-sqrt n))))
       ;; n^(1/3) and n^(1/4).
       (cl-loop for k in '(3 4) thereis
                (let* ((n (calcFunc-round (val (list '^ ax k))))
                       (e (list '^ n (list 'frac 1 k))))
                  (and (radicand-p n) (close-p e) (signed e))))
       ;; (p/q) pi and (p/q) e.
       (cl-loop for c in '((var pi var-pi) (var e var-e)) thereis
                (let ((r (try-rat (math-div ax (val c)))))
                  (and r (signed (list '* r c)))))
       ;; ln(n), for positive x only. Above ln(1000) no candidate can
       ;; match, and exponentiating a large x is pointless work.
       (and (not neg) (math-lessp ax 7)
            (let ((n (calcFunc-round (val (list 'calcFunc-exp ax)))))
              (and (not (math-lessp n 2)) (math-lessp n 1001)
                   (close-p (list 'calcFunc-ln n))
                   (sym (list 'calcFunc-ln n)))))))))

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

(defun maf--unknown-fn-call-p (expr &optional nargs)
  "Return t if EXPR is a call to a function Calc does not define.
An unknown function is a `calcFunc-' head with no Lisp definition —
what Calc leaves behind for f(x) when f has never been defined, as
opposed to sin(x) or ln(x). With NARGS, also require exactly that many
arguments."
  (let ((fn (car-safe expr)))
    (and fn (symbolp fn)
         (string-prefix-p "calcFunc-" (symbol-name fn))
         (not (fboundp fn))
         (or (null nargs) (= (length (cdr expr)) nargs))
         t)))

(defun maf--coordinate-set-index (items)
  "Return the `maf-coordinate-name-sets' index naming ITEMS, or nil.
ITEMS is a coordinate vector's element list. It counts as named by a set
when every element is an equation whose left side is that set's name for
its position — exactly the forms `maf--coordinate-cycle' produces. A
plain vector, a partially named one, or one named with variables from no
set all return nil, and so re-enter the cycle at the first set."
  (and items
       (cl-position-if
        (lambda (names)
          (and (<= (length items) (length names))
               (cl-every (lambda (item name)
                           (and (eq (car-safe item) 'calcFunc-eq)
                                (equal (nth 1 item) name)))
                         items names)))
        maf-coordinate-name-sets)))

(defun maf--coordinate-cycle (vec)
  "Return calc vector VEC named by the next coordinate set, or nil.
The components keep their values — the right side of an element that is
already an equation, the element itself otherwise — and are paired with
the names of the set following the one VEC uses (see
`maf--coordinate-set-index'), wrapping around at the end of
`maf-coordinate-name-sets'. Returns nil when VEC is empty or has more
components than the target set has names."
  (let ((items (cdr vec)))
    (when items
      (let* ((cur (maf--coordinate-set-index items))
             (names (nth (if cur
                             (mod (1+ cur) (length maf-coordinate-name-sets))
                           0)
                         maf-coordinate-name-sets)))
        (when (<= (length items) (length names))
          (cons 'vec
                (cl-mapcar (lambda (name item)
                             (list 'calcFunc-eq name
                                   (if (eq (car-safe item) 'calcFunc-eq)
                                       (nth 2 item)
                                     item)))
                           names items)))))))

(defun maf-vconcat (a b)
  "Concatenate A and B into a vector.
Calc's own `calcFunc-vconcat' (the | operator) only builds the vector
when it can prove both operands are objects, vectors, or declared
scalars; otherwise it leaves `a | b' symbolic, so x | y, 1 | x and
[1, 2] | x all stay unconcatenated. maf commits to the vector reading
instead — the operator's whole point here is to build a vector — and so
gives [x, y], [1, x] and [1, 2, x].

Vector operands still splice rather than nest, and a plain vector joined
with a matrix becomes one row of it; those are `math-concat''s rules,
reproduced here without its scalar test."
  (append (if (and (math-vectorp a)
                   (or (math-matrixp a) (not (math-matrixp b))))
              a
            (list 'vec a))
          (if (and (math-vectorp b)
                   (or (math-matrixp b) (not (math-matrixp a))))
              (cdr b)
            (list b))))

(defun maf-vconcatrev (a b)
  "Concatenate B and A into a vector, the reverse of `maf-vconcat'."
  (maf-vconcat b a))

(defun maf--combinations (items k)
  "Return every K-element combination of list ITEMS, as a list of lists.
Combinations are taken by position, so each element is used at most once
per group, and both the order within a group and the order among the
groups follow ITEMS: (a b c) taken two at a time gives (a b), (a c),
(b c). A K of zero gives one empty combination; a K larger than ITEMS
gives none."
  (cond ((<= k 0) (list nil))
        ((null items) nil)
        (t (append
            (mapcar (lambda (rest) (cons (car items) rest))
                    (maf--combinations (cdr items) (1- k)))
            (maf--combinations (cdr items) k)))))

(defun maf--unique-groups (vec n)
  "Return calc vector VEC's elements grouped N at a time, as a vector.
Each group is itself a vector, holding N of VEC's elements in VEC's own
order, and the groups run in the order `maf--combinations' produces.

Groups that come out identical are kept once: VEC's elements are taken
by position, so repeated elements would otherwise repeat whole groups —
\[a, a, b] would list [a, b] twice. What is left is the distinct
groupings, which is what the vector's contents, rather than its
positions, have to say."
  (let ((seen (make-hash-table :test #'equal))
        groups)
    (dolist (group (maf--combinations (cdr vec) n))
      (unless (gethash group seen)
        (puthash group t seen)
        (push (cons 'vec group) groups)))
    (cons 'vec (nreverse groups))))

(defun maf--flip-relation-op (op)
  "Return relation OP with its direction reversed: lt <-> gt, leq <-> geq.
Symmetric operators (eq, neq) return unchanged."
  (or (cdr (assq op '((calcFunc-lt  . calcFunc-gt)
                      (calcFunc-gt  . calcFunc-lt)
                      (calcFunc-leq . calcFunc-geq)
                      (calcFunc-geq . calcFunc-leq))))
      op))

(defun maf--flip-relation (rel)
  "Return relation REL read from the other side: a < b becomes b > a.
Both the operands and the direction turn, so the statement is the same
one — only which side its subject stands on changes. A symmetric
relation (eq, neq) keeps its operator and just swaps sides."
  (list (maf--flip-relation-op (car rel)) (nth 2 rel) (nth 1 rel)))

(provide 'maf-math)
