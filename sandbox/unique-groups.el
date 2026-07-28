;; Port verification for mafcmd-unique-groups (l g): the resolved
;; vector's elements grouped N at a time, N from the top of the stack.

(defun ug-top= (expr)
  "Non-nil when the calc stack top equals algebraic EXPR.
Compared structurally rather than by `math-format-value', since a vector
of vectors is a matrix and formats over several lines. The encasing calc
leaves on an entry it prepared for selection is stripped first — resolve
runs `calc-prepare-selection' for a sub-formula target, and its
\(cplx N 0) atom wrappers stay on the stored entry afterwards."
  (equal (maf--strip-encasing (calc-top 1 'full))
         (math-normalize (math-read-expr expr))))

(maf-step
  ;; Basic: pairs, in the vector's own order, no reorderings.
  (maf-push "[a, b, c, d]")
  (maf-push "2")
  (call-interactively 'mafcmd-unique-groups)
  (cl-assert (ug-top= "[[a,b],[a,c],[a,d],[b,c],[b,d],[c,d]]"))
  (cl-assert (= (calc-stack-size) 1))
  (calc-pop (calc-stack-size))

  ;; Triples from the same vector.
  (maf-push "[a, b, c, d]")
  (maf-push "3")
  (call-interactively 'mafcmd-unique-groups)
  (cl-assert (ug-top= "[[a,b,c],[a,b,d],[a,c,d],[b,c,d]]"))
  (calc-pop (calc-stack-size))

  ;; Size 1: each element in a group of its own.
  (maf-push "[a, b, c]")
  (maf-push "1")
  (call-interactively 'mafcmd-unique-groups)
  (cl-assert (ug-top= "[[a],[b],[c]]"))
  (calc-pop (calc-stack-size))

  ;; Size equal to the vector's length: one group, all of it.
  (maf-push "[a, b, c]")
  (maf-push "3")
  (call-interactively 'mafcmd-unique-groups)
  (cl-assert (ug-top= "[[a,b,c]]"))
  (calc-pop (calc-stack-size))

  ;; Size larger than the vector: no group to make.
  (maf-push "[a, b]")
  (maf-push "3")
  (call-interactively 'mafcmd-unique-groups)
  (cl-assert (ug-top= "[]"))
  (calc-pop (calc-stack-size))

  ;; Size zero: the one empty group.
  (maf-push "[a, b]")
  (maf-push "0")
  (call-interactively 'mafcmd-unique-groups)
  (cl-assert (ug-top= "[[]]"))
  (calc-pop (calc-stack-size))

  ;; The empty vector, at any size: no group.
  (maf-push "[]")
  (maf-push "2")
  (call-interactively 'mafcmd-unique-groups)
  (cl-assert (ug-top= "[]"))
  (calc-pop (calc-stack-size))

  ;; Repeated elements: positions would give [a,b] twice, contents give
  ;; it once.
  (maf-push "[a, a, b]")
  (maf-push "2")
  (call-interactively 'mafcmd-unique-groups)
  (cl-assert (ug-top= "[[a,a],[a,b]]"))
  (calc-pop (calc-stack-size))

  ;; Numbers group like anything else, and equal values still collapse.
  (maf-push "[1, 2, 2]")
  (maf-push "2")
  (call-interactively 'mafcmd-unique-groups)
  (cl-assert (ug-top= "[[1,2],[2,2]]"))
  (calc-pop (calc-stack-size))

  ;; Compound elements: whole sub-expressions are the members.
  (maf-push "[x + 1, sin(y), 2 z]")
  (maf-push "2")
  (call-interactively 'mafcmd-unique-groups)
  (cl-assert (ug-top= "[[x + 1, sin(y)],[x + 1, 2 z],[sin(y), 2 z]]"))
  (calc-pop (calc-stack-size))

  ;; A matrix subject: its rows are the elements, grouped whole.
  (maf-push "[[1, 2], [3, 4], [5, 6]]")
  (maf-push "2")
  (call-interactively 'mafcmd-unique-groups)
  (cl-assert (ug-top= "[[[1,2],[3,4]],[[1,2],[5,6]],[[3,4],[5,6]]]"))
  (calc-pop (calc-stack-size))

  ;; An integer written as a float still names a size.
  (maf-push "[a, b, c]")
  (maf-push "2.")
  (call-interactively 'mafcmd-unique-groups)
  (cl-assert (ug-top= "[[a,b],[a,c],[b,c]]"))
  (calc-pop (calc-stack-size))

  ;; A fractional size is not a size: it signals, and nothing is
  ;; consumed.
  (maf-push "[a, b, c]")
  (maf-push "2.5")
  (cl-assert (condition-case nil
                 (progn (call-interactively 'mafcmd-unique-groups) nil)
               (error t)))
  (cl-assert (= (calc-stack-size) 2))
  (calc-pop (calc-stack-size))

  ;; So is a negative one.
  (maf-push "[a, b, c]")
  (maf-push "-1")
  (cl-assert (condition-case nil
                 (progn (call-interactively 'mafcmd-unique-groups) nil)
               (error t)))
  (cl-assert (= (calc-stack-size) 2))
  (calc-pop (calc-stack-size))

  ;; And so is a symbol.
  (maf-push "[a, b, c]")
  (maf-push "n")
  (cl-assert (condition-case nil
                 (progn (call-interactively 'mafcmd-unique-groups) nil)
               (error t)))
  (cl-assert (= (calc-stack-size) 2))
  (calc-pop (calc-stack-size))

  ;; A subject that is not a vector commits unchanged.
  (maf-push "x + 1")
  (maf-push "2")
  (call-interactively 'mafcmd-unique-groups)
  (cl-assert (ug-top= "x + 1"))
  (cl-assert (= (calc-stack-size) 1))
  (calc-pop (calc-stack-size))

  ;; Equation subject: the vector side groups, the other passes through.
  (maf-push "v = [a, b, c]")
  (maf-push "2")
  (call-interactively 'mafcmd-unique-groups)
  (cl-assert (ug-top= "v = [[a,b],[a,c],[b,c]]"))
  (calc-pop (calc-stack-size))

  ;; Both sides vectors: both group, against the same size.
  (maf-push "[a, b, c] = [p, q, r]")
  (maf-push "3")
  (call-interactively 'mafcmd-unique-groups)
  (cl-assert (ug-top= "[[a,b,c]] = [[p,q,r]]"))
  (calc-pop (calc-stack-size))

  ;; Sub-formula at point: only the vector around point groups, and
  ;; point may stand on an element — the subject widens out to the
  ;; vector holding it.
  (maf-push "f([a, b, c], w)")
  (maf-push "2")
  (progn (calc-cursor-stack-index 2) (beginning-of-line)
         (search-forward "b") (backward-char 1) nil)
  (call-interactively 'mafcmd-unique-groups)
  (cl-assert (ug-top= "f([[a,b],[a,c],[b,c]], w)"))
  (cl-assert (= (calc-stack-size) 1))
  (calc-pop (calc-stack-size))

  ;; The widening stops at the innermost vector: point inside the inner
  ;; vector groups that one, not the matrix around it.
  (maf-push "[[a, b, c], [p, q, r]]")
  (maf-push "2")
  (progn (calc-cursor-stack-index 2) (beginning-of-line)
         (search-forward "q") (backward-char 1) nil)
  (call-interactively 'mafcmd-unique-groups)
  (cl-assert (ug-top= "[[a,b,c], [[p,q],[p,r],[q,r]]]"))
  (calc-pop (calc-stack-size))

  ;; A sub-formula with no vector around it commits unchanged.
  (maf-push "f(x + 1, w)")
  (maf-push "2")
  (progn (calc-cursor-stack-index 2) (beginning-of-line)
         (search-forward "x") (backward-char 1) nil)
  (call-interactively 'mafcmd-unique-groups)
  (cl-assert (ug-top= "f(x + 1, w)"))
  (calc-pop (calc-stack-size))

  ;; Keep-args leaves both operands below the result.
  (maf-push "[a, b, c]")
  (maf-push "2")
  (call-interactively 'calc-keep-args)
  (call-interactively 'mafcmd-unique-groups)
  (cl-assert (= (calc-stack-size) 3))
  (cl-assert (ug-top= "[[a,b],[a,c],[b,c]]"))
  (cl-assert (equal (calc-top 3 'full)
                    (math-normalize (math-read-expr "[a, b, c]"))))
  (calc-pop (calc-stack-size))

  ;; The real binding, through the keymap.
  (maf-push "[a, b, c, d]")
  (maf-push "3")
  (let* ((buf (get-buffer "*Calculator*"))
         (win (get-buffer-window buf t)))
    (cl-assert win)
    (with-selected-window win
      (with-current-buffer buf
        (execute-kbd-macro (kbd "l g")))))
  (cl-assert (ug-top= "[[a,b,c],[a,b,d],[a,c,d],[b,c,d]]"))
  (cl-assert (= (calc-stack-size) 1))
  (calc-pop (calc-stack-size)))
