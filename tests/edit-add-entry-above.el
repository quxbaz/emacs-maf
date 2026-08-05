;; `maf-edit-add-entry-above' opens its blank entry on the other side of
;; the entry at point than `maf-edit-add-entry-below' does. The
;; contract: the new entry commits one level above the entry the
;; gesture started on — the topmost entry included, where there is no
;; line above to break — and at home it opens at the bottom, the dot
;; being the only line left to sit above.

(maf-step
  ;; Empty stack: nothing to sit above, so the bottom.
  (call-interactively 'maf-edit-add-entry-above)
  (cl-assert maf-edit-mode)
  (progn (execute-kbd-macro "42") nil)
  (call-interactively 'maf-edit-commit)
  (cl-assert (not maf-edit-mode))
  (cl-assert (= (calc-stack-size) 1))
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "42"))
  ;; Point stayed with the new entry, not sent home.
  (cl-assert (eq (char-before) ?2))
  (calc-pop (calc-stack-size))

  ;; Above the entry at point: the new entry commits mid-stack, one
  ;; level above the entry the gesture started on.
  (maf-push "a")
  (maf-push "b")
  (maf-push "c")
  (progn (calc-cursor-stack-index 2)
         (search-forward "b" (line-end-position)) (backward-char 1) nil)
  (call-interactively 'maf-edit-add-entry-above)
  (cl-assert maf-edit-mode)
  (cl-assert (eolp))
  (progn (execute-kbd-macro "q") nil)
  (call-interactively 'maf-edit-commit)
  (cl-assert (= (calc-stack-size) 4))
  (cl-assert (string= (math-format-value (calc-top 4 'full)) "a"))
  (cl-assert (string= (math-format-value (calc-top 3 'full)) "q"))
  (cl-assert (string= (math-format-value (calc-top 2 'full)) "b"))
  ;; Point stayed on the committed entry, not back on the b.
  (cl-assert (eolp))
  (cl-assert (eq (char-before) ?q))
  (cl-assert (= (calc-locate-cursor-element (point)) 3))
  (calc-pop (calc-stack-size))

  ;; The topmost entry: the blank line opens at the very top of the
  ;; buffer, where there is no previous line to break.
  (maf-push "a")
  (maf-push "b")
  (progn (calc-cursor-stack-index 2)
         (search-forward "a" (line-end-position)) (backward-char 1) nil)
  (call-interactively 'maf-edit-add-entry-above)
  (progn (execute-kbd-macro "w") nil)
  (call-interactively 'maf-edit-commit)
  (cl-assert (= (calc-stack-size) 3))
  (cl-assert (string= (math-format-value (calc-top 3 'full)) "w"))
  (cl-assert (string= (math-format-value (calc-top 2 'full)) "a"))
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "b"))
  ;; The entry it opened above kept its own text — the newline landed
  ;; between the two entries, not inside the top one.
  (cl-assert (= (calc-locate-cursor-element (point)) 3))
  (cl-assert (eq (char-before) ?w))
  (calc-pop (calc-stack-size))

  ;; Discard: stack untouched, point keeps its in-edit line.
  (maf-push "a")
  (maf-push "b")
  (progn (calc-cursor-stack-index 1)
         (search-forward "b" (line-end-position)) (backward-char 1) nil)
  (call-interactively 'maf-edit-add-entry-above)
  (progn (execute-kbd-macro "zz") nil)
  (call-interactively 'maf-edit-discard)
  (cl-assert (not maf-edit-mode))
  (cl-assert (= (calc-stack-size) 2))
  ;; The zz line vanished with the discard; point stays on that line,
  ;; now b's.
  (cl-assert (eolp))
  (cl-assert (eq (char-before) ?b))
  (calc-pop (calc-stack-size))

  ;; At home there is no entry to sit above: the bottom of the stack,
  ;; the same place `maf-edit-add-entry-below' opens from there.
  (maf-push "a")
  (progn (goto-char (point-max)) nil)
  (call-interactively 'maf-edit-add-entry-above)
  (progn (execute-kbd-macro "7") nil)
  (call-interactively 'maf-edit-commit)
  (cl-assert (= (calc-stack-size) 2))
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "7"))
  (cl-assert (string= (math-format-value (calc-top 2 'full)) "a"))
  ;; Point stayed on the new entry rather than returning home.
  (cl-assert (eq (char-before) ?7)))
