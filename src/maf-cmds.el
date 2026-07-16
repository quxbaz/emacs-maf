;; -*- lexical-binding: t; -*-
;;
;; maf-cmds.el
;;
;; The standard library of contextual calc commands, defined from a table.
;; Each row (SUFFIX ARITY CALCFUNC [KEY]) expands into a `maf-defcmd' named
;; mafcmd-SUFFIX whose body applies CALCFUNC to the resolved expression and
;; commits the normalized result. `math-normalize' evaluates the call when it
;; can and leaves it symbolic otherwise, matching algebraic entry, and
;; autoloads the calc module that defines CALCFUNC on first use.
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

;; Also defvar'd in maf.el next to the minor mode; whichever file loads first
;; creates the map and the other defvar is a no-op. Declared here too so this
;; file can install the generated bindings below.
(defvar maf-mode-map (make-sparse-keymap)
  "Keymap for `maf-mode'.")

(defmacro maf-defcmds (&rest specs)
  "Define a contextual calc command for each spec in SPECS.
Each spec is a list (SUFFIX ARITY FUNC [KEY] [KEYWORD SUFFIX]...): defines
mafcmd-SUFFIX via `maf-defcmd' with :arity ARITY (unary or binary), whose
body applies FUNC to the resolved expression — plus the stack-top arg for
binary — and commits the result through `math-normalize'. When KEY (a
`kbd' string) is present, the command is bound to it in `maf-mode-map',
shadowing calc's binding of that key while `maf-mode' is on.

The optional keywords :inv, :hyp, and :invhyp name the SUFFIX of another
spec to run instead when calc's Inverse flag, Hyperbolic flag, or both
are set, making the I and H prefixes route to the variant contextually.
:map -1 opts the command out of per-side equation mapping (see
`maf-defcmd'), for commands that consume or produce relations."
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
                 (commit (math-normalize
                          (list ',func expr
                                ,@(when (eq arity 'binary) '(arg)))))))
             (when key
               (list `(define-key maf-mode-map (kbd ,key) #',name))))))
        specs)))

