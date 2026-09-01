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

:doc is the command's own first docstring line: what it does to the
target, said the way a hand-written `maf-defcmd' says it — a binary
row naming what its top-of-stack operand is there for. The generated
line under it keeps the calcFunc on record. A row without one falls
back to that generated line alone, which names the function but says
nothing a reader of *maf-keys* can use.

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
                 (example (plist-get variants :example))
                 (doc (plist-get variants :doc)))
            (append
             (list
              `(maf-defcmd ,name
                   ;; Unary bodies never touch the arg binding; name it _arg
                   ;; so the byte compiler doesn't flag it as unused.
                   (expr ,(if (eq arity 'binary) 'arg '_arg) commit)
                 ,(concat
                   (if doc
                       (format "%s\n\nContextually applies `%s' (%s)."
                               doc func arity)
                     (format "Contextually apply `%s' (%s)." func arity))
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
   :title "add" :example "x, 2 => x + 2"
   :doc "Add the top-of-stack argument to the resolved expression.")
  (sub binary calcFunc-sub "-"
   :title "subtract" :example "x, 2 => x - 2"
   :doc "Subtract the top-of-stack argument from the resolved expression.")
  (mul binary calcFunc-mul "*"
   :title "multiply" :example "x, y => x y"
   :doc "Multiply the resolved expression by the top-of-stack argument.")
  (div binary calcFunc-div "/"
   :title "divide" :example "x, 2 => x / 2"
   :doc "Divide the resolved expression by the top-of-stack argument.")
  (pow binary calcFunc-pow "^" :inv nroot
   :title "power" :example "x, 2 => x^2"
   :doc "Raise the resolved expression to the top-of-stack power.")
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
   :title "concatenate" :example "[1, 2], [3] => [1, 2, 3]"
   :doc "Join the target and the top-of-stack argument into one vector.")
  (mod binary calcFunc-mod "%"
   :title "modulo" :example "7, 3 => 1"
   :doc "Reduce the resolved expression modulo the top-of-stack argument.")
  ;; idiv cedes \ to a second square-root key (bindings.el); calc's
  ;; own \ is shadowed with it. Reachable by name, and I / is not it.
  (idiv binary calcFunc-idiv
   :title "integer division" :example "7, 2 => 3"
   :doc "Floor-divide the resolved expression by the top-of-stack argument.")
  (fact unary calcFunc-fact "!"
   :title "factorial" :example "5 => 120"
   :doc "Take the factorial of the resolved expression.")
  ;; & is calc's own key for the reciprocal; the big-language toggle
  ;; borrowed it while it had one and has since gone unbound
  ;; (bindings.el). o is a second key for it, also there.
  (inv unary calcFunc-inv "&"
   :title "reciprocal" :example "x => 1 / x"
   :doc "Replace the resolved expression with its reciprocal.")
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
   :title "complex conjugate" :example "(3, 4) => (3, -4)"
   :doc "Replace the resolved expression with its complex conjugate.")
  ;; arg cedes calc's G to the preview module, whose maf-preview-show
  ;; declares it (modules/maf-preview.el); the key stays the module's
  ;; whether it is on or off, so the row keeps none.
  (arg unary calcFunc-arg
   :title "complex argument" :example "1 => 0"
   :doc "Take the polar angle of the resolved expression.")
  (sqrt unary calcFunc-sqrt "Q" :inv sqr
   :title "square root" :example "9 => 3"
   :doc "Take the square root of the resolved expression.")
  (min binary calcFunc-min "f n"
   :title "minimum" :example "3, 5 => 3"
   :doc "Take the smaller of the target and the top-of-stack argument.")
  (max binary calcFunc-max "f x"
   :title "maximum" :example "3, 5 => 5"
   :doc "Take the larger of the target and the top-of-stack argument.")
  ;; floor cedes F in native to a second key for mafcmd-fold
  ;; (bindings.el); the calc profile keeps F = floor.
  (floor unary calcFunc-floor "F" :inv ceil :hyp ffloor :invhyp fceil
   :title "floor" :example "2.7 => 2"
   :doc "Round the resolved expression down to an integer.")
  (round unary calcFunc-round "R" :inv trunc :hyp fround :invhyp ftrunc
   :title "round" :example "2.6 => 3"
   :doc "Round the resolved expression to the nearest integer.")
  (sin unary calcFunc-sin "S" :inv arcsin :hyp sinh :invhyp arcsinh
   :title "sine" :example "0 => 0"
   :doc "Take the sine of the resolved expression.")
  (cos unary calcFunc-cos "C" :inv arccos :hyp cosh :invhyp arccosh
   :title "cosine" :example "0 => 1"
   :doc "Take the cosine of the resolved expression.")
  (tan unary calcFunc-tan "T" :inv arctan :hyp tanh :invhyp arctanh
   :title "tangent" :example "0 => 0"
   :doc "Take the tangent of the resolved expression.")
  (ln unary calcFunc-ln "L" :inv exp :hyp log10 :invhyp exp10
   :title "natural logarithm" :example "e => 1"
   :doc "Take the natural logarithm of the resolved expression.")
  (exp unary calcFunc-exp "E" :inv ln :hyp exp10 :invhyp log10
   :title "exponential" :example "0 => 1"
   :doc "Raise e to the resolved expression.")
  (log binary calcFunc-log "B" :inv alog
   :title "logarithm" :example "8, 2 => 3"
   :doc "Take the logarithm of the target to the top-of-stack base.")
  (ceil unary calcFunc-ceil
   :title "ceiling" :example "2.3 => 3"
   :doc "Round the resolved expression up to an integer.")
  (trunc unary calcFunc-trunc
   :doc "Truncate the resolved expression toward zero, to an integer.")
  (sqr unary calcFunc-sqr
   :title "square" :example "x => x^2"
   :doc "Square the resolved expression.")
  (arcsin unary calcFunc-arcsin
   :doc "Take the arcsine of the resolved expression.")
  (arccos unary calcFunc-arccos
   :doc "Take the arccosine of the resolved expression.")
  (arctan unary calcFunc-arctan
   :doc "Take the arctangent of the resolved expression.")
  (alog binary calcFunc-alog
   :doc "Raise the top-of-stack base to the resolved expression.")
  (nroot binary calcFunc-nroot
   :doc "Take the top-of-stack root of the resolved expression.")
  (vconcatrev binary maf-vconcatrev :map -1   ; see vconcat above
   :doc "Join the top-of-stack argument and the target into one vector.")
  (ffloor unary calcFunc-ffloor
   :title "float floor" :example "2.7 => 2."
   :doc "Round the resolved expression down, keeping it a float.")
  (fround unary calcFunc-fround
   :doc "Round the resolved expression to nearest, keeping it a float.")
  (sinh unary calcFunc-sinh
   :doc "Take the hyperbolic sine of the resolved expression.")
  (cosh unary calcFunc-cosh
   :doc "Take the hyperbolic cosine of the resolved expression.")
  (tanh unary calcFunc-tanh
   :doc "Take the hyperbolic tangent of the resolved expression.")
  (log10 unary calcFunc-log10
   :doc "Take the base-10 logarithm of the resolved expression.")
  (exp10 unary calcFunc-exp10
   :doc "Raise ten to the resolved expression.")
  (append binary calcFunc-append :map -1      ; see vconcat above
   :doc "Append the top-of-stack vector to the resolved vector.")
  (fceil unary calcFunc-fceil
   :title "float ceiling" :example "2.3 => 3."
   :doc "Round the resolved expression up, keeping it a float.")
  (ftrunc unary calcFunc-ftrunc
   :doc "Truncate the resolved expression toward zero, keeping it a float.")
  (arcsinh unary calcFunc-arcsinh
   :doc "Take the hyperbolic arcsine of the resolved expression.")
  (arccosh unary calcFunc-arccosh
   :doc "Take the hyperbolic arccosine of the resolved expression.")
  (arctanh unary calcFunc-arctanh
   :doc "Take the hyperbolic arctangent of the resolved expression.")
  (appendrev binary calcFunc-appendrev :map -1  ; see vconcat above
   :doc "Append the resolved vector to the top-of-stack vector.")
  ;; algebra (calc-a-oper-keys)
  (apart unary calcFunc-apart "a a"
   :title "partial fractions" :example "1 / (x^2 - 1) => 1:2 / (x - 1) - 1:2 / (x + 1)"
   :doc "Split the resolved rational function into partial fractions.")
  (collect binary calcFunc-collect "a c"
   :title "collect a variable" :example "x a + x b, x => x*(a + b)"
   :doc "Collect the target as a polynomial in the top-of-stack variable.")
  (deriv binary calcFunc-deriv "a d" :hyp tderiv
   :title "derivative" :example "x^2, x => 2 x"
   :doc "Differentiate the resolved expression by the top-of-stack variable.")
  ;; Simplifying a relation is a whole-relation job: calc divides both
  ;; sides through and moves terms across the operator. Mapped per side
  ;; each side is already as simple as it gets alone, so the command
  ;; would do nothing at all on an equation.
  (esimplify unary calcFunc-esimplify "a s" :map -1
   :title "extended simplify" :example "sqrt(x^2) => x"
   :doc "Simplify the resolved expression by calc's extended rule set.")
  ;; The seed table lists factor/factors with two arguments, but the
  ;; second is calcFunc-factor's optional variable, not an operand:
  ;; calc's own a f factors the one expression.
  (factor unary calcFunc-factor "a f" :hyp factors
   :title "factor" :example "x^2 - 1 => (x + 1) (x - 1)"
   :doc "Factor the resolved expression into a product of terms.")
  (pgcd binary calcFunc-pgcd "a g"
   :title "polynomial gcd" :example "x^2 - 1, x - 1 => x - 1"
   :doc "Take the polynomial GCD of the resolved and top-of-stack polynomials.")
  (integ binary calcFunc-integ "a i"
   :title "integral" :example "2 x, x => x^2"
   :doc "Integrate the resolved expression over the top-of-stack variable.")
  (match binary calcFunc-match "a m" :inv matchnot :map -1
   :title "match a pattern"
   :doc "Keep the top-of-stack elements matching the resolved pattern.")
  (nrat unary calcFunc-nrat "a n"
   :title "normalize to a ratio" :example "1/x + 1/y => (y + x) / (x y)"
   :doc "Rearrange the target into one reduced ratio of polynomials.")
  (rewrite binary calcFunc-rewrite "a r" :map -1
   :title "rewrite by a rule" :example "x + x, x + x := 2 x => 2 * x"
   :doc "Rewrite the resolved expression by the top-of-stack rule.")
  (simplify unary calcFunc-simplify "a e" :map -1   ; see esimplify above
   :title "simplify" :example "x + x => 2 x"
   :doc "Simplify the resolved expression by calc's default rule set.")
  (expand unary calcFunc-expand "a x"
   :title "expand" :example "(x + 1)^2 => x^2 + 2 x + 1"
   :doc "Expand the resolved expression's products and powers.")
  (mapeq binary calcFunc-mapeq "a M" :inv mapeqr :hyp mapeqp :map -1
   :title "map over an equation" :example "sqrt, x = 4 => sqrt(x) = 2"
   :doc "Apply the resolved function to both sides of the equation on top.")
  (roots binary calcFunc-roots "a P" :map -1
   :title "roots" :example "x^2 - 4, x => [2, -2]"
   :doc "Find every root of the target in the top-of-stack variable.")
  (solve binary calcFunc-solve "a S" :inv finv :hyp fsolve :invhyp ffinv :map -1
   :title "solve" :example "x^2 = 4, x => x = 2"
   :doc "Solve the resolved equation for the top-of-stack variable.")
  (eq binary calcFunc-eq "a =" :map -1
   :title "equation" :example "x, 2 => x = 2"
   :doc "Equate the target with the top-of-stack argument.")
  (neq binary calcFunc-neq "a #" :map -1
   :title "not equal" :example "x, 2 => x != 2"
   :doc "Build != between the target and the top-of-stack argument.")
  (lt binary calcFunc-lt "a <" :map -1
   :title "less than" :example "x, 2 => x < 2"
   :doc "Build < between the target and the top-of-stack argument.")
  (gt binary calcFunc-gt "a >" :map -1
   :title "greater than" :example "x, 2 => x > 2"
   :doc "Build > between the target and the top-of-stack argument.")
  (leq binary calcFunc-leq "a [" :map -1
   :title "less or equal" :example "x, 2 => x <= 2"
   :doc "Build <= between the target and the top-of-stack argument.")
  (geq binary calcFunc-geq "a ]" :map -1
   :title "greater or equal" :example "x, 2 => x >= 2"
   :doc "Build >= between the target and the top-of-stack argument.")
  (in binary calcFunc-in "a {" :map -1
   :title "membership" :example "2, [1 .. 3] => 1"
   :doc "Test whether the target is a member of the top-of-stack set.")
  (lnot unary calcFunc-lnot "a !" :map -1
   :title "logical not" :example "0 => 1"
   :doc "Take the logical negation of the resolved expression.")
  (land binary calcFunc-land "a &" :map -1
   :title "logical and" :example "1, 0 => 0"
   :doc "Build a logical and of the target and the top-of-stack argument.")
  (lor binary calcFunc-lor "a |" :map -1
   :title "logical or" :example "1, 0 => 1"
   :doc "Build a logical or of the target and the top-of-stack argument.")
  ;; rmeq cedes calc's a . to mafcmd-remove-equal (bindings.el): the
  ;; seed table lists it with two arguments, but calcFunc-rmeq takes
  ;; one, and the whole-entry scope it needs has no table spelling.
  (subscr binary calcFunc-subscr "a _"
   :title "subscript" :example "v, 2 => v_2"
   :doc "Subscript the resolved expression by the top-of-stack index.")
  (pdiv binary calcFunc-pdiv "a \\"
   :title "polynomial quotient" :example "x^2 - 1, x - 1 => x + 1"
   :doc "Divide the target polynomial by the top-of-stack one, quotient only.")
  (prem binary calcFunc-prem "a %"
   :title "polynomial remainder" :example "x^2, x - 1 => 1"
   :doc "Divide the target polynomial by the top-of-stack one, remainder only.")
  (pdivrem binary calcFunc-pdivrem "a /" :hyp pdivide
   :title "polynomial division" :example "x^2 - 1, x - 1 => [x + 1, 0]"
   :doc "Divide the target polynomial by the top-of-stack one, giving [q, r].")
  (matchnot binary calcFunc-matchnot :map -1
   :doc "Keep the top-of-stack elements not matching the resolved pattern.")
  (mapeqr binary calcFunc-mapeqr :map -1
   :doc "Apply the resolved function to both sides, reversing the inequality.")
  (finv binary calcFunc-finv :map -1
   :doc "Invert the target as a function of the top-of-stack variable.")
  (tderiv binary calcFunc-tderiv
   :doc "Totally differentiate the target by the top-of-stack variable.")
  (factors unary calcFunc-factors   ; see factor above
   :doc "Factor the resolved expression into factor-and-power pairs.")
  (mapeqp binary calcFunc-mapeqp :map -1
   :doc "Apply the resolved function to both sides, keeping the direction.")
  (fsolve binary calcFunc-fsolve :map -1
   :doc "Solve the resolved equation fully, with n1 and s1 for the family.")
  (pdivide binary calcFunc-pdivide
   :doc "Divide the target polynomial by the top-of-stack one, as q + r/d.")
  (ffinv binary calcFunc-ffinv :map -1
   :doc "Invert the target as a function, with n1 and s1 for the family.")
  ;; binary/bitwise (calc-b-oper-keys)
  (and binary calcFunc-and "b a"
   :title "bitwise and" :example "12, 10 => 8"
   :doc "Bitwise-and the target with the top-of-stack argument.")
  (or binary calcFunc-or "b o"
   :title "bitwise or" :example "12, 10 => 14"
   :doc "Bitwise-or the target with the top-of-stack argument.")
  (xor binary calcFunc-xor "b x"
   :title "bitwise exclusive or" :example "12, 10 => 6"
   :doc "Bitwise-exclusive-or the target with the top-of-stack argument.")
  (diff binary calcFunc-diff "b d"
   :title "bitwise difference" :example "12, 10 => 4"
   :doc "Clear the top-of-stack argument's bits from the target.")
  (not unary calcFunc-not "b n"
   :title "bitwise not" :example "-1 => 0"
   :doc "Complement every bit of the target within the word size.")
  (clip unary calcFunc-clip "b c"
   :title "clip to word size" :example "4294967301 => 5"
   :doc "Clip the target to the current binary word size.")
  (lsh binary calcFunc-lsh "b l"
   :title "shift left" :example "1, 4 => 16"
   :doc "Shift the target left by the top-of-stack bit count.")
  (rsh binary calcFunc-rsh "b r"
   :title "shift right" :example "16, 4 => 1"
   :doc "Shift the target right by the top-of-stack bit count.")
  (ash binary calcFunc-ash "b L"
   :title "arithmetic shift left" :example "1, 4 => 16"
   :doc "Arithmetically shift the target left by the top-of-stack count.")
  (rash binary calcFunc-rash "b R"
   :title "arithmetic shift right" :example "16, 2 => 4"
   :doc "Arithmetically shift the target right by the top-of-stack count.")
  (rot binary calcFunc-rot "b t"
   :title "rotate bits" :example "1, 1 => 2"
   :doc "Rotate the target's bits left by the top-of-stack count.")
  (vpack unary calcFunc-vpack "b p"
   :title "pack a bit set" :example "[0, 2] => 5"
   :doc "Pack the resolved set of bit positions into an integer.")
  (vunpack unary calcFunc-vunpack "b u"
   :title "unpack a bit set" :example "5 => [0, 2]"
   :doc "Unpack the resolved integer into the set of its one bits.")
  (irr unary calcFunc-irr "b I" :inv irrb
   :title "internal rate of return" :example "[-100, 60, 60] => 0.130662386292"
   :doc "Take the internal rate of return of the resolved cash flows.")
  (npv binary calcFunc-npv "b N" :inv npvb
   :title "net present value" :example "0.1, [100, 100] => 173.553719008"
   :doc "Take the present value of top-of-stack flows at the resolved rate.")
  (relch binary calcFunc-relch "b %"
   :title "percentage change" :example "50, 60 => 0.2"
   :doc "Take the relative change from the target to the top-of-stack value.")
  (irrb unary calcFunc-irrb
   :doc "Take the internal rate of return, payments at the period's start.")
  (npvb binary calcFunc-npvb
   :doc "Take the net present value, payments at the period's start.")
  ;; conversions (calc-c-oper-keys). Float/fraction conversion lives in
  ;; stack.el: mafcmd-float-frac (l l) toggles by the target's content
  ;; — floats convert toward fractions first, fractions float
  ;; otherwise — with mafcmd-float, mafcmd-frac, and the pervasive
  ;; mafcmd-float-all behind it on the I and H flags and by name.
  ;; Frac keeps its tolerance prefix arg; float and frac are I-linked.
  (deg unary calcFunc-deg "c d"
   :title "to degrees" :example "3.14159265359 => 180."
   :doc "Convert the resolved number from radians to degrees, numerically.")
  (rad unary calcFunc-rad "c r"
   :title "to radians" :example "90 => 1.57079632679"
   :doc "Convert the resolved number from degrees to radians, numerically.")
  (hms unary calcFunc-hms "c h"
   :title "to hours-minutes-seconds" :example "1.5 => 1@ 30' 0.\""
   :doc "Convert the resolved number to an hours-minutes-seconds form.")
  ;; scientific functions (calc-f-oper-keys)
  (beta binary calcFunc-beta "f b"
   :title "beta function" :example "2, 3 => 0.0833333333333"
   :doc "Take the beta function of the resolved and top-of-stack arguments.")
  (erf unary calcFunc-erf "f e" :inv erfc
   :title "error function" :example "0 => 0"
   :doc "Take the error function of the resolved expression.")
  (gamma unary calcFunc-gamma "f g"
   :title "gamma function" :example "5 => 24"
   :doc "Take the gamma function of the resolved expression.")
  ;; hypot has left the table for `mafcmd-hypot' (stack.el, f h), beside
  ;; mafcmd-cath, which is its Inverse variant and vice versa. It cannot
  ;; be a row: rows apply their function under `calc-normalize', which
  ;; normalizes the arguments first, and that floats a sqrt(3) leg before
  ;; the command can see it was exact. Calc's own `calcFunc-hypot' is
  ;; also not what it applies — see `maf--hypot'. Both directions now
  ;; live in stack.el, with the exactness rule they share.
  (im unary calcFunc-im "f i"
   :title "imaginary part" :example "(3, 4) => 4"
   :doc "Take the imaginary part of the resolved expression.")
  (besJ binary calcFunc-besJ "f j"
   :title "Bessel function J" :example "0, 0 => 1."
   :doc "Take the Bessel J of the top-of-stack argument at the resolved order.")
  (re unary calcFunc-re "f r"
   :title "real part" :example "(3, 4) => 3"
   :doc "Take the real part of the resolved expression.")
  (sign unary calcFunc-sign "f s"
   :title "sign" :example "-5 => -1"
   :doc "Reduce the resolved expression to its sign: -1, 0, or 1.")
  (besY binary calcFunc-besY "f y"
   :title "Bessel function Y" :example "1, 1 => -0.78121282"
   :doc "Take the Bessel Y of the top-of-stack argument at the resolved order.")
  (abssqr unary calcFunc-abssqr "f A"
   :title "squared magnitude" :example "(3, 4) => 25"
   :doc "Take the squared magnitude of the resolved expression.")
  (expm1 unary calcFunc-expm1 "f E" :inv lnp1
   :title "exponential minus one" :example "0 => 0"
   :doc "Take e to the target, less one, accurately near zero.")
  (gammaP binary calcFunc-gammaP "f G" :inv gammaQ :hyp gammag :invhyp gammaG
   :title "incomplete gamma" :example "1, 1 => 0.632120558829"
   :doc "Take the lower incomplete gamma P(a, x), a resolved, x on top.")
  (ilog binary calcFunc-ilog "f I"
   :title "integer logarithm" :example "100, 10 => 2"
   :doc "Take the integer logarithm of the target to the top-of-stack base.")
  ;; lnp1 cedes calc's f L to mafcmd-unit-cath (bindings.el); it stays
  ;; reachable as expm1's Inverse variant (I f E) and by name.
  (lnp1 unary calcFunc-lnp1 :inv expm1
   :doc "Take the log of one plus the target, accurately near zero.")
  (mant unary calcFunc-mant "f M"
   :title "mantissa" :example "1234.5 => 1.2345"
   :doc "Take the mantissa of the resolved float.")
  (isqrt unary calcFunc-isqrt "f Q"
   :title "integer square root" :example "17 => 4"
   :doc "Take the integer square root of the resolved expression.")
  ;; scf scales by a power of ten: scf(x, n) takes the exponent as a
  ;; second operand, so the row is binary.
  (scf binary calcFunc-scf "f S"
   :title "scale by a power of ten" :example "1.5, 3 => 1500."
   :doc "Scale the resolved expression by ten to the top-of-stack power.")
  (arctan2 binary calcFunc-arctan2 "f T"
   :title "two-argument arctangent" :example "1.0, 1.0 => 45."
   :doc "Take the angle of the point with the resolved y and top-of-stack x.")
  (xpon unary calcFunc-xpon "f X"
   :title "exponent" :example "1234.5 => 3"
   :doc "Take the exponent of the resolved float.")
  (decr binary calcFunc-decr "f ["
   :title "decrement" :example "5, 1 => 4"
   :doc "Decrement the resolved expression by the top-of-stack step.")
  (incr binary calcFunc-incr "f ]"
   :title "increment" :example "5, 1 => 6"
   :doc "Increment the resolved expression by the top-of-stack step.")
  (erfc unary calcFunc-erfc
   :doc "Take the complementary error function of the resolved expression.")
  (gammaQ binary calcFunc-gammaQ
   :doc "Take the upper incomplete gamma Q(a, x), a resolved, x on top.")
  (gammag binary calcFunc-gammag
   :doc "Take the plain lower incomplete gamma g(a, x), a resolved, x on top.")
  (gammaG binary calcFunc-gammaG
   :doc "Take the plain upper incomplete gamma G(a, x), a resolved, x on top.")
  ;; combinatorics (calc-k-oper-keys)
  (bern unary calcFunc-bern "k b"
   :title "Bernoulli number" :example "4 => -1:30"
   :doc "Take the Bernoulli number of the resolved index.")
  (choose binary calcFunc-choose "k c" :hyp perm
   :title "binomial coefficient" :example "5, 2 => 10"
   :doc "Take the binomial coefficient: the resolved n choose top-of-stack m.")
  ;; dfact cedes calc's k d to mafcmd-factor-powers (bindings.el).
  (dfact unary calcFunc-dfact
   :title "double factorial" :example "6 => 48"
   :doc "Take the double factorial of the resolved expression.")
  (euler unary calcFunc-euler "k e"
   :title "Euler number" :example "4 => 5."
   :doc "Take the Euler number of the resolved index.")
  ;; prfac cedes calc's k f to a second key for mafcmd-factor
  ;; (bindings.el), beside its table key a f, and lives on the shifted
  ;; key instead — displacing calc-utpf, the one utp lookup left
  ;; keyless here, reachable by name.
  (prfac unary calcFunc-prfac "k F"
   :title "prime factors" :example "60 => [2, 2, 3, 5]"
   :doc "Factor the resolved integer into its primes, with repetition.")
  (gcd binary calcFunc-gcd "k g"
   :title "greatest common divisor" :example "12, 18 => 6"
   :doc "Take the GCD of the resolved integer and the top-of-stack argument.")
  (shuffle binary calcFunc-shuffle "k h"
   :title "random sample"
   :doc "Sample the resolved count of distinct values below the stack top.")
  (lcm binary calcFunc-lcm "k l"
   :title "least common multiple" :example "4, 6 => 12"
   :doc "Take the LCM of the resolved integer and the top-of-stack argument.")
  (moebius unary calcFunc-moebius "k m"
   :title "Moebius function" :example "6 => 1"
   :doc "Take the Moebius function of the resolved integer.")
  (nextprime unary calcFunc-nextprime "k n" :inv prevprime
   :title "next prime" :example "10 => 11"
   :doc "Take the next prime above the resolved expression.")
  (random unary calcFunc-random "k r"
   :title "random number"
   :doc "Draw a random value within the resolved bound.")
  ;; stir1 cedes calc's k s to mafcmd-complete-square (bindings.el).
  (stir1 binary calcFunc-stir1 :hyp stir2
   :title "Stirling number, first kind" :example "4, 2 => 11"
   :doc "Take the Stirling number of the first kind, s(n, m), n resolved.")
  ;; totient cedes calc's k t to a second key for mafcmd-perm
  ;; (bindings.el), beside its k p.
  (totient unary calcFunc-totient
   :title "Euler totient" :example "12 => 4"
   :doc "Count the integers below the resolved one that are coprime to it.")
  (utpc binary calcFunc-utpc "k C" :inv ltpc
   :title "chi-square tail" :example "0, 1 => 1."
   :doc "Take the chi-square tail above the target, at top-of-stack degrees.")
  (utpp binary calcFunc-utpp "k P" :inv ltpp
   :title "Poisson tail" :example "0, 1 => 0."
   :doc "Take the Poisson tail at the top-of-stack count, resolved mean.")
  (utpt binary calcFunc-utpt "k T" :inv ltpt
   :title "Student t tail" :example "0, 1 => 1."
   :doc "Take the Student t tail above the target, at top-of-stack degrees.")
  (prevprime unary calcFunc-prevprime
   :doc "Take the last prime below the resolved expression.")
  (ltpc binary calcFunc-ltpc
   :doc "Take the chi-square area below the target, at top-of-stack degrees.")
  (ltpp binary calcFunc-ltpp
   :doc "Take the Poisson area below the top-of-stack count, resolved mean.")
  (ltpt binary calcFunc-ltpt
   :doc "Take the Student t area below the target, at top-of-stack degrees.")
  ;; perm takes calc's k p from calc-prime-test (bindings.el); calc
  ;; leaves it on choose's hyperbolic flag alone.
  (perm binary calcFunc-perm
   :title "permutations" :example "5, 2 => 20"
   :doc "Count the arrangements: the resolved n taken top-of-stack at a time.")
  (stir2 binary calcFunc-stir2
   :title "Stirling number, second kind" :example "4, 2 => 7"
   :doc "Take the Stirling number of the second kind, S(n, m), n resolved.")
  ;; store (calc-s-oper-keys)
  (assign binary calcFunc-assign "s :" :map -1
   :title "assignment" :example "x, 2 => x := 2"
   :doc "Build := between the target and the top-of-stack value.")
  (evalto unary calcFunc-evalto "s =" :map -1
   :title "evaluates to" :example "2 + 3 => 5, kept as a formula"
   :doc "Build => on the resolved expression, keeping it beside its value.")
  ;; time (calc-t-oper-keys)
  (date unary calcFunc-date "t D"
   :title "date" :example "<2026-08-31> => 739859"
   :doc "Convert the resolved expression between a date form and a day number.")
  (incmonth binary calcFunc-incmonth "t I"
   :title "next month" :example "<2026-08-31> => <Wed Sep 30, 2026>"
   :doc "Advance the resolved date by the top-of-stack number of months.")
  (julian unary calcFunc-julian "t J"
   :title "Julian day number" :example "<2026-08-31> => 2461284"
   :doc "Convert the resolved date to its Julian day number, or back.")
  (newmonth unary calcFunc-newmonth "t M"
   :title "start of month" :example "<2026-08-31> => <Sat Aug 1, 2026>"
   :doc "Take the first day of the resolved date's month.")
  (newweek unary calcFunc-newweek "t W"
   :title "start of week" :example "<2026-08-31> => <Sun Aug 30, 2026>"
   :doc "Take the Sunday on or before the resolved date.")
  (unixtime unary calcFunc-unixtime "t U"
   :title "Unix time" :example "<2026-08-31> => 1788156000"
   :doc "Convert the resolved date to Unix epoch seconds, or back.")
  (newyear unary calcFunc-newyear "t Y"
   :title "start of year" :example "<2026-08-31> => <Thu Jan 1, 2026>"
   :doc "Take the first day of the resolved date's year.")
  ;; units/statistics (calc-u-oper-keys)
  (vcov binary calcFunc-vcov "u C" :inv vpcov :hyp vcorr
   :title "covariance" :example "[1, 2, 3], [2, 4, 6] => 2"
   :doc "Take the covariance of the resolved vector and the top-of-stack one.")
  (vgmean unary calcFunc-vgmean "u G" :hyp agmean
   :title "geometric mean" :example "[1, 4] => 2"
   :doc "Take the geometric mean of the resolved vector.")
  (vmean unary calcFunc-vmean "u M" :inv vmeane :hyp vmedian :invhyp vhmean
   :title "mean" :example "[1, 2, 3] => 2"
   :doc "Take the mean of the resolved vector.")
  (vmin unary calcFunc-vmin "u N"
   :title "vector minimum" :example "[3, 1, 2] => 1"
   :doc "Take the smallest element of the resolved vector.")
  (rms unary calcFunc-rms "u R"
   :title "root mean square" :example "[3, 4] => 3.53553390593"
   :doc "Take the root mean square of the resolved vector.")
  (vsdev unary calcFunc-vsdev "u S" :inv vpsdev :hyp vvar :invhyp vpvar
   :title "standard deviation" :example "[1, 2, 3] => 1"
   :doc "Take the sample standard deviation of the resolved vector.")
  (vmax unary calcFunc-vmax "u X"
   :title "vector maximum" :example "[3, 1, 2] => 3"
   :doc "Take the largest element of the resolved vector.")
  (vpcov binary calcFunc-vpcov
   :doc "Take the population covariance of the target and top-of-stack one.")
  (vmeane unary calcFunc-vmeane
   :doc "Take the mean of the resolved vector, as a value with its error.")
  (vpsdev unary calcFunc-vpsdev
   :doc "Take the population standard deviation of the resolved vector.")
  (vcorr binary calcFunc-vcorr
   :doc "Take the correlation of the resolved vector and the top-of-stack one.")
  (agmean binary calcFunc-agmean
   :doc "Take the arithmetic-geometric mean of the target and the stack top.")
  (vmedian unary calcFunc-vmedian
   :doc "Take the median of the resolved vector.")
  (vvar unary calcFunc-vvar
   :doc "Take the sample variance of the resolved vector.")
  (vhmean unary calcFunc-vhmean
   :doc "Take the harmonic mean of the resolved vector.")
  (vpvar unary calcFunc-vpvar
   :doc "Take the population variance of the resolved vector.")
  ;; vector/matrix (calc-v-oper-keys)
  (arrange binary calcFunc-arrange "v a"
   :title "arrange into rows" :example "[1, 2, 3, 4], 2 => [[1, 2], [3, 4]]"
   :doc "Rearrange the resolved vector into rows of the top-of-stack width.")
  (cvec binary calcFunc-cvec "v b"
   :title "constant vector" :example "7, 3 => [7, 7, 7]"
   :doc "Build a vector of the resolved value repeated top-of-stack times.")
  (mcol binary calcFunc-mcol "v c"
   :title "matrix column" :example "[[1, 2], [3, 4]], 1 => [1, 3]"
   :doc "Take the top-of-stack column of the resolved matrix.")
  (diag binary calcFunc-diag "v d"
   :title "diagonal matrix" :example "1, 2 => [[1, 0], [0, 1]]"
   :doc "Build a diagonal matrix from the target, of top-of-stack size.")
  (vexp binary calcFunc-vexp "v e"
   :title "expand by a mask" :example "[1, 0, 1], [7, 8] => [7, 0, 8]"
   :doc "Spread the top-of-stack vector into the mask's nonzero slots.")
  (find binary calcFunc-find "v f"
   :title "find an element" :example "[a, b, c], b => 2"
   :doc "Find where the top-of-stack element sits in the resolved vector.")
  (head unary calcFunc-head "v h" :inv tail :hyp rhead :invhyp rtail
   :title "first element" :example "[1, 2, 3] => 1"
   :doc "Take the first element of the resolved vector.")
  (cons binary calcFunc-cons "v k" :hyp rcons
   :title "prepend" :example "1, [2, 3] => [1, 2, 3]"
   :doc "Prepend the resolved expression to the top-of-stack vector.")
  (vlen unary calcFunc-vlen "v l"
   :title "length" :example "[1, 2, 3] => 3"
   :doc "Count the elements of the resolved vector.")
  (vmask binary calcFunc-vmask "v m"
   :title "select by a mask" :example "[1, 0, 1], [7, 8, 9] => [7, 9]"
   :doc "Keep the top-of-stack elements the resolved mask marks.")
  (rnorm unary calcFunc-rnorm "v n"
   :title "row norm" :example "[3, -4] => 4"
   :doc "Take the row norm of the resolved vector: its largest magnitude.")
  (pack binary calcFunc-pack "v p"
   :title "pack into a vector"
   :doc "Pack the top-of-stack elements into the resolved mode's composite.")
  (mrow binary calcFunc-mrow "v r"
   :title "matrix row" :example "[[1, 2], [3, 4]], 1 => [1, 2]"
   :doc "Take the top-of-stack row of the resolved matrix.")
  (trn unary calcFunc-trn "v t"
   :title "transpose" :example "[[1, 2], [3, 4]] => [[1, 3], [2, 4]]"
   :doc "Transpose the resolved matrix.")
  ;; Unpacking lives in stack.el: mafcmd-unpack (M-u, and calc's own
  ;; v u) unwraps the entry at point into its parts, and mafcmd-unwrap
  ;; (j U) is its narrowing sibling, peeling the wrapper around point.
  ;; Neither is a row here because calcFunc-unpack is binary — it takes
  ;; a mode ahead of the thing — and the contextual commands take that
  ;; mode from a prefix argument rather than the stack. A row would also
  ;; be the wrong shape: the result is a list of values spread over the
  ;; stack, not a single applied call.
  (rev unary calcFunc-rev "v v"
   :title "reverse" :example "[1, 2, 3] => [3, 2, 1]"
   :doc "Reverse the resolved vector end for end.")
  (index unary calcFunc-index "v x"
   :title "index vector" :example "5 => [1, 2, 3, 4, 5]"
   :doc "Build the vector counting from one to the resolved number.")
  ;; The cross product takes both vectors as operands.
  (cross binary calcFunc-cross "v C"
   :title "cross product" :example "[1, 0, 0], [0, 1, 0] => [0, 0, 1]"
   :doc "Take the cross product of the target and the top-of-stack vector.")
  (det unary calcFunc-det "v D"
   :title "determinant" :example "[[1, 2], [3, 4]] => -2"
   :doc "Take the determinant of the resolved matrix.")
  (venum unary calcFunc-venum "v E"
   :title "enumerate a set" :example "[1 .. 4] => [1, 2, 3, 4]"
   :doc "Expand the resolved integer set into its members.")
  (vfloor unary calcFunc-vfloor "v F"
   :title "set of integers" :example "[1.5 .. 4.5] => [2 .. 4]"
   :doc "Round the resolved set's bounds inward to whole integers.")
  (grade unary calcFunc-grade "v G" :inv rgrade
   :title "sorting order" :example "[3, 1, 2] => [2, 3, 1]"
   :doc "Take the index order that would sort the resolved vector.")
  (histogram binary calcFunc-histogram "v H"
   :title "histogram" :example "[1, 2, 2, 3], 3 => [0, 1, 2]"
   :doc "Count the resolved vector's values into the top-of-stack many bins.")
  ;; lud cedes calc's v L to mafcmd-flatten (bindings.el).
  (lud unary calcFunc-lud
   :title "LU decomposition" :example "[[1, 2], [3, 4]] => [[[0, 1], [1, 0]], [[1, 0], [0.333333333333, 1]], [[3, 4], [0, 0.666666666667]]]"
   :doc "Decompose the resolved matrix into permutation, lower, and upper.")
  (cnorm unary calcFunc-cnorm "v N"
   :title "column norm" :example "[3, -4] => 7"
   :doc "Take the column norm of the resolved vector: its summed magnitudes.")
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
   :title "sort" :example "[3, 1, 2] => [1, 2, 3]"
   :doc "Sort the resolved vector into increasing order.")
  (tr unary calcFunc-tr "v T"
   :title "trace" :example "[[1, 2], [3, 4]] => 5"
   :doc "Take the trace of the resolved matrix: its diagonal summed.")
  (vunion binary calcFunc-vunion "v V"
   :title "set union" :example "[1, 2], [2, 3] => [1, 2, 3]"
   :doc "Take the union of the resolved set and the top-of-stack one.")
  (vxor binary calcFunc-vxor "v X"
   :title "set exclusive or" :example "[1, 2], [2, 3] => [1, 3]"
   :doc "Take the exclusive or of the resolved set and the top-of-stack one.")
  (vdiff binary calcFunc-vdiff "v -"
   :title "set difference" :example "[1, 2], [2, 3] => [1]"
   :doc "Drop the top-of-stack set's elements from the resolved one.")
  (vint binary calcFunc-vint "v ^"
   :title "set intersection" :example "[1, 2], [2, 3] => [2]"
   :doc "Take the intersection of the resolved set and the top-of-stack one.")
  (vcompl unary calcFunc-vcompl "v ~"
   :title "set complement" :example "[1] => [[-inf .. 1), (1 .. inf]]"
   :doc "Take the complement of the resolved set over the real line.")
  (vcard unary calcFunc-vcard "v #"
   :title "set size" :example "[1, 2, 3] => 3"
   :doc "Count the integers in the resolved set.")
  ;; vspan has left the table for `mafcmd-vspan' (src/stack.el, v :): it
  ;; grew a second reading — an ordering relation spans to the interval
  ;; it bounds its subject to — which needs a body to choose between
  ;; them, and :map -1, since a relation is its subject rather than a
  ;; pair of sides to run over.
  (rdup unary calcFunc-rdup "v +"
   :title "remove duplicates" :example "[1, 2, 2, 3] => [1, 2, 3]"
   :doc "Sort the resolved vector and drop its duplicates.")
  (tail unary calcFunc-tail
   :doc "Take the resolved vector without its first element.")
  (rgrade unary calcFunc-rgrade
   :doc "Take the index order that would sort the resolved vector downward.")
  (rsort unary maf-rsort
   :doc "Sort the resolved vector into decreasing order.")   ; see sort above
  (rhead unary calcFunc-rhead
   :doc "Take the resolved vector without its last element.")
  (rcons binary calcFunc-rcons
   :doc "Append the top-of-stack element to the resolved vector.")
  (rtail unary calcFunc-rtail
   :title "last element" :example "[1, 2, 3] => 3"
   :doc "Take the last element of the resolved vector."))

(provide 'maf-cmds)
