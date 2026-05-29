(maf-defcmd maf-square (expr arg commit)
  "Square command."
  :arity unary
  :prefix "sqr"
  (commit (calcFunc-mul expr expr)))

(maf--debug-setup-test)

(maf--debug-slowly :delay 0.3
  (calc-push '(+ (* 8 (var x var-x)) 4))
  (progn
    (calc-push '(var x var-x))
    (calc-refresh))
  (goto-char 0)
  (progn
    (call-interactively 'maf-square)
    (calc-refresh))
  (progn
    (unless (= (calc-stack-size) 2)
      (error "FAIL square-at-entry: expected size 2, got %d" (calc-stack-size)))
    (unless (string= (math-format-value (calc-top 2 'full)) "(8 x + 4)^2")
      (error "FAIL square-at-entry: expected pos 2 to be '(8 x + 4)^2', got %s"
             (math-format-value (calc-top 2 'full))))
    (message "PASS square-at-entry")))
