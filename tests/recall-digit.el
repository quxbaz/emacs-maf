;; What feeds the recall ring on the digit-entry path
;; (modules/maf-recall.el). A number pushed as an entry of its own is
;; recorded; a number that modifies something already on the stack — a
;; contextual commit, or a command's argument — is not.

(maf-step
  (progn (maf-use-recall-mode 1) (setq maf-recall--ring nil) nil)

  ;; RET at home pushes an entry of its own: recorded.
  (execute-kbd-macro (kbd "42 RET"))
  (cl-assert (= (calc-stack-size) 1))
  (cl-assert (equal (mapcar #'car maf-recall--ring) '("42")))

  ;; The text recorded is the value's own rendering, not the
  ;; keystrokes: a typed .5 comes back in canonical form.
  (execute-kbd-macro (kbd ".5 RET"))
  (cl-assert (equal (mapcar #'car maf-recall--ring) '("0.5" "42")))
  (progn (calc-pop (calc-stack-size)) nil)

  ;; RET's contextual commit edits the sub-formula at point. Nothing
  ;; new reached the stack, so nothing reaches the ring.
  (maf-push "12 x + 3")
  (progn (goto-char (point-min)) (search-forward "12") (backward-char 1))
  (execute-kbd-macro (kbd "5 RET"))
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "5 x + 3"))
  (cl-assert (equal (mapcar #'car maf-recall--ring) '("0.5" "42")))
  (progn (calc-pop (calc-stack-size)) nil)

  ;; A command key terminating the entry (2 +) makes the number that
  ;; command's argument: it is consumed immediately, not an entry.
  (maf-push "3")
  (progn (goto-char (point-max)) nil)
  (execute-kbd-macro (kbd "2 +"))
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "5"))
  (cl-assert (equal (mapcar #'car maf-recall--ring) '("0.5" "42")))
  (progn (calc-pop (calc-stack-size)) nil)

  ;; The pi shortcut at home pushes a product, and the ring takes the
  ;; product — recording the typed 5 alone would lose the pi.
  (progn (goto-char (point-max)) nil)
  (execute-kbd-macro (kbd "5 P"))
  (cl-assert (= (calc-stack-size) 1))
  (cl-assert (equal (mapcar #'car maf-recall--ring) '("5 * pi" "0.5" "42")))
  (progn (calc-pop (calc-stack-size)) nil)

  ;; C-<return> holds point where it stands, but still pushes an entry
  ;; of its own: recorded like the RET push.
  (maf-push "a + b")
  (progn (goto-char (point-min)) (search-forward "a") (backward-char 1))
  (execute-kbd-macro (kbd "7 C-<return>"))
  (cl-assert (= (calc-stack-size) 2))
  (cl-assert (equal (mapcar #'car maf-recall--ring)
                    '("7" "5 * pi" "0.5" "42"))))
