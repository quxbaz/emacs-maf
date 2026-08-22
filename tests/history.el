(maf-step
  ;; The history log is global session state: stash it and run against
  ;; a clean one; the last form puts everything back.
  (setq maf--history-stash (list maf-history--states
                                 maf-history--last-raw
                                 maf-history-size)
        maf-history--states nil
        maf-history--last-raw nil
        maf-history-size 100)

  ;; Each stack change records a whole-stack state, values top first.
  (calc-wrapper (maf-push "6 x + 12"))
  (maf-history--capture)
  (calc-wrapper (maf-push "a + b"))
  (maf-history--capture)
  (cl-assert (= (length maf-history--states) 2))
  (cl-assert (equal (mapcar #'math-format-value
                            (nth 0 (car maf-history--states)))
                    (list "a + b" "6 x + 12")))

  ;; No stack change, no state.
  (maf-history--capture)
  (cl-assert (= (length maf-history--states) 2))

  ;; A selection encases atoms — new entry conses, same formulas: the
  ;; stripped values dedup against the newest state, no state recorded.
  (progn (goto-char (point-min)) (search-forward "a") (backward-char 1))
  (call-interactively 'calc-select-here)
  (maf-history--capture)
  (cl-assert (= (length maf-history--states) 2))
  (call-interactively 'calc-unselect)
  (maf-history--capture)
  (cl-assert (= (length maf-history--states) 2))

  ;; The buffer renders the newest state like the stack itself, the
  ;; entry the step produced highlighted, header showing position and
  ;; the producing command. A key legend heads the buffer, dial-style;
  ;; the operation strip sits above the stack, both steps labeled `new'
  ;; (each added an entry).
  (with-current-buffer (maf-history--buffer)
    (let ((text (buffer-substring-no-properties (point-min) (point-max))))
      (cl-assert (string-match-p "\\` h/l/u/i step .* r restore .* D delete " text))
      (cl-assert (string-suffix-p "new · new\n\n2:  6 x + 12\n1:  a + b\n" text)))
    (cl-assert (string-prefix-p "maf-history 2/2" header-line-format))
    (progn (goto-char (point-min)) (search-forward "a + b") (backward-char 1))
    (cl-assert (eq (get-text-property (point) 'face) 'maf-history-changed))
    ;; The unchanged entry carries no highlight.
    (progn (goto-char (point-min)) (search-forward "6 x + 12") (backward-char 1))
    (cl-assert (null (get-text-property (point) 'face))))

  ;; p steps to the older state; the oldest has no reference to diff
  ;; against, so nothing is highlighted. n steps back; past either end
  ;; is an error.
  (with-current-buffer (maf-history--buffer)
    (call-interactively 'maf-history-previous)
    (cl-assert (string-suffix-p "new · new\n\n1:  6 x + 12\n"
                                (buffer-substring-no-properties (point-min) (point-max))))
    (cl-assert (string-prefix-p "maf-history 1/2" header-line-format))
    (progn (goto-char (point-min)) (search-forward "6 x + 12") (backward-char 1))
    (cl-assert (null (get-text-property (point) 'face)))
    (cl-assert (not (ignore-errors (call-interactively 'maf-history-previous) t)))
    (call-interactively 'maf-history-next)
    (cl-assert (string-prefix-p "maf-history 2/2" header-line-format))
    (cl-assert (not (ignore-errors (call-interactively 'maf-history-next) t))))

  ;; h/l are bound to older/newer navigation too, matching u/i. Driving
  ;; them through the keymap steps the view and back.
  (with-current-buffer (maf-history--buffer)
    (cl-assert (eq (lookup-key maf-history-mode-map (kbd "h")) 'maf-history-previous))
    (cl-assert (eq (lookup-key maf-history-mode-map (kbd "l")) 'maf-history-next))
    (call-interactively (lookup-key maf-history-mode-map (kbd "h")))
    (cl-assert (string-prefix-p "maf-history 1/2" header-line-format))
    (call-interactively (lookup-key maf-history-mode-map (kbd "l")))
    (cl-assert (string-prefix-p "maf-history 2/2" header-line-format)))

  ;; C-RET on an entry of an older state pushes it onto the live stack —
  ;; a copy — and the view stays on that state as the log grows under it.
  ;; (RET is the same push followed by quit-window, which would quit the
  ;; cockpit's window here.)
  (with-current-buffer (maf-history--buffer)
    (call-interactively 'maf-history-previous)
    ;; Point onto the entry itself (past the strip) so RET/C-RET have a
    ;; history value to push.
    (progn (goto-char (point-min)) (search-forward "6 x + 12") (backward-char 1))
    (call-interactively 'maf-history-insert-stay))
  (maf-history--capture)
  (cl-assert (= (calc-stack-size) 3))
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "6 x + 12"))
  (cl-assert (not (eq (calc-top 1 'full)
                      (car (nth 0 (nth 2 maf-history--states))))))
  (with-current-buffer (maf-history--buffer)
    (cl-assert (string-prefix-p "maf-history 1/3" header-line-format))
    ;; Strip: the two original steps (new) plus the history insert (hist),
    ;; newest last; the view stays on the oldest, single-entry state.
    (cl-assert (string-suffix-p "new · new · hist\n\n1:  6 x + 12\n"
                                (buffer-substring-no-properties (point-min) (point-max)))))

  ;; r replaces the whole stack with the state shown, jumps the view to
  ;; the newest state — which now shows the restored stack — and quits
  ;; the window; the excursion keeps the quit off the cockpit's window.
  (save-window-excursion
    (with-current-buffer (maf-history--buffer)
      (call-interactively 'maf-history-restore)))
  (maf-history--capture)
  (cl-assert (= (calc-stack-size) 1))
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "6 x + 12"))
  (with-current-buffer (maf-history--buffer)
    (cl-assert (string-prefix-p "maf-history 4/4" header-line-format)))

  ;; A single undo reverts the restore, and lands in the log as its own
  ;; step.
  (progn (setq last-command nil) (call-interactively 'maf-undo))
  (maf-history--capture)
  (cl-assert (= (calc-stack-size) 3))
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "6 x + 12"))
  (cl-assert (string= (math-format-value (calc-top 2 'full)) "a + b"))

  ;; The cap: shrinking maf-history-size trims on the next record,
  ;; dropping the oldest states.
  (setq maf-history-size 2)
  (calc-wrapper (maf-push "y^2"))
  (maf-history--capture)
  (cl-assert (= (length maf-history--states) 2))
  (cl-assert (string= (math-format-value (car (nth 0 (car maf-history--states))))
                      "y^2"))

  ;; An empty stack with no history yet is not worth a state: the log
  ;; never starts with an empty baseline. Emptying a live stack is.
  (progn (calc-pop (calc-stack-size))
         (setq maf-history--states nil
               maf-history--last-raw nil))
  (maf-history--capture)
  (cl-assert (null maf-history--states))
  (calc-wrapper (maf-push "7"))
  (maf-history--capture)
  (calc-pop 1)
  (maf-history--capture)
  (cl-assert (= (length maf-history--states) 2))
  (cl-assert (null (nth 0 (car maf-history--states))))

  ;; Put the session's log back and re-render the buffer over it.
  (progn
    (setq maf-history--states (nth 0 maf--history-stash)
          maf-history--last-raw (nth 1 maf--history-stash)
          maf-history-size (nth 2 maf--history-stash))
    (when (get-buffer "*maf-history*")
      (with-current-buffer "*maf-history*"
        (setq maf-history--index 0)
        (maf-history--render)))))
