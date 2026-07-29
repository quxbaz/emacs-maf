;; `(' opens a maf-edit session with a bracketed vector entry already
;; started at the bottom of the stack (`maf-edit-add-vector', the edit
;; module's fourth entry key). A step passes when it raises no error.
;; The contract: the session opens from anywhere, the new entry reads
;; [] with point between the brackets, typing lands inside them, and
;; point returns to where it was before the gesture when the session
;; ends — commit and discard alike.

(maf-step
  ;; Empty stack: the gesture opens both the session and the entry.
  (call-interactively 'maf-edit-add-vector)
  (cl-assert maf-edit-mode)
  (cl-assert (eq (char-before) ?\[))
  (cl-assert (looking-at-p "\\]$"))     ; the closer, and nothing past it
  ;; The line is stamped as an entry that is not on the stack yet.
  (cl-assert (save-excursion (beginning-of-line) (looking-at-p " *[0-9]+\\+")))
  ;; Typing lands inside the brackets rather than after the closer.
  (progn (execute-kbd-macro "1,2") nil)
  (call-interactively 'maf-edit-commit)
  (cl-assert (not maf-edit-mode))
  (cl-assert (= (calc-stack-size) 1))
  (cl-assert (equal (calc-top 1 'full) '(vec 1 2)))
  (calc-pop (calc-stack-size))

  ;; Mid-stack point: the entry still opens at the bottom, the stack
  ;; above it is untouched, and point comes back to the character it
  ;; was on instead of staying in the edited text.
  (maf-push "a")
  (maf-push "b")
  (progn (calc-cursor-stack-index 2)
         (search-forward "a" (line-end-position)) (backward-char 1) nil)
  (call-interactively 'maf-edit-add-vector)
  (cl-assert (eq (char-before) ?\[))
  (progn (execute-kbd-macro "3,4") nil)
  (call-interactively 'maf-edit-commit)
  (cl-assert (= (calc-stack-size) 3))
  (cl-assert (equal (mapcar (lambda (i) (calc-top i 'full))
                            (number-sequence 1 3))
                    '((vec 3 4) (var b var-b) (var a var-a))))
  (cl-assert (looking-at-p "a"))
  (calc-pop (calc-stack-size))

  ;; The pre-filled pair is a real electric pair: typing the closer
  ;; skips over the one already there rather than doubling it.
  (call-interactively 'maf-edit-add-vector)
  (progn (execute-kbd-macro "5]") nil)
  (cl-assert (eolp))                    ; past the single closer
  (call-interactively 'maf-edit-commit)
  (cl-assert (equal (calc-top 1 'full) '(vec 5)))
  (calc-pop (calc-stack-size))

  ;; A matrix, via the displaced row separator (`maf-edit-insert-semicolon').
  (call-interactively 'maf-edit-add-vector)
  (progn (execute-kbd-macro "1,2\e;3,4") nil)
  (call-interactively 'maf-edit-commit)
  (cl-assert (equal (calc-top 1 'full) '(vec (vec 1 2) (vec 3 4))))
  (calc-pop (calc-stack-size))

  ;; Committed untouched the entry is the empty vector — it is what was
  ;; written, and maf-edit commits text exactly as written.
  (maf-push "a")
  (call-interactively 'maf-edit-add-vector)
  (call-interactively 'maf-edit-commit)
  (cl-assert (= (calc-stack-size) 2))
  (cl-assert (equal (calc-top 1 'full) '(vec)))
  (calc-pop (calc-stack-size))

  ;; Discard backs the whole gesture out: stack untouched, point back
  ;; where it was.
  (maf-push "a")
  (maf-push "b")
  (progn (calc-cursor-stack-index 2)
         (search-forward "a" (line-end-position)) (backward-char 1) nil)
  (call-interactively 'maf-edit-add-vector)
  (progn (execute-kbd-macro "9") nil)
  (call-interactively 'maf-edit-discard)
  (cl-assert (not maf-edit-mode))
  (cl-assert (= (calc-stack-size) 2))
  (cl-assert (looking-at-p "a"))
  (calc-pop (calc-stack-size))

  ;; The gesture is an opener, not a key that types a bracket into a
  ;; running session — inside one, maf-mode is off and `(' self-inserts.
  (call-interactively 'maf-edit-add-vector)
  (cl-assert (string-match-p "already active"
                             (condition-case e
                                 (progn (call-interactively 'maf-edit-add-vector) "")
                               (error (error-message-string e)))))
  (call-interactively 'maf-edit-discard))
