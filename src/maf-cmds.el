;; -*- lexical-binding: t; -*-
;;
;; maf-cmds.el
;;
;; The standard library of contextual calc commands, defined from a table.
;; Each row (SUFFIX ARITY CALCFUNC [KEY]) expands into a `maf-defcmd' named
;; mafcmd-SUFFIX whose body applies CALCFUNC to the resolved expression and
;; commits the normalized result. `calc-normalize' evaluates the call when it
;; can and leaves it symbolic otherwise, under the buffer's simplification
;; mode — so a row's key gives what calc's own key gives under m A, m N and
;; the rest, where `math-normalize' would apply the default simplifications
;; alone and leave 3 sqrt(2) / sqrt(2) standing under `alg'. It matches
;; algebraic entry, and autoloads the calc module that defines CALCFUNC on
;; first use.
;;
;; When KEY is present the command is also bound to it in `maf-mode-map', so
;; enabling `maf-mode' in a calc buffer shadows calc's own binding of that key
;; with the contextual equivalent (e.g. + runs mafcmd-add instead of
;; calc-plus). Keys come from calc's real layout, audited against
;; calc-mode-map.
;;
;; Rows without a key are the inverse/hyperbolic variants, and the base rows
;; link to them with :inv/:hyp/:invhyp so calc's I and H flag prefixes route
;; contextually: I S applies arcsin to the resolved expression, H S sinh,
;; I H S arcsinh. The links are the key-join of calc's four oper-keys
;; sub-tables (plain/inverse/hyperbolic/both). Self-links — families where
;; the flag changes the function's arity instead of the function (bern,
;; euler, vexp, histogram) — are omitted; those need distinct commands
;; before they can dispatch.
;;
;; The table is seeded from calc's own key->function operator tables
;; (calc-*-oper-keys in calc-map.el, the data behind V M's operator prompt),
;; filtered to unary/binary entries and deduped. Two chars there are V-M-only
;; codes, not real keys: N and X (calc binds them to calc-eval-num and macro
;; replay); min/max instead get their real keys f n and f x. The table is
;; data, not discovery: edit rows to rename, drop, or add commands. Suffixes
;; are the calcFunc names, which are also the names users type in algebraic
;; entry.

(require 'maf-defcmd)
(require 'maf-math "math")   ; maf-vconcat and maf-sort, applied by the rows below

;; Also defvar'd in maf.el next to the minor mode; whichever file loads first
;; creates the map and the other defvar is a no-op. Declared here too so this
;; file can install the generated bindings below.
(defvar maf-cmds--table-keys nil
  "The (KEY . COMMAND) rows the mafcmd table declares.
Collected here rather than bound: src/bindings.el owns the profile
declarations and reads this list, so a reload of either file leaves
one source of truth.")

(defun maf-cmds--table-key (key command)
  "Record KEY -> COMMAND as a table row, replacing a prior KEY row."
  (let ((cell (assoc key maf-cmds--table-keys)))
    (if cell (setcdr cell command)
      (setq maf-cmds--table-keys
            (append maf-cmds--table-keys (list (cons key command)))))))

(defvar maf-cmds--table nil
  "Every mafcmd table row, as data: (NAME ARITY FUNC KEY INV HYP INVHYP).
NAME is the command symbol, ARITY `unary' or `binary', FUNC what the
body applies, KEY the row's `kbd' string or nil, and the last three
the flag-variant command symbols or nil. The sweep test walks this
list; a reload of the table replaces rows by NAME, keeping one row
per command.")

(defun maf-cmds--table-row (row)
  "Record ROW in `maf-cmds--table', replacing a prior row of its name."
  (let ((cell (assq (car row) maf-cmds--table)))
    (if cell (setcdr cell (cdr row))
      (setq maf-cmds--table (append maf-cmds--table (list row))))))

(defvar maf-mode-map (make-sparse-keymap)
  "Keymap for `maf-mode'.")

(defmacro maf-defcmds (&rest specs)
  "Define a contextual calc command for each spec in SPECS.
Each spec is a list (SUFFIX ARITY FUNC [KEY] [KEYWORD SUFFIX]...): defines
mafcmd-SUFFIX via `maf-defcmd' with :arity ARITY (unary or binary), whose
body applies FUNC to the resolved expression — plus the stack-top arg for
binary — and commits the result through `calc-normalize'. When KEY (a
`kbd' string) is present, the command is bound to it in `maf-mode-map',
shadowing calc's binding of that key while `maf-mode' is on.

The optional keywords :inv, :hyp, and :invhyp name the SUFFIX of another
spec to run instead when calc's Inverse flag, Hyperbolic flag, or both
are set, making the I and H prefixes route to the variant contextually.
:map -1 opts the command out of per-side equation mapping (see
`maf-defcmd'), for commands that consume or produce relations.

:title and :example are the row's presentation strings, passed through
to `maf-defcmd' — the command's proper name spelled out, and one line
showing what it does. Both optional; the surfaces that read them fall
back (see `maf-command-title').

Every row generates a mafcmd-SUFFIX-targets policy variable of its own
(see `maf-defcmd'). Under a flag dispatch the pressed key's policy
rides along and outranks the variable of whichever variant answers
(see `maf--dispatch-narrowing') — H E maps by exp's variable even
though exp10 runs, I | by vconcat's even though vconcatrev does — so a
variant's own variable governs only its direct invocation."
  (declare (indent 0))
  `(progn
     ,@(mapcan
        (pcase-lambda (`(,suffix ,arity ,func . ,rest))
          (let* ((name (intern (format "mafcmd-%s" suffix)))
                 (key (and (stringp (car rest)) (car rest)))
                 (variants (if key (cdr rest) rest))
                 (vcmd (lambda (kw)
                         (let ((s (plist-get variants kw)))
                           (and s (intern (format "mafcmd-%s" s))))))
                 (inv (funcall vcmd :inv))
                 (hyp (funcall vcmd :hyp))
                 (invhyp (funcall vcmd :invhyp))
                 (mapv (plist-get variants :map))
                 (title (plist-get variants :title))
                 (example (plist-get variants :example)))
            (append
             (list
              `(maf-defcmd ,name
                   ;; Unary bodies never touch the arg binding; name it _arg
                   ;; so the byte compiler doesn't flag it as unused.
                   (expr ,(if (eq arity 'binary) 'arg '_arg) commit)
                 ,(concat
                   (format "Contextually apply `%s' (%s)." func arity)
                   (when (or inv hyp invhyp)
                     (concat "\nCalc flag variants:"
                             (and inv (format "\n  I   -> `%s'" inv))
                             (and hyp (format "\n  H   -> `%s'" hyp))
                             (and invhyp (format "\n  I H -> `%s'" invhyp)))))
                 :arity ,arity
                 :prefix ,(symbol-name suffix)
                 ,@(when inv `(:inverse ,inv))
                 ,@(when hyp `(:hyperbolic ,hyp))
                 ,@(when invhyp `(:inverse-hyperbolic ,invhyp))
                 ,@(when mapv `(:map ,mapv))
                 ,@(when title `(:title ,title))
                 ,@(when example `(:example ,example))
                 (commit (calc-normalize
                          (list ',func expr
                                ,@(when (eq arity 'binary) '(arg)))))))
             ;; The row's function and how many operands it takes,
             ;; recorded on the command so the combinators can use it
             ;; as an operation: v R + folds by `calcFunc-add' because
             ;; the + key runs a command stamped with it. This is what
             ;; widens the operation space past calc's fixed table —
             ;; every row qualifies, and a hand-written command joins
             ;; by stamping the property itself.
             (list `(put ',name 'maf-operation
                         '(,func . ,(if (eq arity 'binary) 2 1))))
             ;; And the whole row as data, for the sweep test.
             (list `(maf-cmds--table-row
                     '(,name ,arity ,func ,key ,inv ,hyp ,invhyp)))
             (when key
               (list `(maf-cmds--table-key ,key #',name))))))
        specs)))

(maf-defcmds
  ;; arithmetic and scientific (calc-oper-keys)
  (add binary calcFunc-add "+"
   :title "add" :example "x, 2 => x + 2")
  (sub binary calcFunc-sub "-"
   :title "subtract" :example "x, 2 => x - 2")
  (mul binary calcFunc-mul "*"
   :title "multiply" :example "x, y => x y")
  (div binary calcFunc-div "/"
   :title "divide" :example "x, 2 => x / 2")
  (pow binary calcFunc-pow "^" :inv nroot
   :title "power" :example "x, 2 => x^2")
  ;; vconcat/vconcatrev use maf's own concatenation rather than
  ;; calcFunc-vconcat: | here always builds a vector, where calc leaves
  ;; it symbolic whenever an operand is not provably scalar (see
  ;; `maf-vconcat').
  ;;
  ;; The whole | family takes :map -1: a relation is an element, not a
  ;; thing to run once per side. Mapped, two stacked equations would
  ;; pair up into [x, y] = [1, 2] — one equation of vectors — where
  ;; concatenation means [x = 1, y = 2], the vector of equations that is
  ;; calc's own spelling of a system (what a S returns and takes).
  (vconcat binary maf-vconcat "|" :inv vconcatrev :hyp append :invhyp appendrev :map -1
   :title "concatenate" :example "[1, 2], [3] => [1, 2, 3]")
  (mod binary calcFunc-mod "%"
   :title "modulo" :example "7, 3 => 1")
  ;; idiv cedes \ to a second square-root key (bindings.el); calc's
  ;; own \ is shadowed with it. Reachable by name, and I / is not it.
  (idiv binary calcFunc-idiv
   :title "integer division" :example "7, 2 => 3")
  (fact unary calcFunc-fact "!"
   :title "factorial" :example "5 => 120")
  ;; & is calc's own key for the reciprocal; the big-language toggle
  ;; borrowed it while it had one and has since gone unbound
  ;; (bindings.el). o is a second key for it, also there.
  (inv unary calcFunc-inv "&"
   :title "reciprocal" :example "x => 1 / x")
  ;; neg grew an interval reading — the complement — and lives as a
  ;; maf-defcmd (src/stack.el); its n rides bindings.el with it.
  ;; abs has left the table for `mafcmd-abs' (stack.el, A), which reads
  ;; a vector as its norm through `maf--abs' rather than `calcFunc-abs',
  ;; whose two-element case hands back an inert hypot(2, sqrt(3)). It
  ;; cannot be a row for the reason hypot below could not: rows apply
  ;; their function under `calc-normalize', which normalizes the
  ;; arguments first, and that floats an exact sqrt(3) entry before the
  ;; command can see it was exact.
  ;; conj's J is shadowed in native by a second multiply key
  ;; (bindings.el); the calc profile keeps it, and native's conj
  ;; home is l j.
  (conj unary calcFunc-conj "J"
   :title "complex conjugate" :example "(3, 4) => (3, -4)")
  ;; arg cedes calc's G to the preview module, whose maf-preview-show
  ;; declares it (modules/maf-preview.el); the key stays the module's
  ;; whether it is on or off, so the row keeps none.
  (arg unary calcFunc-arg
   :title "complex argument" :example "1 => 0")
  (sqrt unary calcFunc-sqrt "Q" :inv sqr
   :title "square root" :example "9 => 3")
  (min binary calcFunc-min "f n"
   :title "minimum" :example "3, 5 => 3")
  (max binary calcFunc-max "f x"
   :title "maximum" :example "3, 5 => 5")
  ;; floor cedes F in native to a second key for mafcmd-fold
  ;; (bindings.el); the calc profile keeps F = floor.
  (floor unary calcFunc-floor "F" :inv ceil :hyp ffloor :invhyp fceil
   :title "floor" :example "2.7 => 2")
  (round unary calcFunc-round "R" :inv trunc :hyp fround :invhyp ftrunc
   :title "round" :example "2.6 => 3")
  (sin unary calcFunc-sin "S" :inv arcsin :hyp sinh :invhyp arcsinh
   :title "sine" :example "0 => 0")
  (cos unary calcFunc-cos "C" :inv arccos :hyp cosh :invhyp arccosh
   :title "cosine" :example "0 => 1")
  (tan unary calcFunc-tan "T" :inv arctan :hyp tanh :invhyp arctanh
   :title "tangent" :example "0 => 0")
  (ln unary calcFunc-ln "L" :inv exp :hyp log10 :invhyp exp10
   :title "natural logarithm" :example "e => 1")
  (exp unary calcFunc-exp "E" :inv ln :hyp exp10 :invhyp log10
   :title "exponential" :example "0 => 1")
  (log binary calcFunc-log "B" :inv alog
   :title "logarithm" :example "8, 2 => 3")
  (ceil unary calcFunc-ceil
   :title "ceiling" :example "2.3 => 3")
  (trunc unary calcFunc-trunc)
  (sqr unary calcFunc-sqr
   :title "square" :example "x => x^2")
  (arcsin unary calcFunc-arcsin)
  (arccos unary calcFunc-arccos)
  (arctan unary calcFunc-arctan)
  (alog binary calcFunc-alog)
  (nroot binary calcFunc-nroot)
  (vconcatrev binary maf-vconcatrev :map -1)   ; see vconcat above
  (ffloor unary calcFunc-ffloor
   :title "float floor" :example "2.7 => 2.")
  (fround unary calcFunc-fround)
  (sinh unary calcFunc-sinh)
  (cosh unary calcFunc-cosh)
  (tanh unary calcFunc-tanh)
  (log10 unary calcFunc-log10)
  (exp10 unary calcFunc-exp10)
  (append binary calcFunc-append :map -1)      ; see vconcat above
  (fceil unary calcFunc-fceil
   :title "float ceiling" :example "2.3 => 3.")
  (ftrunc unary calcFunc-ftrunc)
  (arcsinh unary calcFunc-arcsinh)
  (arccosh unary calcFunc-arccosh)
  (arctanh unary calcFunc-arctanh)
  (appendrev binary calcFunc-appendrev :map -1)  ; see vconcat above
  ;; algebra (calc-a-oper-keys)
  (apart unary calcFunc-apart "a a"
   :title "partial fractions" :example "1 / (x^2 - 1) => 1:2 / (x - 1) - 1:2 / (x + 1)")
  (collect binary calcFunc-collect "a c"
   :title "collect a variable" :example "x a + x b, x => x*(a + b)")
  (deriv binary calcFunc-deriv "a d" :hyp tderiv
   :title "derivative" :example "x^2, x => 2 x")
  ;; Simplifying a relation is a whole-relation job: calc divides both
  ;; sides through and moves terms across the operator. Mapped per side
  ;; each side is already as simple as it gets alone, so the command
  ;; would do nothing at all on an equation.
  (esimplify unary calcFunc-esimplify "a s" :map -1
   :title "extended simplify" :example "sqrt(x^2) => x")
  ;; The seed table lists factor/factors with two arguments, but the
  ;; second is calcFunc-factor's optional variable, not an operand:
  ;; calc's own a f factors the one expression.
  (factor unary calcFunc-factor "a f" :hyp factors
   :title "factor" :example "x^2 - 1 => (x + 1) (x - 1)")
  (pgcd binary calcFunc-pgcd "a g"
   :title "polynomial gcd" :example "x^2 - 1, x - 1 => x - 1")
  (integ binary calcFunc-integ "a i"
   :title "integral" :example "2 x, x => x^2")
  (match binary calcFunc-match "a m" :inv matchnot :map -1
   :title "match a pattern")
  (nrat unary calcFunc-nrat "a n"
   :title "normalize to a ratio" :example "1/x + 1/y => (y + x) / (x y)")
  (rewrite binary calcFunc-rewrite "a r" :map -1
   :title "rewrite by a rule" :example "x + x, x + x := 2 x => 2 * x")
  (simplify unary calcFunc-simplify "a e" :map -1   ; see esimplify above
   :title "simplify" :example "x + x => 2 x")
  (expand unary calcFunc-expand "a x"
   :title "expand" :example "(x + 1)^2 => x^2 + 2 x + 1")
  (mapeq binary calcFunc-mapeq "a M" :inv mapeqr :hyp mapeqp :map -1
   :title "map over an equation" :example "sqrt, x = 4 => sqrt(x) = 2")
  (roots binary calcFunc-roots "a P" :map -1
   :title "roots" :example "x^2 - 4, x => [2, -2]")
  (solve binary calcFunc-solve "a S" :inv finv :hyp fsolve :invhyp ffinv :map -1
   :title "solve" :example "x^2 = 4, x => x = 2")
  (eq binary calcFunc-eq "a =" :map -1
   :title "equation" :example "x, 2 => x = 2")
  (neq binary calcFunc-neq "a #" :map -1
   :title "not equal" :example "x, 2 => x != 2")
  (lt binary calcFunc-lt "a <" :map -1
   :title "less than" :example "x, 2 => x < 2")
  (gt binary calcFunc-gt "a >" :map -1
   :title "greater than" :example "x, 2 => x > 2")
  (leq binary calcFunc-leq "a [" :map -1
   :title "less or equal" :example "x, 2 => x <= 2")
  (geq binary calcFunc-geq "a ]" :map -1
   :title "greater or equal" :example "x, 2 => x >= 2")
  (in binary calcFunc-in "a {" :map -1
   :title "membership" :example "2, [1 .. 3] => 1")
  (lnot unary calcFunc-lnot "a !" :map -1
   :title "logical not" :example "0 => 1")
  (land binary calcFunc-land "a &" :map -1
   :title "logical and" :example "1, 0 => 0")
  (lor binary calcFunc-lor "a |" :map -1
   :title "logical or" :example "1, 0 => 1")
  ;; rmeq cedes calc's a . to mafcmd-remove-equal (bindings.el): the
  ;; seed table lists it with two arguments, but calcFunc-rmeq takes
  ;; one, and the whole-entry scope it needs has no table spelling.
  (subscr binary calcFunc-subscr "a _"
   :title "subscript" :example "v, 2 => v_2")
  (pdiv binary calcFunc-pdiv "a \\"
   :title "polynomial quotient" :example "x^2 - 1, x - 1 => x + 1")
  (prem binary calcFunc-prem "a %"
   :title "polynomial remainder" :example "x^2, x - 1 => 1")
  (pdivrem binary calcFunc-pdivrem "a /" :hyp pdivide
   :title "polynomial division" :example "x^2 - 1, x - 1 => [x + 1, 0]")
  (matchnot binary calcFunc-matchnot :map -1)
  (mapeqr binary calcFunc-mapeqr :map -1)
  (finv binary calcFunc-finv :map -1)
  (tderiv binary calcFunc-tderiv)
  (factors unary calcFunc-factors)   ; see factor above
  (mapeqp binary calcFunc-mapeqp :map -1)
  (fsolve binary calcFunc-fsolve :map -1)
  (pdivide binary calcFunc-pdivide)
  (ffinv binary calcFunc-ffinv :map -1)
  ;; binary/bitwise (calc-b-oper-keys)
  (and binary calcFunc-and "b a"
   :title "bitwise and" :example "12, 10 => 8")
  (or binary calcFunc-or "b o"
   :title "bitwise or" :example "12, 10 => 14")
  (xor binary calcFunc-xor "b x"
   :title "bitwise exclusive or" :example "12, 10 => 6")
  (diff binary calcFunc-diff "b d"
   :title "bitwise difference" :example "12, 10 => 4")
  (not unary calcFunc-not "b n"
   :title "bitwise not" :example "-1 => 0")
  (clip unary calcFunc-clip "b c"
   :title "clip to word size" :example "4294967301 => 5")
  (lsh binary calcFunc-lsh "b l"
   :title "shift left" :example "1, 4 => 16")
  (rsh binary calcFunc-rsh "b r"
   :title "shift right" :example "16, 4 => 1")
  (ash binary calcFunc-ash "b L"
   :title "arithmetic shift left" :example "1, 4 => 16")
  (rash binary calcFunc-rash "b R"
   :title "arithmetic shift right" :example "16, 2 => 4")
  (rot binary calcFunc-rot "b t"
   :title "rotate bits" :example "1, 1 => 2")
  (vpack unary calcFunc-vpack "b p"
   :title "pack a bit set" :example "[0, 2] => 5")
  (vunpack unary calcFunc-vunpack "b u"
   :title "unpack a bit set" :example "5 => [0, 2]")
  (irr unary calcFunc-irr "b I" :inv irrb
   :title "internal rate of return" :example "[-100, 60, 60] => 0.130662386292")
  (npv binary calcFunc-npv "b N" :inv npvb
   :title "net present value" :example "0.1, [100, 100] => 173.553719008")
  (relch binary calcFunc-relch "b %"
   :title "percentage change" :example "50, 60 => 0.2")
  (irrb unary calcFunc-irrb)
  (npvb binary calcFunc-npvb)
  ;; conversions (calc-c-oper-keys). Float/fraction conversion lives in
  ;; stack.el: mafcmd-float-frac (l l) toggles by the target's content
  ;; — floats convert toward fractions first, fractions float
  ;; otherwise — with mafcmd-float, mafcmd-frac, and the pervasive
  ;; mafcmd-float-all behind it on the I and H flags and by name.
  ;; Frac keeps its tolerance prefix arg; float and frac are I-linked.
  (deg unary calcFunc-deg "c d"
   :title "to degrees" :example "3.14159265359 => 180.")
  (rad unary calcFunc-rad "c r"
   :title "to radians" :example "90 => 1.57079632679")
  (hms unary calcFunc-hms "c h"
   :title "to hours-minutes-seconds" :example "1.5 => 1@ 30' 0.\"")
  ;; scientific functions (calc-f-oper-keys)
  (beta binary calcFunc-beta "f b"
   :title "beta function" :example "2, 3 => 0.0833333333333")
  (erf unary calcFunc-erf "f e" :inv erfc
   :title "error function" :example "0 => 0")
  (gamma unary calcFunc-gamma "f g"
   :title "gamma function" :example "5 => 24")
  ;; hypot has left the table for `mafcmd-hypot' (stack.el, f h), beside
  ;; mafcmd-cath, which is its Inverse variant and vice versa. It cannot
  ;; be a row: rows apply their function under `calc-normalize', which
  ;; normalizes the arguments first, and that floats a sqrt(3) leg before
  ;; the command can see it was exact. Calc's own `calcFunc-hypot' is
  ;; also not what it applies — see `maf--hypot'. Both directions now
  ;; live in stack.el, with the exactness rule they share.
  (im unary calcFunc-im "f i"
   :title "imaginary part" :example "(3, 4) => 4")
  (besJ binary calcFunc-besJ "f j"
   :title "Bessel function J" :example "0, 0 => 1.")
  (re unary calcFunc-re "f r"
   :title "real part" :example "(3, 4) => 3")
  (sign unary calcFunc-sign "f s"
   :title "sign" :example "-5 => -1")
  (besY binary calcFunc-besY "f y"
   :title "Bessel function Y" :example "1, 1 => -0.78121282")
  (abssqr unary calcFunc-abssqr "f A"
   :title "squared magnitude" :example "(3, 4) => 25")
  (expm1 unary calcFunc-expm1 "f E" :inv lnp1
   :title "exponential minus one" :example "0 => 0")
  (gammaP binary calcFunc-gammaP "f G" :inv gammaQ :hyp gammag :invhyp gammaG
   :title "incomplete gamma" :example "1, 1 => 0.632120558829")
  (ilog binary calcFunc-ilog "f I"
   :title "integer logarithm" :example "100, 10 => 2")
  ;; lnp1 cedes calc's f L to mafcmd-unit-cath (bindings.el); it stays
  ;; reachable as expm1's Inverse variant (I f E) and by name.
  (lnp1 unary calcFunc-lnp1 :inv expm1)
  (mant unary calcFunc-mant "f M"
   :title "mantissa" :example "1234.5 => 1.2345")
  (isqrt unary calcFunc-isqrt "f Q"
   :title "integer square root" :example "17 => 4")
  ;; scf scales by a power of ten: scf(x, n) takes the exponent as a
  ;; second operand, so the row is binary.
  (scf binary calcFunc-scf "f S"
   :title "scale by a power of ten" :example "1.5, 3 => 1500.")
  (arctan2 binary calcFunc-arctan2 "f T"
   :title "two-argument arctangent" :example "1.0, 1.0 => 45.")
  (xpon unary calcFunc-xpon "f X"
   :title "exponent" :example "1234.5 => 3")
  (decr binary calcFunc-decr "f ["
   :title "decrement" :example "5, 1 => 4")
  (incr binary calcFunc-incr "f ]"
   :title "increment" :example "5, 1 => 6")
  (erfc unary calcFunc-erfc)
  (gammaQ binary calcFunc-gammaQ)
  (gammag binary calcFunc-gammag)
  (gammaG binary calcFunc-gammaG)
  ;; combinatorics (calc-k-oper-keys)
  (bern unary calcFunc-bern "k b"
   :title "Bernoulli number" :example "4 => -1:30")
  (choose binary calcFunc-choose "k c" :hyp perm
   :title "binomial coefficient" :example "5, 2 => 10")
  ;; dfact cedes calc's k d to mafcmd-factor-powers (bindings.el).
  (dfact unary calcFunc-dfact
   :title "double factorial" :example "6 => 48")
  (euler unary calcFunc-euler "k e"
   :title "Euler number" :example "4 => 5.")
  ;; prfac cedes calc's k f to a second key for mafcmd-factor
  ;; (bindings.el), beside its table key a f, and lives on the shifted
  ;; key instead — displacing calc-utpf, the one utp lookup left
  ;; keyless here, reachable by name.
  (prfac unary calcFunc-prfac "k F"
   :title "prime factors" :example "60 => [2, 2, 3, 5]")
  (gcd binary calcFunc-gcd "k g"
   :title "greatest common divisor" :example "12, 18 => 6")
  (shuffle binary calcFunc-shuffle "k h"
   :title "random sample")
  (lcm binary calcFunc-lcm "k l"
   :title "least common multiple" :example "4, 6 => 12")
  (moebius unary calcFunc-moebius "k m"
   :title "Moebius function" :example "6 => 1")
  (nextprime unary calcFunc-nextprime "k n" :inv prevprime
   :title "next prime" :example "10 => 11")
  (random unary calcFunc-random "k r"
   :title "random number")
  ;; stir1 cedes calc's k s to mafcmd-complete-square (bindings.el).
  (stir1 binary calcFunc-stir1 :hyp stir2
   :title "Stirling number, first kind" :example "4, 2 => 11")
  ;; totient cedes calc's k t to a second key for mafcmd-perm
  ;; (bindings.el), beside its k p.
  (totient unary calcFunc-totient
   :title "Euler totient" :example "12 => 4")
  (utpc binary calcFunc-utpc "k C" :inv ltpc
   :title "chi-square tail" :example "0, 1 => 1.")
  (utpp binary calcFunc-utpp "k P" :inv ltpp
   :title "Poisson tail" :example "0, 1 => 0.")
  (utpt binary calcFunc-utpt "k T" :inv ltpt
   :title "Student t tail" :example "0, 1 => 1.")
  (prevprime unary calcFunc-prevprime)
  (ltpc binary calcFunc-ltpc)
  (ltpp binary calcFunc-ltpp)
  (ltpt binary calcFunc-ltpt)
  ;; perm takes calc's k p from calc-prime-test (bindings.el); calc
  ;; leaves it on choose's hyperbolic flag alone.
  (perm binary calcFunc-perm
   :title "permutations" :example "5, 2 => 20")
  (stir2 binary calcFunc-stir2
   :title "Stirling number, second kind" :example "4, 2 => 7")
  ;; store (calc-s-oper-keys)
  (assign binary calcFunc-assign "s :" :map -1
   :title "assignment" :example "x, 2 => x := 2")
  (evalto unary calcFunc-evalto "s =" :map -1
   :title "evaluates to" :example "2 + 3 => 5, kept as a formula")
  ;; time (calc-t-oper-keys)
  (date unary calcFunc-date "t D"
   :title "date" :example "<2026-08-31> => 739859")
  (incmonth binary calcFunc-incmonth "t I"
   :title "next month" :example "<2026-08-31> => <Wed Sep 30, 2026>")
  (julian unary calcFunc-julian "t J"
   :title "Julian day number" :example "<2026-08-31> => 2461284")
  (newmonth unary calcFunc-newmonth "t M"
   :title "start of month" :example "<2026-08-31> => <Sat Aug 1, 2026>")
  (newweek unary calcFunc-newweek "t W"
   :title "start of week" :example "<2026-08-31> => <Sun Aug 30, 2026>")
  (unixtime unary calcFunc-unixtime "t U"
   :title "Unix time" :example "<2026-08-31> => 1788156000")
  (newyear unary calcFunc-newyear "t Y"
   :title "start of year" :example "<2026-08-31> => <Thu Jan 1, 2026>")
  ;; units/statistics (calc-u-oper-keys)
  (vcov binary calcFunc-vcov "u C" :inv vpcov :hyp vcorr
   :title "covariance" :example "[1, 2, 3], [2, 4, 6] => 2")
  (vgmean unary calcFunc-vgmean "u G" :hyp agmean
   :title "geometric mean" :example "[1, 4] => 2")
  (vmean unary calcFunc-vmean "u M" :inv vmeane :hyp vmedian :invhyp vhmean
   :title "mean" :example "[1, 2, 3] => 2")
  (vmin unary calcFunc-vmin "u N"
   :title "vector minimum" :example "[3, 1, 2] => 1")
  (rms unary calcFunc-rms "u R"
   :title "root mean square" :example "[3, 4] => 3.53553390593")
  (vsdev unary calcFunc-vsdev "u S" :inv vpsdev :hyp vvar :invhyp vpvar
   :title "standard deviation" :example "[1, 2, 3] => 1")
  (vmax unary calcFunc-vmax "u X"
   :title "vector maximum" :example "[3, 1, 2] => 3")
  (vpcov binary calcFunc-vpcov)
  (vmeane unary calcFunc-vmeane)
  (vpsdev unary calcFunc-vpsdev)
  (vcorr binary calcFunc-vcorr)
  (agmean binary calcFunc-agmean)
  (vmedian unary calcFunc-vmedian)
  (vvar unary calcFunc-vvar)
  (vhmean unary calcFunc-vhmean)
  (vpvar unary calcFunc-vpvar)
  ;; vector/matrix (calc-v-oper-keys)
  (arrange binary calcFunc-arrange "v a"
   :title "arrange into rows" :example "[1, 2, 3, 4], 2 => [[1, 2], [3, 4]]")
  (cvec binary calcFunc-cvec "v b"
   :title "constant vector" :example "7, 3 => [7, 7, 7]")
  (mcol binary calcFunc-mcol "v c"
   :title "matrix column" :example "[[1, 2], [3, 4]], 1 => [1, 3]")
  (diag binary calcFunc-diag "v d"
   :title "diagonal matrix" :example "1, 2 => [[1, 0], [0, 1]]")
  (vexp binary calcFunc-vexp "v e"
   :title "expand by a mask" :example "[1, 0, 1], [7, 8] => [7, 0, 8]")
  (find binary calcFunc-find "v f"
   :title "find an element" :example "[a, b, c], b => 2")
  (head unary calcFunc-head "v h" :inv tail :hyp rhead :invhyp rtail
   :title "first element" :example "[1, 2, 3] => 1")
  (cons binary calcFunc-cons "v k" :hyp rcons
   :title "prepend" :example "1, [2, 3] => [1, 2, 3]")
  (vlen unary calcFunc-vlen "v l"
   :title "length" :example "[1, 2, 3] => 3")
  (vmask binary calcFunc-vmask "v m"
   :title "select by a mask" :example "[1, 0, 1], [7, 8, 9] => [7, 9]")
  (rnorm unary calcFunc-rnorm "v n"
   :title "row norm" :example "[3, -4] => 4")
  (pack binary calcFunc-pack "v p"
   :title "pack into a vector")
  (mrow binary calcFunc-mrow "v r"
   :title "matrix row" :example "[[1, 2], [3, 4]], 1 => [1, 2]")
  (trn unary calcFunc-trn "v t"
   :title "transpose" :example "[[1, 2], [3, 4]] => [[1, 3], [2, 4]]")
  ;; Unpacking lives in stack.el: mafcmd-unpack (M-u, and calc's own
  ;; v u) unwraps the entry at point into its parts, and mafcmd-unwrap
  ;; (j U) is its narrowing sibling, peeling the wrapper around point.
  ;; Neither is a row here because calcFunc-unpack is binary — it takes
  ;; a mode ahead of the thing — and the contextual commands take that
  ;; mode from a prefix argument rather than the stack. A row would also
  ;; be the wrong shape: the result is a list of values spread over the
  ;; stack, not a single applied call.
  (rev unary calcFunc-rev "v v"
   :title "reverse" :example "[1, 2, 3] => [3, 2, 1]")
  (index unary calcFunc-index "v x"
   :title "index vector" :example "5 => [1, 2, 3, 4, 5]")
  ;; The cross product takes both vectors as operands.
  (cross binary calcFunc-cross "v C"
   :title "cross product" :example "[1, 0, 0], [0, 1, 0] => [0, 0, 1]")
  (det unary calcFunc-det "v D"
   :title "determinant" :example "[[1, 2], [3, 4]] => -2")
  (venum unary calcFunc-venum "v E"
   :title "enumerate a set" :example "[1 .. 4] => [1, 2, 3, 4]")
  (vfloor unary calcFunc-vfloor "v F"
   :title "set of integers" :example "[1.5 .. 4.5] => [2 .. 4]")
  (grade unary calcFunc-grade "v G" :inv rgrade
   :title "sorting order" :example "[3, 1, 2] => [2, 3, 1]")
  (histogram binary calcFunc-histogram "v H"
   :title "histogram" :example "[1, 2, 2, 3], 3 => [0, 1, 2]")
  ;; lud cedes calc's v L to mafcmd-flatten (bindings.el).
  (lud unary calcFunc-lud
   :title "LU decomposition" :example "[[1, 2], [3, 4]] => [[[0, 1], [1, 0]], [[1, 0], [0.333333333333, 1]], [[3, 4], [0, 0.666666666667]]]")
  (cnorm unary calcFunc-cnorm "v N"
   :title "column norm" :example "[3, -4] => 7")
  ;; The combinators — apply, reduce, accum, outer, inner and the
  ;; nest/fixp variants — are not rows: their leading argument is an
  ;; operation, not an operand, so applying the calcFunc to the
  ;; resolved expression builds a call of the wrong arity that
  ;; `calc-normalize' can only hand back inert. They read the
  ;; operation from the next key instead (`mafcmd-fold' and
  ;; friends, src/stack.el).
  ;; sort/rsort use maf's own ordering rather than calcFunc-sort:
  ;; calc sorts by expression shape, which strands every negated
  ;; symbolic term after its positive twin ([sqrt(10), -sqrt(10)] comes
  ;; back untouched). maf orders by numeric value when every element
  ;; has one, and defers to calc otherwise (see `maf--sort-vector').
  (sort unary maf-sort "v S" :inv rsort
   :title "sort" :example "[3, 1, 2] => [1, 2, 3]")
  (tr unary calcFunc-tr "v T"
   :title "trace" :example "[[1, 2], [3, 4]] => 5")
  (vunion binary calcFunc-vunion "v V"
   :title "set union" :example "[1, 2], [2, 3] => [1, 2, 3]")
  (vxor binary calcFunc-vxor "v X"
   :title "set exclusive or" :example "[1, 2], [2, 3] => [1, 3]")
  (vdiff binary calcFunc-vdiff "v -"
   :title "set difference" :example "[1, 2], [2, 3] => [1]")
  (vint binary calcFunc-vint "v ^"
   :title "set intersection" :example "[1, 2], [2, 3] => [2]")
  (vcompl unary calcFunc-vcompl "v ~"
   :title "set complement" :example "[1] => [[-inf .. 1), (1 .. inf]]")
  (vcard unary calcFunc-vcard "v #"
   :title "set size" :example "[1, 2, 3] => 3")
  (vspan unary calcFunc-vspan "v :"
   :title "set span" :example "[1, 3] => [1 .. 3]")
  (rdup unary calcFunc-rdup "v +"
   :title "remove duplicates" :example "[1, 2, 2, 3] => [1, 2, 3]")
  (tail unary calcFunc-tail)
  (rgrade unary calcFunc-rgrade)
  (rsort unary maf-rsort)   ; see sort above
  (rhead unary calcFunc-rhead)
  (rcons binary calcFunc-rcons)
  (rtail unary calcFunc-rtail
   :title "last element" :example "[1, 2, 3] => 3"))

(provide 'maf-cmds)
