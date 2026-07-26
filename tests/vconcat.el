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
  (calc-pop 1))
