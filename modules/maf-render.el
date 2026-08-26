;; -*- lexical-binding: t; -*-
;;
;; modules/maf-render.el
;;
;; On-demand typeset preview of a Calc stack entry. `maf-render' takes
;; the whole entry at point (the top entry at home), asks Calc for its
;; LaTeX form, sends that one line to RaTeX, and displays the returned
;; SVG in the lower half of the invoking window without selecting it.
;; Nothing runs between invocations: there are no update hooks and no
;; rendered-image cache.
;;
;; RaTeX is the only external requirement. Its executable is configured
;; by `maf-render-program'; SVG decoding and display are built into a
;; graphical Emacs. The formula color is read from the current default
;; face for each invocation, so a preview follows light/dark theme
;; changes without maintaining any theme hooks.

(require 'calc)
(require 'calc-yank)       ; calc-locate-cursor-element
(require 'maf-lib)
(require 'maf-stack "stack") ; maf--latex-string
(require 'maf-conf "conf")

;; Defined in lazily-loaded Calc and maf modules; declared for the byte
;; compiler because this module can also be loaded on its own.
(declare-function calc-top "calc-ext")
(defvar maf-preview-render-function)     ; modules/maf-preview.el

(declare-function maf-bindings--refresh "maf-bindings")
(declare-function maf-bindings-module-keys "maf-bindings")
(declare-function maf-register-module "maf-module")

(defcustom maf-render-program
  (or (executable-find "render-svg")
      (expand-file-name "~/pkgs/ratex/render-svg"))
  "RaTeX SVG renderer used by `maf-render'.
This may be an executable name found on `exec-path' or a file name. The
program must accept one LaTeX formula on standard input and emit an SVG
with its `--stdout' option."
  :type 'file
  :group 'maf)

(defcustom maf-render-font-size 18
  "Base font size passed to RaTeX by `maf-render'."
  :type 'number
  :group 'maf)

(defconst maf-render--buffer "*maf-render*"
  "Name of the buffer displaying the last rendered entry.")

(defvar maf-render-mode-map
  (let ((map (make-sparse-keymap)))
    (set-keymap-parent map special-mode-map)
    map)
  "Keymap for `maf-render-mode'.")

(define-derived-mode maf-render-mode special-mode "maf-render"
  "Major mode for an on-demand typeset Calc preview."
  (setq-local cursor-type nil)
  (setq-local truncate-lines t)
  (setq-local header-line-format " RaTeX preview    q closes"))

(defun maf-render--program ()
  "Return the configured RaTeX executable, or signal a `user-error'."
  (let* ((configured (substitute-in-file-name maf-render-program))
         (program (if (file-name-directory configured)
                      (expand-file-name configured)
                    (executable-find configured))))
    (unless (and program (file-executable-p program))
      (user-error "RaTeX renderer is not executable: %s (customize `maf-render-program')"
                  maf-render-program))
    program))

(defun maf-render--entry ()
  "Return the whole stack entry at point, or the top entry at home."
  (when (bound-and-true-p maf-edit-mode)
    (user-error "Finish or discard the active edit before rendering"))
  (let ((size (calc-stack-size)))
    (when (zerop size)
      (user-error "Stack is empty"))
    (let ((level (calc-locate-cursor-element (point))))
      (calc-top (if (> level 0) (min level size) 1) 'full))))

(defun maf-render--ratex (latex)
  "Render one-line LATEX with RaTeX and return its SVG output."
  (let ((program (maf-render--program))
        (color (or (face-foreground 'default nil t) "black")))
    (with-temp-buffer
      (let ((status
             (call-process-region
              latex nil program nil '(t nil) nil
              "--stdout"
              "--font-size" (number-to-string maf-render-font-size)
              "--color" color)))
        (unless (and (integerp status) (zerop status))
          (user-error "RaTeX failed with status %s" status))
        (goto-char (point-min))
        (unless (looking-at-p "[[:space:]]*<svg\\(?:[[:space:]>]\\)")
          (user-error "RaTeX returned no SVG"))
        (buffer-string)))))

(defun maf-render--show (svg latex)
  "Show SVG in the preview buffer, using LATEX as image fallback text."
  (let ((image (create-image svg 'svg t :ascent 'center :scale 1)))
    (unless image
      (user-error "Emacs could not create an image from RaTeX's SVG"))
    (let ((buffer (get-buffer-create maf-render--buffer))
          (height (max window-min-height
                       (/ (window-total-height (selected-window)) 2))))
      (with-current-buffer buffer
        (unless (derived-mode-p 'maf-render-mode)
          (maf-render-mode))
        (let ((inhibit-read-only t))
          (erase-buffer)
          (insert-image image latex)
          (insert "\n")
          (goto-char (point-min))))
      (when-let ((window
                  (display-buffer
                   buffer
                   `((display-buffer-reuse-window
                      display-buffer-below-selected)
                     (inhibit-same-window . t)
                     (window-height . ,height)))))
        (set-window-start window (point-min)))
      buffer)))

;;;###autoload
(defun maf-render ()
  "Render the current stack entry as typeset mathematics with RaTeX.

  sqrt(x) / 3  =>  a vertical fraction with a radical numerator

The whole entry at point is formatted using Calc's LaTeX language and
shown as SVG in a preview window below Calc. The preview and Calc
split the original Calc window evenly. At home, the top entry is
rendered. The stack, point, and Calc display language are unchanged."
  (interactive)
  (unless (display-images-p)
    (user-error "The selected frame cannot display images"))
  (maf--with-calc-buffer
    (let* ((latex (maf--latex-string (maf-render--entry)))
           (svg (maf-render--ratex latex)))
      (maf-render--show svg latex))))

;;; The preview panel

(defvar maf-render--panel-cache nil
  "Cons of the last thing the panel typeset and the string it became.
The panel asks once per command and the answer changes only when the
formula or the colour it is drawn in does, so the key is both. RaTeX is
cheap — a few milliseconds — but a subprocess per keystroke is not
something to spend on a formula that has not moved.

A failure is cached under its key too, as nil. A formula Calc's LaTeX
language cannot write is not going to start working on the next
keystroke, and retrying it every command would spend the subprocess
this cache exists to save.")

(defun maf-render--panel-bounds ()
  "Pixels the panel's image is kept within: (WIDTH . HEIGHT).
Most of the frame's width and half its height. A rendering wide enough
to leave the screen is a preview of nothing — the half hanging off it is
the half being looked for — and a tall one buries the stack it is a
second view of. The image is scaled down whole to fit, never clipped:
a formula cut off mid-term gives no sign it was cut."
  (let ((frame (selected-frame)))
    (cons (round (* 0.9 (frame-pixel-width frame)))
          (round (* 0.5 (frame-pixel-height frame))))))

(defun maf-render--panel (value)
  "Return VALUE typeset, as one space carrying the rendered image.
Nil when this display cannot show an SVG at all, or when the formula
does not survive the trip through LaTeX — either way the panel falls
back to its Big rendering rather than going dark. Installed as
`maf-preview-render-function' while `maf-use-render-mode' is on."
  (when (image-type-available-p 'svg)
    ;; Colour, size and bounds are read here rather than left to the
    ;; renderer so they can be part of the key. A theme change, a
    ;; customized font size and a resized frame each move the image
    ;; without the formula moving, and a cache that watched only the
    ;; formula would go on answering with the last one drawn.
    (let* ((bounds (maf-render--panel-bounds))
           (key (list value
                      (face-foreground 'default nil t)
                      maf-render-font-size
                      bounds)))
      (unless (equal (car maf-render--panel-cache) key)
        (setq maf-render--panel-cache
              (cons key
                    (ignore-errors
                      (let* ((svg (maf-render--ratex (maf--latex-string value)))
                             (image (create-image svg 'svg t
                                                  :ascent 'center :scale 1
                                                  :max-width (car bounds)
                                                  :max-height (cdr bounds))))
                        (and image (propertize " " 'display image)))))))
      (cdr maf-render--panel-cache))))

;;; The module

;;;###autoload
(define-minor-mode maf-use-render-mode
  "Make on-demand typeset previews available in Calc.

The render command formats the whole entry at point as LaTeX, passes it
to the configured RaTeX executable, and displays the returned SVG in the
lower half of the invoking Calc window. It neither changes the stack nor
selects the preview.

With the preview module also on, its panel — the one that follows
point — is typeset too, in place of its Big rendering; that panel is
the only thing here that renders without being asked, and only for the
entry it was already showing. Nothing else runs between invocations.

Turning this mode off hands G back to `maf-preview-show' and the panel
back to Big; the command remains available by name."
  :global t
  :group 'maf
  ;; The panel is the preview module's, and it asks rather than being
  ;; told: this sets what it draws with and never draws anything itself,
  ;; so with the preview off there is nothing here to turn on.
  (setq maf-preview-render-function
        (and maf-use-render-mode #'maf-render--panel)
        maf-render--panel-cache nil)
  (maf-bindings--refresh))

;; G, shadowing `maf-preview-show' (src/bindings.el) rather than taking
;; a key of its own. The two are one gesture — a single look at the
;; entry at point, in a rendering the stack is not switched over to —
;; and which rendering that look comes back in is the only thing this
;; module decides. So the toggle chooses what G shows rather than
;; whether G is there at all, and the peek keeps the key untouched for
;; everyone who never turns the module on. vim inherits G from native,
;; but module claims are not derived: the shadow is declared once per
;; profile that has a peek to cover.
(maf-bindings-module-keys 'maf-render 'maf-use-render-mode
  '(((native) "G" maf-render)
     ((vim) "G" maf-render)))

(when (require 'maf-module nil t)
  (maf-register-module 'maf-render #'maf-use-render-mode
                       "Preview one stack entry as typeset mathematics.

Invoke the command on an entry to render it once with RaTeX. The SVG
appears in an even split below Calc without taking focus, and the
stack's own display stays unchanged.

The key is G, which the Big-display peek holds while this is off: the
module decides which rendering one look comes back in, not whether
that look is available. With the preview module on, its following
panel is typeset instead of drawn in Big."
                       "G" "Display"))

(provide 'maf-render)
