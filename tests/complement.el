(maf-step
  ;; Degrees mode: 90 - x, both directions.
  (calc-degrees-mode 1)
  (maf-push "30")
  (call-interactively 'mafcmd-complement)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "60"))
  (calc-pop (calc-stack-size))

  (maf-push "60")
  (call-interactively 'mafcmd-complement)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "30"))
  (calc-pop (calc-stack-size))

  ;; An obtuse angle complements negative; nothing clamps it.
  (maf-push "100")
  (call-interactively 'mafcmd-complement)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "-10"))
  (calc-pop (calc-stack-size))

  ;; A float in degrees keeps its fraction.
  (maf-push "30.5")
  (call-interactively 'mafcmd-complement)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "59.5"))
  (calc-pop (calc-stack-size))

  ;; An exact fraction stays exact.
  (maf-push "1/3")
  (call-interactively 'mafcmd-complement)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "269:3"))
  (calc-pop (calc-stack-size))

  ;; Symbolic in degrees: the subtraction stands.
  (maf-push "x")
  (call-interactively 'mafcmd-complement)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "-x + 90"))
  (calc-pop (calc-stack-size))

  ;; Pi in the expression overrides degrees mode: a pi / 2 quarter turn.
  (maf-push "pi/6")
  (call-interactively 'mafcmd-complement)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "pi / 3"))
  (calc-pop (calc-stack-size))

  ;; The self-complementary angle comes back to itself.
  (maf-push "pi/4")
  (call-interactively 'mafcmd-complement)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "pi / 4"))
  (calc-pop (calc-stack-size))

  ;; HMS mode takes the degrees quarter turn, exactly.
  (calc-hms-mode)
  (maf-push "30@ 30' 0\"")
  (call-interactively 'mafcmd-complement)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "59@ 30' 0\""))
  (calc-pop (calc-stack-size))

  ;; Radians mode: exact stays exact — pi / 2 - pi / 3 is pi / 6, not
  ;; 0.166666666667 pi.
  (calc-radians-mode)
  (maf-push "pi/3")
  (call-interactively 'mafcmd-complement)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "pi / 6"))
  (calc-pop (calc-stack-size))

  ;; Past a quarter turn in radians the difference goes negative, which
  ;; calc's own simplifier writes as a negative denominator.
  (maf-push "2*pi/3")
  (call-interactively 'mafcmd-complement)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "pi / -6"))
  (calc-pop (calc-stack-size))

  ;; A float in radians switches to numeric pi.
  (maf-push "0.5")
  (call-interactively 'mafcmd-complement)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "1.0707963268"))
  (calc-pop (calc-stack-size))

  ;; Symbolic in radians: a symbolic pi / 2 quarter turn.
  (maf-push "x")
  (call-interactively 'mafcmd-complement)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "-x + pi / 2"))
  (calc-pop (calc-stack-size))

  ;; An hms value is degrees by construction, so it takes 90 even in
  ;; radians mode rather than a symbolic pi / 2 it cannot subtract.
  (maf-push "30@ 30' 0\"")
  (call-interactively 'mafcmd-complement)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "59@ 30' 0\""))
  (calc-pop (calc-stack-size))

  ;; Contextual: complement only the sub-formula at point.
  (calc-degrees-mode 1)
  (maf-push "y + 30")
  (progn (calc-cursor-stack-index 1)
         (search-forward "30" (line-end-position))
         (backward-char 2)
         (call-interactively 'mafcmd-complement))
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "y + 60"))
  (calc-pop (calc-stack-size))

  ;; Equation: each side complements independently.
  (maf-push "30 = 60")
  (progn (calc-cursor-stack-index 1) (end-of-line)
         (call-interactively 'mafcmd-complement))
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "60 = 30"))
  (calc-pop (calc-stack-size))

  ;; The binding: M-c runs it on the top entry at home.
  (maf-push "45")
  (progn (calc-cursor-stack-index 0)
         (execute-kbd-macro (kbd "M-c")) nil)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "45"))
  (calc-pop (calc-stack-size))

  ;; And the supplement still works after the shared helper: M-s on the
  ;; same shapes.
  (maf-push "30")
  (progn (calc-cursor-stack-index 0)
         (execute-kbd-macro (kbd "M-s")) nil)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "150"))
  (calc-pop (calc-stack-size))

  (calc-radians-mode)
  (maf-push "30@ 30' 0\"")
  (call-interactively 'mafcmd-supplement)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "149@ 30' 0\""))
  (calc-pop (calc-stack-size))
  (calc-degrees-mode 1))
