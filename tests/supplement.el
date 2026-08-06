(maf-step
  ;; Degrees mode: 180 - x, both directions.
  (calc-degrees-mode 1)
  (maf-push "30")
  (call-interactively 'mafcmd-supplement)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "150"))
  (calc-pop (calc-stack-size))

  (maf-push "150")
  (call-interactively 'mafcmd-supplement)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "30"))
  (calc-pop (calc-stack-size))

  ;; A float in degrees keeps its fraction.
  (maf-push "30.5")
  (call-interactively 'mafcmd-supplement)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "149.5"))
  (calc-pop (calc-stack-size))

  ;; Symbolic in degrees: the subtraction stands.
  (maf-push "x")
  (call-interactively 'mafcmd-supplement)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "-x + 180"))
  (calc-pop (calc-stack-size))

  ;; Pi in the expression overrides degrees mode: a pi half turn.
  (maf-push "pi/6")
  (call-interactively 'mafcmd-supplement)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "5:6 pi"))
  (calc-pop (calc-stack-size))

  ;; HMS mode takes the degrees half turn.
  (calc-hms-mode)
  (maf-push "30@ 30' 0\"")
  (call-interactively 'mafcmd-supplement)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "149@ 30' 0\""))
  (calc-pop (calc-stack-size))

  ;; Radians mode: exact stays exact — pi - 2 pi / 3 is pi / 3, not
  ;; 0.333333333333 pi.
  (calc-radians-mode)
  (maf-push "2*pi/3")
  (call-interactively 'mafcmd-supplement)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "pi / 3"))
  (calc-pop (calc-stack-size))

  ;; A float in radians switches to numeric pi.
  (maf-push "0.5")
  (call-interactively 'mafcmd-supplement)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "2.64159265359"))
  (calc-pop (calc-stack-size))

  ;; Symbolic in radians: a symbolic pi half turn.
  (maf-push "x")
  (call-interactively 'mafcmd-supplement)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "-x + pi"))
  (calc-pop (calc-stack-size))

  ;; Contextual: supplement only the sub-formula at point.
  (calc-degrees-mode 1)
  (maf-push "y + 30")
  (progn (calc-cursor-stack-index 1)
         (search-forward "30" (line-end-position))
         (backward-char 2)
         (call-interactively 'mafcmd-supplement))
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "y + 150"))
  (calc-pop (calc-stack-size))

  ;; Equation: each side supplements independently.
  (maf-push "30 = 150")
  (progn (calc-cursor-stack-index 1) (end-of-line)
         (call-interactively 'mafcmd-supplement))
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "150 = 30"))
  (calc-pop (calc-stack-size))

  ;; The binding: M-s runs it on the top entry at home.
  (maf-push "45")
  (progn (calc-cursor-stack-index 0)
         (execute-kbd-macro (kbd "M-s")) nil)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "135"))
  (calc-pop (calc-stack-size)))
