;; -*- lexical-binding: t; -*-
;;
;; maf-history-insert-state: C-RET on a log row adds that whole state
;; to the live stack rather than replacing it, and leaves the browser
;; open.

(maf-step
  ;; The history log is global session state, the selection into it
  ;; included: stash and run against a clean one; the last form puts
  ;; everything back. The browser's windows open below calc here and
  ;; are quit again at the end.
  (setq maf--history-insert-stash (list maf-history--states
                                        maf-history--last-raw
                                        maf-history-size
                                        maf-history--index
                                        maf-history--hold
                                        maf-history--focus)
        maf-history--states nil
        maf-history--last-raw nil
        maf-history-size 100
        maf-history--index 0
        maf-history--hold nil
        maf-history--focus nil)
  (calc-pop (calc-stack-size))

  ;; Three states, each one entry deeper than the last.
  (calc-wrapper (maf-push "a + b"))
  (maf-history--capture)
  (calc-wrapper (maf-push "6 x"))
  (maf-history--capture)
  (calc-wrapper (maf-push "z^2"))
  (maf-history--capture)
  (cl-assert (= (length maf-history--states) 3))

  ;; C-RET runs the command from the log; the stack window keeps its
  ;; own C-RET, the one-entry push.
  (cl-assert (eq (lookup-key maf-history-mode-map (kbd "C-<return>"))
                 'maf-history-insert-state))
  (cl-assert (eq (lookup-key maf-history-stack-mode-map (kbd "C-<return>"))
                 'maf-history-insert-stay))

  ;; Open the browser for real: whether it is still open is the thing
  ;; under test. Select the oldest state — the one holding just
  ;; "a + b" — and insert it.
  (progn (maf-history) nil)
  (cl-assert (get-buffer-window maf-history--log-buffer t))
  (with-current-buffer (maf-history--buffer)
    (call-interactively 'maf-history-oldest)
    (cl-assert (= maf-history--index 2)))
  (cl-assert (= (calc-stack-size) 3))
  ;; Put calc's point up on an entry first, so parking it at home is a
  ;; move that shows. Run the command from the log window: the focus
  ;; must still be there when it returns.
  (progn (calc-cursor-stack-index 2)
         (cl-assert (not (maf--at-home-p)))
         nil)
  (with-selected-window (get-buffer-window maf-history--log-buffer t)
    (call-interactively 'maf-history-insert-state)
    (cl-assert (eq (window-buffer (selected-window))
                   (get-buffer maf-history--log-buffer))))
  (maf-history--capture)

  ;; Calc's point is at home, in the buffer and in the window showing
  ;; it — the window keeps its own point, so both are checked.
  (cl-assert (maf--at-home-p))
  (cl-assert (= (point) (maf--home-dot-position)))
  (cl-assert (= (window-point (get-buffer-window (current-buffer) t))
                (maf--home-dot-position)))

  ;; The browser is still up, both windows of it.
  (cl-assert (get-buffer-window maf-history--log-buffer t))
  (cl-assert (get-buffer-window maf-history--stack-buffer t))

  ;; Nothing was deleted: the three live entries stand, with the
  ;; state's single entry added on top.
  (cl-assert (= (calc-stack-size) 4))
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "a + b"))
  (cl-assert (string= (math-format-value (calc-top 2 'full)) "z^2"))
  (cl-assert (string= (math-format-value (calc-top 3 'full)) "6 x"))
  (cl-assert (string= (math-format-value (calc-top 4 'full)) "a + b"))

  ;; A copy, not the history's own value: editing the live entry can
  ;; never reach back into the log.
  (cl-assert (not (eq (calc-top 1 'full)
                      (car (nth 0 (nth 3 maf-history--states))))))

  ;; The view held on the state it inserted from as the log grew under
  ;; it, and the stack window still shows that state rather than the
  ;; live one.
  (cl-assert (= (length maf-history--states) 4))
  (cl-assert (= maf-history--index 3))
  (with-current-buffer (maf-history--stack-buffer)
    (cl-assert (equal (buffer-substring-no-properties (point-min) (point-max))
                      "1:  a + b\n")))

  ;; A single undo takes the whole insert back off.
  (progn (setq last-command nil) (call-interactively 'maf-undo))
  (maf-history--capture)
  (cl-assert (= (calc-stack-size) 3))
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "z^2"))

  ;; A multi-entry state goes on whole, in its own order: the state
  ;; holding 6 x over a + b arrives with the top of the snapshot on
  ;; top. No reopening in between — the browser never closed.
  (with-current-buffer (maf-history--buffer)
    (call-interactively 'maf-history-newest)
    (call-interactively 'maf-history-previous)
    (call-interactively 'maf-history-previous)
    (call-interactively 'maf-history-previous)
    (cl-assert (= (length (nth 0 (nth maf-history--index maf-history--states)))
                  2))
    (call-interactively 'maf-history-insert-state))
  (maf-history--capture)
  (cl-assert (= (calc-stack-size) 5))
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "6 x"))
  (cl-assert (string= (math-format-value (calc-top 2 'full)) "a + b"))
  (cl-assert (string= (math-format-value (calc-top 3 'full)) "z^2"))
  (cl-assert (get-buffer-window maf-history--log-buffer t))

  ;; An empty snapshot refuses rather than doing nothing quietly.
  (progn (calc-pop (calc-stack-size))
         (let ((this-command 'maf-erase)) (maf-history--capture))
         (calc-wrapper (maf-push "w"))
         (maf-history--capture))
  (with-current-buffer (maf-history--buffer)
    (call-interactively 'maf-history-newest)
    (call-interactively 'maf-history-previous)
    (cl-assert (null (nth 0 (nth maf-history--index maf-history--states))))
    (cl-assert (condition-case nil
                   (progn (call-interactively 'maf-history-insert-state) nil)
                 (user-error t))))
  (cl-assert (= (calc-stack-size) 1))
  (cl-assert (get-buffer-window maf-history--log-buffer t))

  ;; Quit is still the way out, and takes both windows down.
  (with-current-buffer (maf-history--buffer)
    (call-interactively 'maf-history-quit))
  (cl-assert (null (get-buffer-window maf-history--log-buffer t)))
  (cl-assert (null (get-buffer-window maf-history--stack-buffer t)))

  ;; Put the session's log back and re-render the browser over it.
  (progn
    (calc-pop (calc-stack-size))
    (setq maf-history--states (nth 0 maf--history-insert-stash)
          maf-history--last-raw (nth 1 maf--history-insert-stash)
          maf-history-size (nth 2 maf--history-insert-stash)
          maf-history--index (nth 3 maf--history-insert-stash)
          maf-history--hold (nth 4 maf--history-insert-stash)
          maf-history--focus (nth 5 maf--history-insert-stash))
    (maf-history--render t)))
