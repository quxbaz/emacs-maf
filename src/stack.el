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
(declare-function calcFunc-pfloat "calc-stuff")
(declare-function calc-roll-down "calc-misc")
(declare-function calc-locate-cursor-element "calc-yank")
(declare-function calc-del-selection "calc-sel")
(declare-function calc-change-mode "calc-mode")
(declare-function calc-normal-language "calc-lang")
(declare-function calc-big-language "calc-lang")
(declare-function calcFunc-factor "calc-poly")
(declare-function calcFunc-roots "calcalg2")
(declare-function calcFunc-sub "calc-arith")

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

(defun maf-swap-up (n)
  "Swap the stack entry at point with the one above it on screen.

  2:  a          2:  b
  1:  b|    =>   1:  a|

Entries at level M and M+1 exchange places while point stays put —
same line, same column: the entry at point moves up the screen and
its upper neighbor lands on the line at point. When that neighbor is
shorter than point's column, point clamps to its end of line; at end
of line it stays at end of line. At home the top two entries swap.
Selections travel with their entries. With the entry at point already
the highest, or with fewer than two entries, there is nothing to swap
and the command does nothing.

A prefix argument N bypasses the contextual swap and rolls the top N
entries by one, as calc's TAB does."
  (interactive "P")
  (maf--with-calc-buffer
    (if n
        (let ((snapshot (maf--point-snapshot)))
          (maf--preserve-point (calc-roll-down n))
          ;; A single undo reverts point along with the stack.
          (maf--undo-record-cmd-point snapshot))
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
             ;; values swaps the two levels; the selections travel along.
             (let ((vals (calc-top-list 2 m))
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
            (maf--undo-record-cmd-point snapshot)))))))

(defun maf-equal-to ()
  "Join two adjacent stack entries into one equation, contextually.

  2:  x
  1:  y|    =>   1:  x = y|

With the Inverse flag, builds != instead of =.

  2:  x
  1:  y|    =>   1:  x != y|

The entry above point becomes the left side, the entry at point the
right side, and the equation replaces the pair with point at its end
of line. At home the top two entries join; on the deepest entry —
nothing above it — the pair shifts to the entry below, so either
entry of a two-entry stack gives the same equation. With keep-args
the pair stays put and the equation is pushed on top instead. Both
sides commit structurally intact — nothing simplifies or evaluates,
so equating 3 with 3 gives the equation 3 = 3, not 1. Signals an
error with fewer than two entries."
  (interactive)
  (maf--with-calc-buffer
    (when (< (calc-stack-size) 2)
      (user-error "Two stack entries are needed to equate"))
    (let* ((level (calc-locate-cursor-element (point)))
           ;; Pair (m+1, m): home resolves to the top pair, and on the
           ;; deepest entry — no upper neighbor — the pair shifts down.
           (m (min (max level 1) (1- (calc-stack-size))))
           (keep calc-keep-args-flag)
           (func (if calc-inverse-flag 'calcFunc-neq 'calcFunc-eq))
           (prefix (if calc-inverse-flag "neq" "eq"))
           (commit
            (lambda ()
              (calc-wrapper
               ;; The list runs deepest-first: nth 0 is the entry above
               ;; point — the upper line — which reads as the left side.
               (let* ((vals (mapcar #'maf--strip-encasing
                                    (calc-top-list 2 m)))
                      (result (list func (nth 0 vals) (nth 1 vals))))
                 ;; Explicit nil sels keep the commit on the plain
                 ;; pop/push path; selections elsewhere on the stack stay
                 ;; untouched, and the operands' own selections end with
                 ;; them.
                 (if keep
                     (calc-pop-push-record-list 0 prefix (list result)
                                                1 (list nil))
                   (calc-pop-push-record-list 2 prefix (list result)
                                              m (list nil))))))))
      (let ((snapshot (maf--point-snapshot)))
        (if (or keep (= level 0))
            ;; Nothing under point moved (keep) or point is at home:
            ;; keeping it in place is the right restore.
            (maf--preserve-point (funcall commit))
          ;; The equation takes the pair's upper line while point was on
          ;; the lower one, so a line-based restore would drift onto the
          ;; entry below; follow the equation instead, landing at its EOL
          ;; — the entry margin, ready for further entry commands.
          (funcall commit)
          (calc-cursor-stack-index m)
          (end-of-line))
        ;; A single undo reverts point along with the stack.
        (maf--undo-record-cmd-point snapshot)))))

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
  2:  a + b|   =>  deletes the whole entry     (point on the margin)"
  (interactive)
  (maf--with-calc-buffer
    (when (zerop (calc-stack-size))
      (user-error "Stack is empty"))
    (let ((snapshot (maf--point-snapshot)))
      (maf--preserve-point
        (if (maf--at-home-p)
            (calc-pop 1)
          (calc-del-selection)))
      ;; A deletion that shortens the line clamps point to EOL; record
      ;; the pre-command placement so a single undo reverts point along
      ;; with the stack instead of preserving the clamped spot.
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

(defun maf-dup (&optional keep-point)
  "Duplicate the item at point, pushing a copy onto the stack.

  1:  a + b|   =>   2:  a + b
                    1:  a + b

The copy is pushed on top and the originals are untouched, so the
stack grows by one. Like calc's own duplicate the copy is verbatim:
nothing simplifies or evaluates, and keep-args makes no difference.
Signals an error on an empty stack.

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

Point moves home to the copy. With KEEP-POINT non-nil it stays where
it was instead — `maf-dup-here' is the keep-point entry point."
  (interactive)
  (maf--with-calc-buffer
    (when (zerop (calc-stack-size))
      (user-error "Stack is empty"))
    ;; Unary resolution (no arg, so no below-top restriction) with
    ;; :map -1 so a relation stays whole in :expr rather than mapping
    ;; per side. We only read :expr and push it.
    (let* ((context (maf--resolve-context '((:arity . unary) (:map . -1))))
           (expr (alist-get :expr context)))
      ;; calc-wrapper's epilogue parks point home; keep-point puts it back.
      (if keep-point
          (maf--preserve-point (calc-wrapper (calc-push expr)))
        (calc-wrapper (calc-push expr)))
      ;; Record the resolve-time point so a single `maf-undo' reverts
      ;; point along with the pushed copy, back to where the command ran.
      (maf--undo-record-cmd-point (alist-get :point context)))))

