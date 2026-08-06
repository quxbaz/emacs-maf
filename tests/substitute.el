;; mafcmd-substitute: the two prompts are driven with real keys, so each
;; case queues its input and fires the command in a single form (the
;; region cases must anyway — the harness deactivates the mark between
;; forms).

(maf-step
  ;; Home: the top entry is the subject; both prompts typed. The result
  ;; is normalized, as if the substituted formula had been entered.
  (maf-push "2 x + 1")
  (goto-char (point-max))
  (progn (setq unread-command-events (listify-key-sequence "x\ra + 1\r"))
         (call-interactively 'mafcmd-substitute))
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "2 a + 3"))
  (calc-pop (calc-stack-size))

  ;; With simplification off the substitution is structural: the
  ;; constant lands beside the 3 without folding into it.
  (maf-push "x + 3")
  (goto-char (point-max))
  (progn (let ((calc-simplify-mode 'none))
           (setq unread-command-events (listify-key-sequence "x\r2\r"))
           (call-interactively 'mafcmd-substitute)))
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "2 + 3"))
  (calc-pop (calc-stack-size))

  ;; The first prompt defaults to the subject's priority variable: RET
  ;; alone takes y, and the constant folds.
  (maf-push "3 y + 1")
  (goto-char (point-max))
  (progn (setq unread-command-events (listify-key-sequence "\r2\r"))
         (call-interactively 'mafcmd-substitute))
  (cl-assert (equal (calc-top 1 'full) 7))
  (calc-pop (calc-stack-size))

  ;; Subexpr: only the term at point is rewritten, the other x stands.
  (maf-push "x^2 + x")
  (progn (calc-cursor-stack-index 1) (end-of-line) (backward-char 1))
  (progn (setq unread-command-events (listify-key-sequence "x\r3\r"))
         (call-interactively 'mafcmd-substitute))
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "x^2 + 3"))
  (calc-pop (calc-stack-size))

  ;; A compound expression, not just a variable, can be the old side.
  (maf-push "sin(x) + 1")
  (goto-char (point-max))
  (progn (setq unread-command-events (listify-key-sequence "sin(x)\ru\r"))
         (call-interactively 'mafcmd-substitute))
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "u + 1"))
  (calc-pop (calc-stack-size))

  ;; Equation at the margin: both sides are rewritten; the side without
  ;; an occurrence is left alone rather than refused.
  (maf-push "y = x^2 - 1")
  (progn (calc-cursor-stack-index 1) (end-of-line))
  (progn (setq unread-command-events (listify-key-sequence "x\r3\r"))
         (call-interactively 'mafcmd-substitute))
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "y = 8"))
  (calc-pop (calc-stack-size))

  ;; Selection: the substitution is confined to the selected node, and
  ;; the rewritten node normalizes. (The * is explicit: "y (x + 2)"
  ;; would parse as a call to y.)
  (maf-push "y*(x + 2)")
  (progn (calc-cursor-stack-index 1)
         (search-forward "+ 2" (line-end-position))
         (goto-char (match-beginning 0))
         (call-interactively 'calc-select-here)
         (setq unread-command-events (listify-key-sequence "x\r5\r"))
         (call-interactively 'mafcmd-substitute))
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "y 7"))
  (calc-clear-selections)
  (calc-pop (calc-stack-size))

  ;; What surrounds the subject is left as it stands: with only the x
  ;; selected, the sum holding it is not re-folded.
  (maf-push "y*(x + 2)")
  (progn (calc-cursor-stack-index 1)
         (search-forward "x + 2" (line-end-position))
         (goto-char (match-beginning 0))
         (call-interactively 'calc-select-here)
         (setq unread-command-events (listify-key-sequence "x\r5\r"))
         (call-interactively 'mafcmd-substitute))
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "y*(5 + 2)"))
  (calc-clear-selections)
  (calc-pop (calc-stack-size))

  ;; Region: the covered run is the subject, and the read-only probe
  ;; behind the prompt default leaves the region standing for the run.
  (maf-push "x + x y + b")
  (progn (calc-cursor-stack-index 1)
         (search-forward "x + x y" (line-end-position))
         (goto-char (match-beginning 0))
         (push-mark (match-end 0) t t)
         (setq unread-command-events (listify-key-sequence "x\r2\r"))
         (call-interactively 'mafcmd-substitute))
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "2 y + 2 + b"))
  (cl-assert (not (region-active-p)))
  (calc-pop (calc-stack-size))

  ;; $ takes the replacement from the stack: at home the top entry is
  ;; the replacement and the one below it the subject, consumed on
  ;; commit as any binary arg is.
  (maf-push "2 x")
  (maf-push "a + 1")
  (goto-char (point-max))
  (progn (setq unread-command-events (listify-key-sequence "x\r$\r"))
         (call-interactively 'mafcmd-substitute))
  (cl-assert (= (calc-stack-size) 1))
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "2 a + 2"))
  (calc-pop (calc-stack-size))

  ;; An expression the subject does not contain is refused before
  ;; anything is committed — with $, before the stack entry is eaten.
  (maf-push "a + b")
  (maf-push "9")
  (goto-char (point-max))
  (cl-assert (eq 'user-error
                 (condition-case err
                     (progn (setq unread-command-events
                                  (listify-key-sequence "x\r$\r"))
                            (call-interactively 'mafcmd-substitute)
                            nil)
                   (user-error (car err)))))
  (cl-assert (= (calc-stack-size) 2))
  (cl-assert (string= (math-format-value (calc-top 2 'full)) "a + b"))
  (calc-pop (calc-stack-size))

  ;; Input calc cannot parse is refused, stack untouched.
  (maf-push "a + b")
  (goto-char (point-max))
  (cl-assert (eq 'user-error
                 (condition-case err
                     (progn (setq unread-command-events
                                  (listify-key-sequence "a\r(\r"))
                            (call-interactively 'mafcmd-substitute)
                            nil)
                   (user-error (car err)))))
  (cl-assert (= (calc-stack-size) 1))
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "a + b"))
  (calc-pop (calc-stack-size))

  ;; An empty replacement is refused too — nothing is committed.
  (maf-push "a + b")
  (goto-char (point-max))
  (cl-assert (eq 'user-error
                 (condition-case err
                     (progn (setq unread-command-events
                                  (listify-key-sequence "a\r\r"))
                            (call-interactively 'mafcmd-substitute)
                            nil)
                   (user-error (car err)))))
  (cl-assert (= (calc-stack-size) 1))
  (calc-pop (calc-stack-size)))
