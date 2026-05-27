(maf-defcmd maf-mult (expr arg commit)
  "Multiplication command."
  :arity binary
  :prefix "mult"
  (commit (calcFunc-mul expr arg)))

(maf--debug-setup-test)

(maf--debug-slowly 0.3
  (calc-push '(+ (* 8 (var x var-x)) 4))
  (progn
    (calc-push '(var x var-x))
    (calc-refresh))
  (goto-char 0)
  (progn
    (call-interactively 'maf-mult)
    (calc-refresh))
  (progn
    (unless (= (calc-stack-size) 1)
      (error "FAIL mult-at-entry: expected size 1, got %d" (calc-stack-size)))
    (message "PASS mult-at-entry — top=%s" (math-format-value (calc-top 1 'full)))))
