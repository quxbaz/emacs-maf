(maf-step
  ;; The history log is persisted beside the stack: same session name,
  ;; same saves, its own file. What makes it worth keeping is the part
  ;; of it that is typed rather than derived — the separators dividing
  ;; the log into sittings, and the text written into them — so those
  ;; are what the test follows across a save and a read back.
  ;;
  ;; Driven against a scratch directory and an explicit session name;
  ;; the session's own persistence and history state is stashed and put
  ;; back at the end.
  (setq maf--persist-hist-stash (list maf-stack-directory
                                      maf-stack-session-name
                                      maf--stack-session
                                      maf--history-restored
                                      maf--history-last-saved
                                      maf-history--states
                                      maf-history--index)
        maf-stack-directory (make-temp-file "maf-persist-hist-test" t)
        maf-stack-session-name "hist-a"
        maf--stack-session nil
        maf--history-restored nil
        maf--history-last-saved nil
        maf-history--index 0
        maf-history--states (list (list (list 12) "mul" 'mafcmd-mul)
                                  (list (list 4 3) "entry")
                                  (list (list 3) nil)))

  ;; The log writes to a file of its own under the session's name --
  ;; not the stack's file, which is untouched by a history save.
  (cl-assert (maf-save-history))
  (cl-assert (file-exists-p (maf--history-file "hist-a")))
  (cl-assert (not (file-exists-p (maf--stack-file "hist-a"))))

  ;; Deliberately not `.eld': `maf--stack-saved-sessions' globs that to
  ;; find sessions, and a log wearing it would list as a session of its
  ;; own. With a stack saved beside it, exactly one session is seen.
  (progn (with-temp-file (maf--stack-file "hist-a")
           (prin1 (list (math-read-expr "x + 1")) (current-buffer))))
  (cl-assert (equal (mapcar #'car (maf--stack-saved-sessions)) (list "hist-a")))

  ;; An unchanged log writes nothing.
  (cl-assert (not (maf-save-history)))

  ;; A separator is set in place on the state it marks, so a log that
  ;; is the same list is not the same log. Marking one -- no formula
  ;; moving, nothing pushed -- is a change, and saves again.
  (progn (maf-history--set-separator (nth 1 maf-history--states) "morning"))
  (cl-assert (maf-save-history))
  (cl-assert (not (maf-save-history)))

  ;; Read back into an empty log: the states return, and with them the
  ;; separator and the text written in it.
  (progn (setq maf-history--states nil
               maf--history-restored nil)
         (maf-restore-history))
  (cl-assert (= (length maf-history--states) 3))
  (cl-assert (equal (maf-history--separator (nth 1 maf-history--states))
                    "morning"))
  (cl-assert (equal (maf-history--separator-label (nth 1 maf-history--states))
                    "morning"))
  (cl-assert (null (maf-history--separator (nth 0 maf-history--states))))
  ;; The states themselves came through whole, values and label alike.
  (cl-assert (equal (nth 0 (nth 1 maf-history--states)) (list 4 3)))
  (cl-assert (equal (maf-history--label (nth 1 maf-history--states)) "entry"))
  (cl-assert (eq (nth 2 (nth 0 maf-history--states)) 'mafcmd-mul))

  ;; Once per session: a second call is a no-op, so a log recorded
  ;; since the restore is not overwritten by the file again.
  (progn (setq maf-history--states (list (list (list 7) "new")))
         (maf-restore-history))
  (cl-assert (equal maf-history--states (list (list (list 7) "new"))))

  ;; Nor does it land under a log that already has something in it:
  ;; the session recorded first, so what it recorded stands.
  (progn (setq maf--history-restored nil)
         (maf-restore-history))
  (cl-assert (equal maf-history--states (list (list (list 7) "new"))))

  ;; Trimmed to `maf-history-size', which may have been lowered since
  ;; the save was written.
  (progn (setq maf-history--states
               (cl-loop for i below 8 collect (list (list i) "mul"))
               maf--history-last-saved nil)
         (maf-save-history)
         (setq maf-history--states nil
               maf--history-restored nil))
  (cl-assert (let ((maf-history-size 5))
               (maf-restore-history)
               (= (length maf-history--states) 5)))
  (cl-assert (equal (nth 0 (car maf-history--states)) (list 0)))

  ;; A file that is not a log is skipped with a message and left in
  ;; place: a broken log is not worth failing a calc session over, and
  ;; the running log is left alone rather than half-set from it.
  (progn (with-temp-file (maf--history-file "hist-a") (insert "{{{ not lisp"))
         (setq maf-history--states (list (list (list 5) "kept"))
               maf--history-restored nil)
         (maf-restore-history))
  (cl-assert (equal maf-history--states (list (list (list 5) "kept"))))
  (cl-assert (file-exists-p (maf--history-file "hist-a")))
  ;; A file holding readable lisp that is not a log is refused too.
  (progn (with-temp-file (maf--history-file "hist-a") (prin1 42 (current-buffer)))
         (setq maf-history--states nil
               maf--history-restored nil)
         (maf-restore-history))
  (cl-assert (null maf-history--states))

  ;; With the history module off there is no log to write, and a saved
  ;; one is left as it stands rather than emptied by a session that
  ;; never kept one.
  (progn (with-temp-file (maf--history-file "hist-a")
           (prin1 (list (list (list 1) "kept")) (current-buffer))))
  (cl-assert (let ((maf-use-history-mode nil)
                   (maf-history--states nil)
                   (maf--history-last-saved nil))
               (null (maf-save-history))))
  (cl-assert (equal (maf--history-read (maf--history-file "hist-a"))
                    (list (list (list 1) "kept"))))

  ;; Renaming a session takes its log with it: left behind, the log
  ;; would be orphaned under a name nothing saves to any more.
  (progn (setq maf--stack-session "hist-a")
         (with-temp-file (maf--stack-file "hist-a")
           (prin1 (list (math-read-expr "x")) (current-buffer))))
  (progn (maf-saved-stacks)
         (with-current-buffer (get-buffer "*maf-stacks*")
           (maf--stacks-goto 'hist-a)
           (maf-stacks-name "hist-b")))
  (cl-assert (file-exists-p (maf--history-file "hist-b")))
  (cl-assert (not (file-exists-p (maf--history-file "hist-a"))))

  ;; Deleting a saved stack deletes its log, for the same reason:
  ;; nothing would ever read it again.
  (progn (with-current-buffer (get-buffer "*maf-stacks*")
           (maf--stacks-goto 'hist-b)
           (maf-stacks-delete)))
  (cl-assert (not (file-exists-p (maf--history-file "hist-b"))))
  (cl-assert (not (file-exists-p (maf--stack-file "hist-b"))))

  ;; Put the session's own state back.
  (progn (when (get-buffer "*maf-stacks*") (kill-buffer "*maf-stacks*"))
         (delete-directory maf-stack-directory t)
         (setq maf-stack-directory (nth 0 maf--persist-hist-stash)
               maf-stack-session-name (nth 1 maf--persist-hist-stash)
               maf--stack-session (nth 2 maf--persist-hist-stash)
               maf--history-restored (nth 3 maf--persist-hist-stash)
               maf--history-last-saved (nth 4 maf--persist-hist-stash)
               maf-history--states (nth 5 maf--persist-hist-stash)
               maf-history--index (nth 6 maf--persist-hist-stash))))
