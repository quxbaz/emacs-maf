(maf-step
  ;; Quadrant I passes through; the axis at 0 is its own reference angle.
  (maf-push "30")
  (call-interactively 'mafcmd-ref-angle)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "30"))
  (calc-pop (calc-stack-size))

  ;; Quadrant II folds to 180 - x.
  (maf-push "135")
  (call-interactively 'mafcmd-ref-angle)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "45"))
  (calc-pop (calc-stack-size))

  ;; Quadrant III folds to x - 180.
  (maf-push "210")
  (call-interactively 'mafcmd-ref-angle)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "30"))
  (calc-pop (calc-stack-size))

  ;; Quadrant IV folds to 360 - x.
  (maf-push "300")
  (call-interactively 'mafcmd-ref-angle)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "60"))
  (calc-pop (calc-stack-size))

  ;; Quadrant boundaries: each belongs to the quadrant above it, so 90
  ;; and 270 give 90 and 180 gives 0.
  (maf-push "90")
  (call-interactively 'mafcmd-ref-angle)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "90"))
  (calc-pop (calc-stack-size))

  (maf-push "180")
  (call-interactively 'mafcmd-ref-angle)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "0"))
  (calc-pop (calc-stack-size))

  (maf-push "270")
  (call-interactively 'mafcmd-ref-angle)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "90"))
  (calc-pop (calc-stack-size))

  (maf-push "360")
  (call-interactively 'mafcmd-ref-angle)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "0"))
  (calc-pop (calc-stack-size))

  ;; Past a full turn: wraps first, however many turns.
  (maf-push "750")
  (call-interactively 'mafcmd-ref-angle)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "30"))
  (calc-pop (calc-stack-size))

  (maf-push "855")
  (call-interactively 'mafcmd-ref-angle)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "45"))
  (calc-pop (calc-stack-size))

  ;; Negative angles wrap positive before folding.
  (maf-push "-45")
  (call-interactively 'mafcmd-ref-angle)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "45"))
  (calc-pop (calc-stack-size))

  (maf-push "-270")
  (call-interactively 'mafcmd-ref-angle)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "90"))
  (calc-pop (calc-stack-size))

  (maf-push "-360")
  (call-interactively 'mafcmd-ref-angle)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "0"))
  (calc-pop (calc-stack-size))

  ;; Floats keep their fraction: the folding subtraction runs on the
  ;; angle itself, so 100.7 gives 79.3 and not 79.3000000001.
  (maf-push "400.5")
  (call-interactively 'mafcmd-ref-angle)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "40.5"))
  (calc-pop (calc-stack-size))

  (maf-push "100.7")
  (call-interactively 'mafcmd-ref-angle)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "79.3"))
  (calc-pop (calc-stack-size))

  ;; An expression carrying pi folds against pi, not 180, even in the
  ;; default degrees mode — and exactly, without floating the ratio.
  (maf-push "5 pi / 4")
  (call-interactively 'mafcmd-ref-angle)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "pi / 4"))
  (calc-pop (calc-stack-size))

  (maf-push "7 pi / 6")
  (call-interactively 'mafcmd-ref-angle)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "pi / 6"))
  (calc-pop (calc-stack-size))

  ;; Exact pi multiples stay exact.
  (maf-push "pi / 6")
  (call-interactively 'mafcmd-ref-angle)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "pi / 6"))
  (calc-pop (calc-stack-size))

  (maf-push "-pi / 3")
  (call-interactively 'mafcmd-ref-angle)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "pi / 3"))
  (calc-pop (calc-stack-size))

  ;; A full turn of pi wraps to the axis.
  (maf-push "2 pi")
  (call-interactively 'mafcmd-ref-angle)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "0"))
  (calc-pop (calc-stack-size))

  ;; Radians mode folds a bare number against pi, exactly: 4 radians
  ;; lands in quadrant III, so the reference angle is 4 - pi.
  (progn (calc-radians-mode) nil)
  (maf-push "4")
  (call-interactively 'mafcmd-ref-angle)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "4 - pi"))
  (calc-pop (calc-stack-size))
  (progn (calc-degrees-mode 1) nil)
  (cl-assert (eq calc-angle-mode 'deg))

  ;; An hms angle is degrees by construction and stays hms, exactly:
  ;; 200@ 30' 15" is in quadrant III, giving 20@ 30' 15".
  (maf-push "200@ 30' 15\"")
  (call-interactively 'mafcmd-ref-angle)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "20@ 30' 15\""))
  (calc-pop (calc-stack-size))

  ;; An hms angle keeps its degrees even while calc is in radians mode.
  (progn (calc-radians-mode) nil)
  (maf-push "100@ 0' 0\"")
  (call-interactively 'mafcmd-ref-angle)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "80@ 0' 0\""))
  (calc-pop (calc-stack-size))
  (progn (calc-degrees-mode 1) nil)

  ;; No determined quadrant: a free variable and a complex number both
  ;; commit unchanged rather than erroring.
  (maf-push "x")
  (call-interactively 'mafcmd-ref-angle)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "x"))
  (calc-pop (calc-stack-size))

  (maf-push "(1, 2)")
  (call-interactively 'mafcmd-ref-angle)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "(1, 2)"))
  (calc-pop (calc-stack-size))

  ;; Contextual: fold only the sub-formula at point.
  (maf-push "y + 210")
  (progn (calc-cursor-stack-index 1)
         (search-forward "210" (line-end-position))
         (backward-char 1)
         (call-interactively 'mafcmd-ref-angle))
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "y + 30"))
  (calc-pop (calc-stack-size))

  ;; Equation: each side folds independently, and a side with no
  ;; quadrant passes through instead of aborting the whole command.
  (maf-push "135 = 300")
  (progn (calc-cursor-stack-index 1) (end-of-line)
         (call-interactively 'mafcmd-ref-angle))
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "45 = 60"))
  (calc-pop (calc-stack-size))

  (maf-push "a = 210")
  (progn (calc-cursor-stack-index 1) (end-of-line)
         (call-interactively 'mafcmd-ref-angle))
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "a = 30"))
  (calc-pop (calc-stack-size))

  ;; The M-l binding reaches the command through the keymaps.
  (maf-push "225")
  (progn (calc-cursor-stack-index 0)
         (execute-kbd-macro (kbd "M-l")) nil)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "45"))
  (calc-pop (calc-stack-size)))
