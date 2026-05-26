(maf-defcmd maf-square (expr arg commit)
  "Square command."
  :arity unary
  :prefix "sqr"
  (commit (calcFunc-mul expr expr)))

(maf--debug-setup-test)

(maf--debug-slowly 0.3
  (calc-push '(+ (* 10 (var x var-x)) 4))
  (progn
    (calc-push '(var c var-c))
    (calc-refresh))
  (goto-char 7)
  (call-interactively 'calc-select-here)
  (call-interactively 'maf-square)
  (progn
    (calc-clear-selections)
    (unless (= (calc-stack-size) 2)
      (error "FAIL square-at-selection: expected size 2, got %d" (calc-stack-size)))
    (message "PASS square-at-selection — top=%S bottom=%S"
             (calc-top 1 'full) (calc-top 2 'full))))
