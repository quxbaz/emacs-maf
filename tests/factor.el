;; mafcmd-factor is unary: the seed table lists calcFunc-factor with two
;; arguments, but the second is an optional variable, not an operand.
;; Declared binary it demanded a stack-top argument and died with "Too
;; few elements on stack" on a lone expression.
(maf-step
  ;; a f factors the one resolved expression; no second operand.
  (maf-push "12 y^2 - 19 y + 4")
  (call-interactively 'mafcmd-factor)
  (cl-assert (string= (math-format-value (calc-top 1 'full))
                      "(3 y - 4) (4 y - 1)"))
  (calc-pop 1)

  ;; H a f is factors, also unary: the factor/multiplicity table.
  (maf-push "12 y^2 - 19 y + 4")
  (call-interactively 'calc-hyperbolic)
  (call-interactively 'mafcmd-factor)
  (cl-assert (equal (calc-top 1 'full)
                    (math-read-expr "[[4 y - 1, 1], [3 y - 4, 1]]")))
  (calc-pop 1)

  ;; An equation maps per side, like the other algebra commands.
  (maf-push "12 y^2 - 19 y + 4 = 4 x^2 - 9")
  (call-interactively 'mafcmd-factor)
  (cl-assert (string= (math-format-value (calc-top 1 'full))
                      "(3 y - 4) (4 y - 1) = (2 x + 3) (2 x - 3)"))
  (calc-pop 1))
