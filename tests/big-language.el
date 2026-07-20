(maf-step
  ;; Baseline: normal one-line language.
  (cl-assert (null calc-language))

  ;; A fraction makes the big/normal rendering difference visible.
  (maf-push "1:3")
  (setq big-test-value (calc-top-n 1))
  (setq big-test-normal (buffer-substring-no-properties (point-min) (point-max)))

  ;; Toggle on: Big language re-renders the stack (multi-line), and the
  ;; stack value itself is untouched.
  (call-interactively 'maf-toggle-big-language)
  (cl-assert (eq calc-language 'big))
  (cl-assert (not (equal (buffer-substring-no-properties (point-min) (point-max))
                         big-test-normal)))
  (cl-assert (equal (calc-top-n 1) big-test-value))

  ;; Toggle off: normal language, layout and value restored exactly.
  (call-interactively 'maf-toggle-big-language)
  (cl-assert (null calc-language))
  (cl-assert (equal (buffer-substring-no-properties (point-min) (point-max))
                    big-test-normal))
  (cl-assert (equal (calc-top-n 1) big-test-value))

  (calc-pop (calc-stack-size)))
