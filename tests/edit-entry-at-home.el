;;; Tests for maf-edit-entry-at-home (`) -- the gesture that opens the
;;; level-1 entry for editing and is a trip home: point lands on the
;;; dot, the place it left is marked. On an empty stack there is
;;; nothing to edit and it opens a blank entry instead.

(defvar maf-test--origin nil
  "Buffer position the gesture left, for the mark checks.")

(defvar maf-test--mark nil
  "The mark as it stood before a gesture that should not touch it.")

(maf-step
  ;; calc-wrapper's epilogue renumbers the display; raw pushes would
  ;; leave every entry rendered as level 1.
  (calc-wrapper (maf-push "a") (maf-push "b") (maf-push "12"))

  ;; --- Commit ---

  ;; From inside another entry's formula, the gesture opens the entry
  ;; at level 1 -- not a blank line -- with point at the end of its
  ;; text, ready to extend it.
  (progn (goto-char (point-min)) (search-forward "a"))
  (setq maf-test--origin (point))
  (call-interactively 'maf-edit-entry-at-home)
  (cl-assert maf-edit-mode)
  (cl-assert (eolp))
  ;; The line point sits on is level 1's, already carrying its text.
  (cl-assert (string-match-p "\\`1[:+] +12\\'"
                             (buffer-substring-no-properties
                              (line-beginning-position) (point))))
  (progn (execute-kbd-macro "3") nil)
  (call-interactively 'maf-edit-commit)
  (cl-assert (not maf-edit-mode))
  ;; The entry was edited in place: the stack is the same height and
  ;; the entries above it are untouched.
  (cl-assert (= (calc-stack-size) 3))
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "123"))
  (cl-assert (string= (math-format-value (calc-top 2 'full)) "b"))
  (cl-assert (string= (math-format-value (calc-top 3 'full)) "a"))
  ;; Point is home, on the dot itself — the spot calc parks it at after
  ;; a command, so the next key resolves at home.
  (cl-assert (maf--at-home-p))
  (cl-assert (looking-at "\\.$"))
  (cl-assert (= (point) (progn (calc-wrapper nil) (point))))
  ;; The place the gesture left is marked, so C-u C-SPC returns to it.
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
  ;; still holds the way back, with the edited entry left as it was.
  (calc-wrapper (maf-push "a") (maf-push "12"))
  (progn (goto-char (point-min)) (search-forward "a"))
  (setq maf-test--origin (point))
  (call-interactively 'maf-edit-entry-at-home)
  (progn (execute-kbd-macro "99") nil)
  (call-interactively 'maf-edit-discard)
  (cl-assert (not maf-edit-mode))
  (cl-assert (= (calc-stack-size) 2))
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "12"))
  (cl-assert (maf--at-home-p))
  (cl-assert (looking-at "\\.$"))
  (cl-assert (= (mark t) maf-test--origin))
  (calc-pop (calc-stack-size))

  ;; --- Pressed at home ---

  ;; No journey, so nothing to mark: the mark is left exactly as it
  ;; was. The level-1 entry still opens, and point still lands home.
  (calc-wrapper (maf-push "4"))
  (progn (goto-char (point-max)) nil)
  (cl-assert (maf--at-home-p))
  (setq maf-test--mark (mark t))
  (call-interactively 'maf-edit-entry-at-home)
  (cl-assert (eolp))
  (progn (execute-kbd-macro "7") nil)
  (call-interactively 'maf-edit-commit)
  (cl-assert (= (calc-stack-size) 1))
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "47"))
  (cl-assert (equal (mark t) maf-test--mark))
  (cl-assert (maf--at-home-p))
  (cl-assert (looking-at "\\.$"))
  (calc-pop (calc-stack-size))

  ;; --- Empty stack ---

  ;; Nothing to edit, so the gesture is the quick add it used to be
  ;; throughout: a blank entry opens at the bottom.
  (cl-assert (zerop (calc-stack-size)))
  (call-interactively 'maf-edit-entry-at-home)
  (cl-assert maf-edit-mode)
  (progn (execute-kbd-macro "42") nil)
  (call-interactively 'maf-edit-commit)
  (cl-assert (= (calc-stack-size) 1))
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "42"))
  (cl-assert (maf--at-home-p))
  (cl-assert (looking-at "\\.$"))

  ;; --- A multi-line entry ---

  ;; Level 1 is whatever renders last above the dot, however many lines
  ;; it takes: point lands at the end of its text, not on its first
  ;; line.
  (calc-pop (calc-stack-size))
  (calc-wrapper (maf-push "[1, 2, 3]"))
  (progn (goto-char (point-min)) nil)
  (call-interactively 'maf-edit-entry-at-home)
  (cl-assert (eolp))
  (cl-assert (looking-back "\\]" (line-beginning-position)))
  (call-interactively 'maf-edit-discard)
  (calc-pop (calc-stack-size))

  ;; --- Already editing ---

  ;; The gesture opens a session; it is not a command inside one.
  (call-interactively 'maf-edit-entry-at-home)
  (cl-assert (condition-case nil
                 (progn (call-interactively 'maf-edit-entry-at-home) nil)
               (user-error t)))
  (call-interactively 'maf-edit-discard)

  ;; --- The key ---

  ;; ` reaches the command while the edit module is on, shadowing
  ;; calc-edit, whose job the module takes over.
  (cl-assert (eq (lookup-key maf-mode-map (kbd "`"))
                 'maf-edit-entry-at-home)))
