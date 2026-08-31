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
(declare-function calcFunc-vcompl "calc-vec")
(declare-function calcFunc-reduce "calc-map")
(declare-function calcFunc-rreduce "calc-map")
(declare-function calcFunc-accum "calc-map")
(declare-function calcFunc-raccum "calc-map")
(declare-function calcFunc-apply "calc-map")
(declare-function calcFunc-outer "calc-map")
(declare-function calcFunc-inner "calc-map")
(declare-function math-calcFunc-to-var "calc-ext")
(declare-function calc-default-formula-arglist "calc-prog")
(defvar math-arglist)   ; calc-prog's, filled by the arglist walker
(declare-function calcFunc-div "calc-arith")
(declare-function calcFunc-nrat "calc-poly")
(declare-function calcFunc-expand "calc-poly")
(declare-function math-simplify "calc-alg")
(declare-function math-matrixp "calc-ext")
(declare-function calc-undo "calc-undo")
(declare-function calc-redo "calc-undo")
(declare-function math-looks-negp "calc-misc")
(declare-function calc-push "calc-ext")
(declare-function calc-push-list "calc-ext")
(declare-function calcFunc-pfloat "calc-stuff")
(declare-function calc-clear-command-flag "calc-ext")
(declare-function calc-pi "calc-math")
(declare-function calc-roll-down "calc-misc")
(declare-function calc-locate-cursor-element "calc-yank")
(declare-function calc-yank-internal "calc-yank")
(declare-function calc-del-selection "calc-sel")
(declare-function calc-clear-selections "calc-sel")
;; Calc's fancy-prefix dispatch (K, I, H, O), advised below; the prefix
;; setter itself carries maf's map flag (M).
(declare-function calc-fancy-prefix-other-key "calc-ext")
(declare-function calc-fancy-prefix "calc-ext")
(declare-function calc-unread-command "calc")
(declare-function calc-change-mode "calc-mode")
(declare-function calc-reset "calc-ext")
;; The module system is optional; `maf--reset-calc' calls this only when
;; it is loaded, to re-apply the module list across a reset.
(declare-function maf-modules-apply "maf-module")
;; Calc's own, for the recovery path in `maf--reset-calc'.
(declare-function calc-mode-var-list-restore-default-values "calc")
;; Defined in maf.el, which loads this file; the reset commands read
;; and restore it around `calc-reset'.
(defvar maf-mode)
(declare-function maf-mode "maf")
;; The edit module's, for the paren keys' home fallback
;; (`maf--goto-side'): with the module on they open a blank vector
;; entry at home, as its own binding on "(" did before the motions
;; took the keys.
(defvar maf-use-edit-mode)
(declare-function maf-edit-add-vector "maf-edit")
(declare-function calc-normal-language "calc-lang")
(declare-function calc-big-language "calc-lang")
(declare-function math-solve-eqn "calcalg2")
(declare-function math-is-polynomial "calc-alg")
(declare-function math-expr-subst "calc-alg")
(declare-function math-expr-contains "calc-alg")
(declare-function calc-find-selected-part "calc-sel")
(declare-function calc-prepare-selection "calc-sel")
(declare-function calc-change-current-selection "calc-sel")
(declare-function calc-commute-left "calcsel2")
(declare-function calc-commute-right "calcsel2")
(declare-function calc-auto-selection "calc-sel")
(declare-function calc-find-assoc-parent-formula "calc-sel")
(declare-function calc-find-parent-formula "calc-sel")
(declare-function calc-replace-sub-formula "calc-sel")
(declare-function calc-unselect "calc-sel")
(declare-function calc-sel-jump-equals "calcsel2")
(declare-function calc-var-value "calc-ext")
(declare-function calc-recall "calc-store")
(declare-function math-format-value "calc")
;; Calc's JumpRules holder: the symbol `calc-JumpRules' until first use,
;; then the parsed rule set cached in its place by `calc-var-value'.
(defvar var-JumpRules)
(declare-function calcFunc-factor "calc-poly")
(declare-function calcFunc-roots "calcalg2")
(declare-function calcFunc-sub "calc-arith")
(declare-function math-evaluate-expr "calc-ext")
(declare-function calc-is-assignments "calc-store")
(declare-function math-compose-expr "calccomp")
(declare-function math-compose-vector "calccomp")
(declare-function math-comp-first-char "calccomp")
(declare-function math-tex-expr-is-flat "calc-lang")
(declare-function math-build-call "calc-map")
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
    (commit (maf--literal (calcFunc-mul arg quotient)))))

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
        (commit (maf--literal (calcFunc-mul factor quotient)))))))

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
  x        =>  -x + 180"
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
  x        =>  -x + 90"
  :arity unary
  :prefix "comp"
  (commit (maf--turn-complement expr '(frac 1 4))))

(maf-defcmd mafcmd-hypot (expr arg commit)
  "Take the hypotenuse of a right triangle with the top-of-stack leg.

  3 with 4  =>  5

The resolved expression and the argument are the two legs; the result is
the hypotenuse, sqrt(a^2 + b^2). `mafcmd-cath' (f l) is the inverse and
reads its operands in the same order, and each routes to the other under
the Inverse flag — calc leaves I f h unbound.

What it applies is maf's own `maf--hypot', not `calcFunc-hypot', which
answers only when both legs pass `Math-scalarp' and otherwise hands back
an inert hypot(sqrt(3), 1); here a radical leg reduces and a symbolic one
stays written out as a formula that still composes. Exact operands keep
an exact answer while a float in either evaluates numerically; see
`maf--hypot'. Point picks the target as usual: a sub-formula at point,
each side of an equation, stack level 2 at home; the top entry is always
the argument, popped on commit.

  5 with 12       =>  13
  2 with 1        =>  sqrt(5)
  sqrt(3) with 1  =>  2
  1.5 with 2      =>  2.5
  a with b        =>  sqrt(a^2 + b^2)
  5 with 0        =>  5            (degenerate: the leg itself)"
  :arity binary
  :prefix "hypot"
  :inverse mafcmd-cath
  (commit (maf--hypot expr arg)))

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
  x     =>  sqrt(-x^2 + 1)
  2     =>  sqrt(3) i    (leg past the hypotenuse)"
  :arity unary
  :prefix "ucth"
  (commit (maf--cath 1 expr)))

(maf-defcmd mafcmd-abs (expr _arg commit)
  "Replace the resolved expression with its absolute value.

  -5  =>  5

A vector is read as its norm — calc's own overloading of abs, sqrt of
the summed squared magnitudes of the entries. Calc answers the
two-element [2, sqrt(3)] with an inert hypot(2, sqrt(3)) where the
same entries one longer give sqrt(7); here every length takes the
general recipe, so both give sqrt(7), and exact entries keep an exact
answer while a float in any evaluates numerically — see `maf--abs'.
A symbolic entry is assumed real, giving the textbook form; turn
`maf-abs-assume-real' off for the complex-safe abssqr form. Scalars
are calc's own `calcFunc-abs' untouched. Point picks the target as
usual: a sub-formula at point, each side of an equation, the top
entry at home.

  [3, 4]        =>  5
  [2, sqrt(3)]  =>  sqrt(7)
  [2, 1]        =>  sqrt(5)
  [(3, 4), 0]   =>  5
  [a, b]        =>  sqrt(a^2 + b^2)
  [a, b]        =>  sqrt(abssqr(a) + abssqr(b))   (option off)
  [0.6, 0.8]    =>  1.
  (3, 4)        =>  5    (complex modulus)
  x             =>  abs(x)"
  :arity unary
  :prefix "abs"
  (commit (maf--abs expr)))

