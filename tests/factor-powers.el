(maf-step
  ;; Basic: difference of squares.
  (maf-push "x^2 - 9")
  (call-interactively 'mafcmd-factor-powers)
  (cl-assert (string= (math-format-value (calc-top 1 'full))
                      "(x + 3) (x - 3)"))
  (calc-pop (calc-stack-size))

  ;; Sum of squares: complex conjugates.
  (maf-push "x^2 + 9")
  (call-interactively 'mafcmd-factor-powers)
  (cl-assert (string= (math-format-value (calc-top 1 'full))
                      "(3 + x i) (3 - x i)"))
  (calc-pop (calc-stack-size))

  ;; Non-square constant: a radical, kept exact.
  (maf-push "x^2 - 5")
  (call-interactively 'mafcmd-factor-powers)
  (cl-assert (string= (math-format-value (calc-top 1 'full))
                      "(x + sqrt(5)) (x - sqrt(5))"))
  (calc-pop (calc-stack-size))

  ;; Difference and sum of cubes.
  (maf-push "x^3 - 8")
  (call-interactively 'mafcmd-factor-powers)
  (cl-assert (string= (math-format-value (calc-top 1 'full))
                      "(x - 2) (x^2 + 2 x + 4)"))
  (maf-push "x^3 + 8")
  (call-interactively 'mafcmd-factor-powers)
  (cl-assert (string= (math-format-value (calc-top 1 'full))
                      "(x + 2) (x^2 - 2 x + 4)"))
  (calc-pop (calc-stack-size))

  ;; Constant-first difference of cubes.
  (maf-push "1 - x^3")
  (call-interactively 'mafcmd-factor-powers)
  (cl-assert (string= (math-format-value (calc-top 1 'full))
                      "(1 - x) (1 + x + x^2)"))
  (calc-pop (calc-stack-size))

  ;; Sixth powers: differences prefer squares, sums prefer cubes.
  (maf-push "x^6 - 64")
  (call-interactively 'mafcmd-factor-powers)
  (cl-assert (string= (math-format-value (calc-top 1 'full))
                      "(x^3 + 8) (x^3 - 8)"))
  (maf-push "x^6 + 64")
  (call-interactively 'mafcmd-factor-powers)
  (cl-assert (string= (math-format-value (calc-top 1 'full))
                      "(x^2 + 4) (x^4 - 4 x^2 + 16)"))
  (calc-pop (calc-stack-size))

  ;; Square coefficients root along with the variable part.
  (maf-push "4 x^2 - 9")
  (call-interactively 'mafcmd-factor-powers)
  (cl-assert (string= (math-format-value (calc-top 1 'full))
                      "(2 x + 3) (2 x - 3)"))
  (calc-pop (calc-stack-size))

  ;; Reversed order: the positive term's root leads.
  (maf-push "9 - x^2")
  (call-interactively 'mafcmd-factor-powers)
  (cl-assert (string= (math-format-value (calc-top 1 'full))
                      "(3 + x) (3 - x)"))
  (calc-pop (calc-stack-size))

  ;; Multi-variable square and a compound base.
  (maf-push "x^2 y^2 - 4")
  (call-interactively 'mafcmd-factor-powers)
  (cl-assert (string= (math-format-value (calc-top 1 'full))
                      "(x y + 2) (x y - 2)"))
  (maf-push "(x + 1)^2 - 9")
  (call-interactively 'mafcmd-factor-powers)
  (cl-assert (string= (math-format-value (calc-top 1 'full))
                      "(x + 4) (x - 2)"))
  (calc-pop (calc-stack-size))

  ;; Quotient terms root by parts.
  (maf-push "x^6/8 - y^3/8")
  (call-interactively 'mafcmd-factor-powers)
  (cl-assert (string= (math-format-value (calc-top 1 'full))
                      "(x^2 / 2 - y / 2) (x^4 / 4 + x^2 y / 4 + y^2 / 4)"))
  (calc-pop (calc-stack-size))

  ;; Radical over an independent parameter is allowed...
  (maf-push "x^2 - y")
  (call-interactively 'mafcmd-factor-powers)
  (cl-assert (string= (math-format-value (calc-top 1 'full))
                      "(x + sqrt(y)) (x - sqrt(y))"))
  (calc-pop (calc-stack-size))

  ;; ...but not over a variable the other term uses, and never as the
  ;; only anchor: linear binomials and trinomials pass through.
  (maf-push "x^2 - x")
  (call-interactively 'mafcmd-factor-powers)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "x^2 - x"))
  (maf-push "x - 9")
  (call-interactively 'mafcmd-factor-powers)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "x - 9"))
  (maf-push "x^2 + 6 x + 9")
  (call-interactively 'mafcmd-factor-powers)
  (cl-assert (string= (math-format-value (calc-top 1 'full))
                      "x^2 + 6 x + 9"))
  (calc-push 42)
  (call-interactively 'mafcmd-factor-powers)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "42"))
  (calc-pop (calc-stack-size))

  ;; Equation: each side factors on its own; a constant side passes.
  (maf-push "x^2 - 9 = y^3 + 8")
  (call-interactively 'mafcmd-factor-powers)
  (cl-assert (string= (math-format-value (calc-top 1 'full))
                      "(x + 3) (x - 3) = (y + 2) (y^2 - 2 y + 4)"))
  (calc-pop (calc-stack-size))

  ;; Subexpr: only the binomial under point factors.
  (maf-push "y (x^2 - 9)")
  (progn (goto-char (point-min)) (search-forward "x^2 -") (backward-char 1))
  (call-interactively 'mafcmd-factor-powers)
  (cl-assert (string= (math-format-value (calc-top 1 'full))
                      "y((x + 3) (x - 3))")))
