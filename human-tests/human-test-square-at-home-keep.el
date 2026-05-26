(maf-defcmd maf-square (expr arg commit)
  "Square command."
  :arity unary
  :prefix "sqr"
  (commit (calcFunc-mul expr expr)))

(maf--debug-setup-test)

(maf--debug-slowly 0.3
  (progn
    (calc-push 4)
    (call-interactively 'calc-keep-args))
  (call-interactively 'maf-square))
