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


  ;; --- Hardening and interaction boundaries ---

  ;; Exercise the actual maf-mode binding, not just the command symbol.
  (maf-push "x^2 - 25")
  (let* ((buf (get-buffer "*Calculator*"))
         (win (get-buffer-window buf t)))
    (cl-assert win)
    (with-selected-window win
      (with-current-buffer buf
        (execute-kbd-macro (kbd "M-r")))))
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "[-5, 5]"))
  (calc-pop (calc-stack-size))

  ;; Entry scope ignores an explicit Calc selection and clears it instead
  ;; of splicing the roots into the selected x.
  (maf-push "x^2 - 4")
  (progn (calc-cursor-stack-index 1) (beginning-of-line)
         (search-forward "x") (backward-char 1)
         (call-interactively 'calc-select-here))
  (cl-assert (nth 2 (calc-top 1 'entry)))
  (let* ((buf (get-buffer "*Calculator*"))
         (win (get-buffer-window buf t)))
    (cl-assert win)
    (with-selected-window win
      (with-current-buffer buf
        (execute-kbd-macro (kbd "M-r")))))
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "[-2, 2]"))
  (cl-assert (null (nth 2 (calc-top 1 'entry))))
  (cl-assert (null calc-any-selections))
  (calc-pop (calc-stack-size))

  ;; Keep-args leaves the original below the result.
  (maf-push "x^2 - 4")
  (call-interactively 'calc-keep-args)
  (call-interactively 'mafcmd-poly-roots)
  (cl-assert (= (calc-stack-size) 2))
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "[-2, 2]"))
  (cl-assert (string= (math-format-value (calc-top 2 'full)) "x^2 - 4"))
  (calc-pop (calc-stack-size))

  ;; Zero is a root, including repeated zero roots.
  (maf-push "x")
  (goto-char (point-max)) (call-interactively 'mafcmd-poly-roots)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "[0]"))
  (calc-pop (calc-stack-size))

  (maf-push "x^3 * (x - 2)")
  (goto-char (point-max)) (call-interactively 'mafcmd-poly-roots)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "[2, 0, 0, 0]"))
  (calc-pop (calc-stack-size))

  ;; Calc reports unsolved symbolic roots as an unevaluated roots(...) form.
  ;; Preserve the original rather than returning [] or a partial vector.
  (let ((calc-symbolic-mode t))
    (maf-push "x^6 + x + 1")
    (goto-char (point-max)) (call-interactively 'mafcmd-poly-roots)
    (cl-assert (string= (math-format-value (calc-top 1 'full)) "x^6 + x + 1"))
    (calc-pop (calc-stack-size)))

  (let ((calc-symbolic-mode t))
    (maf-push "(x - 1) * (x^6 + x + 1)")
    (goto-char (point-max)) (call-interactively 'mafcmd-poly-roots)
    (cl-assert (string= (math-format-value (calc-top 1 'full))
                        "(x - 1) (x^6 + x + 1)"))
    (calc-pop (calc-stack-size)))

  ;; With symbolic mode off, the same degree-six polynomial is solved
  ;; numerically and yields all six roots.
  (maf-push "x^6 + x + 1")
  (goto-char (point-max)) (call-interactively 'mafcmd-poly-roots)
  (cl-assert (eq (car-safe (calc-top 1 'full)) 'vec))
  (cl-assert (= (length (calc-top 1 'full)) 7))
  (calc-pop (calc-stack-size))

  ;; A factor independent of the chosen variable is not a failed factor.
  (maf-push "(x - 1) * (y - 2)")
  (goto-char (point-max)) (call-interactively 'mafcmd-poly-roots)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "[1]"))
  (calc-pop (calc-stack-size))

  ;; Built-in function equations use the boundary, not the RHS alone.
  (maf-push "sin(x) = 0")
  (goto-char (point-max)) (call-interactively 'mafcmd-poly-roots)
  (cl-assert (eq (car-safe (calc-top 1 'full)) 'vec))
  (cl-assert (= (length (calc-top 1 'full)) 2))
  (calc-pop (calc-stack-size))

  ;; Only equality can declare an unknown function.  An unknown-function
  ;; inequality is treated as a boundary and, when unsolved, left intact.
  (maf-push "f(x) < x^2 - 4")
  (goto-char (point-max)) (call-interactively 'mafcmd-poly-roots)
  (cl-assert (string= (math-format-value (calc-top 1 'full))
                      "f(x) < x^2 - 4"))
  (calc-pop (calc-stack-size))

  ;; An atomic left side is a normal boundary relation, not a function
  ;; declaration, and must not be passed to `length' as a sequence.
  (maf-push "0 = x^2 - 4")
  (goto-char (point-max)) (call-interactively 'mafcmd-poly-roots)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "[-2, 2]"))
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
  (calc-pop (calc-stack-size))

  ;; The same entry-scope guarantee holds for a selected lower entry.
  (maf-push "x^2 - 16")
  (maf-push "888")
  (progn (calc-cursor-stack-index 2) (beginning-of-line)
         (search-forward "x") (backward-char 1)
         (call-interactively 'calc-select-here))
  (cl-assert (nth 2 (calc-top 2 'entry)))
  (call-interactively 'mafcmd-poly-roots)
  (cl-assert (string= (math-format-value (calc-top 2 'full)) "[-4, 4]"))
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "888"))
  (cl-assert (null (nth 2 (calc-top 2 'entry))))
  (cl-assert (null calc-any-selections))
  (calc-pop (calc-stack-size)))
