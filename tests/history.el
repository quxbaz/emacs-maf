(maf-step
  ;; The history log is global session state, the selection into it
  ;; included: stash both and run against a clean one; the last form
  ;; puts everything back.
  (setq maf--history-stash (list maf-history--states
                                 maf-history--last-raw
                                 maf-history-size
                                 maf-history--index)
        maf-history--states nil
        maf-history--last-raw nil
        maf-history-size 100
        maf-history--index 0)

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

  ;; The browser is two buffers: the action log, one line per state,
  ;; oldest at the top with the current one marked, and beside it the
  ;; stack that state left, the entry the step produced highlighted.
  ;; The log header carries the position counter; the stack header
  ;; carries the key legend, dial-style. Both steps read `new' (each
  ;; added an entry).
  (with-current-buffer (maf-history--buffer)
    (cl-assert (equal (buffer-substring-no-properties (point-min) (point-max))
                      "▸ + new\n  · new\n"))
    (cl-assert (equal header-line-format "maf-history  2/2"))
    ;; Point rests on the current state's line, and every line names
    ;; its state.
    (cl-assert (= (line-number-at-pos) 1))
    (cl-assert (= (get-text-property (point) 'maf-history-index) 0))
    (progn (forward-line 1)
           (cl-assert (= (get-text-property (point) 'maf-history-index) 1))))
  (with-current-buffer (maf-history--stack-buffer)
    (cl-assert (equal (buffer-substring-no-properties (point-min) (point-max))
                      "2:  6 x + 12\n1:  a + b\n"))
    (cl-assert (string-match-p
                " n/p move .* TAB/o/t switch .* r restore .* D delete .* q quit"
                (format-mode-line header-line-format)))
    ;; The entry this step produced is highlighted; the one carried
    ;; over from the state before is not.
    (progn (goto-char (point-min)) (search-forward "a + b") (backward-char 1))
    (cl-assert (eq (get-text-property (point) 'face) 'maf-history-changed))
    (progn (goto-char (point-min)) (search-forward "6 x + 12") (backward-char 1))
    (cl-assert (null (get-text-property (point) 'face))))

  ;; u steps to the older state: the log marker moves onto it, point
  ;; with it, the header counts 1/2, and the stack beside it re-renders
  ;; to that state — the oldest, with no reference to diff against, so
  ;; nothing in it is highlighted. i steps back; past either end is an
  ;; error.
  (with-current-buffer (maf-history--buffer)
    (call-interactively 'maf-history-previous)
    (cl-assert (equal header-line-format "maf-history  1/2"))
    (cl-assert (equal (buffer-substring-no-properties (point-min) (point-max))
                      "  + new\n▸ · new\n"))
    (cl-assert (= (line-number-at-pos) 2)))
  (with-current-buffer (maf-history--stack-buffer)
    (cl-assert (equal (buffer-substring-no-properties (point-min) (point-max))
                      "1:  6 x + 12\n"))
    (progn (goto-char (point-min)))
    (cl-assert (null (get-text-property (point) 'face))))
  (with-current-buffer (maf-history--buffer)
    (cl-assert (not (ignore-errors (call-interactively 'maf-history-previous) t)))
    (call-interactively 'maf-history-next)
    (cl-assert (equal header-line-format "maf-history  2/2"))
    (cl-assert (not (ignore-errors (call-interactively 'maf-history-next) t))))

  ;; In the log every line is a state, so all of n/p/j/k step, and
  ;; they follow the display rather than the clock: with the log
  ;; newest-first, j/n walk down into older states and k/p walk back
  ;; up. Driving them through the keymap steps and back.
  (with-current-buffer (maf-history--buffer)
    (cl-assert (eq (lookup-key maf-history-mode-map (kbd "j")) 'maf-history-previous))
    (cl-assert (eq (lookup-key maf-history-mode-map (kbd "n")) 'maf-history-previous))
    (cl-assert (eq (lookup-key maf-history-mode-map (kbd "k")) 'maf-history-next))
    (cl-assert (eq (lookup-key maf-history-mode-map (kbd "p")) 'maf-history-next))
    (call-interactively (lookup-key maf-history-mode-map (kbd "j")))
    (cl-assert (equal header-line-format "maf-history  1/2"))
    (call-interactively (lookup-key maf-history-mode-map (kbd "k")))
    (cl-assert (equal header-line-format "maf-history  2/2")))

  ;; The stack map inherits the log's, but overrides every motion key:
  ;; in the stack they move between the entries shown rather than
  ;; between states, so the keys always act on the window the hand is
  ;; in.
  (dolist (cell '(("n" . next-line) ("j" . next-line)
                  ("p" . previous-line) ("k" . previous-line)
                  ("<" . maf-history-stack-first)
                  (">" . maf-history-stack-last)
                  ;; The same two under a modifier, and the two Emacs
                  ;; puts the ends of a buffer on.
                  ("M-<" . maf-history-stack-first)
                  ("M->" . maf-history-stack-last)
                  ("RET" . maf-history-insert)))
    (cl-assert (eq (lookup-key maf-history-stack-mode-map (kbd (car cell)))
                   (cdr cell))
               nil "stack key %s should run %s" (car cell) (cdr cell)))
  ;; RET takes what the row names: the whole state in the log, one
  ;; entry of it in the stack.
  (cl-assert (eq (lookup-key maf-history-mode-map (kbd "RET")) 'maf-history-restore))
  ;; What the stack does not override is inherited and works from
  ;; either window.
  (dolist (cell '(("t" . maf-history-switch) ("r" . maf-history-restore)
                  ("D" . maf-history-delete) ("q" . maf-history-quit)))
    (cl-assert (eq (lookup-key maf-history-stack-mode-map (kbd (car cell)))
                   (cdr cell))
               nil "stack key %s should inherit %s" (car cell) (cdr cell)))
  ;; In the log the ends follow the display, as the motion keys do:
  ;; < reaches the top of a newest-first log, > the bottom.
  (cl-assert (eq (lookup-key maf-history-mode-map (kbd "<")) 'maf-history-newest))
  (cl-assert (eq (lookup-key maf-history-mode-map (kbd ">")) 'maf-history-oldest))
  (cl-assert (eq (lookup-key maf-history-mode-map (kbd "M-<")) 'maf-history-newest))
  (cl-assert (eq (lookup-key maf-history-mode-map (kbd "M->")) 'maf-history-oldest))
  ;; Retired keys stay retired: none of them still runs a browsing
  ;; command. They are not asserted unbound — special-mode keeps its
  ;; own claim on some (h is `describe-mode'), which is what should
  ;; show through once ours is gone.
  (dolist (key '("u" "i" "h" "l" "v" "G"))
    (cl-assert (not (memq (lookup-key maf-history-mode-map (kbd key))
                          '(maf-history-previous maf-history-next
                            maf-history-oldest maf-history-newest
                            maf-history-switch maf-history-focus-log
                            maf-history-focus-stack maf-history-visit-calc)))
               nil "key %s should no longer run a browsing command" key))

  ;; < reaches the newest state, and C-M-k clears the log.
  (with-current-buffer (maf-history--buffer)
    (cl-assert (eq (lookup-key maf-history-mode-map (kbd "C-M-k")) 'maf-history-clear))
    (call-interactively 'maf-history-previous)
    (call-interactively (lookup-key maf-history-mode-map (kbd "<")))
    (cl-assert (zerop maf-history--index)))

  ;; Invoking maf-history always lands on the newest state, wherever a
  ;; previous browse left the view.
  (with-current-buffer (maf-history--buffer)
    (call-interactively 'maf-history-previous))
  (save-window-excursion (call-interactively 'maf-history))
  (with-current-buffer (maf-history--buffer)
    (cl-assert (zerop maf-history--index)))

  ;; C-RET on an entry in the stack window pushes it onto the live
  ;; stack — a copy — and the browser stays on that state as the log
  ;; grows under it. (RET is the same push followed by a quit, which
  ;; would take down the cockpit's window here.)
  (with-current-buffer (maf-history--buffer)
    (call-interactively 'maf-history-previous))
  (with-current-buffer (maf-history--stack-buffer)
    ;; Point onto the entry itself so C-RET has a history value to push.
    (progn (goto-char (point-min)) (search-forward "6 x + 12") (backward-char 1))
    (call-interactively 'maf-history-insert-stay))
  (maf-history--capture)
  (cl-assert (= (calc-stack-size) 3))
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "6 x + 12"))
  (cl-assert (not (eq (calc-top 1 'full)
                      (car (nth 0 (nth 2 maf-history--states))))))
  (with-current-buffer (maf-history--buffer)
    ;; The log: the two original steps (new) plus the history insert
    ;; (hist) as the newest, bottom line; the marker stays on the
    ;; oldest state, the log growing under it.
    (cl-assert (equal (buffer-substring-no-properties (point-min) (point-max))
                      "  + hist\n  + new\n▸ · new\n"))
    (cl-assert (equal header-line-format "maf-history  1/3")))
  (with-current-buffer (maf-history--stack-buffer)
    ;; The stack still shows the selected (oldest) state, not the live one.
    (cl-assert (equal (buffer-substring-no-properties (point-min) (point-max))
                      "1:  6 x + 12\n")))

  ;; r replaces the whole stack with the state shown, jumps the view to
  ;; the newest state — which now shows the restored stack — and quits
  ;; the browser; the excursion keeps the quit off the cockpit's window.
  (save-window-excursion
    (with-current-buffer (maf-history--buffer)
      (call-interactively 'maf-history-restore)))
  (maf-history--capture)
  (cl-assert (= (calc-stack-size) 1))
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "6 x + 12"))
  (with-current-buffer (maf-history--buffer)
    (cl-assert (equal header-line-format "maf-history  4/4")))

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

  ;; Beside the label, a state carries the command the change landed
  ;; under. The label names the operation — a trail prefix like "fctr",
  ;; or a structural reading — and the command names the code that ran,
  ;; which no trail prefix says.
  (progn (calc-wrapper (maf-push "z"))
         (let ((this-command 'my-fake-command)) (maf-history--capture))
         (cl-assert (eq (nth 2 (car maf-history--states)) 'my-fake-command)))

  ;; Put the session's log back and re-render the browser over it.
  (progn
    (setq maf-history--states (nth 0 maf--history-stash)
          maf-history--last-raw (nth 1 maf--history-stash)
          maf-history-size (nth 2 maf--history-stash)
          maf-history--index (nth 3 maf--history-stash))
    (maf-history--render t)))
