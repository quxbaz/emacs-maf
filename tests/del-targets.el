(maf-step
  ;; Empty stack: signals instead of guessing.
  (cl-assert (condition-case nil
                 (progn (call-interactively 'maf-del) nil)
               (error t)))

  ;; Summand: dropped from the sum.
  (maf-push "a + b")
  (progn (calc-cursor-stack-index 1)
         (search-forward "b" (line-end-position)) (backward-char 1) nil)
  (call-interactively 'maf-del)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "a"))
  (calc-pop (calc-stack-size))

  ;; Factor: falls out of the product, not zeroed.
  (maf-push "a b")
  (progn (calc-cursor-stack-index 1)
         (search-forward "b" (line-end-position)) (backward-char 1) nil)
  (call-interactively 'maf-del)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "a"))
  (calc-pop (calc-stack-size))

  ;; Exponent: the power collapses to its base.
  (maf-push "a^b")
  (progn (calc-cursor-stack-index 1)
         (search-forward "b" (line-end-position)) (backward-char 1) nil)
  (call-interactively 'maf-del)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "a"))
  (calc-pop (calc-stack-size))

  ;; Vector element: removed, the vector shrinks.
  (maf-push "[a, b, c]")
  (progn (calc-cursor-stack-index 1)
         (search-forward "b" (line-end-position)) (backward-char 1) nil)
  (call-interactively 'maf-del)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "[a, c]"))
  (calc-pop (calc-stack-size))

  ;; Relation side: the other side survives.
  (maf-push "x = y")
  (progn (calc-cursor-stack-index 1)
         (search-forward "y" (line-end-position)) (backward-char 1) nil)
  (call-interactively 'maf-del)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "x"))
  (calc-pop (calc-stack-size))

  ;; Active selection: deleted wherever point sits within the entry.
  (maf-push "q + r s")
  (progn (calc-cursor-stack-index 1)
         (search-forward "r" (line-end-position)) (backward-char 1) nil)
  (call-interactively 'calc-select-here)
  (progn (end-of-line) nil)
  (call-interactively 'maf-del)
  (calc-clear-selections)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "q + s"))
  (calc-pop (calc-stack-size))

  ;; Entry margin: the whole entry at point is deleted.
  (maf-push "q1")
  (maf-push "q2")
  (progn (calc-cursor-stack-index 2) (end-of-line) nil)
  (call-interactively 'maf-del)
  (cl-assert (= (calc-stack-size) 1))
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "q2"))
  (calc-pop (calc-stack-size))

  ;; Home: the top of the stack pops.
  (maf-push "q1")
  (maf-push "q2")
  (progn (goto-char (point-max)) nil)
  (call-interactively 'maf-del)
  (cl-assert (= (calc-stack-size) 1))
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "q1")))
