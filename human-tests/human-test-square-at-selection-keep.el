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
  (progn
    (call-interactively 'calc-keep-args)
    (call-interactively 'maf-square))
  (progn
    (calc-clear-selections)
    (unless (= (calc-stack-size) 3)
      (error "FAIL square-at-selection-keep: expected size 3, got %d" (calc-stack-size)))
    (message "PASS square-at-selection-keep — top=%S" (calc-top 1 'full))))
