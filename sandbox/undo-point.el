(maf-step
  ;; A single undo restores point to where it was before the undone
  ;; command ran — here on the + of "a + b", a position the command's
  ;; rewrite used to strand at column 0.
  (maf-push "a + b")
  (maf-push "c + d")
  (calc-push 2)
  (progn (goto-char (point-min)) (forward-char 6))
  (let ((before (point)))
    (execute-kbd-macro (kbd "+ U"))
    (cl-assert (= (point) before))
    (cl-assert (= (calc-stack-size) 3)))

  ;; Digit-entry handoff (5 +) is one gesture: one undo reverts both
  ;; the push and the command, and point survives the push's stack
  ;; renumbering (used to land at BOL).
  (progn (calc-cursor-stack-index 2) (forward-char 4))
  (let ((before (point)))
    (execute-kbd-macro (kbd "5 + U"))
    (cl-assert (= (point) before))
    (cl-assert (= (calc-stack-size) 3)))

  ;; Undo/redo chain (keys contiguous so last-command links them):
  ;; redo bounces point to the post-command position...
  (progn (goto-char (point-min)) (forward-char 6))
  (progn
    (execute-kbd-macro (kbd "+ U D"))
    (cl-assert (= (current-column) 10))
    (cl-assert (= (calc-stack-size) 2)))
  (calc-pop (calc-stack-size))

  ;; ...and a full bounce lands back at the pre-command position.
  (maf-push "a + b")
  (maf-push "c + d")
  (calc-push 2)
  (progn (goto-char (point-min)) (forward-char 6))
  (let ((before (point)))
    (execute-kbd-macro (kbd "+ U D U"))
    (cl-assert (= (point) before))
    (cl-assert (= (calc-stack-size) 3))))
