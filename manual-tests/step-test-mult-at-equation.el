(maf-defcmd maf-mult (expr arg commit)
  "Multiplication command."
  :arity binary
  :prefix "mult"
  (commit (calcFunc-mul expr arg)))

(maf-step
  (calc-push '(calcFunc-eq (var x var-x) 5))
  (calc-push 2)
  (calc-cursor-stack-index 2)
  (call-interactively 'maf-mult)
  (cl-assert (= (calc-stack-size) 1))
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "2 x = 10")))
