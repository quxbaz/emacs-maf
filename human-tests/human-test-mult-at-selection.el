(maf-defcmd maf-mult (expr arg commit)
  "Multiplication command."
  :arity binary
  :prefix "mult"
  (commit (calcFunc-mul expr arg)))

(maf--debug-setup-test)

(maf--debug-slowly 0.3
  (calc-push '(+ (* 20 (var x var-x)) 10))
  (progn
    (calc-push 2)
    (calc-refresh))
  (goto-char 7)
  (call-interactively 'calc-select-here)
  (call-interactively 'maf-mult)
  (calc-clear-selections))
