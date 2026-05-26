(maf-defcmd maf-square (expr arg commit)
  "Square command."
  :arity unary
  :prefix "sqr"
  (commit (calcFunc-mul expr expr)))

(maf--debug-setup-test)

(maf--debug-slowly 0.3
  (calc-push '(+ (* 20 (var x var-x)) 10))
  (progn
    (calc-push 2)
    (calc-refresh))
  (calc-refresh)
  (goto-char 7)
  (call-interactively 'calc-select-here)
  (call-interactively 'maf-square)
  (calc-clear-selections))
