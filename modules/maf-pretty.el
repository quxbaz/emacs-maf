;; -*- lexical-binding: t; -*-
;;
;; modules/maf-pretty.el
;;
;; On-demand typeset preview of a Calc stack entry. `maf-pretty' takes
;; the whole entry at point (the top entry at home), asks Calc for its
;; LaTeX form, sends that one line to RaTeX, and displays the returned
;; SVG in the lower half of the invoking window, which splits evenly
;; and hands the preview focus; q deletes the preview window and hands
;; both height and focus back. Nothing runs between invocations: there
;; are no update hooks and no rendered-image cache.
;;
;; RaTeX is the only external requirement. Its executable is configured
;; by `maf-pretty-program'; SVG decoding and display are built into a
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

(defcustom maf-pretty-program
  (or (executable-find "render-svg")
      (expand-file-name "~/pkgs/ratex/render-svg"))
  "RaTeX SVG renderer used by `maf-pretty'.
This may be an executable name found on `exec-path' or a file name. The
program must accept one LaTeX formula on standard input and emit an SVG
with its `--stdout' option."
  :type 'file
  :group 'maf)

(defcustom maf-pretty-font-size 16
  "Base font size passed to RaTeX by `maf-pretty'."
  :type 'number
  :group 'maf)

(defconst maf-pretty--buffer "*maf-pretty*"
  "Name of the buffer displaying the last rendered entry.")

(defvar maf-pretty-mode-map
  (let ((map (make-sparse-keymap)))
    (set-keymap-parent map special-mode-map)
    map)
  "Keymap for `maf-pretty-mode'.")

(defvar maf-pretty--return-window nil
  "The window focus goes back to when the preview is dismissed, or nil.
Set each time the preview takes focus; `maf-pretty-quit' reads it.")

(defun maf-pretty-quit ()
  "Dismiss the typeset preview.
Deletes the preview's window — the calc window gets its height back —
and returns focus to the window the preview was invoked from."
  (interactive)
  (let ((window (get-buffer-window maf-pretty--buffer)))
    (when (window-live-p window)
      (if (window-parent window)
          (delete-window window)
        (quit-window nil window))))
  (when (window-live-p maf-pretty--return-window)
    (select-window maf-pretty--return-window)))

;; Outside the defvar so a reload applies edits to the map.
(define-key maf-pretty-mode-map "q" #'maf-pretty-quit)

(define-derived-mode maf-pretty-mode special-mode "maf-pretty"
  "Major mode for an on-demand typeset Calc preview."
  (setq-local cursor-type nil)
  (setq-local truncate-lines t)
  (setq-local header-line-format " Preview    q closes"))

(defun maf-pretty--program ()
  "Return the configured RaTeX executable, or signal a `user-error'."
  (let* ((configured (substitute-in-file-name maf-pretty-program))
         (program (if (file-name-directory configured)
                      (expand-file-name configured)
                    (executable-find configured))))
    (unless (and program (file-executable-p program))
      (user-error "RaTeX renderer is not executable: %s (customize `maf-pretty-program')"
                  maf-pretty-program))
    program))

(defun maf-pretty--entry ()
  "Return the whole stack entry at point, or the top entry at home."
  (when (bound-and-true-p maf-edit-mode)
    (user-error "Finish or discard the active edit before rendering"))
  (let ((size (calc-stack-size)))
    (when (zerop size)
      (user-error "Stack is empty"))
    (let ((level (calc-locate-cursor-element (point))))
      (calc-top (if (> level 0) (min level size) 1) 'full))))

(defun maf-pretty--ratex (latex)
  "Render one-line LATEX with RaTeX and return its SVG output."
  (let ((program (maf-pretty--program))
        (color (or (face-foreground 'default nil t) "black")))
    (with-temp-buffer
      (let ((status
             (call-process-region
              latex nil program nil '(t nil) nil
              "--stdout"
              "--font-size" (number-to-string maf-pretty-font-size)
              "--color" color)))
        (unless (and (integerp status) (zerop status))
          (user-error "RaTeX failed with status %s" status))
        (goto-char (point-min))
        (unless (looking-at-p "[[:space:]]*<svg\\(?:[[:space:]>]\\)")
          (user-error "RaTeX returned no SVG"))
        (buffer-string)))))

(defun maf-pretty--display (fill)
  "Show the preview window in an even split below and select it.
FILL is called with the empty, writable preview buffer current to
insert the content — an SVG for `maf-pretty', Big text for
`maf-preview-show'. The preview and the invoking window end up an
even split of the height they share, whatever the preview window's
history — a reused window keeps its old size and `display-buffer'
sizes only windows it creates, so the split is evened by hand
afterwards. Focus moves to the preview; `maf-pretty-quit' hands it
back."
  (let ((buffer (get-buffer-create maf-pretty--buffer))
        (height (max window-min-height
                     (/ (window-total-height (selected-window)) 2))))
    (with-current-buffer buffer
      (unless (derived-mode-p 'maf-pretty-mode)
        (maf-pretty-mode))
      (let ((inhibit-read-only t))
        (erase-buffer)
        (funcall fill)
        (goto-char (point-min))))
    (when-let ((window
                (display-buffer
                 buffer
                 `((display-buffer-reuse-window
                    display-buffer-below-selected)
                   (inhibit-same-window . t)
                   (window-height . ,height)))))
      (set-window-start window (point-min))
      ;; Meet in the middle: growing the preview by half the
      ;; difference shrinks the sibling by the same. `ignore-errors'
      ;; covers the windows resize refuses to touch.
      (ignore-errors
        (window-resize window
                       (/ (- (window-total-height)
                             (window-total-height window))
                          2)))
      (unless (eq (selected-window) window)
        (setq maf-pretty--return-window (selected-window)))
      (select-window window))))

(defun maf-pretty--show (svg latex)
  "Show SVG in the preview window and select it.
LATEX is the image's fallback text; the window behavior is
`maf-pretty--display's."
  (let ((image (create-image svg 'svg t :ascent 'center :scale 1)))
    (unless image
      (user-error "Emacs could not create an image from RaTeX's SVG"))
    (maf-pretty--display
     (lambda ()
       (insert-image image latex)
       (insert "\n")))))

(defun maf-pretty--show-text (str)
  "Show STR in the preview window and select it.
The same window, split, and dismissal as an SVG preview — what
`maf-preview-show' fills the window with when this module's renderer
is off."
  (maf-pretty--display
   (lambda ()
     (insert str)
     (insert "\n"))))

;;;###autoload
(defun maf-pretty ()
  "Render the current stack entry as typeset mathematics with RaTeX.

  sqrt(x) / 3  =>  a vertical fraction with a radical numerator

The whole entry at point is formatted using Calc's LaTeX language and
shown as SVG in a preview window below Calc. The preview and Calc
split the original Calc window evenly, and focus moves to the
preview; `maf-pretty-quit' in it hands the height and focus back. At
home, the top entry is rendered. The stack and Calc display language
are unchanged."
  (interactive)
  (unless (display-images-p)
    (user-error "The selected frame cannot display images"))
  (maf--with-calc-buffer
    (let* ((latex (maf--latex-string (maf-pretty--entry)))
           (svg (maf-pretty--ratex latex)))
      (maf-pretty--show svg latex))))

;;; The preview panel

(defvar maf-pretty--panel-cache nil
  "Cons of the last thing the panel typeset and the string it became.
The panel asks once per command and the answer changes only when the
formula or the colour it is drawn in does, so the key is both. RaTeX is
cheap — a few milliseconds — but a subprocess per keystroke is not
something to spend on a formula that has not moved.

A failure is cached under its key too, as nil. A formula Calc's LaTeX
language cannot write is not going to start working on the next
keystroke, and retrying it every command would spend the subprocess
this cache exists to save.")

(defun maf-pretty--panel-bounds ()
  "Pixels the panel's image is kept within: (WIDTH . HEIGHT).
Most of the frame's width and half its height. A rendering wide enough
to leave the screen is a preview of nothing — the half hanging off it is
the half being looked for — and a tall one buries the stack it is a
second view of. The image is scaled down whole to fit, never clipped:
a formula cut off mid-term gives no sign it was cut."
  (let ((frame (selected-frame)))
    (cons (round (* 0.9 (frame-pixel-width frame)))
          (round (* 0.5 (frame-pixel-height frame))))))

(defun maf-pretty--panel (value)
  "Return VALUE typeset, as one space carrying the rendered image.
Nil when this display cannot show an SVG at all, or when the formula
does not survive the trip through LaTeX — either way the panel falls
back to its Big rendering rather than going dark. Installed as
`maf-preview-render-function' while `maf-use-pretty-mode' is on."
  (when (image-type-available-p 'svg)
    ;; Colour, size and bounds are read here rather than left to the
    ;; renderer so they can be part of the key. A theme change, a
    ;; customized font size and a resized frame each move the image
    ;; without the formula moving, and a cache that watched only the
    ;; formula would go on answering with the last one drawn.
    (let* ((bounds (maf-pretty--panel-bounds))
           (key (list value
                      (face-foreground 'default nil t)
                      maf-pretty-font-size
                      bounds)))
      (unless (equal (car maf-pretty--panel-cache) key)
        (setq maf-pretty--panel-cache
              (cons key
                    (ignore-errors
                      (let* ((svg (maf-pretty--ratex (maf--latex-string value)))
                             (image (create-image svg 'svg t
                                                  :ascent 'center :scale 1
                                                  :max-width (car bounds)
                                                  :max-height (cdr bounds))))
                        (and image (propertize " " 'display image)))))))
      (cdr maf-pretty--panel-cache))))

;;; The module

;;;###autoload
(define-minor-mode maf-use-pretty-mode
  "Make on-demand typeset previews available in Calc.

The command formats the whole entry at point as LaTeX, passes it to
the configured RaTeX executable, and displays the returned SVG in the
lower half of the invoking Calc window, taking focus; dismissing the
preview (q) hands both height and focus back. The stack is never
changed.

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
        (and maf-use-pretty-mode #'maf-pretty--panel)
        maf-pretty--panel-cache nil)
  (maf-bindings--refresh))

;; G, shadowing `maf-preview-show' (src/bindings.el) rather than taking
;; a key of its own. The two are one gesture — a single look at the
;; entry at point, in a rendering the stack is not switched over to —
;; and which rendering that look comes back in is the only thing this
;; module decides. So the toggle chooses what G shows rather than
;; whether G is there at all, and the Big look keeps the key untouched for
;; everyone who never turns the module on. vim inherits G from native,
;; but module claims are not derived: the shadow is declared once per
;; profile that has a look to cover.
(maf-bindings-module-keys 'maf-pretty 'maf-use-pretty-mode
  '(((native) "G" maf-pretty)
     ((vim) "G" maf-pretty)))

(when (require 'maf-module nil t)
  (maf-register-module 'maf-pretty #'maf-use-pretty-mode
                       "Preview one stack entry as typeset mathematics.

Invoke the command on an entry to render it once with RaTeX. The SVG
appears in an even split below Calc and takes focus — q hands it
back — and the stack's own display stays unchanged.

The key is G, which the Big-display preview holds while this is off: the
module decides which rendering one look comes back in, not whether
that look is available. With the preview module on, its following
panel is typeset instead of drawn in Big."
                       "G" "Display"))

(provide 'maf-pretty)
