(maf-step
  ;; Numeric leaf under point: the entered number replaces it.
  (maf-push "12 x + 3")
  (progn (goto-char (point-min)) (search-forward "12") (backward-char 1))
  (execute-kbd-macro (kbd "5 RET"))
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "5 x + 3"))
  (calc-pop (calc-stack-size))

  ;; Any other sub-formula: the number multiplies it, number on the left.
  (maf-push "x + 3")
  (progn (goto-char (point-min)) (search-forward "x") (backward-char 1))
  (execute-kbd-macro (kbd "5 RET"))
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "5 x + 3"))
  (calc-pop (calc-stack-size))

  ;; The product is literal: multiplying a group must not distribute.
  (maf-push "2 + (a + b)")
  (progn (goto-char (point-min)) (search-forward "(a"))
  (execute-kbd-macro (kbd "5 RET"))
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "2 + 5 (a + b)"))
  (calc-pop (calc-stack-size))

  ;; Replacement covers every number type the entry can produce: a
  ;; typed fraction replaces a float leaf.
  (maf-push "2.5 x")
  (progn (goto-char (point-min)) (search-forward "2.5") (backward-char 1))
  (execute-kbd-macro (kbd "1 : 3 RET"))
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "1:3 x"))
  (calc-pop (calc-stack-size))

  ;; Relation node under point (its = glyph): both sides multiplied.
  (maf-push "x + 1 = y")
  (progn (goto-char (point-min)) (search-forward "=") (backward-char 1))
  (execute-kbd-macro (kbd "5 RET"))
  (cl-assert (string= (math-format-value (calc-top 1 'full))
                      "5 (x + 1) = 5 y"))
  (calc-pop (calc-stack-size))

  ;; Margin and home positions keep calc's plain behavior: push.
  (maf-push "x + 3")
  (progn (goto-char (point-min)) (end-of-line))
  (execute-kbd-macro (kbd "7 RET"))
  (cl-assert (= (calc-stack-size) 2))
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "7"))
  (cl-assert (string= (math-format-value (calc-top 2 'full)) "x + 3"))
  (execute-kbd-macro (kbd "9 RET"))  ; point at home after the push
  (cl-assert (= (calc-stack-size) 3))
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "9"))
  (calc-pop (calc-stack-size))

  ;; A contextual entry is one undo group: a single undo reverts it.
  (maf-push "12 x + 3")
  (progn (goto-char (point-min)) (search-forward "12") (backward-char 1))
  (execute-kbd-macro (kbd "5 RET"))
  (execute-kbd-macro (kbd "U"))
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "12 x + 3"))
  (calc-pop (calc-stack-size))

  ;; Command-key termination at the margin still hands off to the
  ;; command as one gesture: 5 + adds 5 to the entry, one undo reverts
  ;; both the arg push and the add.
  (maf-push "x + 3")
  (progn (goto-char (point-min)) (end-of-line))
  (execute-kbd-macro (kbd "5 +"))
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "x + 8"))
  (execute-kbd-macro (kbd "U"))
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "x + 3"))
  (cl-assert (= (calc-stack-size) 1)))
