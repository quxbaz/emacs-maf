(maf-step
  ;; Sum: the term under point flips the operator joining it, so the
  ;; entry still evaluates to what it did before.
  (maf-push "a + x")
  (progn (goto-char (point-min)) (search-forward "x") (backward-char 1))
  (call-interactively 'mafcmd-negate)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "a - -x"))
  ;; Structural, not simplified: the doubled sign is really there.
  (cl-assert (equal (calc-top 1 'full) '(- (var a var-a) (neg (var x var-x)))))
  ;; Its own inverse: negating the negated term puts the entry back.
  (progn (goto-char (point-min)) (search-forward "-x") (backward-char 2))
  (call-interactively 'mafcmd-negate)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "a + x"))
  (calc-pop (calc-stack-size))

  ;; A difference flips the other way, and the terms around the target
  ;; keep the form they had.
  (maf-push "a + x + b")
  (progn (goto-char (point-min)) (search-forward "x") (backward-char 1))
  (call-interactively 'mafcmd-negate)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "a - -x + b"))
  (calc-pop (calc-stack-size))

  ;; A leading term has no operator in front of it to flip, so the minus
  ;; stays inside its own slot rather than rewriting the whole sum.
  (maf-push "6 x + 12")
  (progn (goto-char (point-min)) (search-forward "6"))
  (call-interactively 'mafcmd-negate)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "-(-6 x) + 12"))
  (cl-assert (equal (calc-top 1 'full)
                    '(+ (neg (* -6 (var x var-x))) 12)))
  (calc-pop (calc-stack-size))
  ;; The same inside one side of a relation: the other side is untouched.
  (maf-push "6 x + 12 = 18 y + 6")
  (progn (goto-char (point-min)) (search-forward "6"))
  (call-interactively 'mafcmd-negate)
  (cl-assert (string= (math-format-value (calc-top 1 'full))
                      "-(-6 x) + 12 = 18 y + 6"))
  (calc-pop (calc-stack-size))
  ;; A leading term the minus cannot reach inside commits unchanged.
  (maf-push "a x + b")
  (progn (goto-char (point-min)) (search-forward "a"))
  (call-interactively 'mafcmd-negate)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "a x + b"))
  (calc-pop (calc-stack-size))

  ;; Product and quotient: the other operand takes the sign, so the two
  ;; minus signs cancel.
  (maf-push "a x")
  (progn (goto-char (point-min)) (search-forward "x") (backward-char 1))
  (call-interactively 'mafcmd-negate)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "-a*-x"))
  (calc-pop (calc-stack-size))
  (maf-push "a / x")
  (progn (goto-char (point-min)) (search-forward "x") (backward-char 1))
  (call-interactively 'mafcmd-negate)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "-a / -x"))
  (calc-pop (calc-stack-size))

  ;; A number in a product folds the sign into itself: 2 - 3 x read as
  ;; a sum of 2 and -3 x. Point on the space names the whole product.
  (maf-push "2 - 3 x")
  (progn (goto-char (point-min)) (search-forward "3"))
  (call-interactively 'mafcmd-negate)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "2 + -3 x"))
  (calc-pop (calc-stack-size))

  ;; Powers: an integer exponent absorbs the base's sign, an even one
  ;; swallowing it and an odd one passing it out front. A symbolic
  ;; exponent has nowhere to put it, so the entry stands.
  (maf-push "x^2")
  (progn (goto-char (point-min)) (search-forward "x") (backward-char 1))
  (call-interactively 'mafcmd-negate)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "(-x)^2"))
  (calc-pop (calc-stack-size))
  (maf-push "x^3")
  (progn (goto-char (point-min)) (search-forward "x") (backward-char 1))
  (call-interactively 'mafcmd-negate)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "-(-x)^3"))
  (calc-pop (calc-stack-size))
  (maf-push "x^y")
  (progn (goto-char (point-min)) (search-forward "x") (backward-char 1))
  (call-interactively 'mafcmd-negate)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "x^y"))
  (calc-pop (calc-stack-size))

  ;; Odd and even functions; one that is neither commits unchanged.
  (maf-push "sin(x)")
  (progn (goto-char (point-min)) (search-forward "(x") (backward-char 1))
  (call-interactively 'mafcmd-negate)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "-sin(-x)"))
  (calc-pop (calc-stack-size))
  (maf-push "cos(x)")
  (progn (goto-char (point-min)) (search-forward "(x") (backward-char 1))
  (call-interactively 'mafcmd-negate)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "cos(-x)"))
  (calc-pop (calc-stack-size))
  (maf-push "floor(x)")
  (progn (goto-char (point-min)) (search-forward "(x") (backward-char 1))
  (call-interactively 'mafcmd-negate)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "floor(x)"))
  (calc-pop (calc-stack-size))

  ;; A relation negates both sides at once, so it keeps saying the same
  ;; thing; an inequality reverses its direction with them. Which side
  ;; point named makes no difference.
  (maf-push "x = a")
  (progn (goto-char (point-min)) (search-forward "x") (backward-char 1))
  (call-interactively 'mafcmd-negate)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "-x = -a"))
  (calc-pop (calc-stack-size))
  (maf-push "2 x - 3 < 7")
  (progn (goto-char (point-min)) (search-forward "<") (backward-char 1))
  (call-interactively 'mafcmd-negate)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "3 - 2 x > -7"))
  (calc-pop (calc-stack-size))

  ;; Inside one side of a relation, only that side's term flips — the
  ;; relation is untouched and still balanced.
  (maf-push "x + 1 = 3 y")
  (progn (goto-char (point-min)) (search-forward "+ 1") (backward-char 1))
  (call-interactively 'mafcmd-negate)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "x - -1 = 3 y"))
  (calc-pop (calc-stack-size))

  ;; At home the whole entry is the target: with nothing around it to
  ;; pay, the expression is shown negated behind a leading minus.
  (maf-push "2 - x")
  (goto-char (point-max))
  (call-interactively 'mafcmd-negate)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "-(x - 2)"))
  (calc-pop (calc-stack-size))
  ;; The entry margin resolves the same way.
  (maf-push "a + b")
  (progn (calc-cursor-stack-index 1) (end-of-line))
  (call-interactively 'mafcmd-negate)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "-(-a - b)"))
  (calc-pop (calc-stack-size))
  ;; Where negating does not reach inside the expression, a second
  ;; minus sign would be all it added, so the entry commits unchanged.
  (maf-push "x")
  (goto-char (point-max))
  (call-interactively 'mafcmd-negate)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "x"))
  (calc-pop (calc-stack-size))

  ;; An explicit selection is the target, and is cleared afterwards as
  ;; the rest of the entry-scoped commands do.
  (maf-push "a + x + b")
  (progn (goto-char (point-min)) (search-forward "x") (backward-char 1))
  (call-interactively 'calc-select-here)
  (call-interactively 'mafcmd-negate)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "a - -x + b"))
  (cl-assert (null (calc-top 1 'sel)))
  (calc-pop (calc-stack-size))

  ;; An entry below the top is rewritten in place, the top untouched.
  (maf-push "a + x")
  (maf-push "q")
  (progn (calc-cursor-stack-index 2) (end-of-line) (search-backward "x"))
  (call-interactively 'mafcmd-negate)
  (cl-assert (string= (math-format-value (calc-top 2 'full)) "a - -x"))
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "q"))
  (cl-assert (= (calc-stack-size) 2))
  (calc-pop (calc-stack-size))

  ;; With keep-args the originals stay and the result lands on top.
  (maf-push "a + x")
  (progn (goto-char (point-min)) (search-forward "x") (backward-char 1))
  (call-interactively 'calc-keep-args)
  (call-interactively 'mafcmd-negate)
  (cl-assert (= (calc-stack-size) 2))
  (cl-assert (string= (math-format-value (calc-top 2 'full)) "a + x"))
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "a - -x"))
  (calc-pop (calc-stack-size)))
