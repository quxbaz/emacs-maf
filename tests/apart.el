(maf-step
  ;; Basic: a proper rational function splits into partial fractions.
  (maf-push "1 / (x^2 - 1)")
  (call-interactively 'mafcmd-apart)
  (cl-assert (string= (math-format-value (calc-top 1 'full))
                      "1:2 / (x - 1) - 1:2 / (x + 1)"))
  (calc-pop (calc-stack-size))

  ;; Improper: the polynomial quotient splits off before the fractions.
  (maf-push "(x^2 + 2) / (x + 1)")
  (call-interactively 'mafcmd-apart)
  (cl-assert (string= (math-format-value (calc-top 1 'full))
                      "x - 1 + 3 / (x + 1)"))
  (calc-pop (calc-stack-size))

  ;; Nothing to split: polynomials and non-rational functions pass
  ;; through unchanged instead of erroring (matters for equation sides).
  (maf-push "6 x + 12")
  (call-interactively 'mafcmd-apart)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "6 x + 12"))
  (maf-push "sin(x)")
  (call-interactively 'mafcmd-apart)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "sin(x)"))
  (calc-pop (calc-stack-size))

  ;; Sum: apart distributes over top-level +/-, so non-rational terms
  ;; ride along while the rational term still splits.
  (maf-push "1 / (x^2 - 1) + sin(x)")
  (call-interactively 'mafcmd-apart)
  (cl-assert (string= (math-format-value (calc-top 1 'full))
                      "1:2 / (x - 1) - 1:2 / (x + 1) + sin(x)"))
  (calc-pop (calc-stack-size))

  ;; Equation: each side splits independently, in its own variable.
  (maf-push "1 / (x^2 - 1) = 1 / (y^2 - 4)")
  (call-interactively 'mafcmd-apart)
  (cl-assert (string= (math-format-value (calc-top 1 'full))
                      "1:2 / (x - 1) - 1:2 / (x + 1) = 1:4 / (y - 2) - 1:4 / (y + 2)"))
  (calc-pop (calc-stack-size))

  ;; Subexpr: only the quotient under point splits; the rest of the
  ;; entry is untouched.
  (maf-push "1 / (x^2 - 1) + sin(x)")
  (calc-push 9)
  (progn (goto-char (point-min)) (search-forward "1 /") (backward-char 1))
  (call-interactively 'mafcmd-apart)
  (cl-assert (string= (math-format-value (calc-top 2 'full))
                      "1:2 / (x - 1) - 1:2 / (x + 1) + sin(x)"))
  (cl-assert (= (calc-stack-size) 2))
  (calc-pop (calc-stack-size))

  ;; Keep-args: the original entry stays below the result.
  (maf-push "1 / (x^2 - 1)")
  (call-interactively 'calc-keep-args)
  (call-interactively 'mafcmd-apart)
  (cl-assert (= (calc-stack-size) 2))
  (cl-assert (string= (math-format-value (calc-top 1 'full))
                      "1:2 / (x - 1) - 1:2 / (x + 1)"))
  (cl-assert (string= (math-format-value (calc-top 2 'full))
                      "1 / (x^2 - 1)")))
