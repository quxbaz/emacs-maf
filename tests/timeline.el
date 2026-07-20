(maf-step
  ;; The history log is global session state: stash it and run against
  ;; a clean one; the last form puts everything back.
  (setq maf--timeline-stash (list maf-timeline--states
                                 maf-timeline--last-raw
                                 maf-timeline-size)
        maf-timeline--states nil
        maf-timeline--last-raw nil
        maf-timeline-size 100)

  ;; Each stack change records a whole-stack state, values top first.
  (calc-wrapper (maf-push "6 x + 12"))
  (maf-timeline--capture)
  (calc-wrapper (maf-push "a + b"))
  (maf-timeline--capture)
  (cl-assert (= (length maf-timeline--states) 2))
  (cl-assert (equal (mapcar #'math-format-value
                            (nth 0 (car maf-timeline--states)))
                    (list "a + b" "6 x + 12")))

  ;; No stack change, no state.
  (maf-timeline--capture)
  (cl-assert (= (length maf-timeline--states) 2))

  ;; A selection encases atoms — new entry conses, same formulas: the
  ;; stripped values dedup against the newest state, no state recorded.
  (progn (goto-char (point-min)) (search-forward "a") (backward-char 1))
  (call-interactively 'calc-select-here)
  (maf-timeline--capture)
  (cl-assert (= (length maf-timeline--states) 2))
  (call-interactively 'calc-unselect)
  (maf-timeline--capture)
  (cl-assert (= (length maf-timeline--states) 2))

  ;; The buffer renders the newest state like the stack itself, the
  ;; entry the step produced highlighted, header showing position and
  ;; the producing command.
  (with-current-buffer (maf-timeline--buffer)
    (cl-assert (string= (buffer-substring-no-properties (point-min) (point-max))
                        "2:  6 x + 12\n1:  a + b\n"))
    (cl-assert (string-prefix-p "maf-timeline 2/2" header-line-format))
    (progn (goto-char (point-min)) (search-forward "a + b") (backward-char 1))
    (cl-assert (eq (get-text-property (point) 'face) 'maf-timeline-changed))
    (cl-assert (null (get-text-property (point-min) 'face))))

  ;; p steps to the older state; the oldest has no reference to diff
  ;; against, so nothing is highlighted. n steps back; past either end
  ;; is an error.
  (with-current-buffer (maf-timeline--buffer)
    (call-interactively 'maf-timeline-previous)
    (cl-assert (string= (buffer-substring-no-properties (point-min) (point-max))
                        "1:  6 x + 12\n"))
    (cl-assert (string-prefix-p "maf-timeline 1/2" header-line-format))
    (cl-assert (null (get-text-property (point-min) 'face)))
    (cl-assert (not (ignore-errors (call-interactively 'maf-timeline-previous) t)))
    (call-interactively 'maf-timeline-next)
    (cl-assert (string-prefix-p "maf-timeline 2/2" header-line-format))
    (cl-assert (not (ignore-errors (call-interactively 'maf-timeline-next) t))))

  ;; C-RET on an entry of an older state pushes it onto the live stack —
  ;; a copy — and the view stays on that state as the log grows under it.
  ;; (RET is the same push followed by quit-window, which would quit the
  ;; cockpit's window here.)
  (with-current-buffer (maf-timeline--buffer)
    (call-interactively 'maf-timeline-previous)
    (goto-char (point-min))
    (call-interactively 'maf-timeline-insert-stay))
  (maf-timeline--capture)
  (cl-assert (= (calc-stack-size) 3))
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "6 x + 12"))
  (cl-assert (not (eq (calc-top 1 'full)
                      (car (nth 0 (nth 2 maf-timeline--states))))))
  (with-current-buffer (maf-timeline--buffer)
    (cl-assert (string-prefix-p "maf-timeline 1/3" header-line-format))
    (cl-assert (string= (buffer-substring-no-properties (point-min) (point-max))
                        "1:  6 x + 12\n")))

  ;; r replaces the whole stack with the state shown and jumps the view
  ;; to the newest state — which now shows the restored stack.
  (with-current-buffer (maf-timeline--buffer)
    (call-interactively 'maf-timeline-restore))
  (maf-timeline--capture)
  (cl-assert (= (calc-stack-size) 1))
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "6 x + 12"))
  (with-current-buffer (maf-timeline--buffer)
    (cl-assert (string-prefix-p "maf-timeline 4/4" header-line-format)))

  ;; A single undo reverts the restore, and lands in the log as its own
  ;; step.
  (progn (setq last-command nil) (call-interactively 'maf-undo))
  (maf-timeline--capture)
  (cl-assert (= (calc-stack-size) 3))
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "6 x + 12"))
  (cl-assert (string= (math-format-value (calc-top 2 'full)) "a + b"))

  ;; The cap: shrinking maf-timeline-size trims on the next record,
  ;; dropping the oldest states.
  (setq maf-timeline-size 2)
  (calc-wrapper (maf-push "y^2"))
  (maf-timeline--capture)
  (cl-assert (= (length maf-timeline--states) 2))
  (cl-assert (string= (math-format-value (car (nth 0 (car maf-timeline--states))))
                      "y^2"))

  ;; An empty stack with no history yet is not worth a state: the log
  ;; never starts with an empty baseline. Emptying a live stack is.
  (progn (calc-pop (calc-stack-size))
         (setq maf-timeline--states nil
               maf-timeline--last-raw nil))
  (maf-timeline--capture)
  (cl-assert (null maf-timeline--states))
  (calc-wrapper (maf-push "7"))
  (maf-timeline--capture)
  (calc-pop 1)
  (maf-timeline--capture)
  (cl-assert (= (length maf-timeline--states) 2))
  (cl-assert (null (nth 0 (car maf-timeline--states))))

  ;; Put the session's log back and re-render the buffer over it.
  (progn
    (setq maf-timeline--states (nth 0 maf--timeline-stash)
          maf-timeline--last-raw (nth 1 maf--timeline-stash)
          maf-timeline-size (nth 2 maf--timeline-stash))
    (when (get-buffer "*maf-timeline*")
      (with-current-buffer "*maf-timeline*"
        (setq maf-timeline--index 0)
        (maf-timeline--render)))))
