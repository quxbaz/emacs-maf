;; The render module drawing the preview panel. modules/maf-render.el
;; installs `maf-preview-render-function' while its mode is on, and
;; modules/maf-preview.el asks that before falling back to Big — so what
;; this file pins is the agreement between the two, not either alone:
;; who installs, who asks, when the answer is refused, and what the
;; panel shows when it is.
;;
;; RaTeX is mocked, and so is the panel's own test for a backend that
;; can display an image, so the file says the same thing on a machine
;; without the renderer and in a session without posframe. That the SVG
;; itself draws is tests/render.el's and the live drive's to show.

(maf-step
  (setq maf--rp-render-stash maf-use-render-mode
        maf--rp-preview-stash maf-use-preview-mode
        maf--rp-calls 0
        maf--rp-svg
        "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"10\" height=\"10\"><path d=\"M0 0h10v10H0z\"/></svg>")

  ;; A counting stand-in for the renderer, and a panel that says it can
  ;; show what comes back. Both are installed per assertion below; these
  ;; are the definitions they share.
  (progn
    (defun maf--rp-ratex (_latex)
      (setq maf--rp-calls (1+ maf--rp-calls))
      maf--rp-svg)
    (defun maf--rp-imagep (str)
      "Non-nil when STR is a panel string carrying an image."
      (and (stringp str) (> (length str) 0)
           (eq (car-safe (get-text-property 0 'display str)) 'image))))

  ;; One entry, point on it, and the buffer in the ordinary one-line
  ;; display — the state every assertion below starts from.
  (progn (calc-pop (calc-stack-size))
         (calc-normal-language)
         (calc-push '(/ (var a var-a) (var b var-b)))
         (calc-refresh)
         (goto-char (point-min))
         (search-forward "a / b")
         (backward-char 3))

  ;; With the module off nothing is installed and the panel is Big, as
  ;; it is for everyone who never turns the module on.
  (maf-use-render-mode -1)
  (cl-assert (null maf-preview-render-function))
  (cl-assert (equal (maf-preview--render) "a\n-\nb"))

  ;; Turning it on installs the renderer; turning it off withdraws it.
  ;; The panel is asked for, never pushed to: this is the whole of the
  ;; wiring between the two modules.
  (maf-use-render-mode 1)
  (cl-assert (eq maf-preview-render-function #'maf-render--panel))

  ;; Asked, on a panel that can show an image, the entry comes back
  ;; typeset — one space carrying the rendering — instead of in Big.
  (cl-letf (((symbol-function 'maf-render--ratex) #'maf--rp-ratex)
            ((symbol-function 'maf-preview--rich-p) (lambda () t)))
    (setq maf--rp-calls 0)
    (cl-assert (maf--rp-imagep (maf-preview--render)))
    (cl-assert (= maf--rp-calls 1)))

  ;; The panel asks once per command and the entry rarely moves, so an
  ;; unchanged formula is answered from the cache rather than by a
  ;; second subprocess.
  (cl-letf (((symbol-function 'maf-render--ratex) #'maf--rp-ratex)
            ((symbol-function 'maf-preview--rich-p) (lambda () t)))
    (setq maf--rp-calls 0)
    (cl-assert (maf--rp-imagep (maf-preview--render)))
    (cl-assert (maf--rp-imagep (maf-preview--render)))
    (cl-assert (= maf--rp-calls 0)))

  ;; A different entry is a different formula, and does render again.
  (progn (calc-push '(^ (var x var-x) 2))
         (calc-refresh)
         (goto-char (point-min))
         (search-forward "x^2")
         (backward-char 2))
  (cl-letf (((symbol-function 'maf-render--ratex) #'maf--rp-ratex)
            ((symbol-function 'maf-preview--rich-p) (lambda () t)))
    (setq maf--rp-calls 0)
    (cl-assert (maf--rp-imagep (maf-preview--render)))
    (cl-assert (= maf--rp-calls 1)))
  (progn (calc-pop 1) (calc-refresh)
         (goto-char (point-min)) (search-forward "a / b") (backward-char 3))

  ;; Where the panel cannot show an image the renderer is never asked:
  ;; the in-window backend lays rows of text over stack lines, measured
  ;; in columns, and an image has no column width to lay out with. Big
  ;; is what that panel gets, module on or off.
  (cl-letf (((symbol-function 'maf-render--ratex) #'maf--rp-ratex)
            ((symbol-function 'maf-preview--rich-p) (lambda () nil)))
    (setq maf--rp-calls 0)
    (cl-assert (equal (maf-preview--render) "a\n-\nb"))
    (cl-assert (= maf--rp-calls 0)))

  ;; A rendering of the module's own is never redundant with the
  ;; buffer's display language, so the Big test guards only the Big
  ;; fallback: a typeset panel over a Big stack is still the second view
  ;; it was turned on to be, where a Big panel over it showed nothing
  ;; new.
  (calc-big-language)
  (cl-letf (((symbol-function 'maf-render--ratex) #'maf--rp-ratex)
            ((symbol-function 'maf-preview--rich-p) (lambda () t)))
    (cl-assert (maf--rp-imagep (maf-preview--render))))
  (cl-letf (((symbol-function 'maf-preview--rich-p) (lambda () nil)))
    (cl-assert (null (maf-preview--render))))
  (progn (calc-normal-language)
         (calc-refresh)
         (goto-char (point-min)) (search-forward "a / b") (backward-char 3))

  ;; A formula the renderer cannot draw takes the panel back to Big
  ;; rather than down: the fallback is what a nil from the renderer
  ;; means, and an error means it too. On an entry of its own, since a
  ;; formula already rendered once is answered from the cache and would
  ;; never reach the failing renderer at all.
  (progn (calc-push '(^ (var y var-y) 3))
         (calc-refresh)
         (goto-char (point-min))
         (search-forward "y^3")
         (backward-char 2))
  (cl-letf (((symbol-function 'maf-render--ratex)
             (lambda (_latex) (user-error "RaTeX failed with status 1")))
            ((symbol-function 'maf-preview--rich-p) (lambda () t)))
    (let ((str (maf-preview--render)))
      (cl-assert (stringp str))
      (cl-assert (not (maf--rp-imagep str)))))

  ;; And the failure is remembered under its own key: a formula LaTeX
  ;; cannot write will not start working on the next keystroke, so the
  ;; retry the panel would otherwise make every command is not made.
  (cl-letf (((symbol-function 'maf-render--ratex) #'maf--rp-ratex)
            ((symbol-function 'maf-preview--rich-p) (lambda () t)))
    (setq maf--rp-calls 0)
    (let ((str (maf-preview--render)))
      (cl-assert (stringp str))
      (cl-assert (not (maf--rp-imagep str))))
    (cl-assert (= maf--rp-calls 0)))
  (progn (calc-pop 1) (calc-refresh)
         (goto-char (point-min)) (search-forward "a / b") (backward-char 3))

  ;; Turning the module off withdraws the renderer and drops what it
  ;; cached, so the next time on starts from the formula in front of it.
  (maf-use-render-mode -1)
  (cl-assert (null maf-preview-render-function))
  (cl-assert (null maf-render--panel-cache))
  (cl-letf (((symbol-function 'maf-render--ratex) #'maf--rp-ratex)
            ((symbol-function 'maf-preview--rich-p) (lambda () t)))
    (setq maf--rp-calls 0)
    (cl-assert (equal (maf-preview--render) "a\n-\nb"))
    (cl-assert (= maf--rp-calls 0)))

  ;; Restore the shared dev session.
  (progn
    (calc-normal-language)
    (calc-pop (calc-stack-size))
    (maf-use-render-mode (if maf--rp-render-stash 1 -1))
    (maf-use-preview-mode (if maf--rp-preview-stash 1 -1))))
