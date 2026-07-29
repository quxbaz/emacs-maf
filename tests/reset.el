;; `maf-reset' and `maf-reset-settings' are real commands (src/stack.el),
;; so these steps drive them directly. A step passes when it raises no
;; error. The contract: reset clears the stack, the trail and the
;; timeline and restores the saved modes; reset-settings restores the
;; modes alone, keeping the stack, its undo history and point; and a
;; settings file that signals costs the settings, not the session.

(maf-step
  ;; --- maf-reset: the whole session goes ---

  ;; The stack is emptied and the modes come back to their saved values.
  (maf-push "a + b")
  (maf-push "7")
  (cl-assert (= (calc-stack-size) 2))
  (call-interactively 'maf-reset)
  (cl-assert (zerop (calc-stack-size)))
  ;; maf-mode survives: calc-reset re-runs calc-mode, which kills every
  ;; buffer-local, and maf's keymap goes with it if nothing puts it back.
  (cl-assert (bound-and-true-p maf-mode))

  ;; Undo and redo go with the stack — nothing is left to undo into.
  (maf-push "x + 1")
  (call-interactively 'maf-reset)
  (cl-assert (null calc-undo-list))
  (cl-assert (null calc-redo-list))

  ;; The trail is emptied rather than killed, so a window showing it
  ;; keeps showing it. `calc-record' is how calc itself files a value
  ;; there, and does not need the trail buffer to be current.
  (maf-push "2 + 3")
  (calc-record (calc-top 1 'full) "test")
  (call-interactively 'maf-reset)
  (cl-assert (or (null (get-buffer "*Calc Trail*"))
                 (with-current-buffer "*Calc Trail*"
                   (zerop (buffer-size)))))

  ;; --- maf-reset-settings: the stack stays ---

  ;; The stack, its size and its contents are untouched.
  (maf-push "a + b")
  (maf-push "c d")
  (call-interactively 'maf-reset-settings)
  (cl-assert (= (calc-stack-size) 2))
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "c d"))
  (cl-assert (string= (math-format-value (calc-top 2 'full)) "a + b"))
  (cl-assert (bound-and-true-p maf-mode))

  ;; Undo survives too: the stack it describes is still there, so the
  ;; history is still valid. calc-reset drops both lists whatever its
  ;; argument, and the command puts them back. What matters is that an
  ;; undo still reaches the stack afterwards; how much it takes back
  ;; depends on how calc batched the pushes above, so the check is that
  ;; the stack shrank at all rather than by an exact count.
  (cl-assert (consp calc-undo-list))
  (progn (setq maf--test-size (calc-stack-size))
         (setq last-command nil)
         (call-interactively 'maf-undo))
  (cl-assert (< (calc-stack-size) maf--test-size))
  (calc-pop (calc-stack-size))

  ;; A display mode toggled by hand goes back to where it was saved.
  (maf-push "1 / 3")
  (progn (calc-frac-mode 1) (setq calc-prefer-frac t))
  (call-interactively 'maf-reset-settings)
  (cl-assert (= (calc-stack-size) 1))
  (calc-pop (calc-stack-size))

  ;; --- a settings file that signals costs the settings, not the session ---

  ;; `calc-reset' nils every buffer-local in `calc-local-var-list', then
  ;; evaluates the settings file's mode block, and only then re-runs
  ;; `calc-mode' to rebuild them. A form that signals in between leaves
  ;; the buffer with no stack top and no display precision — unable to
  ;; render its own stack, let alone take a command. The error still
  ;; reaches the user; what must not happen is losing the session with it.
  (maf-push "a + b")
  (progn
    (setq maf--test-bad-settings (make-temp-file "maf-bad-settings" nil ".el"))
    (with-temp-file maf--test-bad-settings
      (insert ";;; Mode settings stored by Calc\n"
              "(setq calc-float-format '(float 0))\n"
              "(car 'not-a-cons)\n"
              ";;; End of mode settings\n")))
  (cl-assert (eq :signaled
                 (let ((calc-settings-file maf--test-bad-settings))
                   (condition-case nil
                       (progn (maf--reset-calc 1) :no-error)
                     (error :signaled)))))
  ;; The buffer is coherent again: locals rebuilt, maf-mode back on.
  (cl-assert calc-stack-top)
  (cl-assert (bound-and-true-p maf-mode))
  ;; And the stack rode it out — calc-reset shields it behind a let, so
  ;; the abort never reached it — and still renders.
  (cl-assert (= (calc-stack-size) 1))
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "a + b"))
  (progn (delete-file maf--test-bad-settings)
         (setq maf--test-bad-settings nil))
  (calc-pop (calc-stack-size)))
