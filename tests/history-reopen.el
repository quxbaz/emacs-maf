(maf-step
  ;; The history log is global session state, the selection into it
  ;; included: stash and run against a clean one; the last form puts
  ;; everything back. The browser's windows open below calc here and
  ;; are quit again at the end.
  (setq maf--history-reopen-stash (list maf-history--states
                                        maf-history--last-raw
                                        maf-history--index
                                        maf-history--hold
                                        maf-history--focus)
        maf-history--states nil
        maf-history--last-raw nil
        maf-history--index 0
        maf-history--hold nil
        maf-history--focus nil)
  (calc-wrapper (maf-push "a"))
  (maf-history--capture)
  (calc-wrapper (maf-push "b"))
  (maf-history--capture)
  (calc-wrapper (maf-push "c"))
  (maf-history--capture)
  (cl-assert (= (length maf-history--states) 3))

  ;; The step forms run in the calc buffer, so the browser's buffers
  ;; are named where point or the header is read.
  (defun maf--history-reopen-log-index ()
    (with-current-buffer maf-history--log-buffer
      (get-text-property (point) 'maf-history-index)))

  ;; The first browse opens on the newest state, in the log. The
  ;; cockpit takes its window back between forms, so which window a
  ;; browse selected is read in the form that opened it.
  (cl-assert (eq (progn (maf-history) (window-buffer))
                 (get-buffer maf-history--log-buffer)))
  (cl-assert (get-buffer-window maf-history--log-buffer t))
  (cl-assert (= maf-history--index 0))

  ;; Quitting from an older state and browsing again reopens on it,
  ;; point on its row.
  (call-interactively 'maf-history-previous)
  (cl-assert (= maf-history--index 1))
  (call-interactively 'maf-history-quit)
  (cl-assert (null (get-buffer-window maf-history--log-buffer t)))
  (maf-history)
  (cl-assert (= maf-history--index 1))
  (cl-assert (eql (maf--history-reopen-log-index) 1))
  (with-current-buffer maf-history--log-buffer
    (cl-assert (equal header-line-format "maf-history  2/3")))

  ;; Point drifted off the mark at quit: the row it was on is the
  ;; selection the next browse reopens on, the stack beside it showing
  ;; that state.
  (with-selected-window (get-buffer-window maf-history--log-buffer t)
    (goto-char (point-min))
    (forward-line 2)
    (cl-assert (eql (get-text-property (point) 'maf-history-index) 2))
    (call-interactively 'maf-history-quit))
  (maf-history)
  (cl-assert (= maf-history--index 2))
  (cl-assert (eql (maf--history-reopen-log-index) 2))
  (with-current-buffer maf-history--stack-buffer
    (cl-assert (string-match-p "1:  a" (buffer-string)))
    (cl-assert (not (string-match-p "b" (buffer-string)))))

  ;; A state recorded while the browser is closed moves the log down a
  ;; row under the selection, which keeps naming the same state.
  (call-interactively 'maf-history-quit)
  (let ((state (nth maf-history--index maf-history--states)))
    (calc-wrapper (maf-push "d"))
    (maf-history--capture)
    (cl-assert (= (length maf-history--states) 4))
    (cl-assert (= maf-history--index 3))
    (maf-history)
    (cl-assert (eq (nth maf-history--index maf-history--states) state)))

  ;; The stack window keeps its own point across a quit too: on the
  ;; deepest entry at quit, on it again on reopening. Quit from the
  ;; log, the log is selected again.
  (progn (call-interactively 'maf-history-newest)
         (call-interactively 'maf-history-focus-stack)
         (with-selected-window (get-buffer-window maf-history--stack-buffer t)
           (call-interactively 'maf-history-stack-first)
           (cl-assert (looking-at "4:  a")))
         (call-interactively 'maf-history-focus-log)
         (call-interactively 'maf-history-quit))
  (cl-assert (eq (progn (maf-history) (window-buffer))
                 (get-buffer maf-history--log-buffer)))
  (with-current-buffer maf-history--stack-buffer
    (cl-assert (looking-at "4:  a")))

  ;; Quit from the stack window, the next browse selects the stack
  ;; window, point where it was.
  (with-selected-window (get-buffer-window maf-history--stack-buffer t)
    (call-interactively 'maf-history-quit))
  (cl-assert (eq maf-history--focus 'stack))
  (cl-assert (eq (progn (maf-history) (window-buffer))
                 (get-buffer maf-history--stack-buffer)))
  (with-current-buffer maf-history--stack-buffer
    (cl-assert (looking-at "4:  a")))

  ;; Inserting from the newest state records a state of its own, and
  ;; the view holds on the one it inserted from instead of following
  ;; to the new one: the next browse reopens there, point still on the
  ;; entry it took.
  (let ((state (car maf-history--states)))
    (with-selected-window (get-buffer-window maf-history--stack-buffer t)
      (call-interactively 'maf-history-stack-first)
      (call-interactively 'maf-history-insert))
    (maf-history--capture)
    (cl-assert (= (length maf-history--states) 5))
    (cl-assert (= (calc-stack-size) 5))
    (cl-assert (equal (calc-top 1 'full) '(var a var-a)))
    (cl-assert (= maf-history--index 1))
    (cl-assert (eq (nth 1 maf-history--states) state))
    (cl-assert (null maf-history--hold))
    ;; The insert quit from the stack window, so that is the window
    ;; selected, point on the entry it took.
    (cl-assert (eq (progn (maf-history) (window-buffer))
                   (get-buffer maf-history--stack-buffer)))
    (cl-assert (= maf-history--index 1))
    (cl-assert (eql (maf--history-reopen-log-index) 1))
    (with-current-buffer maf-history--stack-buffer
      (cl-assert (looking-at "4:  a"))))

  ;; Restore replaces the stack and is the end of a browse: the next
  ;; one starts on the newest state, which shows what was restored.
  (with-selected-window (get-buffer-window maf-history--log-buffer t)
    (call-interactively 'maf-history-oldest)
    (call-interactively 'maf-history-restore))
  (maf-history--capture)
  ;; The restore ran from the log, so the log is selected.
  (cl-assert (eq (progn (maf-history) (window-buffer))
                 (get-buffer maf-history--log-buffer)))
  (cl-assert (= maf-history--index 0))
  (cl-assert (= (calc-stack-size) 1))

  ;; Clean up: quit the browser, pop what the test pushed, restore the
  ;; log.
  (call-interactively 'maf-history-quit)
  (fmakunbound 'maf--history-reopen-log-index)
  (calc-pop (calc-stack-size))
  (setq maf-history--states (nth 0 maf--history-reopen-stash)
        maf-history--last-raw (nth 1 maf--history-reopen-stash)
        maf-history--index (nth 2 maf--history-reopen-stash)
        maf-history--hold (nth 3 maf--history-reopen-stash)
        maf-history--focus (nth 4 maf--history-reopen-stash)))
