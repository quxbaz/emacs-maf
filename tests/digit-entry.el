(maf-step
  ;; --- SPC commits into the formula at point ---

  ;; Numeric leaf under point: the entered number replaces it.
  (maf-push "12 x + 3")
  (progn (goto-char (point-min)) (search-forward "12") (backward-char 1))
  (execute-kbd-macro (kbd "5 SPC"))
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "5 x + 3"))
  (calc-pop (calc-stack-size))

  ;; Any other sub-formula: the number multiplies it, number on the left.
  (maf-push "x + 3")
  (progn (goto-char (point-min)) (search-forward "x") (backward-char 1))
  (execute-kbd-macro (kbd "5 SPC"))
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "5 x + 3"))
  (calc-pop (calc-stack-size))

  ;; The product is literal: multiplying a group must not distribute.
  (maf-push "2 + (a + b)")
  (progn (goto-char (point-min)) (search-forward "(a"))
  (execute-kbd-macro (kbd "5 SPC"))
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "2 + 5 (a + b)"))
  (calc-pop (calc-stack-size))

  ;; Replacement covers every number type the entry can produce: a
  ;; typed fraction replaces a float leaf.
  (maf-push "2.5 x")
  (progn (goto-char (point-min)) (search-forward "2.5") (backward-char 1))
  (execute-kbd-macro (kbd "1 : 3 SPC"))
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "1:3 x"))
  (calc-pop (calc-stack-size))

  ;; Relation node under point (its = glyph): both sides multiplied.
  (maf-push "x + 1 = y")
  (progn (goto-char (point-min)) (search-forward "=") (backward-char 1))
  (execute-kbd-macro (kbd "5 SPC"))
  (cl-assert (string= (math-format-value (calc-top 1 'full))
                      "5 (x + 1) = 5 y"))
  (calc-pop (calc-stack-size))

  ;; The commit leaves point on the sub-formula it edited: nothing was
  ;; pushed, so there is no push to home after.
  (maf-push "12 x + 3")
  (progn (goto-char (point-min)) (search-forward "12") (backward-char 1))
  (execute-kbd-macro (kbd "5 SPC"))
  (cl-assert (not (maf--at-home-p)))
  (cl-assert (= (calc-stack-size) 1))
  (calc-pop (calc-stack-size))

  ;; A contextual entry is one undo group: a single undo reverts it.
  (maf-push "12 x + 3")
  (progn (goto-char (point-min)) (search-forward "12") (backward-char 1))
  (execute-kbd-macro (kbd "5 SPC"))
  (execute-kbd-macro (kbd "U"))
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "12 x + 3"))
  (calc-pop (calc-stack-size))

  ;; --- RET pushes, wherever point is ---

  ;; On a sub-formula RET is calc's own RET: the formula is untouched
  ;; and the number lands on the stack, point homing after the push.
  (maf-push "12 x + 3")
  (progn (goto-char (point-min)) (search-forward "12") (backward-char 1))
  (execute-kbd-macro (kbd "5 RET"))
  (cl-assert (= (calc-stack-size) 2))
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "5"))
  (cl-assert (string= (math-format-value (calc-top 2 'full)) "12 x + 3"))
  (cl-assert (maf--at-home-p))
  (calc-pop (calc-stack-size))

  ;; The push is its own undo group — it is not an edit of the entry
  ;; point was on, so one undo takes back the push and nothing else.
  (maf-push "12 x + 3")
  (progn (goto-char (point-min)) (search-forward "12") (backward-char 1))
  (execute-kbd-macro (kbd "5 RET"))
  (execute-kbd-macro (kbd "U"))
  (cl-assert (= (calc-stack-size) 1))
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "12 x + 3"))
  (calc-pop (calc-stack-size))

  ;; Margin and home positions are the same push, as in plain calc.
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

  ;; SPC away from a sub-formula is that same push: at a margin there
  ;; is nothing to edit, so it is calc's unshifted twin of RET again.
  (maf-push "x + 3")
  (progn (goto-char (point-min)) (end-of-line))
  (execute-kbd-macro (kbd "7 SPC"))
  (cl-assert (= (calc-stack-size) 2))
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "7"))
  (cl-assert (maf--at-home-p))
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
  (cl-assert (= (calc-stack-size) 1))
  (calc-pop (calc-stack-size))

  ;; --- C-RET pushes like RET but keeps point ---

  ;; At a margin, RET pushes and drops point home; C-<return> pushes the
  ;; same number but leaves point on the entry it was on.
  (maf-push "x + 3")
  (progn (goto-char (point-min)) (end-of-line))
  (execute-kbd-macro (kbd "7 RET"))
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "7"))
  (cl-assert (maf--at-home-p))            ; RET homes
  (calc-pop (calc-stack-size))

  (maf-push "x + 3")
  (progn (goto-char (point-min)) (end-of-line))
  (execute-kbd-macro (kbd "7 C-<return>"))
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "7"))
  (cl-assert (string= (math-format-value (calc-top 2 'full)) "x + 3"))
  (cl-assert (not (maf--at-home-p)))      ; C-RET keeps point
  (cl-assert (= (line-number-at-pos) 1))  ; still on the x + 3 entry's line
  (calc-pop (calc-stack-size))

  ;; It follows RET onto the stack on a sub-formula too — the formula is
  ;; untouched — and there point staying is the whole of what it adds.
  (maf-push "12 x + 3")
  (progn (goto-char (point-min)) (search-forward "12") (backward-char 1))
  (execute-kbd-macro (kbd "5 C-<return>"))
  (cl-assert (= (calc-stack-size) 2))
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "5"))
  (cl-assert (string= (math-format-value (calc-top 2 'full)) "12 x + 3"))
  (cl-assert (not (maf--at-home-p)))
  (cl-assert (= (line-number-at-pos) 1))  ; still on the 12 x + 3 line
  (calc-pop (calc-stack-size))

  ;; At home there is nowhere to keep point, so C-<return> matches RET.
  (maf-push "a")
  (goto-char (point-max))
  (execute-kbd-macro (kbd "9 C-<return>"))
  (cl-assert (= (calc-stack-size) 2))
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "9"))
  (cl-assert (maf--at-home-p))
  (calc-pop (calc-stack-size))

  ;; --- A homing RET leaves a mark to pop back to ---

  ;; RET at a margin parks point home, but drops a mark on the entry the
  ;; user was on: popping it returns there.
  (maf-push "x + 3")
  (progn (goto-char (point-min)) (end-of-line) (setq mark-ring nil) (set-mark nil))
  (execute-kbd-macro (kbd "7 RET"))
  (cl-assert (maf--at-home-p))                    ; homed
  (cl-assert (integerp (mark t)))                 ; a mark was set
  (progn (setq this-command 'set-mark-command last-command nil)
         (pop-to-mark-command))
  (cl-assert (not (maf--at-home-p)))              ; popped back off home
  (cl-assert (= (line-number-at-pos) 1))          ; onto the x + 3 entry
  (calc-pop (calc-stack-size))

  ;; The keep-point completions do not leave a stray mark: point never
  ;; moved, so there is nothing to pop back to.
  (maf-push "x + 3")
  (progn (goto-char (point-min)) (end-of-line) (setq mark-ring nil) (set-mark nil))
  (execute-kbd-macro (kbd "7 C-<return>"))
  (cl-assert (null (mark t)))
  (calc-pop (calc-stack-size))

  (maf-push "12 x + 3")
  (progn (goto-char (point-min)) (search-forward "12") (backward-char 1)
         (setq mark-ring nil) (set-mark nil))
  (execute-kbd-macro (kbd "5 SPC"))
  (cl-assert (null (mark t)))
  (calc-pop (calc-stack-size))

  ;; A RET on a sub-formula does home, though — it pushes like any
  ;; other RET — so it leaves the mark a homing push always leaves.
  (maf-push "12 x + 3")
  (progn (goto-char (point-min)) (search-forward "12") (backward-char 1)
         (setq mark-ring nil) (set-mark nil))
  (execute-kbd-macro (kbd "5 RET"))
  (cl-assert (maf--at-home-p))
  (cl-assert (integerp (mark t)))
  (calc-pop (calc-stack-size)))
