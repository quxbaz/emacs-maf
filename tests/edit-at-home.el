;; Where point lands when a maf-edit session opened at home ends.
;; Opening there is the gesture for adding at the bottom, so commit and
;; discard alike put point back on the . line: the next SPC starts the
;; next entry instead of landing on the one just committed. The flag is
;; the toggle's alone — a session opened on an entry, and the quick-add
;; gestures with a placement of their own, are untouched by it. A step
;; passes when it raises no error.

(maf-step
  ;; Empty stack: point is at home to begin with, and the typed entry
  ;; commits with point back on the dot rather than after the text.
  (cl-assert (maf--at-home-p))
  (call-interactively 'maf-edit)
  (progn (execute-kbd-macro "5") nil)
  (call-interactively 'maf-edit-commit)
  (cl-assert (= (calc-stack-size) 1))
  (cl-assert (equal (calc-top 1 'full) 5))
  (cl-assert (maf--at-home-p))
  (cl-assert (looking-at "\\.$"))
  ;; The flag does not outlive the session it described.
  (cl-assert (not maf-edit--from-home))
  (calc-pop (calc-stack-size))

  ;; With a stack under it the entry still commits on top, and point is
  ;; still home — the placement is about where the session opened, not
  ;; about how much was there.
  (maf-push "a + b")
  (progn (calc-cursor-stack-index 0) nil)
  (call-interactively 'maf-edit)
  (progn (execute-kbd-macro "x+1") nil)
  (call-interactively 'maf-edit-commit)
  (cl-assert (= (calc-stack-size) 2))
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "x + 1"))
  (cl-assert (string= (math-format-value (calc-top 2 'full)) "a + b"))
  (cl-assert (maf--at-home-p))
  (cl-assert (looking-at "\\.$"))
  (calc-pop (calc-stack-size))

  ;; The point of it: entries in a row, driven as real keypresses, with
  ;; no homing key between them. SPC opens, RET commits, and the next
  ;; SPC opens again because point never left home.
  (progn (calc-cursor-stack-index 0)
         (execute-kbd-macro (kbd "SPC 1 1 RET"))
         (execute-kbd-macro (kbd "SPC 2 2 RET"))
         (execute-kbd-macro (kbd "SPC 3 3 RET"))
         nil)
  (cl-assert (= (calc-stack-size) 3))
  (cl-assert (equal (mapcar (lambda (i) (calc-top i 'full))
                            (number-sequence 1 3))
                    '(33 22 11)))
  (cl-assert (maf--at-home-p))
  (calc-pop (calc-stack-size))

  ;; Discard backs the gesture out and lands point home just the same:
  ;; the placement belongs to the session, not to what it committed.
  (maf-push "a")
  (progn (calc-cursor-stack-index 0) nil)
  (call-interactively 'maf-edit)
  (progn (execute-kbd-macro "zz") nil)
  (call-interactively 'maf-edit-discard)
  (cl-assert (not maf-edit-mode))
  (cl-assert (= (calc-stack-size) 1))
  (cl-assert (maf--at-home-p))
  (cl-assert (looking-at "\\.$"))
  (calc-pop (calc-stack-size))

  ;; The one exception: point ended inside an entry that came from the
  ;; stack. The user went off to work on that entry, so the commit
  ;; leaves point with it rather than sending it home.
  (maf-push "a + b")
  (maf-push "c")
  (progn (calc-cursor-stack-index 0) nil)
  (call-interactively 'maf-edit)
  (progn (calc-cursor-stack-index 2) (end-of-line)
         (execute-kbd-macro "+z") nil)
  (call-interactively 'maf-edit-commit)
  (cl-assert (= (calc-stack-size) 2))
  (cl-assert (string= (math-format-value (calc-top 2 'full)) "a + b + z"))
  (cl-assert (not (maf--at-home-p)))
  (cl-assert (eolp))
  (cl-assert (eq (char-before) ?z))
  (calc-pop (calc-stack-size))

  ;; A session opened on an entry keeps its in-edit point, even for an
  ;; entry typed onto the dot line: only the toggle pressed at home
  ;; makes the home landing.
  (maf-push "a")
  (maf-push "b")
  (progn (calc-cursor-stack-index 2) (end-of-line) nil)
  (call-interactively 'maf-edit)
  (progn (goto-char (overlay-start maf-edit--dot)) (end-of-line)
         (execute-kbd-macro "99") nil)
  (call-interactively 'maf-edit-commit)
  (cl-assert (= (calc-stack-size) 3))
  (cl-assert (equal (calc-top 1 'full) 99))
  (cl-assert (not (maf--at-home-p)))
  (cl-assert (eq (char-before) ?9))
  (calc-pop (calc-stack-size))

  ;; The quick-add gestures state their own placement and keep it: at
  ;; home, add-entry-below opens at the bottom and stays with the new
  ;; entry, while add-vector returns to the pre-edit point — which at
  ;; home is home, by its own rule rather than this one.
  (maf-push "a")
  (progn (calc-cursor-stack-index 0) nil)
  (call-interactively 'maf-edit-add-entry-below)
  (progn (execute-kbd-macro "7") nil)
  (call-interactively 'maf-edit-commit)
  (cl-assert (= (calc-stack-size) 2))
  (cl-assert (not (maf--at-home-p)))
  (cl-assert (eq (char-before) ?7))
  (progn (calc-cursor-stack-index 0) nil)
  (call-interactively 'maf-edit-add-vector)
  (progn (execute-kbd-macro "8") nil)
  (call-interactively 'maf-edit-commit)
  (cl-assert (= (calc-stack-size) 3))
  (cl-assert (equal (calc-top 1 'full) '(vec 8)))
  (cl-assert (maf--at-home-p))
  (calc-pop (calc-stack-size)))
