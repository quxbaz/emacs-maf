(maf-defcmd maf-sqrt (expr arg commit)
  "Square-root command."
  :arity unary
  :prefix "sqrt"
  (commit (calcFunc-sqrt expr)))

(maf--debug-setup-test)

(maf--debug-step
  (calc-push '(+ (var a var-a) 16))
  (progn (goto-char (point-min)) (search-forward "16") (backward-char 2))
  (call-interactively 'maf-sqrt)
  (cl-assert (= (calc-stack-size) 1))
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "a + 4")))
