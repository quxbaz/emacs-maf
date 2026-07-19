(maf-step
  ;; Basic: monic quadratic, no constant term.
  (maf-push "x^2 + 6 x")
  (call-interactively 'mafcmd-complete-square)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "(x + 3)^2 - 9"))
  (calc-pop (calc-stack-size))

  ;; Leading coefficient and constant term; exact fractions, no floats.
  (maf-push "2 x^2 + 6 x + 1")
  (call-interactively 'mafcmd-complete-square)
  (cl-assert (string= (math-format-value (calc-top 1 'full))
                      "2 (x + 3:2)^2 - 7:2"))
  (calc-pop (calc-stack-size))

  ;; Fully symbolic coefficients.
  (maf-push "a x^2 + b x + c")
  (call-interactively 'mafcmd-complete-square)
  (cl-assert (string= (math-format-value (calc-top 1 'full))
                      "a*(x + b / (2 a))^2 + c - b^2 / (4 a)"))
  (calc-pop (calc-stack-size))

  ;; Negative leading coefficient.
  (maf-push "-x^2 + 6 x")
  (call-interactively 'mafcmd-complete-square)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "9 - (x - 3)^2"))
  (calc-pop (calc-stack-size))

  ;; Perfect square: the residual constant vanishes.
  (maf-push "x^2 + 6 x + 9")
  (call-interactively 'mafcmd-complete-square)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "(x + 3)^2"))
  (calc-pop (calc-stack-size))

  ;; Compound base: quadratic in sin(y), not in a bare variable.
  (maf-push "sin(y)^2 + 2 sin(y)")
  (call-interactively 'mafcmd-complete-square)
  (cl-assert (string= (math-format-value (calc-top 1 'full))
                      "(sin(y) + 1)^2 - 1"))
  (calc-pop (calc-stack-size))

  ;; Float coefficients stay floats.
  (maf-push "0.5 x^2 + 3 x")
  (call-interactively 'mafcmd-complete-square)
  (cl-assert (string= (math-format-value (calc-top 1 'full))
                      "0.5 (x + 3.)^2 - 4.5"))
  (calc-pop (calc-stack-size))

  ;; Fractional leading coefficient entered as a quotient.
  (maf-push "x^2/2 + 3 x")
  (call-interactively 'mafcmd-complete-square)
  (cl-assert (string= (math-format-value (calc-top 1 'full))
                      "1:2 (x + 3)^2 - 9:2"))
  (calc-pop (calc-stack-size))

  ;; Multivariate: completes in the leftmost quadratic base, y^2 rides
  ;; along in the constant.
  (maf-push "x^2 + y^2 + 2 x")
  (call-interactively 'mafcmd-complete-square)
  (cl-assert (string= (math-format-value (calc-top 1 'full))
                      "(x + 1)^2 + y^2 - 1"))
  (calc-pop (calc-stack-size))

  ;; Not a quadratic: cubic, reciprocal, and atom all pass through.
  (maf-push "x^3 + x^2")
  (call-interactively 'mafcmd-complete-square)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "x^3 + x^2"))
  (maf-push "x^2 + 1/x")
  (call-interactively 'mafcmd-complete-square)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "x^2 + 1 / x"))
  (calc-push 42)
  (call-interactively 'mafcmd-complete-square)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "42"))
  (calc-pop (calc-stack-size))

  ;; Equation: each side maps on its own; the constant side passes
  ;; through quietly.
  (maf-push "x^2 + 6 x = 10")
  (call-interactively 'mafcmd-complete-square)
  (cl-assert (string= (math-format-value (calc-top 1 'full))
                      "(x + 3)^2 - 9 = 10"))
  (calc-pop (calc-stack-size))

  ;; Equation with a quadratic on each side, each in its own base.
  (maf-push "x^2 + 6 x = y^2 + 4 y")
  (call-interactively 'mafcmd-complete-square)
  (cl-assert (string= (math-format-value (calc-top 1 'full))
                      "(x + 3)^2 - 9 = (y + 2)^2 - 4"))
  (calc-pop (calc-stack-size))

  ;; Subexpr: only the sum under point completes; the wrapper stays.
  (maf-push "y (x^2 + 6 x)")
  (progn (goto-char (point-min)) (search-forward "x^2 +") (backward-char 1))
  (call-interactively 'mafcmd-complete-square)
  (cl-assert (string= (math-format-value (calc-top 1 'full))
                      "y((x + 3)^2 - 9)")))
