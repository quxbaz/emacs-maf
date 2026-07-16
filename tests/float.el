(maf-step
  ;; Home: fractions float, integers stay exact.
  (maf-push "6 x + 8:3")
  (goto-char (point-max))
  (call-interactively 'mafcmd-float)
  (cl-assert (string= (math-format-value (calc-top 1 'full))
                      "6 x + 2.66666666667"))
  (calc-pop 1)

  ;; A whole number is a noop.
  (maf-push "6")
  (goto-char (point-max))
  (call-interactively 'mafcmd-float)
  (cl-assert (equal (calc-top 1 'full) 6))
  (calc-pop 1)

  ;; Subexpr: only the fraction under point floats.
  (maf-push "3:4 x + 1:2")
  (progn (goto-char (point-min)) (search-forward "3:4") (backward-char 2))
  (call-interactively 'mafcmd-float)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "0.75 x + 1:2"))
  (calc-pop 1)

  ;; Equation: each side floats, integers still exact.
  (maf-push "1:4 x = 3:8 y + 2")
  (progn (goto-char (point-min)) (end-of-line))
  (call-interactively 'mafcmd-float)
  (cl-assert (string= (math-format-value (calc-top 1 'full))
                      "0.25 x = 0.375 y + 2"))
  (calc-pop 1)

  ;; H flag routes to mafcmd-float-all, which floats everything.
  (maf-push "6 x + 8:3")
  (goto-char (point-max))
  (call-interactively 'calc-hyperbolic)
  (call-interactively 'mafcmd-float)
  (cl-assert (string= (math-format-value (calc-top 1 'full))
                      "6. x + 2.66666666667"))
  (calc-pop 1)

  ;; And back: the I flag routes to mafcmd-frac.
  (maf-push "0.75")
  (goto-char (point-max))
  (call-interactively 'calc-inverse)
  (call-interactively 'mafcmd-float)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "3:4"))
  (calc-pop 1))
