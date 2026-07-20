;; -*- lexical-binding: t; -*-
;;
;; modules/maf-preview.el
;;
;; Big-display preview of the active stack entry. `maf-preview-mode' is
;; a buffer-local minor mode for calc buffers that shows the entry at
;; point, rendered in the Big display language, in a child frame over
;; the top-right of the calc window — so the stack itself stays in
;; the normal one-line display where navigating and editing are
;; convenient, while the 2D form is always visible for the entry you
;; are on.
;;
;; The panel is a posframe child frame, parented to the calc frame and
;; undecorated with focus refused: the window manager does not treat it
;; as a top-level window (it stays out of Alt-Tab and never takes
;; focus), and it floats in place regardless of how far the stack is
;; scrolled — unlike an in-buffer overlay, which scrolls out of view
;; once the stack is taller than the window. It is purely display.
;;
;; posframe is an optional dependency: without it the mode loads but
;; shows nothing. The module toggle is `maf-use-preview-mode', which
;; turns the buffer-local mode on in every calc buffer and registers
;; with the module system as `maf-preview' (see `maf-modules').

(require 'calc)
(require 'calc-yank)         ; calc-locate-cursor-element
(require 'posframe nil t)    ; optional; the preview shows only with it

;; Rendered on demand; the byte compiler needs the declarations.
(declare-function math-format-value "calc-ext")
(declare-function posframe-show "posframe")
(declare-function posframe-hide "posframe")
(declare-function posframe-delete "posframe")
(declare-function posframe-workable-p "posframe")

(defconst maf-preview--buffer " *maf-preview*"
  "Name of the buffer backing the preview child frame.")

(defun maf-preview--poshandler (info)
  "Position the preview inset from the calc window's top-right corner.
Down from the header line and in from the right edge, so the frame does
not crowd the corner. A posframe poshandler; see `posframe-show'."
  (let ((window-left  (plist-get info :parent-window-left))
        (window-top   (plist-get info :parent-window-top))
        (window-width (plist-get info :parent-window-width))
        (posframe-width (plist-get info :posframe-width)))
    (cons (- (+ window-left window-width) posframe-width 18)  ; in from the right
          (+ window-top 40))))                                ; down past the header

(defun maf-preview--render ()
  "Return the active entry rendered in the Big language, or nil.
The active entry is the one at point, or the top entry when point is at
home. Returns nil when there is nothing to preview: an empty stack, an
active maf-edit session (whose text the stack no longer matches), or a
buffer already showing the Big language (the panel would be redundant)."
  (unless (or (eq calc-language 'big)
              (bound-and-true-p maf-edit-mode))
    (let ((size (calc-stack-size)))
      (unless (zerop size)
        (let* ((idx (calc-locate-cursor-element (point)))
               (level (if (> idx 0) (min idx size) 1)))
          ;; Render the value in Big without disturbing the buffer's own
          ;; display language (see this file's commentary).
          (let ((calc-language 'big))
            (math-format-value (calc-top-n level))))))))

(defun maf-preview--hide ()
  "Hide the preview child frame, if it exists."
  (when (and (featurep 'posframe) (get-buffer maf-preview--buffer))
    (posframe-hide maf-preview--buffer)))

(defun maf-preview--update ()
  "Refresh the preview from the entry at point; on `post-command-hook'.
Errors are swallowed so a bad calc state can never disable the hook."
  (when (and (featurep 'posframe) (posframe-workable-p))
    (let ((str (ignore-errors (maf-preview--render))))
      (if (and str (get-buffer-window (current-buffer)))
          (let ((frame (posframe-show
                        maf-preview--buffer
                        :string (concat (propertize "PREVIEW\n" 'face 'shadow) str)
                        :poshandler #'maf-preview--poshandler
                        :internal-border-width 2
                        :internal-border-color "gray50"
                        :left-fringe 8
                        :right-fringe 8
                        :accept-focus nil)))
            ;; posframe-show can leave a previously-hidden child frame
            ;; iconified rather than visible on some window managers;
            ;; force it visible.
            (when (frame-live-p frame) (make-frame-visible frame)))
        (maf-preview--hide)))))

(defun maf-preview--maybe-hide-away (&rest _)
  "Hide the preview when the selected buffer is not a calc buffer.
On `window-selection-change-functions' while the module is on: the
child frame floats over the frame, so it must go when calc is no longer
the buffer in view. Re-shown by `maf-preview--update' on the next
command once calc is current again."
  (unless (derived-mode-p 'calc-mode)
    (maf-preview--hide)))

;;;###autoload
(define-minor-mode maf-preview-mode
  "Show the entry at point rendered in the Big display language.
As point moves over the stack, a child frame at the top-right of the
calc window shows the active entry in 2D Big form, while the stack
itself stays in the normal one-line display. The panel is display-only
— it never takes focus and the window manager ignores it. It is hidden
while the whole buffer is already in Big display and during an in-place
edit session. Requires the `posframe' package; without it the mode is
inert."
  :lighter " preview"
  :group 'maf
  (if maf-preview-mode
      (if (featurep 'posframe)
          (progn
            (add-hook 'post-command-hook #'maf-preview--update nil t)
            (maf-preview--update))
        (message "maf-preview: posframe not available; preview inert"))
    (remove-hook 'post-command-hook #'maf-preview--update t)
    (maf-preview--hide)))

;;; The module

(defun maf-preview--turn-on ()
  "Enable `maf-preview-mode' in the current buffer if it is a calc buffer.
The per-buffer arm of `maf-use-preview-mode'."
  (when (derived-mode-p 'calc-mode)
    (maf-preview-mode 1)))

;;;###autoload
(define-globalized-minor-mode maf-use-preview-mode
  maf-preview-mode maf-preview--turn-on
  :group 'maf
  ;; The child frame floats over the whole Emacs frame, so hide it when
  ;; the view leaves calc; the hook lives only while the module is on.
  (if maf-use-preview-mode
      (add-hook 'window-selection-change-functions #'maf-preview--maybe-hide-away)
    (remove-hook 'window-selection-change-functions #'maf-preview--maybe-hide-away)
    (when (and (featurep 'posframe) (get-buffer maf-preview--buffer))
      (posframe-delete maf-preview--buffer))))

;; Register with the module system when it is present; the mode above
;; works on its own without it.
(when (require 'maf-module nil t)
  (maf-register-module 'maf-preview #'maf-use-preview-mode
                       "Big-display preview of the entry at point, in a floating child frame."))

(provide 'maf-preview)
