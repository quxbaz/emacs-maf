;; maf-e-power module: symbolic exp(x) comes out of normalization as
;; e^x. The rewrite rides the normalize funnels, so it is exercised
;; through `calc-enter-result' — the commit path every command and
;; entry uses — and through a computed result (auto-solve). Numeric
;; evaluation computes exp before any form survives, so it is
;; asserted untouched. Symbolic mode is bound per case: the rewrite
;; only matters where a symbolic exp survives at all.

(maf-step
  (cl-assert maf-use-e-power-mode)

  ;; A committed symbolic exp comes out as a power of e.
  (calc-wrapper
   (let ((calc-symbolic-mode t))
     (calc-enter-result 0 "test" (math-read-expr "exp(2 y) + 1"))))
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "e^(2 y) + 1"))
  (calc-pop (calc-stack-size))

  ;; exp(1) is the bare constant, not e^1.
  (calc-wrapper
   (let ((calc-symbolic-mode t))
     (calc-enter-result 0 "test" (math-read-expr "exp(1)"))))
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "e"))
  (calc-pop (calc-stack-size))

  ;; The solve that motivated the module: ln(x) = 2 lands as x = e^2,
  ;; not x = exp(2).
  (maf-push "ln(x) = 2")
  (goto-char (point-max))
  (call-interactively 'mafcmd-auto-solve)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "x = e^2"))
  (calc-pop (calc-stack-size))

  ;; Identities still hold on the power form: ln inverts it.
  (calc-wrapper
   (let ((calc-symbolic-mode t))
     (calc-enter-result 0 "test" (math-read-expr "ln(exp(2))"))))
  (cl-assert (equal (calc-top 1 'full) 2))
  (calc-pop (calc-stack-size))

  ;; Numeric work is untouched: exp of a float computes to a number
  ;; before any exp form survives to be rewritten.
  (calc-wrapper
   (let ((calc-symbolic-mode nil))
     (calc-enter-result 0 "test" (math-read-expr "exp(1.0)"))))
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "2.71828182846"))
  (calc-pop (calc-stack-size))

  ;; Module off, the function form calc produces is kept.
  (unwind-protect
      (progn
        (maf-use-e-power-mode -1)
        (calc-wrapper
         (let ((calc-symbolic-mode t))
           (calc-enter-result 0 "test" (math-read-expr "exp(2 y)"))))
        (cl-assert (string= (math-format-value (calc-top 1 'full))
                            "exp(2 y)")))
    (maf-use-e-power-mode 1))
  (calc-pop (calc-stack-size)))
