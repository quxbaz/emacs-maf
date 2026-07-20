(maf-step
  (calc-big-language)
  ;; a/b renders across three lines in Big mode — the shape maf-edit's
  ;; one-entry-per-line model can't handle.
  (calc-push '(/ (var a var-a) (var b var-b)))
  (calc-refresh)

  ;; maf-edit refuses to start under the Big display language, leaving
  ;; the display and stack untouched.
  (cl-assert (not (ignore-errors (call-interactively 'maf-edit) t)))
  (cl-assert (not maf-edit-mode))
  (cl-assert (eq calc-language 'big))
  (cl-assert (equal (calc-top-n 1) '(/ (var a var-a) (var b var-b))))

  ;; In normal display it works as usual.
  (calc-normal-language)
  (call-interactively 'maf-edit)
  (cl-assert maf-edit-mode)
  (call-interactively 'maf-edit-discard)
  (cl-assert (not maf-edit-mode))

  (calc-pop (calc-stack-size)))
