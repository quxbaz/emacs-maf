(maf-defcmd maf-mult (expr arg commit)
  "Multiplication command."
  :arity binary
  :prefix "mult"
  (commit (calcFunc-mul expr arg)))

(maf-debug-open-calc-right)
(maf-debug-use-calc-buffer)
(calc-reset 0)

(maf-debug-slowly 0.3
  (calc-push '(+ (* 20 (var x var-x)) 10))
  (progn
    (calc-push 2)
    (calc-refresh))
  (calc-refresh)
  (goto-char 7)
  (call-interactively 'calc-select-here)
  ;; @NOW
  (call-interactively 'maf-mult)
  )
