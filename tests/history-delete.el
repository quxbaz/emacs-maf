(maf-step
  ;; The history log is global session state: stash it and run against
  ;; a clean one; the last form puts everything back.
  (setq maf--history-del-stash (list maf-history--states
                                      maf-history--last-raw)
        maf-history--states nil
        maf-history--last-raw nil)

  ;; Three states to delete from, values top first: (9 7 5), (7 5), (5).
  (calc-wrapper (maf-push "5"))
  (maf-history--capture)
  (calc-wrapper (maf-push "7"))
  (maf-history--capture)
  (calc-wrapper (maf-push "9"))
  (maf-history--capture)
  (cl-assert (= (length maf-history--states) 3))

  ;; D on the middle state removes just that state: the live stack is
  ;; untouched and the view lands on the next older state, position 1/2.
  (with-current-buffer (maf-history--buffer)
    (setq maf-history--index 0)
    (maf-history--render)
    (call-interactively 'maf-history-previous)
    (cl-assert (string-match-p "^2/3\n" (buffer-substring-no-properties (point-min) (point-max))))
    (call-interactively 'maf-history-delete)
    (cl-assert (string-match-p "^1/2\n" (buffer-substring-no-properties (point-min) (point-max)))))
  (cl-assert (= (calc-stack-size) 3))
  (cl-assert (equal (mapcar (lambda (s) (math-format-value (car (nth 0 s))))
                            maf-history--states)
                    '("9" "5")))

  ;; Deleting the newest leaves the view on the newest remaining, and a
  ;; capture does not re-record it: the live stack has not changed.
  (with-current-buffer (maf-history--buffer)
    (call-interactively 'maf-history-newest)
    (call-interactively 'maf-history-delete)
    (cl-assert (string-match-p "^1/1\n" (buffer-substring-no-properties (point-min) (point-max)))))
  (maf-history--capture)
  (cl-assert (= (length maf-history--states) 1))

  ;; Deleting the last state empties the log; D on an empty log signals
  ;; rather than crashing.
  (with-current-buffer (maf-history--buffer)
    (call-interactively 'maf-history-delete)
    (cl-assert (null maf-history--states))
    ;; No states: no counter line, the header just the title, the body
    ;; saying so.
    (cl-assert (equal header-line-format "maf-history"))
    (cl-assert (string-match-p "\\` h/l/u/i step"
                               (buffer-substring-no-properties (point-min) (point-max))))
    (cl-assert (string-match-p "(no states yet)"
                               (buffer-substring-no-properties (point-min) (point-max))))
    (cl-assert (not (ignore-errors (call-interactively 'maf-history-delete) t))))

  ;; Put the stack and the session's log back, re-rendering over it.
  (progn
    (calc-pop (calc-stack-size))
    (setq maf-history--states (nth 0 maf--history-del-stash)
          maf-history--last-raw (nth 1 maf--history-del-stash))
    (when (get-buffer "*maf-history*")
      (with-current-buffer "*maf-history*"
        (setq maf-history--index 0)
        (maf-history--render)))))
