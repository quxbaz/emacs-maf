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
  (progn
    (calc-clear-selections)
    (unless (= (calc-stack-size) 1)
      (error "FAIL mult-at-selection: expected size 1, got %d" (calc-stack-size)))
    (message "PASS mult-at-selection — top=%S" (calc-top 1 'full))))
