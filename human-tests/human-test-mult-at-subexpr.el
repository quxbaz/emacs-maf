(maf-defcmd maf-mult (expr arg commit)
  "Multiplication command."
  :arity binary
  :prefix "mult"
  (commit (calcFunc-mul expr arg)))

(maf--debug-setup-test)

(maf--debug-slowly 0.3
  (calc-push '(* 2 (+ (* 3 (var x var-x)) 4)))
  (progn
    (calc-push 5)
    (calc-refresh))
  (progn
    ;; Point on '+' selects the whole (3x + 4) sub-formula,
    ;; so only that part is multiplied by 5.
    (goto-char (point-min))
    (search-forward "+")
    (backward-char 1))
  (progn
    (call-interactively 'maf-mult)
    (calc-refresh))
  (progn
    (unless (= (calc-stack-size) 1)
      (error "FAIL mult-at-subexpr: expected size 1, got %d" (calc-stack-size)))
    (unless (string= (math-format-value (calc-top 1 'full)) "2 (15 x + 20)")
      (error "FAIL mult-at-subexpr: expected '2 (15 x + 20)', got %s"
             (math-format-value (calc-top 1 'full))))
    (message "PASS mult-at-subexpr")))
