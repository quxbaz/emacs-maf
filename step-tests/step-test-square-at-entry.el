(maf-defcmd maf-square (expr arg commit)
  "Square command."
  :arity unary
  :prefix "sqr"
  (commit (calcFunc-mul expr expr)))

(maf-step
  (calc-push '(+ (* 8 (var x var-x)) 4))
  (calc-push '(var x var-x))
  (goto-char 0)
  (call-interactively 'maf-square)
  (cl-assert (= (calc-stack-size) 2))
  (cl-assert (string= (math-format-value (calc-top 2 'full)) "(8 x + 4)^2")))
