(maf-step
  ;; A matrix at home flattens into a plain vector, in reading order.
  (maf-push "[[1, 2], [3, 4]]")
  (call-interactively 'mafcmd-flatten)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "[1, 2, 3, 4]"))
  (calc-pop (calc-stack-size))

  ;; Nesting comes out at every depth, not just the top level.
  (maf-push "[1, [2, [3, 4]], 5]")
  (call-interactively 'mafcmd-flatten)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "[1, 2, 3, 4, 5]"))
  (calc-pop (calc-stack-size))

  ;; Ragged rows are fine — no column count to fill out.
  (maf-push "[[1, 2], [3]]")
  (call-interactively 'mafcmd-flatten)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "[1, 2, 3]"))
  (calc-pop (calc-stack-size))

  ;; Symbolic elements survive; only the nesting goes.
  (maf-push "[[x, y], [2 z, 3]]")
  (call-interactively 'mafcmd-flatten)
  (cl-assert (string= (math-format-value (calc-top 1 'full))
                      "[x, y, 2 z, 3]"))
  (calc-pop (calc-stack-size))

  ;; An already-flat vector commits unchanged.
  (maf-push "[1, 2]")
  (call-interactively 'mafcmd-flatten)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "[1, 2]"))
  (cl-assert (= (calc-stack-size) 1))
  (calc-pop (calc-stack-size))

  ;; A scalar has nothing to flatten and commits unchanged. The legacy
  ;; version pushed the inert form arrange(5, 0) here.
  (maf-push "5")
  (call-interactively 'mafcmd-flatten)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "5"))
  (calc-pop (calc-stack-size))

  ;; Likewise a variable.
  (maf-push "x")
  (call-interactively 'mafcmd-flatten)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "x"))
  (calc-pop (calc-stack-size))

  ;; An empty vector, and a vector of empty vectors.
  (maf-push "[[], []]")
  (call-interactively 'mafcmd-flatten)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "[]"))
  (calc-pop (calc-stack-size))

  ;; Contextual: flatten only the nested vector at point, in place. The
  ;; ":  " search steps past the stack-level label, which
  ;; `calc-cursor-stack-index' leaves point on — without it the searches
  ;; below match the label's own digit and the target resolves at home
  ;; rather than as a sub-formula.
  (maf-push "x + [1, [2, 3]]")
  (progn (calc-cursor-stack-index 1)
         (search-forward ":  ") (search-forward "2") (backward-char 1)
         (call-interactively 'mafcmd-flatten))
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "x + [1, 2, 3]"))
  (calc-pop (calc-stack-size))

  ;; Widening: point on an element names the flat vector [2, 3], which
  ;; has no nesting to remove, so it widens out to the one that does —
  ;; here the whole entry.
  (maf-push "[1, [2, 3]]")
  (progn (calc-cursor-stack-index 1)
         (search-forward ":  ") (search-forward "2") (backward-char 1)
         (call-interactively 'mafcmd-flatten))
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "[1, 2, 3]"))
  (calc-pop (calc-stack-size))

  ;; Widening stops at the innermost vector with nesting, so flattening
  ;; is scoped to the nesting around point rather than the whole entry:
  ;; point on the 3 widens to [2, [3, 4]], leaving the outer vector.
  (maf-push "x + [1, [2, [3, 4]]]")
  (progn (calc-cursor-stack-index 1)
         (search-forward ":  ") (search-forward "3") (backward-char 1)
         (call-interactively 'mafcmd-flatten))
  (cl-assert (string= (math-format-value (calc-top 1 'full))
                      "x + [1, [2, 3, 4]]"))
  (calc-pop (calc-stack-size))

  ;; A sub-formula with no nested vector around it commits unchanged.
  (maf-push "x + [1, 2]")
  (progn (calc-cursor-stack-index 1)
         (search-forward ":  ") (search-forward "1") (backward-char 1)
         (call-interactively 'mafcmd-flatten))
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "x + [1, 2]"))
  (cl-assert (= (calc-stack-size) 1))
  (calc-pop (calc-stack-size))

  ;; Equation: each side flattens independently.
  (maf-push "[[1, 2]] = [[3], [4]]")
  (progn (calc-cursor-stack-index 1) (end-of-line)
         (call-interactively 'mafcmd-flatten))
  (cl-assert (string= (math-format-value (calc-top 1 'full))
                      "[1, 2] = [3, 4]"))
  (calc-pop (calc-stack-size))

  ;; The binding: v L runs it on the top entry at home, taking the key
  ;; from calc's LU decomposition.
  (maf-push "[[1, 2], [3, 4]]")
  (progn (calc-cursor-stack-index 0)
         (execute-kbd-macro (kbd "v L")) nil)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "[1, 2, 3, 4]"))
  (calc-pop (calc-stack-size)))
