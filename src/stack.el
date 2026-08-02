;; -*- lexical-binding: t; -*-
;;
;; stack.el
;;
;; Hand-written contextual stack commands: composites with no single
;; calcFunc equivalent.

(require 'maf-defcmd)
(require 'maf-conf "conf")
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
(declare-function calc-push-list "calc-ext")
(declare-function calcFunc-pfloat "calc-stuff")
(declare-function calc-roll-down "calc-misc")
(declare-function calc-locate-cursor-element "calc-yank")
(declare-function calc-del-selection "calc-sel")
(declare-function calc-clear-selections "calc-sel")
;; Calc's fancy-prefix dispatch (K, I, H, O), advised below.
(declare-function calc-fancy-prefix-other-key "calc-ext")
(declare-function calc-unread-command "calc")
(declare-function calc-change-mode "calc-mode")
(declare-function calc-reset "calc-ext")
;; The timeline is a feature module, optional by design; `maf-reset'
;; calls this only when it is loaded.
(declare-function maf-timeline-clear "maf-timeline")
;; The module system is optional; `maf--reset-calc' calls this only when
;; it is loaded, to re-apply the module list across a reset.
(declare-function maf-modules-apply "maf-module")
;; Calc's own, for the recovery path in `maf--reset-calc'.
(declare-function calc-mode-var-list-restore-default-values "calc")
;; Defined in maf.el, which loads this file; the reset commands read
;; and restore it around `calc-reset'.
(defvar maf-mode)
(declare-function maf-mode "maf")
(declare-function calc-normal-language "calc-lang")
(declare-function calc-big-language "calc-lang")
(declare-function math-solve-eqn "calcalg2")
(declare-function math-expr-subst "calc-alg")
(declare-function math-expr-contains "calc-alg")
(declare-function calc-find-selected-part "calc-sel")
(declare-function calc-prepare-selection "calc-sel")
(declare-function calc-commute-left "calcsel2")
(declare-function calc-commute-right "calcsel2")
(declare-function calc-auto-selection "calc-sel")
(declare-function calc-find-assoc-parent-formula "calc-sel")
(declare-function calc-find-parent-formula "calc-sel")
(declare-function calc-unselect "calc-sel")
(declare-function calc-sel-jump-equals "calcsel2")
(declare-function calc-var-value "calc-ext")
;; Calc's JumpRules holder: the symbol `calc-JumpRules' until first use,
;; then the parsed rule set cached in its place by `calc-var-value'.
(defvar var-JumpRules)
(declare-function calcFunc-factor "calc-poly")
(declare-function calcFunc-roots "calcalg2")
(declare-function calcFunc-sub "calc-arith")
(declare-function math-evaluate-expr "calc-ext")
(declare-function calc-is-assignments "calc-store")
(declare-function math-compose-expr "calccomp")
(declare-function math-vectorp "calc-ext")
(declare-function math-flatten-vector "calc-vec")
(declare-function calc-set-language "calc-lang")
(declare-function math-read-expr "calc-aent")
(declare-function calc-unpack-item "calc-vec")
(declare-function math-vectorp "calc-ext")
(declare-function math-num-integerp "calc-ext")
(declare-function math-trunc "calc-misc")
(declare-function math-evenp "calc-misc")
(defvar calc-unpack-with-type)
;; Defined in maf.el, which cannot be required from here — it loads
;; this file. `maf-reset-settings' restores the mode calc-reset kills.
(defvar maf-mode)
(declare-function maf-mode "maf")

(maf-defcmd mafcmd-factor-by (expr arg commit)
  "Factor the resolved expression by the top-of-stack argument.

  6 x + 12 by 6  =>  6 (x + 2)

Divides by the argument and commits argument * quotient with the
product left undistributed, whatever the argument — dividing by a
non-factor just moves it out front. Point picks the target as usual:
a sub-formula at point, each side of an equation, stack level 2 at
home; the top entry is always the argument, popped on commit.

  6 x + 12 by 5             =>  5 (6:5 x + 12:5)
  6 x + 12 = 18 y + 6 by 6  =>  6 (x + 2) = 6 (3 y + 1)"
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

  6 x + 12  =>  6 (x + 2)

The GCD is pulled across all terms with the product left
undistributed; a negative leading term pulls out the negated GCD.
With nothing to pull out the expression commits unchanged, so
equation sides that don't factor pass through quietly. Point picks
the target as usual: a sub-formula at point, each side of an
equation, the top entry at home.

  -3 x + 3         =>  -3 (x - 1)
  10 x y + 15 x z  =>  (5 x)*(3 z + 2 y)
  3 x + 7          =>  3 x + 7    (coprime terms: unchanged)
  2.5 x + 5.       =>  2.5 x + 5.  (float coefficients: unchanged)"
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

(maf-defcmd mafcmd-factor-powers (expr _arg commit)
  "Factor the resolved binomial by a square or cube product identity.

  x^2 - 9  =>  (x + 3) (x - 3)

The two additive terms are rooted and the matching identity built
from the roots — difference of squares, sum or difference of cubes,
complex conjugates for a sum of squares — preferring the most exact
candidate: differences try squares before cubes, sums try cubes
before conjugates. A root that resists stays under a radical, kept
exact, when the other term's root is clean: squares of variables,
perfect numeric powers. Anything else — more or fewer than two terms,
a linear binomial, radicals that would spill onto both sides — commits
unchanged, so equation sides without a factorable binomial pass
through quietly. Point picks the target as usual: a sub-formula at
point, each side of an equation, the top entry at home.

  x^3 - 8        =>  (x - 2) (x^2 + 2 x + 4)
  x^3 + 8        =>  (x + 2) (x^2 - 2 x + 4)
  x^2 + 9        =>  (3 + x i) (3 - x i)
  x^2 - 5        =>  (x + sqrt(5)) (x - sqrt(5))
  x^6 - 64       =>  (x^3 + 8) (x^3 - 8)
  4 x^2 - 9      =>  (2 x + 3) (2 x - 3)
  9 - x^2        =>  (3 + x) (3 - x)
  (x + 1)^2 - 9  =>  (x + 4) (x - 2)
  x^2 - x        =>  x^2 - x   (no identity: unchanged)"
  :arity unary
  :prefix "fpow"
  (let ((terms (let ((calc-simplify-mode nil)
                     (calc-prefer-frac t))
                 ;; Normalize each term so signs surface and
                 ;; coefficients are canonical, as in `mafcmd-factor-gcd'.
                 (mapcar #'math-normalize (maf--sum-terms expr)))))
    (commit (or (and (= (length terms) 2)
                     (maf--factor-powers (nth 0 terms) (nth 1 terms)))
                expr))))

(maf-defcmd mafcmd-poly-lcm (expr arg commit)
  "Take the LCM of the resolved expression and the top-of-stack argument.

  x^2 - 1 with x^2 - x  =>  (x + 1) (x - 1) x

Both operands are factored — the content out front, then calc's own
factoring on what remains — and the result keeps every
distinct factor at the higher of its two exponents, with the LCM of
the contents as the coefficient. It commits factored, not distributed,
so the shared and unshared parts stay legible. The coefficient comes
out positive, and factors differing only in sign count as one, so
x^2 - 4 and 4 - x^2 give a degree-2 LCM rather than stacking both
orientations. A zero operand gives 0.

Like any binary command, the entry at point is the subject and the top
of the stack is the argument, consumed on commit; point picks the
subject as usual — a sub-formula at point, each side of an equation,
stack level 2 at home. The polynomial GCD is calc's own, on a g
\(`mafcmd-pgcd').

  6 (x + 1) with 4 (x + 1)      =>  12 (x + 1)
  6 x + 6 with 4 x + 4          =>  12 (x + 1)
  x + 1 with x + 2              =>  (x + 1) (x + 2)   (coprime)
  x^2 - 1 with x^2 - 1          =>  (x + 1) (x - 1)
  12 z^6 (w - 7)^3 with 20 z^5 (w - 7)^4
                                =>  60 z^6 (w - 7)^4"
  :arity binary
  :prefix "plcm"
  (commit (maf--poly-lcm expr arg)))

(maf-defcmd mafcmd-complete-square (expr _arg commit)
  "Complete the square: rewrite the resolved quadratic in vertex form.

  x^2 + 6 x  =>  (x + 3)^2 - 9

The result is a (x + h)^2 + k with h = b/(2 a) and k = c - b^2/(4 a),
built from the quadratic's coefficients, so any quadratic works:
symbolic coefficients, a negative or fractional leading term, a
constant term already present. The square is completed in the
leftmost sub-expression the formula is quadratic in — usually the
variable, but sin(y)^2 + 2 sin(y) completes in sin(y). Exact
coefficients give exact results: fractions, not floats. An expression
that is not a quadratic commits unchanged, so equation sides without
one — a bare constant on the right — pass through quietly. Point
picks the target as usual: a sub-formula at point, each side of an
equation, the top entry at home.

  2 x^2 + 6 x + 1        =>  2 (x + 3:2)^2 - 7:2
  a x^2 + b x + c        =>  a*(x + b / (2 a))^2 + c - b^2 / (4 a)
  -x^2 + 6 x             =>  9 - (x - 3)^2
  x^2 + 6 x + 9          =>  (x + 3)^2
  sin(y)^2 + 2 sin(y)    =>  (sin(y) + 1)^2 - 1
  x^2 + 6 x = 10         =>  (x + 3)^2 - 9 = 10
  x^3 + x^2              =>  x^3 + x^2   (not a quadratic: unchanged)"
  :arity unary
  :prefix "csqr"
  (let* ((base (maf--quadratic-base expr))
         (coeffs (and base (maf--quadratic-coeffs expr base))))
    (commit (if coeffs (maf--vertex-form coeffs base) expr))))

(defconst maf--log-exp-rules
  '(;; Exp-of-log compositions collapse. The neg and p*log variants
    ;; are matched explicitly: a bare pattern variable never matches a
    ;; missing factor, so b^log(x, b) alone would leave scaled
    ;; exponents — the very shape the power rules below produce —
    ;; uncollapsed.
    "b^log(x, b) := x"
    "b^(-log(x, b)) := 1/x"
    "b^(p*log(x, b)) := x^p"
    "e^ln(x) := x"
    "e^(-ln(x)) := 1/x"
    "e^(p*ln(x)) := x^p"
    "10^log10(x) := x"
    "10^(-log10(x)) := 1/x"
    "10^(p*log10(x)) := x^p"
    ;; Log-of-exp compositions collapse. Ordered before the power
    ;; rules, which also match these shapes but would leave a stray
    ;; x*log(b, b) behind.
    "log(b^x, b) := x"
    "ln(e^x) := x"
    "log10(10^x) := x"
    ;; Base identities.
    "log(b, b) := 1"
    "ln(e) := 1"
    "log10(10) := 1"
    ;; Power rules: the exponent moves out front.
    "ln(x^p) := p * ln(x)"
    "log(x^p, b) := p * log(x, b)"
    "log10(x^p) := p * log10(x)")
  "Rewrite rules applied by `mafcmd-log-exp', in match order.
Calc rewrite syntax; e and the literal 10 match only themselves, so
the compositions never fire on a mismatched base.")

(maf-defcmd mafcmd-log-exp (expr _arg commit)
  "Apply logarithm and exponential identities to the resolved expression.

  b^log(x, b)  =>  x

Three families of identities, applied wherever they match and repeated
until nothing changes: exp-of-log compositions collapse (including
negated and scaled exponents), log-of-exp compositions collapse, and a
log of a power moves its exponent out front. Bases must agree for a
composition to fire — e and 10 match only themselves — and rules only
rewrite where they match: everything else in the expression, including
unsimplified arithmetic, commits exactly as it was. An expression with
no matching site commits unchanged, so equation sides without one pass
through quietly. Point picks the target as usual: a sub-formula at
point, each side of an equation, the top entry at home.

  e^(2 ln(x))     =>  x^2
  ln(e^x)         =>  x
  10^(-log10(x))  =>  1 / x
  ln(x^3)         =>  3 ln(x)
  log(x^p, b)     =>  p log(x, b)
  ln(e)           =>  1
  2^ln(x)         =>  2^ln(x)   (base mismatch: unchanged)"
  :arity unary
  :prefix "lexp"
  (let ((rules (cons 'vec (math-read-exprs
                           (string-join maf--log-exp-rules ",")))))
    ;; Simplification off: math-rewrite normalizes the whole expression
    ;; each pass, which would fold arithmetic the rules never touched.
    (commit (let ((calc-simplify-mode 'none))
              (math-rewrite expr rules)))))

(maf-defcmd mafcmd-collect-fractions (expr _arg commit)
  "Combine the resolved expression's terms into a single fraction.

  a / 2 + b / 3  =>  (3 a + 2 b) / 6

Every additive term is put over the least common denominator of them
all and the numerators added, so the result is one fraction rather
than a sum of them. Denominators are taken however they are spelled —
a literal fraction, an explicit division, one buried in a product —
and they need not be numbers: variables and polynomial denominators
take part too, sharing repeated factors instead of stacking them.
The numerator collects like terms; the fraction itself is left
undistributed, so it stays a single fraction rather than being spread
back over its terms. A single term flattens when its divisions are
stacked: an integer ratio divided by something becomes one division.
With no denominator to collect over, the expression commits
unchanged, so equation sides with nothing to combine pass through
quietly. Point picks the target as usual: a sub-formula at point,
each side of an equation, the top entry at home — and a sub-formula
with nothing to collect widens to the innermost one that has, so
point on the y of 2^(y/3 - 1:3) collects the exponent.

  x / 2 + x / 3        =>  5 x / 6
  pi / 2 - 1:2         =>  (pi - 1) / 2
  8:3 / x^2            =>  8 / (3 x^2)
  1 / x + 1 / y        =>  (y + x) / (x y)
  x / 2 + 3 / a^3      =>  (x a^3 + 6) / (2 a^3)
  1/(x+1) + 1/(x^2-1)  =>  x / ((x + 1) (x - 1))
  x + 1                =>  x + 1    (no denominator: unchanged)"
  :arity unary
  :prefix "cfrc"
  :widen maf--collectible-fractions-p
  (commit (or (maf--collect-fractions expr) expr)))

(maf-defcmd mafcmd-to-degrees (expr _arg commit)
  "Convert the resolved expression from radians to degrees.

  pi / 2  =>  90

Multiplies by 180 / pi and simplifies, so exact multiples of pi
convert exactly — fractions, not floats. A float anywhere in the
expression switches to numeric pi: the value already forfeited
exactness, and a symbolic pi would survive the division as clutter.
No unit bookkeeping happens — the command trusts that the value is
radians. With the Inverse flag, routes to `mafcmd-to-radians'. Point
picks the target as usual: a sub-formula at point, each side of an
equation, the top entry at home.

  pi / 6   =>  30
  2 pi     =>  360
  1.5708   =>  90.0002104591
  r        =>  180 r / pi"
  :arity unary
  :prefix "deg"
  :inverse mafcmd-to-radians
  (commit (if (maf--contains-float-p expr)
              (math-div (math-mul expr 180) (math-pi))
            (let ((calc-prefer-frac t))
              (math-simplify (math-div (math-mul expr 180)
                                       '(var pi var-pi)))))))

(maf-defcmd mafcmd-to-radians (expr _arg commit)
  "Convert the resolved expression from degrees to radians, as a factor of pi.

  30  =>  pi / 6

Multiplies by pi / 180 and simplifies; pi stays symbolic even for
float inputs, so the result always reads as a factor of pi, exact
inputs giving exact fractions. No unit bookkeeping happens — the
command trusts that the value is degrees. With the Inverse flag,
routes to `mafcmd-to-degrees'. Point picks the target as usual: a
sub-formula at point, each side of an equation, the top entry at
home.

  90    =>  pi / 2
  45.0  =>  0.25 pi
  d     =>  d pi / 180"
  :arity unary
  :prefix "rad"
  :inverse mafcmd-to-degrees
  (commit (let ((calc-prefer-frac t))
            (math-simplify (math-div (math-mul expr '(var pi var-pi))
                                     180)))))

(maf-defcmd mafcmd-mod-360 (expr _arg commit)
  "Reduce the resolved expression modulo 360, wrapping an angle in degrees.

  400  =>  40

Negative angles wrap positive, floats keep their fraction, and a
symbolic expression stays a symbolic % form. With the Hyperbolic
flag, routes to `mafcmd-mod-180'. Point picks the target as usual: a
sub-formula at point, each side of an equation, the top entry at
home.

  -30    =>  330
  400.5  =>  40.5
  x      =>  x % 360"
  :arity unary
  :prefix "mod"
  :hyperbolic mafcmd-mod-180
  (commit (math-mod expr 360)))

(maf-defcmd mafcmd-mod-180 (expr _arg commit)
  "Reduce the resolved expression modulo 180.

  270  =>  90

`mafcmd-mod-360's Hyperbolic variant; see there. Point picks the
target as usual: a sub-formula at point, each side of an equation,
the top entry at home."
  :arity unary
  :prefix "mod"
  (commit (math-mod expr 180)))

(maf-defcmd mafcmd-ref-angle (expr _arg commit)
  "Fold the resolved expression into its reference angle in quadrant I.

  210  =>  30

The angle wraps into one turn first, so anything reduces — past a full
turn, negative, or both. Radians are recognized: an expression carrying
pi, or any angle while `calc-angle-mode' is rad, folds against pi
instead of 180, while an hms form stays in degrees. An angle with no
determined quadrant — a free variable, a complex number — commits
unchanged, so equation sides that do not apply pass through quietly.
Point picks the target as usual: a sub-formula at point, each side of
an equation, the top entry at home.

  135          =>  45
  -45          =>  45
  750          =>  30           (wraps a full turn first)
  400.5        =>  40.5
  270          =>  90           (boundaries go to the quadrant above)
  1.25 pi      =>  0.25 pi      (pi folds against pi, not 180)
  200@ 30\\=' 0\"  =>  20@ 30\\=' 0\"   (hms stays hms, and stays degrees)
  y + 210|     =>  y + 30       (sub-formula at point)
  x            =>  x            (no quadrant: unchanged)"
  :arity unary
  :prefix "refa"
  (commit (or (maf--ref-angle expr) expr)))

(maf-defcmd mafcmd-supplement (expr _arg commit)
  "Replace the resolved expression with its supplement: a half turn less it.

  30  =>  150

The half turn follows the angle rather than the mode alone: symbolic
pi anywhere in the expression makes it pi — pi / 6 supplements to
5:6 pi even in degrees mode — and otherwise `calc-angle-mode' picks
pi for radians and 180 for degrees, an hms form taking 180 in any
mode. Exact angles stay exact, and a float switches a radian half turn
to numeric pi, as in `mafcmd-to-degrees': the value has already
forfeited exactness, and a symbolic pi would linger as clutter.
Nothing checks that the value is an angle at all — a symbolic
expression just subtracts as it stands. See `maf--turn-complement',
which `mafcmd-complement' shares. Point picks the target as usual: a
sub-formula at point, each side of an equation, the top entry at home.

  150      =>  30
  pi / 6   =>  5:6 pi
  2 pi / 3 =>  pi / 3
  0.5      =>  2.64159265359  (radians mode)
  30@ 30'  =>  149@ 30'       (HMS mode)
  x        =>  180 - x"
  :arity unary
  :prefix "supp"
  (commit (maf--turn-complement expr '(frac 1 2))))

(maf-defcmd mafcmd-complement (expr _arg commit)
  "Replace the resolved expression with its complement: a quarter turn less it.

  30  =>  60

`mafcmd-supplement's twin, taking a quarter turn where that takes a
half: symbolic pi in the expression makes it pi / 2 — pi / 6
complements to pi / 3 even in degrees mode — and otherwise
`calc-angle-mode' picks pi / 2 for radians and 90 for degrees, an hms
form taking 90 in any mode. Exactness and floats work as in the
supplement; see `maf--turn-complement', which both share. Nothing
requires the angle to be acute: an obtuse one has a negative
complement, as the subtraction says. Point picks the target as usual:
a sub-formula at point, each side of an equation, the top entry at
home.

  60       =>  30
  100      =>  -10           (obtuse: the subtraction stands)
  pi / 6   =>  pi / 3
  0.5      =>  1.0707963268  (radians mode)
  30@ 30'  =>  59@ 30'       (HMS mode)
  x        =>  90 - x"
  :arity unary
  :prefix "comp"
  (commit (maf--turn-complement expr '(frac 1 4))))

(maf-defcmd mafcmd-cath (expr arg commit)
  "Take the remaining leg of a right triangle with the top-of-stack leg.

  5 with 3  =>  4

The resolved expression is the hypotenuse and the argument the known
leg; the result is the other leg, sqrt(hyp^2 - leg^2). The operands
read in the same order as `mafcmd-hypot' (f h), whose inverse this is:
hypot builds the hypotenuse from two legs, cath recovers a leg from the
hypotenuse and the other one, and each routes to the other under the
Inverse flag. Exact operands keep an exact answer — the radical stands
rather than floating — while a float in either operand evaluates
numerically; see `maf--cath'. A leg longer than the hypotenuse gives an
imaginary result rather than an error, which is calc's own answer for
the negative radicand. Point picks the target as usual: a sub-formula
at point, each side of an equation, stack level 2 at home; the top
entry is always the argument, popped on commit.

  13 with 5       =>  12
  2 with 1        =>  sqrt(3)
  sqrt(2) with 1  =>  1
  2.5 with 1.5    =>  2.
  h with a        =>  sqrt(h^2 - a^2)
  1 with 2        =>  sqrt(3) i    (leg past the hypotenuse)"
  :arity binary
  :prefix "cath"
  :inverse mafcmd-hypot
  (commit (maf--cath expr arg)))

(maf-defcmd mafcmd-unit-cath (expr _arg commit)
  "Take the remaining leg of a right triangle whose hypotenuse is 1.

  3:5  =>  4:5

`mafcmd-cath' with the hypotenuse fixed at one, so the resolved
expression is the known leg and nothing is taken from the stack:
sqrt(1 - leg^2), the unit-circle companion of a sine or cosine.
Exactness and imaginary results work as in `mafcmd-cath'. Point picks
the target as usual: a sub-formula at point, each side of an equation,
the top entry at home.

  0     =>  1
  1     =>  0
  1:2   =>  sqrt(3) / 2
  0.6   =>  0.8
  x     =>  sqrt(1 - x^2)
  2     =>  sqrt(3) i    (leg past the hypotenuse)"
  :arity unary
  :prefix "ucth"
  (commit (maf--cath 1 expr)))

(maf-defcmd mafcmd-commute (expr _arg commit)
  "Swap the first two operands of the resolved expression.

  a + b  =>  b + a

The swap is structural — nothing simplifies — so non-commutative
operators flip too, any function call swaps its first two arguments,
and operands past the second stay in place. A binary relation keeps
its meaning: the sides swap and the operator's direction reverses
with them. With nothing to swap — an atom, a unary call, an interval
— the expression commits unchanged. Point picks the target as usual:
a sub-formula at point, the two sides of a relation entry, the top
entry at home.

  a - b      =>  b - a
  2 (3 + x)  =>  (3 + x) 2   (no distribution)
  log(x, b)  =>  log(b, x)
  x < y      =>  y > x       (direction reverses: never y < x)"
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

(defun maf--anchor-on-node (m node)
  "Put point on NODE within the entry at stack level M; nil if not found.
For the commands that hand a rewrite to calc and then want point to
follow the term it moved. NODE is matched by identity in the freshly
rewritten entry, so it lands only where the rewrite reused the same
cons — true of an associative shift within a + or * chain, false once
a - or / crossing wraps the term in a fresh neg/reciprocal. Callers
fall back to a positional restore on nil."
  (ignore-errors
    (calc-prepare-selection m)
    (when-let ((pos (maf--comp-node-start-pos node)))
      (goto-char pos))))

(defun maf--commute (dir arg)
  "Shift the term under point one place through its associative chain.
DIR is `left' or `right'; ARG is the repeat count (negative reverses,
as in calc).  The associative rewrite — including the sign flips that
keep the value when a term crosses a - or / — is delegated to calc's own
`calc-commute-left'/`calc-commute-right'.  Point then follows the moved
term where identity survives the rewrite (+ and * chains), falling back
to its prior line and column otherwise.

The term must sit inside a + - * / parent, where the shift preserves
value: sums and products commute, and calc flips the sign crossing a - or
the reciprocal crossing a /.  Any other parent is left untouched, because
reordering its operands would change the value — a ^ (x^2 would become
2^x), a vector concatenation, a function's arguments — or, for a relation,
would reverse it (a < b to b < a, not b > a; swapping a relation's sides
with the direction flip that keeps it true is `mafcmd-commute' (O)).

With no such term under point — at home, on a whole entry, on a lone
term, or on a term whose parent is not + - * / — the command does nothing
rather than signaling calc's \"No term is selected\"."
  (maf--with-calc-buffer
    (let ((m (calc-locate-cursor-element (point))))
      (when (> m 0)
        (let* ((entry  (calc-top m 'entry))
               (expr   (car entry))
               (sel    (ignore-errors (calc-auto-selection entry)))
               (parent (and (consp sel)
                            (calc-find-assoc-parent-formula expr sel))))
          ;; Only commute within an arithmetic chain, where calc's shift is
          ;; value-preserving. Every other binary parent — ^, | (concat), a
          ;; relation, a function call — would have its operands reordered
          ;; by calc without regard to meaning, so reject it.
          (when (memq (car-safe parent) '(+ - * /))
            (let ((snapshot (maf--point-snapshot))
                  ;; Leave no lingering selection behind: maf resolves the
                  ;; term from point each time, as the subexpr target does.
                  (calc-keep-selection nil))
              (condition-case nil
                  (if (eq dir 'left)
                      (calc-commute-left arg)
                    (calc-commute-right arg))
                ;; "Term is already leftmost/rightmost" — nothing to do.
                (error nil))
              (or (maf--anchor-on-node m sel)
                  (maf--point-restore snapshot))
              ;; A single undo reverts point along with the stack.
              (maf--undo-record-cmd-point snapshot))))))))

(defun maf-commute-left (arg)
  "Move the term under point one place left through its associative chain.

  a + b + c|  =>  a + c| + b   (point on c)

Point selects the term as usual — the sub-formula under the cursor — and
follows it as it moves.  The shift respects the operators it crosses: a
term moved left past a minus becomes an addition of its negation, past a
division a multiplication by its reciprocal, so the value is preserved.
Repeat to walk the term further left; with the entry below the top, the
lower entry is acted on in place.

A numeric prefix N shifts N places (a negative N shifts right).  At home,
on a whole entry, or on a term outside any + or * chain — nothing to
move — the command does nothing.

  a - b|      =>  -b| + a
  a / b|      =>  (1/b)| a"
  (interactive "p")
  (maf--commute 'left arg))

(defun maf-commute-right (arg)
  "Move the term under point one place right through its associative chain.

  a| + b + c  =>  b + a| + c   (point on a)

The mirror of `maf-commute-left': point selects the term under the cursor
and follows it right, with the same sign handling when it crosses a minus
or a division.  A numeric prefix N shifts N places (a negative N shifts
left).  At home, on a whole entry, or on a term outside any + or * chain,
the command does nothing."
  (interactive "p")
  (maf--commute 'right arg))


;;; Balanced negation

(defconst maf-negate-odd-functions
  '(calcFunc-sin calcFunc-tan calcFunc-cot calcFunc-csc
    calcFunc-arcsin calcFunc-arctan
    calcFunc-sinh calcFunc-tanh calcFunc-coth calcFunc-csch
    calcFunc-arcsinh calcFunc-arctanh
    calcFunc-re calcFunc-im calcFunc-conj calcFunc-sign
    calcFunc-trunc calcFunc-round calcFunc-ftrunc calcFunc-fround)
  "One-argument functions f satisfying f(-x) = -f(x).
`mafcmd-negate' negates such a call's argument and moves the sign it
gives up out in front of the call.")

(defconst maf-negate-even-functions
  '(calcFunc-cos calcFunc-sec calcFunc-cosh calcFunc-sech calcFunc-abs)
  "One-argument functions f satisfying f(-x) = f(x).
`mafcmd-negate' negates such a call's argument and the call swallows the
sign, leaving everything around it alone.")

(defun maf--negate-whole (expr)
  "Return EXPR with its own sign flipped and the flip paid for inside it.

The in-slot form: what negating comes to wherever there is no operator
in front of the target to flip — the whole entry, and the leading term
of a sum.

A binary relation negates both sides at once and reverses its direction,
which leaves it saying the same thing. Anything else becomes the
negation of its negation: the expression is shown negated behind a
leading minus, with the same value as before.

That holds whatever EXPR is. `math-neg' distributes over a sum, so
a + b comes back as -(-a - b) with the signs moved inside, while an
atom, a product or a function call gives a plain leading minus and so
reads -(-x). Declining the second kind — on the grounds that it only
stacks one minus sign on another — would leave the same slot answering
two ways depending on the shape that filled it."
  (cond
   ((maf--relation-p expr)
    ;; Chained relations (a < b < c) have no single direction to
    ;; reverse, so only the two-sided ones are negated.
    (if (= (length expr) 3)
        (list (maf--flip-relation-op (car expr))
              (math-neg (nth 1 expr))
              (math-neg (nth 2 expr)))
      expr))
   (t (list 'neg (math-neg expr)))))

(defun maf--negate-binary (op a b i)
  "Return the binary OP node on A and B with its Ith operand negated.
Value-preserving: whatever sign the operand gives up is taken back
somewhere else in the node. Nil when OP cannot absorb the flip, leaving
the sign for the target's own slot to hold."
  (let ((neg (math-neg (if (= i 1) a b))))
    (pcase (cons op i)
      ;; A sum or difference flips the operator joining the two terms.
      ;; Only the right-hand term has one: a leading term has nothing
      ;; in front of it to flip, and negating the node as a whole would
      ;; rewrite the entire sum to show one term's sign — so that case
      ;; falls through to the in-slot form instead.
      ('(+ . 2) (list '- a neg))
      ('(- . 2) (list '+ a neg))
      ;; A product or quotient hands the sign to the other operand,
      ;; where the two minus signs cancel — no wrapping parens needed.
      ('(* . 1) (list '* neg (math-neg b)))
      ('(* . 2) (list '* (math-neg a) neg))
      ('(/ . 1) (list '/ neg (math-neg b)))
      ('(/ . 2) (list '/ (math-neg a) neg))
      ;; A power absorbs a base's sign only through an integer exponent:
      ;; an even one swallows it, an odd one passes it out front. Under
      ;; a symbolic exponent the sign has nowhere to go, and negating an
      ;; exponent is not a sign flip at all.
      ('(^ . 1) (and (math-num-integerp b)
                     (if (math-evenp b)
                         (list '^ neg b)
                       (list 'neg (list '^ neg b))))))))

(defun maf--negate-slot (parent i)
  "Return PARENT with its Ith operand replaced by its own in-slot negation.
The fallback when PARENT cannot absorb the flip itself: the minus stays
inside the target rather than reaching out to rewrite the node holding
it. PARENT itself when the target has nowhere to put the sign either."
  (let* ((target (nth i parent))
         (negated (maf--negate-whole target)))
    (if (eq negated target)
        parent
      (let ((rebuilt (copy-sequence parent)))
        (setcar (nthcdr i rebuilt) negated)
        rebuilt))))

(defun maf--negate-operand (parent i)
  "Return PARENT rewritten so its Ith operand shows negated, value unchanged.
Nil when PARENT has no way to take back the sign its operand gave up."
  (let ((op (car-safe parent))
        (n  (length (cdr parent))))
    (cond
     ;; A relation is balanced by negating both sides together — which
     ;; side point named makes no difference to the result.
     ((maf--relation-p parent) (maf--negate-whole parent))
     ((and (= n 2) (memq op '(+ - * / ^)))
      (maf--negate-binary op (nth 1 parent) (nth 2 parent) i))
     ((and (= n 1) (= i 1) (memq op maf-negate-odd-functions))
      (list 'neg (list op (math-neg (nth 1 parent)))))
     ((and (= n 1) (= i 1) (memq op maf-negate-even-functions))
      (list op (math-neg (nth 1 parent)))))))

(defun maf--negate-at (expr path)
  "Return EXPR rewritten so the sub-formula at PATH shows negated.
PATH is the list of `nth' indices leading from EXPR down to the target;
nil means EXPR itself. Nothing is normalized: the node is rebuilt down
the path and every branch off it keeps the cons it already had, so the
rest of the entry cannot be reordered or re-simplified on the way."
  (cond
   ((null path) (maf--negate-whole expr))
   ;; Last index: EXPR is the target's parent, and gets first refusal on
   ;; the sign — it is the only node that can flip an operator in front
   ;; of the target. Where it cannot, the minus stays inside the
   ;; target's own slot; nothing wider than the parent is ever touched.
   ((null (cdr path))
    (or (maf--negate-operand expr (car path))
        (maf--negate-slot expr (car path))))
   (t (let ((rebuilt (copy-sequence expr)))
        (setcar (nthcdr (car path) rebuilt)
                (maf--negate-at (nth (car path) expr) (cdr path)))
        rebuilt))))

(defun maf--negate-tree-path (tree node)
  "Return the list of `nth' indices leading from TREE down to NODE.
NODE is matched by `eq', so it must be a cons taken from TREE itself —
resolve's `:expr-ref', not the stripped `:expr' copy. Nil when NODE is
TREE itself, which means the whole of TREE. Callers reach here only
once resolve has named a target, so a NODE absent from TREE — which
also gives nil — no longer stands for \"point named nothing\"."
  (catch 'maf--negate-tree-path
    (cl-labels ((walk (cur path)
                  (when (eq cur node)
                    (throw 'maf--negate-tree-path (reverse path)))
                  (when (consp cur)
                    (cl-loop for kid in (cdr cur)
                             for i from 1
                             do (walk kid (cons i path))))))
      (walk tree nil))
    nil))

(defun maf--negate-target-path ()
  "Path from the entry at point down to the sub-formula to negate.
Nil — the whole entry — at home, at an entry's margin, and wherever
point names the entry's whole formula (its relation operator, say).

The target is classified by `maf--resolve-context', the same resolver
every other contextual command uses, so negate agrees with the rest of
maf about what point names. That matters twice over: a point naming
nothing signals there rather than reaching here, where a nil path is
indistinguishable from the whole entry and would silently negate it;
and an active region is recognized as the region target it is instead
of decaying to the single node under point.

Resolve is asked in the ordinary scope — the worker takes the entry
whole, but only the path says which part of it to negate — and probes
calc state, so point is restored around it."
  (maf--with-calc-buffer
    (save-excursion
      (let* ((context (maf--resolve-context '((:arity . unary) (:map . -1))))
             (target (alist-get :target context)))
        (pcase target
          ;; The whole formula is the target: no path to walk.
          ((or 'home 'entry 'equation) nil)
          ;; A run of chain terms is not a node, so no path leads to it:
          ;; the sign it gives up would have to be paid for by the chain
          ;; it was cut out of, which the path rewrite cannot express.
          ;; Refusing beats negating whichever single term point happens
          ;; to rest in and passing it off as the region's answer.
          ('region
           (user-error "Negate takes a whole term, not a region of one"))
          (_
           ;; `:expr-ref' is the original encased cons, the identity
           ;; `maf--negate-tree-path' matches on — the stripped `:expr'
           ;; is a copy and would never be found. Nil here now means
           ;; only that the sub-formula spans its whole entry.
           (maf--negate-tree-path
            (car (calc-top (alist-get :m context) 'entry))
            (alist-get :expr-ref context))))))))

(defun maf--negate-follow-selection ()
  "Put point on the entry maf's selection target would pick, if elsewhere.
`:scope entry' resolves the target entry from point, but an active calc
selection outranks point everywhere else in maf; moving point onto the
selected entry first keeps negate in line with the rest."
  (maf--with-calc-buffer
    (when (maf--sel-any-p)
      (let ((m (maf--sel-effective-m)))
        (when (and m (/= m (calc-locate-cursor-element (point))))
          (calc-cursor-stack-index m))))))

(defvar maf--negate-path nil
  "Path to the sub-formula `maf--negate-run' negates, bound per call.
Set by `mafcmd-negate' from point before the worker resolves its own
context; nil means the whole entry.")

(maf-defcmd maf--negate-run (expr _arg commit)
  "Negate the sub-formula at `maf--negate-path' inside EXPR.
The worker behind `mafcmd-negate' — see there. Takes the whole entry
\(`:scope entry'), since the sign an operand gives up may be paid for by
the node above it, which no sub-formula target could reach."
  :arity unary
  :prefix "bneg"
  :map -1
  :scope entry
  (commit (maf--negate-at expr maf--negate-path)))

(defun mafcmd-negate ()
  "Flip the sign of the target, keeping the entry worth what it was.

  2 - 3| x  =>  2 + -3 x

The minus goes to the operator in front of the target if there is one,
and stays inside the target's own slot if there is not. Nothing wider
than the target's parent is ever rewritten. Point picks the target as
usual: a sub-formula at point, an active selection, the whole entry at
its margin or at home.

  a + |x     =>  a - -x        (the operator in front flips)
  6| x + 12  =>  -(-6 x) + 12  (leading term: no operator to flip)
  |a x       =>  -a*-x         (the other factor takes the sign)
  |x = a     =>  -x = -a       (a relation negates both sides)
  |x < a     =>  -x > -a       (direction reverses with the sides)

At the whole entry the same rule reads as pulling a minus sign out to
the front — an entry is a slot with no operator in front of it.

  2 - x     =>  -(x - 2)
  a + b     =>  -(-a - b)

Nothing simplifies: the result is built structurally, so the doubled
signs stay visible rather than cancelling, and everything off the path
to the target keeps the form it had. Where the parent has no operator
to flip, the minus stays in the target's own slot as a doubled sign —
the same in-slot answer the whole entry gets, whatever shape fills the
slot. This is the balanced negation; `mafcmd-neg' is the plain one,
which does change the value.

  x           =>  --x           (in slot: nothing in front to flip)
  a b         =>  --(a b)
  |x^2        =>  (-x)^2        (even power swallows the sign)
  |x^3        =>  -(-x)^3       (odd power passes it out front)
  sin(|x)     =>  -sin(-x)      (odd function)
  cos(|x)     =>  cos(-x)       (even function)
  |x^y        =>  (--x)^y       (symbolic power: the slot holds it)
  f(|x, y)    =>  f(--x, y)     (generic call: likewise)
  a + |x + b  =>  a - -x + b    (the rest of the entry is untouched)"
  (interactive)
  (maf--negate-follow-selection)
  (let ((maf--negate-path (maf--negate-target-path)))
    (call-interactively #'maf--negate-run)))

(maf-defcmd mafcmd-float (expr _arg commit)
  "Float the resolved expression's fractions, leaving integers exact.

  6 x + 8:3  =>  6 x + 2.66666666667

With the Hyperbolic flag, `mafcmd-float-all' floats pervasively,
integers included.

  6 x + 8:3  =>  6. x + 2.66666666667

With the Inverse flag, routes to `mafcmd-frac': floats back to
fractions.

An expression without fractions commits unchanged, so equation sides
already exact pass through quietly. Point picks the target as usual:
a sub-formula at point, each side of an equation, the top entry at
home."
  :arity unary
  :prefix "flt"
  :hyperbolic mafcmd-float-all
  :inverse mafcmd-frac
  (commit (maf--float-fracs expr)))

(maf-defcmd mafcmd-float-all (expr _arg commit)
  "Float every number in the resolved expression, integers included.

  6 x + 8:3  =>  6. x + 2.66666666667

The pervasive variant of `mafcmd-float', its Hyperbolic route. Point
picks the target as usual: a sub-formula at point, each side of an
equation, the top entry at home."
  :arity unary
  :prefix "flt"
  (commit (math-normalize (list 'calcFunc-pfloat expr))))

(maf-defcmd mafcmd-frac (expr _arg commit)
  "Convert the resolved expression's floats to fractions.

  0.75 x + 2  =>  3:4 x + 2

With the Inverse flag, routes to `mafcmd-float': fractions back to
floats.

  3:4 x + 2  =>  0.75 x + 2

Only floats change: exact numbers stay untouched, and an expression
with no floats commits unchanged, so equation sides that are already
exact pass through quietly. A numeric prefix argument gives the
tolerance, as in calc's pfrac: a positive integer N makes each
fraction correct to N significant figures, a float gives an absolute
tolerance, and no argument (or 0) converts exactly within the current
precision — the take-tolerance-from-stack form of a zero prefix is
not supported. Point picks the target as usual: a sub-formula at
point, each side of an equation, the top entry at home.

  3.14159            =>  314159:100000
  C-u 3 3.14159      =>  22:7      (3 significant figures)
  C-u 0.001 3.14159  =>  333:106   (within 0.001)
  6 x + 2            =>  6 x + 2   (no floats: unchanged)
  0.5 y + 0.25| x    =>  0.5 y + 1:4 x   (sub-formula at point)
  x = 0.75 y         =>  x = 3:4 y       (each side of an equation)"
  :arity unary
  :prefix "frac"
  :inverse mafcmd-float
  (commit (math-normalize
           (list 'calcFunc-pfrac expr
                 (prefix-numeric-value (or current-prefix-arg 0))))))

(maf-defcmd mafcmd-evaluate (expr _arg commit)
  "Evaluate the resolved expression numerically.

  sqrt(2)  =>  1.41421356237

Symbolic mode is off for the evaluation, so anything with no exact
value becomes a float — roots, pi and e, trig — and stored variables
are substituted along the way. Exact rational arithmetic goes inexact
too: fractions float and a division by a number becomes its floated
quotient, so 1:3 gives 0.333333333333 and x / 3 gives
0.333333333333 x. Whatever stays exact stays exact: 2 + 3 is 5, and
what has no numeric value at all (x^2, 1 / (x + 1)) commits unchanged.

With the Inverse flag, routes to `mafcmd-identify': the float back to
a closed form.

  I on 1.41421356237  =>  sqrt(2)

Point picks the target as usual: a sub-formula at point, each side of
an equation, the top entry at home.

  x = 2 sqrt(2)  =>  x = 2.82842712475
  2 + sin(30)|   =>  2 + 0.5"
  :arity unary
  :prefix "eval"
  :inverse mafcmd-identify
  ;; Float the leftover rationals after the evaluation, not before: the
  ;; evaluation computes sqrt(2) / 2 to full precision, where halving a
  ;; floated sqrt(2) would round twice.
  (commit (maf--float-rationals
           (let ((calc-symbolic-mode nil)) (math-evaluate-expr expr)))))

(maf-defcmd mafcmd-identify (expr _arg commit)
  "Identify the resolved expression as a simple closed form.

  1.41421356237  =>  sqrt(2)

The Inverse route of `mafcmd-evaluate', undoing it where the value is
recognizable. The expression is evaluated to a number first, then
matched against the candidates `maf--identify-expr' knows — integers,
small fractions, rational multiples of a square root, cube and fourth
roots, rational multiples of pi and e, and logarithms of integers —
and the match commits in exact symbolic form.

  0.333333333333   =>  1:3
  2.44948974278    =>  sqrt(6)
  4.71238898038    =>  3:2 pi
  1.60943791243    =>  ln(5)

An expression with no numeric value commits unchanged, so the x in
x = 0.333333333333 passes through quietly while the other side
identifies. A number that matches no candidate signals instead,
committing nothing. Point picks the target as usual: a sub-formula at
point, each side of an equation, the top entry at home.

  x = 0.333333333333  =>  x = 1:3"
  :arity unary
  :prefix "idfy"
  (let ((val (let ((calc-symbolic-mode nil)) (math-evaluate-expr expr))))
    (commit (cond ((not (Math-realp val)) expr)
                  ((maf--identify-expr val))
                  (t (user-error "Cannot identify %s as a simple expression"
                                 (math-format-value val)))))))

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

  x on a| + 2  =>  x a + 2

At home with no selection active, the variable is pushed as a new
stack entry instead. Any other target is multiplied by it, variable
on the left: the selection, the sub-formula at point, each side of an
equation, the whole entry from its margin. Any letter is a valid
variable; anything else aborts."
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

(maf-defcmd mafcmd-toggle-op (expr _arg commit)
  "Toggle the top operator of the resolved expression to its counterpart.

  a + b  =>  a - b

Pairs come from `maf-toggle-op-pairs', each toggling both ways. The
swap is structural: operands stay in place and nothing simplifies, so
a relation flips its operator with both sides untouched — unlike
`mafcmd-commute', which moves the sides. With no toggle for the
operator — an atom, an unpaired operator, a log(x) with no explicit
base — the expression commits unchanged. Point picks the target as
usual: a sub-formula at point, the whole relation on a relation entry
(put point inside a side to toggle there), the top entry at home.

  a * b      =>  a / b
  ln(x)      =>  exp(x)
  log(a, b)  =>  a^b
  sin(x)     =>  arcsin(x)
  x = y      =>  x != y
  x < y      =>  x > y    (sides stay put: never y > x)
  x          =>  x        (no pair: unchanged)"
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

(defvar maf--simplify-restore 'alg
  "Simplify mode `maf-toggle-simplify' restores when toggling back on.
Captured from `calc-simplify-mode' as simplification is toggled off;
algebraic — calc's default — until the first toggle.")

(defun maf-toggle-simplify ()
  "Toggle automatic simplification off and back on.

Off, results commit structurally: nothing evaluates, collects, or
reorders, so 2 + 3 stays 2 + 3. Toggling back on restores the
simplify mode that was in effect when simplification was turned off —
algebraic, calc's default, unless another mode was active. Point
stays put. The echo area reports each switch; the mode line shows
calc's usual simplify-mode indicator."
  (interactive)
  (maf--with-calc-buffer
    (maf--preserve-point
      (calc-wrapper
       (if (eq calc-simplify-mode 'none)
           (progn
             (calc-change-mode 'calc-simplify-mode maf--simplify-restore)
             ;; Each capture is consumed by its restore, so entering
             ;; none by hand later toggles back to the default instead
             ;; of resurrecting a stale capture.
             (setq maf--simplify-restore 'alg)
             (message "Simplification restored: %s"
                      (alist-get calc-simplify-mode
                                 '((nil . "basic only")
                                   (alg . "algebraic")
                                   (num . "numeric arguments only")
                                   (binary . "binary")
                                   (ext . "extended algebraic")
                                   (units . "units"))
                                 "algebraic")))
         (setq maf--simplify-restore calc-simplify-mode)
         (calc-change-mode 'calc-simplify-mode 'none)
         (message "Simplification is disabled"))))))

(defun maf-toggle-big-language ()
  "Toggle Calc's \"Big\" display language on and off.

Big language renders the stack in multi-line 2D notation — fractions
stacked over a bar, exponents raised, radicals under a drawn sign;
toggling off restores the normal one-line notation. Only the display
changes, never the stack values. Point stays put, and the echo area
reports the switch."
  (interactive)
  (maf--with-calc-buffer
    (maf--preserve-point
      (if (eq calc-language 'big)
          (calc-normal-language)
        (calc-big-language)))))


;;; Session

(defun maf--reset-calc (arg)
  "Run `calc-reset' with ARG, leaving `maf-mode' as it found it.
`calc-reset' re-runs `calc-mode', and starting a major mode kills
every buffer-local variable — `maf-mode' among them, which takes maf's
whole keymap out of the buffer with it, C-M-k included. A
`calc-mode-hook' entry turns the mode back on for anyone who has one;
putting it back here means a reset never depends on that.

ARG is `calc-reset''s, and picks both axes at once: nil clears the
stack and restores the mode settings saved in `calc-settings-file', 0
clears the stack and restores calc's factory defaults, a positive
number keeps the stack with the saved settings, a negative one keeps
the stack with the defaults.

A settings file that signals part way through — a stray paren in a
hand-edited one — is survivable. `calc-reset' empties every
buffer-local calc variable before refilling them from the file, and
only once the refill is through does it run `calc-mode' to rebuild
them. An abort in between leaves the buffer with no display precision,
no line breaking, no stack top: not a calc buffer that can render its
own stack, let alone take the next command. Restoring the factory
defaults and re-running `calc-mode' there gives the session something
coherent to carry on in, and the stack rides it out — `calc-reset'
shields that behind a let, so the abort never reached it. A bad
settings file costs the settings, not the session. On the ordinary
path `calc-reset' has already run `calc-mode', so the guard is a
no-op."
  (let ((was (and (bound-and-true-p maf-mode) t)))
    (unwind-protect
        (calc-reset arg)
      (unless calc-stack-top
        (calc-mode-var-list-restore-default-values)
        (calc-mode)
        (calc-refresh))
      (when (and (fboundp 'maf-mode)
                 (not (eq (and (bound-and-true-p maf-mode) t) was)))
        (maf-mode (if was 1 -1)))
      ;; The modules register their state through `maf-mode', which the
      ;; re-run of `calc-mode' just killed and put back; re-applying the
      ;; list keeps an enabled module enabled across a reset.
      (when (fboundp 'maf-modules-apply)
        (maf-modules-apply)))))

(defun maf--reset-clear-trail ()
  "Empty calc's trail buffer, if one exists.
Erases the text rather than killing the buffer, so a window showing
the trail keeps showing it — the \"Emacs Calculator Trail\" banner is
a header line, not buffer text, and survives. Calc has no command for
this: \\`t k' kills one line and the trail otherwise grows for the
life of the session.

The overlay arrow marking `calc-trail-pointer' goes too. Calc only
drops it from `calc-trail-here', so left alone it would sit parked on
the first line of an empty trail; it is cleared in the calc buffer
only when it really points into the trail, since there the variable
may be the global one that a debugger is also using."
  (when-let ((buf (get-buffer "*Calc Trail*")))
    (with-current-buffer buf
      (let ((inhibit-read-only t))
        (erase-buffer))
      (setq overlay-arrow-position nil))
    (maf--with-calc-buffer
      (when (and (markerp overlay-arrow-position)
                 (eq (marker-buffer overlay-arrow-position) buf))
        (setq overlay-arrow-position nil)))))

(defun maf--reset-load-settings ()
  "Re-read `calc-settings-file' whole, if it names a readable file.
`calc-reset' already restores the mode settings from that file, but
only the block calc maintains between its own two marker comments.
Everything else the file holds — stored variables (\\`s p'), permanent
keyboard macros (\\`Z K'), user-defined units and functions — it never
looks at. Loading the file picks those up as well, so edits made to it
since the session started take effect without restarting Emacs.

Returns non-nil if the file was loaded."
  (let ((file (and calc-settings-file
                   (substitute-in-file-name calc-settings-file))))
    (and file (file-readable-p file) (load file t t))))

(defun maf-reset (&optional defaults)
  "Reset calc to a clean slate: empty stack, empty history, fresh settings.

Clears the stack, calc's undo and redo lists, the trail, and the maf
stack timeline, restores the mode settings saved in
`calc-settings-file', then re-reads the rest of that file (see
`maf--reset-load-settings'). What survives is what lives outside the
calc buffer: stored variables, the formula library, the kill ring.

With a prefix argument DEFAULTS, restore calc's factory default modes
instead of the saved ones — and then leave the settings file alone,
since loading it would immediately put the saved modes back and make
the prefix do nothing.

Nothing here is undoable: the undo list is one of the things cleared."
  (interactive "P")
  (maf--with-calc-buffer
    (maf--reset-calc (if defaults 0 nil))
    (maf--reset-clear-trail)
    ;; The timeline is a module and may not be loaded; it is also what
    ;; the trail used to be for, so a reset that left it standing would
    ;; leave the whole session recoverable from it.
    (when (fboundp 'maf-timeline-clear)
      (maf-timeline-clear))
    (message (if (and (not defaults) (maf--reset-load-settings))
                 "Calc reset; settings reloaded"
               "Calc reset"))))

(defun maf-reset-settings (&optional defaults)
  "Reset calc's modes and display settings, keeping the stack.

The other half of `maf-reset': restores the mode settings saved in
`calc-settings-file' and re-reads the rest of that file, but leaves
the stack, its selections, and the timeline exactly as they are. The
command for when a mode got toggled by accident and the session is
worth keeping.

With a prefix argument DEFAULTS, restore calc's factory default modes
instead of the saved ones, and leave the settings file unread — as in
`maf-reset'.

Undo and redo survive as well. `calc-reset' clears both whatever its
argument, which makes sense when it also clears the stack; with the
stack kept, the undo list still describes it exactly, so this command
puts the two lists back afterward. Point stays put."
  (interactive "P")
  (maf--with-calc-buffer
    (let ((undo calc-undo-list)
          (redo calc-redo-list))
      (maf--preserve-point
        (maf--reset-calc (if defaults -1 1))
        (setq calc-undo-list undo
              calc-redo-list redo)
        (unless defaults (maf--reset-load-settings))))
    (message (if defaults "Calc settings reset to defaults" "Calc settings reset"))))

(defun maf-beginning-of-entry ()
  "Move point to the beginning of the stack entry on the current line.

  2:  6 x + 12|  =>  2:  |6 x + 12

Point lands on the formula, right after the line-number prefix; on
the home line or a line without one, right after the leading
indentation."
  (interactive)
  (beginning-of-line)
  (if (looking-at " *[0-9]+: +")
      (goto-char (match-end 0))
    (skip-chars-forward " ")))

(defun maf--home-drop-mark (pos)
  "Drop the mark at POS that `maf-go-home' just returned to.
The mark the trip out pushed is spent once point is back on it, so it
comes off rather than staying where point already is. The one it
displaced is restored from the ring (`push-mark' put it there), leaving
the ring as deep as it was before the round trip — unlike `pop-mark',
which rotates the spent mark to the ring's tail instead. A no-op when
the mark has moved on since, POS then being none of its business."
  (when (and (mark t) (= (mark t) pos))
    (if mark-ring
        (let ((prev (car mark-ring)))
          (set-marker (mark-marker) (marker-position prev) (current-buffer))
          (move-marker prev nil)
          (setq mark-ring (cdr mark-ring)))
      (set-marker (mark-marker) nil))))

(defun maf--home-mark-position ()
  "Return the mark `maf-go-home' should bounce back to, or nil.
Nil when the buffer has no mark, and when the mark is itself at home:
the trip out never marks home, so a mark that sits there is either the
user's own or a leftover from a stack rewrite that consumed the entry
it tracked — either way there is nothing to go back to."
  (let ((mark (mark t)))
    (and mark
         (<= mark (point-max))
         (save-excursion (goto-char mark) (not (maf--at-home-p)))
         mark)))

(defun maf-go-home ()
  "Move point home, to the . line past the last stack entry.

  1:  6 x| + 12  =>  1:  6 x + 12
      .              |  .

Point lands on the . itself, where calc parks it after every command,
so the next key resolves at home rather than on an entry.

The trip out marks the place point left (`maf--mark-before-home', as
every maf command that homes point does), so C-u C-SPC returns to it.

Pressed at home the key makes the return trip itself: point goes back
to that mark, and the mark is dropped — the ring is left as it was
before the round trip (`maf--home-drop-mark'), older marks and all, so
C-u C-SPC still walks the ones the trip found there. The trip itself
always returns to where it last left, never further back. One key
covers both legs of it: out
to home for a command that wants the whole entry, back to the
sub-formula for one that wants the term. The stack may be rewritten in
between; a mark is a marker and rides the rewrite.

The mark it returns to is whichever one is current, so a homing push —
a dup, an algebraic entry — is bounced back from just as this command's
own trip out is. Home itself is never marked, on the way out or back:
it is one keystroke away, and the ring is for places that are not. That
also makes a mark sitting at home meaningless here, so a press finding
one (or finding no mark at all) just tidies point onto the dot. The
marking is silent throughout: the motion is common enough that a \"Mark
set\" on every press would be noise.

With a region up the marks are left alone in both directions, as in
`beginning-of-buffer' — the mark is the selection's anchor, and moving
or dropping it would lose the region, which is a target here
\(`maf-copy' takes it, and resolve reads it). The test is
`use-region-p', the same one resolve uses, so an empty active mark —
which `calc-refresh' leaves behind on every redraw — counts as no
region and does not block the trip.

Calc has no plain command for this: `calc-realign' goes to a stack
element only when given a numeric prefix argument (0 being home), and
with none it just undoes horizontal scrolling."
  (interactive)
  (let* ((from (point))
         (home (maf--at-home-p))
         (back (and home
                    (not (use-region-p))
                    (maf--home-mark-position))))
    (cond
     (back
      (goto-char back)
      (maf--home-drop-mark back))
     (t
      (calc-cursor-stack-index 0)
      ;; The dot sits past the line-number margin when numbering is on,
      ;; at the line's start when it is off.
      (skip-chars-forward " ")
      ;; A press that started at home moved point at most from the tail
      ;; of the line onto the dot: no journey, nothing to mark.
      (unless (or home (use-region-p))
        (maf--mark-before-home from))))))

(defun maf--swap-target-with-top ()
  "Swap the resolved sub-formula at point with the level-1 entry.
Resolve picks the target: an explicit calc selection, else the
sub-formula under point. The argument replaces that slot, and the
displaced sub-formula becomes the new level-1 entry."
  (let (context landed)
    (condition-case err
        (progn
          (calc-wrapper
           (setq context
                 (maf--resolve-context
                  '((:arity . binary) (:prefix . "swap") (:map . -1))))
           (unless (memq (alist-get :target context) '(selection subexpr))
             (user-error "Swap needs a selection or a sub-formula at point"))
           (let ((expr (alist-get :expr context))
                 (arg (alist-get :arg context)))
             ;; Commit ARG into the resolved slot, consuming the old
             ;; level-1 entry. Then put the displaced slot value on top.
             (setq landed (maf--commit arg context))
             (calc-push-list (list expr))
             ;; Commit reports the target's level after consuming level 1.
             ;; Pushing EXPR restores its original level.
             (setcdr (assq :m landed) (1+ (alist-get :m landed)))))
          (maf--undo-amalgamate-digit-entry)
          ;; Deliberately not the glyph anchor other commands use: swap
          ;; puts a foreign value in the slot rather than rewriting the
          ;; node in place, so the old node's glyph index means nothing
          ;; here. Point goes to the start of what arrived.
          (or (maf--point-restore-start landed)
              (maf--point-restore (alist-get :point context)))
          (maf--undo-record-cmd-point (alist-get :point context)))
      (error
       (when context
         (maf--point-restore (alist-get :point context)))
       (signal (car err) (cdr err))))))

(defun maf-swap-up (n)
  "Swap the stack entry at point with the one above it on screen.

  2:  a          2:  b
  1:  b|    =>   1:  a|

Point picks the target as usual: the sub-formula under point swaps
with the level-1 entry, and an active selection is taken instead of
it, however far apart the two sit. The value that arrives stays
selected only when a selection asked for it.

  3:  |20 x + 10     3:  |7 x + 10
  2:  8         =>   2:  8
  1:  7              1:  20

The line swap above is what point in the margin or at end of line
asks for: levels M and M+1 exchange places, the entry at point moving
up the screen while its upper neighbor lands on the line at point. At
home the top two entries swap. Point inside the top entry swaps lines
too — a sub-formula there has nothing below it to trade with.

Point stays on the same line and column; when the arriving entry is
shorter it clamps to that line's end, and at end of line it stays at
end of line. A sub-formula swap instead follows the value: point lands
on the first character of what arrived, in the entry it arrived in, so
the swapped-in sub-formula is what the next command sees.
With the entry at point already the highest, or with fewer than two
entries, there is nothing to swap and the command does nothing.

A prefix argument N bypasses the contextual swap and rolls the top N
entries by one, as calc's own roll does.

  C-u 3  3:  a       3:  c
         2:  b   =>  2:  a
         1:  c       1:  b"
  (interactive "P")
  (maf--with-calc-buffer
    (cond
     (n
      (let ((snapshot (maf--point-snapshot)))
        (maf--preserve-point (calc-roll-down n))
        ;; A single undo reverts point along with the stack.
        (maf--undo-record-cmd-point snapshot)))
     ;; These mirror resolve's own priority order, so the target it
     ;; hands back matches the one dispatched on here. Deliberately not
     ;; gated on `use-region-p': `calc-refresh' re-activates the mark on
     ;; every redraw once the buffer has one (it ends with `set-mark'),
     ;; so a region can be live without the user asking for anything.
     ;; A real region still resolves as such and is refused below.
     ((maf--sel-any-p)
      (maf--swap-target-with-top))
     ((maf--at-home-p)
      (maf--swap-adjacent-entries))
     ;; A sub-formula in the top entry has nothing below it to trade
     ;; with — its own entry would be the argument — so point inside
     ;; level 1 keeps the neighboring-entry swap.
     ((and (maf--at-subexpr-p)
           (> (calc-locate-cursor-element (point)) 1))
      (maf--swap-target-with-top))
     (t
      (maf--swap-adjacent-entries)))))

(defun maf--swap-adjacent-entries ()
  "Swap the entry at point with the one above it on screen.
Levels M and M+1 exchange places, point keeping its line and column.
Does nothing when the entry at point is already the highest."
  (maf--with-calc-buffer
    (let ((m (max (calc-locate-cursor-element (point)) 1)))
      (when (< m (calc-stack-size))
        ;; Point is a screen position here, not a formula position:
        ;; restore it by line and column, not buffer offset — the two
        ;; lines change length, so `maf--preserve-point's pos-first
        ;; restore would land unpredictably.
        (let ((snapshot (maf--point-snapshot))
              (home (maf--at-home-p))
              (line (line-number-at-pos))
              (col  (current-column))
              (eol  (eolp)))
          (calc-wrapper
           ;; Both lists run deepest-first, so reversing the pair of
           ;; values swaps the two levels. Disabled selections travel
           ;; with their whole entries on this path.
           (let ((vals (calc-top-list 2 m 'full))
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
            (if eol (end-of-line) (move-to-column col)))
          ;; A single undo reverts point along with the stack.
          (maf--undo-record-cmd-point snapshot))))))

(defun maf-roll-to-top ()
  "Move the stack entry at point to the top of the stack.

  3:  a|         3:  b
  2:  b     =>   2:  c
  1:  c          1:  a|

The entry at point becomes level 1, on the bottom line; the entries
that were under it on screen each move up a line, keeping their order,
and the entries above it stay where they are. Only the arrangement
changes — nothing is evaluated, and no entry is added or dropped.

Point travels with the entry, keeping its place within it: on a
sub-formula it stays on that sub-formula, at end of line it stays at
end of line, in the line-number margin it stays in the margin. The
position point left is pushed on the mark ring, so \\[universal-argument] \\[set-mark-command] returns to
it; the region is not left active. Selections travel with their
entries. With the entry at point already on top, at home, or on an
empty stack, there is nothing to move and the command does nothing —
the mark ring included."
  (interactive)
  (maf--with-calc-buffer
    (let ((m (calc-locate-cursor-element (point))))
      ;; m of 1 (the top entry) or 0 (home, empty stack) has nothing to
      ;; move; leaving early also spares point calc-wrapper's homing.
      (when (> m 1)
        ;; The entry can travel a long way, so leave a mark behind to
        ;; jump back to, as `beginning-of-buffer' and friends do. Only
        ;; on a roll that actually happens — the early exits above must
        ;; not disturb the mark ring. `calc-refresh' restores the mark
        ;; with `set-mark', which activates it, so the region is killed
        ;; off again once the roll is done: the mark is a place to
        ;; return to, not a selection the user asked for.
        (push-mark nil t)
        (let ((snapshot (maf--point-snapshot))
              ;; The screen place the mark stands for. The roll reprints
              ;; the whole buffer, which collapses the mark marker to
              ;; column 0 — the line-number margin, where the contextual
              ;; commands read a different target than they would inside
              ;; the formula. Restore it by line and column afterwards,
              ;; as `maf--swap-adjacent-entries' does for point.
              (mline (line-number-at-pos))
              (mcol  (current-column))
              ;; Point as an offset into the entry's own text. The roll
              ;; reprints the same formula and the stack keeps its size,
              ;; so the line-number prefixes keep their width too: the
              ;; offset lands on the same character once the entry is at
              ;; level 1, multi-line renderings included.
              (offset (- (point) (save-excursion
                                   (calc-cursor-stack-index m)
                                   (point)))))
          (calc-wrapper
           ;; Both lists run deepest-first, so moving the entry at point
           ;; (their car) to the end puts it on level 1 while the rest
           ;; keep their order. The selections travel along — calc's own
           ;; roll keeps them only while `calc-use-selections' is nil.
           ;; The values are read with `full': a plain `calc-top-list'
           ;; hands back the *selection* for a selected entry, which
           ;; would put the selected part on the stack in place of the
           ;; whole formula.
           (let ((vals (calc-top-list m 1 'full))
                 (sels (calc-top-list m 1 'sel)))
             (calc-pop-push-list m
                                 (append (cdr vals) (list (car vals)))
                                 1
                                 (append (cdr sels) (list (car sels))))))
          ;; Calc parks point at home after the rewrite; follow the
          ;; entry down to level 1 instead.
          (calc-cursor-stack-index 1)
          (goto-char (min (+ (point) offset) (point-max)))
          (save-excursion
            (goto-char (point-min))
            (forward-line (1- mline))
            ;; move-to-column stops at end of line, clamping for free.
            (move-to-column mcol)
            (set-marker (mark-marker) (point)))
          (deactivate-mark)
          ;; A single undo reverts point along with the stack.
          (maf--undo-record-cmd-point snapshot))))))

(defun maf-roll-to-bottom ()
  "Bury the stack entry at point at the bottom of the stack.

  3:  a          3:  b
  2:  b|    =>   2:  c
  1:  c          1:  a

The entry at point sinks to the deepest level — the top line of the
stack window — and everything that was above it drops one level, so the
entry that was one line up lands on the line at point. The entries below
point are untouched. At home the top entry is buried; with point already
on the deepest entry, or with fewer than two entries, there is nothing
to bury and the command does nothing.

Point keeps its level rather than following the entry it moved: it stays
at level M, on whatever entry arrives there, at the same column (clamped
to the new line's end, with end-of-line and line-prefix positions
staying at their end). Selections travel with their entries."
  (interactive)
  (maf--with-calc-buffer
    (let ((n (calc-stack-size))
          (m (max 1 (calc-locate-cursor-element (point)))))
      ;; m = n is the entry already at the bottom: a genuine no-op, so
      ;; skip the rewrite rather than record an undo group for it.
      (when (and (> n 1) (< m n))
        (let ((snapshot (maf--point-snapshot))
              (home (maf--at-home-p)))
          (calc-wrapper
           ;; Rotate the window of levels M..N by one. Both lists run
           ;; deepest-first — (N N-1 ... M+1 M) — so moving the last
           ;; element to the front sends level M to the bottom and slides
           ;; the rest down one. Passing `sels' explicitly keeps the
           ;; selections with their entries and, more importantly, keeps
           ;; `calc-pop-push-list' off its `calc-replace-selections'
           ;; path, which would splice each rolled value into the
           ;; selected sub-formula of the entry landing on it — the bug
           ;; in calc's own `calc-roll-up'/`calc-roll-down' whenever a
           ;; selection exists and `calc-use-selections' is on.
           ;;
           ;; `full' is required on the value list: with sel-mode nil,
           ;; `calc-get-stack-element' hands back the *selection* of a
           ;; selected entry, not the entry, so a plain `calc-top-list'
           ;; would bury the sub-formula and drop the rest of its entry.
           (let* ((count (1+ (- n m)))
                  (vals (calc-top-list count m 'full))
                  (sels (calc-top-list count m 'sel))
                  (roll (lambda (l) (cons (car (last l)) (butlast l)))))
             (calc-pop-push-list count (funcall roll vals)
                                 m (funcall roll sels))))
          ;; Calc parks point at home after the rewrite; that is already
          ;; right for a home invocation. Otherwise return to level M by
          ;; index, not by screen line: the rewrite relaid out every line
          ;; from M up, and the arriving entry need not be the same
          ;; height as the one that left.
          (unless home
            (calc-cursor-stack-index m)
            (pcase (alist-get :affinity snapshot)
              ('eol (end-of-line))
              ('bol (maf--point-restore-margin (alist-get :col snapshot)))
              ;; move-to-column stops at end of line, clamping for free.
              (_ (move-to-column (alist-get :col snapshot)))))
          ;; A single undo reverts point along with the stack.
          (maf--undo-record-cmd-point snapshot))))))

(defun maf--carry-entry (count up)
  "Move the entry at point COUNT levels, UP the screen when UP, else down.
Point travels with the entry. The travel wraps around the stack: an
entry carried past the deepest level reappears at level 1, and one
carried past level 1 reappears at the deepest. With point at home or on
an empty stack — and on a stack of one entry, or with a COUNT that laps
it exactly — nothing happens: no rewrite, no undo group."
  (maf--with-calc-buffer
    (let* ((n (calc-stack-size))
           (m (calc-locate-cursor-element (point)))
           ;; m of 0 is home or an empty stack: no entry at point.
           ;; Otherwise the levels are a ring of size N and the entry
           ;; travels COUNT places round it, so any count is in range.
           (target (and (> m 0)
                        (1+ (mod (+ (1- m) (if up count (- count))) n))))
           ;; A wrapped travel is the same rewrite as the unwrapped one
           ;; going the other way: carrying up from level N to level 1
           ;; lifts every other entry one level, exactly as carrying the
           ;; same entry down from N to 1 would. So the direction that
           ;; matters below is the target's side of M, not UP.
           (up (and target (> target m)))
           (k (if target (abs (- target m)) 0)))
      (when (> k 0)
        (let ((snapshot (maf--point-snapshot))
              ;; Point as an offset into the entry's own text. The entry
              ;; travels unchanged and the stack keeps its size, so the
              ;; line-number prefixes keep their width too: the offset
              ;; lands on the same character at the level the entry
              ;; reaches, multi-line renderings included. This is what
              ;; makes point ride the entry — the line-and-column
              ;; restore `maf--swap-adjacent-entries' uses instead is
              ;; how point stays put while an entry moves under it.
              (offset (- (point) (save-excursion
                                   (calc-cursor-stack-index m)
                                   (point)))))
          (calc-wrapper
           ;; Rotate the window of levels the entry travels through.
           ;; Both lists run deepest-first, so carrying up (level M to
           ;; M+K) moves the window's last element to its front, and
           ;; carrying down (M to M-K) its first element to the end;
           ;; either way the entries passed each shift one level the
           ;; other way, keeping their order.
           ;;
           ;; Passing `sels' explicitly keeps the selections with their
           ;; entries and keeps `calc-pop-push-list' off its
           ;; `calc-replace-selections' path — see `maf-roll-to-bottom'
           ;; for what that path does to a stack carrying a selection.
           ;; `full' is required on the value list: with sel-mode nil,
           ;; `calc-get-stack-element' hands back the *selection* of a
           ;; selected entry rather than the entry itself.
           (let* ((base (if up m (- m k)))
                  (size (1+ k))
                  (vals (calc-top-list size base 'full))
                  (sels (calc-top-list size base 'sel))
                  (roll (if up
                            (lambda (l) (cons (car (last l)) (butlast l)))
                          (lambda (l) (append (cdr l) (list (car l)))))))
             (calc-pop-push-list size (funcall roll vals)
                                 base (funcall roll sels))))
          ;; Calc parks point at home after the rewrite; follow the
          ;; entry to the level it landed on instead.
          (calc-cursor-stack-index target)
          (goto-char (min (+ (point) offset) (point-max)))
          ;; A single undo reverts point along with the stack.
          (maf--undo-record-cmd-point snapshot))))))

(defun maf-carry-up (n)
  "Carry the stack entry at point one line up the screen, point riding along.

  3:  a          3:  a
  2:  b     =>   2:  c|
  1:  c|         1:  b

The entry at point and the one above it exchange levels, and point
travels with the entry it started on, keeping its place inside it: on a
sub-formula it stays on that sub-formula, at end of line it stays at
end of line, in the line-number margin it stays in the margin. Nothing
is evaluated and no entry is added or dropped; selections travel with
their entries.

The whole entry moves whatever point sits on — a sub-formula under
point is carried along rather than traded away, which is what
`maf-swap-up' does with it.

The stack is a ring: an entry already the deepest is carried round to
level 1, every other entry rising a level to make room.

  3:  a|         3:  b
  2:  b     =>   2:  c
  1:  c          1:  a|

With point at home or on an empty stack there is no entry to carry, and
the command does nothing; on a stack of one entry there is nowhere to
carry it to.

A prefix argument N carries the entry N lines at once, wrapping as
often as it takes; a negative N carries it down instead, as
`maf-carry-down' does.

  C-u 3  4:  a       4:  d|
         3:  b   =>  3:  a
         2:  c       2:  b
         1:  d|      1:  c"
  (interactive "p")
  (maf--carry-entry (abs n) (>= n 0)))

(defun maf-carry-down (n)
  "Carry the stack entry at point one line down the screen, point riding along.

  3:  a          3:  a
  2:  b|    =>   2:  c
  1:  c          1:  b|

The mirror of `maf-carry-up': the entry at point and the one below it
exchange levels, point travelling with the entry it started on and
keeping its place inside it. The stack is a ring here too — an entry
already on top, at level 1, is carried round to the deepest level:

  3:  a          3:  c|
  2:  b     =>   2:  a
  1:  c|         1:  b

With point at home or on an empty stack there is no entry to carry, and
the command does nothing.

A prefix argument N carries the entry N lines at once, wrapping as
often as it takes; a negative N carries it up instead.

  C-u 3  4:  a|      4:  b
         3:  b   =>  3:  c
         2:  c       2:  d
         1:  d       1:  a|"
  (interactive "p")
  (maf--carry-entry (abs n) (< n 0)))

(maf-defcmd mafcmd-equal-to (expr arg commit)
  "Equate the entry at point with the top-of-stack argument.

  2:  x
  1:  y|    =>   1:  x = y|

Like any binary command, the entry at point is the subject and the top
of the stack is the argument: the equation is subject = argument, the
argument is consumed, and the result lands where the subject was. Point
on the top entry shifts the pair down — the top becomes the argument and
the entry below the subject — so on a two-entry stack either entry gives
the same equation; at home the top two join. With a deeper stack, the
entry at point equates with the top regardless of the entries between.

  3:  a|         2:  a = c
  2:  b     =>   1:  b
  1:  c

With the Inverse flag, `mafcmd-not-equal-to' builds != instead. With
keep-args the operands stay and the equation is pushed on top. Both
sides commit structurally intact — nothing simplifies or evaluates, so
equating 3 with 3 gives the equation 3 = 3, not 1. Signals an error
with fewer than two entries."
  :arity binary
  :prefix "eq"
  :scope entry
  :map -1
  :inverse mafcmd-not-equal-to
  (commit (list 'calcFunc-eq expr arg)))

(maf-defcmd mafcmd-not-equal-to (expr arg commit)
  "Build != between the entry at point and the top-of-stack argument.

The Inverse route of `mafcmd-equal-to' — identical in every way but the
relation it forms: subject != argument, structural, no simplification."
  :arity binary
  :prefix "neq"
  :scope entry
  :map -1
  (commit (list 'calcFunc-neq expr arg)))

(maf-defcmd mafcmd-remove-equal (expr _arg commit)
  "Drop the relation from the entry at point, keeping the side that matters.

  x = 5  =>  5

The side kept is the right one, except when the right side is a bare
variable and the left an object — there the object wins, so a solution
reads the same whichever way round it was written. Every relation
qualifies, not just equality, along with assignments and evalto. A
vector maps element-wise, so a list of equations gives the list of its
sides.

Nothing else changes: the surviving side commits structurally, exactly
as it stood inside the relation. An entry with no relation in it
commits unchanged, as does a vector element that has none. With
keep-args the entry stays and the side is pushed on top.

It acts on the whole entry — the relation at point, wherever point sits
on its line — or the top entry at home; removing a relation has no
sub-formula meaning, so point within the formula is not used to narrow
it.

  y = 2 x + 1     =>  2 x + 1
  5 = x           =>  5           (the bare variable loses)
  a < b           =>  b
  x := 5          =>  5
  [x = 1, y = 2]  =>  [1, 2]
  2 x + 1         =>  2 x + 1     (no relation: unchanged)"
  :arity unary
  :prefix "rmeq"
  :map -1
  :scope entry
  (commit (maf--remove-relation expr)))

(defun maf--del-land-above (m snapshot)
  "Put point on the entry now at level M — the one just above the deleted
entry — keeping SNAPSHOT's eol/bol affinity. After a whole entry at level
M is removed, the entry that was above it (old M+1) drops to level M; land
there. When M is past the new top — the deleted entry was the highest —
there is no entry above, so point rests at home."
  (if (> m (calc-stack-size))
      (goto-char (point-max))
    (calc-cursor-stack-index m)
    (pcase (alist-get :affinity snapshot)
      ('bol (beginning-of-line))
      (_    (end-of-line)))))

(defun maf-del ()
  "Delete the target at point: selection, sub-formula, entry, or top.

  a + b|  =>  a

Deletion patches the structure around the deleted part rather than
zeroing it: a factor or exponent falls out of its product or power, a
vector element leaves the vector, and deleting one side of a relation
leaves the other side standing. With point on an entry's margin the
whole entry is deleted; at home the top of the stack pops, as does an
entry whose whole formula is selected or deleted. Signals an error on
an empty stack.

  a b|         =>  a
  a^b|         =>  a
  [a, b|, c]   =>  [a, c]
  x = y|       =>  x
  2:  a + b|   =>  deletes the whole entry     (point on the margin)

When a whole entry goes, point lands on the entry that was just above it
(the next one up the stack), at the same end — eol stays eol, the
line-prefix stays there. Deleting the topmost entry leaves point at home.
A sub-formula deletion, which leaves the entry standing, keeps point in
place, as does the home pop."
  (interactive)
  (maf--with-calc-buffer
    (when (zerop (calc-stack-size))
      (user-error "Stack is empty"))
    (let ((snapshot (maf--point-snapshot))
          (home (maf--at-home-p))
          (m (max 1 (calc-locate-cursor-element (point))))
          (size0 (calc-stack-size)))
      (if home
          (calc-pop 1)
        (calc-del-selection))
      (cond
       ;; Home pop: calc already parked point at home.
       (home)
       ;; A whole entry was removed (the stack shrank): land on the entry
       ;; that was above it.
       ((< (calc-stack-size) size0)
        (maf--del-land-above m snapshot))
       ;; A sub-formula went but the entry remains: keep point on it. The
       ;; deletion may have shortened the line and clamped point to EOL.
       (t (maf--point-restore snapshot)))
      ;; Record the pre-command placement so a single undo reverts point
      ;; along with the stack.
      (maf--undo-record-cmd-point snapshot))))

(defun maf-kill ()
  "Kill the entry at point: off the stack and onto the kill ring.

  2:  a + b|  =>  entry gone   (kill ring gets a + b)

The whole entry is killed wherever point sits on its line — unlike
`maf-del', which resolves sub-formulas, killing is line-based. At
home the top of the stack is killed. The kill ring gets the entry's
formatted text, without the level-number prefix, ready for yanking
anywhere. Signals an error on an empty stack."
  (interactive)
  (maf--with-calc-buffer
    (when (zerop (calc-stack-size))
      (user-error "Stack is empty"))
    (let ((m (max 1 (calc-locate-cursor-element (point))))
          (snapshot (maf--point-snapshot)))
      (kill-new (math-format-value (calc-top m 'full)))
      (maf--preserve-point
        (calc-wrapper (calc-pop-stack 1 m)))
      ;; A single undo reverts point along with the stack.
      (maf--undo-record-cmd-point snapshot))))

;;; LaTeX composition

;; LaTeX composition forms for the logarithms, consulted by
;; `math-compose-expr' whenever calc formats in the latex language —
;; calc's own latex display mode (d L), and maf's latex output.
;;
;; Calc renders log(x, b) as the literal "log\left( x, 3 \right)" and,
;; worse, log10(x) as "\log{x}", which silently drops the base. Both
;; become \log with the base as a subscript.
;;
;; The composition is keyed on nil (the whole expression) rather than an
;; argument count, since the handler returns a composition, not a
;; formula. calccomp's dispatch is `math-compose-forms'; the property
;; name is not free-form.
(defun maf--latex-compose-log (expr)
  "Compose EXPR, a `calcFunc-log' call, as LaTeX.
Two arguments give \\log_{base}, one gives \\ln — calc normalizes
log(x) to ln(x), so the one-argument form only shows up unevaluated."
  (if (= (length expr) 3)
      (list 'horiz
            "\\log_{" (math-compose-expr (nth 2 expr) 0) "}"
            "\\left( " (math-compose-expr (nth 1 expr) 0) " \\right)")
    (list 'horiz
          "\\ln\\left( " (math-compose-expr (nth 1 expr) 0) " \\right)")))

(defun maf--latex-compose-log10 (expr)
  "Compose EXPR, a `calcFunc-log10' call, as LaTeX \\log_{10}."
  (list 'horiz
        "\\log_{10}\\left( " (math-compose-expr (nth 1 expr) 0) " \\right)"))

(with-eval-after-load 'calccomp
  (put 'calcFunc-log 'math-compose-forms
       '((latex (nil . maf--latex-compose-log))))
  (put 'calcFunc-log10 'math-compose-forms
       '((latex (nil . maf--latex-compose-log10)))))

;;; Copy

(defvar maf--copy-state nil
  "What the last `maf-copy' put on the kill ring, for its repeat toggle.
A plist:

  :text    the plain-language text that was copied
  :expr    the calc value behind it, or nil for region text that has
           not been parsed
  :format  `normal' or `latex' — which of the two is on the kill ring

Read only when `maf-copy' is the immediately preceding command, so a
stale entry is never picked up by a later copy.")

(defun maf--latex-string (expr)
  "Format EXPR as a single line of LaTeX.
Calc's latex language does the formatting, but only for the call: the
language variables it sets are restored afterwards, so the stack
display never changes language. `math-format-value' inhibits line
breaking, so the result is one line however wide."
  (maf--with-calc-buffer
    (let ((lang calc-language)
          (opt calc-language-option))
      (unwind-protect
          (progn (calc-set-language 'latex nil t)
                 (math-format-value expr))
        (calc-set-language lang opt t)))))

(defun maf--copy-squeeze (text)
  "Return TEXT with all whitespace removed, for comparing renderings."
  (replace-regexp-in-string "[[:space:]]+" "" (substring-no-properties text)))

(defun maf--copy-read (text)
  "Parse copied TEXT into a calc value.
A leading level prefix (\"2: \") is dropped, so a region that swept up
the whole display line still parses. Signals a `user-error' when the
text is not a complete formula — text taken off the display verbatim
need not be one.

Calc's reader is lenient about truncated input rather than rejecting
it: \"a + sqrt(\" reads as a zero-argument sqrt, \"[1, 2\" closes the
vector for you, \"((a\" drops the parens. None of those say what the
region says, so a parse counts only when formatting it back reproduces
the text, whitespace aside."
  ;; The prefix needs the whitespace calc puts after the colon to be
  ;; told from a fraction, which is written 1:2 with none.
  (let* ((clean (replace-regexp-in-string "\\`[0-9]+:[[:space:]]+" ""
                                          (string-trim text)))
         (val (math-read-expr clean)))
    (when (eq (car-safe val) 'error)
      (user-error "No LaTeX for this copy: %s" (nth 2 val)))
    (unless (string= (maf--copy-squeeze (math-format-value val))
                     (maf--copy-squeeze clean))
      (user-error "No LaTeX for this copy: not a complete formula"))
    val))

(defun maf--copy-fresh ()
  "Copy the region, the entry at point, or the top entry.
Returns the new `maf--copy-state'."
  (cond
   ;; Verbatim text, as M-w means everywhere else: the region may cover
   ;; several entries, half a token, or the level prefixes, and none of
   ;; that has to parse as a formula. Unlike calc's own M-w this does
   ;; not round the region out to whole entry lines.
   ((use-region-p)
    (copy-region-as-kill (region-beginning) (region-end) 'region)
    (list :text (car kill-ring) :expr nil :format 'normal))
   (t
    (when (zerop (calc-stack-size))
      (user-error "Stack is empty"))
    (let* ((m (max 1 (calc-locate-cursor-element (point))))
           (val (calc-top m 'full))
           (text (math-format-value val)))
      (kill-new text)
      (list :text text :expr val :format 'normal)))))

(defun maf--copy-toggle-format ()
  "Re-copy the last `maf-copy' source in the other format.
Replaces the head of the kill ring instead of pushing a second entry:
the two formats are one copy, not two."
  (let ((text (plist-get maf--copy-state :text)))
    (if (eq (plist-get maf--copy-state :format) 'latex)
        (progn
          (kill-new text t)
          (setq maf--copy-state (plist-put maf--copy-state :format 'normal)))
      ;; The value from an entry copy is exact; region text has to be
      ;; read back. Cache what it parsed to, so toggling back and forth
      ;; parses once.
      (let ((expr (or (plist-get maf--copy-state :expr)
                      (maf--copy-read text))))
        (kill-new (maf--latex-string expr) t)
        (setq maf--copy-state
              (plist-put (plist-put maf--copy-state :expr expr)
                         :format 'latex))))))

(defun maf-copy ()
  "Copy the region, the entry at point, or the top of the stack.

  region       =>  kill ring gets the selected text, verbatim
  2:  a + b|   =>  kill ring gets a + b
  home         =>  kill ring gets the top entry

Copying is line-based like `maf-kill': the whole entry goes wherever
point sits on its line, sub-formulas and calc selections included. An
entry is copied as calc formats it, without the level-number prefix,
so it reads back in — unlike the region, which is taken verbatim.

Pressed twice in a row the same copy is remade as LaTeX, replacing
what the first press put on the kill ring rather than adding a second
entry; a third press goes back to the plain form. Region text that is
not a formula has no LaTeX form, and says so, leaving the plain copy
in place.

  1:  sqrt(x)/3   M-w      =>  sqrt(x) / 3
                  M-w M-w  =>  \\frac{\\sqrt{x}}{3}

Signals an error on an empty stack when there is no region."
  (interactive)
  (maf--with-calc-buffer
    (if (and (eq last-command 'maf-copy) maf--copy-state)
        (maf--copy-toggle-format)
      (setq maf--copy-state (maf--copy-fresh)))
    (message "Copied%s: %s"
             (if (eq (plist-get maf--copy-state :format) 'latex) " as LaTeX" "")
             (string-trim (car kill-ring)))))

(defun maf-dup (&optional keep-point)
  "Duplicate the item at point, pushing a copy onto the stack.

  1:  a + b|   =>   2:  a + b
                    1:  a + b

The copy is pushed on top and the originals are untouched, so the
stack grows by one. Like calc's own duplicate the copy is verbatim:
nothing simplifies or evaluates, and keep-args changes nothing about
what lands on the stack — it only holds point (see below). Signals an
error on an empty stack.

Point picks the target as usual — a sub-formula at point, a calc
selection or an active region's run when either is present, the whole
entry from its margin, the top entry at home. A sub-formula is pushed
on its own, lifted out of the entry it came from; a relation is
duplicated whole from its margin, or by the side under point from
within it.

  1:  (a +| b) c   =>   2:  (a + b) c
                        1:  a + b        (sub-formula at point)
  1:  x = y|       =>   2:  x = y
                        1:  x = y        (whole relation, from the margin)

Point moves home to the copy, leaving a mark where it was so a single
`pop-to-mark-command' returns there. With a prefix argument (KEEP-POINT
non-nil) point stays put instead and no mark is left, so the next
command still targets what point was on — C-u RET, with `maf-dup-here'
as the named entry point.

  1:  (a +| b) c   C-u RET  =>   2:  (a +| b) c
                                 1:  b            (point stays on b)

Calc's keep-args prefix asks for the same hold: K RET duplicates and
keeps point, the modifier route to what C-u RET does. The flag reads as
it always does, as \"consume nothing\" — and a duplicate consumes
nothing on the stack to begin with, so what it spares here is point."
  (interactive "P")
  (maf--with-calc-buffer
    (when (zerop (calc-stack-size))
      (user-error "Stack is empty"))
    ;; The origin to mark before point homes, captured now, before
    ;; resolve probes calc state and may move point; the buffer is
    ;; unedited until the push, so the position stays valid. Unused when
    ;; point turns out to be held (keep-args is only known after
    ;; resolve), and nil when point is already home.
    (let* ((origin (unless (maf--at-home-p) (point)))
           ;; Unary resolution (no arg, so no below-top restriction) with
           ;; :map -1 so a relation stays whole in :expr rather than mapping
           ;; per side. We only read :expr and push it.
           (context (maf--resolve-context '((:arity . unary) (:map . -1))))
           (expr (alist-get :expr context))
           ;; K RET holds point just as C-u RET does. The flag is read
           ;; from resolve's snapshot: calc-wrapper's epilogue clears it
           ;; below, and `maf--fancy-prefix-keep-ret' is what got it here
           ;; through RET at all.
           (keep-point (or keep-point (alist-get :keep context))))
      ;; calc-wrapper's epilogue parks point home; keep-point puts it back.
      (if keep-point
          (maf--preserve-point (calc-wrapper (calc-push expr)))
        ;; Mark the origin before the push homes point, so it can be
        ;; popped back to (the marker rides the push's renumber).
        (progn
          (when origin (maf--mark-before-home origin))
          (calc-wrapper (calc-push expr))))
      ;; Record the resolve-time point so a single `maf-undo' reverts
      ;; point along with the pushed copy, back to where the command ran.
      (maf--undo-record-cmd-point (alist-get :point context)))))

(defun maf-dup-here ()
  "Duplicate the item at point like `maf-dup', but keep point in place.
The copy is still pushed on top; point stays where it was instead of
moving home to the copy. The named entry point for RET's prefix
argument, C-u RET."
  (interactive)
  (maf-dup t))

(defun maf-dup-below ()
  "Duplicate the item at point, placing the copy directly below it.

  3:  a + b       4:  a + b
  2:  c|      =>  3:  c
  1:  d           2:  c|
                  1:  d

Point picks the subject as usual — a sub-formula at point, a calc
selection or an active region's run when either is present, the whole
entry from its margin, the top entry at home. What sets this apart from
`maf-dup' is only where the copy goes: the slot directly below the entry
the subject came from, rather than the top of the stack. The copy is
verbatim: nothing simplifies or evaluates, and keep-args makes no
difference.

  2:  (a +| b) c   =>   3:  (a + b) c
  1:  z                 2:  a + b        (sub-formula at point)
                        1:  z

Point travels to the copy. A whole entry renders exactly like its
source, so point keeps its place within it and lands on the same
character one entry down; a sub-formula renders on its own, with no such
place to keep, so point lands at the start of the copy.

On the top entry there is nothing between point and the home line, so
the copy lands on top as `maf-dup' would. At home point stays home,
having never been on the entry that was copied. Signals an error on an
empty stack.

  1:  x = y|  =>  2:  x = y     (relations copy whole, not per side)
                  1:  x = y|"
  (interactive)
  (maf--with-calc-buffer
    (when (zerop (calc-stack-size))
      (user-error "Stack is empty"))
    ;; Point's own level, captured before the push renumbers everything.
    ;; Home (0) and the top entry both give 1, which needs no roll.
    (let* ((snapshot (maf--point-snapshot))
           (home (maf--at-home-p))
           (at (max 1 (calc-locate-cursor-element (point))))
           ;; Which screen line of the entry point is on, for a multi-line
           ;; rendering; a whole-entry copy is laid out identically.
           (row (unless home
                  (- (line-number-at-pos)
                     (save-excursion (calc-cursor-stack-index at)
                                     (line-number-at-pos)))))
           ;; Contextual resolution: whatever point names is the subject.
           ;; `:map -1' keeps a relation whole rather than copying it per
           ;; side. We only read :expr and push it.
           (context (maf--resolve-context '((:arity . unary) (:map . -1))))
           (expr (alist-get :expr context))
           ;; The copy goes below the entry the subject came from, which
           ;; is point's own entry except when a selection or a region
           ;; named another one (:m).
           (m (or (alist-get :m context) at))
           ;; Whether the copy renders exactly like what point was looking
           ;; at: it does when the subject is point's own entry whole —
           ;; from the margin, or as the sub-formula that spans it — and
           ;; not when a part was lifted out to stand on its own.
           (whole (and (= m at)
                       (equal expr (maf--strip-encasing (calc-top at 'full))))))
      ;; calc-wrapper's epilogue parks point home; restoring the snapshot
      ;; puts it back on the original, whose screen line the insertion
      ;; below did not disturb, and the step to the copy starts there.
      (maf--preserve-point
        (calc-wrapper (calc-push expr))
        (maf--roll-top-below m))
      ;; The copy sits at level M, the original having moved up to M+1.
      (cond
       ;; At home point was never on the entry that was copied, so it
       ;; has nowhere to travel from; calc left it home already.
       (home)
       ;; Step by row and column rather than a buffer offset: the push can
       ;; widen every line-number prefix (a stack crossing 9 entries), which
       ;; a raw offset would carry into the formula text.
       (whole
        (let ((col (current-column)))
          (calc-cursor-stack-index m)
          (forward-line row)
          (move-to-column col)))
       (t (maf--goto-entry-text m)))
      ;; Record the resolve-time point so a single `maf-undo' reverts
      ;; point along with the copy.
      (maf--undo-record-cmd-point snapshot))))

;;; Selections

(defun maf-clear-selections ()
  "Clear every active selection, leaving point where it is.

Selections on every entry go, not just the one under point. The stack
itself is untouched — nothing is pushed, popped, or rewritten, so
there is nothing to undo either. Point keeps its line and column
instead of parking on the home line, leaving the entry under the
cursor for the next command. With nothing selected this does nothing."
  (interactive)
  (maf--with-calc-buffer
    (maf--preserve-point
      (calc-clear-selections))))

(defun maf-dup-or-clear-selections (&optional keep-point)
  "Clear active selections, or duplicate the item at point.

With any selection active the selections are cleared and the stack is
left alone (`maf-clear-selections'); the key that narrows down to a
sub-formula is also the one that steps back out. With none active the
item at point is duplicated onto the top of the stack (`maf-dup').

A prefix argument (KEEP-POINT non-nil) passes through to the duplicate,
which then keeps point instead of homing — RET's prefix must reach
`maf-dup' through this dispatcher, since RET is bound here. The clear
moves point nowhere to begin with, so the prefix does not vary it.
Calc's keep-args flag (K RET) holds point the same way; `maf-dup' reads
it, and `maf--fancy-prefix-keep' is what lets it survive the key."
  (interactive "P")
  (if (maf--sel-any-p)
      (maf-clear-selections)
    (maf-dup keep-point)))

;; RET is bound to a hand-written command rather than a `maf-defcmd' one,
;; so nothing stamps the property for it. It reads `calc-keep-args-flag'
;; deliberately (see the docstring above), which is exactly what the mark
;; means, so set it here.
(put 'maf-dup-or-clear-selections 'maf-command t)

(defun maf--fancy-prefix-binding (event)
  "The command or keymap EVENT would run, ignoring calc's fancy prefix.
`overriding-terminal-local-map' is unbound for the lookup: the fancy
prefix installs itself there, so it would otherwise answer for every key.
An event with no binding of its own is retried through
`local-function-key-map'. That retry is load-bearing for RET — it is
bound as the character 13, a graphical frame delivers the symbol
`return', and only the translation connects the two."
  (maf--with-calc-buffer
    (let ((overriding-terminal-local-map nil))
      (or (key-binding (vector event))
          (let ((translated (lookup-key local-function-key-map (vector event))))
            (and (vectorp translated) (key-binding translated)))))))

(defun maf--fancy-prefix-decide ()
  "Clear calc's flags unless the command that just resolved accepts them.
Runs once, from `pre-command-hook', after Emacs has read a whole key
sequence that began with a prefix `maf--fancy-prefix-keep' let through.
Only the leaf can say whether the flags were meant for it: a prefix like
C-c is shared, holding maf commands and ordinary global ones side by
side, so deciding at the prefix would hand the flag to whatever followed.
Removing the hook is the first thing done, so an aborted or undefined
sequence cannot strand it — `this-command' is nil for a quit under a
keyboard macro, which is why the test is \"keep only if marked\" rather
than \"clear if quit\"."
  (remove-hook 'pre-command-hook #'maf--fancy-prefix-decide)
  (unless (and (symbolp this-command) (get this-command 'maf-command))
    (calc-wrapper)))

(defun maf--fancy-prefix-keep (orig arg)
  "Let a maf command through calc's fancy prefix without clearing its flags.
A fancy prefix (K, I, H, O) sets its flag and installs
`calc-fancy-prefix-map' as the overriding map, so the next key runs
`calc-fancy-prefix-other-key' (ORIG, with prefix argument ARG) instead of
its own binding. That function decides whether the key was a calc
command, and its test excludes most of what maf binds: every control
character below SPC, and every event that is not an integer at all, which
is every function key. The flags are cleared before the key is unread and
dispatched for real, so the command runs without them.

Keep the flags when the key opens a command marked `maf-command' — the
commands whose commit path reads the resolve-time `:keep' snapshot, so
keep-args means something to them. Otherwise do exactly what ORIG does.
When the key is a prefix the leaf is not known yet, so let it through
provisionally and let `maf--fancy-prefix-decide' settle it once the whole
sequence has resolved.

Either way the flag clears where every command's does, in the epilogue of
the `calc-wrapper' the command itself runs.

Only for keep-args in a maf buffer — plain calc, and I/H/O, keep calc's
own behavior."
  (let ((def (and calc-keep-args-flag
                  (maf--with-calc-buffer maf-mode)
                  (maf--fancy-prefix-binding last-command-event))))
    (if (or (and (symbolp def) (get def 'maf-command))
            (keymapp def))
        (progn
          (when (keymapp def)
            (add-hook 'pre-command-hook #'maf--fancy-prefix-decide))
          (setq prefix-arg arg)
          (calc-unread-command)
          (setq overriding-terminal-local-map nil))
      (funcall orig arg))))

(advice-add 'calc-fancy-prefix-other-key :around #'maf--fancy-prefix-keep)

;; Calc's JumpRules are written for = alone: all 24 rules match
;; plain(... = ...) and nothing else. The same moves hold across a !=
;; — a != b exactly when a - c != b - c, and when a/c != b/c for a
;; nonzero c, the same latitude calc already takes with = — so maf
;; extends the set with an != twin of every rule. The twins are derived
;; from calc's own rules rather than kept as a second hand-written
;; copy, which would drift the moment calc edits the set upstream.
;;
;; The ordered relations stay out on purpose: crossing a < with a
;; division flips its direction, and a rewrite rule has no way to know
;; the divisor's sign. Those need `mafcmd-solve-for' / `calc-sel-isolate',
;; which reason about the solution rather than shuffling terms.

(defvar maf--jump-rules-cache nil
  "Memo cell for `maf--jump-rules': a cons of (SOURCE . EXTENDED).
SOURCE is the `var-JumpRules' value EXTENDED was derived from, compared
by identity — so a user who re-stores JumpRules gets a fresh derivation
instead of a stale extension.")

(defun maf--jump-subst-neq (expr)
  "Return EXPR with every = relation in it rewritten to !=."
  (if (Math-primp expr)
      expr
    (cons (if (eq (car expr) 'calcFunc-eq) 'calcFunc-neq (car expr))
          (mapcar #'maf--jump-subst-neq (cdr expr)))))

(defun maf--jump-rules ()
  "Return calc's JumpRules extended with an != twin of every = rule.
Reads whatever `var-JumpRules' currently holds — calc's own accessor
compiles the rule text on first use — and appends the substituted
copies, memoized so repeated jumps reuse one rule object and calc's
rewrite-compiler cache stays valid. Entries with no = in them, such as
the leading iterations(1) that caps the rule set at a single pass, are
not doubled."
  (let ((base (calc-var-value 'var-JumpRules)))
    (unless (eq base (car maf--jump-rules-cache))
      (setq maf--jump-rules-cache
            (cons base
                  (if (eq (car-safe base) 'vec)
                      (append base
                              (delq nil
                                    (mapcar
                                     (lambda (rule)
                                       (let ((neq (maf--jump-subst-neq rule)))
                                         (unless (equal neq rule) neq)))
                                     (cdr base))))
                    base))))
    (cdr maf--jump-rules-cache)))

(defun maf--jump-relation (expr node)
  "Return the innermost = or != in EXPR that contains NODE, or nil.
NODE itself does not count: a whole relation has no side to move a term
to. Ordered relations are not matched — see the commentary above."
  (let ((n node))
    (while (and (consp (setq n (calc-find-parent-formula expr n)))
                (not (memq (car n) '(calcFunc-eq calcFunc-neq)))))
    (and (consp n) n)))

(defun maf-jump-equals ()
  "Move the term under point across the = it sits in.

  x + a| = y  =>  x = -a| + y

Point picks the term as usual — the sub-formula under the cursor, or
the active selection when there is one — and calc's JumpRules perform
the move, inverting the operation the term crosses: a sum becomes a
negation, a product a quotient, a power a root. The result is calc's,
committed unsimplified. The term keeps its place under point on the
far side, so the next command still resolves there, and no selection
is left behind for the next keystroke to trip over.

  a x| = y    =>  a = y / x|
  a ^ 2| = y  =>  a = sqrt(y)|
  y = a + b|  =>  y - b| = a

A != is handled alongside =, on rules maf derives from calc's own. The
ordered relations (<, <=, >, >=) are not: moving a term across one can
flip its direction, which no rewrite rule can decide. Use
`mafcmd-isolate' on those.

At home, where point names no entry, a selection standing anywhere is
the term to move and the jump goes to it.

With no term to move — at home with nothing selected, on a whole entry,
on a term outside any = or !=, or on one the rules do not reach — the
command does nothing rather than signaling."
  (interactive)
  (maf--with-calc-buffer
    (let* ((at-point (calc-locate-cursor-element (point)))
           ;; At home point names no entry, but a selection standing
           ;; anywhere still names one, so the jump reaches it — the
           ;; fallback `maf--sel-effective-m' makes for the selection
           ;; commands.
           (m (if (> at-point 0) at-point (maf--sel-topmost-m))))
      (when m
        (let* ((entry (calc-top m 'entry))
               ;; On an entry this resolves the sub-formula under the
               ;; cursor, as the subexpr target does. Reached from home,
               ;; the entry carries an explicit selection — that is how
               ;; it was found — which this returns without consulting
               ;; point, so nothing has to move to read it.
               (sel (ignore-errors (calc-auto-selection entry))))
          ;; Only jump a term that has a relation above it. Handing calc
          ;; a selection the rules cannot match would still pop and push
          ;; the entry — an undo step, and a re-normalization — for a
          ;; result identical to what was there.
          (when (and (consp sel) (maf--jump-relation (car entry) sel))
            (let ((snapshot (maf--point-snapshot))
                  (var-JumpRules (maf--jump-rules)))
              ;; Calc's rewrite locates its entry from point, not from an
              ;; index, so from home point travels to the one the
              ;; selection named before the rewrite runs.
              (unless (> at-point 0) (calc-cursor-stack-index m))
              (condition-case nil
                  ;; nil: no repeat count. Repeating a jump only walks
                  ;; the term back where it came from.
                  (calc-sel-jump-equals nil)
                (error nil))
              ;; The rewrite reselects the moved term. maf resolves from
              ;; point instead, so read where the term landed, drop the
              ;; selection, and send point after it.
              (let ((moved (calc-top m 'sel)))
                (calc-unselect m)
                (or (and moved (maf--anchor-on-node m moved))
                    (maf--point-restore snapshot)))
              ;; A single undo reverts point along with the stack.
              (maf--undo-record-cmd-point snapshot))))))))

;;; Coordinates

(defun maf--coordinate-form (expr)
  "Return EXPR's next coordinate form, or nil when it has none.

A vector advances to the next name set (`maf--coordinate-cycle'). An
equation whose left side is an unknown function of one argument is a
graph point, f(a) = b, and unfolds to the pair [a, b] — the entry point
into the cycle for a value read off a graph. Any other relation cycles
whichever of its sides are vectors and leaves the rest alone, so v =
\[1, 2] names the right side in place."
  (cond
   ((eq (car-safe expr) 'vec)
    (maf--coordinate-cycle expr))
   ;; f(a) = b, f unknown. A known function (sin(2) = 0) is an equation
   ;; about a value, not a point, so it falls through to the relation
   ;; branch below.
   ((and (eq (car-safe expr) 'calcFunc-eq)
         (maf--unknown-fn-call-p (nth 1 expr) 1))
    (list 'vec (nth 1 (nth 1 expr)) (nth 2 expr)))
   ((maf--relation-p expr)
    (let ((sides (mapcar (lambda (side)
                           (if (eq (car-safe side) 'vec)
                               (maf--coordinate-cycle side)
                             side))
                         (cdr expr))))
      ;; Nil from a side means that vector could not be cycled; with no
      ;; vector side at all there is nothing to name.
      (and (cl-some (lambda (side) (eq (car-safe side) 'vec)) (cdr expr))
           (not (memq nil sides))
           (cons (car expr) sides))))))

(maf-defcmd mafcmd-coordinate-toggle (expr _arg commit)
  "Cycle the resolved vector through the coordinate name sets.

  [2, 4]  =>  [x = 2, y = 4]

A plain vector is named x, y, z, w; naming again advances to h, k, l, m,
then p, q, r, s, then back to x, y, z, w — so repeated presses walk the
naming conventions for a point, a vertex, and a second point without
disturbing the values. A vector named with anything else, or named only
in part, re-enters the cycle at x, y, z, w. The sets are
`maf-coordinate-name-sets'.

An equation f(a) = b whose function is undefined is a graph point and
unfolds to [a, b], which the next press names. Any other relation names
its vector sides in place. A vector with more components than the target
set has names is refused rather than silently truncated, and so is an
expression with no coordinate reading.

Point picks the target as usual: a vector under point, the vector entry
at point, the top entry at home.

  [1, 2, 3]          =>  [x = 1, y = 2, z = 3]
  [x = 1, y = 2]     =>  [h = 1, k = 2]
  [p = 1, q = 2]     =>  [x = 1, y = 2]
  [a = 1, b = 2]     =>  [x = 1, y = 2]
  f(2) = 0           =>  [2, 0]
  v = [1, 2]         =>  v = [x = 1, y = 2]"
  :arity unary
  :prefix "crd"
  ;; The graph-point case consumes the whole equation, and the relation
  ;; branch handles the per-side naming that mapping would otherwise do.
  :map -1
  (let ((form (maf--coordinate-form expr)))
    (unless form
      (user-error "No coordinate form for this expression"))
    (commit form)))

;;; Variables

(defun maf--swap-vars-in (expr a b)
  "Return EXPR with variables A and B traded throughout.
Every occurrence of A becomes B and every occurrence of B becomes A, in
a single structural pass — no temporary variable that a name already in
EXPR could collide with, and nothing normalized or reordered along the
way, so only the names change and the shape is left alone.

Descends the same nodes as `math-expr-subst' (`Math-primp' terminates
the walk), but without its two-argument deriv special case, which skips
the differentiated body: a rename that reached only the deriv's variable
slot would change the expression's meaning."
  (cond ((equal expr a) b)
        ((equal expr b) a)
        ((Math-primp expr) expr)
        (t (cons (car expr)
                 (mapcar (lambda (part) (maf--swap-vars-in part a b))
                         (cdr expr))))))

(defvar maf--swap-vars-pair nil
  "The two calc variables `maf--swap-vars-run' should trade, as a list.
Bound per `mafcmd-swap-vars' call, from the prompt it reads.")

(defun maf--swap-vars-default ()
  "Return the variable pair `mafcmd-swap-vars' offers as its default.
A string of two names, or nil when the entry has fewer than two
variables — or when point resolves to no entry at all, leaving the
prompt without a default. Read-only: resolves the same whole-entry
subject the command will act on and takes its first two variables in
priority order (see `maf--solve-sorted-vars'), without touching calc
state."
  (ignore-errors
    (let* ((context (maf--resolve-context
                     '((:arity . unary) (:scope . entry) (:map . -1))))
           (vars (maf--solve-sorted-vars (alist-get :expr context))))
      (when (nth 1 vars)
        (format "%s %s" (nth 1 (nth 0 vars)) (nth 1 (nth 1 vars)))))))

(defun maf--swap-vars-read (default)
  "Read the two variable names to swap; return them as calc variables.
DEFAULT is the pair empty input stands for, or nil to require input.
The two names are separated by a space or a comma, and surrounding
brackets are ignored, so x y, x,y and [x, y] all name the same pair.
Anything but exactly two plain variable names is a `user-error'."
  (let* ((input (string-trim
                 (read-string (if default
                                  (format "Swap variables (default %s): " default)
                                "Swap variables: ")
                              nil nil default)))
         ;; Brackets and commas are separators, not part of a name; the
         ;; rest splits on whitespace.
         (names (split-string (replace-regexp-in-string "[][,]" " " input)
                              nil t)))
    (unless (= (length names) 2)
      (user-error "Give exactly two variable names, as in x y"))
    (mapcar (lambda (name)
              (let ((var (math-read-expr name)))
                ;; Only plain names, so that a bare x y can be split on
                ;; whitespace rather than read as the product x y. A parse
                ;; failure comes back as (error POSITION MESSAGE), which is
                ;; no more a variable than 2 or f(x) is.
                (unless (eq (car-safe var) 'var)
                  (user-error "Not a variable name: %s" name))
                var))
            names)))

(maf-defcmd maf--swap-vars-run (expr _arg commit)
  "Trade the variables in `maf--swap-vars-pair' throughout the entry.
The worker behind `mafcmd-swap-vars' — see there. Takes the whole entry
\(`:scope entry'), so point within the formula never narrows the subject,
and takes a relation whole (`:map -1') rather than a side at a time, so a
pair split across the sides still swaps."
  :arity unary
  :prefix "swap"
  :map -1
  :scope entry
  (let ((a (nth 0 maf--swap-vars-pair))
        (b (nth 1 maf--swap-vars-pair)))
    ;; With neither name present the swap is a no-op, which reads as
    ;; nothing having happened; say so instead of committing a copy.
    (unless (or (math-expr-contains expr a) (math-expr-contains expr b))
      (user-error "Neither %s nor %s occurs in this entry"
                  (nth 1 a) (nth 1 b)))
    (commit (maf--swap-vars-in expr a b))))

(defun mafcmd-swap-vars ()
  "Swap two variables read from the minibuffer, throughout the expression.

  2 y = x + 2  =>  2 x = y + 2

Renaming only: the two names trade places wherever they occur and
nothing else moves, so the expression keeps its shape — no side is
re-solved and no sum reordered. Naming a variable that does not occur
renames the other one to it, which is how a single variable gets
renamed; when neither occurs the command signals rather than commit an
unchanged copy.

The prompt offers the entry's first two variables as its default — x, y,
z, t first, then alphabetical. Both names are given at once,
separated by a space or a comma; brackets around the pair are ignored.
Only plain variable names are accepted, since a bare x y has to split on
whitespace rather than read as the product.

It acts on the whole entry — the one at point, wherever point sits on its
line, or the top entry at home. Renaming is a statement about the whole
formula, so point within it is not used to narrow the subject, and a
relation is taken whole rather than a side at a time: a pair split across
the sides still swaps.

  x^2 + y            =>  y^2 + x      (typed: x y)
  a x + b y          =>  a y + b x    (typed: x y)
  x^2 + y            =>  y^2 + x      (typed: y x — order is immaterial)
  u + 1              =>  x + 1        (typed: u x — a rename)"
  (interactive)
  ;; Read the prompt before any calc state is touched, so C-g aborts with
  ;; nothing done.
  (let ((maf--swap-vars-pair (maf--swap-vars-read (maf--swap-vars-default))))
    (call-interactively #'maf--swap-vars-run)))

;;; Solving

(defun maf--solve-solved-for (expr)
  "Return the variable EXPR is already solved for, or nil.
That is the plain variable standing alone on one side of a relation —
an equation or an inequality."
  (when (maf--relation-p expr)
    (let ((lhs (nth 1 expr)) (rhs (nth 2 expr)))
      (cond ((eq (car-safe lhs) 'var) lhs)
            ((eq (car-safe rhs) 'var) rhs)))))

(defun maf--solve-fresh-var (expr)
  "Return a variable node whose name does not occur in EXPR."
  (let ((n 0) var)
    (while
        (progn
          (let ((name (format "u%d" n)))
            (setq var (list 'var (intern name)
                            (intern (concat "var-" name)))))
          (math-expr-contains expr var))
      (setq n (1+ n)))
    var))

(defun maf--solve-for-subexpr (rel target)
  "Solve relation REL for the sub-expression TARGET, or nil.
A plain variable is solved directly. A compound sub-expression is
isolated by substituting a fresh variable for it — calc cannot solve
for a compound directly through a nonlinear operator like sqrt — then
solving for that variable and substituting the sub-expression back."
  (if (eq (car-safe target) 'var)
      (math-solve-eqn rel target nil)
    (let* ((u (maf--solve-fresh-var rel))
           (soln (math-solve-eqn (math-expr-subst rel target u) u nil)))
      (and soln (math-expr-subst soln u target)))))

(defvar maf--solve-target nil
  "Sub-expression `mafcmd-auto-solve' should isolate, bound per call.
Nil means solve for a variable instead; read by `maf--auto-solve-run'.")

(defvar maf--solve-target-isolated nil
  "Non-nil when `maf--auto-solve-run' isolated `maf--solve-target'.
Bound per `mafcmd-isolate' call so its point handling can distinguish
a successful isolation from the fallback variable solve.")

(defvar maf--solve-solved-var nil
  "Variable `maf--auto-solve-run' solved the relation for, or nil.
Set only when the solve produced a relation, so a subject that came
back unchanged leaves it nil. Bound per call by `maf--auto-solve',
which reads it to land point on the variable the solve isolated.")

(defun maf--auto-solve-target ()
  "Return the sub-expression under point to isolate, or nil.
Any sub-expression under point is a target — a constant included, to
stay consistent with subexpr targeting. Nil only when there is no
sub-expression to speak of: point at a line margin, or on the relation
operator (whose sub-formula is the whole relation); the caller then
solves for a variable instead."
  (when (maf--at-subexpr-p)
    (maf--with-calc-buffer
      (save-excursion
        (let ((m (calc-locate-cursor-element (point))))
          (calc-prepare-selection m)
          (let ((sub (ignore-errors
                       (maf--strip-encasing (calc-find-selected-part)))))
            (and sub (not (maf--relation-p sub)) sub)))))))

(maf-defcmd maf--auto-solve-run (expr _arg commit)
  "Solve the whole relation for `maf--solve-target', else for a variable.
The worker behind `mafcmd-auto-solve' and `mafcmd-isolate' — see there.
Which of the two ran is invisible here: the difference is only whether
the caller found a sub-expression to put in `maf--solve-target', and
`mafcmd-auto-solve' never looks for one. Takes the whole entry
\(`:scope entry') and solves it: for `maf--solve-target' (the
sub-expression under point) when that is set and solvable, otherwise for
a variable — the first of x, y, z, t then alphabetical, cycling to the
next when already solved for one. Symbolic and prefer-frac so a
non-integer solution stays exact (1:2 and sqrt(2), not 0.5 and 1.414); a
bare expression is treated as = 0; nothing solvable commits unchanged."
  :arity unary
  :prefix "slv"
  :map -1
  :scope entry
  (let* ((rel (if (maf--relation-p expr) expr (list 'calcFunc-eq expr 0)))
         (result
          (let ((calc-symbolic-mode t) (calc-prefer-frac t))
            (let ((target-result
                   (and maf--solve-target
                        (maf--solve-for-subexpr rel maf--solve-target))))
              (setq maf--solve-target-isolated
                    (and (maf--relation-p target-result) t))
              (or
               (and maf--solve-target-isolated target-result)
               ;; If the target cannot be isolated, solve for a variable,
               ;; cycling on repeat.
               (let* ((vars (maf--solve-sorted-vars rel))
                      (n (length vars)))
                 (and (> n 0)
                      (let* ((solved
                              (and (> n 1) (maf--solve-solved-for rel)))
                             (pos
                              (and solved
                                   (cl-position solved vars :test #'equal)))
                             (var
                              (if pos
                                  (nth (mod (1+ pos) n) vars)
                                (car vars))))
                        (setq maf--solve-solved-var var)
                        (math-solve-eqn rel var nil)))))))))
    ;; Nothing solvable: the subject commits unchanged, so no variable
    ;; was isolated after all and point has nothing to land on.
    (if (maf--relation-p result)
        (commit result)
      (setq maf--solve-solved-var nil)
      (commit expr))))

(defun maf--auto-solve-point-offset ()
  "Point's offset within the sub-expression under point, or nil.
Measured from the sub-formula's first non-`(' glyph, so its wrapping
parens — rendered here but gone once it leads the isolated relation —
do not shift the offset."
  (save-excursion
    (let ((pt (point))
          (idx (calc-locate-cursor-element (point))))
      (when (> idx 0)
        (calc-prepare-selection idx)
        (let ((bounds (ignore-errors (maf--comp-find-bounds))))
          (when bounds
            (goto-char (car bounds))
            (skip-chars-forward "(")
            (max 0 (- pt (point)))))))))

(defun maf--auto-solve-land-on-var (var)
  "Put point on VAR where the solve left it in the entry at point.
The solved-for variable stands alone on one side of the result, but
which side is calc's call: solving 5 - x > 2 for x gives 3 > x, the
variable on the right. So the side is found rather than assumed, and
point goes to the start of its rendering. A result that does not carry
VAR as a bare side — an unchanged subject, a partial solve — leaves
point where it was."
  (let ((m (maf--with-calc-buffer (calc-locate-cursor-element (point)))))
    (when (> m 0)
      (let* ((formula (maf--with-calc-buffer (calc-top m 'full)))
             ;; The matched cons comes from the formula itself, which is
             ;; what the composition machinery can locate on screen.
             (side (and (maf--relation-p formula)
                        (cl-find var (list (nth 1 formula) (nth 2 formula))
                                 :test #'equal))))
        (when side
          (maf--point-restore-start `((:node . ,side) (:m . ,m))))))))

(defun maf--auto-solve (isolate)
  "Solve the entry at point, isolating the sub-expression when ISOLATE.
The shared body of `mafcmd-auto-solve' and `mafcmd-isolate': the two
differ only in whether point is read for a sub-expression to isolate,
which is what ISOLATE decides. Without it the worker sees no target and
solves for a variable, so the whole entry is the subject however deep
in the formula point rests.

Either way point lands on what the solve isolated — the sub-expression
when that was the target, otherwise the variable solved for. The undo
point is re-recorded afterwards, so one `maf-undo' still returns point
to where the command ran."
  (let* ((maf--solve-target (and isolate (maf--auto-solve-target)))
         (maf--solve-target-isolated nil)
         (maf--solve-solved-var nil)
         (snapshot (maf--point-snapshot))
         (offset (and maf--solve-target (maf--auto-solve-point-offset))))
    (call-interactively #'maf--auto-solve-run)
    (cond
     (maf--solve-target-isolated
      ;; Point follows the isolated sub-expression: it now leads the
      ;; entry, so return to the same offset within it.
      (maf-beginning-of-entry)
      (skip-chars-forward "(")
      (when (and offset (> offset 0)) (forward-char offset))
      (maf--undo-record-cmd-point snapshot))
     (maf--solve-solved-var
      (when (maf--auto-solve-land-on-var maf--solve-solved-var)
        (maf--undo-record-cmd-point snapshot))))))

(defun mafcmd-auto-solve ()
  "Solve the relation at point for a variable, cycling on repeat.

  x + 3 = 7  =>  x = 4

The whole entry is the subject wherever point rests within it: a
sub-formula under point never narrows it. The variable solved for is
the first of x, y, z, t, else alphabetical; running the command again
on a relation already solved for one moves on to the next.

  x + y = 5    =>  x = 5 - y   (again: y = 5 - x)
  2 x - 3 < 7  =>  x < 5
  x + 3 != 7   =>  x != 4
  3 = 3        =>  3 = 3       (no variable: unchanged)

Equations and inequalities alike, the relation kept — calc flips an
inequality's sense when it must. A bare expression is treated as = 0.
The result stays exact: a root gives sqrt(2), a ratio 1:2.

Point lands on the variable that ended up isolated, whichever side calc
put it on — solving 5 - x > 2 gives 3 > x, and point goes to the x on
the right. An entry that comes back unchanged leaves point where it
was, and a command invoked from home stays there. To solve for the
sub-expression under point instead, use `mafcmd-isolate'."
  (interactive)
  (maf--auto-solve nil))

(defun mafcmd-isolate ()
  "Isolate the sub-expression under point, else solve for a variable.

With point on a sub-expression, isolate it: solve the relation for that
sub-expression, standing it alone on the left. Any sub-expression works
— a compound whole (point on the product 30 x in y = 30 x + 12), one
under a nonlinear operator (x + 1 in sqrt(x + 1) = 3 y), even a bare
constant (the 1 in x + 1 = 3 y). The result stays exact: a root gives
sqrt(2), a ratio 1:2. If Calc cannot isolate the target, the command
falls back to the variable solve.

  a = b| c        =>  b = a / c        (isolate the factor at point)
  y = 30 x| + 12  =>  x = y / 30 - 2:5 (isolate x)
  x + 1| = 3 y    =>  1 = 3 y - x      (isolate the constant)

Point rides along with the isolated sub-expression, keeping its spot
within it as it moves to the head of the entry.

With no sub-expression to isolate — the line prefix or end of line, the
relation operator, or point at home — it solves the whole relation for
a variable, exactly as `mafcmd-auto-solve' does, point landing on that
variable; that command is this one with the sub-expression targeting
left out, for when the entry is the subject however point happens to
sit on it.

  x + 3 = 7|  =>  x = 4
  x + y = 5   =>  x = 5 - y   (again: y = 5 - x)
  3 = 3       =>  3 = 3       (no variable: unchanged)"
  (interactive)
  (maf--auto-solve t))

(defvar maf--solve-for-vars nil
  "Variable (or vector of them) `maf--solve-for-run' should solve for.
Bound per `mafcmd-solve-for' call, from the prompt it reads.")

(defvar maf--solve-for-func nil
  "Solver `maf--solve-for-run' should apply, a calcFunc symbol.
Bound per `mafcmd-solve-for' call, from calc's Inverse/Hyperbolic flags.")

(defun maf--solve-for-default-var ()
  "Return the variable name `mafcmd-solve-for' offers as its default.
Read-only: resolves the whole entry the command will act on and takes
its priority variable (see `maf--solve-sorted-vars'), so the prompt can
show a default without touching calc state. Nil when the subject has no
variable, or when point resolves to no entry at all — the prompt then
has no default and the command's own error, if any, reports the miss."
  (ignore-errors
    (let* ((context (maf--resolve-context
                     '((:arity . unary) (:scope . entry) (:map . -1))))
           (vars (maf--solve-sorted-vars (alist-get :expr context))))
      (and vars (symbol-name (nth 1 (car vars)))))))

(defun maf--solve-for-read-vars (default)
  "Read the variable(s) to solve for; return them as a calc expression.
DEFAULT is the variable name empty input stands for, or nil to require
input. Several names, separated by commas or spaces, come back as a
vector, so a system of equations can be solved for all its unknowns at
once. Anything calc cannot parse is a `user-error'."
  (let ((input (string-trim
                (read-string (if default
                                 (format "Solve for (default %s): " default)
                               "Solve for: ")
                             nil nil default))))
    (when (string-empty-p input)
      (user-error "No variable to solve for"))
    ;; Two or more names denote a vector; bracket them so calc reads one,
    ;; since bare "x y" would otherwise parse as the product x y. Input
    ;; that already brackets its own list is passed through as written.
    (let ((expr (math-read-expr
                 (if (and (string-match-p ",\\|[^ ] +[^ ]" input)
                          (not (string-search "[" input)))
                     (concat "[" input "]")
                   input))))
      ;; A parse failure comes back as (error POSITION MESSAGE).
      (when (eq (car-safe expr) 'error)
        (user-error "Bad format in expression: %s" (nth 2 expr)))
      expr)))

(maf-defcmd maf--solve-for-run (expr _arg commit)
  "Apply `maf--solve-for-func' to the whole entry for `maf--solve-for-vars'.
The worker behind `mafcmd-solve-for' — see there. Takes the whole entry
\(`:scope entry'), so point within the formula never narrows the
subject. Symbolic and prefer-frac, so a non-integer solution stays
exact. Calc leaves an unsolvable input as an unevaluated call to the
solver; that, and a calc signal raised along the way, both commit the
entry unchanged instead."
  :arity unary
  :prefix "solv"
  :map -1
  :scope entry
  (let ((result (let ((calc-symbolic-mode t) (calc-prefer-frac t))
                  (condition-case nil
                      (funcall maf--solve-for-func expr maf--solve-for-vars)
                    (error nil)))))
    (commit (if (or (null result)
                    (eq (car-safe result) maf--solve-for-func))
                expr
              result))))

(defun mafcmd-solve-for ()
  "Solve the relation at point for a variable read from the minibuffer.

  x + 3 = 7  =>  x = 4

Inverse: give the solver's inverse function instead, as an expression in
the named variable.

  x^2  =>  sqrt(x)

Hyperbolic: solve fully, naming the remaining freedom with a dummy
variable — s1 over the signs of an even root, n1 over the integer
multiples of a periodic solution.

  x^2 = 4  =>  x = 2 s1

Inverse Hyperbolic: the inverse function, likewise fully.

  x^2  =>  s1 sqrt(x)

The prompt offers the subject's priority variable as its default — x, y,
z, t first, then alphabetical. Several names separated by commas or
spaces solve a vector of equations for all of them at once. Solutions
stay exact: a root gives sqrt(2), a ratio 1:2, so an arc function of a
float stays unevaluated rather than collapsing to a number.

It acts on the whole entry — the relation at point, wherever point sits
on its line, or the top entry at home; solving has no sub-formula
meaning, so point within the formula is not used to narrow it. To solve
for something Calc cannot solve for directly — a compound
sub-expression, under a nonlinear operator — use `mafcmd-isolate',
which isolates the sub-expression under point. A bare expression is
treated as = 0, inequalities keep their relation, and an input Calc
cannot solve for the named variable commits unchanged.

  x + y = 5                     =>  y = 5 - x       (typed: y)
  [x + y = 3, x - y = 1]        =>  [x = 2, y = 1]  (typed: x,y)
  2 x - 3 < 7                   =>  x < 5
  -2 x < 4                      =>  -2 < x          (sides swap, sense kept)
  x^2 + y^2 = r^2               =>  y = sqrt(r^2 - x^2)
  x + 3                         =>  x = -3          (bare: solved = 0)
  2 x = 1                       =>  x = 1:2         (exact, not 0.5)
  x + 3 = 7                     =>  x + 3 = 7       (no y in it: unchanged)"
  (interactive)
  (let ((func (cond ((and calc-inverse-flag calc-hyperbolic-flag)
                     'calcFunc-ffinv)
                    (calc-inverse-flag 'calcFunc-finv)
                    (calc-hyperbolic-flag 'calcFunc-fsolve)
                    (t 'calcFunc-solve)))
        ;; Read the prompt before any calc state is touched, so C-g
        ;; aborts with nothing done. The flags are consumed only once the
        ;; input is in hand, and the worker's epilogue clears the mode
        ;; line — an abort leaves I/H set for the next command, as calc
        ;; itself does.
        (vars (maf--solve-for-read-vars (maf--solve-for-default-var))))
    (setq calc-inverse-flag nil
          calc-hyperbolic-flag nil)
    (let ((maf--solve-for-vars vars)
          (maf--solve-for-func func))
      (call-interactively #'maf--solve-for-run))))

(maf-defcmd mafcmd-inverse-function (expr _arg commit)
  "Invert the function at point: y = f(x) becomes y = f-inverse(x).

  y = 2 x + 3  =>  y = x / 2 - 3:2

The input and output are swapped and the equation solved back, so the
result reads as a function of the same input variable. Any names work:
the variable standing alone on one side is the output, the other side
the body, and the body's first variable in solve order — x, y, z, t,
then the alphabet — is the input, so parameters beside it carry
through.

  y = x^2            =>  y = sqrt(x)
  y = sqrt(x)        =>  y = x^2
  y = e^(x + k) + 3  =>  y = ln(x - 3) - k    (k is a parameter)
  x + 1 = y          =>  y = x - 1            (either side)

An f(x) on one side is kept as written and its argument is the input
variable, so the entry keeps naming the same function while its body
inverts.

  f(x) = x^2         =>  f(x) = sqrt(x)
  f(k) = k^2 + x     =>  f(k) = sqrt(k - x)   (inverts in k, not x)

An equation with no side standing alone is solved for its output
variable first — y when it occurs, else the second of its two
variables. A bare expression is the body alone; its inverse is named
y, or y1 when the expression itself uses y.

  2 y = x + 1        =>  y = 2 x - 1
  x^2 + y^2 = 1      =>  y = sqrt(1 - x^2)    (its own inverse)
  x + 1              =>  y = x - 1
  y^2                =>  y1 = sqrt(y)

The subject is the whole entry — the equation at point wherever point
sits on its line, or the top entry at home; inverting has no
sub-formula meaning, so point within the formula does not narrow it.
Solutions stay exact, a root giving sqrt rather than a float. Anything
that names no invertible function of a variable commits unchanged: an
inequality, an equation without variables, a body calc cannot solve.
To invert for a variable you name, use `mafcmd-solve-for' with calc's
Inverse prefix (I i), which gives the bare inverse expression.

  2 x - 3 < 7        =>  2 x - 3 < 7          (not a function)
  y = x^6 + x + 1    =>  y = x^6 + x + 1      (calc cannot solve it)"
  :arity unary
  :prefix "finv"
  :map -1
  :scope entry
  (commit (or (maf--function-inverse expr) expr)))

;;; Absolute-value inequalities

(defconst maf--abs-ineq-ops
  '(calcFunc-lt calcFunc-leq calcFunc-gt calcFunc-geq)
  "The ordering relations `mafcmd-abs-ineq' reads and produces.
Only these four bound a magnitude. An = or != says nothing about which
side of the bound the body falls on, so neither states an absolute-value
inequality nor comes out of splitting one.")

(defun maf--abs-ineq-p (expr)
  "Non-nil when EXPR is an ordering relation with abs() alone on one side.
The `:widen' predicate for `mafcmd-abs-ineq', and the same test its body
uses to decide there is work to do. The abs may stand on either side —
5 > abs(x) states the same bound as abs(x) < 5 — but it has to be the
whole side: 2 abs(x) < 5 carries a coefficient to divide out first,
which this command does not do."
  (and (consp expr)
       (memq (car expr) maf--abs-ineq-ops)
       (or (eq (car-safe (nth 1 expr)) 'calcFunc-abs)
           (eq (car-safe (nth 2 expr)) 'calcFunc-abs))
       t))

(defun maf--abs-ineq-parts (expr)
  "Return EXPR read as the list (OP BODY BOUND), or nil if it is not one.
BODY is what the abs() wraps and BOUND the other side, with OP oriented
so the three read as \"magnitude of BODY, OP, BOUND\" — an abs on the
right is flipped rather than left in place, so 5 > abs(x) takes the same
route as abs(x) < 5. With an abs on both sides the left one is the body,
the right one an ordinary bound."
  (when (maf--abs-ineq-p expr)
    (let ((lhs (nth 1 expr)) (rhs (nth 2 expr)))
      (if (eq (car-safe lhs) 'calcFunc-abs)
          (list (car expr) (nth 1 lhs) rhs)
        (list (maf--flip-relation-op (car expr)) (nth 1 rhs) lhs)))))

(defun maf--abs-ineq-solve (part var)
  "Solve the ordering relation PART for VAR, or return PART unchanged.
PART stands as it is when there is no VAR to solve for, when VAR already
stands alone on one side, and when calc's solver declines.

It also stands when the solver answers with something that is not an
ordering relation. Calc rearranges an inequality only where it can settle
the sign of what it divides by; where it cannot, it falls back to solving
the corresponding equation and reports the boundary as a !=, which states
something quite different from the bound asked about — x^2 < 5 comes back
as x != sqrt(5). Leaving the part as written is the honest answer there.

Symbolic and prefer-frac, as `maf--auto-solve-run' is, so a non-integer
bound stays exact: abs(2 x) < 5 bounds x by 5:2 rather than 2.5."
  (if (or (null var)
          (equal (nth 1 part) var)
          (equal (nth 2 part) var))
      part
    (let* ((calc-symbolic-mode t)
           (calc-prefer-frac t)
           (soln (ignore-errors (math-solve-eqn part var nil))))
      (if (memq (car-safe soln) maf--abs-ineq-ops) soln part))))

(defun maf--abs-ineq-band (lower upper var)
  "Join LOWER && UPPER as a band, VAR standing between its two bounds.
The band reads lower < VAR && VAR < upper. The parts arrive in that
order and calc's solver leaves the solved-for side where it found it, so
they need swapping only when it moved VAR across — which it does to both
parts together, the coefficient it divides by being the same one."
  (if (and var (equal (nth 1 lower) var))
      (list 'calcFunc-land upper lower)
    (list 'calcFunc-land lower upper)))

(defun maf--abs-ineq-tails (left right var)
  "Join LEFT || RIGHT as two tails, VAR leading each of them.
The tails read VAR < lower || VAR > upper: VAR on the near side of both
parts, and the < or <= one first, so the two tails run left to right
along the number line. A part the solver moved VAR across is flipped
back rather than reordered, since with the two bounds pointing opposite
ways only one of them can lead."
  (let* ((l (if (and var (equal (nth 2 left) var))
                (maf--flip-relation left) left))
         (r (if (and var (equal (nth 2 right) var))
                (maf--flip-relation right) right)))
    (if (memq (car l) '(calcFunc-lt calcFunc-leq))
        (list 'calcFunc-lor l r)
      (list 'calcFunc-lor r l))))

(defun maf--abs-ineq-split (expr)
  "Return EXPR's absolute-value inequality as a compound one, or nil.
A magnitude held below a bound is a band — both tails cut off, joined by
&& — and a magnitude held above one is the two tails themselves, joined
by ||. Each part is then solved for EXPR's first variable in
`maf--solve-sorted-vars' order, so the variable comes to stand alone
against each bound where calc can put it there."
  (pcase-let ((`(,op ,body ,bound) (maf--abs-ineq-parts expr)))
    (when op
      (let ((neg (math-neg bound))
            (var (car (maf--solve-sorted-vars body))))
        (pcase op
          ((or 'calcFunc-lt 'calcFunc-leq)
           (maf--abs-ineq-band
            (maf--abs-ineq-solve (list op neg body) var)
            (maf--abs-ineq-solve (list op body bound) var)
            var))
          ((or 'calcFunc-gt 'calcFunc-geq)
           ;; The lower tail points the other way: abs(a) > b holds when
           ;; a runs past -b downward, not up to it.
           (let ((down (if (eq op 'calcFunc-gt) 'calcFunc-lt 'calcFunc-leq)))
             (maf--abs-ineq-tails
              (maf--abs-ineq-solve (list down body neg) var)
              (maf--abs-ineq-solve (list op body bound) var)
              var))))))))

(maf-defcmd mafcmd-abs-ineq (expr _arg commit)
  "Split the absolute-value inequality at point into a compound one.

  abs(x) < 5   =>  -5 < x && x < 5
  abs(x) > 5   =>  x < -5 || x > 5

A magnitude held below a bound is a band: both tails are cut off, and
the two halves join with &&, the variable standing between its bounds.
A magnitude held above one is those tails themselves, joined with ||,
the variable leading each. <= and >= carry through to both halves, so a
closed bound stays closed.

  abs(x) <= b  =>  -b <= x && x <= b
  abs(x) >= b  =>  x <= -b || x >= b

Each half is then solved for the body's first variable in solve order —
x, y, z, t, then the alphabet — so the bounds come out as bounds on that
variable rather than on the expression around it. The arithmetic stays
exact, a halved bound giving 5:2 rather than 2.5, and a negative
coefficient turns both halves together, keeping the band and the tails
reading the right way round.

  abs(2 x) < 5      =>  -5:2 < x && x < 5:2
  abs(x - 1) <= 3   =>  -2 <= x && x <= 4
  abs(-2 x) > 5     =>  x < -5:2 || x > 5:2
  abs(x + y) < 5    =>  -y - 5 < x && x < 5 - y   (y is a parameter)

The abs may stand on either side — 5 > abs(x) is the same bound as
abs(x) < 5 — and a half calc cannot rearrange is kept as written rather
than forced, so the split itself is never lost.

  5 > abs(x)        =>  -5 < x && x < 5
  abs(x^2) < 5      =>  -5 < x^2 && x^2 < 5      (calc cannot isolate x)

Within a formula, point widens outward to the innermost abs inequality
around it, so the command means the same thing from anywhere inside one,
including inside a compound that holds it. Anything that is not an abs
inequality commits unchanged rather than signaling — an ordinary
relation, an equality, or an abs under a coefficient, which would have
to be divided out first.

  abs(x)| < 5 && y > 0  =>  (-5 < x && x < 5) && y > 0
  abs(x) = 5            =>  abs(x) = 5           (not an ordering)
  2 abs(x) < 5          =>  2 abs(x) < 5         (coefficient in the way)
  x < 5                 =>  x < 5                (no abs)"
  :arity unary
  :prefix "aineq"
  ;; The subject is the relation whole — its two sides are the bound and
  ;; the magnitude, and the split consumes both at once.
  :map -1
  ;; Point inside an abs inequality usually names the body or the bound,
  ;; neither of which can be split on its own; widening to the relation
  ;; that can is what keeps the key from doing nothing there.
  :widen maf--abs-ineq-p
  (commit (or (maf--abs-ineq-split expr) expr)))

;;; Substitution

(defvar maf--subst-old nil
  "The expression `maf--substitute-run' replaces.
Bound per `mafcmd-substitute' call, from the prompt it reads.")

(defvar maf--subst-new nil
  "The replacement `maf--substitute-run' puts in `maf--subst-old's place.
Bound per `mafcmd-substitute' call; nil for the $ form, whose
replacement is the stack arg `maf--substitute-arg-run' receives.")

(defun maf--subst-subject (arity)
  "Return the expression `mafcmd-substitute' will act on, or nil.
Read-only: resolves the target an ARITY command would resolve without
touching calc state, so the prompt can offer a default and a
substitution that matches nothing can be refused before anything is
committed.

The mark is saved and restored around the resolve: the region target
consumes the gesture by deactivating the mark, and this probe must
leave the region standing for the run that follows. Nil when point
resolves to no target at all — the run then raises the real error."
  (ignore-errors
    (save-mark-and-excursion
      (alist-get :expr (maf--resolve-context `((:arity . ,arity)))))))

(defun maf--subst-parse (input)
  "Return INPUT parsed as a calc expression.
Empty input, and anything calc cannot parse, are `user-error's."
  (when (string-empty-p input)
    (user-error "No expression given"))
  (let ((expr (math-read-expr input)))
    ;; A parse failure comes back as (error POSITION MESSAGE).
    (when (eq (car-safe expr) 'error)
      (user-error "Bad format in expression: %s" (nth 2 expr)))
    expr))

(defun maf--subst-read-old (default)
  "Read the expression to replace; return it parsed.
DEFAULT is the name empty input stands for, or nil to require input."
  (maf--subst-parse
   (string-trim (read-string (if default
                                 (format "Substitute (default %s): " default)
                               "Substitute: ")
                             nil nil default))))

(defun maf--subst-read-new (old)
  "Read the replacement for OLD; return it parsed.
A lone $ comes back as the symbol `stack': the replacement is then the
entry above the subject, taken as the command's binary arg."
  (let ((input (string-trim
                (read-string (format "Substitute %s with: "
                                     (math-format-value old))))))
    (if (string= input "$")
        'stack
      (maf--subst-parse input))))

(maf-defcmd maf--substitute-run (expr _arg commit)
  "Replace `maf--subst-old' with `maf--subst-new' in the resolved expression.
The worker behind `mafcmd-substitute' — see there. The rewritten
expression is normalized, so a substitution that makes a part constant
folds it under the current simplification mode."
  :arity unary
  :prefix "sbst"
  (commit (math-normalize
           (math-expr-subst expr maf--subst-old maf--subst-new))))

(maf-defcmd maf--substitute-arg-run (expr arg commit)
  "Like `maf--substitute-run', with the stack supplying the replacement.
The $ form of `mafcmd-substitute': the entry above the subject is the
replacement, and commit consumes it as the binary arg it is."
  :arity binary
  :prefix "sbst"
  (commit (math-normalize (math-expr-subst expr maf--subst-old arg))))

(defun mafcmd-substitute ()
  "Replace every occurrence of one expression with another, contextually.

  2 x + 1  =>  2 a + 3     (typed: x, then a + 1)

Reads the expression to replace and its replacement from the
minibuffer, both in algebraic notation. The first prompt offers the
subject's priority variable as its default — x, y, z, t first, then
alphabetical — so substituting for the obvious unknown is two returns.

Point picks the subject as usual: the selection or sub-formula at
point, each side of an equation, the whole entry from its margin, the
top entry at home. Only the subject is rewritten, so a substitution
can be confined to one part of a formula.

  x^2 + x|            =>  x^2 + 3     (subject is the term at point)
  y = x^2 - 1         =>  y = 8       (both sides; typed: x, 3)

The result is normalized under the current simplification mode, as
calc's own substitution is: putting a value in collapses what it makes
constant, and what lands beside it combines, exactly as if the
substituted formula had been typed in. What surrounds the subject is
untouched and never refolded, so putting 5 in for a selected x leaves
y (5 + 2) standing. With simplification off (@) the substitution is
structural throughout — 2 + 3 stays 2 + 3.

  x + 3               =>  5           (typed: x, 2)
  x + 3               =>  2 + 3       (the same, simplification off)

Answering $ at the replacement prompt takes the replacement from the
stack — the entry above the subject, the top entry at home — and
consumes it on commit, so an expression already on the stack need not
be retyped. As for any binary command, the subject must lie below the
top for that form.

An expression the subject does not contain is refused before anything
is committed, rather than rewritten to an unchanged copy."
  (interactive)
  (let* ((subject (maf--subst-subject 'unary))
         (vars (and subject (maf--solve-sorted-vars subject)))
         ;; Read both prompts before any calc state is touched, so C-g
         ;; aborts with nothing done.
         (old (maf--subst-read-old
               (and vars (symbol-name (nth 1 (car vars))))))
         (new (maf--subst-read-new old))
         (stack-arg (eq new 'stack))
         ;; $ makes the command binary, which resolves a different
         ;; subject (the entry below the top at home); check that one.
         (subject (if stack-arg (maf--subst-subject 'binary) subject)))
    (when (and subject (not (math-expr-contains subject old)))
      (user-error "No occurrences of %s" (math-format-value old)))
    (let ((maf--subst-old old)
          (maf--subst-new (unless stack-arg new)))
      (call-interactively (if stack-arg
                              #'maf--substitute-arg-run
                            #'maf--substitute-run)))))

(defun maf--let-bindings (arg)
  "Return ARG's assignments as an alist of (SYMBOL . VALUE), or nil.
ARG is an assignment — x := 3, or the plain equation x = 3 — or a
vector of nothing but assignments; SYMBOL is calc's storage symbol for
the variable (var-x) and VALUE the expression assigned to it.

Calc's own `calc-is-assignments' does the reading, so the shapes
accepted are exactly the ones `calc-let' takes. It builds its list back
to front; reversing puts the bindings in written order, so a vector
naming the same variable twice ends with the later assignment standing."
  ;; calc-ext's autoload registry covers most of calc-store but not this
  ;; function, so the module has to be pulled in by hand.
  (require 'calc-store)
  (nreverse (calc-is-assignments arg)))

(defun maf--let-evaluate (expr bindings)
  "Return EXPR evaluated with BINDINGS in force.
BINDINGS is an alist as `maf--let-bindings' returns. Each variable is
stored for the evaluation and restored afterwards — to its previous
value, or to unbound when it had none — even if the evaluation signals.

Evaluation is calc's, so every stored variable is substituted, not only
the ones bound here, and the result normalizes as the current
simplification mode says.

`calc-refresh-evaltos' is deliberately not called around the stores:
the bindings are gone again before the command commits, so no => entry's
value ends up changed, and refreshing would only rewrite stack entries
underneath the commit that is about to run."
  (let ((saved (mapcar (lambda (b)
                         (list (car b)
                               (boundp (car b))
                               (and (boundp (car b)) (symbol-value (car b)))))
                       bindings)))
    (unwind-protect
        (progn
          (dolist (b bindings)
            (set (car b) (calc-normalize (cdr b))))
          (math-evaluate-expr expr))
      (dolist (s saved)
        (if (nth 1 s)
            (set (car s) (nth 2 s))
          (makunbound (car s)))))))

(maf-defcmd mafcmd-let (expr arg commit)
  "Evaluate the resolved expression under the top-of-stack assignments.

  2 x + 1 with x := 3  =>  7

The argument is an assignment — `mafcmd-assign's x := 3, or the plain
equation x = 3 — or a vector of nothing but assignments, and it binds
its variables for this one evaluation: nothing is stored, and a
variable that already had a value has it back by the time the command
returns.

The value is evaluated in rather than pasted in, so the formula folds
around it as if the number had been there all along — that is the
difference from `mafcmd-substitute', which rewrites structurally. With
simplification off (@) nothing folds and the value simply lands in
place. Being an evaluation, it also brings in whatever other variables
are stored, exactly as calc's own `s l' does; a variable with no value
anywhere stands.

  a x with [x := 3, a := 2]  =>  6
  2 x + 1 with x := 3        =>  2 3 + 1    (the same, simplification off)
  x + y with x := 3          =>  y + 3      (y unbound: stands)

Like any binary command, the entry at point is the subject and the top
of the stack is the argument, consumed on commit; at home the subject
is stack level 2. Point inside a formula does not narrow the subject
\(`:scope explicit'): the entry is evaluated whole, each side of a
relation in turn, wherever point rests on it — including on the
argument, which resolves to the entry below, so an assignment can be
typed and used without moving back to the formula it binds. A region or
a calc selection does narrow the subject to what it covers: evaluating
one part of an entry is asked for rather than fallen into.

With keep-args both operands stay and the result is pushed on top. A
top entry that is not an assignment signals, with the stack untouched.
An assignment written as a plain equation stays one argument even when
the subject is a relation: each side is evaluated under it, rather than
its two sides pairing with the subject's as they would in equation
arithmetic — so the subject's operator does not have to be = either.

  y = x^2 + 1 with x := 3   =>  y = 10
  3 x < 15 with x = 2       =>  6 < 15
  x^2 + x| with x := 3      =>  12         (point within: the entry whole)
  x^2 + x  with x := 3|     =>  12         (point on the argument: likewise)"
  :arity binary
  :prefix "let"
  :pair -1
  :scope explicit
  (let ((bindings (maf--let-bindings arg)))
    (unless bindings
      (user-error "Top of stack is not an assignment, or a vector of them"))
    (commit (maf--let-evaluate expr bindings))))

;;; Roots

(defun maf--poly-factors (expr)
  "Return EXPR's multiplicative factors as (FACTOR . MULTIPLICITY) pairs.
Splits products and positive integer powers, so (x - 2)^2 (x + 1)
yields (x - 2) with multiplicity 2 and (x + 1) with multiplicity 1."
  (cond
   ((eq (car-safe expr) '*)
    (append (maf--poly-factors (nth 1 expr))
            (maf--poly-factors (nth 2 expr))))
   ((and (eq (car-safe expr) '^) (integerp (nth 2 expr)) (> (nth 2 expr) 0))
    (let ((sub (maf--poly-factors (nth 1 expr)))
          (e (nth 2 expr)))
      (mapcar (lambda (fm) (cons (car fm) (* (cdr fm) e))) sub)))
   (t (list (cons expr 1)))))

(defun maf--poly-roots-of (poly var)
  "Return a Calc vector of all known roots of POLY in VAR, or nil.
POLY is factored first, then each factor's roots are taken and repeated
by the factor's multiplicity, so (x - 2)^2 contributes 2 twice.
Factors independent of VAR are ignored.  If Calc cannot solve any factor
that does contain VAR, return nil rather than a misleading partial vector.
A Calc signal during factoring or root-finding (e.g. `calcFunc-roots'
raising division-by-zero on a rational with no roots) is likewise treated
as unsolved: return nil so the command commits the entry unchanged rather
than letting the error escape `calc-wrapper' and strand point at home."
  (condition-case nil
      (catch 'unsolved
        (cons 'vec
              (cl-mapcan
               (lambda (fm)
                 (let ((factor (car fm)))
                   (if (not (member var (maf--solve-sorted-vars factor)))
                       nil
                     (let ((result (calcFunc-roots factor var)))
                       (unless (eq (car-safe result) 'vec)
                         (throw 'unsolved nil))
                       (cl-mapcan
                        (lambda (root) (make-list (cdr fm) root))
                        (cdr result))))))
               (maf--poly-factors (calcFunc-factor poly)))))
    (error nil)))

(defun maf--poly-roots-subject (expr)
  "Return the polynomial whose roots EXPR asks for.
A relation reduces to one side or the difference of sides: an equation
whose left side is an unknown unary function (as in f(x) = x^2 - 4)
uses the right side.  Otherwise the difference of the sides is used, so
ordinary function equations, inequalities, and != yield the roots of
their boundary.  A bare expression is returned unchanged."
  (if (maf--relation-p expr)
      (let ((lhs (nth 1 expr)) (rhs (nth 2 expr)))
        (if (and (eq (car expr) 'calcFunc-eq)
                 (maf--unknown-fn-call-p lhs 1))
            rhs
          (calcFunc-sub lhs rhs)))
    expr))

(maf-defcmd mafcmd-poly-roots (expr _arg commit)
  "Find the roots of the resolved polynomial, as a vector.

  x^2 - 4  =>  [-2, 2]

The polynomial is factored first, so repeated factors keep their
multiplicity and the roots come out one per factor. An equation is
accepted too: f(x) = g uses g when f is an unknown function, otherwise
the difference of the sides. The variable is chosen as for
`mafcmd-auto-solve' — x, y, z, t first, then alphabetical. An expression
with no variable, or one Calc cannot solve completely under the current
modes, commits unchanged. It acts on the whole entry — the polynomial or
equation at point, wherever point sits on its line — or the top entry at
home; finding roots has no sub-formula meaning, so point within the
formula is not used to narrow it.

  x^3 - x^2 - 4 x + 4    =>  [-2, 1, 2]
  (x - 1)^2 (x + 2)      =>  [-2, 1, 1]   (multiplicity kept)
  x^2 - 4 = 0            =>  [-2, 2]
  f(x) = x - 3           =>  [3]"
  :arity unary
  :prefix "root"
  :map -1
  :scope entry
  (let* ((poly (maf--poly-roots-subject expr))
         (vars (maf--solve-sorted-vars poly)))
    (commit (or (and vars (maf--poly-roots-of poly (car vars)))
                expr))))

;;; Vectors

(maf-defcmd mafcmd-unique-groups (expr arg commit)
  "Group the resolved vector's elements, the top of the stack at a time.

  [a, b, c] with 2  =>  [[a, b], [a, c], [b, c]]

Every group of that many distinct positions is produced, each element
used at most once per group, so the result holds the combinations of
the vector rather than its permutations — [b, a] never appears beside
\[a, b]. The order within a group and among the groups is the vector's
own. Groups that come out identical are listed once, so a vector with
repeated elements gives the distinct groupings instead of one group per
position.

A size larger than the vector gives the empty vector, having no group
to make, and a size of zero the one empty group. Anything but a
non-negative integer is not a size and signals; a subject that is not a
vector commits unchanged, so equation sides without one pass through
quietly.

Like any binary command, the entry at point is the subject and the top
of the stack is the argument, consumed on commit; point picks the
subject as usual — a sub-formula at point, each side of an equation,
stack level 2 at home. Within a formula the subject is the innermost
vector around point rather than the node point names, so pressing the
key on an element groups the vector holding it. An explicit calc
selection is taken as it stands and never widened.

  [a, b, c, d] with 2  =>  [[a, b], [a, c], [a, d], [b, c], [b, d], [c, d]]
  [a, b, c, d] with 3  =>  [[a, b, c], [a, b, d], [a, c, d], [b, c, d]]
  [a, b, c] with 1     =>  [[a], [b], [c]]
  [a, b, c] with 3     =>  [[a, b, c]]
  [a, b] with 3        =>  []
  [a, a, b] with 2     =>  [[a, a], [a, b]]
  v = [a, b, c] with 2 =>  v = [[a, b], [a, c], [b, c]]
  x with 2             =>  x    (not a vector: unchanged)"
  :arity binary
  :prefix "ugrp"
  ;; Only a vector has groups, so resolve hands the body the innermost
  ;; one around point instead of whatever node point happens to name.
  ;; Without this, pressing the key on an element — the obvious place to
  ;; stand — would silently commit that element unchanged.
  :widen math-vectorp
  ;; An integer written as a float (3.) still names a size; anything
  ;; with a fractional part, a negative, or a symbol does not.
  (let ((n (and (math-num-integerp arg) (math-trunc arg))))
    (unless (and n (>= n 0))
      (user-error "Group size must be a non-negative integer"))
    (commit (if (math-vectorp expr)
                (maf--unique-groups expr n)
              expr))))

;;; Flattening

(defun maf--flatten-nested-p (expr)
  "Non-nil when EXPR is a vector with a vector among its elements.
The `:widen' predicate for `mafcmd-flatten', and the same test its body
uses to decide there is work to do: a vector whose elements are all
scalars is already flat, so flattening it would commit it unchanged.
Widening past such a vector is what lets the command mean something
from anywhere inside a matrix — point on the 1 of [[1, 2], [3, 4]]
names the flat row [1, 2], and the matrix that holds that row is the
node with nesting to remove."
  (and (math-vectorp expr)
       (cl-some #'math-vectorp (cdr expr))))

(maf-defcmd mafcmd-flatten (expr _arg commit)
  "Flatten the resolved vector into a single flat vector.

  [[1, 2], [3, 4]]  =>  [1, 2, 3, 4]

Nesting is removed at every depth, not just the top level, and the
elements keep their reading order. This is calc's `v a' (arrange) with
a column count of zero — `mafcmd-arrange' spreads a vector into rows of
N columns, and flattening is the degenerate case that asks for no rows
at all.

The result is a single expression, so it fits any target. Within a
formula, point widens outward to the innermost vector that actually has
nesting to remove, so the command means the same thing from anywhere
inside a matrix. Anything with no nesting to remove — a scalar, a
variable, an already-flat vector, or a sub-formula with no nested
vector around it — commits unchanged rather than signaling.

  [1, [2, [3, 4]], 5]      =>  [1, 2, 3, 4, 5]   (all depths)
  [[1, 2], [3]]            =>  [1, 2, 3]         (ragged rows are fine)
  x + [[1, 2], [3, 4]]|    =>  x + [1, 2, 3, 4]
  [[1|, 2], [3, 4]]        =>  [1, 2, 3, 4]      (widens to the matrix)
  [1, 2]                   =>  [1, 2]            (already flat)
  5                        =>  5                 (nothing to flatten)"
  :arity unary
  :prefix "flat"
  ;; In a formula slot the node under point is often a row or an element,
  ;; neither of which has nesting to remove. Widening to the innermost
  ;; vector that does is what keeps the key from silently doing nothing
  ;; when pressed inside a matrix.
  :widen maf--flatten-nested-p
  ;; calcFunc-arrange returns nil for a non-vector, which normalizes to
  ;; the inert form arrange(5, 0) — so guard on the vector test and build
  ;; the flat vector directly instead of going through the call.
  (commit (if (maf--flatten-nested-p expr)
              (cons 'vec (math-flatten-vector expr))
            expr)))

;;; Unpacking

(defun maf--unpack-parts (expr mode)
  "Return EXPR's parts as a list, or nil if it has none to give.
MODE is calc's unpacking mode: nil splits one level, a positive N splits
N levels deep, a negative N splits a vector by component type. Calc
signals for anything the mode does not apply to — a bare variable, a
plain number, an HMS mode against a non-HMS form; return nil there
instead, so callers can leave such an expression alone rather than
abort. `calc-unpack-with-type' is bound off so the parts come back on
their own, as `calcFunc-unpack' returns them, without the trailing
dimension entries `calc-unpack' adds for its own stack listing."
  (let ((calc-unpack-with-type nil))
    (condition-case nil
        (calc-unpack-item mode expr)
      (error nil))))

(defun maf--unpack-mode ()
  "The unpacking mode for this command, from the prefix argument.
Nil — one level — when no prefix was given."
  (and current-prefix-arg (prefix-numeric-value current-prefix-arg)))

(defun maf--unpack-peelable-p (expr)
  "Non-nil when EXPR unwraps to exactly one part.
The `:widen' predicate for `mafcmd-unpack': a node that gives exactly
one part is one a sub-formula slot can hold, so it is the node to peel.
Reads the mode through `maf--unpack-mode', the same way the body does —
resolve and body must agree on what counts, or resolve would widen to a
node the body then declines to unwrap."
  (let ((parts (maf--unpack-parts expr (maf--unpack-mode))))
    (and parts (null (cdr parts)))))

(maf-defcmd mafcmd-unpack (expr _arg commit)
  "Unwrap the resolved expression, spreading its parts across the stack.

  [x, y]  =>  2:  x
              1:  y

One level comes apart at a time: a composite object into its
components, a function call into its arguments, an operator into its
operands. A whole entry gives one stack entry per part.

Inside a formula there is room for only one expression, so point peels
the innermost wrapper around it that gives exactly one part — the node
under point when that fits, otherwise the nearest enclosing one. So
anywhere within sin(2 x) the command means the same thing: take off
the sin.

  sin(2| x)  =>  2 x
  sin|(2 x)  =>  2 x

A numeric prefix argument gives calc's unpacking mode: a positive N
unwraps N levels deep, a negative N splits a vector by component type.
An expression with nothing to give — a plain number, a bare variable,
or one the requested mode does not fit — commits unchanged rather than
signaling, as does a sub-formula with no peelable wrapper around it.
An explicit calc selection is taken as it stands and never widened.

  sin(x)                 =>  x
  a + b                  =>  2:  a / 1:  b
  3:4                    =>  2:  3 / 1:  4
  1.5                    =>  2:  15 / 1:  -1   (mantissa and exponent)
  x                      =>  x                 (nothing to give)
  C-u 2 [(1,2),(3,4)]    =>  4:  1 / 3:  2 / 2:  3 / 1:  4
  x = sin(y)             =>  2:  x / 1:  sin(y)
  y + sin(a + b)|        =>  y + a + b         (peels the sin)
  (a| + b) (2 c - d)     =>  unchanged         (no wrapper to peel)"
  :arity unary
  :prefix "unpk"
  ;; A relation is a function call like any other: unwrapping consumes
  ;; it into its two sides, as calc-unpack does, rather than mapping
  ;; over them and putting the relation back together.
  :map -1
  ;; In a formula slot only a one-part node fits, so resolve hands the
  ;; body the innermost such node around point instead of whatever
  ;; point happens to name. Without this, pressing the key on an
  ;; operand or on a multi-part operator would silently do nothing.
  :widen maf--unpack-peelable-p
  (let ((parts (maf--unpack-parts expr (maf--unpack-mode))))
    (commit
     (cond
      ;; Nothing to give: leave the target exactly as it stands.
      ((null parts) expr)
      ;; A whole stack entry takes the parts as a value list, which
      ;; commit spreads over one entry each.
      ((memq maf-target '(home entry)) parts)
      ;; A sub-formula slot holds a single expression: unwrap when the
      ;; parts amount to one, otherwise there is no room for them.
      ((null (cdr parts)) (car parts))
      (t expr)))))

;;; Raising

(maf-defcmd mafcmd-raise (expr _arg commit)
  "Discard everything in the entry but the resolved expression.

  x + sin|(2 y)  =>  sin(2 y)

The part point names becomes the whole stack entry. Nothing is
computed and nothing is simplified: the formula that held the part is
thrown away and the part arrives exactly as it stood.

  a + |b + c  =>  b
  x = 3| y    =>  3 y     (a relation's side)

Point picks the target as usual — the sub-formula at point, the run of
terms a region covers, an explicit calc selection. Where the target
already is the whole entry, at home or on the entry's margin, there is
nothing around it to discard and the entry commits unchanged. With
calc's keep-args flag the entry stays as it stands and the raised part
arrives as a new entry on top of it.

  (a + b|) (2 c - d)  =>  a + b
  [1, |2, 3]          =>  2
  a| + b + c          =>  a + b   (a sum groups leftward: (a + b) + c)
  x + y|              =>  x + y   (the margin names the whole entry)"
  :arity unary
  :prefix "rais"
  ;; The value replaces the entry that held it — that is the whole
  ;; command. Without this, commit would splice the part back into the
  ;; slot it came from, which is exactly the no-op it is not.
  :commit-scope entry
  ;; A relation under point is raised whole, like any other node: there
  ;; is no per-side reading of \"keep only this\", and mapping would
  ;; rebuild a relation the command means to leave untouched.
  :map -1
  (commit expr))

(defvar maf-undo--chain-point nil
  "Point snapshot saved by the last `maf-undo'/`maf-redo' in a chain.
Holds where point stood just before that command changed the buffer —
i.e. its position in the state the next chained undo/redo returns to.")

(defun maf--undo-redo (fn n)
  "Run undo/redo FN with N, managing point across undo/redo chains.
In an uninterrupted run of `maf-undo'/`maf-redo' commands, each command
restores the point snapshot its predecessor saved: that snapshot was
taken in the very state this command returns to, so toggling undo/redo
bounces point along with the stack.

Entering a chain with a single undo whose target is the defcmd that
just ran restores that command's own pre-command snapshot (see
`maf-undo--cmd-point'): the stack and point revert together. Otherwise
— point repositioned since, a foreign command's group on top, or a
multi-step undo — point is simply kept in place as
`maf--preserve-point' does."
  (let ((snapshot (maf--point-snapshot))
        (chained (and (memq last-command '(maf-undo maf-redo))
                      maf-undo--chain-point))
        (cmd-point (and (eq fn #'calc-undo) (= n 1)
                        maf-undo--cmd-point
                        (eq (nth 0 maf-undo--cmd-point) calc-undo-list)
                        (= (nth 1 maf-undo--cmd-point) (point))
                        (nth 2 maf-undo--cmd-point))))
    (cond (chained
           (funcall fn n)
           (maf--point-restore maf-undo--chain-point))
          (cmd-point
           (funcall fn n)
           (maf--point-restore cmd-point))
          (t (maf--preserve-point (funcall fn n))))
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
