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
  (cl-assert (= (calc-stack-size) 1))
  (calc-pop (calc-stack-size))

  ;; --- C-RET commits like RET but keeps point ---

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

  ;; On a sub-formula the commit is contextual (as with RET) and point
  ;; stays: a numeric leaf is replaced, point off the home line.
  (maf-push "12 x + 3")
  (progn (goto-char (point-min)) (search-forward "12") (backward-char 1))
  (execute-kbd-macro (kbd "5 C-<return>"))
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "5 x + 3"))
  (cl-assert (not (maf--at-home-p)))
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
  (execute-kbd-macro (kbd "5 RET"))
  (cl-assert (null (mark t)))
  (calc-pop (calc-stack-size))

  ;; --- S-RET adds the number as a new entry just below the one at point ---

  ;; On a mid-stack entry the number lands at that entry's level; the
  ;; entry bumps up one, lower entries stay, and point rests on the new one.
  (maf-push "w") (maf-push "x") (maf-push "y") (maf-push "z")  ; 4:w 3:x 2:y 1:z
  (progn (goto-char (point-min)) (forward-line 1) (end-of-line))   ; on 3: x
  (execute-kbd-macro (kbd "9 S-<return>"))
  (cl-assert (equal (mapcar (lambda (i) (math-format-value (calc-top i 'full)))
                            (number-sequence 1 5))
                    '("z" "y" "9" "x" "w")))     ; 9 inserted at level 3
  (cl-assert (not (maf--at-home-p)))
  (cl-assert (string= (math-format-value (calc-top 3 'full)) "9"))
  (calc-pop (calc-stack-size))

  ;; From a sub-formula, it adds below the whole containing entry.
  (maf-push "a + b") (maf-push "c")             ; 2: a + b   1: c
  (progn (calc-cursor-stack-index 2) (beginning-of-line)
         (search-forward "a") (backward-char 1))
  (execute-kbd-macro (kbd "9 S-<return>"))
  (cl-assert (equal (mapcar (lambda (i) (math-format-value (calc-top i 'full)))
                            (number-sequence 1 3))
                    '("c" "9" "a + b")))
  (calc-pop (calc-stack-size))

  ;; On the top entry there is nothing below but home, so it lands on top.
  (maf-push "p") (maf-push "q") (maf-push "r")  ; 3:p 2:q 1:r
  (progn (calc-cursor-stack-index 1) (end-of-line))
  (execute-kbd-macro (kbd "9 S-<return>"))
  (cl-assert (equal (mapcar (lambda (i) (math-format-value (calc-top i 'full)))
                            (number-sequence 1 4))
                    '("9" "r" "q" "p")))
  (calc-pop (calc-stack-size))

  ;; The push and the roll are one undoable gesture: a single undo reverts.
  (maf-push "w") (maf-push "x") (maf-push "y") (maf-push "z")
  (progn (goto-char (point-min)) (forward-line 1) (end-of-line))
  (execute-kbd-macro (kbd "9 S-<return>"))
  (execute-kbd-macro (kbd "U"))
  (cl-assert (equal (mapcar (lambda (i) (math-format-value (calc-top i 'full)))
                            (number-sequence 1 4))
                    '("z" "y" "x" "w")))
  (calc-pop (calc-stack-size)))
