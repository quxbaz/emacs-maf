(maf-defcmd maf-square (expr arg commit)
  "Square command."
  :arity unary
  :prefix "sqr"
  (commit (calcFunc-mul expr expr)))

(maf--debug-setup-test)

(maf--debug-slowly :delay 0.3
  (calc-push 4)
  (call-interactively 'maf-square)
  (progn
    (unless (= (calc-stack-size) 1)
      (error "FAIL square-at-home: expected size 1, got %d" (calc-stack-size)))
    (unless (equal (calc-top 1 'full) 16)
      (error "FAIL square-at-home: expected top 16, got %S" (calc-top 1 'full)))
    (message "PASS square-at-home")))
