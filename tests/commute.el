(maf-step
  ;; Basic: swap the operands of a sum.
  (maf-push "a + b")
  (call-interactively 'mafcmd-commute)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "b + a"))
  (calc-pop (calc-stack-size))

  ;; Product, and no simplification: the numeric coefficient must not
  ;; be distributed through.
  (maf-push "2 (3 + x)")
  (call-interactively 'mafcmd-commute)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "(3 + x) 2"))
  (calc-pop (calc-stack-size))

  ;; Non-commutative operator: swapped structurally, not algebraically.
  (maf-push "a - b")
  (call-interactively 'mafcmd-commute)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "b - a"))
  (calc-pop (calc-stack-size))

  ;; Function call with more than two args: first two swap, the rest
  ;; stay in place (the legacy version dropped them).
  (maf-push "f(a, b, c)")
  (call-interactively 'mafcmd-commute)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "f(b, a, c)"))
  (calc-pop (calc-stack-size))

  ;; Vector: first two elements swap, tail preserved.
  (maf-push "[a, b, c]")
  (call-interactively 'mafcmd-commute)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "[b, a, c]"))
  (calc-pop (calc-stack-size))

  ;; Nothing to swap: atoms and unary calls pass through unchanged.
  (calc-push 42)
  (call-interactively 'mafcmd-commute)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "42"))
  (maf-push "sqrt(x)")
  (call-interactively 'mafcmd-commute)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "sqrt(x)"))
  (calc-pop (calc-stack-size))

  ;; Interval: its first slot is the endpoint mask, not an operand;
  ;; must pass through unchanged (the legacy version corrupted it).
  (maf-push "[1 .. 3]")
  (call-interactively 'mafcmd-commute)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "[1 .. 3]"))
  (calc-pop (calc-stack-size))

  ;; Equation: the two sides swap as a whole (:map -1), not per side.
  (maf-push "x = y + 1")
  (call-interactively 'mafcmd-commute)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "y + 1 = x"))
  (calc-pop (calc-stack-size))

  ;; Subexpr: only the sub-formula under point commutes; point stays put.
  (maf-push "1 + (a + b)")
  (progn (goto-char (point-min)) (search-forward "a +") (backward-char 1))
  (call-interactively 'mafcmd-commute)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "1 + (b + a)"))
  (cl-assert (eq (char-after) ?+)))
