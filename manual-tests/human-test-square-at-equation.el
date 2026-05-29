(maf-defcmd maf-square (expr arg commit)
  "Square command."
  :arity unary
  :prefix "sqr"
  (commit (calcFunc-mul expr expr)))

(maf--debug-setup-test)

(maf--debug-slowly :delay 0.3
  (calc-push '(calcFunc-eq (var x var-x) 5))
  (progn
    (calc-refresh)
    ;; Point at the top entry's line-prefix (margin), routing past subexpr to
    ;; the equation target.
    (goto-char 0))
  (progn
    (call-interactively 'maf-square)
    (calc-refresh))
  (progn
    (unless (= (calc-stack-size) 1)
      (error "FAIL square-at-equation: expected size 1, got %d" (calc-stack-size)))
    ;; Both sides squared: x = 5  ->  x^2 = 25
    (unless (string= (math-format-value (calc-top 1 'full)) "x^2 = 25")
      (error "FAIL square-at-equation: expected 'x^2 = 25', got %s"
             (math-format-value (calc-top 1 'full))))
    (message "PASS square-at-equation")))
