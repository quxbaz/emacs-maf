(maf-step
  (calc-push (math-read-expr "y (6 x + 12)"))
  (calc-push 3)
  (progn (goto-char (point-min)) (search-forward "6 x +") (backward-char 1))
  (call-interactively 'mafcmd-factor-by)
  (cl-assert (= (calc-stack-size) 1))
  ;; The inner sum is factored by 3 and the product left undistributed.
  (cl-assert (string= (math-format-value (calc-top 1 'full))
                      "y(3 (2 x + 4))")))
