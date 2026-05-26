(maf-defcmd maf-mult (expr arg commit)
  "Multiplication command."
  :arity binary
  :prefix "mult"
  (commit (calcFunc-mul expr arg)))

(maf--debug-setup-test)

(maf--debug-slowly 0.3
  (calc-push 3)
  (progn
    (calc-push 2)
    (calc-refresh)
    (call-interactively 'calc-keep-args))
  (call-interactively 'maf-mult))
