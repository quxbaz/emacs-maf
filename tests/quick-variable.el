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

  ;; Point on the operator names the whole sum: multiplied like any
  ;; other sub-formula, variable on the left.
  (maf-push "x + 2")
  (progn (goto-char (point-min)) (search-forward "+") (backward-char 1))
  (progn (setq unread-command-events (listify-key-sequence "y"))
         (call-interactively 'maf-quick-variable))
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "y*(x + 2)"))
  (calc-pop (calc-stack-size))

  ;; Right margin on a bare variable: joined, not renamed. Point is
  ;; past the name rather than on it, so the gesture is to carry on
  ;; writing — the rename needs a name pointed at.
  (maf-push "x")
  (progn (goto-char (point-min)) (end-of-line))
  (progn (setq unread-command-events (listify-key-sequence "y"))
         (call-interactively 'maf-quick-variable))
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "x y"))
  (cl-assert (eolp))
  (calc-pop (calc-stack-size))

  ;; Right margin: the variable lands where typing it there would —
  ;; inside the sum's last term, not around the whole entry.
  (maf-push "a + 2")
  (progn (goto-char (point-min)) (end-of-line))
  (progn (setq unread-command-events (listify-key-sequence "x"))
         (call-interactively 'maf-quick-variable))
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "a + 2 x"))
  (calc-pop (calc-stack-size))

  ;; ...and the smallest formula ending at point takes it: past a^2 it
  ;; is the exponent that ends there, not the power.
  (maf-push "a^2")
  (progn (goto-char (point-min)) (end-of-line))
  (progn (setq unread-command-events (listify-key-sequence "y"))
         (call-interactively 'maf-quick-variable))
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "a^(2 y)"))
  (calc-pop (calc-stack-size))

  ;; Just past a sub-formula mid-entry, the same join: point sits at
  ;; the end of the x, so the variable carries on from there instead
  ;; of the enclosing sum being named.
  (maf-push "a = x + 2")
  (progn (goto-char (point-min)) (search-forward "x"))
  (progn (setq unread-command-events (listify-key-sequence "y"))
         (call-interactively 'maf-quick-variable))
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "a = x y + 2"))
  (calc-pop (calc-stack-size))

  ;; Past a name, joined — not renamed. The rename needs the name
  ;; pointed at, and past it the relation is not mapped per side
  ;; either: the variable lands at the one place point named.
  (maf-push "a = x + 2")
  (progn (goto-char (point-min)) (search-forward "a"))
  (progn (setq unread-command-events (listify-key-sequence "y"))
         (call-interactively 'maf-quick-variable))
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "a y = x + 2"))
  (calc-pop (calc-stack-size))

  ;; On an operator glyph nothing ends at point: the glyph names the
  ;; whole formula, which is multiplied like any other target.
  (maf-push "x + 2")
  (progn (goto-char (point-min)) (search-forward "+"))
  (progn (setq unread-command-events (listify-key-sequence "y"))
         (call-interactively 'maf-quick-variable))
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "y*(x + 2)"))
  (calc-pop (calc-stack-size))

  ;; A relation at the right margin stays whole: one variable at the
  ;; end of it, not one per side.
  (maf-push "a = b + 2")
  (progn (goto-char (point-min)) (end-of-line))
  (progn (setq unread-command-events (listify-key-sequence "y"))
         (call-interactively 'maf-quick-variable))
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "a = b + 2 y"))
  (calc-pop (calc-stack-size))

  ;; Left margin: the whole formula is multiplied, undistributed.
  (maf-push "a + 2")
  (progn (goto-char (point-min)) (beginning-of-line))
  (progn (setq unread-command-events (listify-key-sequence "x"))
         (call-interactively 'maf-quick-variable))
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "x*(a + 2)"))
  (calc-pop (calc-stack-size))

  ;; A relation from the left margin runs the body once per side, and
  ;; a bare-variable side is multiplied like any other: a margin is
  ;; not a name pointed at, so nothing reached from one is renamed.
  (maf-push "a = b + 1")
  (progn (goto-char (point-min)) (beginning-of-line))
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
