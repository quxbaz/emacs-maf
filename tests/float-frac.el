(maf-step
  ;; Floats present: toward exact, and the echo names the landing.
  (maf-push "0.75 x + 2")
  (goto-char (point-max))
  (call-interactively 'mafcmd-float-frac)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "3:4 x + 2"))
  (calc-pop 1)

  ;; Fractions only: toward floats.
  (maf-push "3:4 x + 2")
  (goto-char (point-max))
  (call-interactively 'mafcmd-float-frac)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "0.75 x + 2"))
  (calc-pop 1)

  ;; Two presses round-trip.
  (maf-push "6 x + 8:3")
  (goto-char (point-max))
  (call-interactively 'mafcmd-float-frac)
  (call-interactively 'mafcmd-float-frac)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "6 x + 8:3"))
  (calc-pop 1)

  ;; Mixed: exactness wins, then the toggle is a clean flip.
  (maf-push "0.5 y + 1:4 x")
  (goto-char (point-max))
  (call-interactively 'mafcmd-float-frac)
  (cl-assert (string= (math-format-value (calc-top 1 'full))
                      "1:2 y + 1:4 x"))
  (calc-pop 1)

  ;; An equation goes one way as a whole: sides that would flip
  ;; opposite directions instead both follow the floats, and the
  ;; relation survives its sides becoming equal.
  (maf-push "0.5 = 1:2")
  (progn (goto-char (point-min)) (end-of-line))
  (call-interactively 'mafcmd-float-frac)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "1:2 = 1:2"))
  (calc-pop 1)

  ;; Tolerance prefix arg rides the frac direction.
  (maf-push "3.14159")
  (goto-char (point-max))
  (let ((current-prefix-arg 3))
    (call-interactively 'mafcmd-float-frac))
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "22:7"))
  (calc-pop 1)

  ;; Subexpr: the direction reads off the part under point alone.
  (maf-push "0.75 x + 1:2")
  (progn (goto-char (point-min)) (search-forward "0.75") (backward-char 2))
  (call-interactively 'mafcmd-float-frac)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "3:4 x + 1:2"))
  (calc-pop 1)

  ;; Neither kind: refuses, stack untouched.
  (maf-push "6 x + 2")
  (goto-char (point-max))
  (cl-assert (condition-case nil
                 (progn (call-interactively 'mafcmd-float-frac) nil)
               (user-error t)))
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "6 x + 2"))
  (calc-pop 1)

  ;; The I flag forces the float, even with floats present.
  (maf-push "0.5 y + 1:4 x")
  (goto-char (point-max))
  (call-interactively 'calc-inverse)
  (call-interactively 'mafcmd-float-frac)
  (cl-assert (string= (math-format-value (calc-top 1 'full))
                      "0.5 y + 0.25 x"))
  (calc-pop 1)

  ;; The H flag routes to the pervasive float-all.
  (maf-push "6 x + 8:3")
  (goto-char (point-max))
  (call-interactively 'calc-hyperbolic)
  (call-interactively 'mafcmd-float-frac)
  (cl-assert (string= (math-format-value (calc-top 1 'full))
                      "6. x + 2.66666666667"))
  (calc-pop 1))
