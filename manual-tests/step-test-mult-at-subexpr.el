(maf-defcmd maf-mult (expr arg commit)
  "Multiplication command."
  :arity binary
  :prefix "mult"
  (commit (calcFunc-mul expr arg)))

(maf--debug-setup-test)

(maf--debug-step
  (calc-push '(* 2 (+ (* 3 (var x var-x)) 4)))
  (calc-push 5)
  (progn (goto-char (point-min)) (search-forward "+") (backward-char 1))
  (call-interactively 'maf-mult)
  (cl-assert (= (calc-stack-size) 1))
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "2 (15 x + 20)")))
