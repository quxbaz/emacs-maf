(maf-step
  ;; Each pair toggles both ways: + <-> -.
  (maf-push "a + b")
  (call-interactively 'mafcmd-toggle-op)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "a - b"))
  (call-interactively 'mafcmd-toggle-op)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "a + b"))
  (calc-pop (calc-stack-size))

  ;; * <-> /.
  (maf-push "a * b")
  (call-interactively 'mafcmd-toggle-op)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "a / b"))
  (call-interactively 'mafcmd-toggle-op)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "a b"))
  (calc-pop (calc-stack-size))

  ;; ln <-> exp.
  (maf-push "ln(x)")
  (call-interactively 'mafcmd-toggle-op)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "exp(x)"))
  (call-interactively 'mafcmd-toggle-op)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "ln(x)"))
  (calc-pop (calc-stack-size))

  ;; log <-> ^; operands stay in place, so log(a, b) gives a^b.
  (maf-push "log(a, b)")
  (call-interactively 'mafcmd-toggle-op)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "a^b"))
  (call-interactively 'mafcmd-toggle-op)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "log(a, b)"))
  (calc-pop (calc-stack-size))

  ;; Structural swap only: numeric operands must not evaluate.
  (maf-push "2 + 3")
  (call-interactively 'mafcmd-toggle-op)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "2 - 3"))
  (calc-pop (calc-stack-size))

  ;; Nothing to toggle: atoms and a base-less log pass through unchanged.
  (maf-push "x")
  (call-interactively 'mafcmd-toggle-op)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "x"))
  (maf-push "log(x)")
  (call-interactively 'mafcmd-toggle-op)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "log(x)"))
  (calc-pop (calc-stack-size))

  ;; Relations flip whole (:map -1), both sides untouched.
  (maf-push "2 x - 3 < 7")
  (call-interactively 'mafcmd-toggle-op)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "2 x - 3 > 7"))
  (call-interactively 'mafcmd-toggle-op)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "2 x - 3 < 7"))
  (maf-push "a <= b")
  (call-interactively 'mafcmd-toggle-op)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "a >= b"))
  (maf-push "x = y + 1")
  (call-interactively 'mafcmd-toggle-op)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "x != y + 1"))
  (calc-pop (calc-stack-size))

  ;; Trig toggles to its inverse and back; sec has no upstream inverse.
  (maf-push "sin(x)")
  (call-interactively 'mafcmd-toggle-op)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "arcsin(x)"))
  (call-interactively 'mafcmd-toggle-op)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "sin(x)"))
  (maf-push "tanh(x)")
  (call-interactively 'mafcmd-toggle-op)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "arctanh(x)"))
  (maf-push "sec(x)")
  (call-interactively 'mafcmd-toggle-op)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "sec(x)"))
  (calc-pop (calc-stack-size))

  ;; Subexpr: only the operator node under point toggles.
  (maf-push "q1 + q2 / q3")
  (progn (goto-char (point-min)) (search-forward "q2 /") (backward-char 1))
  (call-interactively 'mafcmd-toggle-op)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "q1 + q2 q3"))
  (cl-assert (= (calc-stack-size) 1)))
