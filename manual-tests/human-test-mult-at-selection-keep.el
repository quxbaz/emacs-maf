(maf-defcmd maf-mult (expr arg commit)
  "Multiplication command."
  :arity binary
  :prefix "mult"
  (commit (calcFunc-mul expr arg)))

(maf--debug-setup-test)

(maf--debug-slowly :delay 0.3
  (calc-push '(+ (* 20 (var x var-x)) 10))
  (progn
    (calc-push 2)
    (calc-refresh))
  (goto-char 7)
  (call-interactively 'calc-select-here)
  (progn
    (call-interactively 'calc-keep-args)
    (call-interactively 'maf-mult))
  (progn
    (calc-clear-selections)
    (unless (= (calc-stack-size) 3)
      (error "FAIL mult-at-selection-keep: expected size 3, got %d" (calc-stack-size)))
    (unless (equal (calc-top 2 'full) 2)
      (error "FAIL mult-at-selection-keep: expected pos 2 to be 2, got %S" (calc-top 2 'full)))
    (message "PASS mult-at-selection-keep — top=%S" (calc-top 1 'full))))
