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
  (calc-pop (calc-stack-size))

  ;; --- More complex expressions ---

  ;; A constant factor is stripped; only the variable roots remain.
  (maf-push "3*x^2 - 12")
  (goto-char (point-max)) (call-interactively 'mafcmd-poly-roots)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "[-2, 2]"))
  (calc-pop (calc-stack-size))

  ;; Negative leading term / terms in reversed order still resolve.
  (maf-push "4 - x^2")
  (goto-char (point-max)) (call-interactively 'mafcmd-poly-roots)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "[-2, 2]"))
  (calc-pop (calc-stack-size))

  ;; Mixed multiplicities in product form each repeat their root.
  (maf-push "(x - 2)^2 * (x + 1)^3")
  (goto-char (point-max)) (call-interactively 'mafcmd-poly-roots)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "[-1, -1, -1, 2, 2]"))
  (calc-pop (calc-stack-size))

  ;; --- Equation and relation forms ---

  ;; An equation with a nonzero right side reduces to the difference.
  (maf-push "x^2 = 4")
  (goto-char (point-max)) (call-interactively 'mafcmd-poly-roots)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "[-2, 2]"))
  (calc-pop (calc-stack-size))

  ;; Both sides polynomial: the difference is what gets its roots.
  (maf-push "x^2 = x + 2")
  (goto-char (point-max)) (call-interactively 'mafcmd-poly-roots)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "[-1, 2]"))
  (calc-pop (calc-stack-size))

  ;; The remaining inequality flavors reduce to the boundary too.
  (maf-push "x^2 - 4 >= 0")
  (goto-char (point-max)) (call-interactively 'mafcmd-poly-roots)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "[-2, 2]"))
  (calc-pop (calc-stack-size))

  (maf-push "x^2 - 4 > 0")
  (goto-char (point-max)) (call-interactively 'mafcmd-poly-roots)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "[-2, 2]"))
  (calc-pop (calc-stack-size))

  ;; --- Variable selection ---

  ;; With no x present, the next priority variable (y) is used.
  (maf-push "y^2 - 9")
  (goto-char (point-max)) (call-interactively 'mafcmd-poly-roots)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "[-3, 3]"))
  (calc-pop (calc-stack-size))

  ;; A non-priority variable is chosen alphabetically.
  (maf-push "a^2 - 4")
  (goto-char (point-max)) (call-interactively 'mafcmd-poly-roots)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "[-2, 2]"))
  (calc-pop (calc-stack-size))

  ;; --- Respects the ambient calc modes ---

  ;; Unlike auto-solve, poly-roots does not force symbolic/frac: a
  ;; fractional root comes out as a float under the default modes.
  (maf-push "2*x - 1")
  (goto-char (point-max)) (call-interactively 'mafcmd-poly-roots)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "[0.5]"))
  (calc-pop (calc-stack-size))

  ;; With prefer-frac on, the same root stays exact.
  (let ((calc-prefer-frac t))
    (maf-push "2*x - 1")
    (goto-char (point-max)) (call-interactively 'mafcmd-poly-roots)
    (cl-assert (string= (math-format-value (calc-top 1 'full)) "[1:2]"))
    (calc-pop (calc-stack-size)))

  ;; With symbolic mode on, an irrational root stays symbolic.
  (let ((calc-symbolic-mode t))
    (maf-push "x^2 - 2")
    (goto-char (point-max)) (call-interactively 'mafcmd-poly-roots)
    (cl-assert (string= (math-format-value (calc-top 1 'full)) "[sqrt(2), -sqrt(2)]"))
    (calc-pop (calc-stack-size)))

  ;; Complex roots are returned when there are no real ones.
  (maf-push "x^2 + 1")
  (goto-char (point-max)) (call-interactively 'mafcmd-poly-roots)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "[(0, 1), (0, -1)]"))
  (calc-pop (calc-stack-size))

  ;; --- Stack position ---

  ;; Point on a lower entry finds that entry's roots, top left intact.
  (maf-push "x^2 - 9")       ; lands at index 2 after the next push
  (maf-push "777")           ; the top decoy (index 1)
  (progn (calc-cursor-stack-index 2) (beginning-of-line)
         (goto-char (line-end-position)))
  (call-interactively 'mafcmd-poly-roots)
  (cl-assert (string= (math-format-value (calc-top 2 'full)) "[-3, 3]"))
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "777"))
  (calc-pop (calc-stack-size)))
