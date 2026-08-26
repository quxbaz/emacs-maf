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
                 (mapv (plist-get variants :map)))
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
             (when key
               (list `(maf-cmds--table-key ,key #',name))))))
        specs)))

(maf-defcmds
  ;; arithmetic and scientific (calc-oper-keys)
  (add binary calcFunc-add "+")
  (sub binary calcFunc-sub "-")
  (mul binary calcFunc-mul "*")
  (div binary calcFunc-div "/")
  (pow binary calcFunc-pow "^" :inv nroot)
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
  (vconcat binary maf-vconcat "|" :inv vconcatrev :hyp append :invhyp appendrev :map -1)
  (mod binary calcFunc-mod "%")
  ;; idiv cedes \ to a second square-root key (bindings.el); calc's
  ;; own \ is shadowed with it. Reachable by name, and I / is not it.
  (idiv binary calcFunc-idiv)
  (fact unary calcFunc-fact "!")
  ;; & is calc's own key for the reciprocal; the big-language toggle
  ;; borrowed it while it had one and has since gone unbound
  ;; (bindings.el). o is a second key for it, also there.
  (inv unary calcFunc-inv "&")
  (neg unary calcFunc-neg "n")
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
  (conj unary calcFunc-conj "J")
  ;; arg cedes calc's G to the preview module, whose maf-preview-show
  ;; declares it (modules/maf-preview.el); the key stays the module's
  ;; whether it is on or off, so the row keeps none.
  (arg unary calcFunc-arg)
  (sqrt unary calcFunc-sqrt "Q" :inv sqr)
  (min binary calcFunc-min "f n")
  (max binary calcFunc-max "f x")
  ;; floor cedes F in native to a second key for mafcmd-reduce
  ;; (bindings.el); the calc profile keeps F = floor.
  (floor unary calcFunc-floor "F" :inv ceil :hyp ffloor :invhyp fceil)
  (round unary calcFunc-round "R" :inv trunc :hyp fround :invhyp ftrunc)
  (sin unary calcFunc-sin "S" :inv arcsin :hyp sinh :invhyp arcsinh)
  (cos unary calcFunc-cos "C" :inv arccos :hyp cosh :invhyp arccosh)
  (tan unary calcFunc-tan "T" :inv arctan :hyp tanh :invhyp arctanh)
  (ln unary calcFunc-ln "L" :inv exp :hyp log10 :invhyp exp10)
  (exp unary calcFunc-exp "E" :inv ln :hyp exp10 :invhyp log10)
  (log binary calcFunc-log "B" :inv alog)
  (ceil unary calcFunc-ceil)
  (trunc unary calcFunc-trunc)
  (sqr unary calcFunc-sqr)
  (arcsin unary calcFunc-arcsin)
  (arccos unary calcFunc-arccos)
  (arctan unary calcFunc-arctan)
  (alog binary calcFunc-alog)
  (nroot binary calcFunc-nroot)
  (vconcatrev binary maf-vconcatrev :map -1)   ; see vconcat above
  (ffloor unary calcFunc-ffloor)
  (fround unary calcFunc-fround)
  (sinh unary calcFunc-sinh)
  (cosh unary calcFunc-cosh)
  (tanh unary calcFunc-tanh)
  (log10 unary calcFunc-log10)
  (exp10 unary calcFunc-exp10)
  (append binary calcFunc-append :map -1)      ; see vconcat above
  (fceil unary calcFunc-fceil)
  (ftrunc unary calcFunc-ftrunc)
  (arcsinh unary calcFunc-arcsinh)
  (arccosh unary calcFunc-arccosh)
  (arctanh unary calcFunc-arctanh)
  (appendrev binary calcFunc-appendrev :map -1)  ; see vconcat above
  ;; algebra (calc-a-oper-keys)
  (apart unary calcFunc-apart "a a")
  (collect binary calcFunc-collect "a c")
  (deriv binary calcFunc-deriv "a d" :hyp tderiv)
  ;; Simplifying a relation is a whole-relation job: calc divides both
  ;; sides through and moves terms across the operator. Mapped per side
  ;; each side is already as simple as it gets alone, so the command
  ;; would do nothing at all on an equation.
  (esimplify unary calcFunc-esimplify "a s" :map -1)
  ;; The seed table lists factor/factors with two arguments, but the
  ;; second is calcFunc-factor's optional variable, not an operand:
  ;; calc's own a f factors the one expression.
  (factor unary calcFunc-factor "a f" :hyp factors)
  (pgcd binary calcFunc-pgcd "a g")
  (integ binary calcFunc-integ "a i")
  (match binary calcFunc-match "a m" :inv matchnot :map -1)
  (nrat unary calcFunc-nrat "a n")
  (rewrite binary calcFunc-rewrite "a r" :map -1)
  (simplify unary calcFunc-simplify "a e" :map -1)   ; see esimplify above
  (expand unary calcFunc-expand "a x")
  (mapeq binary calcFunc-mapeq "a M" :inv mapeqr :hyp mapeqp :map -1)
  (roots binary calcFunc-roots "a P" :map -1)
  (solve binary calcFunc-solve "a S" :inv finv :hyp fsolve :invhyp ffinv :map -1)
  (eq binary calcFunc-eq "a =" :map -1)
  (neq binary calcFunc-neq "a #" :map -1)
  (lt binary calcFunc-lt "a <" :map -1)
  (gt binary calcFunc-gt "a >" :map -1)
  (leq binary calcFunc-leq "a [" :map -1)
  (geq binary calcFunc-geq "a ]" :map -1)
  (in binary calcFunc-in "a {" :map -1)
  (lnot unary calcFunc-lnot "a !" :map -1)
  (land binary calcFunc-land "a &" :map -1)
  (lor binary calcFunc-lor "a |" :map -1)
  ;; rmeq cedes calc's a . to mafcmd-remove-equal (bindings.el): the
  ;; seed table lists it with two arguments, but calcFunc-rmeq takes
  ;; one, and the whole-entry scope it needs has no table spelling.
  (subscr binary calcFunc-subscr "a _")
  (pdiv binary calcFunc-pdiv "a \\")
  (prem binary calcFunc-prem "a %")
  (pdivrem binary calcFunc-pdivrem "a /" :hyp pdivide)
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
  (and binary calcFunc-and "b a")
  (or binary calcFunc-or "b o")
  (xor binary calcFunc-xor "b x")
  (diff binary calcFunc-diff "b d")
  (not unary calcFunc-not "b n")
  (clip unary calcFunc-clip "b c")
  (lsh binary calcFunc-lsh "b l")
  (rsh binary calcFunc-rsh "b r")
  (ash binary calcFunc-ash "b L")
  (rash binary calcFunc-rash "b R")
  (rot binary calcFunc-rot "b t")
  (vpack unary calcFunc-vpack "b p")
  (vunpack unary calcFunc-vunpack "b u")
  (irr unary calcFunc-irr "b I" :inv irrb)
  (npv binary calcFunc-npv "b N" :inv npvb)
  (relch binary calcFunc-relch "b %")
  (irrb unary calcFunc-irrb)
  (npvb binary calcFunc-npvb)
  ;; conversions (calc-c-oper-keys). Float/fraction conversion lives in
  ;; stack.el: mafcmd-float-frac (l l) toggles by the target's content
  ;; — floats convert toward fractions first, fractions float
  ;; otherwise — with mafcmd-float, mafcmd-frac, and the pervasive
  ;; mafcmd-float-all behind it on the I and H flags and by name.
  ;; Frac keeps its tolerance prefix arg; float and frac are I-linked.
  (deg unary calcFunc-deg "c d")
  (rad unary calcFunc-rad "c r")
  (hms unary calcFunc-hms "c h")
  ;; scientific functions (calc-f-oper-keys)
  (beta binary calcFunc-beta "f b")
  (erf unary calcFunc-erf "f e" :inv erfc)
  (gamma unary calcFunc-gamma "f g")
  ;; hypot has left the table for `mafcmd-hypot' (stack.el, f h), beside
  ;; mafcmd-cath, which is its Inverse variant and vice versa. It cannot
  ;; be a row: rows apply their function under `calc-normalize', which
  ;; normalizes the arguments first, and that floats a sqrt(3) leg before
  ;; the command can see it was exact. Calc's own `calcFunc-hypot' is
  ;; also not what it applies — see `maf--hypot'. Both directions now
  ;; live in stack.el, with the exactness rule they share.
  (im unary calcFunc-im "f i")
  (besJ binary calcFunc-besJ "f j")
  (re unary calcFunc-re "f r")
  (sign unary calcFunc-sign "f s")
  (besY binary calcFunc-besY "f y")
  (abssqr unary calcFunc-abssqr "f A")
  (expm1 unary calcFunc-expm1 "f E" :inv lnp1)
  (gammaP binary calcFunc-gammaP "f G" :inv gammaQ :hyp gammag :invhyp gammaG)
  (ilog binary calcFunc-ilog "f I")
  ;; lnp1 cedes calc's f L to mafcmd-unit-cath (bindings.el); it stays
  ;; reachable as expm1's Inverse variant (I f E) and by name.
  (lnp1 unary calcFunc-lnp1 :inv expm1)
  (mant unary calcFunc-mant "f M")
  (isqrt unary calcFunc-isqrt "f Q")
  ;; scf scales by a power of ten: scf(x, n) takes the exponent as a
  ;; second operand, so the row is binary.
  (scf binary calcFunc-scf "f S")
  (arctan2 binary calcFunc-arctan2 "f T")
  (xpon unary calcFunc-xpon "f X")
  (decr binary calcFunc-decr "f [")
  (incr binary calcFunc-incr "f ]")
  (erfc unary calcFunc-erfc)
  (gammaQ binary calcFunc-gammaQ)
  (gammag binary calcFunc-gammag)
  (gammaG binary calcFunc-gammaG)
  ;; combinatorics (calc-k-oper-keys)
  (bern unary calcFunc-bern "k b")
  (choose binary calcFunc-choose "k c" :hyp perm)
  ;; dfact cedes calc's k d to mafcmd-factor-powers (bindings.el).
  (dfact unary calcFunc-dfact)
  (euler unary calcFunc-euler "k e")
  ;; prfac cedes calc's k f to a second key for mafcmd-factor
  ;; (bindings.el), beside its table key a f.
  (prfac unary calcFunc-prfac)
  (gcd binary calcFunc-gcd "k g")
  (shuffle binary calcFunc-shuffle "k h")
  (lcm binary calcFunc-lcm "k l")
  (moebius unary calcFunc-moebius "k m")
  (nextprime unary calcFunc-nextprime "k n" :inv prevprime)
  (random unary calcFunc-random "k r")
  ;; stir1 cedes calc's k s to mafcmd-complete-square (bindings.el).
  (stir1 binary calcFunc-stir1 :hyp stir2)
  ;; totient cedes calc's k t to a second key for mafcmd-perm
  ;; (bindings.el), beside its k p.
  (totient unary calcFunc-totient)
  (utpc binary calcFunc-utpc "k C" :inv ltpc)
  (utpp binary calcFunc-utpp "k P" :inv ltpp)
  (utpt binary calcFunc-utpt "k T" :inv ltpt)
  (prevprime unary calcFunc-prevprime)
  (ltpc binary calcFunc-ltpc)
  (ltpp binary calcFunc-ltpp)
  (ltpt binary calcFunc-ltpt)
  ;; perm takes calc's k p from calc-prime-test (bindings.el); calc
  ;; leaves it on choose's hyperbolic flag alone.
  (perm binary calcFunc-perm)
  (stir2 binary calcFunc-stir2)
  ;; store (calc-s-oper-keys)
  (assign binary calcFunc-assign "s :" :map -1)
  (evalto unary calcFunc-evalto "s =" :map -1)
  ;; time (calc-t-oper-keys)
  (date unary calcFunc-date "t D")
  (incmonth binary calcFunc-incmonth "t I")
  (julian unary calcFunc-julian "t J")
  (newmonth unary calcFunc-newmonth "t M")
  (newweek unary calcFunc-newweek "t W")
  (unixtime unary calcFunc-unixtime "t U")
  (newyear unary calcFunc-newyear "t Y")
  ;; units/statistics (calc-u-oper-keys)
  (vcov binary calcFunc-vcov "u C" :inv vpcov :hyp vcorr)
  (vgmean unary calcFunc-vgmean "u G" :hyp agmean)
  (vmean unary calcFunc-vmean "u M" :inv vmeane :hyp vmedian :invhyp vhmean)
  (vmin unary calcFunc-vmin "u N")
  (rms unary calcFunc-rms "u R")
  (vsdev unary calcFunc-vsdev "u S" :inv vpsdev :hyp vvar :invhyp vpvar)
  (vmax unary calcFunc-vmax "u X")
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
  (arrange binary calcFunc-arrange "v a")
  (cvec binary calcFunc-cvec "v b")
  (mcol binary calcFunc-mcol "v c")
  (diag binary calcFunc-diag "v d")
  (vexp binary calcFunc-vexp "v e")
  (find binary calcFunc-find "v f")
  (head unary calcFunc-head "v h" :inv tail :hyp rhead :invhyp rtail)
  (cons binary calcFunc-cons "v k" :hyp rcons)
  (vlen unary calcFunc-vlen "v l")
  (vmask binary calcFunc-vmask "v m")
  (rnorm unary calcFunc-rnorm "v n")
  (pack binary calcFunc-pack "v p")
  (mrow binary calcFunc-mrow "v r")
  (trn unary calcFunc-trn "v t")
  ;; Unpacking lives in stack.el: mafcmd-unpack (M-u, and calc's own
  ;; v u) unwraps the entry at point into its parts, and mafcmd-unwrap
  ;; (j U) is its narrowing sibling, peeling the wrapper around point.
  ;; Neither is a row here because calcFunc-unpack is binary — it takes
  ;; a mode ahead of the thing — and the contextual commands take that
  ;; mode from a prefix argument rather than the stack. A row would also
  ;; be the wrong shape: the result is a list of values spread over the
  ;; stack, not a single applied call.
  (rev unary calcFunc-rev "v v")
  (index unary calcFunc-index "v x")
  ;; The cross product takes both vectors as operands.
  (cross binary calcFunc-cross "v C")
  (det unary calcFunc-det "v D")
  (venum unary calcFunc-venum "v E")
  (vfloor unary calcFunc-vfloor "v F")
  (grade unary calcFunc-grade "v G" :inv rgrade)
  (histogram binary calcFunc-histogram "v H")
  ;; lud cedes calc's v L to mafcmd-flatten (bindings.el).
  (lud unary calcFunc-lud)
  (cnorm unary calcFunc-cnorm "v N")
  ;; The combinators — apply, reduce, accum, outer, inner and the
  ;; nest/fixp variants — are not rows: their leading argument is an
  ;; operation, not an operand, so applying the calcFunc to the
  ;; resolved expression builds a call of the wrong arity that
  ;; `calc-normalize' can only hand back inert. They read the
  ;; operation from the next key instead (`mafcmd-reduce' and
  ;; friends, src/stack.el).
  ;; sort/rsort use maf's own ordering rather than calcFunc-sort:
  ;; calc sorts by expression shape, which strands every negated
  ;; symbolic term after its positive twin ([sqrt(10), -sqrt(10)] comes
  ;; back untouched). maf orders by numeric value when every element
  ;; has one, and defers to calc otherwise (see `maf--sort-vector').
  (sort unary maf-sort "v S" :inv rsort)
  (tr unary calcFunc-tr "v T")
  (vunion binary calcFunc-vunion "v V")
  (vxor binary calcFunc-vxor "v X")
  (vdiff binary calcFunc-vdiff "v -")
  (vint binary calcFunc-vint "v ^")
  (vcompl unary calcFunc-vcompl "v ~")
  (vcard unary calcFunc-vcard "v #")
  (vspan unary calcFunc-vspan "v :")
  (rdup unary calcFunc-rdup "v +")
  (tail unary calcFunc-tail)
  (rgrade unary calcFunc-rgrade)
  (rsort unary maf-rsort)   ; see sort above
  (rhead unary calcFunc-rhead)
  (rcons binary calcFunc-rcons)
  (rtail unary calcFunc-rtail))

(provide 'maf-cmds)
