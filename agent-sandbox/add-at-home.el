(maf-defcmd maf-add (expr arg commit)
  "Addition command."
  :arity binary
  :prefix "add"
  (commit (calcFunc-add expr arg)))

(maf-step
  (calc-push 3)
  (calc-push 4)
  (call-interactively 'maf-add)
  (cl-assert (= (calc-stack-size) 1))
  (cl-assert (equal (calc-top 1 'full) 7)))
