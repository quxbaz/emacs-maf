;; -*- lexical-binding: t; -*-
;;
;; modules/maf-e-power.el
;;
;; Exponentials as powers of e: symbolic exp(x) written e^x, the way
;; it is written on paper.
;;
;; Calc prints the symbolic exponential as a function call, so a solve
;; involving a logarithm comes back as x = exp(2) where paper writes
;; x = e^2. There is no display setting for this — calccomp.el gives
;; exp no special composition in any language mode — but the e^x form
;; is first-class in calc: the `^' simplifier leaves e^2 alone (its
;; `math-simplify-exp' only rewrites special exponents like ln(y)),
;; ln(e^2) still simplifies to 2, and N still floats e^2 to 7.389. So
;; a formula rewritten into the power form stays there, and nothing
;; downstream misses the function form.
;;
;; The fix is a piece of :filter-return advice that takes each
;; formula coming out of normalization and, when it is a symbolic
;; exp call, rewrites it into a power of the constant e. Only forms
;; that survive evaluation are touched: exp of a float computes to a
;; number before any calcFunc-exp form reaches the filter, so numeric
;; work never changes. Subformulas are covered by normalization's own
;; recursion — each exp node passes through the funnel itself on the
;; way up.
;;
;; The advice sits on `math-normalize' and `calc-normalize', the same
;; two funnels as maf-poly-order and for the same reason: the former
;; catches every internally computed formula, the latter the top level
;; of a commit under the fancy simplify modes ('alg, 'units) where
;; `math-simplify' can hand a result back without a final normalize.
;;
;; Two states hold the advice back. `calc-simplify-mode' 'none means
;; hands off, as everywhere in maf — the user asked calc to leave
;; formulas alone. And during symbolic integration the exp form is
;; load-bearing: upstream's own `^' simplifier keeps exp intact while
;; `math-integrating', and the integrator's tables match on it, so the
;; advice stands aside there too; the final result still passes a
;; normalize after the integrator returns and is rewritten then.
;;
;; The feature is `maf-use-e-power-mode', a global minor mode
;; registered with the module system as `maf-e-power' (see
;; `maf-modules').

(require 'calc)
(require 'maf-conf "conf")   ; the `maf' customize group

;; Dynamically bound by calc's integrator (calcalg2.el), which may not
;; be loaded; probed with `bound-and-true-p' below.
(defvar math-integrating)

(defun maf-e-power--normalize (result)
  "Rewrite RESULT from exp(x) into e^x form when it is a symbolic exp.
Filter-return advice on `math-normalize' and `calc-normalize',
installed by `maf-use-e-power-mode'. Stands aside under
`calc-simplify-mode' 'none and while `math-integrating', where the
exp form is load-bearing for the integrator. exp(1) becomes the bare
constant e — the power form would read e^1, which normalization has
already collapsed for powers it builds itself."
  (if (and (eq (car-safe result) 'calcFunc-exp)
           (= (length result) 2)
           (not (eq calc-simplify-mode 'none))
           (not (bound-and-true-p math-integrating)))
      (let ((x (nth 1 result)))
        (if (eq x 1) '(var e var-e) (list '^ '(var e var-e) x)))
    result))

;;; The module

;;;###autoload
(define-minor-mode maf-use-e-power-mode
  "Global minor mode writing the symbolic exponential as a power of e.
Enabled, every symbolic exp(x) coming out of normalization is
rewritten to e^x, so solving ln(x) = 2 lands as x = e^2 rather than
x = exp(2). Numeric work is untouched — exp of a float computes to a
number before any exp form survives — and calc's identities still
hold on the power form: ln(e^2) simplifies to 2, N floats e^2.
Disabled, formulas keep the exp(x) function form calc produces;
already-rewritten entries on the stack stay as they are either way.

The rewrite rides one filter on `math-normalize' — the funnel for
internally computed formulas — and on `calc-normalize', which catches
the top level of a commit under the fancy simplify modes ('alg,
'units). It stands aside under `calc-simplify-mode' 'none and during
symbolic integration, where the integrator matches on the exp form.
This is the `maf-e-power' module (see `maf-modules')."
  :global t
  :group 'maf
  (if maf-use-e-power-mode
      (progn
        (advice-add 'math-normalize :filter-return #'maf-e-power--normalize)
        (advice-add 'calc-normalize :filter-return #'maf-e-power--normalize))
    (advice-remove 'math-normalize #'maf-e-power--normalize)
    (advice-remove 'calc-normalize #'maf-e-power--normalize)))

;; Register with the module system when it is present; the mode above
;; works on its own without it.
(when (require 'maf-module nil t)
  (maf-register-module 'maf-e-power #'maf-use-e-power-mode
                       "Write the exponential function as a power of e: exp(2) becomes e^2.

Calc prints the symbolic exponential as a function call, so a solve
comes back as x = exp(2) where paper writes e^2. Symbolic exp forms
are rewritten into powers of the constant e as results normalize.
Numeric work never changes: exp of a float still computes to a
number, and N still floats e^2 to 7.389."))

(provide 'maf-e-power)
