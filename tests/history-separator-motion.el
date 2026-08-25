(maf-step
  ;; M-n and M-p step between the rules rather than between the states:
  ;; the step keys under a modifier, moving the same way -- older down,
  ;; newer up, the log running newest-first -- but a sitting at a time.
  ;; They land on the state a rule sits under, which is the state the
  ;; rule belongs to.

  ;; The browser is two buffers on one selection. Stash the session's
  ;; log, work on a made-up one, and put it back at the end. Ten states,
  ;; rules under 2, 5 and 6 -- two of them adjacent, so a step of one
  ;; cannot be mistaken for a step to the far side of a gap.
  (setq maf--history-motion-stash (list maf-history--states maf-history--index)
        maf-history--states (cl-loop for i below 10
                                     collect (list (list i) "mul" 'mafcmd-mul))
        maf-history--index 0)
  (progn (dolist (i '(2 5 6))
           (maf-history--set-separator (nth i maf-history--states) t))
         (with-current-buffer (maf-history--buffer) (maf-history--render t)))

  ;; The log binds them, and the stack window inherits them as it
  ;; inherits L -- its map's parent is the log's -- so the jump can be
  ;; made from either side of one selection. Its own n and p still
  ;; override the parent's, moving by line within the stack.
  (cl-assert (eq (lookup-key maf-history-mode-map (kbd "M-n"))
                 'maf-history-previous-separator))
  (cl-assert (eq (lookup-key maf-history-mode-map (kbd "M-p"))
                 'maf-history-next-separator))
  (cl-assert (eq (keymap-parent maf-history-stack-mode-map)
                 maf-history-mode-map))
  (cl-assert (eq (lookup-key maf-history-stack-mode-map (kbd "M-n"))
                 'maf-history-previous-separator))
  (cl-assert (eq (lookup-key maf-history-stack-mode-map (kbd "n")) 'next-line))

  ;; M-n walks down the log, rule to rule, and stops at the last one
  ;; rather than wrapping.
  (with-current-buffer (maf-history--buffer)
    (progn (call-interactively 'maf-history-previous-separator))
    (cl-assert (= maf-history--index 2))
    (progn (call-interactively 'maf-history-previous-separator))
    (cl-assert (= maf-history--index 5))
    ;; Adjacent rules are two steps, not one.
    (progn (call-interactively 'maf-history-previous-separator))
    (cl-assert (= maf-history--index 6))
    (cl-assert (not (ignore-errors
                      (call-interactively 'maf-history-previous-separator) t)))
    (cl-assert (= maf-history--index 6)))

  ;; M-p walks back up.
  (with-current-buffer (maf-history--buffer)
    (progn (call-interactively 'maf-history-next-separator))
    (cl-assert (= maf-history--index 5))
    (progn (call-interactively 'maf-history-next-separator))
    (cl-assert (= maf-history--index 2))
    (cl-assert (not (ignore-errors
                      (call-interactively 'maf-history-next-separator) t)))
    (cl-assert (= maf-history--index 2)))

  ;; Starting from a marked state skips it: a jump from a rule goes to
  ;; the next rule rather than staying where it already is.
  (progn (setq maf-history--index 5)
         (with-current-buffer (maf-history--buffer) (maf-history--render t)))
  (with-current-buffer (maf-history--buffer)
    (progn (call-interactively 'maf-history-previous-separator))
    (cl-assert (= maf-history--index 6)))

  ;; A prefix count steps that many rules at once.
  (progn (setq maf-history--index 0)
         (with-current-buffer (maf-history--buffer) (maf-history--render t)))
  (with-current-buffer (maf-history--buffer)
    (progn (maf-history-previous-separator 3))
    (cl-assert (= maf-history--index 6))
    (progn (maf-history-next-separator 2))
    (cl-assert (= maf-history--index 2)))

  ;; A count reaching past the last rule refuses and leaves the
  ;; selection where it was, rather than stopping part way along.
  (progn (setq maf-history--index 0)
         (with-current-buffer (maf-history--buffer) (maf-history--render t)))
  (with-current-buffer (maf-history--buffer)
    (cl-assert (not (ignore-errors (maf-history-previous-separator 9) t)))
    (cl-assert (= maf-history--index 0)))

  ;; Both windows follow the jump: the selection moved, so the stack
  ;; beside the log shows the state it landed on.
  (with-current-buffer (maf-history--buffer)
    (progn (call-interactively 'maf-history-previous-separator))
    (cl-assert (= maf-history--index 2))
    (cl-assert (= (get-text-property (point) 'maf-history-index) 2)))

  ;; A log with no rules in it has nowhere to jump, either way.
  (progn (setq maf-history--states (cl-loop for i below 3
                                            collect (list (list i) "mul"))
               maf-history--index 0)
         (with-current-buffer (maf-history--buffer) (maf-history--render t)))
  (with-current-buffer (maf-history--buffer)
    (cl-assert (not (ignore-errors
                      (call-interactively 'maf-history-previous-separator) t)))
    (cl-assert (not (ignore-errors
                      (call-interactively 'maf-history-next-separator) t))))

  ;; An empty log has no states at all, and says so.
  (progn (setq maf-history--states nil maf-history--index 0)
         (with-current-buffer (maf-history--buffer) (maf-history--render t)))
  (cl-assert (not (ignore-errors
                    (with-current-buffer (maf-history--buffer)
                      (call-interactively 'maf-history-previous-separator))
                    t)))

  ;; The legend names the pair, beside the key that draws a rule.
  (progn (setq maf-history--states (list (list (list 5) "mul"))
               maf-history--index 0)
         (with-current-buffer (maf-history--buffer) (maf-history--render t)))
  (with-current-buffer (maf-history--stack-buffer)
    (cl-assert (string-match-p
                "rules"
                (substring-no-properties (format-mode-line header-line-format)))))

  ;; Put the session's log back and re-render the browser over it.
  (progn
    (setq maf-history--states (nth 0 maf--history-motion-stash)
          maf-history--index (nth 1 maf--history-motion-stash))
    (maf-history--render t)))
