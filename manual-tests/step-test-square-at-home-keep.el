(maf-defcmd maf-square (expr arg commit)
  "Square command."
  :arity unary
  :prefix "sqr"
  (commit (calcFunc-mul expr expr)))

(maf-step
  (calc-push 4)
  (call-interactively 'calc-keep-args)
  (call-interactively 'maf-square)
  (cl-assert (= (calc-stack-size) 2))
  (cl-assert (equal (calc-top 1 'full) 16))
  (cl-assert (equal (calc-top 2 'full) 4)))
