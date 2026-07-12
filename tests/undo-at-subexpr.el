(maf-step
  (calc-push (math-read-expr "6 x + 12"))
  (calc-push 5)
  (progn (goto-char (point-min)) (search-forward "x") (backward-char 1))
  (call-interactively 'mafcmd-mul)
  ;; maf-undo restores the stack and keeps point on the same spot, where
  ;; calc-undo alone would jump home.
  (call-interactively 'maf-undo)
  (cl-assert (string= (math-format-value (calc-top 2 'full)) "6 x + 12"))
  (cl-assert (eq (char-after) ?x))
  ;; maf-redo from EOL keeps the EOL affinity.
  (progn (goto-char (point-min)) (end-of-line))
  (call-interactively 'maf-redo)
  (cl-assert (eolp))
  (cl-assert (= (calc-stack-size) 1)))
