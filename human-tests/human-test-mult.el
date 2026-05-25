(maf-defcmd maf-mult (expr arg commit)
  "Test multiplication function."
  :arity binary
  :prefix "mult"
  (commit (calcFunc-mul expr arg)))

(maf-debug--open-calc-right)

(maf--with-calc-buffer
  (calc-reset 0)
  (maf-debug-slowly 0.3
    (calc-push 3)
    (calc-push 2)
    (call-interactively 'maf-mult)))
