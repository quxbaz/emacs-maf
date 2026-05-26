(maf-defcmd maf-square (expr arg commit)
  "Square command."
  :arity unary
  :prefix "sqr"
  (commit (calcFunc-mul expr expr)))

(maf--debug-setup-test)

(maf--debug-slowly 0.3
  (calc-push '(+ (* 10 (var x var-x)) 4))
  (progn
    (calc-push '(var c var-c))
    (calc-refresh))
  (goto-char 7)
  (call-interactively 'calc-select-here)
  (call-interactively 'maf-square)
  (calc-clear-selections))
