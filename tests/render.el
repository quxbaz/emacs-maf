;; On-demand RaTeX preview. The renderer is mocked so this durable test
;; has no external executable requirement; the live drive covers the
;; installed binary itself.

(maf-step
  (setq maf--render-mode-stash maf-use-render-mode
        maf--render-svg-fixture
        "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"10\" height=\"10\"><path d=\"M0 0h10v10H0z\"/></svg>")

  ;; The module owns the on-demand binding and removes it when off.
  (maf-use-render-mode 1)
  (cl-assert (eq (key-binding (kbd "l t")) #'maf-render))
  (maf-use-render-mode -1)
  (cl-assert (not (eq (key-binding (kbd "l t")) #'maf-render)))
  (maf-use-render-mode 1)

  ;; Point on an older entry selects that whole entry. Calc supplies the
  ;; LaTeX, the renderer receives exactly that string, and neither stack
  ;; contents nor display language changes.
  (maf-push "sqrt(x) / 3")
  (maf-push "a + b")
  (progn (calc-cursor-stack-index 2)
         (search-forward "sqrt" (line-end-position))
         (backward-char 2))
  (setq maf--render-latex nil
        maf--render-source-window (selected-window))
  (cl-letf (((symbol-function 'maf-render--ratex)
             (lambda (latex)
               (setq maf--render-latex latex)
               maf--render-svg-fixture)))
    (call-interactively 'maf-render))
  (cl-assert (string= maf--render-latex "\\frac{\\sqrt{x}}{3}"))
  (cl-assert (= (calc-stack-size) 2))
  (cl-assert (null calc-language))
  (with-current-buffer maf-render--buffer
    (cl-assert (derived-mode-p 'maf-render-mode))
    (cl-assert (eq (car-safe (get-text-property (point-min) 'display))
                   'image)))
  (let ((render-window (get-buffer-window maf-render--buffer)))
    (cl-assert (<= (abs (- (window-total-height maf--render-source-window)
                           (window-total-height render-window)))
                   1)))

  ;; At home the same command renders the top entry.
  (goto-char (point-max))
  (setq maf--render-latex nil)
  (cl-letf (((symbol-function 'maf-render--ratex)
             (lambda (latex)
               (setq maf--render-latex latex)
               maf--render-svg-fixture)))
    (call-interactively 'maf-render))
  (cl-assert (string= maf--render-latex "a + b"))

  ;; A missing executable and an empty stack both fail clearly before a
  ;; preview can pretend to have succeeded.
  (let ((maf-render-program "/definitely/not/a/ratex-renderer"))
    (cl-assert (condition-case nil
                   (progn (maf-render--program) nil)
                 (user-error t))))
  (calc-pop (calc-stack-size))
  (cl-assert (condition-case nil
                 (progn (maf-render--entry) nil)
               (user-error t)))

  ;; Restore the shared dev session and remove the preview window/buffer.
  (progn
    (when-let ((win (get-buffer-window maf-render--buffer)))
      (quit-window nil win))
    (when-let ((buf (get-buffer maf-render--buffer)))
      (kill-buffer buf))
    (unless maf--render-mode-stash
      (maf-use-render-mode -1))))
