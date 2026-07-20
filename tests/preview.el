(maf-step
  (maf-use-preview-mode 1)
  (calc-normal-language)
  (calc-push '(/ (var a var-a) (var b var-b)))
  (calc-refresh)

  ;; The active entry renders in 2D Big form for the preview, while the
  ;; stack itself stays in the one-line normal display.
  (progn (goto-char (point-min)) (search-forward "a / b") (backward-char 3))
  (cl-assert (equal (maf-preview--render) "a\n-\nb"))
  (cl-assert (string-match-p "a / b" (buffer-substring-no-properties
                                      (point-min) (point-max))))

  ;; Nothing to preview while the whole buffer is already in Big display.
  (calc-big-language)
  (cl-assert (null (maf-preview--render)))
  (calc-normal-language)
  (calc-refresh)
  (progn (goto-char (point-min)) (search-forward "a / b") (backward-char 3))
  (cl-assert (maf-preview--render))

  ;; Nothing to preview during an in-place edit session (the stack no
  ;; longer matches the edited text).
  (call-interactively 'maf-edit)
  (cl-assert (null (maf-preview--render)))
  (call-interactively 'maf-edit-discard)

  ;; Nothing to preview on an empty stack.
  (calc-pop (calc-stack-size))
  (cl-assert (null (maf-preview--render))))
