;;; Tests for maf-edit-add-entry-at-home (`) -- the quick-add gesture
;;; that is a trip home: point lands on the dot, the place it left is
;;; marked.

(defvar maf-test--origin nil
  "Buffer position the gesture left, for the mark checks.")

(defvar maf-test--mark nil
  "The mark as it stood before a gesture that should not touch it.")

(maf-step
  ;; calc-wrapper's epilogue renumbers the display; raw pushes would
  ;; leave every entry rendered as level 1.
  (calc-wrapper (maf-push "a") (maf-push "b") (maf-push "c"))

  ;; --- Commit ---

  ;; From inside an entry's formula, the gesture opens a blank entry at
  ;; the bottom, ready to type.
  (progn (goto-char (point-min)) (search-forward "a"))
  (setq maf-test--origin (point))
  (call-interactively 'maf-edit-add-entry-at-home)
  (cl-assert maf-edit-mode)
  (cl-assert (eolp))
  (progn (execute-kbd-macro "z") nil)
  (call-interactively 'maf-edit-commit)
  (cl-assert (not maf-edit-mode))
  (cl-assert (= (calc-stack-size) 4))
  ;; The new entry landed on the bottom, the rest of the stack intact.
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "z"))
  (cl-assert (string= (math-format-value (calc-top 4 'full)) "a"))
  ;; Point is home, on the dot itself — the spot calc parks it at after
  ;; a command, so the next key resolves at home.
  (cl-assert (maf--at-home-p))
  (cl-assert (looking-at "\\.$"))
  (cl-assert (= (point) (progn (calc-wrapper nil) (point))))
  ;; The place the gesture left is marked, so C-u C-SPC returns to it.
  ;; The push renumbered every prefix but did not move the line.
  (cl-assert (= (mark t) maf-test--origin))
  (cl-assert (save-excursion (goto-char (mark t))
                             (looking-back "a" (line-beginning-position))))

  ;; maf-go-home pressed at home makes the return trip on that mark.
  (call-interactively 'maf-go-home)
  (cl-assert (= (point) maf-test--origin))
  (cl-assert (not (maf--at-home-p)))
  (calc-pop (calc-stack-size))

  ;; --- Discard ---

  ;; The trip out happened either way: point lands home and the mark
  ;; still holds the way back, with the stack untouched.
  (calc-wrapper (maf-push "a") (maf-push "b"))
  (progn (goto-char (point-min)) (search-forward "a"))
  (setq maf-test--origin (point))
  (call-interactively 'maf-edit-add-entry-at-home)
  (progn (execute-kbd-macro "zz") nil)
  (call-interactively 'maf-edit-discard)
  (cl-assert (not maf-edit-mode))
  (cl-assert (= (calc-stack-size) 2))
  (cl-assert (maf--at-home-p))
  (cl-assert (looking-at "\\.$"))
  (cl-assert (= (mark t) maf-test--origin))
  (calc-pop (calc-stack-size))

  ;; --- Pressed at home ---

  ;; No journey, so nothing to mark: the mark is left exactly as it
  ;; was. Point still lands on the dot.
  (calc-wrapper (maf-push "a"))
  (progn (goto-char (point-max)) nil)
  (cl-assert (maf--at-home-p))
  (setq maf-test--mark (mark t))
  (call-interactively 'maf-edit-add-entry-at-home)
  (progn (execute-kbd-macro "7") nil)
  (call-interactively 'maf-edit-commit)
  (cl-assert (= (calc-stack-size) 2))
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "7"))
  (cl-assert (equal (mark t) maf-test--mark))
  (cl-assert (maf--at-home-p))
  (cl-assert (looking-at "\\.$"))
  (calc-pop (calc-stack-size))

  ;; --- Empty stack ---

  ;; The bottom of an empty stack is home, and the gesture opens there
  ;; like any other.
  (cl-assert (zerop (calc-stack-size)))
  (call-interactively 'maf-edit-add-entry-at-home)
  (cl-assert maf-edit-mode)
  (progn (execute-kbd-macro "42") nil)
  (call-interactively 'maf-edit-commit)
  (cl-assert (= (calc-stack-size) 1))
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "42"))
  (cl-assert (maf--at-home-p))
  (cl-assert (looking-at "\\.$"))

  ;; --- Already editing ---

  ;; The gesture opens a session; it is not a command inside one.
  (call-interactively 'maf-edit-add-entry-at-home)
  (cl-assert (condition-case nil
                 (progn (call-interactively 'maf-edit-add-entry-at-home) nil)
               (user-error t)))
  (call-interactively 'maf-edit-discard)

  ;; --- The key ---

  ;; ` reaches the command while the edit module is on, shadowing
  ;; calc-edit, whose job the module takes over.
  (cl-assert (eq (lookup-key maf-mode-map (kbd "`"))
                 'maf-edit-add-entry-at-home)))
