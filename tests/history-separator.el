(maf-step
  ;; L draws a separator rule under a state's row: a line dividing the
  ;; log into stretches of work. The rule is a row of its own, given a
  ;; background extended past the line to the window edge, so the band
  ;; runs the log's full width and the division has a row of vertical
  ;; margin rather than sitting glued under the text. Setting one
  ;; prompts for text to write into the band, titling the stretch it
  ;; closes; an empty answer is the plain rule. Browsing is by state
  ;; rather than by line, so the extra row costs the stepping keys
  ;; nothing, and the band carries the index of the state it sits under.

  ;; The band under the log line LINE (zero-based), if there is one:
  ;; the row after it wearing the separator face. Its own text is not
  ;; part of the question -- a plain band and a titled one are the same
  ;; row -- so this reads the index it carries either way.
  (defun maf--history-sep-band (line)
    (goto-char (point-min))
    (forward-line (1+ line))
    (and (bolp)
         (memq 'maf-history-separator
               (ensure-list (get-text-property (point) 'face)))
         (get-text-property (point) 'maf-history-index)))

  ;; What the band under LINE reads, as text.
  (defun maf--history-sep-text (line)
    (goto-char (point-min))
    (forward-line (1+ line))
    (buffer-substring-no-properties (point) (line-end-position)))

  ;; A press of L answering the prompt with TEXT. Through
  ;; `call-interactively', so the command is entered the way the key
  ;; enters it and the prompt is part of what is under test.
  (defun maf--history-sep-press (text)
    (cl-letf (((symbol-function 'read-string) (lambda (&rest _) text)))
      (call-interactively 'maf-history-separate)))

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
    (maf--history-sep-press "")
    (cl-assert (maf-history--separator (nth 1 maf-history--states)))
    ;; An empty answer is the plain rule: the slot keeps the bare flag
    ;; rather than an empty string, and the band carries no text.
    (cl-assert (eq (maf-history--separator (nth 1 maf-history--states)) t))
    (cl-assert (null (maf-history--separator-label (nth 1 maf-history--states))))
    ;; The selection did not move, and neither did point: the command
    ;; acted on the row under point, so that is the row it leaves it on.
    (cl-assert (= maf-history--index 0))
    (cl-assert (= (get-text-property (point) 'maf-history-index) 1))

    ;; The rule is an empty row under the marked state -- no text of
    ;; the log goes to it, and the states read exactly as they did.
    (cl-assert (equal (buffer-substring-no-properties (point-min) (point-max))
                      (concat "▸ - mul (mafcmd-mul)\n"
                              "  + entry\n"
                              "\n"
                              "  · entry\n")))
    (cl-assert (= (count-lines (point-min) (point-max)) 4))

    ;; The band is the face on that empty row's newline, which is all
    ;; the row has: `:extend' is what carries the background from there
    ;; out to the window edge, making the rule a full-width line rather
    ;; than a stripe the width of nothing.
    (cl-assert (eql (maf--history-sep-band 1) 1))
    (cl-assert (eq (face-attribute 'maf-history-separator :extend) t))
    (cl-assert (face-attribute 'maf-history-separator :background))
    ;; The rows around it are untouched: the mark is one state's, and
    ;; the marked row keeps what it already wore -- here the marker's
    ;; own face, not the band's.
    (cl-assert (null (maf--history-sep-band 0)))
    (cl-assert (null (maf--history-sep-band 3)))
    (progn (goto-char (point-min)) (forward-line 1) (search-forward "+")
           (backward-char 1))
    (cl-assert (equal (get-text-property (point) 'face) 'maf-history-added))

    ;; Stepping is by state rather than by line, so the extra row is
    ;; not a stop on the way: the log's own motion keys skip it.
    (progn (goto-char (point-min)) (call-interactively 'maf-history-previous))
    (cl-assert (= maf-history--index 1))
    (cl-assert (= (get-text-property (point) 'maf-history-index) 1))
    (cl-assert (not (looking-at-p "$")))
    (progn (call-interactively 'maf-history-next))
    (cl-assert (= maf-history--index 0)))

  ;; The mark belongs to the state, not to a row number: a new state
  ;; landing on top shifts the log down and the rule goes with it.
  (progn (setq maf-history--states (cons (list (list 24) "mul" 'mafcmd-mul)
                                         maf-history--states))
         (with-current-buffer (maf-history--buffer) (maf-history--render t)))
  (cl-assert (maf-history--separator (nth 2 maf-history--states)))
  (with-current-buffer (maf-history--buffer)
    (cl-assert (eql (maf--history-sep-band 2) 2)))

  ;; Pressing it again on the same state takes the line off. The press
  ;; that removes a rule has no text to ask for, so it does not prompt
  ;; -- `call-interactively' with no answer prepared would hang here if
  ;; it did.
  (with-current-buffer (maf-history--buffer)
    (progn (goto-char (point-min)) (forward-line 2))
    (call-interactively 'maf-history-separate)
    (cl-assert (null (maf-history--separator (nth 2 maf-history--states))))
    (cl-assert (null (maf--history-sep-band 2))))

  ;; Answering the prompt writes the text into the band. It is the same
  ;; row doing the same dividing -- still banded, still carrying its
  ;; state's index, so browsing over it is unchanged -- with the text
  ;; centred in the row.
  (with-current-buffer (maf-history--buffer)
    (progn (goto-char (point-min)) (forward-line 2))
    (maf--history-sep-press "morning")
    (cl-assert (equal (maf-history--separator (nth 2 maf-history--states))
                      "morning"))
    (cl-assert (equal (maf-history--separator-label (nth 2 maf-history--states))
                      "morning"))
    (cl-assert (eql (maf--history-sep-band 2) 2))
    ;; One space in the buffer ahead of the text, not a run of padding:
    ;; the centring is a display stretch on that space, measured at
    ;; redisplay against the window, so the title re-centres when the
    ;; window is resized rather than holding a column count worked out
    ;; when the log was rendered. Half the text's width left of centre
    ;; is where text of that width starts if it is to straddle it, and
    ;; a column further left again is the optical nudge -- the log's
    ;; rows start a gutter in, so measured centre reads right of it.
    (cl-assert (equal (maf--history-sep-text 2) " morning"))
    (progn (goto-char (point-min)) (forward-line 3))
    (cl-assert (equal (get-text-property (point) 'display)
                      (list 'space :align-to
                            (list '- 'center
                                  (+ (/ (string-width "morning") 2.0) 1)))))
    ;; The text wears the band, so it reads on it rather than in the
    ;; default foreground over it. The stretch ahead of it wears it
    ;; too, so the band is unbroken up to where the title starts.
    (cl-assert (memq 'maf-history-separator
                     (ensure-list (get-text-property (point) 'face))))
    (progn (forward-char 1))
    (cl-assert (looking-at-p "morning"))
    (cl-assert (memq 'maf-history-separator
                     (ensure-list (get-text-property (point) 'face))))
    (cl-assert (face-attribute 'maf-history-separator :foreground))
    ;; Off again, and the text goes with the rule: the next one asks
    ;; afresh rather than keeping what this one was called.
    (progn (goto-char (point-min)) (forward-line 2))
    (call-interactively 'maf-history-separate)
    (cl-assert (null (maf-history--separator (nth 2 maf-history--states))))
    (maf--history-sep-press "")
    (cl-assert (eq (maf-history--separator (nth 2 maf-history--states)) t))
    (progn (goto-char (point-min)) (forward-line 2))
    (call-interactively 'maf-history-separate))

  ;; Off a log row -- the stack window has none -- it marks the state
  ;; the browser has selected, which is the one that window shows.
  (with-current-buffer (maf-history--stack-buffer)
    (maf--history-sep-press "")
    (cl-assert (maf-history--separator (nth maf-history--index
                                            maf-history--states))))
  (with-current-buffer (maf-history--buffer)
    (cl-assert (eql (maf--history-sep-band 0) 0)))

  ;; A deleted state takes its rule with it rather than leaving it on
  ;; whichever state slides into its row.
  (progn (with-current-buffer (maf-history--buffer)
           (call-interactively 'maf-history-delete)))
  (cl-assert (null (maf-history--separator (car maf-history--states))))
  (with-current-buffer (maf-history--buffer)
    (cl-assert (null (maf--history-sep-band 0))))

  ;; The mark lives in a slot a state need not have yet: a state made
  ;; before there was one is padded out to reach it rather than refused.
  (progn (setq maf-history--states (list (list (list 5) "mul"))
               maf-history--index 0)
         (with-current-buffer (maf-history--buffer) (maf-history--render t))
         (with-current-buffer (maf-history--buffer)
           (maf--history-sep-press "")))
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
