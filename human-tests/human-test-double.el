(maf-defcmd maf-mult (expr arg commit)
  "Test multiplication function."
  :arity binary
  :prefix "mult"
  ;; :simp t
  ;; :map t
  (commit (calcFunc-mul expr arg)))

(maf--with-calc-buffer
  (calc-reset 0)
  (maf-debug-slowly
    (calc-push 3)
    (calc-push 2)
    (call-interactively 'maf-mult)))
