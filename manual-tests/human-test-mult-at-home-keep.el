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
    (calc-refresh)
    (call-interactively 'calc-keep-args))
  (call-interactively 'maf-mult)
  (progn
    (unless (= (calc-stack-size) 3)
      (error "FAIL mult-at-home-keep: expected size 3, got %d" (calc-stack-size)))
    (unless (equal (calc-top 1 'full) 6)
      (error "FAIL mult-at-home-keep: expected top 6, got %S" (calc-top 1 'full)))
    (unless (equal (calc-top 2 'full) 2)
      (error "FAIL mult-at-home-keep: expected pos 2 to be 2, got %S" (calc-top 2 'full)))
    (unless (equal (calc-top 3 'full) 3)
      (error "FAIL mult-at-home-keep: expected pos 3 to be 3, got %S" (calc-top 3 'full)))
    (message "PASS mult-at-home-keep")))
