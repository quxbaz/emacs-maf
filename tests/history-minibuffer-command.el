(maf-step
  ;; A command that reads from the minibuffer is still the command the
  ;; log names. The read runs a command loop of its own, and each command
  ;; in it is named as `this-command' in turn, so a change committed after
  ;; the read lands with `this-command' naming the RET that ended the
  ;; entry — `exit-minibuffer', or whatever RET is bound to there — and
  ;; the log used to echo that: "filter (autopair-newline)". The command
  ;; is noted as the minibuffer opens (`maf-history--note-minibuffer-entry')
  ;; and read back when `this-command' is what the read left behind
  ;; (`maf-history--command').
  (setq maf--history-minibuffer-stash (list maf-history--states
                                            maf-history--last-raw
                                            maf-history-size
                                            maf-history--index)
        maf-history--states nil
        maf-history--last-raw nil
        maf-history-size 100
        maf-history--index 0)
  (maf-history--capture)

  ;; f f prompts for the predicate; the state it records names it.
  (calc-wrapper (maf-push "[0, 1, 2, 3, 4]"))
  (maf-history--capture)
  (execute-kbd-macro (kbd "f f > 2 RET"))
  (cl-assert (string= (math-format-value (calc-top 1)) "[3, 4]"))
  (cl-assert (equal (maf-history--label (car maf-history--states)) "filter"))
  (cl-assert (eq (nth 2 (car maf-history--states)) 'mafcmd-filter))
  (cl-assert (equal (maf-history--command-name (car maf-history--states))
                    "mafcmd-filter"))
  ;; The notes are consumed with the command that read, so they cannot
  ;; name a later change after it.
  (cl-assert (null maf-history--minibuffer-command))
  (cl-assert (null maf-history--minibuffer-exit-command))

  ;; A command that reads twice — a substitution reads the target, then
  ;; the replacement — is named by its first read's note; the second
  ;; read opens under the first's ending command and must not renote.
  (calc-wrapper (maf-push "a + b"))
  (maf-history--capture)
  (execute-kbd-macro (kbd "a b a RET c RET"))
  (cl-assert (string= (math-format-value (calc-top 1)) "c + b"))
  (cl-assert (eq (nth 2 (car maf-history--states)) 'mafcmd-substitute))

  ;; Under M-x the first read is `execute-extended-command''s own, and it
  ;; names the command it runs as `this-command' once that read is over:
  ;; a name set on purpose after a read, told from one the read left
  ;; behind, so the command's own read notes the right one.
  (execute-kbd-macro (kbd "M-x mafcmd-substitute RET b RET d RET"))
  (cl-assert (string= (math-format-value (calc-top 1)) "c + d"))
  (cl-assert (eq (nth 2 (car maf-history--states)) 'mafcmd-substitute))
  ;; ... and a command that reads nothing keeps the name M-x gave it.
  (execute-kbd-macro (kbd "M-x calc-pop RET"))
  (cl-assert (eq (nth 2 (car maf-history--states)) 'calc-pop))

  ;; The rule itself: `this-command' is trusted unless it is what the
  ;; last read left behind, and then the noted opener stands in.
  (cl-assert (eq (let ((this-command 'exit-minibuffer)
                       (maf-history--minibuffer-command 'mafcmd-filter)
                       (maf-history--minibuffer-exit-command 'exit-minibuffer))
                   (maf-history--command))
                 'mafcmd-filter))
  (cl-assert (eq (let ((this-command 'mafcmd-filter-stack)
                       (maf-history--minibuffer-command 'execute-extended-command)
                       (maf-history--minibuffer-exit-command 'exit-minibuffer))
                   (maf-history--command))
                 'mafcmd-filter-stack))
  (cl-assert (eq (let ((this-command 'exit-minibuffer)
                       (maf-history--minibuffer-command nil)
                       (maf-history--minibuffer-exit-command nil))
                   (maf-history--command))
                 'exit-minibuffer))

  ;; Put the session's log back.
  (progn
    (calc-pop (calc-stack-size))
    (setq maf-history--states (nth 0 maf--history-minibuffer-stash)
          maf-history--last-raw (nth 1 maf--history-minibuffer-stash)
          maf-history-size (nth 2 maf--history-minibuffer-stash)
          maf-history--index (nth 3 maf--history-minibuffer-stash))
    (maf-history--render t)))
