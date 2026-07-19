(maf-step
  ;; Empty stack: below-entry falls back to the bottom gesture.
  (call-interactively 'maf-edit-add-entry-below)
  (cl-assert maf-edit-mode)
  (progn (execute-kbd-macro "42") nil)
  (call-interactively 'maf-edit-commit)
  (cl-assert (not maf-edit-mode))
  (cl-assert (= (calc-stack-size) 1))
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "42"))
  ;; Point stayed with the new entry, not sent home.
  (cl-assert (eq (char-before) ?2))
  (calc-pop (calc-stack-size))

  ;; Below the entry at point: the new entry commits mid-stack, one
  ;; level below the entry the gesture started on.
  (maf-push "a")
  (maf-push "b")
  (maf-push "c")
  (progn (calc-cursor-stack-index 3)
         (search-forward "a" (line-end-position)) (backward-char 1) nil)
  (call-interactively 'maf-edit-add-entry-below)
  (cl-assert maf-edit-mode)
  (cl-assert (eolp))
  (progn (execute-kbd-macro "q") nil)
  (call-interactively 'maf-edit-commit)
  (cl-assert (= (calc-stack-size) 4))
  (cl-assert (string= (math-format-value (calc-top 4 'full)) "a"))
  (cl-assert (string= (math-format-value (calc-top 3 'full)) "q"))
  ;; Point stayed on the committed entry, not back on the a.
  (cl-assert (eolp))
  (cl-assert (eq (char-before) ?q))
  (cl-assert (= (calc-locate-cursor-element (point)) 3))
  (calc-pop (calc-stack-size))

  ;; Discard: stack untouched, point keeps its in-edit line.
  (maf-push "a")
  (maf-push "b")
  (progn (calc-cursor-stack-index 2)
         (search-forward "a" (line-end-position)) (backward-char 1) nil)
  (call-interactively 'maf-edit-add-entry-below)
  (progn (execute-kbd-macro "zz") nil)
  (call-interactively 'maf-edit-discard)
  (cl-assert (not maf-edit-mode))
  (cl-assert (= (calc-stack-size) 2))
  ;; The zz line vanished with the discard; point stays on that line,
  ;; now b's.
  (cl-assert (eolp))
  (cl-assert (eq (char-before) ?b))
  (calc-pop (calc-stack-size))

  ;; At home the gesture is maf-edit-add-entry's: bottom of the stack.
  (maf-push "a")
  (progn (goto-char (point-max)) nil)
  (call-interactively 'maf-edit-add-entry-below)
  (progn (execute-kbd-macro "7") nil)
  (call-interactively 'maf-edit-commit)
  (cl-assert (= (calc-stack-size) 2))
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "7"))
  (cl-assert (string= (math-format-value (calc-top 2 'full)) "a"))
  ;; Point stayed on the new entry rather than returning home.
  (cl-assert (eq (char-before) ?7)))
