(maf-step
  ;; The reported scenario: the sole entry edited down to () commits
  ;; as nothing — the stack comes back empty instead of blocking on
  ;; "Expected a number".
  (maf-push "x")
  (progn (calc-cursor-stack-index 1) (end-of-line) nil)
  (call-interactively 'maf-edit)
  (progn (execute-kbd-macro (kbd "DEL")) (execute-kbd-macro "()") nil)
  (call-interactively 'maf-edit-commit)
  (cl-assert (not maf-edit-mode))
  (cl-assert (= (calc-stack-size) 0))

  ;; A () entry among real ones deletes alone; its neighbours commit.
  (maf-push "a")
  (maf-push "b")
  (call-interactively 'maf-edit-add-entry-below)
  (progn (execute-kbd-macro "()") nil)
  (call-interactively 'maf-edit-commit)
  (cl-assert (= (calc-stack-size) 2))
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "b"))
  (cl-assert (string= (math-format-value (calc-top 2 'full)) "a"))
  (calc-pop (calc-stack-size))

  ;; Nesting and whitespace still wrap nothing.
  (call-interactively 'maf-edit-add-entry-below)
  (progn (execute-kbd-macro "( () )") nil)
  (call-interactively 'maf-edit-commit)
  (cl-assert (= (calc-stack-size) 0))

  ;; [] is the empty vector, a value in its own right — not deleted.
  (call-interactively 'maf-edit-add-entry-below)
  (progn (execute-kbd-macro "[]") nil)
  (call-interactively 'maf-edit-commit)
  (cl-assert (= (calc-stack-size) 1))
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "[]"))
  (calc-pop (calc-stack-size))

  ;; Unbalanced parens are still a blocked commit, not a deletion.
  ;; Electric pairing may close the typed paren; deleting to eol
  ;; leaves the bare ( either way.
  (call-interactively 'maf-edit-add-entry-below)
  (progn (execute-kbd-macro "(")
         (delete-region (point) (line-end-position)) nil)
  (cl-assert (condition-case nil
                 (progn (call-interactively 'maf-edit-commit) nil)
               (error t)))
  (cl-assert maf-edit-mode)
  (call-interactively 'maf-edit-discard)
  (cl-assert (= (calc-stack-size) 0)))
