(maf-defcmd maf-mult (expr arg commit)
  "Multiplication command."
  :arity binary
  :prefix "mult"
  (commit (calcFunc-mul expr arg)))

(maf-step
  (calc-push '(+ (* 20 (var x var-x)) 10))
  (calc-push 2)
  (goto-char 7)
  (call-interactively 'calc-select-here)
  (call-interactively 'maf-mult)
  (calc-clear-selections)
  (cl-assert (= (calc-stack-size) 1)))
