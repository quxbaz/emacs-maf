(maf-step
  ;; Commit is literal: arithmetic the user typed never folds.
  (call-interactively 'maf-edit-add-entry-below)
  (progn (execute-kbd-macro "1 + 2 + x") nil)
  (call-interactively 'maf-edit-commit)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "1 + 2 + x"))
  (calc-pop (calc-stack-size))

  ;; Editing an existing entry commits as written too.
  (maf-push "a")
  (progn (calc-cursor-stack-index 1) (end-of-line) nil)
  (call-interactively 'maf-edit)
  (progn (execute-kbd-macro " + 3 + 4") nil)
  (call-interactively 'maf-edit-commit)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "a + 3 + 4"))
  (calc-pop (calc-stack-size))

  ;; Literalness ends at the commit: an operation that consumes the
  ;; entry normalizes as usual.
  (call-interactively 'maf-edit-add-entry-below)
  (progn (execute-kbd-macro "1 + 2 + x") nil)
  (call-interactively 'maf-edit-commit)
  (calc-push 10)
  (calc-plus nil)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "x + 13")))
