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

(defun test-double ()
  (maf-defcmd maf-double (expr arg commit)
    "Test multiplication function."
    :arity unary
    :prefix "double"
    (commit (calcFunc-mul expr 2)))

  (other-window 1) (my/calc-direct)

  (maf--with-calc-buffer
    (calc-reset 0)
    ;; (calc-push '(var x var-x))
    (calc-push 3)
    (call-interactively 'maf-double)))

(test-mult)
