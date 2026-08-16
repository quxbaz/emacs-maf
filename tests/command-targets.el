;; Per-command targeting policy: every conventional defcmd generates a
;; *-targets variable naming the narrowing gestures it honors (region,
;; selection, subexpr). Editing the list retunes the command; a gesture
;; off the list is skipped, never chosen as the subject. The variables
;; are let-bound here so nothing leaks into the session. Two expandable
;; nodes keep subexpr and entry targeting distinguishable throughout:
;; narrowing expands one power, the whole entry expands both.

(maf-defcmd maf-test-entry-cap (expr _arg commit)
  "Test probe: entry-scoped with subexpr capability, doubling the subject."
  :arity unary
  :prefix "tcap"
  :scope entry
  :targets (subexpr)
  (commit (math-normalize (list '* 2 expr))))

(maf-step
  ;; The default set narrows by subexpr: point on the first power
  ;; expands it alone.
  (maf-push "(x + 1)^2 + (y + 1)^2")
  (progn (calc-cursor-stack-index 1) (search-forward "^") (backward-char 1))
  (call-interactively 'mafcmd-expand)
  (cl-assert (string= (math-format-value
                       (maf--strip-encasing (calc-top 1 'full)))
                      "x^2 + 2 x + 1 + (y + 1)^2"))
  (calc-pop (calc-stack-size))

  ;; Subexpr removed: the same gesture takes the entry whole — both
  ;; powers expand, so a policy silently ignored would fail here. The
  ;; constants fold: the result is committed under the simplification
  ;; mode, as calc's own a x commits it, and this is its `alg' shape.
  (maf-push "(x + 1)^2 + (y + 1)^2")
  (progn (calc-cursor-stack-index 1) (search-forward "^") (backward-char 1))
  (let ((mafcmd-expand-targets '(region selection)))
    (call-interactively 'mafcmd-expand))
  (cl-assert (string= (math-format-value
                       (maf--strip-encasing (calc-top 1 'full)))
                      "x^2 + 2 x + y^2 + 2 y + 2"))
  (calc-pop (calc-stack-size))

  ;; A suppressed selection is never chosen and never captures the
  ;; result: the whole entry is rewritten. (The selection lived on the
  ;; rewritten entry, so it is gone with it — that is the documented
  ;; limit, not an accident.)
  (maf-push "(x + 1)^2 + (y + 1)^2")
  (progn (calc-cursor-stack-index 1) (search-forward "^") (backward-char 1)
         (execute-kbd-macro (kbd "j s")))
  (let ((mafcmd-expand-targets nil))
    (call-interactively 'mafcmd-expand))
  (cl-assert (string= (math-format-value
                       (maf--strip-encasing (calc-top 1 'full)))
                      "x^2 + 2 x + y^2 + 2 y + 2"))
  (cl-assert (not (maf--sel-any-p)))
  (calc-pop (calc-stack-size))

  ;; A suppressed region is skipped, not resolved: the cascade falls
  ;; through to the subexpr under point, and only that power expands.
  (maf-push "(x + 1)^2 + (y + 1)^2")
  (progn (calc-cursor-stack-index 1)
         (search-forward "(x") (backward-char 2)
         (push-mark (point) t t)
         (search-forward "^") (backward-char 1))
  (let ((mafcmd-expand-targets '(selection subexpr)))
    (call-interactively 'mafcmd-expand))
  (cl-assert (string= (math-format-value
                       (maf--strip-encasing (calc-top 1 'full)))
                      "x^2 + 2 x + 1 + (y + 1)^2"))
  (calc-pop (calc-stack-size))

  ;; Entry-scoped with a declared capability ships closed: the probe's
  ;; variable exists but defaults to nil, so point inside the formula
  ;; still takes the entry whole.
  (cl-assert (null maf-test-entry-cap-targets))
  (maf-push "x + 1")
  (progn (calc-cursor-stack-index 1) (search-forward "x") (backward-char 1))
  (call-interactively 'maf-test-entry-cap)
  (cl-assert (string= (math-format-value
                       (maf--strip-encasing (calc-top 1 'full)))
                      "2 x + 2"))
  (calc-pop (calc-stack-size))

  ;; ...and the capability is the door the user may open: subexpr
  ;; enabled narrows, region stays refused.
  (maf-push "x + 1")
  (progn (calc-cursor-stack-index 1) (search-forward "x") (backward-char 1))
  (let ((maf-test-entry-cap-targets '(subexpr)))
    (call-interactively 'maf-test-entry-cap))
  (cl-assert (string= (math-format-value
                       (maf--strip-encasing (calc-top 1 'full)))
                      "2 x + 1"))
  (cl-assert (string-match-p
              "cannot target region"
              (condition-case err
                  (let ((maf-test-entry-cap-targets '(region)))
                    (call-interactively 'maf-test-entry-cap)
                    "")
                (user-error (error-message-string err)))))
  (calc-pop (calc-stack-size))

  ;; A symbol outside the capability refuses loudly — which also
  ;; catches a typo — and so does a value that is not a list at all.
  (maf-push "x + 1")
  (goto-char (point-max))
  (cl-assert (string-match-p
              "cannot target subexp"
              (condition-case err
                  (let ((mafcmd-expand-targets '(subexp)))
                    (call-interactively 'mafcmd-expand)
                    "")
                (user-error (error-message-string err)))))
  (cl-assert (string-match-p
              "must be a list"
              (condition-case err
                  (let ((mafcmd-expand-targets t))
                    (call-interactively 'mafcmd-expand)
                    "")
                (user-error (error-message-string err)))))
  (cl-assert (= (calc-stack-size) 1))
  (calc-pop (calc-stack-size))

  ;; The pressed key's policy rides the dispatch: with vconcat's
  ;; narrowing off, I | takes the entry whole from inside it, even
  ;; though vconcatrev answers with a variable of its own.
  (cl-assert (boundp 'mafcmd-vconcatrev-targets))
  (maf-push "[a, b] + z")
  (maf-push "[1, 2]")
  (progn (calc-cursor-stack-index 2) (search-forward "[a") (backward-char 2))
  (let ((mafcmd-vconcat-targets nil) (calc-inverse-flag t))
    (call-interactively 'mafcmd-vconcat))
  (cl-assert (string= (math-format-value
                       (maf--strip-encasing (calc-top 1 'full)))
                      "[1, 2, [a, b] + z]"))
  (calc-pop (calc-stack-size))

  ;; Across a flag dispatch the pressed key's policy governs: H E maps
  ;; by exp's variable though exp10 answers...
  (maf-push "x + 1")
  (progn (calc-cursor-stack-index 1) (search-forward "x") (backward-char 1))
  (let ((mafcmd-exp-targets nil) (calc-hyperbolic-flag t))
    (call-interactively 'mafcmd-exp))
  (cl-assert (string= (math-format-value
                       (maf--strip-encasing (calc-top 1 'full)))
                      "10.^(x + 1)"))
  (calc-pop (calc-stack-size))

  ;; ...ln's variable does not govern H E...
  (maf-push "x + 1")
  (progn (calc-cursor-stack-index 1) (search-forward "x") (backward-char 1))
  (let ((mafcmd-ln-targets nil) (calc-hyperbolic-flag t))
    (call-interactively 'mafcmd-exp))
  (cl-assert (string= (math-format-value
                       (maf--strip-encasing (calc-top 1 'full)))
                      "10.^x + 1"))
  (calc-pop (calc-stack-size))

  ;; ...and I L maps by ln's even though exp answers.
  (maf-push "x + 1")
  (progn (calc-cursor-stack-index 1) (search-forward "x") (backward-char 1))
  (let ((mafcmd-ln-targets nil) (calc-inverse-flag t))
    (call-interactively 'mafcmd-ln))
  (cl-assert (string= (math-format-value
                       (maf--strip-encasing (calc-top 1 'full)))
                      "exp(x + 1)"))
  (calc-pop (calc-stack-size))

  ;; Direct invocation of a variant consults its own variable — no
  ;; table-order ownership.
  (maf-push "x + 1")
  (progn (calc-cursor-stack-index 1) (search-forward "x") (backward-char 1))
  (let ((mafcmd-exp10-targets nil) (mafcmd-ln-targets '(region selection subexpr)))
    (call-interactively 'mafcmd-exp10))
  (cl-assert (string= (math-format-value
                       (maf--strip-encasing (calc-top 1 'full)))
                      "10.^(x + 1)"))
  (calc-pop (calc-stack-size))

  ;; A misconfigured variable signals without stranding a prefix flag:
  ;; the dispatcher consumes I/H before validating what rides.
  (maf-push "x + 1")
  (goto-char (point-max))
  (progn (setq calc-inverse-flag t)
         (cl-assert (string-match-p
                     "must be a list"
                     (condition-case err
                         (let ((mafcmd-ln-targets t))
                           (call-interactively 'mafcmd-ln)
                           "")
                       (user-error (error-message-string err)))))
         (cl-assert (null calc-inverse-flag))
         (cl-assert (null calc-hyperbolic-flag)))
  (cl-assert (= (calc-stack-size) 1))
  (calc-pop (calc-stack-size))

  ;; An explicitly empty :targets is rejected at expansion — it must
  ;; not read as absent and silently grant full capability; its two
  ;; meanings are already spelled :scope entry and :targets custom.
  (cl-assert (eq 'rejected
                 (condition-case nil
                     (progn (macroexpand-1
                             '(maf-defcmd maf-test-nil-targets (e _a c)
                                "P." :arity unary :targets nil (c e)))
                            'expanded)
                   (error 'rejected))))

  ;; Workers carry their public command's name: the prompt and stack
  ;; forms of substitution share one variable, the map commands have
  ;; their own, and bespoke-targeting commands generate none.
  (cl-assert (boundp 'mafcmd-substitute-targets))
  (cl-assert (equal mafcmd-map-targets '(region selection)))
  (cl-assert (boundp 'maf-quick-variable-targets))
  (cl-assert (not (boundp 'maf--negate-run-targets)))
  (cl-assert (not (boundp 'maf--solve-for-run-targets)))
  (cl-assert (not (boundp 'maf--digit-apply-targets))))
