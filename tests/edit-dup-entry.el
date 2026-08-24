;; Duplicating an entry inside a maf-edit session: M-RET copies the
;; entry at point into the slot directly below it
;; (`maf-edit-dup-entry'). A step passes when it raises no error.
;;
;; The contract: the unit is the entry, never the screen line, so an
;; entry rendered across several lines copies whole; the copy carries
;; the source's value object, so a display too lossy to read back
;; still duplicates exactly and the copy shows a plain N: rather than
;; the N+ of an entry parsed from text; the neighbouring entries keep
;; their own values, which a copy inserted at the next line's start
;; would carry off; and point rides to the copy, or stays home when it
;; was never on an entry at all.

(maf-step
  ;; Both spellings of the key, as the terminal cannot deliver the GUI
  ;; event. The stack's own `maf-dup-go' duplicates too, though its
  ;; copy lands on top rather than below.
  (cl-assert (eq (lookup-key maf-edit-mode-map (kbd "M-<return>"))
                 'maf-edit-dup-entry))
  (cl-assert (eq (lookup-key maf-edit-mode-map (kbd "M-RET"))
                 'maf-edit-dup-entry))

  ;; Outside a session the command refuses rather than editing calc's
  ;; rendered stack; the key never reaches it there.
  (cl-assert (not (ignore-errors (call-interactively 'maf-edit-dup-entry) t)))

  ;; --- The copy lands directly below, and nothing else moves ---
  (maf-push "a")
  (maf-push "b")
  (maf-push "c")
  (progn (calc-cursor-stack-index 2)
         (search-forward "b" (line-end-position)) nil)
  (call-interactively 'maf-edit)
  (cl-assert maf-edit-mode)
  (call-interactively 'maf-edit-dup-entry)
  (cl-assert (= (length (maf-edit--overlays)) 4))
  (cl-assert (equal (mapcar #'maf-edit--entry-text (maf-edit--overlays))
                    '("a" "b" "b" "c")))
  ;; Point rode to the copy, keeping its place within the entry.
  (cl-assert (eq (char-before) ?b))
  (cl-assert (eq (maf-edit--entry-at-point) (nth 2 (maf-edit--overlays))))
  (call-interactively 'maf-edit-commit)
  (cl-assert (= (calc-stack-size) 4))
  (cl-assert (equal (mapcar (lambda (n) (math-format-value (calc-top n 'full)))
                            '(1 2 3 4))
                    '("c" "b" "b" "a")))
  (calc-pop (calc-stack-size))

  ;; --- Every neighbour keeps its own value object ---
  ;; A copy inserted at the next line's beginning lands inside the
  ;; neighbour's overlay and carries its value off; the neighbour then
  ;; commits as a re-reading of its text. Here each entry still holds
  ;; the object it was adopted with, and none is flagged new.
  (maf-push "a")
  (maf-push "b")
  (progn (calc-cursor-stack-index 2)
         (search-forward "a" (line-end-position)) nil)
  (call-interactively 'maf-edit)
  (call-interactively 'maf-edit-dup-entry)
  (cl-assert (seq-every-p (lambda (o) (overlay-get o 'maf-edit-val))
                          (maf-edit--overlays)))
  ;; No entry advertises itself as new or dirty: every prefix is N:.
  (cl-assert (not (string-match-p "[*+]" (buffer-substring-no-properties
                                          (point-min) (point-max)))))
  (call-interactively 'maf-edit-commit)
  (calc-pop (calc-stack-size))

  ;; --- A lossy display duplicates exactly ---
  ;; Fixed-point notation shows three digits of a nine-digit float. The
  ;; copy is the value, not the reading of those three digits, so both
  ;; entries survive the round trip whole.
  (calc-push '(float 123456789 -9))
  (calc-fix-notation 3)
  (calc-refresh)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "0.123"))
  (progn (calc-cursor-stack-index 1)
         (search-forward "0.123" (line-end-position)) nil)
  (call-interactively 'maf-edit)
  (call-interactively 'maf-edit-dup-entry)
  (call-interactively 'maf-edit-commit)
  (cl-assert (= (calc-stack-size) 2))
  (cl-assert (equal (calc-top 1 'full) '(float 123456789 -9)))
  (cl-assert (equal (calc-top 2 'full) '(float 123456789 -9)))
  (progn (calc-normal-notation nil) (calc-refresh) nil)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "0.123456789"))
  (calc-pop (calc-stack-size))

  ;; --- A multi-line entry copies whole ---
  ;; A matrix renders one row per line. Copying the line point is on
  ;; would cut the rows apart — either committing a nested vector that
  ;; no one asked for, or refusing on unbalanced delimiters.
  (calc-push '(vec (vec 1 2) (vec 3 4)))
  (calc-refresh)
  (progn (calc-cursor-stack-index 1) (forward-line 1)
         (search-forward "3" (line-end-position)) nil)
  (call-interactively 'maf-edit)
  (call-interactively 'maf-edit-dup-entry)
  (cl-assert (= (length (maf-edit--overlays)) 2))
  ;; Point kept its place inside the entry: the copy's second row.
  (cl-assert (eq (char-before) ?3))
  (call-interactively 'maf-edit-commit)
  (cl-assert (= (calc-stack-size) 2))
  (cl-assert (equal (calc-top 1 'full) '(vec (vec 1 2) (vec 3 4))))
  (cl-assert (equal (calc-top 2 'full) '(vec (vec 1 2) (vec 3 4))))
  (calc-pop (calc-stack-size))

  ;; --- An edited entry copies as the text it now has ---
  (maf-push "a")
  (progn (calc-cursor-stack-index 1)
         (search-forward "a" (line-end-position)) nil)
  (call-interactively 'maf-edit)
  (progn (execute-kbd-macro "+1") nil)
  (call-interactively 'maf-edit-dup-entry)
  (cl-assert (equal (mapcar #'maf-edit--entry-text (maf-edit--overlays))
                    '("a+1" "a+1")))
  (call-interactively 'maf-edit-commit)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "a + 1"))
  (cl-assert (string= (math-format-value (calc-top 2 'full)) "a + 1"))
  (calc-pop (calc-stack-size))

  ;; --- At home the bottom entry is the subject, and point stays ---
  (maf-push "a")
  (maf-push "b")
  (progn (goto-char (point-max)) nil)
  (call-interactively 'maf-edit)
  (cl-assert (null (maf-edit--entry-at-point)))
  (call-interactively 'maf-edit-dup-entry)
  (cl-assert (equal (mapcar #'maf-edit--entry-text (maf-edit--overlays))
                    '("a" "b" "b")))
  ;; Point never left the home line, which the copy went in above.
  (cl-assert (null (maf-edit--entry-at-point)))
  (call-interactively 'maf-edit-commit)
  (cl-assert (= (calc-stack-size) 3))
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "b"))
  (cl-assert (string= (math-format-value (calc-top 2 'full)) "b"))
  (calc-pop (calc-stack-size))

  ;; --- An active region is not the subject ---
  ;; The line duplicate this replaces reads the region when there is
  ;; one, and copies a run of text across two entries as if it were an
  ;; entry itself. Here the entry point is in is the subject either way.
  (maf-push "a")
  (maf-push "b")
  (progn (calc-cursor-stack-index 2)
         (search-forward "a" (line-end-position)) nil)
  (call-interactively 'maf-edit)
  (progn (push-mark (point) t t)
         (calc-cursor-stack-index 1) (end-of-line)
         (setq deactivate-mark nil) nil)
  (call-interactively 'maf-edit-dup-entry)
  (cl-assert (equal (mapcar #'maf-edit--entry-text (maf-edit--overlays))
                    '("a" "b" "b")))
  (call-interactively 'maf-edit-discard)
  (calc-pop (calc-stack-size))

  ;; --- A numeric prefix argument makes that many copies ---
  (maf-push "a")
  (progn (calc-cursor-stack-index 1)
         (search-forward "a" (line-end-position)) nil)
  (call-interactively 'maf-edit)
  (progn (let ((current-prefix-arg 3))
           (call-interactively 'maf-edit-dup-entry))
         nil)
  (cl-assert (equal (mapcar #'maf-edit--entry-text (maf-edit--overlays))
                    '("a" "a" "a" "a")))
  (call-interactively 'maf-edit-commit)
  (cl-assert (= (calc-stack-size) 4))
  (calc-pop (calc-stack-size))

  ;; --- Undo takes the copy back, values and flags with it ---
  ;; The line duplicate leaves the neighbour flagged new even after an
  ;; undo, its value object gone for good; here one undo restores the
  ;; session exactly, and the commit that follows is the original stack.
  (maf-push "a")
  (maf-push "b")
  (progn (calc-cursor-stack-index 2)
         (search-forward "a" (line-end-position)) nil)
  (call-interactively 'maf-edit)
  (call-interactively 'maf-edit-dup-entry)
  (cl-assert (= (length (maf-edit--overlays)) 3))
  (progn (undo-boundary) (call-interactively 'undo) (maf-edit--post-command) nil)
  (cl-assert (equal (mapcar #'maf-edit--entry-text (maf-edit--overlays))
                    '("a" "b")))
  (cl-assert (not (string-match-p "[*+]" (buffer-substring-no-properties
                                          (point-min) (point-max)))))
  (call-interactively 'maf-edit-commit)
  (cl-assert (= (calc-stack-size) 2))
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "b"))
  (cl-assert (string= (math-format-value (calc-top 2 'full)) "a"))
  (calc-pop (calc-stack-size))

  ;; --- Nothing to duplicate ---
  ;; A session on an empty stack has no entry anywhere, home included.
  (call-interactively 'maf-edit)
  (cl-assert maf-edit-mode)
  (cl-assert (not (ignore-errors (call-interactively 'maf-edit-dup-entry) t)))
  (call-interactively 'maf-edit-discard)
  (cl-assert (zerop (calc-stack-size))))
