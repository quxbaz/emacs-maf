(maf-defcmd maf-mult (expr arg commit)
  "Multiplication command."
  :arity binary
  :prefix "mult"
  (commit (calcFunc-mul expr arg)))

(maf--debug-setup-test)

(maf--debug-slowly :delay 0.3
  (calc-push 3)
  (progn
    (calc-push 2)
    (calc-refresh))
  (call-interactively 'maf-mult)
  (progn
    (unless (= (calc-stack-size) 1)
      (error "FAIL mult-at-home: expected size 1, got %d" (calc-stack-size)))
    (unless (equal (calc-top 1 'full) 6)
      (error "FAIL mult-at-home: expected top 6, got %S" (calc-top 1 'full)))
    (message "PASS mult-at-home")))
