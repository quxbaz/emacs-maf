;; On-demand RaTeX preview. The renderer is mocked so this durable test
;; has no external executable requirement; the live drive covers the
;; installed binary itself.

(maf-step
  (setq maf--pretty-mode-stash maf-use-pretty-mode
        maf--render-svg-fixture
        "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"10\" height=\"10\"><path d=\"M0 0h10v10H0z\"/></svg>")

  ;; The module shadows G while it is on, and hands the key back to the
  ;; Big-display preview — not to nothing — when it goes off.
  (maf-use-pretty-mode 1)
  (cl-assert (eq (key-binding (kbd "G")) #'maf-pretty))
  (maf-use-pretty-mode -1)
  (cl-assert (eq (key-binding (kbd "G")) #'maf-preview-show))
  (maf-use-pretty-mode 1)

  ;; Point on an older entry selects that whole entry. Calc supplies the
  ;; LaTeX, the renderer receives exactly that string, and neither stack
  ;; contents nor display language changes.
  (maf-push "sqrt(x) / 3")
  (maf-push "a + b")
  (progn (calc-cursor-stack-index 2)
         (search-forward "sqrt" (line-end-position))
         (backward-char 2))
  (setq maf--pretty-latex nil
        maf--pretty-source-window (selected-window))
  (cl-letf (((symbol-function 'maf-pretty--ratex)
             (lambda (latex)
               (setq maf--pretty-latex latex)
               maf--render-svg-fixture)))
    (call-interactively 'maf-pretty)
    ;; The preview takes the selection, and the two windows are an
    ;; even split of the height they came from.
    (let ((pretty-window (get-buffer-window maf-pretty--buffer)))
      (cl-assert (eq (selected-window) pretty-window))
      (cl-assert (<= (abs (- (window-total-height maf--pretty-source-window)
                             (window-total-height pretty-window)))
                     1))
      ;; Dismissing takes the window down, hands the height back, and
      ;; returns focus to the invoking window.
      (maf-pretty-quit)
      (cl-assert (null (get-buffer-window maf-pretty--buffer)))
      (cl-assert (eq (selected-window) maf--pretty-source-window))))
  ;; The radicand carries its strut, so every radical draws one height
  ;; (the \mathstrut pass in `maf-pretty--latex').
  (cl-assert (string= maf--pretty-latex "\\frac{\\sqrt{\\mathstrut x}}{3}"))
  (cl-assert (= (calc-stack-size) 2))
  (cl-assert (null calc-language))
  (with-current-buffer maf-pretty--buffer
    (cl-assert (derived-mode-p 'maf-pretty-mode))
    (cl-assert (eq (car-safe (get-text-property (point-min) 'display))
                   'image)))

  ;; At home the same command renders the top entry.
  (goto-char (point-max))
  (setq maf--pretty-latex nil)
  (cl-letf (((symbol-function 'maf-pretty--ratex)
             (lambda (latex)
               (setq maf--pretty-latex latex)
               maf--render-svg-fixture)))
    (call-interactively 'maf-pretty))
  (cl-assert (string= maf--pretty-latex "a + b"))

  ;; A missing executable and an empty stack both fail clearly before a
  ;; preview can pretend to have succeeded.
  (let ((maf-pretty-program "/definitely/not/a/ratex-renderer"))
    (cl-assert (condition-case nil
                   (progn (maf-pretty--program) nil)
                 (user-error t))))
  (calc-pop (calc-stack-size))
  (cl-assert (condition-case nil
                 (progn (maf-pretty--entry) nil)
               (user-error t)))

  ;; Grouping delimiters grow to \left/\right pairs, so superscripts
  ;; sit inside their parens; a function call's parens keep their
  ;; tight spacing, and a shed script paren stays shed
  ;; (`maf-pretty--grow-parens', the pipeline's last pass).
  (cl-assert (equal (maf-pretty--latex (math-read-expr "(a + b^2) c"))
                    "\\left(a + b^2\\right) c"))
  (cl-assert (equal (maf-pretty--latex (math-read-expr "sin(x) + x^(-n)"))
                    "\\sin(x) + x^{-n}"))
  (cl-assert (equal (maf-pretty--latex (math-read-expr "[1 .. inf)"))
                    "\\left[1 \\ldots \\infty\\right)"))

  ;; Restore the shared dev session and remove the preview window/buffer.
  (progn
    (when-let ((win (get-buffer-window maf-pretty--buffer)))
      (quit-window nil win))
    (when-let ((buf (get-buffer maf-pretty--buffer)))
      (kill-buffer buf))
    (unless maf--pretty-mode-stash
      (maf-use-pretty-mode -1))))
