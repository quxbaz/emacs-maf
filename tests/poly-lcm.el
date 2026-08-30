;; Port verification for mafcmd-poly-lcm (a L): the LCM of the
;; resolved expression and the top-of-stack argument, factored.

(maf-step
  ;; Basic: integer content out front, shared factor kept once.
  (maf-push "6*(x + 1)")
  (maf-push "4*(x + 1)")
  (call-interactively 'mafcmd-poly-lcm)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "12 (x + 1)"))
  (cl-assert (= (calc-stack-size) 1))
  (calc-pop (calc-stack-size))

  ;; The same operands expanded: calc's own factoring leaves content in
  ;; place (12 x + 12 factors to itself), so the content is taken out
  ;; before factoring.
  (maf-push "6*x + 6")
  (maf-push "4*x + 4")
  (call-interactively 'mafcmd-poly-lcm)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "12 (x + 1)"))
  (calc-pop (calc-stack-size))

  ;; Shared and unshared factors: x - 1 appears once, x and x + 1 join it.
  (maf-push "x^2 - 1")
  (maf-push "x^2 - x")
  (call-interactively 'mafcmd-poly-lcm)
  (cl-assert (string= (math-format-value (calc-top 1 'full))
                      "(x + 1) (x - 1) x"))
  (calc-pop (calc-stack-size))

  ;; Coprime operands: the product, still factored.
  (maf-push "x + 1")
  (maf-push "x + 2")
  (call-interactively 'mafcmd-poly-lcm)
  (cl-assert (string= (math-format-value (calc-top 1 'full))
                      "(x + 1) (x + 2)"))
  (calc-pop (calc-stack-size))

  ;; Identical operands: the LCM is the operand, not its square.
  (maf-push "x^2 - 1")
  (maf-push "x^2 - 1")
  (call-interactively 'mafcmd-poly-lcm)
  (cl-assert (string= (math-format-value (calc-top 1 'full))
                      "(x + 1) (x - 1)"))
  (calc-pop (calc-stack-size))

  ;; Repeated factor: calc factors x^2 + 2 x + 1 to (x + 1)^2, whose
  ;; exponent must be seen as a multiplicity rather than an opaque base.
  (maf-push "x^2 + 2*x + 1")
  (maf-push "x + 1")
  (call-interactively 'mafcmd-poly-lcm)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "(x + 1)^2"))
  (calc-pop (calc-stack-size))

  ;; Higher of the two exponents, with the content LCM out front.
  (maf-push "2*x^2 - 8")
  (maf-push "3*x^2 + 12*x + 12")
  (call-interactively 'mafcmd-poly-lcm)
  (cl-assert (string= (math-format-value (calc-top 1 'full))
                      "6 (x + 2)^2 (x - 2)"))
  (calc-pop (calc-stack-size))

  ;; Multivariate, already factored: each base keeps its higher power.
  (maf-push "4*(z - 4)^2*(w + 3)")
  (maf-push "18*(z - 4)^3*(w + 3)^3")
  (call-interactively 'mafcmd-poly-lcm)
  (cl-assert (string= (math-format-value (calc-top 1 'full))
                      "36 (z - 4)^3 (w + 3)^3"))
  (calc-pop (calc-stack-size))

  ;; Multivariate monomials: bare variables are factors too.
  (maf-push "12*z^6*(w - 7)^3")
  (maf-push "20*z^5*(w - 7)^4")
  (call-interactively 'mafcmd-poly-lcm)
  (cl-assert (string= (math-format-value (calc-top 1 'full))
                      "60 z^6 (w - 7)^4"))
  (calc-pop (calc-stack-size))

  ;; Opposite signs: calc factors 4 - x^2 as (x + 2) (2 - x), so 2 - x
  ;; must fold onto x - 2 instead of stacking a third factor.
  (maf-push "x^2 - 4")
  (maf-push "4 - x^2")
  (call-interactively 'mafcmd-poly-lcm)
  (cl-assert (string= (math-format-value (calc-top 1 'full))
                      "(x + 2) (x - 2)"))
  (calc-pop (calc-stack-size))

  ;; A negative-leading operand: the sign goes into the coefficient,
  ;; which always comes out positive.
  (maf-push "-6*x - 6")
  (maf-push "4*x + 4")
  (call-interactively 'mafcmd-poly-lcm)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "12 (x + 1)"))
  (calc-pop (calc-stack-size))

  ;; Exact rational content: 1:2 x + 1:2 has content 1:2, and
  ;; lcm(1:2, 1:3) is 1.
  (maf-push "(1:2)*x + 1:2")
  (maf-push "(1:3)*x + 1:3")
  (call-interactively 'mafcmd-poly-lcm)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "x + 1"))
  (calc-pop (calc-stack-size))

  ;; Plain numbers: calc's own integer lcm.
  (maf-push "6")
  (maf-push "4")
  (call-interactively 'mafcmd-poly-lcm)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "12"))
  (calc-pop (calc-stack-size))

  ;; A zero operand: the LCM is 0, not 0 times a product.
  (maf-push "0")
  (maf-push "x + 1")
  (call-interactively 'mafcmd-poly-lcm)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "0"))
  (calc-pop (calc-stack-size))

  ;; Non-polynomial factors are still merged by multiplicity.
  (maf-push "sin(t)^2")
  (maf-push "sin(t)^3")
  (call-interactively 'mafcmd-poly-lcm)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "sin(t)^3"))
  (calc-pop (calc-stack-size))

  ;; Incomplete factoring: calc splits x^10 - 1 into
  ;; (x + 1) (x - 1) (x^8 + x^6 + x^4 + x^2 + 1), hiding the factor
  ;; x^5 - 1 shares, so a plain merge would multiply it in twice. The
  ;; pgcd check catches that and the result stays x^10 - 1.
  (maf-push "x^10 - 1")
  (maf-push "x^5 - 1")
  (call-interactively 'mafcmd-poly-lcm)
  (cl-assert (string= (math-format-value (calc-top 1 'full))
                      "(x + 1) (x^8 + x^6 + x^4 + x^2 + 1) (x - 1)"))
  (calc-pop (calc-stack-size))

  ;; A monomial pair, where calc's pgcd is unreliable: pgcd(2 x^2, x)
  ;; is 2, not x, so the pgcd reference works out to x^3 — not even a
  ;; multiple of 2 x^2. The zero-remainder condition on the division
  ;; rejects it and the merged result stands.
  (maf-push "2*x^2")
  (maf-push "x")
  (call-interactively 'mafcmd-poly-lcm)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "2 x^2"))
  (calc-pop (calc-stack-size))

  ;; Float coefficients have no exact content and pgcd rejects them:
  ;; the product stands as the common multiple rather than erroring.
  (maf-push "2.5*x + 5")
  (maf-push "x + 2")
  (call-interactively 'mafcmd-poly-lcm)
  (cl-assert (string= (math-format-value (calc-top 1 'full))
                      "(2.5 x + 5) (x + 2)"))
  (calc-pop (calc-stack-size))

  ;; Equation subject: each side takes its LCM with the same argument.
  (maf-push "x^2 - 1 = x^2 - x")
  (maf-push "x + 1")
  (call-interactively 'mafcmd-poly-lcm)
  (cl-assert (string= (math-format-value (calc-top 1 'full))
                      "(x + 1) (x - 1) = x*(x - 1) (x + 1)"))
  (calc-pop (calc-stack-size))

  ;; Sub-formula at point: only the factor under point takes the LCM.
  (maf-push "5*(x^2 - 1)")
  (maf-push "x^2 - x")
  (progn (calc-cursor-stack-index 2) (beginning-of-line)
         (search-forward "x^2 -") (backward-char 2))
  (call-interactively 'mafcmd-poly-lcm)
  (cl-assert (string= (math-format-value (calc-top 1 'full))
                      "5 (x + 1) (x - 1) x"))
  (cl-assert (= (calc-stack-size) 1))
  (calc-pop (calc-stack-size))

  ;; Keep-args leaves both operands below the result.
  (maf-push "x^2 - 1")
  (maf-push "x^2 - x")
  (call-interactively 'calc-keep-args)
  (call-interactively 'mafcmd-poly-lcm)
  (cl-assert (= (calc-stack-size) 3))
  (cl-assert (string= (math-format-value (calc-top 1 'full))
                      "(x + 1) (x - 1) x"))
  (cl-assert (string= (math-format-value (calc-top 3 'full)) "x^2 - 1"))
  (calc-pop (calc-stack-size))

  ;; The result commits factored, not distributed: it is a product node.
  (maf-push "6*x + 6")
  (maf-push "4*x + 4")
  (call-interactively 'mafcmd-poly-lcm)
  (cl-assert (eq (car-safe (calc-top 1 'full)) '*))
  (calc-pop (calc-stack-size))

  ;; The real binding, through the keymap.
  (maf-push "x^2 - 1")
  (maf-push "x^2 - x")
  (let* ((buf (get-buffer "*Calculator*"))
         (win (get-buffer-window buf t)))
    (cl-assert win)
    (with-selected-window win
      (with-current-buffer buf
        (execute-kbd-macro (kbd "a L")))))
  (cl-assert (string= (math-format-value (calc-top 1 'full))
                      "(x + 1) (x - 1) x"))
  (cl-assert (= (calc-stack-size) 1))
  (calc-pop (calc-stack-size))

  ;; The selection machinery encases entry atoms in place — preparing
  ;; a selection leaves (cplx 6 0) where 6 was, entirely apart from
  ;; any command — and resolve strips the casing off the top-of-stack
  ;; argument as it does off :expr, so the factoring sees the 6 and
  ;; not an opaque cplx (which cost the content its numeric part:
  ;; 4 (x + 1) 6 where 12 (x + 1) was owed).
  (maf-push "4*(x + 1)")
  (maf-push "6*(x + 1)")
  (progn (calc-prepare-selection 1) nil)
  (progn (calc-cursor-stack-index 0) nil)
  (call-interactively 'mafcmd-poly-lcm)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "12 (x + 1)"))
  (calc-pop (calc-stack-size)))
