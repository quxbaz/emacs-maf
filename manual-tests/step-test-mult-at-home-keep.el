(maf-defcmd maf-mult (expr arg commit)
  "Multiplication command."
  :arity binary
  :prefix "mult"
  (commit (calcFunc-mul expr arg)))

(maf--debug-setup-test)

(maf--debug-step
  (calc-push 3)
  (calc-push 2)
  (call-interactively 'calc-keep-args)
  (call-interactively 'maf-mult)
  (cl-assert (= (calc-stack-size) 3))
  (cl-assert (equal (calc-top 1 'full) 6))
  (cl-assert (equal (calc-top 2 'full) 2))
  (cl-assert (equal (calc-top 3 'full) 3)))
