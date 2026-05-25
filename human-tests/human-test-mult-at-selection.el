(maf-defcmd maf-mult (expr arg commit)
  "Multiplication command."
  :arity binary
  :prefix "mult"
  (commit (calcFunc-mul expr arg)))

(maf-debug--open-calc-right)

(maf-debug-use-calc-buffer
  (calc-reset 0)
  (maf-debug-slowly 0.3
    (calc-push '(+ (* 20 (var x var-x)) 10))
    (calc-push 2)
    (calc-refresh)
    (goto-char 7)
    ;; (call-interactively 'maf-mult)
    ))
