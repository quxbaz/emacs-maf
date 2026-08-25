;; -*- lexical-binding: t; -*-
;;
;; modules/maf-log-power.el
;;
;; General-base log identities in simplification: b^log(a,b) collapses
;; to a, b^(n log(a,b)) to a^n, and log(b^y, b) to y, the way they do
;; on paper.
;;
;; Calc's `^' simplifier knows the inverse pair for exactly two bases —
;; 10 with log10 and e with ln (calc-alg.el) — and the two-argument
;; log function has no simplification rules at all. So a s leaves
;; 3^log(x, 3) sitting there, though 10^log10(x) and e^ln(x) both
;; collapse.
;;
;; The fix adds the missing rules through calc's own extension point:
;; `math-simplify-step' runs every handler on a function symbol's
;; `math-simplify' property to a fixed point, and `math-defsimplify'
;; is nothing but an append to that property. The rules mirror the
;; upstream precedents exactly, guards included. b^log(a,b) -> a is
;; unconditional, as upstream's 10^log10(x) -> x is: the exponential
;; of a log is the safe direction, and a well-formed log(a,b) already
;; presumes b is not 0 or 1. log(b^y, b) -> y is the branchy
;; direction, so it takes the same guard upstream puts on ln(e^y) and
;; log10(10^y): y known real, or `math-living-dangerously' (a s in
;; maf runs esimplify, which binds it). The scaled b^(n log(a,b)) ->
;; a^n follows upstream's e^(n ln(x)), which
;; `math-should-expand-trig' admits only under
;; `math-living-dangerously' and only for a multiplier that is an
;; integer above one or one half — so a bare -log(x,2) in the
;; exponent stays put here exactly as -ln(x) does there.
;;
;; Handlers only ever run inside `math-simplify', i.e. when
;; simplification was asked for, so unlike the normalize-advice
;; modules there is no `calc-simplify-mode' guard to add. The toggle
;; edits the property lists directly — `math-defsimplify' registers
;; anonymous lambdas that could never be removed — appending on
;; enable so upstream's rules keep first crack, deleting on disable.
;;
;; The feature is `maf-use-log-power-mode', a global minor mode
;; registered with the module system as `maf-log-power' (see
;; `maf-modules').

(require 'calc)
(require 'maf-conf "conf")   ; the `maf' customize group

;; Defined in lazily-loaded calc modules; calc-ext's autoload registry
;; resolves them at runtime, but the byte compiler needs declarations.
(declare-function math-known-realp "calc-arith")
(declare-function math-is-multiple "calc-alg")
(declare-function math-equal "calc-ext")
(declare-function maf-register-module "maf-module")

;; Dynamically bound by `math-simplify-extended' (calc-alg.el), which
;; may not be loaded; probed with `bound-and-true-p' below.
(defvar math-living-dangerously)

(defun maf-log-power--base-match (a b)
  "Whether A and B are the same logarithm base.
Structural equality covers symbolic bases; the numeric comparison
folds representation differences like 3 against 3.0."
  (or (equal a b)
      (and (Math-numberp a) (Math-numberp b) (math-equal a b))))

(defun maf-log-power--log-arg (x b)
  "The argument of X when X is a logarithm in base B, else nil.
All three spellings count: log(a, b) with a matching base, and the
dedicated log10(a) and ln(a) when B is 10 or e. Normalization
rewrites log(a, 10) into log10(a) and log(a, e) into ln(a), so a
rule that only knew the two-argument form would miss its own case
once calc got hold of it."
  (cond ((and (eq (car-safe x) 'calcFunc-log)
              (= (length x) 3)
              (maf-log-power--base-match b (nth 2 x)))
         (nth 1 x))
        ((and (eq (car-safe x) 'calcFunc-log10)
              (= (length x) 2)
              (maf-log-power--base-match b 10))
         (nth 1 x))
        ((and (eq (car-safe x) 'calcFunc-ln)
              (= (length x) 2)
              (equal b '(var e var-e)))
         (nth 1 x))))

(defun maf-log-power--pow (expr)
  "Simplify EXPR as b^log(a, b) -> a or b^(n log(a, b)) -> a^n, else nil.
Handler on `^''s `math-simplify' property, installed by
`maf-use-log-power-mode'. The log may be written any of the ways
`maf-log-power--log-arg' accepts, log10 and ln included. The bare
collapse is unconditional, like upstream's 10^log10(x) -> x: a
well-formed log(a,b) already presumes b is neither 0 nor 1, and the
exponential of a log needs no branch cut. The scaled form carries the
guard upstream puts on e^(n ln(x)) (`math-should-expand-trig'):
extended simplification's `math-living-dangerously', and a multiplier
that is an integer above one or one half."
  (let ((b (nth 1 expr))
        (x (nth 2 expr)))
    (or (maf-log-power--log-arg x b)
        (let ((m (and (bound-and-true-p math-living-dangerously)
                      (math-is-multiple x))))
          (and m
               (or (and (integerp (car m)) (> (car m) 1))
                   (equal (car m) '(frac 1 2)))
               (let ((a (maf-log-power--log-arg (nth 1 m) b)))
                 (and a (list '^ a (car m)))))))))

(defun maf-log-power--log (expr)
  "Simplify EXPR as log(b^y, b) -> y, else return nil.
Handler on `calcFunc-log''s `math-simplify' property, installed by
`maf-use-log-power-mode'. Guarded like upstream's ln(e^y) and
log10(10^y) rules: y known real, or extended simplification's
`math-living-dangerously'."
  (and (= (length expr) 3)
       (let ((pow (nth 1 expr)))
         (and (eq (car-safe pow) '^)
              (maf-log-power--base-match (nth 1 pow) (nth 2 expr))
              (or (bound-and-true-p math-living-dangerously)
                  (math-known-realp (nth 2 pow)))
              (nth 2 pow)))))

(defconst maf-log-power--handlers
  '((^ . maf-log-power--pow)
    (calcFunc-log . maf-log-power--log))
  "The simplify handlers, as (FUNCTION-SYMBOL . HANDLER) pairs.")

;;; The module

;;;###autoload
(define-minor-mode maf-use-log-power-mode
  "Simplify logarithms of general base against matching powers.

Calc only collapses b^log(a,b) when the base is 10 or e. With this
mode on, simplification does it for any base: 3^log(x, 3) becomes x,
3^(2 log(x, 3)) becomes x^2, and log(3^x, 3) becomes x too (the last
two under extended simplification — maf's a s — or, for the log, when
x is known real).

The rules run only when simplification is asked for; entering a
formula does not rewrite it. Turning the mode off affects new
simplifications only."
  :global t
  :group 'maf
  (dolist (pair maf-log-power--handlers)
    (let* ((sym (car pair))
           (fn (cdr pair))
           (handlers (delq fn (get sym 'math-simplify))))
      (put sym 'math-simplify
           (if maf-use-log-power-mode
               ;; Append, so upstream's own rules keep first crack.
               (append handlers (list fn))
             handlers)))))

;; Register with the module system when it is present; the mode above
;; works on its own without it.
(when (require 'maf-module nil t)
  (maf-register-module 'maf-log-power #'maf-use-log-power-mode
                       "Simplify b^log(a,b) and log(b^y,b) for any base.

Calc only collapses these for base 10 and e. With this on, a s also
simplifies 3^log(x, 3) to x, 3^(2 log(x, 3)) to x^2, and log(3^x, 3)
to x."
                       nil "Rewrite"))

(provide 'maf-log-power)
