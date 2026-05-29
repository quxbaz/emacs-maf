(maf-defcmd maf-square (expr arg commit)
  "Square command."
  :arity unary
  :prefix "sqr"
  (commit (calcFunc-mul expr expr)))

(maf--debug-setup-test)

(maf--debug-slowly :delay 0.3
  (progn
    (calc-push '(calcFunc-eq (var x var-x) 5))
    (calc-refresh)
    (goto-char 0)                       ; relation at top (m=1), margin
    (call-interactively 'calc-keep-args))
  (progn
    (call-interactively 'maf-square)
    (calc-refresh))
  (progn
    ;; keep-args: result pushed on top, original relation preserved below.
    (unless (= (calc-stack-size) 2)
      (error "FAIL square-at-equation-keep: expected size 2, got %d" (calc-stack-size)))
    (unless (string= (math-format-value (calc-top 1 'full)) "x^2 = 25")
      (error "FAIL square-at-equation-keep: expected top 'x^2 = 25', got %s"
             (math-format-value (calc-top 1 'full))))
    (unless (string= (math-format-value (calc-top 2 'full)) "x = 5")
      (error "FAIL square-at-equation-keep: expected pos 2 'x = 5', got %s"
             (math-format-value (calc-top 2 'full))))
    (message "PASS square-at-equation-keep")))
