(maf-step
  ;; The test drives the feature against a scratch directory and
  ;; explicit session names; the session's own persistence state is
  ;; stashed and put back at the end.
  (setq maf--persist-stash (list maf-stack-directory
                                 maf-stack-session-name
                                 maf--stack-session
                                 maf--stack-restored
                                 maf--stack-last-saved)
        maf-stack-directory (make-temp-file "maf-persist-test" t)
        maf-stack-session-name "test-a"
        maf--stack-session nil
        maf--stack-restored t
        maf--stack-last-saved 'maf--persist-unset)

  ;; Save writes this session's file: values top first, name claimed
  ;; and locked.
  (calc-wrapper (maf-push "6 x + 12") (maf-push "a + b"))
  (cl-assert (maf-save-stack))
  (cl-assert (string= maf--stack-session "test-a"))
  (cl-assert (file-exists-p (maf--stack-file "test-a" ".lock")))
  (cl-assert (equal (maf--stack-read (maf--stack-file "test-a"))
                    (list (math-read-expr "a + b")
                          (math-read-expr "6 x + 12"))))

  ;; Unchanged stack: the save is skipped.
  (cl-assert (not (maf-save-stack)))

  ;; Restore brings this session's entries back in order.
  (calc-pop (calc-stack-size))
  (setq maf--stack-restored nil)
  (maf-restore-stack)
  (cl-assert (= (calc-stack-size) 2))
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "a + b"))
  (cl-assert (string= (math-format-value (calc-top 2 'full)) "6 x + 12"))

  ;; Once per session, and never onto a non-empty stack.
  (maf-restore-stack)
  (cl-assert (= (calc-stack-size) 2))
  (setq maf--stack-restored nil)
  (maf-restore-stack)
  (cl-assert (= (calc-stack-size) 2))
  (calc-pop (calc-stack-size))

  ;; A second session saves under its own name; nothing is shared.
  (setq maf-stack-session-name "test-b"
        maf--stack-session nil
        maf--stack-last-saved 'maf--persist-unset)
  (calc-wrapper (maf-push "y^2"))
  (cl-assert (maf-save-stack))
  (cl-assert (equal (maf--stack-read (maf--stack-file "test-b"))
                    (list (math-read-expr "y^2"))))
  (cl-assert (equal (maf--stack-read (maf--stack-file "test-a"))
                    (list (math-read-expr "a + b")
                          (math-read-expr "6 x + 12"))))
  (calc-pop (calc-stack-size))

  ;; The chooser lists both sessions, newest save first.
  (cl-assert (equal (mapcar #'car (maf--stack-saved-sessions))
                    '("test-b" "test-a")))

  ;; Restoring another session's stack replaces the current one...
  (calc-wrapper (maf-push "999"))
  (maf-restore-stack-from "test-a")
  (cl-assert (= (calc-stack-size) 2))
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "a + b"))

  ;; ...and with KEEP it pushes on top instead.
  (maf-restore-stack-from "test-b" t)
  (cl-assert (= (calc-stack-size) 3))
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "y^2"))
  (cl-assert (string= (math-format-value (calc-top 3 'full)) "6 x + 12"))
  (calc-pop (calc-stack-size))

  ;; Name uniquification: a name locked by a live process is taken —
  ;; PID 1 is always alive — and a dead owner's lock is stale.
  (with-temp-file (maf--stack-file "test-c" ".lock") (insert "1"))
  (setq maf-stack-session-name "test-c" maf--stack-session nil)
  (cl-assert (string= (maf--stack-session) "test-c-2"))
  (with-temp-file (maf--stack-file "test-d" ".lock") (insert "999999999"))
  (setq maf-stack-session-name "test-d" maf--stack-session nil)
  (cl-assert (string= (maf--stack-session) "test-d"))

  ;; A corrupt save file is skipped with a message; calc keeps working.
  (with-temp-file (maf--stack-file "test-d") (insert "((( not lisp"))
  (setq maf--stack-restored nil)
  (maf-restore-stack)
  (cl-assert (= (calc-stack-size) 0))

  ;; No file for this session, but others saved: start empty and say
  ;; how to load one.
  (setq maf-stack-session-name "test-e" maf--stack-session nil
        maf--stack-restored nil)
  ;; Assert on *Messages*, not (current-message): stepping via
  ;; keyboard macro suppresses the echo area.
  (progn (maf-restore-stack)
         (cl-assert (with-current-buffer (messages-buffer)
                      (save-excursion
                        (goto-char (point-max))
                        (search-backward "maf-restore-stack-from"
                                         (max (point-min) (- (point-max) 500))
                                         t)))))
  (cl-assert (= (calc-stack-size) 0))

  ;; The single switch: on wires hooks and one timer, off removes them
  ;; and releases the name lock.
  (maf-persist-mode 1)
  (maf-persist-mode 1)
  (cl-assert (memq 'maf--stack-shutdown kill-emacs-hook))
  (cl-assert (memq 'maf-restore-stack calc-mode-hook))
  (cl-assert (= 1 (seq-count (lambda (tm) (eq (timer--function tm) 'maf-save-stack))
                             timer-idle-list)))
  (maf-persist-mode -1)
  (cl-assert (not (memq 'maf--stack-shutdown kill-emacs-hook)))
  (cl-assert (not (memq 'maf-restore-stack calc-mode-hook)))
  (cl-assert (not (seq-some (lambda (tm) (eq (timer--function tm) 'maf-save-stack))
                            timer-idle-list)))
  (cl-assert (not (file-exists-p (maf--stack-file "test-e" ".lock"))))
  (cl-assert (null maf--stack-session))

  ;; Put the session's own persistence state back, mode included.
  (progn (delete-directory maf-stack-directory t)
         (setq maf-stack-directory (nth 0 maf--persist-stash)
               maf-stack-session-name (nth 1 maf--persist-stash)
               maf--stack-session (nth 2 maf--persist-stash)
               maf--stack-restored (nth 3 maf--persist-stash)
               maf--stack-last-saved (nth 4 maf--persist-stash))
         (maf-persist-mode 1)))