(maf-defcmd mafcmd-commute (expr _arg commit)
  "Swap the first two operands of the resolved expression.

  a + b  =>  b + a

The swap preserves the value wherever the operator lets it: a sum or
product just reorders, and a subtraction or division carries the
second operand across as its inverse — negated into a sum, made a
reciprocal in a product — folding it back into the operator on the
return trip, so commuting twice restores the original. A binary
relation keeps its meaning: the sides swap and the operator's
direction reverses with them. Heads with no compensating form — a
power, a function call, a vector — swap structurally as written,
nothing simplifies, and operands past the second stay in place. With
nothing to swap — an atom, a unary call, an interval — the
expression commits unchanged. Point picks the target as usual: a
sub-formula at point, the two sides of a relation entry, the top
entry at home.

  a - b        =>  -b + a        (value kept: never b - a)
  -b + a       =>  a - b         (the inverse folds back: round trip)
  a - (b + c)  =>  -(b + c) + a  (crosses intact, and still round-trips)
  a / b        =>  (1 / b) a
  2 (3 + x)    =>  (3 + x) 2     (no distribution)
  log(x, b)    =>  log(b, x)
  x < y        =>  y > x         (direction reverses: never y < x)"
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
           ;; Subtraction and division: the second operand crosses to
           ;; the front as its inverse, so the value is preserved —
           ;; a - b gives -b + a, a / b gives (1 / b) a. The negation is
           ;; a literal neg marker, never math-neg: math-neg rewrites
           ;; compounds (-(b + c) into -b - c) beyond the fold's reach,
           ;; and any eager folding loses a degenerate subtrahend — a
           ;; zero, a negative, an already-negated term, all possible
           ;; with simplification off. The marker costs nothing on the
           ;; common shapes ((neg 2) still prints as -2), and only an
           ;; untouched marker lets the fold below reverse every case.
           ((and (eq (car-safe expr) '-) (= (length expr) 3))
            (list '+ (list 'neg (nth 2 expr)) (nth 1 expr)))
           ((and (eq (car-safe expr) '/) (= (length expr) 3))
            (list '* (list '/ 1 (nth 2 expr)) (nth 1 expr)))
           ;; The mirror images: a neg marker, a negative number, or a
           ;; reciprocal leading a sum or product folds back into the
           ;; operator when the swap carries it to second place, so
           ;; commuting is a round trip (-b + a back to a - b, -2 + a
           ;; back to a - 2) rather than a literal a + -b. Only the
           ;; marker unfolds cons-exactly; a sum led by a bare negative
           ;; number (built elsewhere — commuting emits markers) settles
           ;; after one commute into the marker orbit, identical in
           ;; display but not in cons.
           ((and (eq (car-safe expr) '+) (= (length expr) 3)
                 (let ((f (nth 1 expr)))
                   (or (eq (car-safe f) 'neg)
                       (and (Math-realp f) (Math-negp f)))))
            (let ((f (nth 1 expr)))
              (list '- (nth 2 expr)
                    (if (eq (car-safe f) 'neg) (nth 1 f) (math-neg f)))))
           ((and (eq (car-safe expr) '*) (= (length expr) 3)
                 (let ((f (nth 1 expr)))
                   (and (eq (car-safe f) '/) (= (length f) 3)
                        (eq (nth 1 f) 1))))
            (list '/ (nth 2 expr) (nth 2 (nth 1 expr))))
           ((and (not (Math-primp expr))
                 (not (eq (car expr) 'intv))
                 (>= (length expr) 3))
            (append (list (car expr) (nth 2 expr) (nth 1 expr))
                    (nthcdr 3 expr)))
           (t expr))))

(defun maf--anchor-offset-on-node (m node)
  "Point's character offset into NODE's rendering, or nil.
NODE is a sub-formula of the entry at stack level M, read before a
rewrite so the offset can be replayed against the moved node
afterwards (see `maf--anchor-on-node'). nil when point is outside
NODE's rendering, or the entry does not render flat.

`calc-prepare-selection' sets `calc-keep-selection', which the commands
that call this bind around their own rewrite; the binding here keeps
the probe from leaking that flag past them."
  (ignore-errors
    (let ((calc-keep-selection calc-keep-selection))
      (calc-prepare-selection m)
      (maf--comp-node-point-offset node))))

(defun maf--anchor-on-node (m node &optional offset)
  "Put point on NODE within the entry at stack level M; nil if not found.
For the commands that hand a rewrite to calc and then want point to
follow the term it moved. NODE is matched by identity in the freshly
rewritten entry, so it lands only where the rewrite reused the same
cons — true of an associative shift within a + or * chain, false once
a - or / crossing wraps the term in a fresh neg/reciprocal. Callers
fall back to a positional restore on nil.

OFFSET, from `maf--anchor-offset-on-node' before the rewrite, keeps the
character of NODE point was on rather than pulling it back to NODE's
first character. The term travels whole, so every grip on it survives
the trip: from the = of an element of [h = 0, p = -4, k = 0] point is
on that = wherever the element lands, and from the 2 of [a, b, c12] on
that 2 — not on the p or the c. Without one, the start of NODE's
rendering is the only placement it names."
  (ignore-errors
    (calc-prepare-selection m)
    (when-let ((pos (or (and offset (maf--comp-node-offset-pos node offset))
                        (maf--comp-node-start-pos node))))
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
value — sums and products commute, and calc flips the sign crossing a -
or the reciprocal crossing a / — or be an element of a vector, whose
order is the vector's to give: the element moves through its neighbors,
clamped at the ends. Any other parent is left untouched, because
reordering its operands would change the value — a ^ (x^2 would become
2^x), a vector concatenation, a function's arguments — or, for a relation,
would reverse it (a < b to b < a, not b > a; swapping a relation's sides
with the direction flip that keeps it true is `mafcmd-commute' (O)).

With no such term under point — at home, on a whole entry, on a lone
term, or on a term whose parent is not + - * / or a vector — the command
does nothing rather than signaling calc's \"No term is selected\"."
  (maf--with-calc-buffer
    (let ((m (calc-locate-cursor-element (point))))
      (when (> m 0)
        (let* ((entry  (calc-top m 'entry))
               (expr   (car entry))
               (sel    (ignore-errors (calc-auto-selection entry)))
               ;; Read before the rewrite: where in the term point was,
               ;; so it can ride along on that character rather than
               ;; being pulled to the term's first one.
               (anchor (and (consp sel) (maf--anchor-offset-on-node m sel)))
               (direct (and (consp sel)
                            (calc-find-parent-formula expr sel)))
               (parent (and (consp sel)
                            (calc-find-assoc-parent-formula expr sel))))
          (cond
           ;; A vector element: shift its position. Calc has no rewrite
           ;; for this — its commute knows only arithmetic chains — so
           ;; the reorder is maf's own list surgery, sharing the
           ;; arithmetic branch's point-follow and undo shape. The
           ;; moved element keeps its cons, so the anchor finds it.
           ((eq (car-safe direct) 'vec)
            (let* ((elems (cdr direct))
                   (idx (- (length elems) (length (memq sel elems))))
                   (delta (if (eq dir 'left) (- arg) arg))
                   (new-idx (min (max (+ idx delta) 0)
                                 (1- (length elems)))))
              ;; Already at the end it is pushed toward: nothing to do,
              ;; as with calc's "term is already leftmost".
              (unless (= new-idx idx)
                (let* ((rest (remq sel elems))
                       (new (calc-replace-sub-formula
                             expr direct
                             (cons 'vec (append (seq-take rest new-idx)
                                                (list sel)
                                                (nthcdr new-idx rest)))))
                       (snapshot (maf--point-snapshot))
                       (calc-keep-selection nil))
                  ;; One undoable unit, as in the selection commands.
                  (calc-wrapper
                   (calc-pop-push-record-list 1 "cmut" (list new)
                                              m (list nil)))
                  (or (maf--anchor-on-node m sel anchor)
                      (maf--point-restore snapshot))
                  (maf--undo-record-cmd-point snapshot)))))
           ;; An arithmetic chain, where calc's shift is
           ;; value-preserving. Every other binary parent — ^, |
           ;; (concat), a relation, a function call — would have its
           ;; operands reordered by calc without regard to meaning, so
           ;; fall through to nothing.
           ((memq (car-safe parent) '(+ - * /))
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
              (or (maf--anchor-on-node m sel anchor)
                  (maf--point-restore snapshot))
              ;; A single undo reverts point along with the stack.
              (maf--undo-record-cmd-point snapshot)))))))))

(defun maf-commute-left (arg)
  "Move the term under point one place left through its associative chain.

  a + b + c|  =>  a + c| + b   (point on c)

Point selects the term as usual — the sub-formula under the cursor — and
follows it as it moves, keeping the character of it that it had: from
the = of an element of [h = 0, p =| -4, k = 0] point is on that = once
the element has moved, not back on its p.  The shift respects the
operators it crosses: a term moved left past a minus becomes an addition
of its negation, past a division a multiplication by its reciprocal, so
the value is preserved.
Repeat to walk the term further left; with the entry below the top, the
lower entry is acted on in place.

An element of a vector shifts its position the same way, the order
being the vector's own to give, and the walk stops at the ends.  A
composite element moves whole from its operator or comma — the comma
of [3, 4] moves that row.

  [a, b|, c]  =>  [b|, a, c]

A numeric prefix N shifts N places (a negative N shifts right).  At home,
on a whole entry, or on a term outside any + or * chain or vector —
nothing to move — the command does nothing.

  a - b|      =>  -b| + a
  a / b|      =>  (1/b)| a"
  (interactive "p")
  (maf--commute 'left arg))

(defun maf-commute-right (arg)
  "Move the term under point one place right through its associative chain.

  a| + b + c  =>  b + a| + c   (point on a)

The mirror of `maf-commute-left': point selects the term under the cursor
and follows it right, with the same sign handling when it crosses a minus
or a division, and the same positional shift for a vector's element
([a|, b, c] gives [b, a|, c]).  A numeric prefix N shifts N places (a
negative N shifts left).  At home, on a whole entry, or on a term
outside any + or * chain or vector, the command does nothing."
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

(defconst maf--pinf '(var inf var-inf)
  "Calc's positive infinity, as intervals spell their open ends.")

(defconst maf--minf '(neg (var inf var-inf))
  "Calc's negative infinity, as intervals spell their open ends.")

(defun maf--interval-complement (intv)
  "The complement of INTV as calc's set: the rays beyond its ends.
What `calcFunc-vcompl' answers for constant endpoints — two rays as a
vector, a single ray bare when an end already sits at its infinity,
the empty set for the whole line — but built from the mask alone, so
a symbolic endpoint complements too: [-x .. x] has nothing constp
about it and still owns the rays beyond x and -x."
  (let ((mask (nth 1 intv))
        (lo (nth 2 intv))
        (hi (nth 3 intv))
        (rays nil))
    (unless (equal hi maf--pinf)
      (push (list 'intv (if (zerop (logand mask 1)) 3 1) hi maf--pinf)
            rays))
    (unless (equal lo maf--minf)
      (push (list 'intv (if (zerop (logand mask 2)) 3 2) maf--minf lo)
            rays))
    (cond ((null rays) (list 'vec))
          ((null (cdr rays)) (car rays))
          (t (cons 'vec rays)))))

(defun maf--rays-complement (set)
  "The interval SET's two rays bound, or nil when SET is another shape.
The inverse of `maf--interval-complement's two-ray answer, read off
the masks the same way, so a symbolic set complements back and the
key undoes itself; nil hands any other set to `calcFunc-vcompl'."
  (pcase set
    (`(vec (intv ,m1 ,lo1 ,hi1) (intv ,m2 ,lo2 ,hi2))
     (and (equal lo1 maf--minf)
          (equal hi2 maf--pinf)
          (list 'intv
                (+ (if (zerop (logand m1 1)) 2 0)
                   (if (zerop (logand m2 2)) 1 0))
                hi1 lo2)))))

(maf-defcmd mafcmd-neg (expr _arg commit)
  "Negate the resolved expression; an interval complements instead.

  2 x - 3    =>  3 - 2 x
  [-5 .. 5]  =>  [[-inf .. -5), (5 .. inf]]

An interval reads as a set here, and the sign flip that would only
mirror it gives way to the complement: the rays beyond its ends,
open where the interval was closed. The rays are built from the
interval's own shape (`maf--interval-complement'), so a symbolic
endpoint complements as readily as a constant one. A vector whose
elements are all intervals is the same set in pieces, so it
complements too, and the key undoes itself; any other vector negates
elementwise, as every other expression negates arithmetically. Point
picks the target as usual: a sub-formula at point, each side of an
equation, the top entry at home.

  [2 .. 3)                    =>  [[-inf .. 2), [3 .. inf]]
  [-x .. x]                   =>  [[-inf .. -x), (x .. inf]]
  [[-inf .. -5), (5 .. inf]]  =>  [-5 .. 5]    (the complement back)
  [1, 2, 3]                   =>  [-1, -2, -3] (not a set: elementwise)"
  :arity unary
  :prefix "neg"
  (commit (cond
           ((eq (car-safe expr) 'intv)
            (maf--interval-complement expr))
           ((and (eq (car-safe expr) 'vec)
                 (cdr expr)
                 (cl-every (lambda (el) (eq (car-safe el) 'intv))
                           (cdr expr)))
            (or (maf--rays-complement expr)
                (condition-case nil (calcFunc-vcompl expr)
                  (wrong-type-argument
                   (user-error "A symbolic set beyond two rays has no complement here")))))
           (t (math-neg expr)))))

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

(maf-defcmd mafcmd-float-frac (expr _arg commit)
  "Toggle the resolved expression between floats and fractions.

  0.75 x + 2  =>  3:4 x + 2   (floats present: toward exact)
  3:4 x + 2   =>  0.75 x + 2  (fractions only: toward floats)

With the Inverse flag, `mafcmd-float' runs instead — fractions to
floats, whatever the target holds. With the Hyperbolic flag,
`mafcmd-float-all' floats pervasively, integers included.

Any float in the target decides the direction: floats convert to
fractions, exactness winning when both kinds are present, and only a
target with no floats floats its fractions. The kind landed on is
echoed. A numeric prefix argument gives the tolerance when the
conversion goes toward fractions, as in `mafcmd-frac'. A target with
neither floats nor fractions refuses. Point picks the target as
usual: a sub-formula at point, the top entry at home — an equation is
taken whole, the direction decided once for both sides, so they
cannot flip opposite ways.

  0.5 y + 1:4 x      =>  1:2 y + 1:4 x   (mixed: exactness wins)
  0.5 = 1:2          =>  1:2 = 1:2       (one direction for both sides)
  C-u 3 3.14159      =>  22:7            (3 significant figures)
  0.75| x + 1:2      =>  3:4 x + 1:2     (sub-formula at point)"
  :arity unary
  :prefix "ff"
  :map -1
  :inverse mafcmd-float
  :hyperbolic mafcmd-float-all
  (let* ((direction (cond ((maf--contains-type-p expr 'float) 'frac)
                          ((maf--contains-type-p expr 'frac) 'float)
                          (t (user-error
                              "No floats or fractions to toggle"))))
         (convert (if (eq direction 'frac)
                      (let ((tol (prefix-numeric-value
                                  (or current-prefix-arg 0))))
                        (lambda (side)
                          (math-normalize
                           (list 'calcFunc-pfrac side tol))))
                    #'maf--float-fracs)))
    ;; A relation converts side by side, its head untouched: one
    ;; normalize over the whole would evaluate a relation whose sides
    ;; the conversion made equal (0.5 = 1:2 must give 1:2 = 1:2, not
    ;; 1). The direction is still the one decision above.
    (commit (if (maf--relation-p expr)
                (cons (car expr) (mapcar convert (cdr expr)))
              (funcall convert expr)))
    (message "Toggled to %s"
             (if (eq direction 'frac) "fractions" "floats"))
    ;; The conversion's inner routines can raise the clear-message
    ;; flag, whose epilogue in `calc-do' blanks the echo area on the
    ;; way out; stand it down so the direction stays said.
    (calc-clear-command-flag 'clear-message)))

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

(defvar maf--quick-variable-path nil
  "Path to the sub-formula `mafcmd--quick-variable-join' joins onto.
A `maf--node-path' path into the entry, from `maf-quick-variable'.")

(maf-defcmd mafcmd--quick-variable-mul (expr _arg commit)
  "Apply `maf--quick-variable' to the resolved expression.
Internal: `maf-quick-variable' reads the variable, binds it, and
dispatches here when point names an expression rather than sitting
just past one. A target the user pointed at — a selection, a region,
the sub-formula under point — that is itself a variable is
overwritten: naming a name means renaming it. Anything else is
multiplied, variable on the left; a target reached from a margin is
never renamed, a margin being where the entry is taken whole rather
than a name pointed at."
  :arity unary
  :prefix "qvar"
  :targets-var maf-quick-variable-targets
  (commit (if (and (eq (car-safe expr) 'var)
                   (memq maf-target '(subexpr selection region)))
              maf--quick-variable
            (calcFunc-mul maf--quick-variable expr))))

(maf-defcmd mafcmd--quick-variable-join (expr _arg commit)
  "Join `maf--quick-variable' onto the sub-formula at `maf--quick-variable-path'.
Internal: `maf-quick-variable' dispatches here when point sits just
past a sub-formula, where the gesture is to carry on writing rather
than to name what is there. The variable multiplies that sub-formula
on its right, in place; the rest of the entry is untouched, so nothing
else re-simplifies. The entry is the subject whole — a relation
included, since the variable lands at one place inside it rather than
once per side."
  :arity unary
  :prefix "qvar"
  :scope entry
  :map -1
  (commit (maf--splice-path
           expr maf--quick-variable-path
           (lambda (node) (calcFunc-mul node maf--quick-variable)))))

(defun maf--quick-variable-join-path ()
  "Path for `mafcmd--quick-variable-join', or nil to target normally.
Non-nil when point sits just past a sub-formula (`maf--path-just-past-point')
and no narrowing gesture this command honors is in play: a region or a
calc selection is a deliberate naming of what to act on, and outranks
the position of point within it."
  (and (not (and (use-region-p)
                 (memq 'region maf-quick-variable-targets)))
       (not (and (maf--sel-any-p)
                 (memq 'selection maf-quick-variable-targets)))
       (maf--path-just-past-point)))

(defun maf-quick-variable ()
  "Read a letter and apply it as a variable, contextually.

  y on |x         =>  y            (a name pointed at is renamed)
  y on x|         =>  x y          (past it, the variable joins on)
  y on a = x| + 2 =>  a = x y + 2
  y on x + 2|     =>  x + 2 y
  y on x +| 2     =>  y (x + 2)

At home with no selection active, the variable is pushed as a new
stack entry instead.

Point just past a sub-formula — exactly at the end of its text — joins
the variable onto it, multiplied on its right, leaving the rest of the
entry alone. Where several formulas end at point the smallest one
takes it, so at the end of x + 2 the variable joins the 2 rather than
the sum, and at the end of a relation it joins the tail of the right
side rather than landing once per side.

Anywhere else the position names a target instead: the selection, the
region, the sub-formula under point (its operator glyph names the
whole formula), each side of an equation, the whole entry from a
margin. A target that is itself a variable is replaced by the new
one — naming a name means renaming it — but only where the user
pointed at that name; a margin is not a name pointed at, so nothing
reached from one is ever renamed. Every other target is multiplied by
the variable, on the left.

Any letter is a valid variable; anything else aborts."
  (interactive)
  (let ((char (read-char-from-minibuffer "Variable: ")))
    (unless (or (<= ?a char ?z) (<= ?A char ?Z))
      (user-error "Invalid variable '%c'; must be a letter" char))
    (let ((var (list 'var
                     (intern (char-to-string char))
                     (intern (concat "var-" (char-to-string char)))))
          (path (maf--quick-variable-join-path)))
      (cond
       ((and (maf--at-home-p) (not (maf--sel-any-p)))
        (calc-wrapper (calc-push var)))
       (path
        (let ((maf--quick-variable var)
              (maf--quick-variable-path (cdr path)))
          (mafcmd--quick-variable-join)))
       (t
        (let ((maf--quick-variable var))
          (mafcmd--quick-variable-mul)))))))

(maf-defcmd mafcmd--pi-mul (expr _arg commit)
  "Multiply the resolved expression by the symbolic constant pi.
Internal: `maf-pi' dispatches here when point is on an expression;
the Inverse and Hyperbolic flags route to the sibling constants. The
target is multiplied, constant on the right — a variable target too,
never replaced."
  :arity unary
  :prefix "pi"
  :targets-var maf-pi-targets
  :inverse mafcmd--gamma-mul
  :hyperbolic mafcmd--e-mul
  :inverse-hyperbolic mafcmd--phi-mul
  (commit (calcFunc-mul expr '(var pi var-pi))))

(maf-defcmd mafcmd--e-mul (expr _arg commit)
  "Multiply the resolved expression by the symbolic constant e.
Internal: the Hyperbolic route of `maf-pi'. See `mafcmd--pi-mul'."
  :arity unary
  :prefix "e"
  :targets-var maf-pi-targets
  (commit (calcFunc-mul expr '(var e var-e))))

(maf-defcmd mafcmd--gamma-mul (expr _arg commit)
  "Multiply the resolved expression by Euler's constant gamma.
Internal: the Inverse route of `maf-pi'. See `mafcmd--pi-mul'."
  :arity unary
  :prefix "gmma"
  :targets-var maf-pi-targets
  (commit (calcFunc-mul expr '(var gamma var-gamma))))

(maf-defcmd mafcmd--phi-mul (expr _arg commit)
  "Multiply the resolved expression by the golden ratio phi.
Internal: the Inverse Hyperbolic route of `maf-pi'. See
`mafcmd--pi-mul'."
  :arity unary
  :prefix "phi"
  :targets-var maf-pi-targets
  (commit (calcFunc-mul expr '(var phi var-phi))))

(defun maf-pi ()
  "Multiply the target by pi, contextually.

  |x + 2  =>  x pi + 2

With the Hyperbolic flag the constant is e, with Inverse it is gamma
(Euler's constant), and with both it is phi (the golden ratio).

At home with no selection active, the command stays `calc-pi': the
constant is pushed as a new stack entry, a float under the current
precision unless Symbolic mode is on. Anywhere else the target is
multiplied by the symbolic constant, on the right: the selection, the
sub-formula at point, each side of an equation, the whole entry from
its margin. Unlike `maf-quick-variable', a target that is itself a
variable is multiplied like anything else, never replaced.

  2| x       =>  (2 pi) x        (the product goes in as one factor)
  x = 3 y    =>  x pi = 3 y pi   (each side, from the entry's margin)"
  (interactive)
  ;; The map flag is an explicit request to map, so it outranks the
  ;; home push: M routes to the worker even at home.
  (if (and (maf--at-home-p) (not (maf--sel-any-p)) (not maf-map-flag))
      (call-interactively #'calc-pi)
    (call-interactively #'mafcmd--pi-mul)))

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

;;; Nudging

(defun maf--nudge-amount ()
  "The step for `mafcmd-increment', from the prefix argument.
One when no prefix was given."
  (if current-prefix-arg (prefix-numeric-value current-prefix-arg) 1))

(maf-defcmd mafcmd-increment (expr _arg commit)
  "Add one to the target, contextually.

  x + 5|  =>  x + 6

Plain arithmetic, not calc's f ] — a float steps by 1, not by its last
representable digit. The usual targets: the sub-formula at point (a
constant under the cursor nudges in place), the selection, each side
of an equation, the whole entry from its margin — where a vector steps
elementwise. A numeric prefix gives the step, so C-u 5 adds 5 and a
negative prefix walks the other way.

`mafcmd-decrement' (<) is the same step downward."
  :arity unary
  :prefix "incr"
  (commit (math-add expr (maf--nudge-amount))))

(maf-defcmd mafcmd-decrement (expr _arg commit)
  "Subtract one from the target, contextually.
The downward twin of `mafcmd-increment' (>) — see there."
  :arity unary
  :prefix "decr"
  (commit (math-sub expr (maf--nudge-amount))))

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

Clears the stack, calc's undo and redo lists, and the trail, restores
the mode settings saved in `calc-settings-file', then re-reads the
rest of that file (see `maf--reset-load-settings'). What survives is
what lives outside the calc buffer: stored variables, the formula
library, the kill ring — and the maf stack history, which is a log
of what happened rather than part of the session, and stays browsable
across the reset. `maf-history-clear' empties it separately.

With a prefix argument DEFAULTS, restore calc's factory default modes
instead of the saved ones — and then leave the settings file alone,
since loading it would immediately put the saved modes back and make
the prefix do nothing.

Nothing here is undoable: the undo list is one of the things cleared."
  (interactive "P")
  (maf--with-calc-buffer
    (maf--reset-calc (if defaults 0 nil))
    (maf--reset-clear-trail)
    (message (if (and (not defaults) (maf--reset-load-settings))
                 "Calc reset; settings reloaded"
               "Calc reset"))))

(defun maf-reset-settings (&optional defaults)
  "Reset calc's modes and display settings, keeping the stack.

The other half of `maf-reset': restores the mode settings saved in
`calc-settings-file' and re-reads the rest of that file, but leaves
the stack, its selections, and the history exactly as they are. The
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

(defun maf-end-of-line-bounce ()
  "Move point to the end of the line, or bounce to the entry's start.

  2:  6 x| + 12   =>  2:  6 x + 12|
  2:  6 x + 12|   =>  2:  |6 x + 12

Already at the end, point crosses to the other extreme instead: the
beginning of the entry, right after the line-number prefix, where
`maf-beginning-of-entry' lands. One key thus alternates between the
two ends of the line."
  (interactive)
  (if (eolp)
      (maf-beginning-of-entry)
    (end-of-line)))

(defun maf-backward-char (&optional n)
  "Move point back N characters; from home, back into the stack.

  1:  x = y        1:  x = y|
      .|       =>      .

At home there is no entry text behind point, and the press puts
point at the end of the entry on level 1 — one key back into the
newest entry, where plain `backward-char' would crawl there a column
at a time. Everywhere else, and on an empty stack, it is
`backward-char' exactly, prefix argument included."
  (interactive "^p")
  (if (and (<= (calc-locate-cursor-element (point)) 0)
           (> (calc-stack-size) 0))
      (goto-char (1- (save-excursion (calc-cursor-stack-index 0)
                                     (point))))
    (backward-char n)))

(defconst maf--noun-regexp
  (concat
   ;; A radix number, whose # would otherwise split it in two: 16#ff.
   "[0-9]+#[0-9a-zA-Z]+"
   ;; A plain number: digits, an optional fractional part (calc prints
   ;; the float 1.0 as \"1.\", so the digits after the point are
   ;; optional too), an optional exponent, and the : parts a fraction
   ;; is printed with — 3:4, and 1:3:4 in mixed format.
   "\\|[0-9]+\\(?:\\.[0-9]*\\)?\\(?:e[-+]?[0-9]+\\)?\\(?::[0-9]+\\)*"
   ;; An identifier: a variable, or a function's name. A subscripted
   ;; name carries its _ along (b_1 is one noun), but no noun starts
   ;; with one — calc prints no such name, and Big language draws a
   ;; radical's overbar as a run of underscores that would otherwise
   ;; read as a variable.
   "\\|[a-zA-Z][a-zA-Z0-9_]*")
  "Regexp matching one noun in the calc display.
A noun is what a term is named or valued by: a number, a variable, or a
function's name. Operators and punctuation are what is left over, and
what the motions step across.

Matched against the rendering rather than the formula, so it is what the
motion commands can see in every language calc prints in.")

(defun maf--noun-line-positions ()
  "Return the start position of every noun on the current line, in order.
The line-number prefix is not scanned: the level number in \"2:  6 x\"
is part of the margin, not of the formula, and it is the only place a
motion by noun could stop where no term is."
  (save-excursion
    (let ((end (line-end-position))
          (found nil))
      (beginning-of-line)
      (when (looking-at " *[0-9]+: +")
        (goto-char (match-end 0)))
      (while (re-search-forward maf--noun-regexp end t)
        (push (match-beginning 0) found))
      (nreverse found))))

(defun maf--noun-position (dir)
  "Return the position of the nearest noun start in direction DIR, or nil.
DIR is 1 forward, -1 back. Strictly past point, so the noun point already
sits on is never its own answer; from inside one, the step back lands on
its start, as `backward-word' does. The scan crosses lines, over the
whole stack."
  (save-excursion
    (let ((from (point)))
      (catch 'done
        (while t
          (let* ((positions (maf--noun-line-positions))
                 (hit (if (> dir 0)
                          (seq-find (lambda (p) (> p from)) positions)
                        (seq-find (lambda (p) (< p from)) (nreverse positions)))))
            (when hit (throw 'done hit))
            (if (> dir 0)
                (progn
                  (when (>= (line-end-position) (point-max))
                    (throw 'done nil))
                  (forward-line 1)
                  ;; Every noun on the line just reached starts past this.
                  (setq from (1- (point))))
              (when (<= (line-beginning-position) (point-min))
                (throw 'done nil))
              (forward-line -1)
              (setq from (1+ (line-end-position))))))))))

(defun maf--noun-move (n)
  "Move point over N nouns, backward when N is negative.
Signals at the end of the stack, having taken the steps it could."
  (let ((dir (if (< n 0) -1 1)))
    (dotimes (_ (abs n))
      (let ((pos (maf--noun-position dir)))
        (unless pos
          (user-error "No noun %s point" (if (> dir 0) "after" "before")))
        (goto-char pos)))))

(defun maf-forward-noun (&optional n)
  "Move point to the start of the next number, variable, or function name.

  2:  |6 x + 12  =>  2:  6 |x + 12

Every stop is a place resolve names something: a function name lands
point on the call it heads, so the motion reaches the sub-formulas whose
operator is a word, not only the leaves.

  1:  |1 + sqrt(x)  =>  1:  1 + |sqrt(x)  =>  1:  1 + sqrt(|x)

What is left over is what the motion crosses: the operators and the
punctuation between the terms, and the line-number prefix — the level
number is the margin, not a term — so the walk runs from the last noun
of one entry to the first of the next. A numeric prefix N moves that
many nouns, backward when negative."
  (interactive "p")
  (maf--noun-move (or n 1)))

(defun maf-backward-noun (&optional n)
  "Move point to the start of the previous number, variable, or function name.

  2:  6 x + |12  =>  2:  6 |x + 12

The mirror of `maf-forward-noun', over the same stops. From inside a
noun the step lands on its own start, as `backward-word' does, so the
two motions retrace each other."
  (interactive "p")
  (maf--noun-move (- (or n 1))))

(defun maf--operand-positions (m)
  "Sorted buffer positions of the operand stops in the entry at level M.
The entry is read column by column and every position handed to
resolve, so each stop is a place `calc-find-selected-part' already
answers with the node the motion advertises there, rather than a column
computed from the composition and trusted to resolve to it. Asking
rather than computing is what lets the walk work in every rendering:
the composition carries the formula's shape but a flat character count
is only an address when the entry is drawn as one row of glyphs, and
Big language draws a quotient as three (`math-comp-is-flat'), a matrix
as one row per line, a radical with its overbar above.

One stop per node, at the landing `maf--up-pick-landing' picks out of
the positions naming it — the rule the climb lands by, so the walk and
`maf-up-expression' agree by construction rather than by two
computations arriving at the same column.

nil when the entry offers no stop: a bare atom is all noun
\(`math-primp'), and the nouns are `maf-forward-noun''s to walk. A node
the rendering gives point no way to name — a matrix row, whose brackets
calc tags to the matrix itself — offers none either, having nowhere to
be named at."
  (calc-prepare-selection m)
  (let ((region (maf--up-entry-region m))
        ;; (NODE . POSITIONS) per operation met, positions reversed.
        (nodes nil))
    (save-excursion
      (goto-char (car region))
      (while (< (point) (cdr region))
        (let ((node (ignore-errors (calc-find-selected-part))))
          (when (and node (not (math-primp node)))
            (let ((cell (assq node nodes)))
              (if cell
                  (push (point) (cdr cell))
                (push (list node (point)) nodes)))))
        (forward-char 1)))
    (sort (delq nil
                (mapcar (lambda (cell)
                          (maf--up-pick-landing (nreverse (cdr cell))
                                                (car cell)))
                        nodes))
          #'<)))

(defun maf--operand-position (dir)
  "Return the position of the nearest operand stop in direction DIR, or nil.
DIR is 1 forward, -1 back. Strictly past point, so the stop point
already sits on is never its own answer. The scan is confined to the
entry point sits in: it never runs on into the entry below or above,
so each entry's first and last stops are where the walk stops asking.
nil at home as well, there being no entry there to walk."
  (let* ((from (point))
         (m (calc-locate-cursor-element from)))
    (when (and (>= m 1) (<= m (calc-stack-size)))
      (let ((stops (maf--operand-positions m)))
        (if (> dir 0)
            (seq-find (lambda (p) (> p from)) stops)
          (seq-find (lambda (p) (< p from)) (reverse stops)))))))

(defun maf--operand-move (n)
  "Move point over N operand stops, backward when N is negative.
Signals at the entry's edge, having taken the steps it could."
  (let ((dir (if (< n 0) -1 1)))
    (dotimes (_ (abs n))
      (let ((pos (maf--operand-position dir)))
        (unless pos
          (user-error "No operand %s point in this entry"
                      (if (> dir 0) "after" "before")))
        (goto-char pos)))))

(defun maf-forward-operand (&optional n)
  "Move point to the next operand: the next operation, where resolve names it.

  2:  |6 x + 12  =>  2:  6| x + 12   (the product 6 x)
  2:  6| x + 12  =>  2:  6 x |+ 12   (the whole sum)

Every operation of the entry is one stop, the whole entry among them —
each an operand the next command could act on — at the first glyph it
renders itself: an operation at its operator, a call at its function
name, a vector at its bracket. That glyph is where resolve names the
sub-formula, the landing `maf-up-expression' picks, so a few presses
cross the entry target by target, offering every compound target once.
A juxtaposed product renders its multiplication as nothing but a
space, so its stop is that space, as in the first step above. The
parens calc prints around an operand only where precedence asks for
them are the context's rather than the operand's own glyphs, so a
parenthesized operation is named at its operator like any other:

  1:  y^2 = 3| (x - 5)  =>  1:  y^2 = 3 (x |- 5)   (the difference)

The nouns are not stops: a number or a variable is one term, and
walking those is `maf-forward-noun''s (M-f) job, so the two motions
divide the entry between them rather than covering the same columns.
An entry that is a bare atom offers no stop of its own and is crossed
whole. An entry drawn over several lines is walked like any other: in
Big language the stops run down the rendering as they run across it,
a quotient named at its bar with the numerator's own stops above it.

The walk stays inside the entry it starts in: the last operand is
where it stops asking, and it signals there rather than crossing the
line-number margin into the entry below. A numeric prefix N moves over
that many operands, backward when negative."
  (interactive "p")
  (maf--operand-move (or n 1)))

(defun maf-backward-operand (&optional n)
  "Move point to the previous operand: the operation before point.

  1:  1 + sqrt(x| y)  =>  1:  1 + |sqrt(x y)   (the sqrt call)
  1:  1 + |sqrt(x y)  =>  1:  1 |+ sqrt(x y)   (the whole sum)

The mirror of `maf-forward-operand', over the same stops — every
operation of the entry at the first glyph it renders itself, the nouns
left to `maf-backward-noun' — so the two motions retrace each other.
It stays inside its entry the same way, signalling at the first
operand rather than climbing to the entry above. A numeric prefix N
moves over that many operands, forward when negative."
  (interactive "p")
  (maf--operand-move (- (or n 1))))

(defun maf--home-drop-mark (pos)
  "Drop the mark at POS that `maf-go-home' just returned to.
The mark the trip out pushed is spent once point is back on it, so it
comes off rather than staying where point already is. The one it
displaced is restored from the ring (`push-mark' put it there), leaving
the ring as deep as it was before the round trip — unlike `pop-mark',
which rotates the spent mark to the ring's tail instead. A no-op when
the mark has moved on since, POS then being none of its business."
  (setq maf--home-mark-column nil)
  (when (and (mark t) (= (mark t) pos))
    (if mark-ring
        (let ((prev (car mark-ring)))
          (set-marker (mark-marker) (marker-position prev) (current-buffer))
          (move-marker prev nil)
          (setq mark-ring (cdr mark-ring)))
      (set-marker (mark-marker) nil))))

(defun maf--home-restore-mark-column ()
  "Put point at the column the homing trip left, when the mark lost it.
A mark is a marker, and a marker rides a push and a renumber but not a
rewrite of the entry it sits in: re-rendering deletes the text around
it and collapses it to the line's start, landing the return trip in
the line-number prefix instead of on the glyph it left. That is the
one case corrected here, from `maf--home-mark-column' — a mark still
holding a column of its own is left alone, so a rendering that shifted
sideways keeps the marker's answer rather than a stale recorded one.
The column is clamped by `move-to-column' when the rewrite left the
line shorter than it was."
  (when (and maf--home-mark-column (maf--at-line-prefix-p))
    (move-to-column maf--home-mark-column)))

(defun maf--home-dot-position ()
  "Return the buffer position of the home line's dot.
The dot sits past the line-number margin when numbering is on, at the
line's start when it is off."
  (save-excursion
    (calc-cursor-stack-index 0)
    (skip-chars-forward " ")
    (point)))

(defun maf--home-snap ()
  "Keep point on the dot whenever it is in the home section.
Point has no business anywhere else past the last stack entry — the
line's leading margin, its tail, the blank below — so a command that
leaves it there is tidied onto the dot, the one home position
\(`maf--home-dot-position'), where calc itself parks point after every
command. No mark is pushed: the spots snapped from are all a keystroke
from the dot, no journey worth returning to.

Runs on `post-command-hook' in maf calc buffers (installed by
`maf-mode'); errors are swallowed so a bad calc state can never get
the hook function disabled. Steps aside while a region is active — the
mark is the selection's anchor, point its live end, and both are
targets — and under `maf-edit-mode', whose editable text point roams
freely. Isearch is left alone mid-search, so a search can walk through
home; the snap catches up on the command that exits it."
  (ignore-errors
    (unless (or (region-active-p)
                (bound-and-true-p isearch-mode)
                (bound-and-true-p maf-edit-mode))
      (when (maf--at-home-p)
        (let ((dot (maf--home-dot-position)))
          (unless (= (point) dot)
            (goto-char dot)))))))

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

Pressed on the dot itself the key makes the return trip: point goes
back to that mark, and the mark is dropped — the ring is left as it was
before the round trip (`maf--home-drop-mark'), older marks and all, so
C-u C-SPC still walks the ones the trip found there. The trip itself
always returns to where it last left, never further back. One key
covers both legs of it: out
to home for a command that wants the whole entry, back to the
sub-formula for one that wants the term. The stack may be rewritten in
between; a mark is a marker and rides the rewrite.

At home but off the dot — the line's tail, the blank below — the press
only tidies point onto the dot. The bounce fires from the dot alone,
never by surprise from a stray spot on the row: one press to land,
a second to leave.

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
         (dot (maf--home-dot-position))
         (back (and (= from dot)
                    (not (use-region-p))
                    (maf--home-mark-position))))
    (cond
     (back
      (goto-char back)
      (maf--home-restore-mark-column)
      (maf--home-drop-mark back))
     (t
      (goto-char dot)
      ;; A press that started at home moved point at most from the tail
      ;; of the line onto the dot: no journey, nothing to mark.
      (unless (or home (use-region-p))
        (maf--mark-before-home from))))))

(defun maf--up-entry-region (m)
  "Return (BEG . END), the buffer span the entry at stack level M renders into.
END is where the entry below begins, so a rendering taller than one line
— a matrix, a Big-language fraction, an entry wrapped over several
lines — is covered whole."
  (cons (save-excursion (calc-cursor-stack-index m) (point))
        (save-excursion (calc-cursor-stack-index (1- m)) (point))))

(defun maf--up-node-position (node region)
  "Return the position in REGION where point names NODE, or nil.
Asks calc which sub-formula point would resolve to — the question
`maf--resolve-target-subexpr' asks — at each position in turn, rather
than computing NODE's place from the composition
\(`maf--comp-node-start-pos'), which is defined for flat renderings
only. Reading the rendering back through the resolver is what keeps the
landing honest in every rendering: Big language, a matrix's own lines, a
wrapped entry. It also means a node the rendering gives point no way to
name — a matrix row, whose brackets calc tags to the matrix itself —
comes back nil rather than a position that would resolve to something
else.

Of the positions that name NODE, the first non-blank one wins: those
are the glyphs NODE renders itself, and landing on the operator or
paren reads better than landing on the space before it. A juxtaposed
product renders its multiplication as nothing but a space, so blank is
all it has; then the first position stands. The parens a context puts
around NODE are none of its glyphs (`maf--comp-own-brackets-p'), so
the pair is passed over and the sum in `3 (x + 1)' is named at its
`+' — the same landing `maf--comp-landing-positions' reads off the
composition for the operand walk.

`calc-prepare-selection' must have run for the entry REGION covers."
  (maf--up-pick-landing (maf--up-naming-positions node region) node))

(defun maf--up-naming-positions (node region)
  "Positions in REGION where point resolves to NODE, in order."
  (save-excursion
    (let ((found nil))
      (goto-char (car region))
      (while (< (point) (cdr region))
        (when (eq (ignore-errors (calc-find-selected-part)) node)
          (push (point) found))
        (forward-char 1))
      (nreverse found))))

(defun maf--up-pick-landing (positions node)
  "The landing among POSITIONS, the places that name NODE, or nil.
The first non-blank position wins, the first blank one standing in when
NODE has nothing but blanks to be named by. A paren pair enclosing all
of them is the context's punctuation rather than NODE's own glyphs, and
drops out first, so a parenthesized operation is named inside its
parens: `x + 1' in `3 (x + 1)' at the `+', as it is at the top of an
entry, where nothing parenthesizes it."
  (let* ((blankp (lambda (p) (memq (char-after p) '(?\s ?\t ?\n))))
         (visible (cl-remove-if blankp positions))
         (open (car visible))
         (close (car (last visible)))
         (positions (if (and open close (/= open close)
                             (not (maf--comp-own-brackets-p node))
                             (eq (char-after open) ?\()
                             (eq (char-after close) ?\)))
                        (remq close (remq open positions))
                      positions)))
    (or (cl-find-if-not blankp positions)
        (car positions))))

(defun maf--up-step (node m)
  "Return (ANCESTOR . POSITION) one step out from NODE, or nil at the root.
The step goes to NODE's nearest ancestor in the entry at stack level M
that point can name. An ancestor the rendering leaves unnameable is
walked past rather than landed on: point is the whole of maf's
targeting, so a landing where resolve would name something other than
the node the motion advertised is worse than a longer step."
  (let ((region (maf--up-entry-region m)))
    (cl-loop for anc in (maf--resolve-ancestors (calc-top m 'full) node)
             for pos = (maf--up-node-position anc region)
             when pos return (cons anc pos))))

(defun maf-up-expression (&optional n)
  "Move point out to the sub-formula enclosing the one it is on.

  y = 2 (|x + 3)^2 - 12  =>  y = 2 |(x + 3)^2 - 12

Point lands on the enclosing formula's own first glyph — its operator,
the parens calc printed around it, its function name — which is where
resolve names that formula, so the next command acts on it. Repeat to
climb, ending at the whole entry.

A numeric prefix climbs that many levels at once.

The climb follows the formula, not the printed parentheses, so it steps
through the levels calc renders without any: out of x below, the term
x + 3 comes first, then the power, then the product. It works in every
rendering — Big language, a matrix, an entry wrapped over several lines
— since each landing is checked by asking calc what point would resolve
to there. A level the rendering gives point no way to name is skipped:
a matrix's rows are drawn with brackets calc tags to the matrix itself,
so a climb from an element lands on the whole matrix.

At the outermost formula the motion signals rather than moving: the
entry is already the subject there. So does a press at home, or at the
line prefix or end of line, where point names the whole entry to begin
with.

With a selection up on the entry, the selection is the subject rather
than point, so it climbs along with the motion and stays what the next
command acts on.

  y = 2 |(x + 3)^2 - 12  =>  y = 2 (x + 3)|^2 - 12
  y = 2 (x + 3)|^2 - 12  =>  y = 2| (x + 3)^2 - 12   (the product, whose
                                                      glyph is a space)
  y = 2| (x + 3)^2 - 12  =>  y = 2 (x + 3)^2 |- 12
  y = 2 (x + 3)^2 |- 12  =>  y |= 2 (x + 3)^2 - 12   (the whole entry)"
  (interactive "p")
  (let ((m (calc-locate-cursor-element (point))))
    (when (<= m 0)
      (user-error "No expression at point"))
    (calc-prepare-selection m)
    (let ((node (calc-find-selected-part))
          (pos nil))
      (unless node
        (user-error "Already at the whole entry"))
      (dotimes (_ (or n 1))
        (when-let* ((step (maf--up-step node m)))
          (setq node (car step)
                pos (cdr step))))
      (unless pos
        (user-error "Already at the whole entry"))
      ;; A selection outranks point when a command resolves its subject
      ;; (see `maf--resolve-context'), so a motion that left it behind
      ;; would move the cursor and change nothing. Carrying it along
      ;; keeps the one promise the command makes: what point names now
      ;; is what the next command acts on. The re-render this does
      ;; rewrites the entry's lines, so point is placed after it.
      (when (calc-top m 'sel)
        (calc-wrapper
         (calc-prepare-selection m)
         (calc-change-current-selection node))
        (calc-prepare-selection m)
        (setq pos (or (maf--up-node-position node (maf--up-entry-region m))
                      pos)))
      (goto-char pos))))

;;; Equation sides

(defun maf--side-relation (expr node)
  "Return the innermost relation of EXPR at or above NODE, or nil.
NODE itself counts: point on a relation's own operator names that
relation, and its two sides are what there is to move to. Failing
that the walk climbs, so a term inside one element of [a = 1, b = 2]
finds the equation it sits in rather than the vector around it, and
the outermost relation answers only when nothing nearer is one. A nil
NODE — point on the entry's margin, where it names the whole entry —
starts the walk at EXPR itself."
  (let ((n (or node expr)))
    ;; `calc-find-parent-formula' answers t at the root and nil for a
    ;; node EXPR does not contain; either way the loop ends on a
    ;; non-cons, which is the no-relation answer.
    (while (and (consp n) (not (maf--relation-p n)))
      (setq n (calc-find-parent-formula expr n)))
    (and (consp n) n)))

(defun maf--relation-arm (expr rel node)
  "Which arm of REL the NODE sits in: 1 for left, 2 for right, nil.
The climb through EXPR's parents stops one step short of REL, and the
arm arrived at is the answer. A nil NODE — or NODE naming REL itself,
point on the relation's own operator — is in neither arm."
  (when (and (consp node) (not (eq node rel)))
    (let ((n node))
      (while (let ((up (calc-find-parent-formula expr n)))
               (and (consp up) (not (eq up rel)) (setq n up))))
      (cond ((eq n (nth 1 rel)) 1)
            ((eq n (nth 2 rel)) 2)))))

(defun maf--goto-side (side)
  "Move point to the whole SIDE of the relation it sits in.
SIDE is `left', `right' or `other' — the side point is not in now.
The shared body of `maf-goto-left-side', `maf-goto-right-side' and
`maf-goto-other-side'; those docstrings describe what the motion
promises.

Point already standing where SIDE would land crosses to the other side
instead, so either paren key walks the relation on repeat.

At home the paren keys keep the meaning the edit module gives them
there — a blank vector entry opened at the bottom of the stack —
since there is no entry at point for the motion to work within; the
crossing reaches into the stack instead, to the right side of the
entry on level 1, falling back to the module's fresh bottom entry
only on an empty stack. With that module off there is nothing to
fall back to and the motions signal."
  (let ((m (calc-locate-cursor-element (point))))
    ;; The crossing works from home: the newest relation is the one
    ;; crossed into, its right side the landing.
    (when (and (<= m 0) (eq side 'other) (> (calc-stack-size) 0))
      (setq m 1 side 'right))
    (if (<= m 0)
        (if (bound-and-true-p maf-use-edit-mode)
            (if (eq side 'other)
                (maf-edit-add-entry-above)
              (maf-edit-add-vector))
          (user-error "No expression at point"))
      (calc-prepare-selection m)
      (let* ((expr (calc-top m 'full))
             (part (calc-find-selected-part))
             (rel (maf--side-relation expr part)))
        (unless rel
          (user-error "No relation at point"))
        ;; The crossing names its side here: out of the right arm is
        ;; left, out of the left arm is right, and in neither — the
        ;; relation's own operator, the margins naming the whole entry
        ;; — position decides: the end of the line stands at or past
        ;; the right side's own glyph and crosses left, and anywhere
        ;; earlier crosses right.
        (when (eq side 'other)
          (setq side
                (pcase (maf--relation-arm expr rel part)
                  (2 'left)
                  (1 'right)
                  (_ (let ((right-pos (maf--up-node-position
                                       (nth 2 rel)
                                       (maf--up-entry-region m))))
                       (if (and right-pos (>= (point) right-pos))
                           'left
                         'right))))))
        (let* ((region (maf--up-entry-region m))
               (node (nth (if (eq side 'left) 1 2) rel))
               (pos (maf--up-node-position node region)))
          ;; Cycle rather than stand still. Point already on the side
          ;; the key names has arrived: there is nowhere further out on
          ;; that end of the relation, so the press crosses to the
          ;; other side instead and one key walks the whole relation.
          ;; The test is the landing itself — point sitting where this
          ;; motion would put it — so it holds however point got there,
          ;; the mirror key included.
          (when (and pos (= pos (point)))
            (let* ((other (if (eq side 'left) 'right 'left))
                   (other-node (nth (if (eq other 'left) 1 2) rel))
                   (other-pos (maf--up-node-position other-node region)))
              ;; A side with nothing to name it by is no destination:
              ;; the press stays put rather than signalling, since the
              ;; side it was asked for is where point already is.
              (when other-pos
                (setq side other node other-node pos other-pos))))
          (unless pos
            (user-error "Nothing to name the %s side by"
                        (if (eq side 'left) "left" "right")))
          ;; A selection outranks point when a command resolves its
          ;; subject (see `maf--resolve-context'), so a motion that left
          ;; one behind would move the cursor and change nothing.
          ;; Carrying it to the side keeps the promise the motion makes,
          ;; as `maf-up-expression' does for the climb; the re-render it
          ;; costs rewrites the entry's lines, so point is placed after.
          (when (calc-top m 'sel)
            (calc-wrapper
             (calc-prepare-selection m)
             (calc-change-current-selection node))
            (calc-prepare-selection m)
            (setq pos (or (maf--up-node-position
                           node (maf--up-entry-region m))
                          pos)))
          (goto-char pos))))))

(defun maf-goto-left-side ()
  "Move point to the whole left side of the relation it sits in.

  6 x + 12 = 18 y| + 6  =>  6 x |+ 12 = 18 y + 6

Point lands on that side's own first glyph — its operator, the parens
calc printed around it, its function name — which is where resolve
names it, so the next command acts on the side entire rather than on
the term point was in. The side is the largest formula there is on the
left: `maf-up-expression' climbs to it a level at a time, and this is
the one key that arrives.

The relation is the innermost one point sits in, so a term inside one
element of a vector of equations finds its own equation rather than the
vector around it. All six relations count, not just =.

  2 x - 3| < 7  =>  2 x |- 3 < 7

From the entry's margin — the line-number prefix, the end of the line —
where point names the whole entry, the entry's own relation is the one
used.

  |1:  y = (x + 3)^2  =>  1:  |y = (x + 3)^2

Pressed from the side it already names, the key crosses to the other
one rather than standing still: the side is as far out as that end of
the relation goes, so the press that would repeat it is a crossing
instead.

  6 x |+ 12 = 18 y + 6  =>  6 x + 12 = 18 y |+ 6

One key therefore walks the whole relation, and the pair are two ways
into the same walk — `(' starting it leftward, `)' rightward. The test
is the landing, not the key that made it, so a `)' arrival cycles under
`(' just the same.

With a selection up on the entry it travels to the side along with
point, since a selection is what the next command would resolve — the
crossing carries it too.

At home, where there is no entry at point, the key keeps the meaning
the edit module gives it there: a blank vector entry opened at the
bottom of the stack (`maf-edit-add-vector'). With that module off it
signals instead, as it does on an entry that holds no relation."
  (interactive)
  (maf--goto-side 'left))

(defun maf-goto-right-side ()
  "Move point to the whole right side of the relation it sits in.

  6 x| + 12 = 18 y + 6  =>  6 x + 12 = 18 y |+ 6

The mirror of `maf-goto-left-side', over the same relation — the
innermost one point sits in — and landing the same way: on the glyph
that names the whole side, so the next command acts on it entire.

  2 x - 3| < 7  =>  2 x - 3 < |7

Pressed from the side it already names, it crosses back the same way
`maf-goto-left-side' does:

  6 x + 12 = 18 y |+ 6  =>  6 x |+ 12 = 18 y + 6

So either key alone is the whole crossing — one press to the far side,
one back, whatever term point started on — and the two differ only in
which side they set out for."
  (interactive)
  (maf--goto-side 'right))

(defun maf-goto-other-side ()
  "Move point to the whole side of the relation it is not in.

  6 x + 12 = 18 y| + 6  =>  6 x |+ 12 = 18 y + 6

The crossing half of `maf-goto-left-side' and `maf-goto-right-side',
without naming a side: wherever point sits in the relation — the
innermost one it sits in, as for those two — the press lands on the
whole of the opposite side, on the glyph that names it, so the next
command acts on that side entire. Pressed again it crosses back, and
the one key rocks between the sides:

  6 x |+ 12 = 18 y + 6  =>  6 x + 12 = 18 y |+ 6

In neither side — the margins naming the whole entry, the relation's
own operator — position decides: the end of the line stands past the
right side and crosses left, and anywhere earlier crosses right:

  |1:  y = (x + 3)^2  =>  1:  y = (x + 3)|^2
  1:  x = y|          =>  1:  |x = y

A selection up on the entry travels to the side along with point, as
it does for the named motions.

At home the crossing reaches into the stack: the landing is the
whole right side of the entry on level 1, so one press from the dot
puts point on the newest relation's answer side. On an empty stack
the key keeps the meaning the edit module gives it there — a fresh
entry opened at the bottom (`maf-edit-add-entry-above') — and with
that module off it signals, as it does on an entry that holds no
relation."
  (interactive)
  (maf--goto-side 'other))

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

(defun maf--carry-entry (count up &optional from-home)
  "Move the entry at point COUNT levels, UP the screen when UP, else down.
Point travels with the entry. The travel wraps around the stack: an
entry carried past the deepest level reappears at level 1, and one
carried past level 1 reappears at the deepest. With point at home or on
an empty stack — and on a stack of one entry, or with a COUNT that laps
it exactly — nothing happens: no rewrite, no undo group.

FROM-HOME reads home as level 1 rather than as no entry at all: the
entry the home line sits under is the one carried, and point rides it
to the margin of the line it lands on — the offset into the entry that
point riding along keeps, taken from a point that was never inside it.
A repeat then carries the same entry on. An empty stack still has
nothing to carry."
  (maf--with-calc-buffer
    (let* ((n (calc-stack-size))
           (at (calc-locate-cursor-element (point)))
           ;; 0 and below is home or an empty stack: no entry at point,
           ;; unless FROM-HOME names level 1 for it. (The dot line reads
           ;; 0 and the blank line under it -1, as `maf--at-home-p'
           ;; allows for.)
           (homed (and from-home (<= at 0) (> n 0)))
           (m (if homed 1 at))
           ;; The levels are a ring of size N and the entry travels
           ;; COUNT places round it, so any count is in range.
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
              ;; A carry that read home as level 1 has no offset to
              ;; keep: 0 is the margin, the entry's own line start.
              (offset (if homed
                          0
                        (- (point) (save-excursion
                                     (calc-cursor-stack-index m)
                                     (point))))))
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

At home the top entry is the one carried, as if point had been on it:
it rises a line and point rides along, landing in that line's margin,
so a repeat carries the same entry on rather than the next one up.

  2:  a          2:  |b
  1:  b     =>   1:  a
      .|

On an empty stack there is nothing to carry, and on a stack of one
entry there is nowhere to carry it to.

A prefix argument N carries the entry N lines at once, wrapping as
often as it takes; a negative N carries it down instead, as
`maf-carry-down' does — from home too, where that means the same
no-op.

  C-u 3  4:  a       4:  d|
         3:  b   =>  3:  a
         2:  c       2:  b
         1:  d|      1:  c"
  (interactive "p")
  ;; Home reads as level 1 only for the upward carry: negated, the
  ;; command is a carry-down, and home is a no-op there.
  (maf--carry-entry (abs n) (>= n 0) (>= n 0)))

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
the command does nothing — unlike `maf-carry-up', which reads home as
the top entry, since carrying that entry down is a trip round the ring
to the deepest level rather than the one-line move the gesture asks
for.

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

The sides stand as the stack had them — a bare variable on the right
stays on the right, like the operands of any other binary command;
nothing reorders the pair.

  2:  5          1:  5 = x|
  1:  x|

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
relation it forms: subject != argument, structural, no simplification,
the sides standing as the stack had them."
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
;; Calc renders log(x, b) as the literal "log\left( x, 3 \right)" and
;; log10(x) as "\log{x}". A base becomes \log's subscript — except 10,
;; the base the bare \log already assumes, which stays unwritten:
;; 3 log10(5) typesets as 3 log(5).
;;
;; The composition is keyed on nil (the whole expression) rather than an
;; argument count, since the handler returns a composition, not a
;; formula. calccomp's dispatch is `math-compose-forms'; the property
;; name is not free-form.
(defun maf--latex-compose-log (expr)
  "Compose EXPR, a `calcFunc-log' call, as LaTeX.
Two arguments give \\log_{base} — except a literal base 10, which
renders as the bare \\log like `calcFunc-log10' — and one gives \\ln;
calc normalizes log(x) to ln(x), so the one-argument form only shows
up unevaluated."
  (cond ((and (= (length expr) 3) (eq (nth 2 expr) 10))
         (maf--latex-compose-log10 expr))
        ((= (length expr) 3)
         (list 'horiz
               "\\log_{" (math-compose-expr (nth 2 expr) 0) "}"
               "\\left( " (math-compose-expr (nth 1 expr) 0) " \\right)"))
        (t
         (list 'horiz
               "\\ln\\left( " (math-compose-expr (nth 1 expr) 0)
               " \\right)"))))

(defun maf--latex-compose-log10 (expr)
  "Compose EXPR, a `calcFunc-log10' call, as the bare LaTeX \\log.
The 10 is the base \\log assumes, so a subscript would only say it
twice; the notation reads 3 log(5), not 3 log_10(5)."
  (list 'horiz
        "\\log\\left( " (math-compose-expr (nth 1 expr) 0) " \\right)"))

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

(defconst maf--latex-paren-calls
  '((calcFunc-sin . "\\sin") (calcFunc-cos . "\\cos")
    (calcFunc-tan . "\\tan") (calcFunc-cot . "\\cot")
    (calcFunc-sec . "\\sec") (calcFunc-csc . "\\csc"))
  "Calls `maf--latex-string' typesets with their argument in parens.
Calc's own formatter braces a simple argument — \\sin{x}, typeset as
sin x — and these six read better as sin(x); see
`maf--latex-compose-paren-call'.")

(defconst maf--latex-set-signs
  '((calcFunc-vunion . " \\cup ") (calcFunc-vint . " \\cap "))
  "Set calls `maf--latex-string' typesets with their sign written out.
vunion draws as the cup, vint as the cap, between their operands; see
`maf--latex-compose-set-op'.")

(defun maf--latex-join-composed (exprs sign)
  "Compose EXPRS and return them joined by the string SIGN."
  (let (parts)
    (dolist (x exprs)
      (when parts (push sign parts))
      (push (math-compose-expr x 0) parts))
    (cons 'horiz (nreverse parts))))

(defun maf--latex-set-operand-parens-p (head x)
  "Whether X, an operand of the set call HEAD, needs parens to read.
A multi-piece set — a vector of intervals, drawn as cups — and a set
call of the other sign each read wrong flattened into a different
sign around them; a piece of the same sign chains flat."
  (or (and (eq (car-safe x) 'vec)
           (> (length x) 2)
           (cl-every (lambda (el) (eq (car-safe el) 'intv)) (cdr x))
           (not (eq head 'calcFunc-vunion)))
      (and (assq (car-safe x) maf--latex-set-signs)
           (not (eq (car-safe x) head)))))

(defun maf--latex-compose-set-op (a)
  "Compose the set call A with its sign between the operands.
The signs of `maf--latex-set-signs' — A cup B for a union, A cap B
for an intersection — rather than the named calls calc writes, an
operand of mixed sign parenthesized
\(`maf--latex-set-operand-parens-p'). On the latex
`math-special-function-table' during `maf--latex-string' alone."
  (let ((sign (cdr (assq (car a) maf--latex-set-signs)))
        parts)
    (dolist (x (cdr a))
      (when parts (push sign parts))
      (push (if (maf--latex-set-operand-parens-p (car a) x)
                (list 'horiz "(" (math-compose-expr x 0) ")")
              (math-compose-expr x 0))
            parts))
    (cons 'horiz (nreverse parts))))

(defun maf--latex-compose-paren-call (a)
  "Compose the call A as NAME(arg), the argument always in parens.
The brace spelling calc gives a simple argument (\\sin{x}, typeset
sin x) is traded for the parenthesized call; an argument calc would
not render flat keeps the \\left( sizing calc gives it. On the latex
`math-special-function-table' during `maf--latex-string' alone, for
the calls in `maf--latex-paren-calls' — the stack's own languages are
untouched."
  (let ((name (cdr (assq (car a) maf--latex-paren-calls)))
        (flat (and (= (length a) 2)
                   (math-tex-expr-is-flat (nth 1 a)))))
    (list 'horiz name
          (if flat "(" "\\left( ")
          (math-compose-vector (cdr a) ", " 0)
          (if flat ")" " \\right)"))))

(defun maf--latex-separate-digit-product (a comp)
  "Write the sign into COMP where A's juxtaposition would run digits together.
A is the expression COMP was composed from. Calc writes a product as
lhs SPACE rhs and TeX throws the space away, so 4 2^x typesets as
42^x; a right factor whose rendering opens on a digit gets \\times
written out instead, the sign calc itself falls back to where
juxtaposition will not do. The juxtaposed product composes in exactly
one shape — lhs, a break, a lone space, rhs — and only that shape is
touched; every other product, 4 x included, keeps its juxtaposition."
  (when (and (eq (car-safe a) '*)
             (eq (car-safe comp) 'horiz)
             (= (length comp) 6)
             (eq (car-safe (nth 1 comp)) 'set)
             (eq (car-safe (nth 3 comp)) 'break)
             (equal (nth 4 comp) " ")
             (let ((c (math-comp-first-char (nth 5 comp))))
               (and c (<= ?0 c) (<= c ?9))))
    (setf (nth 4 comp) "\\cdot "))
  comp)

(defun maf--latex-strip-script-parens (latex)
  "LATEX with parens dropped from scripts they span whole.
Calc writes x^(-n) into TeX as x^{(-n)}: the parens that made the
exponent one expression in flat notation ride along into the
superscript, where the raised position already groups it — nobody
writes the parens by hand. Dropped from a super- or subscript only
when the pair spans the whole braced group, so a script holding a
product of groups keeps its inner pairs."
  (let ((i 0))
    (while (setq i (string-match "[_^]{(" latex i))
      (let* ((open (+ i 2))
             (depth 1)
             (j (1+ open)))
        (while (and (> depth 0) (< j (length latex)))
          (pcase (aref latex j)
            (?\( (setq depth (1+ depth)))
            (?\) (setq depth (1- depth))))
          (setq j (1+ j)))
        ;; J is one past the matching close paren. A } right there
        ;; means the pair spans the script — nothing stands between it
        ;; and either brace — and the parens go.
        (if (and (zerop depth)
                 (< j (length latex))
                 (eq (aref latex j) ?\}))
            (setq latex (concat (substring latex 0 open)
                                (substring latex (1+ open) (1- j))
                                (substring latex j)))
          (setq i (+ i 2)))))
    latex))

(defun maf--latex-string (expr)
  "Format EXPR as a single line of LaTeX.
Calc's latex language does the formatting, but only for the call: the
language variables it sets are restored afterwards, so the stack
display never changes language. `math-format-value' inhibits line
breaking, so the result is one line however wide. The trig calls of
`maf--latex-paren-calls' typeset with their argument in parens —
sin(x), not calc's sin x; an exponent or subscript sheds the
parens flat notation needed around it: x^{-n}, not x^{(-n)} — see
`maf--latex-strip-script-parens'; and a juxtaposed factor opening on
a digit gets its sign written out — 4 \\cdot 2^x, where TeX would
have run the 4 and 2 together (`maf--latex-separate-digit-product');
the degree unit deg typesets as the raised circle, 180 deg drawing
as 180 with the \\circ on its shoulder; and the sets read with their
signs — a vector of intervals joins its pieces with the cup instead
of bracketing them, and vunion and vint calls draw as A cup B and
A cap B (`maf--latex-compose-set-op'). A plain vector brackets with
\\left[ and \\right], so a tall element gets full-height delimiters;
a matrix keeps calc's pmatrix.

Calc writes a product as juxtaposition except when the right factor
is a \\left( group, where it falls back to \\times — its flatness
test is structural, so even a factor that renders flat can trip it.
Juxtaposition is unambiguous there too, so the \\times goes — and so
does the one calc writes between a variable and a plain paren group,
where 4 p (x - h) is what anyone writes by hand. The sign stays only
where dropping it would change the reading — a negated right factor,
a factor opening on a digit — spelled \\cdot rather than the \\times
calc writes, the dot reading lighter than the cross.

Calc writes if(c, a, b) as c ? a : b, but TeX ignores the source
spaces and ? is an ordinary character, so it typesets crammed
(0?x) while the : beside it, a relation to TeX, gets spaced. The ?
is reclassed \\mathrel to match."
  (maf--with-calc-buffer
    (let ((lang calc-language)
          (opt calc-language-option)
          (compose (symbol-function 'math-compose-expr)))
      (unwind-protect
          ;; The language is set before the table is read: calc-lang
          ;; loads lazily on the first `calc-set-language', and a
          ;; binding taken from the not-yet-populated property would
          ;; be "restored" to nil on exit, wiping \\frac and its
          ;; siblings for the rest of the session.
          (progn
            (calc-set-language 'latex nil t)
            (cl-letf (((get 'latex 'math-special-function-table)
                     (append (mapcar (lambda (entry)
                                       (cons (car entry)
                                             #'maf--latex-compose-paren-call))
                                     maf--latex-paren-calls)
                             (mapcar (lambda (entry)
                                       (cons (car entry)
                                             #'maf--latex-compose-set-op))
                                     maf--latex-set-signs)
                             (get 'latex 'math-special-function-table)))
                    ((symbol-function 'math-compose-expr)
                     (lambda (a prec &optional div)
                       ;; The degree unit is notation, not a name: the
                       ;; raised circle rides the factor before it —
                       ;; {}^{\circ} juxtaposes into 180^\circ. A
                       ;; vector of intervals is a set in pieces and
                       ;; reads with its sign, the pieces joined by
                       ;; the cup, the carrying brackets dropped. All
                       ;; else composes as calc would, digit products
                       ;; separated.
                       (cond
                        ((equal a '(var deg var-deg)) "{}^{\\circ}")
                        ((and (eq (car-safe a) 'vec)
                              (cdr a)
                              (cl-every (lambda (el)
                                          (eq (car-safe el) 'intv))
                                        (cdr a)))
                         (maf--latex-join-composed (cdr a) " \\cup "))
                        ;; A plain vector brackets with \left/\right,
                        ;; so a tall element — a \frac — gets
                        ;; full-height delimiters; calc writes the
                        ;; literal [ ] whatever is inside. A matrix
                        ;; keeps calc's pmatrix.
                        ((and (eq (car-safe a) 'vec)
                              (cdr a)
                              (not (math-matrixp a)))
                         (list 'horiz "\\left[ "
                               (maf--latex-join-composed (cdr a) ", ")
                               " \\right]"))
                        (t (maf--latex-separate-digit-product
                            a (funcall compose a prec div)))))))
              (maf--latex-strip-script-parens
               (replace-regexp-in-string
                " \\? " " \\\\mathrel{?} "
                (replace-regexp-in-string
                 "\\\\times" "\\\\cdot"
                 (replace-regexp-in-string "\\\\times \\((\\|\\\\left(\\)" "\\1"
                                           (math-format-value expr)))))))
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

;;; Yank

(defconst maf--yank-grouped-number-re
  (concat "^[ \t]*[-+]?[0-9]\\{1,3\\}\\(?:,[0-9]\\{3\\}\\)+"
          "\\(?:\\.[0-9]*\\)?\\(?:[eE][-+]?[0-9]+\\)?[ \t]*$")
  "A line that is one number written with digit-group commas.
Groups after the first are exactly three digits with no space after
the comma — \"1,234,567\" — which is what tells a grouped number from
a comma-separated list like \"1, 234\" or \"12,34\". Anchored per
line, so each line of a multi-line yank is judged on its own.")

(defun maf--yank-degroup (text)
  "Return TEXT with digit-group commas stripped from whole-number lines.
A line matching `maf--yank-grouped-number-re' loses its commas; every
other line is untouched. When no line matches, TEXT itself is
returned, not a copy — `calc-yank-internal' recognizes calc's own
last kill by object identity, and that exactness path survives only
if the string passes through unchanged."
  (if (string-match maf--yank-grouped-number-re text)
      (replace-regexp-in-string maf--yank-grouped-number-re
                                (lambda (line) (string-replace "," "" line))
                                text 'fixedcase 'literal)
    text))

(defconst maf--yank-level-prefix-re
  "^[[:space:]]*[0-9]+:[[:space:]]+"
  "A stack level prefix opening a yanked line — \"2:  \", indented or not.
The whitespace after the colon tells it from a fraction, which calc
writes 1:2 with none; the whitespace before it covers text quoted
with indentation, as notes and transcripts carry it.")

(defun maf--yank-strip-levels (text)
  "Return TEXT with stack level prefixes stripped from its lines.
A yank swept off a stack display carries each entry's \"2:  \" — the
same prefix `maf--copy-read' drops from a single copied line. The
number is discarded, never read: lines push in the order they appear,
whatever levels they name. When no line carries one, TEXT itself is
returned, not a copy, for the same identity reason as
`maf--yank-degroup'."
  (if (string-match maf--yank-level-prefix-re text)
      (replace-regexp-in-string maf--yank-level-prefix-re "" text)
    text))

(defun maf-yank (radix)
  "Yank from the kill ring, reading digit-grouped numbers whole.

  kill ring: 1,234,567   =>   1:  1234567

Numbers copied from spreadsheets, web pages, or bank statements
arrive with digit-group commas, which calc's reader takes as
expression separators — a stock yank of \"1,234,567\" pushes three
entries. A line that is entirely one such number is read as the
number; the commas must bracket exact groups of three, so \"1, 234\"
and \"12,34\" still yank as the separate values they are. Each line
of a multi-line yank is judged on its own, so a copied spreadsheet
column comes in one entry per line.

Stack level prefixes are dropped: text swept off a stack display —
\"2:  [x = 6, x = 0]\" over \"1:  [y = 5, y = 2]\" — yanks as the
entries themselves, one per line (`maf--yank-strip-levels'; the
fraction 1:2, written without whitespace, is left alone). Everything
else behaves as `calc-yank', RADIX prefix included."
  (interactive "P")
  (maf--with-calc-buffer
    (calc-yank-internal radix (maf--yank-degroup
                               (maf--yank-strip-levels
                                (current-kill 0 t))))))

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
command still targets what point was on — C-u RET, or C-RET, which is
that same prefix on a key of its own
(`maf-dup-here-or-clear-selections'); `maf-dup-here' is the named entry
point.

  1:  (a +| b) c   C-u RET  =>   2:  (a +| b) c
                                 1:  b            (point stays on b)

Calc's keep-args prefix asks for the same hold: K RET duplicates and
keeps point, the modifier route to what C-u RET does. The flag reads as
it always does, as \"consume nothing\" — and a duplicate consumes
nothing on the stack to begin with, so what it spares here is point.

The Hyperbolic flag widens the target to the whole entry: H RET copies
the entry at point however deep within it point rests — sub-formula
and selection make no difference — the way the solve commands take
their subject.

  1:  (a +| b) c   H RET  =>   2:  (a + b) c
                               1:  (a + b) c    (whole entry, not b)"
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
           ;; per side. We only read :expr and push it. The Hyperbolic
           ;; flag widens to the whole entry (:scope entry); calc-wrapper's
           ;; epilogue below consumes the flag as it does every prefix.
           (context (maf--resolve-context
                     (if calc-hyperbolic-flag
                         '((:arity . unary) (:map . -1) (:scope . entry))
                       '((:arity . unary) (:map . -1)))))
           (expr (alist-get :expr context))
           ;; K RET holds point just as C-u RET does. The flag is read
           ;; from resolve's snapshot: calc-wrapper's epilogue clears it
           ;; below, and `maf--fancy-prefix-keep' is what got it here
           ;; through RET at all — this command carries the `maf-command'
           ;; mark by hand for exactly that.
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
argument, C-u RET; the key C-RET goes through RET's dispatcher instead
(`maf-dup-here-or-clear-selections'), so a selection still clears there."
  (interactive)
  (maf-dup t))

(defun maf-dup-go ()
  "Duplicate the item at point, pushing the copy onto the top of the stack.

  3:  a + b       4:  a + b
  2:  c|      =>  3:  c
  1:  d           2:  d
                  1:  c|

Point picks the subject as usual — a sub-formula at point, a calc
selection or an active region's run when either is present, the whole
entry from its margin, the top entry at home. The copy lands on top,
where `maf-dup' puts it too; what sets this command apart is only where
point goes: it travels with the copy instead of parking on the home
line, leaving a mark at the origin so a single `pop-to-mark-command'
returns there. The copy is verbatim: nothing simplifies or evaluates,
and keep-args makes no difference.

  2:  (a +| b) c   =>   3:  (a + b) c
  1:  z                 2:  z
                        1:  |a + b      (sub-formula at point)

A whole entry renders exactly like its source, so point keeps its place
within it and lands on the same character in the copy; a sub-formula
renders on its own, with no such place to keep, so point lands at the
start of the copy.

At home point stays home, having never been on the entry that was
copied. Signals an error on an empty stack.

  1:  x = y|  =>  2:  x = y     (relations copy whole, not per side)
                  1:  x = y|"
  (interactive)
  (maf--with-calc-buffer
    (when (zerop (calc-stack-size))
      (user-error "Stack is empty"))
    (let* ((snapshot (maf--point-snapshot))
           (home (maf--at-home-p))
           ;; The origin the mark keeps, captured now, before resolve
           ;; probes calc state and may move point; the buffer is
           ;; unedited until the push, so the position stays valid. Nil
           ;; at home, where point does not travel.
           (origin (unless home (point)))
           ;; Point's own level, captured before the push renumbers
           ;; everything. Home gives 0, clamped to the top entry.
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
           ;; The entry the subject came from: point's own, except when
           ;; a selection or a region named another one (:m).
           (m (or (alist-get :m context) at))
           ;; Whether the copy renders exactly like what point was looking
           ;; at: it does when the subject is point's own entry whole —
           ;; from the margin, or as the sub-formula that spans it — and
           ;; not when a part was lifted out to stand on its own.
           (whole (and (= m at)
                       (equal expr (maf--strip-encasing (calc-top at 'full))))))
      ;; Mark the origin before the push, so `pop-to-mark-command'
      ;; returns there (the marker rides the push's renumber).
      (when origin (maf--mark-before-home origin))
      ;; calc-wrapper's epilogue parks point home; restoring the snapshot
      ;; puts it back on the original — the copy went in below every
      ;; entry, disturbing no line above it — and the step to the copy
      ;; starts there.
      (maf--preserve-point
        (calc-wrapper (calc-push expr)))
      ;; The copy is the new top of the stack.
      (cond
       ;; At home point was never on the entry that was copied, so it
       ;; has nowhere to travel from; calc left it home already.
       (home)
       ;; Step by row and column rather than a buffer offset: the push can
       ;; widen every line-number prefix (a stack crossing 9 entries), which
       ;; a raw offset would carry into the formula text.
       (whole
        (let ((col (current-column)))
          (calc-cursor-stack-index 1)
          (forward-line row)
          (move-to-column col)))
       (t (maf--goto-entry-text 1)))
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
it, and `maf--fancy-prefix-keep' is what lets it survive the key. The
Hyperbolic flag (H RET) reaches `maf-dup' the same way and widens the
copy to the whole entry at point; with a selection active the clear
still wins, flag or no flag."
  (interactive "P")
  (if (maf--sel-any-p)
      (maf-clear-selections)
    (maf-dup keep-point)))

;; RET is bound to a hand-written command rather than a `maf-defcmd' one,
;; so nothing stamps the property for it. It reads `calc-keep-args-flag'
;; deliberately (see the docstring above), which is exactly what the mark
;; means, so set it here.
(put 'maf-dup-or-clear-selections 'maf-command t)

(defun maf-dup-here-or-clear-selections ()
  "Clear active selections, or duplicate the item at point, keeping point.
`maf-dup-or-clear-selections' with its keep-point argument set — the
same thing C-u RET runs, on a key of its own: C-RET. With no selection
active the copy is pushed onto the top of the stack and point stays on
what it named instead of homing, so the next command still targets it.
With a selection active this clears like plain RET: the clear moves
point nowhere to begin with, so there is nothing for the hold to vary."
  (interactive)
  (maf-dup-or-clear-selections t))

;; Hand-written like the dispatcher it wraps, and bound to a key calc's
;; fancy prefix would otherwise strip the flags off (K C-RET), so it
;; carries the same mark.
(put 'maf-dup-here-or-clear-selections 'maf-command t)

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

Only for keep-args and hyperbolic in a maf buffer — plain calc, and
I/O, keep calc's own behavior. Hyperbolic joined keep-args when H RET
learned to widen the copy to the whole entry: RET is a control
character, exactly the class ORIG strips the flags from, so without
this the flag never reached the dispatcher."
  (let ((def (and (or calc-keep-args-flag calc-hyperbolic-flag)
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
;; The ordered relations take the same treatment, but only the additive
;; rules earn a twin. Crossing a < with a division flips its direction
;; and a rewrite rule has no way to know the divisor's sign; crossing
;; one with a power is not a term move at all (a^2 <= y says nothing
;; about a <= sqrt(y)). Adding and subtracting are the moves that hold
;; whatever the sign, so the rules built from + and - alone carry over
;; unchanged.
;;
;; A lone factor under a < does cross, but outside the rules:
;; `maf--jump-ordered-move' divides it across by hand, where the sign
;; can be consulted. Known-sign factors move directly, the direction
;; flipped for a negative; sign-unknown ones move as the three-way
;; sign split the solve commands write (see `maf--solve-relation').
;; What remains — exponents, log arguments, factors of only part of a
;; side — has no sound move, and the command messages toward
;; `mafcmd-isolate', which reasons about the solution rather than
;; shuffling terms.

(defconst maf--jump-relations
  '(calcFunc-eq calcFunc-neq calcFunc-lt calcFunc-leq calcFunc-gt calcFunc-geq)
  "The relations `maf-jump-equals' will move a term across.")

(defconst maf--jump-ordered-relations
  '(calcFunc-lt calcFunc-leq calcFunc-gt calcFunc-geq)
  "The subset of `maf--jump-relations' that only the additive rules serve.")

(defconst maf--jump-additive-heads
  '(calcFunc-assign calcFunc-plain calcFunc-eq calcFunc-select + - neg)
  "Heads a JumpRule may be built from and still hold for an ordered relation.
Everything outside this set — *, /, ^, log, sqrt — makes the move depend
on a sign or a monotonicity the rule cannot check.")

(defvar maf--jump-rules-cache nil
  "Memo cell for `maf--jump-rules': a cons of (SOURCE . EXTENDED).
SOURCE is the `var-JumpRules' value EXTENDED was derived from, compared
by identity — so a user who re-stores JumpRules gets a fresh derivation
instead of a stale extension.")

;; The identity key catches a re-stored JumpRules but not a reload that
;; changes the derivation itself: `defvar' leaves the cell alone, so a
;; live session would keep serving twins built by the code just
;; replaced. Reset it on every load — the next jump re-derives.
(setq maf--jump-rules-cache nil)

(defun maf--jump-subst-rel (expr op)
  "Return EXPR with every = relation in it rewritten to OP."
  (if (Math-primp expr)
      expr
    (cons (if (eq (car expr) 'calcFunc-eq) op (car expr))
          (mapcar (lambda (sub) (maf--jump-subst-rel sub op)) (cdr expr)))))

(defun maf--jump-additive-rule-p (rule)
  "Non-nil when RULE is built from addition and subtraction alone.
Read off the rule itself rather than listed by hand, so a rule calc adds
upstream is classified the moment it appears."
  (or (Math-primp rule)
      (and (memq (car rule) maf--jump-additive-heads)
           (seq-every-p #'maf--jump-additive-rule-p (cdr rule)))))

(defun maf--jump-rules ()
  "Return calc's JumpRules extended with twins for maf's other relations.
Every = rule gets a != twin; the additive ones (`maf--jump-additive-rule-p')
also get a twin per ordered relation. Reads whatever `var-JumpRules'
currently holds — calc's own accessor compiles the rule text on first use
— and appends the substituted copies, memoized so repeated jumps reuse one
rule object and calc's rewrite-compiler cache stays valid. Entries with no
= in them, such as the leading iterations(1) that caps the rule set at a
single pass, are not doubled."
  (let ((base (calc-var-value 'var-JumpRules)))
    (unless (eq base (car maf--jump-rules-cache))
      (setq maf--jump-rules-cache
            (cons base
                  (if (eq (car-safe base) 'vec)
                      (append
                       base
                       (delq nil
                             (mapcan
                              (lambda (rule)
                                (mapcar
                                 (lambda (op)
                                   (let ((twin (maf--jump-subst-rel rule op)))
                                     (unless (equal twin rule) twin)))
                                 (if (maf--jump-additive-rule-p rule)
                                     (cons 'calcFunc-neq
                                           maf--jump-ordered-relations)
                                   '(calcFunc-neq))))
                              (cdr base))))
                    base))))
    (cdr maf--jump-rules-cache)))

(defun maf--jump-relation (expr node)
  "Return the innermost relation in EXPR that contains NODE, or nil.
NODE itself does not count: a whole relation has no side to move a term
to.

Under an ordered relation the term must also stand in an additive
position — every node between it and the relation a + or a - — which is
the only shape the ordered twins match. Anywhere else under a <, a
factor or an exponent or a log argument, no twin rule exists, so letting
the jump run would pop and push the entry for an unchanged result;
refusing here keeps it a clean no-op."
  (let ((n node) (additive t))
    (while (and (consp (setq n (calc-find-parent-formula expr n)))
                (not (memq (car n) maf--jump-relations)))
      (unless (memq (car n) '(+ -)) (setq additive nil)))
    (and (consp n)
         (or additive (not (memq (car n) maf--jump-ordered-relations)))
         n)))

(defun maf--jump-ordered-factor (expr node)
  "Return (REL . SIDE) when NODE is a lone factor under an ordered relation.
REL is the innermost relation above NODE in EXPR, of
`maf--jump-ordered-relations'; SIDE is 1 or 2, the side NODE stands
in; and every node between NODE and REL is a product — the shape
where moving NODE across is exactly a division by it. Any other
position, or a non-ordered relation (those go through the rules),
returns nil."
  (let ((n node) (inside nil) (pure t) parent)
    (while (and (consp (setq parent (calc-find-parent-formula expr n)))
                (not (memq (car parent) maf--jump-relations)))
      (setq inside t)
      (unless (eq (car parent) '*) (setq pure nil))
      (setq n parent))
    (and inside pure
         (consp parent)
         (memq (car parent) maf--jump-ordered-relations)
         (cons parent (if (eq n (nth 1 parent)) 1 2)))))

(defun maf--jump-ordered-blocked-p (expr node)
  "Non-nil when NODE stands under an ordered relation it cannot cross."
  (let ((n node))
    (while (and (consp (setq n (calc-find-parent-formula expr n)))
                (not (memq (car n) maf--jump-relations))))
    (and (consp n) (memq (car n) maf--jump-ordered-relations))))

(defun maf--jump-drop-factor (expr node)
  "Return EXPR with the exact cons NODE replaced by 1.
Identity, not equality: in x x only the factor point named goes."
  (cond ((eq expr node) 1)
        ((Math-primp expr) expr)
        (t (cons (car expr)
                 (mapcar (lambda (sub) (maf--jump-drop-factor sub node))
                         (cdr expr))))))

(defun maf--jump-node-equal (tree value)
  "Return the first subtree of TREE `equal' to VALUE, depth-first."
  (if (equal tree value)
      tree
    (and (consp tree)
         (cl-some (lambda (sub) (maf--jump-node-equal sub value))
                  (cdr tree)))))

(defun maf--jump-landed-factor (tree node)
  "Return NODE's moved copy in TREE: the divisor of a quotient by it.
The ordered move writes the factor as / NODE on the far side, so the
landing must find that copy — in x y < x + 1 the numerator already
holds an equal-looking x that a plain first-match would stop on.
Falls back to the first equal subtree when no such quotient survived
the normalize (a numeric factor folds away)."
  (or (letrec ((divisor
                (lambda (tree)
                  (and (consp tree)
                       (if (and (eq (car tree) '/)
                                (equal (nth 2 tree) node))
                           (nth 2 tree)
                         (cl-some divisor (cdr tree)))))))
        (funcall divisor tree))
      (maf--jump-node-equal tree node)))

(defun maf--jump-ordered-move (rel side node)
  "Return REL with factor NODE moved across, the direction handled.
NODE is a lone factor of REL's SIDE (1 or 2) — see
`maf--jump-ordered-factor'. A factor whose sign calc knows moves
directly, the direction flipped when it is negative. A sign-unknown
factor moves as calc's if, split three ways on its sign, the zero
case last: the relation with NODE substituted by 0, each side
normalized so it reads as the residue it is. A zero factor cannot
move — dividing by it is undefined — and returns nil with a
message.

Built under default simplifications whatever the session's simplify
mode: the construction's own normalize must fold the crossed factor
and its quotient the same way every time — mode none would commit
1 x k < 2/2."
  (let* ((calc-simplify-mode nil)
         (head (car rel))
         (lhs (nth 1 rel)) (rhs (nth 2 rel))
         (src (if (= side 1) lhs rhs))
         (dst (if (= side 1) rhs lhs))
         (dropped (maf--jump-drop-factor src node))
         ;; The drop is by identity; a NODE from another tree would
         ;; leave SRC intact and the factor on both sides. Signal
         ;; rather than commit that.
         (rest (if (equal dropped src)
                   (error "maf--jump-ordered-move: NODE is not a factor of SIDE")
                 (math-normalize dropped)))
         (moved (list '/ dst node))
         (keep (if (= side 1) (list head rest moved) (list head moved rest)))
         (flip-op (maf--flip-relation-op head))
         (flip (if (= side 1) (list flip-op rest moved)
                 (list flip-op moved rest))))
    (cond
     ((Math-zerop node)
      (message "A zero factor cannot cross: dividing by it is undefined")
      nil)
     ((math-known-posp node) (math-normalize keep))
     ((math-known-negp node) (math-normalize flip))
     (t (math-normalize
         (list 'calcFunc-if (list 'calcFunc-gt node 0)
               keep
               (list 'calcFunc-if (list 'calcFunc-lt node 0)
                     flip
                     (list head
                           (math-normalize (math-expr-subst lhs node 0))
                           (math-normalize
                            (math-expr-subst rhs node 0))))))))))

(defun maf-jump-equals ()
  "Move the term under point across the relation it sits in.

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
ordered relations (<, <=, >, >=) take added and subtracted terms, which
cross without disturbing the direction, and lone factors — a factor of
a whole side, every node above it a product:

  x + a| <= y  =>  x <= -a| + y
  y > a - b|   =>  y + b| > a
  -3 x| < 6    =>  x > -2     (negative factor: the direction flips)
  2 x k| < 2   =>  k > 0 ? 2 x < 2 / k| : k < 0 ? 2 x > 2 / k : 0 < 2

A factor whose sign calc knows crosses directly, the direction flipped
when it is negative. A sign-unknown factor crosses as calc's if, split
three ways on its sign with the zero case last — the same shape the
solve commands write; the move is then one-way, the ternary having no
relation at top level to jump back across. A zero factor stays put:
dividing by it is undefined. Anywhere else under an ordered relation —
an exponent, a log argument, a factor of only part of a side — no
sound move exists and the command says so; `mafcmd-isolate' (j j)
solves for those instead.

A selection standing anywhere is the term to move, whatever entry point
is on — it is the more deliberate gesture, and this is where the rest
of maf takes its subject too. With none, the term under point.

With no term to move — at home with nothing selected, on a whole entry,
on a term outside any relation, or on one the rules do not reach — the
command does nothing rather than signaling; the blocked ordered cases
above message instead, since there the silence read as breakage."
  (interactive)
  (maf--with-calc-buffer
    (let* ((at-point (calc-locate-cursor-element (point)))
           ;; An active selection anywhere outranks point, as it does in
           ;; `maf--resolve-context' — it is the more deliberate gesture,
           ;; and the entry it sits on is the subject even when point has
           ;; wandered to another. `maf--sel-effective-m' picks the one
           ;; under point when that entry is the selected one. Failing
           ;; any selection, the entry at point; at home there is then
           ;; nothing to name, and the command has nothing to do.
           (m (or (and calc-use-selections (maf--sel-effective-m))
                  (and (> at-point 0) at-point))))
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
          (cond
           ((not (consp sel)))
           ((maf--jump-relation (car entry) sel)
            (let ((snapshot (maf--point-snapshot))
                  (var-JumpRules (maf--jump-rules))
                  ;; Calc's `calc-rewrite-selection' runs `calc-normalize'
                  ;; over the rewrite's result, so whatever simplification
                  ;; mode is in effect gets a pass at the moved term. Under
                  ;; alg that pass re-derives the equation and can move a
                  ;; *different* term than the one point named — jumping
                  ;; the 27 of x^2 - 2 x - 8 = 27 lands on
                  ;; x^2 - 2 x - 27 = 8, the 8 swapped across instead of
                  ;; the 27 merely moved. Held to `none', the pass is
                  ;; plain normalization and the result is the rewrite's
                  ;; own, committed unsimplified as documented.
                  (calc-simplify-mode 'none))
              ;; Calc's rewrite locates its entry from point, not from an
              ;; index, so point travels to the entry this resolved to
              ;; before the rewrite runs — from home, and from any other
              ;; entry a selection outranked.
              (unless (= m at-point) (calc-cursor-stack-index m))
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
              (maf--undo-record-cmd-point snapshot)))
           ((maf--jump-ordered-factor (car entry) sel)
            (let* ((info (maf--jump-ordered-factor (car entry) sel))
                   (new (maf--jump-ordered-move (car info) (cdr info) sel)))
              (when new
                (let ((snapshot (maf--point-snapshot))
                      ;; Committed unsimplified, as the rules path is.
                      (calc-simplify-mode 'none))
                  ;; `calc-wrapper' makes the commit one undoable unit.
                  (calc-wrapper
                   (calc-pop-push-record-list 1 "jump" (list new) m (list nil)))
                  ;; Land point on the moved factor on the far side — in
                  ;; a split, on its copy in the first branch.
                  (let* ((committed (car (calc-top m 'entry)))
                         (region (if (maf--solve-split-p committed)
                                     (nth 2 committed)
                                   committed))
                         (landed (maf--jump-landed-factor region sel)))
                    (or (and landed (maf--anchor-on-node m landed))
                        (maf--point-restore snapshot)))
                  ;; A single undo reverts point along with the stack.
                  (maf--undo-record-cmd-point snapshot)))))
           ((maf--jump-ordered-blocked-p (car entry) sel)
            (message "No sound move across an ordered relation from here; j j (isolate) solves for it instead"))))))))

;;; Collecting terms

(defvar maf--collect-vars nil
  "Variable (or vector of them) `maf--collect-run' collects.
Bound per `mafcmd-collect-terms' call, from the prompt it reads.")

(defvar maf--collect-side nil
  "Side of the relation the collected terms land on: 1 left, 2 right.
Bound per `mafcmd-collect-terms' call, from where point stood.")

(defun maf--collect-addends (expr)
  "Return EXPR's top-level additive terms, subtraction folded to negation."
  (pcase (car-safe expr)
    ('+ (append (maf--collect-addends (nth 1 expr))
                (maf--collect-addends (nth 2 expr))))
    ('- (append (maf--collect-addends (nth 1 expr))
                (mapcar #'math-neg (maf--collect-addends (nth 2 expr)))))
    ('neg (mapcar #'math-neg (maf--collect-addends (nth 1 expr))))
    (_ (list expr))))

(defun maf--collect-contains-p (term vars)
  "Non-nil when TERM contains VARS: one var node, or any of a vector."
  (if (eq (car-safe vars) 'vec)
      (cl-some (lambda (v) (math-expr-contains term v)) (cdr vars))
    (math-expr-contains term vars)))

(defun maf--collect-sum (terms)
  "Return the sum of TERMS, 0 when there are none."
  (if terms (cl-reduce #'math-add terms) 0))

(defun maf--collect-point-side ()
  "Return the relation side point stands in for the entry at point: 1 or 2.
The sub-formula under point decides, by which side of the innermost
relation it sits in. Anywhere that names no side — home, the entry's
margin, the relation operator — reads as 1, the left."
  (maf--with-calc-buffer
    (or (when (and (not (maf--at-home-p)) (maf--at-subexpr-p))
          (save-excursion
            (let ((m (calc-locate-cursor-element (point))))
              (when (> m 0)
                (calc-prepare-selection m)
                ;; The part stays unstripped: encasing is what gives an
                ;; atom a cons the parent walk can identify in the tree.
                (let* ((formula (car (calc-top m 'entry)))
                       (sub (ignore-errors (calc-find-selected-part))))
                  (when (and (consp sub) (not (eq sub formula)))
                    (let ((n sub) parent)
                      (while (and (consp (setq parent
                                               (calc-find-parent-formula
                                                formula n)))
                                  (not (maf--relation-p parent)))
                        (setq n parent))
                      (and (consp parent)
                           (if (eq n (nth 2 parent)) 2 1)))))))))
        1)))

(maf-defcmd maf--collect-run (expr _arg commit)
  "Collect every term containing `maf--collect-vars' on `maf--collect-side'.
The worker behind `mafcmd-collect-terms' — see there. Takes the whole
relation (:scope entry, :map -1) and rearranges it: the terms
containing a named variable collect on the side point stood on,
every other term moves to the other side. Both moves are additions
and subtractions on both sides, so any relation keeps its direction.
Sums are rebuilt under default simplifications whatever the session's
simplify mode, so collected like terms fold the same way every time.
A bare expression, or a relation no term of which contains a named
variable, commits unchanged."
  :arity unary
  :prefix "clct"
  :map -1
  :scope entry
  (if (not (maf--relation-p expr))
      (commit expr)
    (let ((head (car expr))
          with-l without-l with-r without-r)
      (dolist (term (maf--collect-addends (nth 1 expr)))
        (if (maf--collect-contains-p term maf--collect-vars)
            (push term with-l)
          (push term without-l)))
      (dolist (term (maf--collect-addends (nth 2 expr)))
        (if (maf--collect-contains-p term maf--collect-vars)
            (push term with-r)
          (push term without-r)))
      (setq with-l (nreverse with-l) without-l (nreverse without-l)
            with-r (nreverse with-r) without-r (nreverse without-r))
      (if (not (or with-l with-r))
          (commit expr)
        (let* ((calc-simplify-mode nil)
               (flip (lambda (terms) (mapcar #'math-neg terms)))
               (new
                (if (eql maf--collect-side 2)
                    (list head
                          (maf--collect-sum
                           (append without-l (funcall flip without-r)))
                          (maf--collect-sum
                           (append with-r (funcall flip with-l))))
                  (list head
                        (maf--collect-sum
                         (append with-l (funcall flip with-r)))
                        (maf--collect-sum
                         (append without-r (funcall flip without-l)))))))
          (commit (math-normalize new)))))))

(defun mafcmd-collect-terms ()
  "Collect every term of a variable on the side of the relation at point.

  1:  x| + 2 k = x^2 - x + 3   collect x  =>  -x^2 + 2 x = -2 k + 3

Point names the side: the terms containing the variable collect on
the side point stands in, and every other term moves to the other —
here point in the right side would collect them there instead. Home,
the entry's margin, and the relation operator read as the left. The
variable is read from the minibuffer as `mafcmd-solve-for' reads it:
the subject's priority variable as the default, several names
separated by commas or spaces collecting the terms of them all.

Terms move whole, by containment, wherever the variable appears in
them; both moves are additions and subtractions on both sides, so
every relation keeps its direction, inequalities included. A side
left with no terms becomes 0. A relation no term of which contains
the variable, or a bare expression, commits unchanged.

  1:  a x| <= b - x   collect x  =>  a x + x <= b
  1:  x + 2 k| = 3    collect z  =>  x + 2 k = 3   (no z: unchanged)"
  (interactive)
  (let ((vars (maf--solve-for-read-vars (maf--solve-for-default-var)
                                        "Collect variable on one side of equation"))
        (side (maf--collect-point-side)))
    (let ((maf--collect-vars vars)
          (maf--collect-side side))
      (call-interactively #'maf--collect-run))))

;;; Collecting terms

(defvar maf--collect-vars nil
  "Variable (or vector of them) `maf--collect-run' collects.
Bound per `mafcmd-collect-terms' call, from the prompt it reads.")

(defvar maf--collect-side nil
  "Side of the relation the collected terms land on: 1 left, 2 right.
Bound per `mafcmd-collect-terms' call, from where point stood.")

(defun maf--collect-addends (expr)
  "Return EXPR's top-level additive terms, subtraction folded to negation."
  (pcase (car-safe expr)
    ('+ (append (maf--collect-addends (nth 1 expr))
                (maf--collect-addends (nth 2 expr))))
    ('- (append (maf--collect-addends (nth 1 expr))
                (mapcar #'math-neg (maf--collect-addends (nth 2 expr)))))
    ('neg (mapcar #'math-neg (maf--collect-addends (nth 1 expr))))
    (_ (list expr))))

(defun maf--collect-contains-p (term vars)
  "Non-nil when TERM contains VARS: one var node, or any of a vector."
  (if (eq (car-safe vars) 'vec)
      (cl-some (lambda (v) (math-expr-contains term v)) (cdr vars))
    (math-expr-contains term vars)))

(defun maf--collect-sum (terms)
  "Return the sum of TERMS, 0 when there are none."
  (if terms (cl-reduce #'math-add terms) 0))

(defun maf--collect-point-side ()
  "Return the relation side point stands in for the entry at point: 1 or 2.
The sub-formula under point decides, by which side of the innermost
relation it sits in. Anywhere that names no side — home, the entry's
margin, the relation operator — reads as 1, the left."
  (maf--with-calc-buffer
    (or (when (and (not (maf--at-home-p)) (maf--at-subexpr-p))
          (save-excursion
            (let ((m (calc-locate-cursor-element (point))))
              (when (> m 0)
                (calc-prepare-selection m)
                ;; The part stays unstripped: encasing is what gives an
                ;; atom a cons the parent walk can identify in the tree.
                (let* ((formula (car (calc-top m 'entry)))
                       (sub (ignore-errors (calc-find-selected-part))))
                  (when (and (consp sub) (not (eq sub formula)))
                    (let ((n sub) parent)
                      (while (and (consp (setq parent
                                               (calc-find-parent-formula
                                                formula n)))
                                  (not (maf--relation-p parent)))
                        (setq n parent))
                      (and (consp parent)
                           (if (eq n (nth 2 parent)) 2 1)))))))))
        1)))

(maf-defcmd maf--collect-run (expr _arg commit)
  "Collect every term containing `maf--collect-vars' on `maf--collect-side'.
The worker behind `mafcmd-collect-terms' — see there. Takes the whole
relation (:scope entry, :map -1) and rearranges it: the terms
containing a named variable collect on the side point stood on,
every other term moves to the other side. Both moves are additions
and subtractions on both sides, so any relation keeps its direction.
Sums are rebuilt under default simplifications whatever the session's
simplify mode, so collected like terms fold the same way every time.
A bare expression, or a relation no term of which contains a named
variable, commits unchanged."
  :arity unary
  :prefix "clct"
  :map -1
  :scope entry
  (if (not (maf--relation-p expr))
      (commit expr)
    (let ((head (car expr))
          with-l without-l with-r without-r)
      (dolist (term (maf--collect-addends (nth 1 expr)))
        (if (maf--collect-contains-p term maf--collect-vars)
            (push term with-l)
          (push term without-l)))
      (dolist (term (maf--collect-addends (nth 2 expr)))
        (if (maf--collect-contains-p term maf--collect-vars)
            (push term with-r)
          (push term without-r)))
      (setq with-l (nreverse with-l) without-l (nreverse without-l)
            with-r (nreverse with-r) without-r (nreverse without-r))
      (if (not (or with-l with-r))
          (commit expr)
        (let* ((calc-simplify-mode nil)
               (flip (lambda (terms) (mapcar #'math-neg terms)))
               (new
                (if (eql maf--collect-side 2)
                    (list head
                          (maf--collect-sum
                           (append without-l (funcall flip without-r)))
                          (maf--collect-sum
                           (append with-r (funcall flip with-l))))
                  (list head
                        (maf--collect-sum
                         (append with-l (funcall flip with-r)))
                        (maf--collect-sum
                         (append without-r (funcall flip without-l)))))))
          (commit (math-normalize new)))))))

(defun mafcmd-collect-terms ()
  "Collect every term of a variable on the side of the relation at point.

  1:  x| + 2 k = x^2 - x + 3   collect x  =>  -x^2 + 2 x = -2 k + 3

Point names the side: the terms containing the variable collect on
the side point stands in, and every other term moves to the other —
here point in the right side would collect them there instead. Home,
the entry's margin, and the relation operator read as the left. The
variable is read from the minibuffer as `mafcmd-solve-for' reads it:
the subject's priority variable as the default, several names
separated by commas or spaces collecting the terms of them all.

Terms move whole, by containment, wherever the variable appears in
them; both moves are additions and subtractions on both sides, so
every relation keeps its direction, inequalities included. A side
left with no terms becomes 0. A relation no term of which contains
the variable, or a bare expression, commits unchanged.

  1:  a x| <= b - x   collect x  =>  a x + x <= b
  1:  x + 2 k| = 3    collect z  =>  x + 2 k = 3   (no z: unchanged)"
  (interactive)
  (let ((vars (maf--solve-for-read-vars (maf--solve-for-default-var)
                                        "Collect variable on one side of equation"))
        (side (maf--collect-point-side)))
    (let ((maf--collect-vars vars)
          (maf--collect-side side))
      (call-interactively #'maf--collect-run))))

;; Calc's DistribRules and MergeRules are written against a marked
;; sub-formula: every rule mentions select(...) somewhere, and matches
;; the formula *around* it — `x * select(a + b)' rewrites the product,
;; not the sum point named. So neither set can run on a resolved
;; sub-expression the way `mafcmd-log-exp's self-contained rules do:
;; the rewrite needs the whole entry with the target marked inside it.
;; That is what these commands build, rather than delegating to calc's
;; `calc-rewrite-selection', which would also leave its selection
;; standing and give the frac substitution below nowhere to happen.
(declare-function math-rewrite "calc-rewr")
(declare-function math-looks-negp "calc-misc")
;; Calc's rule-set holders: the symbols `calc-DistribRules' /
;; `calc-MergeRules' until first use, then the parsed sets cached in
;; their place by `calc-var-value'.
(defvar var-DistribRules)
(defvar var-MergeRules)
;; Bound by `calc-rewrite-selection' around its rewrite; maf's does the
;; same. Non-nil, select( ) in a pattern matches only a real marker;
;; nil, it matches anywhere, which is how an unmarked entry rewrites.
(defvar math-rewrite-selections)
(defvar math-rewrite-default-iters)

;; Four of calc's MergeRules collect powers of unlike bases wrongly, in
;; two ways, and both lose the value rather than merely spell it oddly.
;; Stock `calc-sel-merge' has the same answers; none of this is maf's
;; doing.
;;
;; The first divides by the wrong base. Where every sibling reads the
;; numerator's base as a, these read b:
;;
;;   (a^x) / select(b^x)  :=  select((b / b) ^ x)
;;   (a^x) / select(b^y)  :=  select((b / b^(y-x)) ^ x)
;;
;; so a^x / b^x with the denominator marked answers b/b = 1.
;;
;; The second is the exponent arithmetic shared by the whole
;; differing-exponent family. Collecting a^x and b^y under one power of
;; x needs (b^(y/x))^x = b^y, but the rules subtract where they must
;; divide, giving b^(x(y-x)):
;;
;;   (a^x) * select(b^y)  :=  select((a * b^(y-x)) ^ x)
;;   select(a^x) / (b^y)  :=  select((a / b^(y-x)) ^ x)
;;
;; so a^4 / b^2 merges to 1048576 where a=2, b=4 rather than 1.
;;
;; maf corrects all four rather than mirror a wrong answer, as it
;; already does for the fraction the negation rule mangles (see
;; `maf--sel-as-division'). The corrections are swapped into whatever
;; calc currently holds rather than kept as a second copy of the set,
;; which would drift the moment calc edits it upstream.

(defconst maf--merge-rule-fixes
  '("(a^x) * select(b^y) := select((a * b^(y/x)) ^ x)"
    "(a^x) / select(b^x) := select((a / b) ^ x)"
    "(a^x) / select(b^y) := select((a / b^(y/x)) ^ x)"
    "select(a^x) / (b^y) := select((a / b^(y/x)) ^ x)")
  "Corrected replacements for calc's four faulty power-merge rules.
Matched against the loaded set by left-hand side, so a rule calc has
since fixed or reworded is simply not found and nothing is replaced.")

(defvar maf--merge-rules-cache nil
  "Memo cell for `maf--merge-rules': a cons of (SOURCE . CORRECTED).
SOURCE is the `var-MergeRules' value CORRECTED was derived from,
compared by identity — so a user who re-stores MergeRules gets a fresh
derivation instead of a stale correction.")

(defun maf--merge-rules ()
  "Return calc's MergeRules with the faulty power-merge rules corrected.
Reads whatever `var-MergeRules' currently holds — calc's own accessor
compiles the rule text on first use — and swaps in the corrections,
memoized so repeated merges reuse one rule object and calc's
rewrite-compiler cache stays valid."
  (let ((base (calc-var-value 'var-MergeRules)))
    (unless (eq base (car maf--merge-rules-cache))
      (setq maf--merge-rules-cache
            (cons base
                  (if (eq (car-safe base) 'vec)
                      (let ((fixes (math-read-exprs
                                    (string-join maf--merge-rule-fixes ","))))
                        (cons 'vec
                              (mapcar
                               (lambda (rule)
                                 (or (seq-find
                                      (lambda (fix)
                                        (and (eq (car-safe rule)
                                                 'calcFunc-assign)
                                             (equal (nth 1 fix) (nth 1 rule))))
                                      fixes)
                                     rule))
                               (cdr base))))
                    base))))
    (cdr maf--merge-rules-cache)))

(defvar maf--sel-marked nil
  "Node the surviving select( ) marker wrapped, set by `maf--sel-unmark'.
The rules carry a marker through to their result — `x * select(a + b)'
becomes `x*select(a) + x*b' — which names the part of the new formula
the rewrite considers the outcome. maf reads it to send point there
instead of reselecting. `t' when more than one marker survived, so no
single node stands for the result.")

(defun maf--sel-unmark (expr)
  "Return EXPR with every select( ) marker stripped out.
Records the marked node in `maf--sel-marked'. Unlike calc's
`calc-locate-select-marker', this recurses through a marked node too,
so no marker can ride into the stack when a rule nests one inside
another."
  (cond
   ((Math-primp expr) expr)
   ((and (eq (car expr) 'calcFunc-select) (= (length expr) 2))
    (let ((inner (maf--sel-unmark (nth 1 expr))))
      (setq maf--sel-marked (if maf--sel-marked t inner))
      inner))
   (t (cons (car expr) (mapcar #'maf--sel-unmark (cdr expr))))))

(defun maf--sel-mark (expr node marked)
  "Return EXPR with NODE (matched by identity) replaced by MARKED."
  (cond
   ((eq expr node) marked)
   ((Math-primp expr) expr)
   (t (cons (car expr)
            (mapcar (lambda (x) (maf--sel-mark x node marked)) (cdr expr))))))

(defun maf--sel-as-division (node)
  "Return NODE as a division when it is a literal fraction, else NODE.
Calc stores a rational as its own `frac' atom, which no rule spelled
`a / b' can match — so a fraction under point looks inert to
DistribRules, even though every rule that distributes a quotient
applies to it. Rewritten as an explicit division it matches — calc's
matcher reads a division as a product by the reciprocal, so the
product rule is the one that takes it, and sqrt(3:4) distributes to
sqrt(1/4) sqrt(3). Only correct under no simplification, which would
fold the division straight back to a `frac'."
  (if (eq (car-safe node) 'frac)
      (list '/ (nth 1 node) (nth 2 node))
    node))

(defun maf--sel-expand-pow (expr)
  "Return EXPR with any residual expandpow( ) call evaluated.
DistribRules raises a sum to an integer power by calling calc's
`expandpow' from inside a rule and reading the result back. The helper
computes a binomial expansion and means nothing on the stack, but the
rewrite runs unsimplified, so the call is never evaluated and would
ride into the entry as (x + y)^2 => expandpow(y + x, 2).

The call is evaluated under `alg' rather than whatever mode is in
effect outside the command, since the point is to finish a computation
the rule started: a user who has turned simplification off — maf binds
a key for it — would otherwise get the internal helper on the stack
instead of the polynomial. Only these calls are evaluated; the rest of
what the rules built is left as they built it."
  (cond
   ((Math-primp expr) expr)
   ((eq (car expr) 'calcFunc-expandpow)
    (let ((calc-simplify-mode 'alg)) (calc-normalize expr)))
   (t (cons (car expr) (mapcar #'maf--sel-expand-pow (cdr expr))))))

(defun maf--sel-marked-node (expr)
  "Return the node EXPR's select( ) marker wraps, or nil.
nil also when more than one marker survived, there being no single
node to name then."
  (let ((maf--sel-marked nil))
    (maf--sel-unmark expr)
    (and maf--sel-marked (not (eq maf--sel-marked t)) maf--sel-marked)))

(defun maf--sel-sign-peel-p (before after)
  "Return t when AFTER only split a sign BEFORE's marked node lacks.
Two DistribRules mark a bare negation — `select(- a) ^ x' and
`sqrt(select(- a))' — and calc's matcher reads *any* expression as
-a, binding a to its negation, because -(-a) is a. So they match every
marker there is, and being early in the set they claim it before the
rule the gesture meant: on the x of ln(x^2) they answer
ln((-1)^2 (-x)^2), equal to the original and of no use, where the
log-of-a-power rule one level out gives ln(x) 2.

Both rules carry the marker from n to -n, so a result marking exactly
`math-neg' of what went in is one of them having fired. That alone
does not condemn it — on a genuinely negative base the split is the
whole point, and (-x)^2 => (-1)^2 x^2 moves the marker the same way —
so the test is the sign of the marked node itself.

BEFORE and AFTER are both whole expressions carrying their marker, the
rewriter's input and its output, so the two nodes compared have been
through the same normalization. Reading the node from the stack entry
instead would compare an encased (cplx n 0) against a plain one and
never match (see `Encasing' in docs/reference/concepts.org)."
  (let ((in (maf--sel-marked-node before))
        (out (maf--sel-marked-node after)))
    (and in out
         (not (math-looks-negp in))
         (equal out (math-neg in)))))

(defun maf--sel-product-factors (expr)
  "Return the factors of product EXPR, flattening a nested * chain."
  (if (eq (car-safe expr) '*)
      (append (maf--sel-product-factors (nth 1 expr))
              (maf--sel-product-factors (nth 2 expr)))
    (list expr)))

(defun maf--sel-marked-p (expr)
  "Return t when EXPR contains a select( ) marker."
  (and (not (Math-primp expr))
       (or (and (eq (car expr) 'calcFunc-select) (= (length expr) 2))
           (and (seq-some #'maf--sel-marked-p (cdr expr)) t))))

(defun maf--sel-coefficient-first (expr)
  "Return EXPR with the rewritten product's numeric factors moved first.
Calc writes a coefficient ahead of what it multiplies — 2 ln(x), not
ln(x) 2 — but that ordering is part of the simplifier, which a
distribution has to run without (see `maf--sel-rewrite'). The rules
build their result in whatever order the rule text names, so a
coefficient the rule puts second stays there, and ln(x^2) commits as
ln(x) 2.

Calc's ordering cannot simply be run afterwards: it is inseparable
from the folding, and the same pass that fronts the 2 turns x^b x^a
back into x^(b + a). So maf applies the one part of it that cannot
undo a rewrite — moving numbers ahead of the rest of a product.
Numbers commute with every operand there is, matrices included, so
this is a reordering and never a change of value. The relative order
within each group is kept, and a product calc already ordered, or one
with nothing numeric in it, comes back untouched.

Only products holding the marker are touched, the marker being what
the rules carried through to name their own result. A product the
command did not produce is left as the user wrote it: distributing the
logarithm in ln(x^2) + y 3 must not also turn the y 3 into 3 y."
  (cond
   ((not (maf--sel-marked-p expr)) expr)
   (t
    (let ((node (cons (car expr)
                      (mapcar #'maf--sel-coefficient-first (cdr expr)))))
      (if (eq (car node) '*)
          (let* ((factors (maf--sel-product-factors node))
                 (nums (seq-filter #'Math-realp factors))
                 (rest (seq-remove #'Math-realp factors)))
            (if (and nums rest (not (Math-realp (car factors))))
                (let ((ordered (append nums rest)))
                  (let ((acc (car ordered)))
                    (dolist (f (cdr ordered) acc)
                      (setq acc (list '* acc f)))))
              node))
        node)))))

(defun maf--sel-rewrite-try (expr site part rules as-division)
  "Rewrite SITE under RULES with PART marked, spliced back into EXPR.
Returns nil when no rule fired. AS-DIVISION marks a literal fraction
as a division (see `maf--sel-as-division').

Only SITE is handed to the rewriter, and the rest of EXPR is carried
over untouched. Rewriting the whole entry instead would let the
normalization the rewriter does on the way in fold sites the gesture
never named: merging the logarithms of ln(a) + ln(b) + x^p x^q would
also collapse the powers, two structural changes for one keystroke.
Calc's own `calc-rewrite-selection' normalizes the entry and has that
behavior; maf's other commands leave what they did not target alone,
and these follow them. SITE is where the rule matches — it is the
formula around PART, which is what every rule in these sets reads —
so scoping the rewrite to it costs no matches.

The rewrite always runs with a marker, never on a bare formula. Calc
reads an unmarked one by letting select( ) in a pattern match
anywhere, which sounds like the right thing for a whole-entry subject
and is not: the sign rules below match every expression there is, so
an unmarked sqrt(x) rewrites to sqrt(-1) sqrt(-x). Marking a candidate
and asking about that one place keeps every rewrite answerable, which
is why home walks sites too (see `maf--sel-rewrite-entry').

The result is compared against the rewriter's own input, so the answer
is exactly \"did a rule fire\": normalizing on the way in reorders sums
and products, and that reordering alone must not read as a change
worth committing. A rule that only peels off a sign the marker does
not have counts as not firing, so the walk carries on past it (see
`maf--sel-sign-peel-p')."
  (let* ((math-rewrite-selections t)
         (math-rewrite-default-iters 1)
         (marked (maf--sel-mark site part
                                (list 'calcFunc-select
                                      (if as-division
                                          (maf--sel-as-division part)
                                        part))))
         (normalized (calc-normalize marked))
         (rewritten (math-rewrite normalized rules nil)))
    (unless (or (equal rewritten normalized)
                (maf--sel-sign-peel-p normalized rewritten))
      (maf--sel-mark expr site rewritten))))

(defun maf--sel-rewrite-site (expr site preferred rules as-division)
  "Rewrite EXPR under RULES marking a part of SITE; nil when none fired.
Every rule matches the formula around its marker, so the candidates at
SITE are its immediate parts, not SITE itself. PREFERRED is tried
first when it is one of them — that is the part point is in, and where
two parts of one site both fire, the gesture decides. Returns nil when
SITE has no parts, an atom having none."
  (let (result)
    (unless (Math-primp site)
      (let ((parts (if (memq preferred (cdr site))
                       (cons preferred (remq preferred (cdr site)))
                     (cdr site))))
        (while (and parts (not result))
          (setq result (maf--sel-rewrite-try expr site (car parts) rules
                                             as-division)
                parts (cdr parts)))))
    result))

(defun maf--sel-rewrite-entry (expr site rules as-division)
  "Rewrite EXPR under RULES at the first site within SITE that fires.
For home, where point names no part and the whole entry is the
subject. Walks SITE outermost first, trying each site's parts as the
marker, and takes the first rewrite that comes of it — \"the first
site in the entry the rules reach\".

Calc would read an unmarked entry instead, letting select( ) match
wherever it can, and that is not usable here: the sign rules match
every expression there is, so a bare sqrt(x) comes back as
sqrt(-1) sqrt(-x). Walking marked candidates puts home on the same
footing as the rest of the command, sign guard included — and reaches
what the unmarked reading misses, since normalizing an entry on the
way into the rewriter can fold the very thing a rule was going to
match (x^a x^b becomes x^(a + b) before MergeRules ever sees it)."
  (unless (Math-primp site)
    (or (maf--sel-rewrite-site expr site nil rules as-division)
        (seq-some (lambda (part)
                    (maf--sel-rewrite-entry expr part rules as-division))
                  (cdr site)))))

(defun maf--sel-rewrite-widen (expr sel rules as-division)
  "Rewrite EXPR under RULES at SEL, widening outward until a rule fires.
Every rule in these sets matches the formula *around* the marker, so
the marker is always a part of the formula being rewritten, never that
formula itself. Two things follow, and the walk has to allow for both:
the node point names may be one level too deep to be the marker — on
the a of x (a + b) the rule that fires reads the product, and marks the
sum — or it may already be the formula to rewrite, on the ln of
ln(x^2), where the marker is its argument one level in.

So the walk is over rewrite *sites*, from the node under point out
through its ancestors, trying each site's own parts as the marker (see
`maf--sel-rewrite-site'). The node under point is itself the first
site, which is what lets point stand on a function or an operator and
name the formula there; it comes up again as a candidate marker when
the walk reaches its parent, so standing on a term still marks that
term. Innermost site wins, and within a site the part point is in.
Returns nil when nothing fires out to the whole entry."
  (let ((site sel) (inner sel) result)
    (while (and site (not result))
      (setq result (maf--sel-rewrite-site expr site inner rules as-division))
      (unless result
        (setq inner site
              site (let ((up (calc-find-parent-formula expr site)))
                     (and (consp up) up)))))
    result))

(defun maf--sel-rewrite (rules prefix &optional no-simplify as-division)
  "Rewrite the entry at point under RULES, marking the sub-formula there.
RULES is a compiled rule set; PREFIX its trail label. NO-SIMPLIFY
commits what the rules give without calc's simplifier running over it.
AS-DIVISION rewrites a literal fraction under point as a division
first (see `maf--sel-as-division'), and needs NO-SIMPLIFY to be useful,
since the simplifier folds the division straight back to a fraction.

Point picks the target the way the subexpr context does — the
sub-formula under the cursor, widened outward to the innermost
ancestor some rule reaches (see `maf--sel-rewrite-widen'). An active
selection is the target instead when there is one, and is never
widened. At home a selection standing anywhere names its entry; with
none, the whole entry is the subject and its own sites are walked for
the first one a rule reaches (see `maf--sel-rewrite-entry').

Nothing is left selected: point names the target on the next
keystroke, and point follows the marker the rules carried into the
result — or stays home, when it was home. With no rule matching, the entry is left untouched rather than
popped and pushed for a value that only normalization changed."
  (maf--with-calc-buffer
    (let ((at-point (calc-locate-cursor-element (point))))
      (when (> (calc-stack-size) 0)
        ;; An active selection anywhere outranks point, as it does in
        ;; `maf--resolve-context' — it is the more deliberate gesture,
        ;; and the entry it sits on is the subject even when point has
        ;; wandered to another. `maf--sel-effective-m' picks the one
        ;; under point when that entry is the selected one. Failing any
        ;; selection, the entry at point, and at home the top.
        (let* ((m (or (and calc-use-selections (maf--sel-effective-m))
                      (and (> at-point 0) at-point)
                      1))
               (entry (calc-top m 'entry))
               (expr (car entry))
               (explicit (and calc-use-selections (nth 2 entry)))
               ;; Only consult point for a sub-formula when point is on
               ;; the entry this resolved to; otherwise the selection
               ;; is all there is to read, and reading it must not move
               ;; point.
               (sel (and calc-use-selections
                         (if (and (= m at-point) (not explicit))
                             (ignore-errors (calc-auto-selection entry))
                           explicit)))
               (snapshot (maf--point-snapshot))
               (maf--sel-marked nil)
               (calc-simplify-mode (if no-simplify 'none calc-simplify-mode))
               (rewritten
                (cond
                 ;; Nothing named: the whole entry is the subject, and
                 ;; the walk finds the first site in it a rule reaches.
                 ((not (consp sel))
                  (maf--sel-rewrite-entry expr expr rules as-division))
                 ;; An active selection is a deliberate gesture and is
                 ;; never widened, as everywhere else in maf — the mark
                 ;; goes exactly where the user put it, which is also
                 ;; what calc's own commands do with it. The site is
                 ;; then fixed too: the formula holding the selection,
                 ;; since that is what a rule reads around it.
                 (explicit
                  (let ((site (calc-find-parent-formula expr sel)))
                    (and (consp site)
                         (maf--sel-rewrite-try expr site sel rules
                                               as-division))))
                 (t (maf--sel-rewrite-widen expr sel rules as-division)))))
          (when rewritten
            ;; No `calc-encase-atoms' here, deliberately: calc wraps
            ;; every atom of a rewrite's result in (cplx n 0) so the
            ;; reselected node has a cons to be identified by. maf
            ;; reselects nothing, and under no simplification those
            ;; wrappers are never folded away again — they would ride
            ;; into the entry as the value 3 spelled (cplx 3 0).
            ;; No normalizing pass over the whole result, and no
            ;; `calc-encase-atoms' either. The rewriter already
            ;; normalized the site it rewrote; running it again over
            ;; the entry would reach the parts the gesture never named
            ;; and fold those too — merging the logarithms of
            ;; ln(a) + ln(b) + x^p x^q would collapse the powers as
            ;; well. Encasing is calc wrapping every atom as (cplx n 0)
            ;; so a reselected node has a cons to be identified by; maf
            ;; reselects nothing, and unsimplified those wrappers are
            ;; never folded away again, riding into the entry as the
            ;; value 3 spelled (cplx 3 0).
            (let* ((expanded (maf--sel-expand-pow rewritten))
                   ;; Ordering only where the simplifier was held off:
                   ;; with it running, calc has already ordered what it
                   ;; built.
                   (new (maf--sel-unmark
                         (if no-simplify
                             (maf--sel-coefficient-first expanded)
                           expanded))))
              ;; `calc-wrapper' makes the commit one undoable unit.
              ;; Without it the pop and push join whatever undo group
              ;; is already open, and a single undo takes back more
              ;; than this command did. The rewrite itself is computed
              ;; above, outside the wrapper, so the paths that commit
              ;; nothing run calc's epilogue not at all and leave point
              ;; exactly where it was.
              (calc-wrapper
               (calc-pop-push-record-list 1 prefix (list new) m (list nil)))
              ;; The epilogue parks point at home; put it back on the
              ;; part the rules marked as the outcome — when point was
              ;; on an entry to begin with. From home the gesture named
              ;; no part, and point stays home as it does after any
              ;; other command run from there.
              (or (and (> at-point 0)
                       (consp maf--sel-marked)
                       (maf--anchor-on-node m maf--sel-marked))
                  (maf--point-restore snapshot))
              ;; A single undo reverts point along with the stack.
              (maf--undo-record-cmd-point snapshot))))))))

(defun maf-distribute ()
  "Spread the formula around the target inward over its parts.

  x*(a| + b)  =>  x b| + x a

Point picks the target as usual — the sub-formula under the cursor, or
the active selection when there is one — and calc's DistribRules do
the spreading. Each rule reads the operation *around* what it marks,
so the marked part is often not the term point names: on the a above
it is the product that distributes. maf looks outward from point for
the innermost formula some rule reaches, and marks the part of it the
rule wants, preferring the part point is in. So any position on the
entry works — on a term, on the operator joining them, or on the name
of the function being distributed.

  (a + b) / x  =>  b / x + a / x
  sqrt(a b)    =>  sqrt(b) sqrt(a)
  ln(a b)      =>  ln(b) + ln(a)
  ln(x^2)      =>  2 ln(x)
  log(x^p, b)  =>  log(x, b) p
  x^(a + b)    =>  x^b x^a
  sin(a + b)   =>  sin(b) cos(a) + cos(b) sin(a)
  (x + y)^2    =>  y^2 + 2 x y + x^2

The result is calc's, committed unsimplified — without which the
simplifier folds a distributed power straight back to x^(a + b) — so
the parts come out in whatever order the rules name them, which need
not be the order they were written in. A numeric coefficient is the
exception, moved to the front as calc writes it: ln(x^2) gives
2 ln(x), not ln(x) 2. Only numbers move, that being the one part of
calc's ordering that cannot undo a rewrite, so a symbolic coefficient
stays where the rule put it. Nothing is left selected for the next
keystroke to trip over, and point follows the part the rules mark as
the outcome; from home it stays home.

A literal fraction distributes too, though calc stores one as a single
atom no `a / b' rule can match. It is read as an explicit division
first, which both makes it distribute at all and avoids the wrong
answer stock calc gives it — sqrt(3:4) rewritten by the negation rule
comes out as i sqrt(-3:4), which is -sqrt(3)/2.

  sqrt(3:4)  =>  sqrt(1/4) sqrt(3)
  ln(3:4)    =>  ln(1/4) + ln(3)

A selection standing anywhere is the target, whatever entry point is
on — it is the more deliberate gesture, and this is where the rest of
maf takes its subject too. With none, the entry at point, or the top
entry at home, and the rules apply at the first site in it they reach.

An active selection is never widened, as everywhere else in maf: the
mark goes exactly where it was put, so a selection the rules cannot
use leaves the entry alone instead of reaching past it.

Only the formula the rule matches is rewritten; the rest of the entry
is carried over as it was. A second site the gesture never named keeps
its shape, unsimplified arithmetic included.

Two of calc's rules split a sign off a negation, and its matcher reads
any expression at all as one, since -(-a) is a. Left to themselves
they would claim every marker before the rule the gesture meant, so a
split of a sign the marked node does not have is passed over — on the
x of ln(x^2) it is the log-of-a-power rule that fires, not the answer
ln((-1)^2 (-x)^2). A genuinely negative operand still splits.

  sqrt(-x)  =>  sqrt(-1) sqrt(x)
  (-x)^2    =>  (-1)^2 x^2

One rule fires per invocation, so unfolding a nested distribution is
repeated keystrokes rather than one. With no rule matching — a term
with nothing to spread, or a shape the rules do not reach — the entry
is left untouched, nothing pushed or popped, rather than signaling."
  (interactive)
  (maf--sel-rewrite (calc-var-value 'var-DistribRules) "dist" t t))

(defun maf-merge ()
  "Collect the target into the formula around it.

  x a + x b|  =>  x*(a + b|)

The reverse of `maf-distribute', on calc's own MergeRules: a common
factor comes out of a sum, a shared denominator collects, powers of
one base add, two logarithms or roots combine into one. Point picks
the target as usual — the sub-formula under the cursor, or the active
selection when there is one — looking outward for the innermost
formula some rule reaches and marking the part of it the rule wants,
so any position on the entry works. Where two parts of one formula
would both serve, the one point is in decides which is marked.
Nothing is left selected, and point follows the merged part; from home
it stays home.

  a / x + b / x    =>  (a + b) / x
  x^a x^b          =>  x^(a + b)
  ln(a) + ln(b)    =>  ln(a b)
  sqrt(a) sqrt(b)  =>  sqrt(a b)
  exp(a) exp(b)    =>  exp(a + b)

The merged coefficients are left as the rules built them rather than
folded together, since the rule marks its result and calc does not
simplify across the mark:

  2 x + 3 x  =>  x*(2 + 3)

A selection standing anywhere is the target, whatever entry point is
on; with none, the entry at point, or the top entry at home. An active
selection is never widened, as everywhere else in maf, and only the
formula the rule matches is rewritten — a second site the gesture
never named keeps its shape.

Two of calc's rules for collecting powers of unlike bases answer with
the wrong value, and two more get the exponent wrong; maf corrects all
four, so a^x / b^x collects to (a / b)^x from either end of the
quotient rather than to 1.

One rule fires per invocation. With no rule matching — nothing beside
the target to collect it with — the entry is left untouched, nothing
pushed or popped, rather than signaling."
  (interactive)
  (maf--sel-rewrite (maf--merge-rules) "merg"))

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

(defconst maf--calc-own-variables
  '("AlgSimpRules" "CommuteRules" "Decls" "DistribRules" "EvalRules"
    "ExtSimpRules" "FactorRules" "FitRules" "GenCount" "Holidays"
    "IntegAfterRules" "IntegLimit" "IntegRules" "IntegSimpRules"
    "InvertRules" "JumpRules" "LineStyles" "MergeRules" "Modes"
    "NegateRules" "PlotRejects" "PointStyles" "RandSeed" "TimeZone"
    "UnitSimpRules" "Units"
    "e" "gamma" "i" "phi" "pi" "γ" "π" "φ")
  "Names of the variables calc owns, without the `var-' prefix.
Its constants, the rewrite-rule sets it consults by name, and the
settings and hooks it documents as belonging to it — everything it
either defines itself or reads if the user defines it.

`maf-browse-variables' groups by this list: a name on it is calc's,
anything else is the user's, and the two are listed apart. The quick
registers (q0-q9) are deliberately absent — calc defines them, but
what they hold is the user's, which is the distinction the grouping
is about.

A name calc introduces that is missing here is simply listed as the
user's. That is the failure worth having: the list is a claim about
calc, and an unlisted name lands in the group the user is looking
at rather than being hidden among the constants.")

(defun maf--calc-own-variable-p (name)
  "Return non-nil if NAME is one of calc's own variables.
See `maf--calc-own-variables'."
  (and (member name maf--calc-own-variables) t))

(defun maf--variable-names ()
  "Names of the calc variables `maf-browse-variables' offers.
Without the `var-' prefix, the user's own first and calc's after,
each group alphabetical. Yours is the group you came for — calc's
constants are a handful of fixed values that never change and never
need looking up, so they sit below rather than alphabetically among
what you stored.

Every variable that holds a value, less the ones
`maf-browse-variables-exclude' matches — by default the formula
library, calc's rewrite-rule sets, and its settings, none of them a
value anyone recalls onto a stack. The exclusion is only about the
list: `maf--variable-value-string' still renders whatever name it is
handed.

A variable bound to nil is unset as far as calc is concerned —
`calc-recall' refuses one — so it is left out, which is also what
keeps the `var-' symbols that are only declared off the list."
  (let (names)
    (mapatoms
     (lambda (sym)
       (let ((name (symbol-name sym)))
         (when (and (string-prefix-p "var-" name)
                    (boundp sym)
                    (symbol-value sym))
           (let ((name (substring name 4)))
             (unless (seq-some (lambda (re) (string-match-p re name))
                               maf-browse-variables-exclude)
               (push name names)))))))
    (append (sort (seq-remove #'maf--calc-own-variable-p names) #'string<)
            (sort (seq-filter #'maf--calc-own-variable-p names) #'string<))))

(defun maf--variable-value-string (name)
  "One-line rendering of calc variable NAME's value, or nil.
What recalling it would land, not what the symbol holds: the value
goes through `calc-var-value' and `calc-normalize', the two steps
`calc-recall' takes, so a rewrite-rule set shows as the parsed set
rather than as the function symbol standing in for it until first use,
and pi as its number rather than as the (special-const (math-pi)) form
it is stored as.

Formatted in calc's Flat language whatever the display language is —
an annotation has one line to work with, and both `big' notation and
an ordinary matrix are laid out across several — and with
simplification off, matching the recall itself. Unreadable contents (a
string-valued variable that no longer parses) give nil rather than
signal: the browser still lists the variable, and recalling it is what
should report the problem."
  (maf--with-calc-buffer
    (when-let* ((val (ignore-errors (calc-var-value (intern (concat "var-" name)))))
                (str (ignore-errors
                       (let ((calc-language 'flat))
                         (math-format-value (maf--literal (calc-normalize val)))))))
      ;; Flat lays out on one line by construction; this is the guard
      ;; for a value that breaks the rule anyway (an embedded string),
      ;; and it collapses the padding along with the newlines.
      (string-join (split-string str) " "))))

(defun maf--variable-separator (width)
  "A rule WIDTH wide, the divider between the two variable groups.
It goes in as a candidate of its own rather than as completion
`group-function' metadata, which only some UIs render; a candidate is
a line in every one of them. Made of a character no variable name can
contain, so typing anything at all filters it away, and
`maf-browse-variables' refuses it if it is somehow chosen."
  (make-string width ?─))

(defun maf-browse-variables ()
  "Recall a calc variable picked off a list of what they hold.

  Recall variable: height   9.8 t + 3
                   mass     70
                   ──────   calc vars
                   e        2.71828182846
                   pi       3.14159265359

Completing-read over the names, each annotated with the value it would
push, so the variable is chosen by looking at the values rather than by
remembering which name holds what. Offered are the ones you stored
\(\\`s s') and calc's constants — everything holding a value except
what `maf-browse-variables-exclude' filters out, which by default is
everything that is not arithmetic: the formula library, the
rewrite-rule sets, and calc's settings.

Yours come first and calc's follow, under a rule dividing them: the
constants are a handful of fixed values that never change, and mixing
them alphabetically through what you stored would be the list you did
not come for. The rule is inert — typing anything filters it away, and
choosing it is refused.

The chosen variable is pushed as a new stack entry with simplification
off, so what was stored is what lands — a stored x + x stays x + x.
Calc's own \\`s r' is the unannotated version of the same recall,
reaches the excluded names too, and keeps its key. The push parks
point at home, as calc's own does; a mark is left where point was, so
\\[maf-go-home] (or \\[pop-to-mark-command]) goes back to it.

An annotation is computed when it is first shown and remembered for
the rest of the prompt: rendering a value is unbounded work — a stored
matrix or a long vector is one entry on this list — and nothing pays
for one that is never scrolled to."
  (interactive)
  (require 'calc-ext)
  (let* ((names (or (maf--variable-names)
                    (user-error "No calc variable to recall")))
         (width (apply #'max (mapcar #'length names)))
         ;; What is left of the line once the name column and its
         ;; gutters are spoken for; a long vector would otherwise run
         ;; off the frame and take the candidate with it.
         (limit (max 20 (- (frame-width) width 8)))
         ;; Where the user's names end and calc's begin. Both groups
         ;; have to be non-empty for there to be a boundary worth
         ;; drawing.
         (split (seq-count (lambda (n) (not (maf--calc-own-variable-p n)))
                           names))
         (rule (and (> split 0) (< split (length names))
                    (maf--variable-separator width)))
         (candidates (if rule
                         (append (seq-take names split) (list rule)
                                 (seq-drop names split))
                       names))
         (cache (make-hash-table :test #'equal))
         (table (lambda (string pred action)
                  (if (eq action 'metadata)
                      ;; Yours, the rule, then calc's is the whole point
                      ;; of the list; a UI that sorts would alphabetize
                      ;; the groups back together and strand the rule.
                      '(metadata (display-sort-function . identity)
                                 (cycle-sort-function . identity))
                    (complete-with-action action candidates string pred))))
         (completion-extra-properties
          (list :annotation-function
                (lambda (name)
                  (let ((str (if (equal name rule)
                                 "calc vars"
                               ;; A variable with no readable value
                               ;; caches "", a hit like any other — the
                               ;; cost of finding that out is paid once.
                               (or (gethash name cache)
                                   (puthash name
                                            (or (maf--variable-value-string name)
                                                "")
                                            cache)))))
                    (concat (make-string (max 1 (- (+ width 2) (length name))) ?\s)
                            (truncate-string-to-width str limit 0 nil t))))))
         (name (completing-read "Recall variable: " table nil t)))
    (when (equal name rule)
      (user-error "That is the divider, not a variable"))
    ;; The push parks point at home; mark where the user was first, so a
    ;; single `pop-to-mark-command' returns there, as every maf command
    ;; that homes point does.
    (unless (maf--at-home-p) (maf--mark-before-home))
    (maf--literal (calc-recall (intern (concat "var-" name))))))

(defun maf--recall-literal (var)
  "Push VAR's stored value with simplification off, marking the way back.
The shared trunk of the recall commands: what was stored is what lands
— a stored x + x stays x + x instead of collapsing to 2 x — the push
parks point at home as calc's own recall does, and a mark is left
where point was so \\[maf-go-home] returns to it. An empty VAR signals
here; `calc-recall' signals for one that holds no value."
  (unless var (user-error "No variable to recall"))
  (unless (maf--at-home-p) (maf--mark-before-home))
  (maf--literal (calc-recall var)))

(defun maf-recall-variable ()
  "Recall a variable read from the minibuffer, without simplification.
Calc's prompt recall (s r, which keeps its key and its simplifying
push) with the literal push of `maf-browse-variables' (p), which is
the annotated version of this same recall — this one asks by name.
The prompt is read before any calc state is touched, so C-g aborts
with nothing done. Bound to r r, unbound in calc itself."
  (interactive)
  (require 'calc-ext)
  (maf--recall-literal (calc-read-var-name "Recall: ")))

(defun maf-recall-quick ()
  "Recall quick variable q0-q9, without simplification.
Calc's own quick recall on the same keys renormalizes the value under
the current modes on the way out; this push is literal, so what s 0-9
stored is what lands. The digit is the key that invoked the command,
exactly as calc's `calc-recall-quick' reads it."
  (interactive)
  (maf--recall-literal (intern (format "var-q%c" last-command-event))))

;;; Vector access

(defun maf--nth-digit-index (expr)
  "The element index the invoking digit key names, checked against EXPR.
Shared by `mafcmd-nth-element' and its inverse: the digit is read off
`last-command-event', as quick recall reads its own digit keys.
Signals when the invoking key was no digit, or when EXPR is a vector
with fewer elements than the digit names; nil when EXPR is not a
vector at all, where the caller commits it unchanged."
  (let ((n (- last-command-event ?0)))
    (unless (<= 1 n 9)
      (user-error "%s reads its element from a digit key" this-command))
    (when (eq (car-safe expr) 'vec)
      (if (> n (1- (length expr)))
          (user-error "No element %d: only %d element%s" n
                      (1- (length expr))
                      (if (= (length expr) 2) "" "s"))
        n))))

(maf-defcmd mafcmd-remove-nth-element (expr _arg commit)
  "Remove the element the digit key names from the resolved vector.

  [10, 20, 30]  =>  [10, 30]   (the 2 key)

The complement of `mafcmd-nth-element', reached through its Inverse
flag: the digit names the same element, and everything else is what
commits. The remaining elements are kept literally — not
renormalized. A resolved expression that is not a vector commits
unchanged, and equation sides without one pass through quietly; a
digit past the vector's end signals instead. Point picks the target
as usual: a sub-formula at point, each side of an equation, the top
entry at home."
  :arity unary
  :prefix "rmnth"
  (let ((n (maf--nth-digit-index expr)))
    (commit (if n
                (append (cl-subseq expr 0 n) (nthcdr (1+ n) expr))
              expr))))

(maf-defcmd mafcmd-nth-element (expr _arg commit)
  "Take the element of the resolved vector the digit key names.

  [10, 20, 30]  =>  20   (the 2 key)

The digit is the key that invoked the command, as quick recall reads
its own digit keys: pressing 2 takes the second element, 1 the first,
up to 9. The element is lifted out literally — not renormalized, so
what the vector held is what lands. A resolved expression that is not
a vector commits unchanged, and equation sides without one pass
through quietly; a digit past the vector's end signals instead. Point
picks the target as usual: a sub-formula at point, each side of an
equation, the top entry at home.

  [a, b] = v            =>  b = v   (the v side: unchanged, the 2 key)
  [a, b] with the 5 key =>  error: only 2 elements

Inverse: the complement — the vector with that element removed
\(`mafcmd-remove-nth-element').

  [10, 20, 30]  =>  [10, 30]   (I then the 2 key)"
  :arity unary
  :prefix "nth"
  :inverse mafcmd-remove-nth-element
  (let ((n (maf--nth-digit-index expr)))
    (commit (if n (nth n expr) expr))))

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

(defconst maf--solve-order-heads
  '(calcFunc-lt calcFunc-leq calcFunc-gt calcFunc-geq)
  "Relation heads with a direction the solver must not lose.")

(defun maf--solve-split-p (expr)
  "Non-nil when EXPR is the sign-split `maf--solve-relation' writes.
Calc's if with a relation in the true branch; the false branch is
the next case — another such if, a relation, or the zero case's
residue: the truth value (1, 0) the coefficient-free relation
collapsed to, or that relation itself when its constant term stays
symbolic."
  (and (eq (car-safe expr) 'calcFunc-if)
       (= (length expr) 4)
       (maf--relation-p (nth 2 expr))
       (let ((tail (nth 3 expr)))
         (or (maf--relation-p tail)
             (memql tail '(0 1))
             (maf--solve-split-p tail)))))

(defun maf--solve-relation (rel var)
  "Solve REL for VAR as `math-solve-eqn' does, direction preserved.
Calc keeps an inequality's direction only while it knows the sign of
what it divides by: solving 2 x k - 2 < 0 for x degrades to
x != 1/k, and the <= form fails outright, the direction thrown away
either way. When REL is linear in VAR the direction is exactly the
sign of the leading coefficient, so those solves come back as calc's
if, split three ways on that sign:

  2 k > 0 ? x < 1/k : 2 k < 0 ? x > 1/k : -2 < 0

the zero case last — the relation with its variable term gone, so no
branch quietly claims x > 1/0. The if collapses to the case that
holds once k is known — substitute a value and it evaluates away, the
zero case to plain truth (1 here: -2 < 0 holds for every x). A degradation past
linear (x^2 < 4 asks for an interval, which calc cannot say) returns
nil with a message, keeping the misleading != off the stack; all
else — equations, !=, an inequality whose signs calc can see —
passes through as calc solved it."
  (let ((head (car-safe rel))
        (plain (math-solve-eqn rel var nil)))
    (if (or (not (memq head maf--solve-order-heads))
            (and plain (memq (car-safe plain) maf--solve-order-heads)))
        plain
      ;; Built under default simplifications whatever the session's
      ;; simplify mode, so the split's own normalize folds the bound
      ;; the same way every time (mode none would keep x < 2/(2 k)).
      (let* ((calc-simplify-mode nil)
             (coeffs (math-is-polynomial
                      (math-sub (nth 1 rel) (nth 2 rel)) var 1))
             (lead (nth 1 coeffs)))
        (cond
         ((and (= (length coeffs) 2) (not (Math-zerop lead)))
          (let ((bound (math-normalize
                        (math-div (math-neg (car coeffs)) lead)))
                (keep head)
                (flip (maf--flip-relation-op head)))
            ;; A leading coefficient written negative reads better
            ;; positive: -c > 0 ? A : B becomes c > 0 ? B : A.
            (when (math-looks-negp lead)
              (setq lead (math-neg lead))
              (cl-rotatef keep flip))
            (math-normalize
             (list 'calcFunc-if (list 'calcFunc-gt lead 0)
                   (list keep var bound)
                   (list 'calcFunc-if (list 'calcFunc-lt lead 0)
                         (list flip var bound)
                         ;; The zero case: the variable term gone, the
                         ;; relation is its constant term against 0 —
                         ;; a truth value once that term is numeric.
                         (list head (car coeffs) 0))))))
         ((math-expr-contains rel var)
          (message "Sign unknown past linear: the direction cannot be kept; solve the = form instead")
          nil))))))

(defun maf--solve-for-subexpr (rel target)
  "Solve relation REL for the sub-expression TARGET, or nil.
A plain variable is solved directly. A compound sub-expression is
isolated by substituting a fresh variable for it — calc cannot solve
for a compound directly through a nonlinear operator like sqrt — then
solving for that variable and substituting the sub-expression back."
  (if (eq (car-safe target) 'var)
      (maf--solve-relation rel target)
    (let* ((u (maf--solve-fresh-var rel))
           (soln (maf--solve-relation (math-expr-subst rel target u) u)))
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
                    (and (or (maf--relation-p target-result)
                             (maf--solve-split-p target-result))
                         t))
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
                        (maf--solve-relation rel var)))))))))
    ;; Nothing solvable: the subject commits unchanged, so no variable
    ;; was isolated after all and point has nothing to land on.
    (if (or (maf--relation-p result) (maf--solve-split-p result))
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
             ;; A sign-split lands on the variable in its first branch.
             (rel (cond ((maf--relation-p formula) formula)
                        ((maf--solve-split-p formula) (nth 2 formula))))
             ;; The matched cons comes from the formula itself, which is
             ;; what the composition machinery can locate on screen.
             (side (and rel
                        (cl-find var (list (nth 1 rel) (nth 2 rel))
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

  x + y = 5    =>  x = -y + 5   (again: y = -x + 5)
  2 x - 3 < 7  =>  x < 5
  k x < 1      =>  k > 0 ? x < 1/k : k < 0 ? x > 1/k : -1 < 0
  x + 3 != 7   =>  x != 4
  3 = 3        =>  3 = 3       (no variable: unchanged)

Equations and inequalities alike, the relation kept — calc flips an
inequality's sense when it must, and a direction that hinges on a
sign calc cannot see comes back as calc's if, split on that sign;
substituting a value for k later collapses the if to the branch that
holds. A direction that cannot be kept at all (x^2 < 4 asks for an
interval) leaves the entry unchanged with a message. A bare
expression is treated as = 0. The result stays exact: a root gives
sqrt(2), a ratio 1:2.

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
  x + y = 5   =>  x = -y + 5   (again: y = -x + 5)
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

(defun maf--solve-for-read-vars (default &optional prompt)
  "Read the variable(s) to solve for; return them as a calc expression.
DEFAULT is the variable name empty input stands for, or nil to require
input. PROMPT heads the prompt string, \"Solve for\" when nil. Several
names, separated by commas or spaces, come back as a vector, so a
system of equations can be solved for all its unknowns at once.
Anything calc cannot parse is a `user-error'."
  (let* ((prompt (or prompt "Solve for"))
         (input (string-trim
                 (read-string (if default
                                  (format "%s (default %s): " prompt default)
                                (concat prompt ": "))
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
exact. A solution calc leaves with its variable on the right is turned
round (see `maf--relation-var-left'), element-wise through a vector of
them. Calc leaves an unsolvable input as an unevaluated call to the
solver; that, and a calc signal raised along the way, both commit the
entry unchanged instead — unchanged means as written, so nothing turns."
  :arity unary
  :prefix "solv"
  :map -1
  :scope entry
  (let ((result (let ((calc-symbolic-mode t) (calc-prefer-frac t))
                  (condition-case nil
                      ;; An order inequality solved for one variable goes
                      ;; through the direction-preserving wrapper; the
                      ;; other solvers and vector subjects go to calc.
                      (if (and (eq maf--solve-for-func 'calcFunc-solve)
                               (eq (car-safe maf--solve-for-vars) 'var)
                               (memq (car-safe expr) maf--solve-order-heads))
                          (maf--solve-relation expr maf--solve-for-vars)
                        (funcall maf--solve-for-func expr maf--solve-for-vars))
                    (error nil)))))
    (commit (if (or (null result)
                    (eq (car-safe result) maf--solve-for-func))
                expr
              (maf--relation-var-left result)))))

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
treated as = 0, inequalities keep their relation — one whose direction
hinges on a sign calc cannot see comes back as calc's if, split on
that sign — and an input Calc cannot solve for the named variable
commits unchanged.

The solution is written with its variable on the left. Calc leaves an
inequality whose sign flipped reading the other way round (-2 < x); it
is turned back, direction and all, so every solved form leads with the
variable that was solved for.

  x + y = 5                     =>  y = 5 - x       (typed: y)
  [x + y = 3, x - y = 1]        =>  [x = 2, y = 1]  (typed: x,y)
  2 x - 3 < 7                   =>  x < 5
  k x < 1                       =>  k > 0 ? x < 1/k : k < 0 ? x > 1/k : -1 < 0
  -2 x < 4                      =>  x > -2          (turned, sense kept)
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

(defun mafcmd-roots-for ()
  "Find all roots of the entry at point, for a variable from the minibuffer.

  x^2 - 4  =>  [2, -2]

The variable is read as `mafcmd-solve-for' (i) reads it: the prompt
offers the subject\='s priority variable as its default — x, y, z, t
first, then alphabetical — so RET takes the variable the entry
suggests. The roots come back as a vector, complete with multiplicity,
exact whatever the mode, a family\='s leftover freedom named by a dummy
variable (n1 over the integer multiples of a periodic root). A bare
expression is treated as = 0, and an input calc cannot take roots of
for the named variable commits unchanged.

It acts on the whole entry — wherever point sits on its line, or the
top entry at home; root-finding has no sub-formula meaning, so point
within the formula is not used to narrow it. The stock form stays on
a P (`mafcmd-roots\='), its variable taken from the stack, and
`mafcmd-poly-roots\=' (l T) picks the variable itself.

  x^2 = 4            =>  [2, -2]
  (x - 1)^2 (x + 2)  =>  [-2, 1, 1]   (multiplicity kept)
  2 x = 1            =>  [1:2]        (exact, not 0.5)
  x^2 + y^2 = 4      =>  [sqrt(-x^2 + 4), -sqrt(-x^2 + 4)]  (typed: y)
  y + 3              =>  y + 3        (typed: x — no x in it: unchanged)"
  (interactive)
  (when (or calc-inverse-flag calc-hyperbolic-flag)
    ;; calc\='s a P has no flag variants — roots already finds them all —
    ;; so refuse rather than drop the flag silently, consuming it as
    ;; the defcmd dispatcher would.
    (let ((flag (if calc-inverse-flag "inverse" "hyperbolic")))
      (setq calc-inverse-flag nil
            calc-hyperbolic-flag nil)
      (calc-set-mode-line)
      (user-error "No %s variant for this command" flag)))
  ;; Read the prompt before any calc state is touched, so C-g aborts
  ;; with nothing done.
  (let ((maf--solve-for-vars
         (maf--solve-for-read-vars (maf--solve-for-default-var) "Roots for")))
    (call-interactively #'maf--roots-for-run)))
(put 'mafcmd-roots-for 'maf-command t)

(maf-defcmd maf--roots-for-run (expr _arg commit)
  "Take `calcFunc-roots' of the whole entry for `maf--solve-for-vars'.
The worker behind `mafcmd-roots-for' — see there. Takes the whole
entry (`:scope entry'), so point within the formula never narrows the
subject. Symbolic and prefer-frac, so a non-integer root stays exact.
Calc leaves input it cannot take roots of as an unevaluated call;
that, and a calc signal raised along the way, both commit the entry
unchanged."
  :arity unary
  :prefix "prts"
  :map -1
  :scope entry
  (let ((result (let ((calc-symbolic-mode t) (calc-prefer-frac t))
                  (condition-case nil
                      (calcFunc-roots expr maf--solve-for-vars)
                    (error nil)))))
    (commit (if (or (null result)
                    (eq (car-safe result) 'calcFunc-roots))
                expr
              result))))

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
  x^2 + y^2 = 1      =>  y = sqrt(-x^2 + 1)   (its own inverse)
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
  abs(x + y) < 5    =>  -y - 5 < x && x < -y + 5   (y is a parameter)

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
  :targets-var mafcmd-substitute-targets
  (commit (math-normalize
           (math-expr-subst expr maf--subst-old maf--subst-new))))

(maf-defcmd maf--substitute-arg-run (expr arg commit)
  "Like `maf--substitute-run', with the stack supplying the replacement.
The $ form of `mafcmd-substitute': the entry above the subject is the
replacement, and commit consumes it as the binary arg it is."
  :arity binary
  :prefix "sbst"
  :targets-var mafcmd-substitute-targets
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
naming the same variable twice ends with the later assignment standing
(`mafcmd-let') — and `mafcmd-let-each' evaluates its branches in that
same written order."
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

(defun maf--let-evaluate-subject (expr bindings)
  "Return EXPR evaluated under BINDINGS, a two-sided relation per side.
The sides evaluate separately, as the equation target used to run the
body: the values go in and each side folds, but evaluation never
rearranges the relation whole — 6 x + 12 = 18 y + 6 with x = 2 stays
24 = 18 y + 6, where whole evaluation would carry it further. A
chained relation, or anything else, evaluates in one piece."
  (if (and (maf--relation-p expr) (= (length expr) 3))
      (list (car expr)
            (maf--let-evaluate (nth 1 expr) bindings)
            (maf--let-evaluate (nth 2 expr) bindings))
    (maf--let-evaluate expr bindings)))

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

A vector of distinct variables is one joint set: every variable
bound at once for a single evaluation, a repeated variable's later
assignment standing — calc's own `s l' reading. A vector naming one
variable throughout is the exception: a joint set would silently keep
only its last value, so it branches instead — the subject evaluated
once per assignment, the results collecting in a vector —

  y = x - 2 with [x = 1, x = 2]  =>  [y = -1, y = 0]

and the Hyperbolic flag asks for that branching explicitly, whatever
the variables: see `mafcmd-let-each', which H M-RET runs.

Like any binary command, the entry at point is the subject and the top
of the stack is the argument, consumed on commit; at home the subject
is stack level 2. Point inside a formula does not narrow the subject
\=(`:scope explicit'): the entry is evaluated whole, each side of a
relation in turn (`maf--let-evaluate-subject', under `:map -1'),
wherever point rests on it — including on the argument, which
resolves to the entry below, so an assignment can be typed and used
without moving back to the formula it binds. A region or
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
  :hyperbolic mafcmd-let-each
  :map -1
  :pair -1
  :scope explicit
  (let ((bindings (maf--let-bindings arg)))
    (unless bindings
      (user-error "Top of stack is not an assignment, or a vector of them"))
    (commit
     (if (and (cdr bindings)
              (null (cdr (cl-remove-duplicates (mapcar #'car bindings)))))
         ;; One variable throughout: branches, as H would read it.
         (cons 'vec (mapcar (lambda (b)
                              (maf--let-evaluate-subject expr (list b)))
                            bindings))
       (maf--let-evaluate-subject expr bindings)))))

(maf-defcmd mafcmd-let-each (expr arg commit)
  "Evaluate the resolved expression once per top-of-stack assignment.

  y = 2 x + 1 with [x = 1, y = 2]   =>  [y = 3, 2 = 2 x + 1]
  x = 2 y - 1 with [x = 6, x = 0]   =>  [6 = 2 y - 1, 0 = 2 y - 1]

`mafcmd-let's Hyperbolic variant, H M-RET: where the plain command
binds a vector's assignments as one joint set for a single result,
here each assignment is a branch of its own — the subject evaluated
under it alone, the results collecting in a vector, in written order.
The shape solver output arrives in, so a solution vector feeds back
whole; the relations land as substitution leaves them, like any let
over a relation, and a mapped auto-solve (M M-i) carries the example
above on to the solved [y = 3, x = 1:2].

The subject arrives whole (`:map -1') so each branch's result is a
whole relation — its sides evaluated in turn by
`maf--let-evaluate-subject', never rearranged whole and never
re-paired across branches. A lone assignment is one branch: the
result is still a vector, of one. Everything else — what counts as an
assignment, how the subject resolves, keep-args — is `mafcmd-let's."
  :arity binary
  :prefix "let"
  :map -1
  :pair -1
  :scope explicit
  (let ((bindings (maf--let-bindings arg)))
    (unless bindings
      (user-error "Top of stack is not an assignment, or a vector of them"))
    (commit (cons 'vec (mapcar (lambda (b)
                                 (maf--let-evaluate-subject expr (list b)))
                               bindings)))))

;;; Mapping

(defconst maf--map-param '(var $ var-$)
  "The variable standing for the element a mapping formula applies to.
A $ in the formula is read as this variable (see `maf--map-read'), and
applying the mapper substitutes the element for it. The name is
unforgeable: $ is a token in calc's syntax, never an identifier, so no
formula the user types can name this variable by accident.")

(defconst maf--map-param2 '(var $$ var-$$)
  "The variable standing for the subject's element in a $$ formula.
A $$ turns the mapping binary (see `maf--map-read'): this variable
takes the subject's elements while `maf--map-param' takes the consumed
top entry's — the levels calc's own $$ and $ name. Unforgeable as the
first parameter is.")

(defun maf--map-function-symbol (var)
  "Return the calc function symbol the variable node VAR names.
sin gives `calcFunc-sin' — a symbol whether or not calc defines it, so
the caller can validate its definition and arity."
  (intern (concat "calcFunc-" (symbol-name (nth 1 var)))))

(defun maf--map-function-accepts-one-p (func)
  "Return non-nil when Calc function FUNC accepts one argument."
  (pcase-let ((`(,min . ,max) (func-arity func)))
    (and (<= min 1)
         (or (eq max 'many)
             (and (integerp max) (>= max 1))))))

(defun maf--map-from-expr (expr &optional subject)
  "Return the mapper EXPR describes, as a cons of (PARAM . BODY).
Applying it substitutes the mapped element for PARAM in BODY. EXPR is a
parsed formula, from the stack or from the prompt, in one of three
shapes:

  <x : x^2>   a nameless function — its own parameter and body
  sin         a bare one-argument function name — the call it names
  x^2         a formula with one free variable — that variable

A name calc knows is read as the function, so a variable of the same
name cannot be mapped bare; write it as a formula ($ sin) to mean the
variable. A formula with no variable has nothing to map over, and one
with several does not say which of them is the element: with SUBJECT —
the expression being mapped, which the stack form has in hand — the
choice is asked for (see `maf--map-choose-element'), without it the
refusal points at the $ that marks the element inline at the prompt."
  (cond
   ((eq (car-safe expr) 'calcFunc-lambda)
    ;; An element is one thing, so only the one-argument form maps.
    (if (= (length expr) 3)
        (cons (nth 1 expr) (nth 2 expr))
      (user-error "Mapping takes a one-argument function")))
   ((and (eq (car-safe expr) 'var)
         (fboundp (maf--map-function-symbol expr)))
    (let ((func (maf--map-function-symbol expr)))
      (unless (maf--map-function-accepts-one-p func)
        (user-error "Mapping function %s does not take one argument"
                    (nth 1 expr)))
      (cons maf--map-param (list func maf--map-param))))
   (t
    (let ((vars (maf--solve-sorted-vars expr)))
      (pcase (length vars)
        (1 (cons (car vars) expr))
        (0 (user-error "Nothing to map: %s has no variable in it"
                       (math-format-value expr)))
        (_ (if subject
               (cons (maf--map-choose-element vars subject) expr)
             (user-error "Several variables: mark the element with $"))))))))

(defun maf--map-subject-noun (expr)
  "The word for EXPR in the element prompt: what is being mapped.
A vector of vectors reads as the matrix it renders as; an = as an
equation, its ordered kin as relations; anything else is an
expression, 7 and a + b alike."
  (cond ((and (eq (car-safe expr) 'vec)
              (cl-every (lambda (e) (eq (car-safe e) 'vec)) (cdr expr)))
         "matrix")
        ((eq (car-safe expr) 'vec) "vector")
        ((eq (car-safe expr) 'calcFunc-eq) "equation")
        ((maf--relation-p expr) "relation")
        (t "expression")))

(defun maf--map-choose-element (vars subject)
  "Ask which of VARS the SUBJECT maps over; the rest stay symbolic.
The stack form's way of naming the element: a formula typed at the
prompt marks it inline with $, but a stack formula is already built,
so refusing there would be a dead end — this prompt is the out, the
one-element reading of calc's argument-list prompt at V M $. VARS is
the formula's variable nodes; the answer must be one of them. SUBJECT
is the resolved expression being mapped, worded into the prompt by
its shape so the question says what is about to spread over the
chosen variable.

VARS arrive in solve-priority order (x, y, z, t ahead of the rest,
see `maf--solve-sorted-vars`); a prompt list is for scanning, not
solving, so it reads alphabetically here."
  (let* ((vars (sort (copy-sequence vars)
                     (lambda (a b) (string< (symbol-name (nth 1 a))
                                            (symbol-name (nth 1 b))))))
         (names (mapcar (lambda (v) (symbol-name (nth 1 v))) vars))
         (choice (completing-read
                  (format "Map %s over variable (%s): "
                          (maf--map-subject-noun subject)
                          (mapconcat #'identity names ", "))
                  names nil t)))
    (nth (seq-position names choice) vars)))

(defun maf--map-read-elementwise (input)
  "Parse INPUT, the typed formula rewritten with the element's $ supplied.
The second read behind `maf--map-read's operator and constant sugar."
  (let* ((calc-dollar-values (list maf--map-param))
         (calc-dollar-used 0)
         (expr (math-read-expr input)))
    (when (eq (car-safe expr) 'error)
      (user-error "Bad format in formula: %s" (nth 2 expr)))
    (cons maf--map-param expr)))

(defun maf--map-read ()
  "Read the mapping formula from the minibuffer; return a mapper.
A lone $ returns the symbol `stack' instead: the formula then comes
from the stack, exactly as answering $ at `mafcmd-substitute's
replacement prompt takes the replacement from there.

Anywhere else in the formula a $ stands for the element being mapped —
the one thing calc's own operator prompt uses it for — so 2 $ + 1 and
2 x + 1 say the same thing. The two readings never collide: a $ that
means the stack is the whole answer, a $ that means the element is part
of a larger formula.

A $$ turns the mapping binary (see `mafcmd-map'): the answer is then
a (pair P1 P2 BODY) list for `maf--map-pair-run', where the one-$
forms answer a (PARAM . BODY) cons. Top-level commas wrap the input
in the vector they imply, so $$, $ and [$$, $] read alike.

Input that names no element at all reads as an operation on it. An
operator on either end takes the element on that side: +2 adds 2,
-2 subtracts it, /2 halves, ^2 squares — and 2+ adds the same 2,
2- subtracts the element from it, 2/ divides it by the element. The
relations read the same way: > 0, == 0 and their kin build the
comparison with the element on the open side. A lone - negates. Any
other constant multiplies: 2 doubles, sqrt(2) scales by it. Only input
that would otherwise refuse reads this way — -x still negates, x + 2
still adds — so every formula that named its element before means what
it meant."
  (let ((input (string-trim (read-string "Map: "))))
    (when (string-empty-p input)
      (user-error "No formula given"))
    (if (string= input "$")
        'stack
      ;; Calc's reader refuses $ unless `calc-dollar-values' offers it
      ;; something to stand for; the placeholders are that something,
      ;; and `calc-dollar-used' comes back with the deepest one the
      ;; formula spent. Top-level commas read as the vector they imply
      ;; — $$, $ and [$$, $] say the same thing.
      (let* ((calc-dollar-values (list maf--map-param maf--map-param2))
             (calc-dollar-used 0)
             (exprs (math-read-exprs input))
             (expr (cond ((eq (car-safe exprs) 'error) exprs)
                         ((cdr exprs) (cons 'vec exprs))
                         (t (car exprs)))))
        (cond
         ;; A parse failure comes back as (error POSITION MESSAGE).
         ;; An operator on either end is not a formula at all until
         ;; the element fills that side (*2, /2, ^2, 2+, 2/ all fail
         ;; here) — those read again with the $ supplied where the
         ;; operator left room; anything else is malformed.
         ((eq (car-safe expr) 'error)
          (cond
           ;; A lone - is the one operator whole on its own: negation.
           ((string= input "-")
            (maf--map-read-elementwise "-$"))
           ((string-match-p "\\`[-+*/^%|<>=!]" input)
            (maf--map-read-elementwise (concat "$ " input)))
           ((string-match-p "[-+*/^%|<>=!]\\'" input)
            (maf--map-read-elementwise (concat input " $")))
           (t (user-error "Bad format in formula: %s" (nth 2 expr)))))
         ;; A $$ pairs a second operand and the mapping turns binary:
         ;; the subject's element rides $$, the consumed top entry's $.
         ((> calc-dollar-used 1)
          (list 'pair maf--map-param2 maf--map-param expr))
         ((> calc-dollar-used 0)
          (cons maf--map-param expr))
         ;; Parsed, but nothing names the element — no $, no variable.
         ;; +2 and -2 land here rather than above, their sign reading
         ;; as part of the number, and < 0 lands here too, calc's
         ;; reader seeing a date in the < ; a typed leading operator
         ;; is kept either way. Any other constant scales. The lambda
         ;; guard keeps a nameless function on the strict one-argument
         ;; check below.
         ((and (not (eq (car-safe expr) 'calcFunc-lambda))
               (null (maf--solve-sorted-vars expr)))
          (maf--map-read-elementwise
           (if (string-match-p "\\`[-+<>=!]" input)
               (concat "$ " input)
             (concat "$ * (" input ")"))))
         (t
          (maf--map-from-expr expr)))))))

(defun maf--map-apply (mapper expr)
  "Return EXPR with MAPPER applied to it.
A vector is mapped elementwise, and nested vectors recurse, so a matrix
maps over its individual elements rather than its rows. Anything else
is one element and takes the formula whole.

The result is normalized, as a substituted formula is: putting a value
in collapses what it makes constant, under the current simplification
mode."
  (if (eq (car-safe expr) 'vec)
      (cons 'vec (mapcar (lambda (e) (maf--map-apply mapper e)) (cdr expr)))
    ;; Apply through Calc's lambda path rather than substituting directly:
    ;; `math-build-call' protects parameters bound by a nested lambda from
    ;; replacement when they shadow this mapper's parameter.
    (math-normalize
     (math-build-call (list 'calcFunc-lambda (car mapper) (cdr mapper))
                      (list expr)))))

(defun maf--map-pair-apply (mapper expr arg)
  "Return EXPR and ARG mapped in lockstep through the pair MAPPER.
MAPPER is (pair P1 P2 BODY): P1 is $$'s slot and takes EXPR's side,
P2 is $'s and takes ARG's. Two vectors pair element by element and
must run the same length; nested vectors recurse, so matrices pair
cell by cell. A lone value beside a vector repeats for every element,
and two lone values apply the formula once, whole.

A relation as a whole operand refuses: side by side is the one-$
form's reading (`maf--map-relation'), and a pair of sides against a
vector's elements has no one pairing to mean. A relation met inside a
vector is different — an element is a value whatever its shape, so
solver output like [x = 6, x = 0] pairs entry by entry."
  (when (or (maf--relation-p expr) (maf--relation-p arg))
    (user-error "A relation maps with the one-$ form, not $$"))
  (pcase-let ((`(pair ,p1 ,p2 ,body) mapper))
    (cl-labels
        ((walk (a b)
           (cond
            ((and (eq (car-safe a) 'vec) (eq (car-safe b) 'vec))
             (unless (= (length a) (length b))
               (user-error "Lengths differ: %d and %d elements"
                           (1- (length a)) (1- (length b))))
             (cons 'vec (cl-mapcar #'walk (cdr a) (cdr b))))
            ((eq (car-safe a) 'vec)
             (cons 'vec (mapcar (lambda (e) (walk e b)) (cdr a))))
            ((eq (car-safe b) 'vec)
             (cons 'vec (mapcar (lambda (e) (walk a e)) (cdr b))))
            (t (math-normalize
                (math-build-call (list 'calcFunc-lambda p1 p2 body)
                                 (list a b)))))))
      (walk expr arg))))

(defun maf--map-relation (mapper rel reverse)
  "Return relation REL with MAPPER applied to both of its sides.
REVERSE reverses the relation's direction, which is what makes mapping
a decreasing formula over an inequality come out true.

An = maps unconditionally: equality survives any function. An
inequality does not — mapping -2 x over a < b gives -2 a > -2 b, not
-2 a < -2 b — and nothing here can tell whether the formula the user
typed increases or decreases. Rather than pick a direction and be
silently wrong half the time, the plain command refuses an inequality
and REVERSE is how the user states that the formula decreases.

Calc's own `a M' takes the other choice: it knows a handful of named
functions reverse, and keeps the direction for everything else — so
mapping the nameless <x : -2 x> over a < b returns the false
-2 a < -2 b. maf reverses by hand where it can already tell (see
`maf--negate-whole'), and asks here where it cannot.

A != is refused either way: a != b says nothing about f(a) and f(b)
unless f is one-to-one, and reversing has no meaning for it."
  (unless (= (length rel) 3)
    ;; Chained relations (a < b < c) have no single direction, the same
    ;; reason `maf--negate-whole' leaves them alone.
    (user-error "A chained relation has no single direction to map over"))
  (let ((op (car rel))
        (lhs (maf--map-apply mapper (nth 1 rel)))
        (rhs (maf--map-apply mapper (nth 2 rel))))
    (cond
     ((eq op 'calcFunc-eq) (list op lhs rhs))
     ((eq op 'calcFunc-neq)
      (user-error "Mapping over != needs a one-to-one formula, which this may not be"))
     (reverse (list (maf--flip-relation-op op) lhs rhs))
     (t (user-error
         "Mapping an inequality keeps its direction only for an increasing formula: use I to map and reverse it")))))

(defun maf--map-subject (mapper expr reverse)
  "Return EXPR mapped through MAPPER, REVERSE reversing a relation.
A relation is mapped side by side (see `maf--map-relation'); anything
else goes to `maf--map-apply', which spreads over a vector's elements
and takes a plain expression whole."
  (if (maf--relation-p expr)
      (maf--map-relation mapper expr reverse)
    (maf--map-apply mapper expr)))

(defvar maf--map-mapper nil
  "The mapper `maf--map-run' applies; bound per `mafcmd-map' call.
A (PARAM . BODY) cons, or (pair P1 P2 BODY) for the $$ form, whose
worker is `maf--map-pair-run'. Nil for the M $ form, whose formula is
the stack arg `maf--map-arg-run' receives.")

(defvar maf--map-reverse nil
  "Non-nil while a mapping command should reverse the relation it maps.
Bound per call from calc's Inverse flag — see `maf--map-relation'.")

(maf-defcmd maf--map-run (expr _arg commit)
  "Apply `maf--map-mapper' to the resolved expression.
The worker behind `mafcmd-map' — see there. Relations are consumed
whole (`:map -1') because mapping decides for itself what to do with
one: an = maps side by side, an inequality only under I. The subject
is the whole entry wherever point sits on it (`:scope explicit'):
mapping speaks of the entry's elements, so point within the formula
does not narrow it — a region or a calc selection still does."
  :arity unary
  :prefix "map"
  :map -1
  :scope explicit
  :targets-var mafcmd-map-targets
  (commit (maf--map-subject maf--map-mapper expr maf--map-reverse)))

(maf-defcmd maf--map-arg-run (expr arg commit)
  "Like `maf--map-run', with the stack supplying the formula.
The M $ form: the entry above the subject is the formula, read by
`maf--map-from-expr' and consumed as the binary arg it is."
  :arity binary
  :prefix "map"
  :map -1
  :scope explicit
  :targets-var mafcmd-map-stack-targets
  (commit (maf--map-subject (maf--map-from-expr arg expr) expr maf--map-reverse)))

(maf-defcmd maf--map-pair-run (expr arg commit)
  "Apply the pair mapper `maf--map-mapper' to the subject and the top.
The $$ form of `mafcmd-map' — see there. The subject supplies $$'s
elements and the consumed top entry $'s, the operand order every
binary command uses; `maf--map-pair-apply' walks the two in lockstep."
  :arity binary
  :prefix "map"
  :map -1
  :scope explicit
  :targets-var mafcmd-map-targets
  (commit (maf--map-pair-apply maf--map-mapper expr arg)))

(defun maf--map-dispatch (mapper)
  "Run the mapping worker MAPPER calls for, consuming calc's I flag.
MAPPER is what `maf--map-read' returns — a mapper, or `stack' for the
form that takes its formula from the stack. Shared by `mafcmd-map' and
`mafcmd-map-stack', which differ only in where the formula comes from."
  (let ((maf--map-reverse calc-inverse-flag))
    ;; Consumed here rather than left for the worker: the worker is a
    ;; plain defcmd with no variants of its own, and a flag still set
    ;; when it returns would carry into the next command.
    (setq calc-inverse-flag nil
          calc-hyperbolic-flag nil)
    (if (eq mapper 'stack)
        (call-interactively #'maf--map-arg-run)
      (let ((maf--map-mapper mapper))
        (call-interactively (if (eq (car-safe mapper) 'pair)
                                #'maf--map-pair-run
                              #'maf--map-run))))))

(defun maf--map-refuse-hyperbolic ()
  "Signal if calc's Hyperbolic flag is set, consuming it first.
Mapping has an inverse variant (reverse the relation) and no hyperbolic
one. A plain defun gets no flag checking from `maf-defcmd', so it makes
the macro's answer by hand rather than ignoring the prefix silently."
  (when calc-hyperbolic-flag
    (setq calc-inverse-flag nil
          calc-hyperbolic-flag nil)
    (calc-set-mode-line)
    (user-error "No hyperbolic variant for this command")))

(defun mafcmd-map ()
  "Map a formula you type over the target, contextually.

  [1, 2, 3]  =>  [1, 4, 9]        (typed: x^2)

Reads the formula in algebraic notation. It may name the element three
ways: a formula with one free variable (x^2), a $ in place of the
element (2 $ + 1), or a bare one-argument function name (sin). Input
that names no element reads as an operation on it: an operator on
either end takes the element on that side (+2 and 2+ add, -2 subtracts
2, 2- subtracts the element from it, /2 halves, 2/ divides 2 by it,
^2 squares, > 0 and == 0 build the comparison), a lone - negates, and
a bare constant multiplies (2 doubles). A lone
$ is the exception — it means the formula is on the stack, and is the same
gesture as `mafcmd-map-stack' (M $).

A $$ pairs a second operand and the mapping turns binary: $$ is the
subject's element and $ the top entry's — the entry above the
subject, consumed as any binary argument. [$$, $] over [a, b] with
[x, y] on top gives [[a, x], [b, y]], and bare top-level commas read
as that vector, so $$, $ says the same. The vectors pair index by
index and must run the same length, a lone value beside a vector
repeats for every element, and a relation as a whole operand refuses
— side-by-side mapping belongs to the one-$ form; an equation inside
a vector is an element like any other, so [$$, $] over solver output
pairs the solutions.

The subject is the whole entry at point, wherever point sits on its
line, or the top entry at home: mapping speaks of the entry's
elements, so point within the formula is not used to narrow it. A
region or a calc selection still narrows — the deliberate gestures —
so a selected vector maps in place, leaving what surrounds it alone.
A vector is mapped elementwise, and a matrix over its individual
elements.

  [1, 2] + k          =>  [1, 4] + k      (the vector selected)

An equation maps side by side — both sides through the same formula,
which is what keeps the equation saying something true.

  y = x + 1           =>  y^2 = (x + 1)^2

An inequality is refused: whether the direction survives depends on
the formula increasing or decreasing, and a formula typed at a prompt
cannot be asked. I maps it and reverses the direction, which is the way
to say the formula decreases.

  a < b               =>  -2 a > -2 b     (I, typed: -2 x)

The result is normalized under the current simplification mode. A
prefix argument is reserved for choosing rows over elements on a
matrix, which is not implemented yet."
  (interactive)
  (maf--map-refuse-hyperbolic)
  ;; Read the prompt before any calc state is touched, so C-g aborts
  ;; with nothing done.
  (maf--map-dispatch (maf--map-read)))
(put 'mafcmd-map 'maf-command t)

(defun mafcmd-map-stack ()
  "Map the formula on the stack over the target, contextually.

  x^2                                     (the formula, on top)
  [1, 2, 3]  =>  [1, 4, 9]

The same command as `mafcmd-map' (M :) with the formula taken from the
stack instead of a prompt — the shortcut for a formula already built
there, and the same thing a lone $ at M :'s prompt does. As for any
binary command, the formula is the entry above the subject (the top
entry at home) and is consumed on commit, so the subject must lie below
the top.

The formula names its element as at $'s prompt: one free variable, or a
bare one-argument function name. A nameless function (<x : x^2>) works
too, its own parameter being the element. A formula with several
variables asks which one is the element — the others stay symbolic —
where the prompt form refuses toward its inline $ marker instead.

Everything else — how the subject is picked, vectors elementwise,
equations side by side, inequalities only under I — is `mafcmd-map's."
  (interactive)
  (maf--map-refuse-hyperbolic)
  (maf--map-dispatch 'stack))
(put 'mafcmd-map-stack 'maf-command t)

(defconst maf--map-flag-carriers
  '(mafcmd-map-flag calc-fancy-prefix-other-key
    calc-inverse calc-hyperbolic calc-option calc-keep-args
    universal-argument digit-argument negative-argument)
  "Commands `maf-map-flag' survives, read by `maf--map-flag-expire'.
The flag's own setter and the machinery a pending flag rides through:
`calc-fancy-prefix-other-key' is what the next key actually runs while
a fancy prefix is live (it unreads the key and dispatches it for real),
the other fancy prefixes chain (M I N maps the inverse), and the
argument readers carry a prefix argument to the command they precede.")

(defun maf--map-flag-entry ()
  "Run `mafcmd-map' as \\`M :' or \\`M M', spending the pending map flag.
The flag and the prefix keymap are cleared first: the flag asks the
next command to map, and this command is its own mapping — left set it
would ask `mafcmd-map' to map the mapper."
  (interactive)
  (setq overriding-terminal-local-map nil
        maf-map-flag nil)
  (call-interactively #'mafcmd-map))

(defun maf--map-flag-stack ()
  "Run `mafcmd-map-stack' as \\`M $', spending the pending map flag.
See `maf--map-flag-entry'."
  (interactive)
  (setq overriding-terminal-local-map nil
        maf-map-flag nil)
  (call-interactively #'mafcmd-map-stack))

(defvar maf--map-flag-keys
  (let ((map (make-sparse-keymap)))
    (define-key map "$" #'maf--map-flag-stack)
    (define-key map ":" #'maf--map-flag-entry)
    ;; The doubled key: the prompt is the flag's commonest exit, and
    ;; M M reaches it without the shift : costs. Without this entry
    ;; the second M would only re-run the flag setter, a no-op.
    (define-key map "M" #'maf--map-flag-entry)
    ;; The parent collects digits as a prefix argument, but maf's
    ;; digits start a numeric entry: give them the fall-through every
    ;; other key gets, so M 1 + types the 1 and adds it plainly (the
    ;; entry is a command with no reading of the flag, which drops
    ;; it). An explicit prefix argument stays reachable through C-u.
    (dotimes (d 10)
      (define-key map (char-to-string (+ ?0 d))
                  #'calc-fancy-prefix-other-key))
    map)
  "Keymap live for the keypress after \\`M', over calc's fancy-prefix map.
Its parent is `calc-fancy-prefix-map', attached in `mafcmd-map-flag'
once calc-ext has defined it, so its changes are few: $ runs the
stack-formula mapping, : and a doubled M the prompting one, a digit
starts a numeric entry as it does
outside the flag (C-u still reads a prefix argument), and any other
key falls to `calc-fancy-prefix-other-key', which re-dispatches it
normally with the flag still set. Chaining a fancy prefix drops this
map with the re-dispatch, so \\`M I' keeps the flag but not the two
keys — chain as \\`I M $' instead.")

(defun maf--map-flag-expire ()
  "Sweep `maf-map-flag' once a command that does not read it has run.
On `post-command-hook' from `mafcmd-map-flag' until the flag is gone.
A `maf-defcmd' command consumes the flag itself at resolve time; this
hook is for every other next command — calc's or Emacs' own — which
would ignore the flag silently and leave it lying in wait for a later
command that does read it. Carrier commands (see
`maf--map-flag-carriers') pass it along instead.

The minibuffer passes it along too: a prompting command (l x, i)
reads its input before its defcmd worker runs, so while a minibuffer is
active the command the flag waits for has not happened yet — the
prompt's own keystrokes must not spend it."
  (cond ((null maf-map-flag)
         ;; A quit after M can leave the prefix keymap behind with the
         ;; flag already gone; sweep it with the hook.
         (when (eq overriding-terminal-local-map maf--map-flag-keys)
           (setq overriding-terminal-local-map nil))
         (remove-hook 'post-command-hook #'maf--map-flag-expire))
        ((> (minibuffer-depth) 0))
        ((not (memq this-command maf--map-flag-carriers))
         (setq maf-map-flag nil)
         (when (eq overriding-terminal-local-map maf--map-flag-keys)
           (setq overriding-terminal-local-map nil))
         (remove-hook 'post-command-hook #'maf--map-flag-expire))))

(defun mafcmd-map-flag (&optional n)
  "Set the map flag: the next contextual command maps over its subject.

  [x, y]  M N   =>  [-x, -y]      (negate, mapped over the elements)

Where `mafcmd-map' (M :) maps a formula you type and `mafcmd-map-stack'
(M $) maps one from the stack, M maps a command — any `maf-defcmd'
command, unary or binary, with no keymap of blessed operations behind
it (calc's V M reads its operator from a fixed table; a flag needs no
table). A binary command's argument is shared across the runs:

  [a, b]  5  M |   =>  [a | 5, b | 5]

A vector subject runs the command once per element, a matrix over its
individual elements — the same reading M gives one. A relation subject
runs it once per side, which most commands do anyway; under the flag
even commands that normally consume a relation whole (the | family,
solve) split it, since the flag is an explicit request to map — though
those forced commands split only an =. An ordered relation or a !=
refuses there: whether the direction survives depends on which way the
command bends, which a command, unlike $'s formula, has no way to
state. Any other subject is the degenerate map — the command runs
once on the whole entry, so M Q on a scalar is plain Q.

The flag lasts for exactly one command, like calc's K or I: it chains
with those prefixes (M I | runs |'s inverse variant, vconcatrev, once
per element), a second M is the formula prompt rather than a cancel
(C-g cancels), and a command that has no reading of it simply drops
it. It also survives a command's own prompt, so
M i on a vector of relations solves each one for the variable typed."
  (interactive "P")
  (calc-fancy-prefix 'maf-map-flag "Map..." n)
  (when maf-map-flag
    ;; Ride over calc's fancy-prefix map for the next keypress, adding
    ;; $ and M on top of it. The parent attaches here rather than at
    ;; the defvar: `calc-fancy-prefix-map' is calc-ext's, not yet
    ;; loaded when this file is.
    (unless (keymap-parent maf--map-flag-keys)
      (set-keymap-parent maf--map-flag-keys calc-fancy-prefix-map))
    (when (eq overriding-terminal-local-map calc-fancy-prefix-map)
      (setq overriding-terminal-local-map maf--map-flag-keys))
    (add-hook 'post-command-hook #'maf--map-flag-expire)))
(put 'mafcmd-map-flag 'maf-command t)

;;; Combinators

;; apply, fold, accumulate and the outer product take an operation
;; where the other vector commands take an operand, so none of them can
;; be a table row: a row applies its function to the resolved
;; expression, which for these builds a call one argument short that
;; `calc-normalize' can only hand back inert. They read the operation
;; from the keyboard instead, as calc's own V R and V O do — the
;; gesture is calc's, unchanged, and what widens is only the space the
;; key is looked up in. Calc reads a character and finds it in
;; `calc-oper-keys', a fixed table of blessed operations; these read a
;; whole key sequence and find it in maf's own map, so any command
;; carrying a `maf-operation' stamp qualifies (every mafcmd table row
;; does, and a hand-written command joins by stamping the property).
;; The formula routes come along with it: : types one, as it does
;; after the map flag.

(defun maf--operation-lambda (input nargs)
  "Build a Calc lambda of NARGS arguments from INPUT, a typed formula.
The formula names its arguments with its own free variables, taken in
alphabetical order: a - b subtracts right from left, b - a the other
way. Input already written as a lambda is taken as it stands."
  (let ((expr (math-read-expr input)))
    (when (eq (car-safe expr) 'error)
      (user-error "Bad format in formula: %s" (nth 2 expr)))
    (if (eq (car-safe expr) 'calcFunc-lambda)
        expr
      (let ((math-arglist nil))
        (calc-default-formula-arglist expr)
        (let ((args (sort math-arglist #'string-lessp)))
          (unless (= (length args) nargs)
            (user-error "Formula needs %d variable%s, not %d"
                        nargs (if (= nargs 1) "" "s") (length args)))
          (append '(calcFunc-lambda)
                  (mapcar (lambda (v)
                            (list 'var v (intern (concat "var-" (symbol-name v)))))
                          args)
                  (list expr)))))))

(defun maf--operation-of (command nargs)
  "Return COMMAND's operation as a Calc function of NARGS arguments.
Nil when COMMAND carries no `maf-operation' stamp, and the symbol
`arity' when it carries one of the wrong size — the two refusals the
reader reports differently."
  (let ((op (get command 'maf-operation)))
    (cond ((null op) nil)
          ((/= (cdr op) nargs) 'arity)
          ;; Calc wants the operation as a variable, not as the
          ;; calcFunc symbol the stamp records: `calcFunc-reduce' and
          ;; its kin convert back themselves and reject the symbol.
          (t (math-calcFunc-to-var (car op))))))

(defun maf--read-operation (msg nargs)
  "Read an operation of NARGS arguments from the keyboard and return it.
MSG names the combinator asking. Any command stamped with a
`maf-operation' of the right size answers, pressed on its own key —
so + is addition and a s the extended simplify — and : reads a typed
formula instead. C-g aborts. Rejections re-prompt rather than
signalling, so a mistyped key costs one keystroke."
  (let ((result nil))
    (while (not result)
      (let* ((seq (read-key-sequence
                   (format "%s (operation key, or : for a formula):" msg)))
             (cmd (key-binding seq t)))
        (cond
         ((equal seq (kbd "C-g")) (keyboard-quit))
         ((equal seq ":")
          (setq result (maf--operation-lambda
                        (string-trim (read-string (format "%s by formula: " msg)))
                        nargs)))
         (t
          (let ((op (and cmd (symbolp cmd) (maf--operation-of cmd nargs))))
            (cond
             ((eq op 'arity)
              (message "%s takes %d argument%s, not %d"
                       cmd (cdr (get cmd 'maf-operation))
                       (if (= (cdr (get cmd 'maf-operation)) 1) "" "s") nargs)
              (sit-for 1))
             ((null op)
              (message "%s is not an operation" (key-description seq))
              (sit-for 1))
             (t (setq result op))))))))
    result))

(defvar maf--combinator-op nil
  "The operation the combinator workers apply, bound per call.
Read from the keyboard by `maf--read-operation' before any calc state
is touched, so C-g aborts with nothing done.")

(defvar maf--combinator-op2 nil
  "The second operation `maf--inner-run' applies — the sum's.
See `maf--combinator-op'.")

(defvar maf--combinator-func nil
  "The Calc function a combinator worker calls, bound per call.
`calcFunc-reduce' or `calcFunc-rreduce' for the fold pair, and the
matching split for accumulate: the Inverse flag picks the direction
before the worker runs.")

(maf-defcmd maf--fold-run (expr _arg commit)
  "Fold the resolved vector by `maf--combinator-op'.
The worker behind `mafcmd-fold' — see there."
  :arity unary
  :prefix "fold"
  (commit (funcall maf--combinator-func maf--combinator-op expr)))

(maf-defcmd maf--accum-run (expr _arg commit)
  "Accumulate over the resolved vector by `maf--combinator-op'.
The worker behind `mafcmd-accum' — see there."
  :arity unary
  :prefix "accm"
  (commit (funcall maf--combinator-func maf--combinator-op expr)))

(maf-defcmd maf--apply-run (expr _arg commit)
  "Apply `maf--combinator-op' to the resolved vector's elements as arguments.
The worker behind `mafcmd-apply' — see there."
  :arity unary
  :prefix "appl"
  (commit (calcFunc-apply maf--combinator-op expr)))

(maf-defcmd maf--outer-run (expr arg commit)
  "Build the outer product of the resolved vector and the stack's.
The worker behind `mafcmd-outer' — see there."
  :arity binary
  :prefix "outr"
  :map -1
  (commit (calcFunc-outer maf--combinator-op expr arg)))

(maf-defcmd maf--inner-run (expr arg commit)
  "Build the inner product of the resolved vector and the stack's.
The worker behind `mafcmd-inner' — see there."
  :arity binary
  :prefix "innr"
  :map -1
  (commit (calcFunc-inner maf--combinator-op maf--combinator-op2 expr arg)))

(defun mafcmd-fold ()
  "Fold the vector at point by an operation you press.

  [1, 2, 3, 4]  =>  10        (pressing +)

The operation is the next key: any contextual command of two arguments
answers on its own key, so + sums, * multiplies and f x takes the
maximum, and : types a formula instead. The operation folds along the
vector from the left, each result becoming the next call's first
argument.

Inverse: fold from the right instead.

  [1, 2, 3, 4]  =>  -2        (pressing I then -, as 1 - (2 - (3 - 4)))

Point picks the target as usual: a sub-formula at point, each side of
an equation, the top entry at home.

  [[1, 2], [3, 4]]  =>  10          (pressing +: a matrix folds whole)
  [a, b, c]         =>  a + b + c   (pressing +: symbolic, unevaluated)"
  (interactive)
  (let ((op (maf--read-operation "Fold" 2))
        (func (if calc-inverse-flag 'calcFunc-rreduce 'calcFunc-reduce)))
    (setq calc-inverse-flag nil
          calc-hyperbolic-flag nil)
    (let ((maf--combinator-op op)
          (maf--combinator-func func))
      (call-interactively #'maf--fold-run))))
(put 'mafcmd-fold 'maf-command t)

(defun mafcmd-accum ()
  "Accumulate over the vector at point by an operation you press.

  [1, 2, 3, 4]  =>  [1, 3, 6, 10]        (pressing +)

The running results of the fold `mafcmd-fold' performs, kept as a
vector rather than reduced to the last one. The operation is read the
same way: the next key, or : for a typed formula.

Inverse: accumulate from the right.

  [1, 2, 3, 4]  =>  [-2, 3, -1, 4]       (pressing I then -)

Point picks the target as usual: a sub-formula at point, each side of
an equation, the top entry at home."
  (interactive)
  (let ((op (maf--read-operation "Accumulate" 2))
        (func (if calc-inverse-flag 'calcFunc-raccum 'calcFunc-accum)))
    (setq calc-inverse-flag nil
          calc-hyperbolic-flag nil)
    (let ((maf--combinator-op op)
          (maf--combinator-func func))
      (call-interactively #'maf--accum-run))))
(put 'mafcmd-accum 'maf-command t)

(defun mafcmd-apply ()
  "Apply an operation you press to the vector at point, element by element.

  [3, 5]  =>  8        (pressing +)

The vector's elements become the operation's arguments, so a
two-argument operation wants a vector of two. The operation is the next
key, or : for a typed formula.

Point picks the target as usual: a sub-formula at point, each side of
an equation, the top entry at home."
  (interactive)
  (let ((op (maf--read-operation "Apply" 2)))
    (setq calc-inverse-flag nil
          calc-hyperbolic-flag nil)
    (let ((maf--combinator-op op))
      (call-interactively #'maf--apply-run))))
(put 'mafcmd-apply 'maf-command t)

(defun mafcmd-outer ()
  "Build the outer product of two vectors under an operation you press.

  2:  [1, 2]     =>  1:  [[3, 4], [6, 8]]      (pressing *)
  1:  [3, 4]

Every element of the lower vector meets every element of the upper one,
giving a matrix with the lower vector's elements down the rows. The
operation is the next key: any contextual command of two arguments, or
: for a typed formula.

Point picks the target as usual, the stack's top entry supplying the
second vector.

  2:  [1, 3, 9]     =>  1:  [[1, 1:2, 1:3, 1:6], [3, 3:2, 1, 1:2],
  1:  [1, 2, 3, 6]                    [9, 9:2, 3, 3:2]]

                       (pressing /: every quotient of the two)"
  (interactive)
  (let ((op (maf--read-operation "Outer" 2)))
    (setq calc-inverse-flag nil
          calc-hyperbolic-flag nil)
    (let ((maf--combinator-op op))
      (call-interactively #'maf--outer-run))))
(put 'mafcmd-outer 'maf-command t)

(defun mafcmd-inner ()
  "Build the inner product of two vectors under two operations you press.

  2:  [1, 2, 3]     =>  1:  32        (pressing * then +)
  1:  [4, 5, 6]

The first operation combines the pairs, the second reduces them — * and
+ give the ordinary dot product. Each is read the same way: the next
key, or : for a typed formula.

Point picks the target as usual, the stack's top entry supplying the
second vector."
  (interactive)
  (let* ((mul (maf--read-operation "Inner (multiply)" 2))
         (add (maf--read-operation "Inner (add)" 2)))
    (setq calc-inverse-flag nil
          calc-hyperbolic-flag nil)
    (let ((maf--combinator-op mul)
          (maf--combinator-op2 add))
      (call-interactively #'maf--inner-run))))
(put 'mafcmd-inner 'maf-command t)

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

(defun maf-index (&optional n)
  "Prompt for a size and push the index vector [1, 2, .., N].

  5  =>  [1, 2, 3, 4, 5]

The size comes from the prompt — or a numeric prefix, which skips it —
never from the stack or from point; the vector simply lands on top.
The contextual sibling is `mafcmd-index' (v x), which reads its size
from the target. The prompt takes a formula, so 2^4 sizes as 16 and a
symbolic size pushes the call unevaluated, ready for a value later.

Ported from the legacy config's v RET, which kept calc's own
`calc-index' there; the prompt-only reading is the part kept — the
C-u form that reads start and increment off the stack is not, being
the stack-reading this key exists to avoid."
  (interactive "P")
  (let ((size
         (if n
             (prefix-numeric-value n)
           (let* ((input (string-trim (read-string "Size of vector: ")))
                  (expr (and (not (string-empty-p input))
                             (math-read-expr input))))
             (when (null expr)
               (user-error "No size given"))
             (when (eq (car-safe expr) 'error)
               (user-error "Bad format in size: %s" (nth 2 expr)))
             (math-simplify expr)))))
    ;; A number must be a whole size; anything symbolic passes through
    ;; and the call waits for its value.
    (when (and (Math-numberp size)
               (not (and (math-integerp size) (not (math-negp size)))))
      (user-error "Size of vector must be a non-negative integer"))
    (calc-wrapper
     (calc-enter-result 0 "indx" (list 'calcFunc-index size)))))
(put 'maf-index 'maf-command t)

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

;;; Bracketing

(maf-defcmd mafcmd-bracket (expr _arg commit)
  "Enclose the resolved expression in square brackets.

  x  =>  [x]

The brackets are calc's vector brackets, so what comes back is the
one-element vector holding what point named — the one-operand
counterpart of the concatenation on the | key, which builds a vector
out of two stack entries. Nothing is computed and nothing is
simplified: the expression arrives inside the brackets exactly as it
stood.

Point picks the target as usual: a sub-formula at point, the entry at
point, the top entry at home. A vector nests inside the new one rather
than splicing into it — that is what surrounding it means — and a
relation is one element rather than a subject to bracket side by side,
so an equation comes back whole within the brackets. For a bracketed
entry, `mafcmd-unpack' is the way back out, peeling the one-element
vector to its element.

  x + 1|   =>  [x + 1]
  x + |1   =>  x + [1]
  [a, b]   =>  [[ a, b ]]   (nests rather than splicing)
  x = 1    =>  [x = 1]    (a relation is one element)
  a| + b   =>  [a] + b"
  :arity unary
  :prefix "brkt"
  ;; A relation is an element, not a thing to run once per side: the
  ;; whole point is a bracket around what point named, and mapped, an
  ;; equation would come back as the vector equation [x] = [1] instead
  ;; of the one-element system [x = 1]. Same reading as the | family
  ;; takes in maf-cmds.el.
  :map -1
  (commit (list 'vec expr)))

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
  ;; calc-ext's autoload registry covers most of calc-vec but not this
  ;; function, so the module has to be pulled in by hand — and outside
  ;; the condition-case, which would otherwise swallow the void-function
  ;; error and report "nothing to unpack" for every expression until
  ;; something else in the session happened to load calc-vec.
  (require 'calc-vec)
  (let ((calc-unpack-with-type nil))
    (condition-case nil
        (calc-unpack-item mode expr)
      (error nil))))

(defun maf--unpack-mode ()
  "The unpacking mode for this command, from the prefix argument.
Nil — one level — when no prefix was given."
  (and current-prefix-arg (prefix-numeric-value current-prefix-arg)))

(maf-defcmd mafcmd-unpack (expr _arg commit)
  "Unwrap the entry at point, spreading its parts across the stack.

  [x, y]  =>  2:  x
              1:  y

One level comes apart at a time: a composite object into its
components, a function call into its arguments, an operator into its
operands — one stack entry per part.

The subject is always a whole entry: the entry at point, the top at
home, whatever the gesture. The parts land as stack entries, and a
formula slot has no room for them, so a region, a calc selection, or
point within a formula names the entry that holds it, not a part.

A numeric prefix argument gives calc's unpacking mode: a positive N
unwraps N levels deep, a negative N splits a vector by component type.
An entry with nothing to give — a plain number, a bare variable, or
one the requested mode does not fit — commits unchanged rather than
signaling.

  sin(x)                 =>  x
  a + b                  =>  2:  a / 1:  b
  3:4                    =>  2:  3 / 1:  4
  1.5                    =>  2:  15 / 1:  -1   (mantissa and exponent)
  x                      =>  x                 (nothing to give)
  C-u 2 [(1,2),(3,4)]    =>  4:  1 / 3:  2 / 2:  3 / 1:  4
  x = sin(y)             =>  2:  x / 1:  sin(y)
  y + sin(a| + b)        =>  2:  y / 1:  sin(a + b)   (the whole entry)"
  :arity unary
  :prefix "unpk"
  ;; A relation is a function call like any other: unwrapping consumes
  ;; it into its two sides, as calc-unpack does, rather than mapping
  ;; over them and putting the relation back together.
  :map -1
  ;; The parts spread over the stack, and only a whole entry has room
  ;; for that: whatever the gesture, the subject is the entry at point.
  :scope entry
  (let ((parts (maf--unpack-parts expr (maf--unpack-mode))))
    (commit
     (cond
      ;; Nothing to give: leave the entry exactly as it stands.
      ((null parts) expr)
      ;; The map flag forced a relation apart past :map -1, and each
      ;; side's slot holds a single expression: unwrap when the parts
      ;; amount to one, otherwise there is no room for them.
      ((eq maf-target 'equation) (if (cdr parts) expr (car parts)))
      ;; The whole entry takes the parts as a value list, which commit
      ;; spreads over one entry each.
      (t parts)))))

;;; Unwrapping

(defun maf--unpack-peelable-p (expr)
  "Non-nil when EXPR unwraps to exactly one part.
The `:widen' predicate for `mafcmd-unwrap': a node that gives exactly
one part is one a sub-formula slot can hold, so it is the node to peel.
Reads the mode through `maf--unpack-mode', the same way the body does —
resolve and body must agree on what counts, or resolve would widen to a
node the body then declines to unwrap."
  (let ((parts (maf--unpack-parts expr (maf--unpack-mode))))
    (and parts (null (cdr parts)))))

(maf-defcmd mafcmd-unwrap (expr _arg commit)
  "Unwrap the resolved expression, taking off the wrapper around point.

  sin(2| x)  =>  2 x

Inside a formula there is room for only one expression, so point peels
the innermost wrapper around it that gives exactly one part — the node
under point when that fits, otherwise the nearest enclosing one. So
anywhere within sin(2 x) the command means the same thing: take off
the sin, leaving what it held in its place.

Where the target is a whole entry the parts have room to spread, and
the command reads as `mafcmd-unpack' does: one level comes apart at a
time — a composite object into its components, a function call into
its arguments, an operator into its operands — one stack entry per
part.

A numeric prefix argument gives calc's unpacking mode: a positive N
unwraps N levels deep, a negative N splits a vector by component type.
An expression with nothing to give — a plain number, a bare variable,
or one the requested mode does not fit — commits unchanged rather than
signaling, as does a sub-formula with no peelable wrapper around it.
An explicit calc selection is taken as it stands and never widened.

  sin|(2 x)              =>  2 x
  2 x - 3 < sin(|7)      =>  2 x - 3 < 7
  y + sin(a| + b)        =>  y + (a + b)       (peels the sin)
  (a| + b) (2 c - d)     =>  unchanged         (no wrapper to peel)
  [x, y]                 =>  2:  x / 1:  y     (a whole entry spreads)
  x                      =>  x                 (nothing to give)"
  :arity unary
  :prefix "unwr"
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
