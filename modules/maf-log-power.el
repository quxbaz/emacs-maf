;; -*- lexical-binding: t; -*-
;;
;; modules/maf-log-power.el
;;
;; General-base log identities in simplification: b^log(a,b) collapses
;; to a, and log(b^y, b) to y, the way it does on paper.
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
;; maf runs esimplify, which binds it).
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

(defun maf-log-power--pow (expr)
  "Simplify EXPR as b^log(a, b) -> a, else return nil.
Handler on `^''s `math-simplify' property, installed by
`maf-use-log-power-mode'. Unconditional, like upstream's
10^log10(x) -> x: a well-formed log(a,b) already presumes b is
neither 0 nor 1, and the exponential of a log needs no branch cut."
  (let ((log (nth 2 expr)))
    (and (eq (car-safe log) 'calcFunc-log)
         (= (length log) 3)
         (maf-log-power--base-match (nth 1 expr) (nth 2 log))
         (nth 1 log))))

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
mode on, a s simplifies it for any base: 3^log(x, 3) becomes x, and
log(3^x, 3) becomes x too (the latter when x is known real, or under
extended simplification — maf's a s).

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
simplifies 3^log(x, 3) to x, and log(3^x, 3) to x."
                       nil "Rewrite"))

(provide 'maf-log-power)
