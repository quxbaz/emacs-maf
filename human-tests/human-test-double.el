(maf-defcmd maf-double (expr arg commit)
  "Test multiplication function."
  :arity unary
  :prefix "doub"
  (commit (calcFunc-mul expr 2)))

(maf--with-calc-buffer
  (calc-reset 0)
  (maf-debug-slowly
    (calc-push 10)
    (call-interactively 'maf-double)))