(maf-defcmds
  ;; arithmetic and scientific (calc-oper-keys)
  (add binary calcFunc-add "+")
  (sub binary calcFunc-sub "-")
  (mul binary calcFunc-mul "*")
  (div binary calcFunc-div "/")
  (pow binary calcFunc-pow "^" :inv nroot)
  (vconcat binary calcFunc-vconcat "|" :inv vconcatrev :hyp append :invhyp appendrev)
  (mod binary calcFunc-mod "%")
  (idiv binary calcFunc-idiv "\\")
  (fact unary calcFunc-fact "!")
  (inv unary calcFunc-inv "&")
  (neg unary calcFunc-neg "n")
  (abs unary calcFunc-abs "A")
  (conj unary calcFunc-conj "J")
  (arg unary calcFunc-arg "G")
  (sqrt unary calcFunc-sqrt "Q" :inv sqr)
  (min binary calcFunc-min "f n")
  (max binary calcFunc-max "f x")
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
  (vconcatrev binary calcFunc-vconcatrev)
  (ffloor unary calcFunc-ffloor)
  (fround unary calcFunc-fround)
  (sinh unary calcFunc-sinh)
  (cosh unary calcFunc-cosh)
  (tanh unary calcFunc-tanh)
  (log10 unary calcFunc-log10)
  (exp10 unary calcFunc-exp10)
  (append binary calcFunc-append)
  (fceil unary calcFunc-fceil)
  (ftrunc unary calcFunc-ftrunc)
  (arcsinh unary calcFunc-arcsinh)
  (arccosh unary calcFunc-arccosh)
  (arctanh unary calcFunc-arctanh)
  (appendrev binary calcFunc-appendrev)
  ;; algebra (calc-a-oper-keys)
  (collect binary calcFunc-collect "a c")
  (deriv binary calcFunc-deriv "a d" :hyp tderiv)
  (esimplify unary calcFunc-esimplify "a e")
  (factor binary calcFunc-factor "a f" :hyp factors)
  (pgcd binary calcFunc-pgcd "a g")
  (integ binary calcFunc-integ "a i")
  (match binary calcFunc-match "a m" :inv matchnot :map -1)
  (nrat unary calcFunc-nrat "a n")
  (rewrite binary calcFunc-rewrite "a r" :map -1)
  (simplify unary calcFunc-simplify "a s")
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
  (rmeq binary calcFunc-rmeq "a ." :map -1)
  (subscr binary calcFunc-subscr "a _")
  (pdiv binary calcFunc-pdiv "a \\")
  (prem binary calcFunc-prem "a %")
  (pdivrem binary calcFunc-pdivrem "a /" :hyp pdivide)
  (matchnot binary calcFunc-matchnot :map -1)
  (mapeqr binary calcFunc-mapeqr :map -1)
  (finv binary calcFunc-finv :map -1)
  (tderiv binary calcFunc-tderiv)
  (factors binary calcFunc-factors)
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
  ;; conversions (calc-c-oper-keys). Like calc-fraction, the plain key
  ;; applies the symbolic-safe pfrac; the H flag forces the exact frac.
  ;; Floating lives in stack.el: mafcmd-float (l l) floats fractions
  ;; only, and routes H to the pervasive pfloat row below.
  (deg unary calcFunc-deg "c d")
  (rad unary calcFunc-rad "c r")
  (hms unary calcFunc-hms "c h")
  (pfrac unary calcFunc-pfrac "c F" :hyp frac)
  (pfloat unary calcFunc-pfloat)
  (frac unary calcFunc-frac)
  ;; scientific functions (calc-f-oper-keys)
  (beta binary calcFunc-beta "f b")
  (erf unary calcFunc-erf "f e" :inv erfc)
  (gamma unary calcFunc-gamma "f g")
  (hypot binary calcFunc-hypot "f h")
  (im unary calcFunc-im "f i")
  (besJ binary calcFunc-besJ "f j")
  (re unary calcFunc-re "f r")
  (sign unary calcFunc-sign "f s")
  (besY binary calcFunc-besY "f y")
  (abssqr unary calcFunc-abssqr "f A")
  (expm1 unary calcFunc-expm1 "f E" :inv lnp1)
  (gammaP binary calcFunc-gammaP "f G" :inv gammaQ :hyp gammag :invhyp gammaG)
  (ilog binary calcFunc-ilog "f I")
  (lnp1 unary calcFunc-lnp1 "f L" :inv expm1)
  (mant unary calcFunc-mant "f M")
  (isqrt unary calcFunc-isqrt "f Q")
  (scf unary calcFunc-scf "f S")
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
  (dfact unary calcFunc-dfact "k d")
  (euler unary calcFunc-euler "k e")
  (prfac unary calcFunc-prfac "k f")
  (gcd binary calcFunc-gcd "k g")
  (shuffle binary calcFunc-shuffle "k h")
  (lcm binary calcFunc-lcm "k l")
  (moebius unary calcFunc-moebius "k m")
  (nextprime unary calcFunc-nextprime "k n" :inv prevprime)
  (random unary calcFunc-random "k r")
  (stir1 binary calcFunc-stir1 "k s" :hyp stir2)
  (totient unary calcFunc-totient "k t")
  (utpc binary calcFunc-utpc "k C" :inv ltpc)
  (utpp binary calcFunc-utpp "k P" :inv ltpp)
  (utpt binary calcFunc-utpt "k T" :inv ltpt)
  (prevprime unary calcFunc-prevprime)
  (ltpc binary calcFunc-ltpc)
  (ltpp binary calcFunc-ltpp)
  (ltpt binary calcFunc-ltpt)
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
  (agmean unary calcFunc-agmean)
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
  (unpack unary calcFunc-unpack "v u")
  (rev unary calcFunc-rev "v v")
  (index unary calcFunc-index "v x")
  (apply unary calcFunc-apply "v A")
  (cross unary calcFunc-cross "v C")
  (det unary calcFunc-det "v D")
  (venum unary calcFunc-venum "v E")
  (vfloor unary calcFunc-vfloor "v F")
  (grade unary calcFunc-grade "v G" :inv rgrade)
  (histogram binary calcFunc-histogram "v H")
  (inner binary calcFunc-inner "v I")
  (lud unary calcFunc-lud "v L")
  (cnorm unary calcFunc-cnorm "v N")
  (outer binary calcFunc-outer "v O")
  (reduce unary calcFunc-reduce "v R" :inv rreduce :hyp nest :invhyp fixp)
  (sort unary calcFunc-sort "v S" :inv rsort)
  (tr unary calcFunc-tr "v T")
  (accum unary calcFunc-accum "v U" :inv raccum :hyp anest :invhyp afixp)
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
  (rreduce unary calcFunc-rreduce)
  (rsort unary calcFunc-rsort)
  (raccum unary calcFunc-raccum)
  (rhead unary calcFunc-rhead)
  (rcons binary calcFunc-rcons)
  (nest binary calcFunc-nest)
  (anest binary calcFunc-anest)
  (rtail unary calcFunc-rtail)
  (fixp unary calcFunc-fixp)
  (afixp unary calcFunc-afixp))

(provide 'maf-cmds)
