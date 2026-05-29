(maf-defcmd maf-mult (expr arg commit)
  "Multiplication command."
  :arity binary
  :prefix "mult"
  (commit (calcFunc-mul expr arg)))

(maf--debug-setup-test)

(maf--debug-step
  (calc-push '(calcFunc-eq (var x var-x) 5))
  (progn
    (calc-push 2)
    (calc-refresh))
  (progn
    ;; Relation at level 2, arg (2) at level 1. Point at the relation's
    ;; line-prefix margin → equation target with m=2 (binary needs the
    ;; relation below the top).
    (calc-cursor-stack-index 2)
    (beginning-of-line))
  (progn
    (call-interactively 'maf-mult)
    (calc-refresh))
  (progn
    ;; Both sides multiplied by 2, arg consumed once: x = 5  ->  2 x = 10
    (unless (= (calc-stack-size) 1)
      (error "FAIL mult-at-equation: expected size 1, got %d" (calc-stack-size)))
    (unless (string= (math-format-value (calc-top 1 'full)) "2 x = 10")
      (error "FAIL mult-at-equation: expected '2 x = 10', got %s"
             (math-format-value (calc-top 1 'full))))
    (message "PASS mult-at-equation")))
