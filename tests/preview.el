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

  ;; The preview shows the entry as it stands on the stack, not what calc
  ;; would make of it: an unsimplified formula previews unsimplified,
  ;; matching its stack line (`calc-top', not the normalizing
  ;; `calc-top-n', which would preview this one as "5 a").
  (progn (calc-push '(+ (* 2 (var a var-a)) (* 3 (var a var-a))))
         (calc-refresh)
         (goto-char (point-min)) (search-forward "2 a + 3 a") (backward-char 3))
  (cl-assert (equal (maf-preview--render) "2 a + 3 a"))
  (progn (calc-pop 1) (calc-refresh)
         (goto-char (point-min)) (search-forward "a / b") (backward-char 3))

  ;; The rendered entry is laid out as a bordered, titled panel whose
  ;; rows are all one width — what both backends put on screen.
  (cl-assert (equal (maf-preview--panel-rows "a\n-\nb" 40 10)
                    '("┌─PREVIEW──┐"
                      "│ a        │"
                      "│ -        │"
                      "│ b        │"
                      "└──────────┘")))

  ;; The panel is clipped to the room it is given, in both directions,
  ;; with an ellipsis for what was cut — and refused outright when even
  ;; the title would not fit.
  (cl-assert (equal (maf-preview--panel-rows "abcdefghijklmnopqrst" 16 10)
                    '("┌─PREVIEW──────┐"
                      "│ abcdefghijk… │"
                      "└──────────────┘")))
  (cl-assert (equal (maf-preview--panel-rows "1\n2\n3\n4" 40 5)
                    '("┌─PREVIEW──┐"
                      "│ 1        │"
                      "│ 2        │"
                      "│ …        │"
                      "└──────────┘")))
  (cl-assert (null (maf-preview--panel-rows "x" 11 10)))

  ;; Without a child frame — on a text terminal, or with no posframe —
  ;; that panel is drawn inside the window itself. It lives entirely in
  ;; overlay strings anchored below the window's first line, so it stays
  ;; at the top of the view rather than following the entry, and the
  ;; buffer's own text is left alone.
  (when (not (maf-preview--posframe-p))
    (maf-preview--update)
    (let ((drawn (mapconcat (lambda (ov)
                              (or (overlay-get ov 'display)
                                  (overlay-get ov 'after-string)
                                  ""))
                            ;; Pushed as they are drawn, so the topmost
                            ;; row of the panel is the last one.
                            (reverse maf-preview--overlays)
                            "\n")))
      (cl-assert (string-match-p "PREVIEW" drawn))
      (cl-assert (string-match-p "│ a" drawn))
      (cl-assert (not (string-match-p "PREVIEW" (buffer-substring-no-properties
                                                 (point-min) (point-max)))))
      (cl-assert (= (line-number-at-pos
                     (overlay-start (car (last maf-preview--overlays))))
                    (1+ (line-number-at-pos (window-start))))))

    ;; Turning the mode off takes the panel down with it.
    (maf-preview-mode -1)
    (cl-assert (null maf-preview--overlays))
    (maf-preview-mode 1))

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
