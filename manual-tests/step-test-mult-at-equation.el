(maf-defcmd maf-mult (expr arg commit)
  "Multiplication command."
  :arity binary
  :prefix "mult"
  (commit (calcFunc-mul expr arg)))

(maf--debug-setup-test)

(maf--debug-step
  (calc-push '(calcFunc-eq (var x var-x) 5))
  (calc-push 2)
  (calc-cursor-stack-index 2)
  (call-interactively 'maf-mult)
  (unless (= (calc-stack-size) 1)
    (error "FAIL mult-at-equation: expected size 1, got %d" (calc-stack-size)))
  (unless (string= (math-format-value (calc-top 1 'full)) "2 x = 10")
    (error "FAIL mult-at-equation: expected '2 x = 10', got %s"
           (math-format-value (calc-top 1 'full))))
  (message "PASS mult-at-equation"))
