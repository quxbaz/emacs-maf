(maf-step
  ;; L draws a separator rule under a state's row: a line dividing the
  ;; log into stretches of work, drawn without a line of the log going
  ;; to it. The rule is the row's own underline, extended past the end
  ;; of the text to the window edge, so the log stays one row per state
  ;; and there is nothing there to step onto, count, or land point on.

  ;; The browser is two buffers on one selection. Stash the session's
  ;; log, work on a made-up one, and put it back at the end.
  (setq maf--history-sep-stash (list maf-history--states maf-history--index)
        maf-history--states (list (list (list 12) "mul" 'mafcmd-mul)
                                  (list (list 4 3) "entry")
                                  (list (list 3) nil))
        maf-history--index 0)
  (with-current-buffer (maf-history--buffer) (maf-history--render t))

  ;; L is on the log, beside the D that deletes: the two keys that edit
  ;; the log rather than browse it. The stack window inherits it, so
  ;; the mark can be set from either side.
  (cl-assert (eq (lookup-key maf-history-mode-map (kbd "L")) 'maf-history-separate))
  (cl-assert (eq (lookup-key maf-history-stack-mode-map (kbd "L"))
                 'maf-history-separate))

  (with-current-buffer (maf-history--buffer)
    ;; Mark the middle row. Point picks the state, so put it there
    ;; first — the selection stays on the newest state throughout.
    (progn (goto-char (point-min)) (forward-line 1))
    (cl-assert (= (get-text-property (point) 'maf-history-index) 1))
    (call-interactively 'maf-history-separate)
    (cl-assert (maf-history--separator (nth 1 maf-history--states)))
    ;; The selection did not move, and neither did point: the command
    ;; acted on the row under point, so that is the row it leaves it on.
    (cl-assert (= maf-history--index 0))
    (cl-assert (= (get-text-property (point) 'maf-history-index) 1))

    ;; Not one character of the buffer went to the rule -- the log
    ;; reads exactly as it did, three rows for three states.
    (cl-assert (equal (buffer-substring-no-properties (point-min) (point-max))
                      (concat "▸ - mul (mafcmd-mul)\n"
                              "  + entry\n"
                              "  · entry\n")))
    (cl-assert (= (count-lines (point-min) (point-max)) 3))

    ;; It is a face on the marked row, the terminating newline included:
    ;; the newline is where `:extend' carries the underline out to the
    ;; window edge, which is what makes the rule a full-width line
    ;; rather than a stripe under the text alone.
    (cl-assert (memq 'maf-history-separator
                     (ensure-list (get-text-property (line-end-position) 'face))))
    (cl-assert (eq (face-attribute 'maf-history-separator :extend) t))
    (cl-assert (eq (face-attribute 'maf-history-separator :underline) t))
    ;; The rows around it are untouched: the mark is one state's.
    (cl-assert (not (memq 'maf-history-separator
                          (ensure-list (get-text-property (point-min) 'face)))))
    (progn (goto-char (point-min)) (forward-line 2))
    (cl-assert (not (memq 'maf-history-separator
                          (ensure-list (get-text-property (point) 'face)))))

    ;; The rule sets no colour, so the row keeps what it already wore --
    ;; here the marker's own, under the underline.
    (progn (goto-char (point-min)) (forward-line 1) (search-forward "+")
           (backward-char 1))
    (cl-assert (equal (get-text-property (point) 'face)
                      '(maf-history-separator maf-history-added))))

  ;; The mark belongs to the state, not to a row number: a new state
  ;; landing on top shifts the log down and the rule goes with it.
  (progn (setq maf-history--states (cons (list (list 24) "mul" 'mafcmd-mul)
                                         maf-history--states))
         (with-current-buffer (maf-history--buffer) (maf-history--render t)))
  (cl-assert (maf-history--separator (nth 2 maf-history--states)))
  (with-current-buffer (maf-history--buffer)
    (progn (goto-char (point-min)) (forward-line 2))
    (cl-assert (memq 'maf-history-separator
                     (ensure-list (get-text-property (line-end-position) 'face)))))

  ;; Pressing it again on the same state takes the line off.
  (with-current-buffer (maf-history--buffer)
    (progn (goto-char (point-min)) (forward-line 2))
    (call-interactively 'maf-history-separate)
    (cl-assert (null (maf-history--separator (nth 2 maf-history--states))))
    (cl-assert (not (memq 'maf-history-separator
                          (ensure-list (get-text-property (line-end-position)
                                                          'face))))))

  ;; Off a log row -- the stack window has none -- it marks the state
  ;; the browser has selected, which is the one that window shows.
  (with-current-buffer (maf-history--stack-buffer)
    (call-interactively 'maf-history-separate)
    (cl-assert (maf-history--separator (nth maf-history--index
                                            maf-history--states))))
  (with-current-buffer (maf-history--buffer)
    (cl-assert (memq 'maf-history-separator
                     (ensure-list (get-text-property
                                   (line-end-position) 'face)))))

  ;; A deleted state takes its rule with it rather than leaving it on
  ;; whichever state slides into its row.
  (progn (with-current-buffer (maf-history--buffer)
           (call-interactively 'maf-history-delete)))
  (cl-assert (null (maf-history--separator (car maf-history--states))))
  (with-current-buffer (maf-history--buffer)
    (cl-assert (not (memq 'maf-history-separator
                          (ensure-list (get-text-property (point-min) 'face))))))

  ;; The mark lives in a slot a state need not have yet: a state made
  ;; before there was one is padded out to reach it rather than refused.
  (progn (setq maf-history--states (list (list (list 5) "mul"))
               maf-history--index 0)
         (with-current-buffer (maf-history--buffer) (maf-history--render t))
         (with-current-buffer (maf-history--buffer)
           (call-interactively 'maf-history-separate)))
  (cl-assert (equal (car maf-history--states) (list (list 5) "mul" nil t)))

  ;; An empty log has no state to mark, and says so.
  (progn (setq maf-history--states nil maf-history--index 0)
         (with-current-buffer (maf-history--buffer) (maf-history--render t)))
  (cl-assert (not (ignore-errors
                    (with-current-buffer (maf-history--buffer)
                      (call-interactively 'maf-history-separate))
                    t)))

  ;; The legend names the key, beside the other log-editing keys.
  (progn (setq maf-history--states (list (list (list 5) "mul"))
               maf-history--index 0)
         (with-current-buffer (maf-history--buffer) (maf-history--render t)))
  (with-current-buffer (maf-history--stack-buffer)
    (cl-assert (string-match-p
                "L rule"
                (substring-no-properties (format-mode-line header-line-format)))))

  ;; Put the session's log back and re-render the browser over it.
  (progn
    (setq maf-history--states (nth 0 maf--history-sep-stash)
          maf-history--index (nth 1 maf--history-sep-stash))
    (maf-history--render t)))
