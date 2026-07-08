(maf-defcmd maf-square (expr arg commit)
  "Square command."
  :arity unary
  :prefix "sqr"
  (commit (calcFunc-mul expr expr)))

(maf-step
  (calc-push '(calcFunc-eq (var x var-x) 5))
  (goto-char 0)
  (call-interactively 'calc-keep-args)
  (call-interactively 'maf-square)
  (cl-assert (= (calc-stack-size) 2))
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "x^2 = 25"))
  (cl-assert (string= (math-format-value (calc-top 2 'full)) "x = 5")))
