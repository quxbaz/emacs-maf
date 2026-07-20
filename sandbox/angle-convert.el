(maf-step
  ;; Radians to degrees: exact multiples of pi convert exactly.
  (maf-push "pi/2")
  (call-interactively 'mafcmd-to-degrees)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "90"))
  (calc-pop (calc-stack-size))

  ;; Float radians use numeric pi.
  (maf-push "1.5708")
  (call-interactively 'mafcmd-to-degrees)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "90.0002104591"))
  (calc-pop (calc-stack-size))

  ;; Symbolic radians stay symbolic.
  (maf-push "r")
  (call-interactively 'mafcmd-to-degrees)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "180 r / pi"))
  (calc-pop (calc-stack-size))

  ;; Degrees to radians: a factor of pi, exact in, exact out.
  (maf-push "30")
  (call-interactively 'mafcmd-to-radians)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "pi / 6"))
  (calc-pop (calc-stack-size))

  ;; Float degrees keep a float factor of pi.
  (maf-push "45.0")
  (call-interactively 'mafcmd-to-radians)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "0.25 pi"))
  (calc-pop (calc-stack-size))

  ;; The pair inverts: I l r runs to-degrees via the Inverse flag.
  (maf-push "pi / 6")
  (progn (calc-cursor-stack-index 0)
         (execute-kbd-macro (kbd "I l r")) nil)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "30"))
  (calc-pop (calc-stack-size))

  ;; Contextual: convert only the sub-formula at point — the division
  ;; node under its / glyph.
  (maf-push "y + pi/2")
  (progn (calc-cursor-stack-index 1)
         (search-forward "/" (line-end-position))
         (backward-char 1)
         (call-interactively 'mafcmd-to-degrees))
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "y + 90"))
  (calc-pop (calc-stack-size))

  ;; Equation: each side converts independently.
  (maf-push "pi/2 = pi/6")
  (progn (calc-cursor-stack-index 1) (end-of-line)
         (call-interactively 'mafcmd-to-degrees))
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "90 = 30"))
  (calc-pop (calc-stack-size)))
