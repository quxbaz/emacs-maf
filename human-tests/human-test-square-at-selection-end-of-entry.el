(maf-defcmd maf-square (expr arg commit)
  "Square command."
  :arity unary
  :prefix "sqr"
  (commit (calcFunc-mul expr expr)))

(maf--debug-setup-test)

(maf--debug-slowly 0.3
  (calc-push '(+ (* 8 (var x var-x)) 4))
  (progn
    (calc-push 2)
    (calc-refresh))
  (goto-char 14)
  (call-interactively 'maf-square)
  (progn
    (unless (string= (math-format-value (calc-top 1 'full)) "16 x + 8")
      (error "FAIL"))))
