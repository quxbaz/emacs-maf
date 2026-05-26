(maf-defcmd maf-double (expr arg commit)
  "Doubling command."
  :arity unary
  :prefix "doub"
  (commit (calcFunc-mul expr 2)))

(maf--debug-setup-test)

(maf--debug-slowly 0.3
  (calc-push 10)
  (call-interactively 'maf-double))
