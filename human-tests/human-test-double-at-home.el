(maf-defcmd maf-double (expr arg commit)
  "Doubling command."
  :arity unary
  :prefix "doub"
  (commit (calcFunc-mul expr 2)))

(maf-debug--open-calc-right)

(maf-debug-use-calc-buffer
  (calc-reset 0)
  (maf-debug-slowly 0.3
    (calc-push 10)
    (call-interactively 'maf-double)))