(defun maf-dup-here ()
  "Duplicate the item at point like `maf-dup', but keep point in place.
The copy is still pushed on top; point stays where it was instead of
moving home to the copy."
  (interactive)
  (maf-dup t))

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
  "Return a calc vector of the roots of POLY in VAR, with multiplicity.
POLY is factored first, then each factor's roots are taken and repeated
by the factor's multiplicity, so (x - 2)^2 contributes 2 twice."
  (cons 'vec
        (cl-mapcan
         (lambda (fm)
           (let* ((r (calcFunc-roots (car fm) var))
                  (rs (and (eq (car-safe r) 'vec) (cdr r))))
             (cl-mapcan (lambda (root) (make-list (cdr fm) root)) rs)))
         (maf--poly-factors (calcFunc-factor poly)))))

(defun maf--poly-roots-subject (expr)
  "Return the polynomial whose roots EXPR asks for.
A relation reduces to one side or the difference of sides: f(x) REL g
uses g when the left side is a function call (as in f(x) = x^2 - 4),
otherwise the difference of the sides — so an equation, an inequality,
or a != all yield the roots of their boundary. A bare expression is
returned unchanged."
  (if (maf--relation-p expr)
      (let ((lhs (nth 1 expr)) (rhs (nth 2 expr)))
        (if (and (= (length lhs) 2)
                 (string-prefix-p "calcFunc-" (symbol-name (car-safe lhs))))
            rhs
          (calcFunc-sub lhs rhs)))
    expr))

(maf-defcmd mafcmd-poly-roots (expr _arg commit)
  "Find the roots of the resolved polynomial, as a vector.

  x^2 - 4  =>  [-2, 2]

The polynomial is factored first, so repeated factors keep their
multiplicity and the roots come out one per factor. An equation is
accepted too: f(x) = g uses g when the left side is a function call,
otherwise the difference of the sides. The variable is chosen as for
`mafcmd-auto-solve' — x, y, z, t first, then alphabetical — and an
expression with no variable commits unchanged. It acts on the whole
entry — the polynomial or equation at point, wherever point sits on its
line — or the top entry at home; finding roots has no sub-formula
meaning, so point within the formula is not used to narrow it.

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
    (commit (if vars (maf--poly-roots-of poly (car vars)) expr))))

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
