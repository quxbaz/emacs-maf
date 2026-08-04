;; mafcmd-vconcat always builds a vector.
;;
;; Calc's own | only concatenates when it can prove both operands are
;; objects, vectors, or declared scalars, and otherwise leaves the
;; symbolic `a | b' behind. maf's | commits to the vector reading, so a
;; symbolic operand concatenates like any other.

(maf-step
  ;; Two undeclared variables — the case calc leaves as `x | y'.
  (maf-push "x")
  (maf-push "y")
  (goto-char (point-max))
  (call-interactively 'mafcmd-vconcat)
  (cl-assert (equal (calc-top 1 'full) '(vec (var x var-x) (var y var-y))))
  (calc-pop 1)

  ;; Same through the real keypress, via maf-mode's binding of |.
  (maf-push "x")
  (maf-push "y")
  (goto-char (point-max))
  (execute-kbd-macro (kbd "|"))
  (cl-assert (equal (calc-top 1 'full) '(vec (var x var-x) (var y var-y))))
  (calc-pop 1)

  ;; Numbers concatenate as they always did.
  (maf-push "1")
  (maf-push "2")
  (goto-char (point-max))
  (call-interactively 'mafcmd-vconcat)
  (cl-assert (equal (calc-top 1 'full) '(vec 1 2)))
  (calc-pop 1)

  ;; A mixed pair: calc leaves `1 | x', maf gives [1, x].
  (maf-push "1")
  (maf-push "x")
  (goto-char (point-max))
  (call-interactively 'mafcmd-vconcat)
  (cl-assert (equal (calc-top 1 'full) '(vec 1 (var x var-x))))
  (calc-pop 1)

  ;; Vector operands splice rather than nest, on either side, even when
  ;; the other operand is symbolic.
  (maf-push "[1, 2]")
  (maf-push "x")
  (goto-char (point-max))
  (call-interactively 'mafcmd-vconcat)
  (cl-assert (equal (calc-top 1 'full) '(vec 1 2 (var x var-x))))
  (calc-pop 1)

  (maf-push "x")
  (maf-push "[1, 2]")
  (goto-char (point-max))
  (call-interactively 'mafcmd-vconcat)
  (cl-assert (equal (calc-top 1 'full) '(vec (var x var-x) 1 2)))
  (calc-pop 1)

  (maf-push "[1, 2]")
  (maf-push "[3, 4]")
  (goto-char (point-max))
  (call-interactively 'mafcmd-vconcat)
  (cl-assert (equal (calc-top 1 'full) '(vec 1 2 3 4)))
  (calc-pop 1)

  ;; A plain vector joined with a matrix becomes a row of it, as in calc.
  (maf-push "[[1, 2]]")
  (maf-push "[3, 4]")
  (goto-char (point-max))
  (call-interactively 'mafcmd-vconcat)
  (cl-assert (equal (calc-top 1 'full) '(vec (vec 1 2) (vec 3 4))))
  (calc-pop 1)

  ;; I | reverses the operands and still always builds a vector.
  (maf-push "x")
  (maf-push "y")
  (goto-char (point-max))
  (call-interactively 'calc-inverse)
  (call-interactively 'mafcmd-vconcat)
  (cl-assert (equal (calc-top 1 'full) '(vec (var y var-y) (var x var-x))))
  (calc-pop 1)

  ;; H | is append, unchanged: it joins two vectors.
  (maf-push "[1, 2]")
  (maf-push "[3, 4]")
  (goto-char (point-max))
  (call-interactively 'calc-hyperbolic)
  (call-interactively 'mafcmd-vconcat)
  (cl-assert (equal (calc-top 1 'full) '(vec 1 2 3 4)))
  (calc-pop 1)

  ;; I H | is appendrev.
  (maf-push "[1, 2]")
  (maf-push "[3, 4]")
  (goto-char (point-max))
  (call-interactively 'calc-inverse)
  (call-interactively 'calc-hyperbolic)
  (call-interactively 'mafcmd-vconcat)
  (cl-assert (equal (calc-top 1 'full) '(vec 3 4 1 2)))
  (calc-pop 1)

  ;; A relation is an element, not a subject to run once per side: the
  ;; | family takes :map -1 (see the table in maf-cmds.el). Two stacked
  ;; equations give the vector of equations — calc's own spelling of a
  ;; system — where the per-side mapping would pair them into the one
  ;; equation [x, y] = [1, 2].
  (maf-push "x = 1")
  (maf-push "y = 2")
  (goto-char (point-max))
  (call-interactively 'mafcmd-vconcat)
  (cl-assert (equal (calc-top 1 'full)
                    '(vec (calcFunc-eq (var x var-x) 1)
                          (calcFunc-eq (var y var-y) 2))))
  (calc-pop 1)

  ;; Same through the real keypress.
  (maf-push "x = 1")
  (maf-push "y = 2")
  (goto-char (point-max))
  (execute-kbd-macro (kbd "|"))
  (cl-assert (equal (calc-top 1 'full)
                    '(vec (calcFunc-eq (var x var-x) 1)
                          (calcFunc-eq (var y var-y) 2))))
  (calc-pop 1)

  ;; And from the top equation's own line, not just from home — the
  ;; margin resolves the entry whole rather than as an equation target.
  (maf-push "x = 1")
  (maf-push "y = 2")
  (goto-char (point-max))
  (forward-line -1)
  (end-of-line)
  (call-interactively 'mafcmd-vconcat)
  (cl-assert (equal (calc-top 1 'full)
                    '(vec (calcFunc-eq (var x var-x) 1)
                          (calcFunc-eq (var y var-y) 2))))
  (calc-pop 1)

  ;; One equation and a scalar: the equation stays one element.
  (maf-push "x = 1")
  (maf-push "2")
  (goto-char (point-max))
  (call-interactively 'mafcmd-vconcat)
  (cl-assert (equal (calc-top 1 'full)
                    '(vec (calcFunc-eq (var x var-x) 1) 2)))
  (calc-pop 1)

  ;; A vector operand splices around a relation as around anything else.
  (maf-push "[a, b]")
  (maf-push "y = 2")
  (goto-char (point-max))
  (call-interactively 'mafcmd-vconcat)
  (cl-assert (equal (calc-top 1 'full)
                    '(vec (var a var-a) (var b var-b)
                          (calcFunc-eq (var y var-y) 2))))
  (calc-pop 1)

  ;; The variants opt out too: I | reverses, H | appends vectors of
  ;; equations.
  (maf-push "x = 1")
  (maf-push "y = 2")
  (goto-char (point-max))
  (call-interactively 'calc-inverse)
  (call-interactively 'mafcmd-vconcat)
  (cl-assert (equal (calc-top 1 'full)
                    '(vec (calcFunc-eq (var y var-y) 2)
                          (calcFunc-eq (var x var-x) 1))))
  (calc-pop 1)

  (maf-push "[x = 1]")
  (maf-push "[y = 2]")
  (goto-char (point-max))
  (call-interactively 'calc-hyperbolic)
  (call-interactively 'mafcmd-vconcat)
  (cl-assert (equal (calc-top 1 'full)
                    '(vec (calcFunc-eq (var x var-x) 1)
                          (calcFunc-eq (var y var-y) 2))))
  (calc-pop 1)

  ;; The opt-out is the | family's alone — arithmetic still pairs two
  ;; equations side by side.
  (maf-push "x = 1")
  (maf-push "y = 2")
  (goto-char (point-max))
  (call-interactively 'mafcmd-add)
  (cl-assert (equal (calc-top 1 'full)
                    '(calcFunc-eq (+ (var x var-x) (var y var-y)) 3)))
  (calc-pop 1))
