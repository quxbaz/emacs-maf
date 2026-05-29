(maf-defcmd maf-square (expr arg commit)
  "Square command."
  :arity unary
  :prefix "sqr"
  (commit (calcFunc-mul expr expr)))

(maf--debug-setup-test)

(maf--debug-step
  (calc-push '(+ (* 10 (var x var-x)) 4))
  (calc-push '(var c var-c))
  (goto-char 7)
  (call-interactively 'calc-select-here)
  (call-interactively 'maf-square)
  (calc-clear-selections)
  (cl-assert (= (calc-stack-size) 2)))
