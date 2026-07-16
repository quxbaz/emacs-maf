(maf-step
  ;; Home: floats convert to exact fractions, exact numbers untouched.
  (maf-push "0.75 x + 2")
  (goto-char (point-max))
  (call-interactively 'mafcmd-frac)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "3:4 x + 2"))
  (calc-pop 1)

  ;; A whole number is a noop.
  (maf-push "6")
  (goto-char (point-max))
  (call-interactively 'mafcmd-frac)
  (cl-assert (equal (calc-top 1 'full) 6))
  (calc-pop 1)

  ;; Tolerance prefix arg: 3 significant figures on pi.
  (maf-push "3.14159")
  (goto-char (point-max))
  (let ((current-prefix-arg 3))
    (call-interactively 'mafcmd-frac))
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "22:7"))
  (calc-pop 1)

  ;; Subexpr: only the float under point converts.
  (maf-push "0.75 x + 0.5")
  (progn (goto-char (point-min)) (search-forward "0.75") (backward-char 2))
  (call-interactively 'mafcmd-frac)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "3:4 x + 0.5"))
  (calc-pop 1)

  ;; Equation: each side converts, integers still exact.
  (maf-push "0.25 x = 0.5 y + 3")
  (progn (goto-char (point-min)) (end-of-line))
  (call-interactively 'mafcmd-frac)
  (cl-assert (string= (math-format-value (calc-top 1 'full))
                      "1:4 x = 1:2 y + 3"))
  (calc-pop 1)

  ;; The I flag routes back to mafcmd-float.
  (maf-push "3:4")
  (goto-char (point-max))
  (call-interactively 'calc-inverse)
  (call-interactively 'mafcmd-frac)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "0.75"))
  (calc-pop 1))
