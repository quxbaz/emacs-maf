(maf-defcmd maf-square (expr arg commit)
  "Square command."
  :arity unary
  :prefix "sqr"
  (commit (calcFunc-mul expr expr)))

(maf--debug-setup-test)

(maf--debug-slowly 0.3
  (progn
    (calc-push 4)
    (call-interactively 'calc-keep-args))
  (call-interactively 'maf-square)
  (progn
    (unless (= (calc-stack-size) 2)
      (error "FAIL square-at-home-keep: expected size 2, got %d" (calc-stack-size)))
    (unless (equal (calc-top 1 'full) 16)
      (error "FAIL square-at-home-keep: expected top 16, got %S" (calc-top 1 'full)))
    (unless (equal (calc-top 2 'full) 4)
      (error "FAIL square-at-home-keep: expected pos 2 to be 4, got %S" (calc-top 2 'full)))
    (message "PASS square-at-home-keep")))
