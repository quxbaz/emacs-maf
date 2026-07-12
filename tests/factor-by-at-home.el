(maf-step
  ;; At home with a relation at level 2, the body maps per side: the entry
  ;; is factored on both sides by the top-of-stack argument.
  (calc-push (math-read-expr "6 x + 12 = 18 y + 6"))
  (calc-push 6)
  (progn (goto-char (point-max)) nil)
  (call-interactively 'mafcmd-factor-by)
  (cl-assert (= (calc-stack-size) 1))
  (cl-assert (string= (math-format-value (calc-top 1 'full))
                      "6 (x + 2) = 6 (3 y + 1)"))
  (calc-pop 1)
  ;; Relation-consuming commands opt out via :map -1: solve at home still
  ;; receives the whole relation.
  (calc-push (math-read-expr "2 x + 1 = 7"))
  (calc-push (math-read-expr "x"))
  (progn (goto-char (point-max)) nil)
  (call-interactively 'mafcmd-solve)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "x = 3")))
