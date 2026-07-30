(maf-step
  ;; Mod 360 wraps: past a full turn, negative, float, symbolic.
  (maf-push "400")
  (call-interactively 'mafcmd-mod-360)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "40"))
  (calc-pop (calc-stack-size))

  (maf-push "-30")
  (call-interactively 'mafcmd-mod-360)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "330"))
  (calc-pop (calc-stack-size))

  (maf-push "400.5")
  (call-interactively 'mafcmd-mod-360)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "40.5"))
  (calc-pop (calc-stack-size))

  (maf-push "x")
  (call-interactively 'mafcmd-mod-360)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "x % 360"))
  (calc-pop (calc-stack-size))

  ;; H M-o routes to the mod-180 variant via the Hyperbolic flag.
  (maf-push "270")
  (progn (calc-cursor-stack-index 0)
         (execute-kbd-macro (kbd "H M-o")) nil)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "90"))
  (calc-pop (calc-stack-size)))
