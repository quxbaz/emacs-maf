(maf-defcmd maf-sqrt (expr arg commit)
  "Square-root command."
  :arity unary
  :prefix "sqrt"
  (commit (calcFunc-sqrt expr)))

(maf--debug-setup-test)

(maf--debug-slowly 0.3
  (calc-push '(+ (var a var-a) 16))
  (calc-refresh)
  (progn
    ;; Position point on the '16' sub-formula (not at EOL or in line-prefix),
    ;; so the cascade routes to at-subexpr-p.
    (goto-char (point-min))
    (search-forward "16")
    (backward-char 2))
  (progn
    (call-interactively 'maf-sqrt)
    (calc-refresh))
  (progn
    (unless (= (calc-stack-size) 1)
      (error "FAIL sqrt-at-subexpr: expected size 1, got %d" (calc-stack-size)))
    (unless (string= (math-format-value (calc-top 1 'full)) "a + 4")
      (error "FAIL sqrt-at-subexpr: expected 'a + 4', got %s"
             (math-format-value (calc-top 1 'full))))
    (message "PASS sqrt-at-subexpr")))
