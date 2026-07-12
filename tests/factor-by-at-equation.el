(maf-step
  (calc-push (math-read-expr "6 x + 12 = 18 y + 6"))
  (calc-push 6)
  (calc-cursor-stack-index 2)
  (call-interactively 'mafcmd-factor-by)
  (cl-assert (= (calc-stack-size) 1))
  ;; Each side factored by 6; the shared arg is consumed once.
  (cl-assert (string= (math-format-value (calc-top 1 'full))
                      "6 (x + 2) = 6 (3 y + 1)")))
