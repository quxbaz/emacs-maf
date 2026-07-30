(maf-step
  ;; Exp-of-log composition at home.
  (maf-push "b^log(x, b)")
  (call-interactively 'mafcmd-log-exp)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "x"))
  (calc-pop (calc-stack-size))

  ;; Scaled exponent: the general p*log collapse.
  (maf-push "e^(2 ln(x))")
  (call-interactively 'mafcmd-log-exp)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "x^2"))
  (calc-pop (calc-stack-size))

  ;; Log-of-exp composition.
  (maf-push "log(b^x, b)")
  (call-interactively 'mafcmd-log-exp)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "x"))
  (calc-pop (calc-stack-size))

  ;; Negated exponent.
  (maf-push "10^(-log10(x))")
  (call-interactively 'mafcmd-log-exp)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "1 / x"))
  (calc-pop (calc-stack-size))

  ;; Power rule.
  (maf-push "ln(x^3)")
  (call-interactively 'mafcmd-log-exp)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "3 ln(x)"))
  (calc-pop (calc-stack-size))

  ;; Only rule sites change: the unsimplified sum survives.
  (maf-push "1 + 2 + ln(x^3)")
  (call-interactively 'mafcmd-log-exp)
  (cl-assert (string= (math-format-value (calc-top 1 'full))
                      "1 + 2 + 3 ln(x)"))
  (calc-pop (calc-stack-size))

  ;; Base mismatch: unchanged.
  (maf-push "2^ln(x)")
  (call-interactively 'mafcmd-log-exp)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "2^ln(x)"))
  (calc-pop (calc-stack-size))

  ;; Nested tower collapses to a fixpoint.
  (maf-push "e^ln(e^ln(x))")
  (call-interactively 'mafcmd-log-exp)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "x"))
  (calc-pop (calc-stack-size))

  ;; Sub-formula at point: only the pow node under point rewrites.
  (maf-push "y + e^ln(x)")
  (progn (calc-cursor-stack-index 1)
         (search-forward "e^" (line-end-position))
         (backward-char 1)
         (call-interactively 'mafcmd-log-exp))
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "y + x"))
  (calc-pop (calc-stack-size))

  ;; Equation: each side rewrites independently.
  (maf-push "ln(x^2) = e^ln(y)")
  (progn (calc-cursor-stack-index 1) (end-of-line)
         (call-interactively 'mafcmd-log-exp))
  (cl-assert (string= (math-format-value (calc-top 1 'full))
                      "2 ln(x) = y"))
  (calc-pop (calc-stack-size)))
