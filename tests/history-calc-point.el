(maf-step
  ;; Calc's point across an insert and a restore from the history
  ;; browser. Both rewrite the stack from another window, where the
  ;; calc window's own point rides the edit like a marker — a push
  ;; kept its line and lost its column, a restore collapsed it to the
  ;; top of the buffer. Now both put it back: line and column on an
  ;; entry, the dot at home, and home again when the restored stack
  ;; no longer reaches the line. The log is global session state:
  ;; stash and run against a clean one; the last form puts it back.
  (setq maf--history-point-stash (list maf-history--states
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

  ;; What the user sees is the calc window's point, so that is what
  ;; each scenario sets and reads. The helpers name the calc buffer:
  ;; focusing a browser window makes its buffer current for the rest
  ;; of the form.
  (defun maf--history-point-set (line col)
    (maf--with-calc-buffer
      (select-window (get-buffer-window (current-buffer) t))
      (goto-char (point-min))
      (forward-line (1- line))
      (move-to-column col)
      (point)))
  (defun maf--history-point-get ()
    (maf--with-calc-buffer
      (save-excursion
        (goto-char (window-point (get-buffer-window (current-buffer) t)))
        (list (line-number-at-pos) (current-column)
              (buffer-substring-no-properties (line-beginning-position)
                                              (line-end-position))))))
  (defun maf--history-point-home-p ()
    (maf--with-calc-buffer
      (= (window-point (get-buffer-window (current-buffer) t))
         (maf--home-dot-position))))

  ;; Insert from a point on an entry: the push lands below every
  ;; entry, and point keeps its line and column — on the b of what is
  ;; now 3: b, one deeper than it was.
  (progn (maf--history-point-set 2 4)
         (cl-assert (equal (maf--history-point-get) '(2 4 "2:  b")))
         (maf-history)
         (call-interactively 'maf-history-focus-stack)
         (with-selected-window (get-buffer-window maf-history--stack-buffer t)
           (call-interactively 'maf-history-stack-first)
           (call-interactively 'maf-history-insert))
         (cl-assert (= (maf--with-calc-buffer (calc-stack-size)) 4))
         (cl-assert (equal (maf--history-point-get) '(2 4 "3:  b"))))
  (maf-history--capture)

  ;; Insert from home: point stays on the dot, which the push moved
  ;; down a line.
  (progn (maf--history-point-set 1 0)
         (goto-char (maf--home-dot-position))
         (cl-assert (maf--history-point-home-p))
         (maf-history)
         (call-interactively 'maf-history-focus-stack)
         (with-selected-window (get-buffer-window maf-history--stack-buffer t)
           (call-interactively 'maf-history-stack-first)
           (call-interactively 'maf-history-insert))
         (cl-assert (= (maf--with-calc-buffer (calc-stack-size)) 5))
         (cl-assert (maf--history-point-home-p)))
  (maf-history--capture)

  ;; Restore a stack the same height or taller than point's line: the
  ;; line and column come back on the new text.
  (progn (maf--history-point-set 2 4)
         (cl-assert (equal (maf--history-point-get) '(2 4 "4:  b")))
         (maf-history)
         (call-interactively 'maf-history-focus-log)
         (unless (= maf-history--index 0)
           (call-interactively 'maf-history-newest))
         (call-interactively 'maf-history-previous)
         (cl-assert (= (length (nth 0 (nth maf-history--index maf-history--states))) 4))
         (call-interactively 'maf-history-restore)
         (cl-assert (= (maf--with-calc-buffer (calc-stack-size)) 4))
         (cl-assert (equal (maf--history-point-get) '(2 4 "3:  b"))))
  (maf-history--capture)

  ;; Restore a stack too short to reach point's line: point lands at
  ;; home, on the dot, as calc parks it after a command of its own.
  (progn (maf--history-point-set 3 4)
         (cl-assert (equal (maf--history-point-get) '(3 4 "2:  c")))
         (maf-history)
         (call-interactively 'maf-history-focus-log)
         (call-interactively 'maf-history-oldest)
         (call-interactively 'maf-history-restore)
         (cl-assert (= (maf--with-calc-buffer (calc-stack-size)) 1))
         (cl-assert (maf--history-point-home-p)))

  ;; Clean up: pop what the test left, drop the helpers, restore the
  ;; log.
  (calc-pop (calc-stack-size))
  (fmakunbound 'maf--history-point-set)
  (fmakunbound 'maf--history-point-get)
  (fmakunbound 'maf--history-point-home-p)
  (setq maf-history--states (nth 0 maf--history-point-stash)
        maf-history--last-raw (nth 1 maf--history-point-stash)
        maf-history--index (nth 2 maf--history-point-stash)
        maf-history--hold (nth 3 maf--history-point-stash)
        maf-history--focus (nth 4 maf--history-point-stash)))
