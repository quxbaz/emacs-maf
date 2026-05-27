(maf-defcmd maf-square (expr arg commit)
  "Square command."
  :arity unary
  :prefix "sqr"
  (commit (calcFunc-mul expr expr)))

(maf--debug-setup-test)

(maf--debug-slowly 0.3
  (calc-push '(+ (* 8 (var x var-x)) 4))
  (progn
    (calc-push '(var x var-x))
    (calc-refresh))
  (goto-char 12)
  (call-interactively 'maf-square)
  (progn
    (unless (string= (math-format-value (calc-top 2 'full)) "(8 x + 4)^2")
      (error "FAIL"))
    (message "PASS")))
