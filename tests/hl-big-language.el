(maf-step
  (maf-use-hl-mode 1)                     ;; ensure the module (and its advice) is on
  (calc-normal-language)
  (calc-push '(+ (var a var-a) (var b var-b)))

  ;; Normal display: highlighting is active.
  (cl-assert (null calc-language))
  (cl-assert maf-hl-mode)

  ;; Big display disables maf-hl-mode.
  (call-interactively 'maf-toggle-big-language)
  (cl-assert (eq calc-language 'big))
  (cl-assert (not maf-hl-mode))

  ;; Returning to normal re-enables it.
  (call-interactively 'maf-toggle-big-language)
  (cl-assert (null calc-language))
  (cl-assert maf-hl-mode)

  ;; The same holds for calc's own language commands, not just
  ;; maf-toggle-big-language — the advice sits on their shared choke point.
  (calc-big-language)
  (cl-assert (not maf-hl-mode))
  (calc-normal-language)
  (cl-assert maf-hl-mode)

  (calc-pop (calc-stack-size)))
