(maf-step
  ;; At home: pushes the variable as a new entry (original behavior).
  (maf-push "7")
  (goto-char (point-max))
  (progn (setq unread-command-events (listify-key-sequence "x"))
         (call-interactively 'maf-quick-variable))
  (cl-assert (= (calc-stack-size) 2))
  (cl-assert (equal (calc-top 1 'full) '(var x var-x)))
  (calc-pop (calc-stack-size))

  ;; Subexpr (the example): point on the a of a + 2, variable x
  ;; multiplies just that sub-formula.
  (maf-push "a + 2")
  (progn (goto-char (point-min)) (search-forward "a") (backward-char 1))
  (progn (setq unread-command-events (listify-key-sequence "x"))
         (call-interactively 'maf-quick-variable))
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "x a + 2"))
  (calc-pop (calc-stack-size))

  ;; Entry margin: the whole formula is multiplied, undistributed.
  (maf-push "a + 2")
  (progn (goto-char (point-min)) (end-of-line))
  (progn (setq unread-command-events (listify-key-sequence "x"))
         (call-interactively 'maf-quick-variable))
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "x*(a + 2)"))
  (cl-assert (eolp))
  (calc-pop (calc-stack-size))

  ;; Equation: each side is multiplied, preserving the relation.
  (maf-push "a = b + 1")
  (progn (goto-char (point-min)) (end-of-line))
  (progn (setq unread-command-events (listify-key-sequence "y"))
         (call-interactively 'maf-quick-variable))
  (cl-assert (string= (math-format-value (calc-top 1 'full))
                      "y a = y*(b + 1)"))
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
