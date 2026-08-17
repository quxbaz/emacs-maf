(maf-step
  ;; The history log is global session state: stash it and run against
  ;; a clean one; the last form puts everything back.
  (setq maf--timeline-del-stash (list maf-timeline--states
                                      maf-timeline--last-raw)
        maf-timeline--states nil
        maf-timeline--last-raw nil)

  ;; Three states to delete from, values top first: (9 7 5), (7 5), (5).
  (calc-wrapper (maf-push "5"))
  (maf-timeline--capture)
  (calc-wrapper (maf-push "7"))
  (maf-timeline--capture)
  (calc-wrapper (maf-push "9"))
  (maf-timeline--capture)
  (cl-assert (= (length maf-timeline--states) 3))

  ;; D on the middle state removes just that state: the live stack is
  ;; untouched and the view lands on the next older state, position 1/2.
  (with-current-buffer (maf-timeline--buffer)
    (setq maf-timeline--index 0)
    (maf-timeline--render)
    (call-interactively 'maf-timeline-previous)
    (cl-assert (string-prefix-p "maf-timeline 2/3" header-line-format))
    (call-interactively 'maf-timeline-delete)
    (cl-assert (string-prefix-p "maf-timeline 1/2" header-line-format)))
  (cl-assert (= (calc-stack-size) 3))
  (cl-assert (equal (mapcar (lambda (s) (math-format-value (car (nth 0 s))))
                            maf-timeline--states)
                    '("9" "5")))

  ;; Deleting the newest leaves the view on the newest remaining, and a
  ;; capture does not re-record it: the live stack has not changed.
  (with-current-buffer (maf-timeline--buffer)
    (call-interactively 'maf-timeline-newest)
    (call-interactively 'maf-timeline-delete)
    (cl-assert (string-prefix-p "maf-timeline 1/1" header-line-format)))
  (maf-timeline--capture)
  (cl-assert (= (length maf-timeline--states) 1))

  ;; Deleting the last state empties the log; D on an empty log signals
  ;; rather than crashing.
  (with-current-buffer (maf-timeline--buffer)
    (call-interactively 'maf-timeline-delete)
    (cl-assert (null maf-timeline--states))
    (cl-assert (equal header-line-format "maf-timeline: no states yet"))
    (cl-assert (not (ignore-errors (call-interactively 'maf-timeline-delete) t))))

  ;; Put the stack and the session's log back, re-rendering over it.
  (progn
    (calc-pop (calc-stack-size))
    (setq maf-timeline--states (nth 0 maf--timeline-del-stash)
          maf-timeline--last-raw (nth 1 maf--timeline-del-stash))
    (when (get-buffer "*maf-timeline*")
      (with-current-buffer "*maf-timeline*"
        (setq maf-timeline--index 0)
        (maf-timeline--render)))))
