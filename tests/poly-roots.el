(maf-step
  ;; Expression forms.
  (maf-push "x^3 - x^2 - 4*x + 4")
  (goto-char (point-max)) (call-interactively 'mafcmd-poly-roots)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "[-2, 1, 2]"))
  (calc-pop (calc-stack-size))

  (maf-push "x^2 - 4")
  (goto-char (point-max)) (call-interactively 'mafcmd-poly-roots)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "[-2, 2]"))
  (calc-pop (calc-stack-size))

  (maf-push "x - 3")
  (goto-char (point-max)) (call-interactively 'mafcmd-poly-roots)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "[3]"))
  (calc-pop (calc-stack-size))

  ;; Equation forms: f(x) = 0 reduces to the difference of sides.
  (maf-push "x^2 - 4 = 0")
  (goto-char (point-max)) (call-interactively 'mafcmd-poly-roots)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "[-2, 2]"))
  (calc-pop (calc-stack-size))

  ;; Factored input already in product form.
  (maf-push "(x + 2) * (x - 1) * (x - 2)")
  (goto-char (point-max)) (call-interactively 'mafcmd-poly-roots)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "[-2, 1, 2]"))
  (calc-pop (calc-stack-size))

  ;; Multiplicity is kept: a repeated factor repeats its root.
  (maf-push "(x - 2)^2")
  (goto-char (point-max)) (call-interactively 'mafcmd-poly-roots)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "[2, 2]"))
  (calc-pop (calc-stack-size))

  (maf-push "(x - 1)^3")
  (goto-char (point-max)) (call-interactively 'mafcmd-poly-roots)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "[1, 1, 1]"))
  (calc-pop (calc-stack-size))

  (maf-push "(x - 1)^2 * (x + 2)")
  (goto-char (point-max)) (call-interactively 'mafcmd-poly-roots)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "[-2, 1, 1]"))
  (calc-pop (calc-stack-size))

  ;; Multiplicity is recovered even from an expanded polynomial.
  (maf-push "x^3 - 3*x^2 + 3*x - 1")
  (goto-char (point-max)) (call-interactively 'mafcmd-poly-roots)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "[1, 1, 1]"))
  (calc-pop (calc-stack-size))

  ;; A function definition f(x) = g uses the right-hand side.
  (maf-push "f(x) = x^2 - 4")
  (goto-char (point-max)) (call-interactively 'mafcmd-poly-roots)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "[-2, 2]"))
  (calc-pop (calc-stack-size))

  ;; A relation gives the roots of its boundary — inequalities and !=
  ;; reduce to the difference of sides, just like =.
  (maf-push "x^2 - 4 < 0")
  (goto-char (point-max)) (call-interactively 'mafcmd-poly-roots)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "[-2, 2]"))
  (calc-pop (calc-stack-size))

  (maf-push "x^2 - 4 != 0")
  (goto-char (point-max)) (call-interactively 'mafcmd-poly-roots)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "[-2, 2]"))
  (calc-pop (calc-stack-size))

  ;; Whole-entry scope: point inside the formula (on the x) still finds
  ;; the roots of the whole polynomial, not the sub-formula under point.
  (maf-push "x^2 - 4")
  (progn (calc-cursor-stack-index 1) (beginning-of-line)
         (search-forward "x") (backward-char 1))
  (call-interactively 'mafcmd-poly-roots)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "[-2, 2]"))
  (calc-pop (calc-stack-size))

  ;; No variable: the entry is left unchanged.
  (maf-push "42")
  (goto-char (point-max)) (call-interactively 'mafcmd-poly-roots)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "42"))
  (calc-pop (calc-stack-size)))
