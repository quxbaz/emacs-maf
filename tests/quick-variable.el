(maf-step
  ;; At home: pushes the variable as a new entry (original behavior).
  (maf-push "7")
  (goto-char (point-max))
  (progn (setq unread-command-events (listify-key-sequence "x"))
         (call-interactively 'maf-quick-variable))
  (cl-assert (= (calc-stack-size) 2))
  (cl-assert (equal (calc-top 1 'full) '(var x var-x)))
  (calc-pop (calc-stack-size))

  ;; Subexpr on a variable: overwritten, not multiplied — naming a
  ;; name means renaming it.
  (maf-push "a + 2")
  (progn (goto-char (point-min)) (search-forward "a") (backward-char 1))
  (progn (setq unread-command-events (listify-key-sequence "x"))
         (call-interactively 'maf-quick-variable))
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "x + 2"))
  (calc-pop (calc-stack-size))

  ;; Subexpr on anything else (the example): multiplied, variable on
  ;; the left.
  (maf-push "a + 2")
  (progn (goto-char (point-min)) (search-forward "2") (backward-char 1))
  (progn (setq unread-command-events (listify-key-sequence "x"))
         (call-interactively 'maf-quick-variable))
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "a + 2 x"))
  (calc-pop (calc-stack-size))

  ;; Entry margin: the whole formula is multiplied, undistributed.
  (maf-push "a + 2")
  (progn (goto-char (point-min)) (end-of-line))
  (progn (setq unread-command-events (listify-key-sequence "x"))
         (call-interactively 'maf-quick-variable))
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "x*(a + 2)"))
  (cl-assert (eolp))
  (calc-pop (calc-stack-size))

  ;; Equation: the body runs once per side, so a bare-variable side is
  ;; renamed while the other side is multiplied.
  (maf-push "a = b + 1")
  (progn (goto-char (point-min)) (end-of-line))
  (progn (setq unread-command-events (listify-key-sequence "y"))
         (call-interactively 'maf-quick-variable))
  (cl-assert (string= (math-format-value (calc-top 1 'full))
                      "y = y*(b + 1)"))
  (calc-pop (calc-stack-size))

  ;; A non-letter is rejected with the stack untouched.
  (maf-push "5")
  (goto-char (point-max))
  (cl-assert (eq 'user-error
                 (condition-case err
                     (progn (setq unread-command-events
                                  (listify-key-sequence "1"))
                            (call-interactively 'maf-quick-variable)
                            nil)
                   (user-error (car err)))))
  (cl-assert (= (calc-stack-size) 1))
  (calc-pop (calc-stack-size)))
