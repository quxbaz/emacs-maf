;; -*- lexical-binding: t; -*-
;;
;; modules/maf-preview.el
;;
;; Big-display preview of the active stack entry. `maf-preview-mode' is
;; a buffer-local minor mode for calc buffers that shows the entry at
;; point — as it stands on the stack, unsimplified — rendered in the Big
;; display language, in a panel over the top-right of the calc window.
;; The stack itself stays in the normal one-line display, where
;; navigating and editing are convenient, while the 2D form is always
;; visible for the entry you are on.
;;
;; Two display backends, picked per update by what the frame can do:
;;
;; - Child frame (posframe), on a graphical frame. Parented to the calc
;;   frame and undecorated with focus refused: the window manager does
;;   not treat it as a top-level window (it stays out of Alt-Tab and
;;   never takes focus).
;;
;; - In-window panel, on a text terminal — where child frames do not
;;   exist before Emacs 31 — and on any frame without posframe. The
;;   panel is drawn with one overlay per line it covers, each carrying a
;;   single row of the panel to the right of that line's text: a line
;;   long enough to reach the panel has its tail replaced, so the panel
;;   occludes the stack beneath it as a child frame would, and no line
;;   is pushed sideways or down. Rows past the end of the buffer ride
;;   along on the last overlay.
;;
;; Either way the panel is purely display, and it is anchored to the top
;; of the window rather than to buffer text, so it floats in place
;; regardless of how far the stack is scrolled — unlike a plain
;; in-buffer overlay, which scrolls out of view once the stack is taller
;; than the window.
;;
;; The module toggle is `maf-use-preview-mode', which turns the
;; buffer-local mode on in every calc buffer and registers with the
;; module system as `maf-preview' (see `maf-modules').

(require 'calc)
(require 'calc-yank)         ; calc-locate-cursor-element
(require 'seq)
(require 'mule-util)         ; truncate-string-to-width, truncate-string-ellipsis
(require 'posframe nil t)    ; optional; the child-frame backend needs it
(require 'maf-conf "conf")   ; the `maf' customize group

;; Rendered on demand; the byte compiler needs the declarations.
(declare-function math-format-value "calc-ext")
(declare-function posframe-show "posframe")
(declare-function posframe-hide "posframe")
(declare-function posframe-delete "posframe")
(declare-function posframe-workable-p "posframe")

(defconst maf-preview--buffer " *maf-preview*"
  "Name of the buffer backing the preview child frame.")

(defconst maf-preview--title "PREVIEW"
  "Label the preview carries, so the panel is not mistaken for the stack.")

(defface maf-preview-panel
  '((t :inherit default))
  "Face for the text inside the in-window preview panel.
Inherits `default' rather than leaving the face unspecified so the panel
is opaque: it covers whatever face the stack line beneath it carries."
  :group 'maf)

(defface maf-preview-border
  '((t :inherit (shadow default)))
  "Face for the border of the in-window preview panel."
  :group 'maf)

;;; Rendering the entry

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
          ;; The stored value, via `calc-top' rather than `calc-top-n':
          ;; the preview is a second view of the entry as it stands on
          ;; the stack, so it must show what the stack line shows.
          ;; `calc-top-n' normalizes, which under a simplification mode
          ;; would preview `6 x + 12 = 18 y + 6' as `x + 1 = 3 y' — a
          ;; different formula from the one being worked on. This is the
          ;; value calc itself composes the stack line from.
          ;;
          ;; Rendered in Big without disturbing the buffer's own display
          ;; language (see this file's commentary).
          (let ((calc-language 'big))
            (math-format-value (calc-top level))))))))

;;; The child-frame backend

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

(defun maf-preview--posframe-p ()
  "Non-nil when the child-frame backend can be used on this frame.
False on a text terminal, and whenever posframe is not installed."
  (and (featurep 'posframe) (posframe-workable-p)))

(defun maf-preview--posframe-show (str)
  "Show STR in the preview child frame."
  (let ((frame (posframe-show
                maf-preview--buffer
                :string (concat (propertize (concat maf-preview--title "\n")
                                            'face 'shadow)
                                str)
                :poshandler #'maf-preview--poshandler
                :internal-border-width 2
                :internal-border-color "gray50"
                :left-fringe 8
                :right-fringe 8
                :accept-focus nil)))
    ;; posframe-show can leave a previously-hidden child frame
    ;; iconified rather than visible on some window managers; force it
    ;; visible.
    (when (frame-live-p frame) (make-frame-visible frame))))

(defun maf-preview--posframe-hide ()
  "Hide the preview child frame, if it exists."
  (when (and (featurep 'posframe) (get-buffer maf-preview--buffer))
    (posframe-hide maf-preview--buffer)))

;;; The in-window backend

(defconst maf-preview--panel-inset 2
  "Columns kept clear between the in-window panel and the window's right edge.")

(defconst maf-preview--panel-top 1
  "Screen lines kept clear between the top of the window and the panel.")

(defvar maf-preview--overlays nil
  "Overlays drawing the in-window panel, or nil when no panel is shown.
Global, like the single child frame of the other backend: the panel
exists in at most one window at a time.")

(defun maf-preview--border-row (left right inner &optional label)
  "Return a horizontal panel border INNER columns wide between LEFT and RIGHT.
LEFT and RIGHT are the corner characters. LABEL, when given, is written
into the border one column in from LEFT."
  (let ((text (if label (concat "─" label) "")))
    (propertize (concat (string left)
                        text
                        (make-string (- inner (string-width text)) ?─)
                        (string right))
                'face 'maf-preview-border)))

(defun maf-preview--body-row (line inner)
  "Return the panel row holding LINE, INNER columns wide between its borders."
  (let ((edge (propertize "│" 'face 'maf-preview-border)))
    (concat edge
            (propertize (concat " " line
                                (make-string (- inner 1 (string-width line)) ?\s))
                        'face 'maf-preview-panel)
            edge)))

(defun maf-preview--panel-rows (str max-width max-height)
  "Return STR as the rows of a bordered panel, or nil if none fits.
Each row is one screen line of the panel, borders included, and all are
the same width. STR is clipped — lines to MAX-WIDTH columns, the panel
to MAX-HEIGHT rows — with an ellipsis marking what was cut."
  (let ((body-width (- max-width 4))       ; two borders plus a pad column each side
        (body-height (- max-height 2)))    ; the top and bottom borders
    (when (and (> body-width (string-width maf-preview--title))
               (>= body-height 1))
      (let* ((lines (split-string str "\n"))
             (lines (if (> (length lines) body-height)
                        (append (seq-take lines (1- body-height))
                                (list (truncate-string-ellipsis)))
                      lines))
             (lines (mapcar (lambda (line)
                              (truncate-string-to-width line body-width nil nil t))
                            lines))
             (inner (max (+ 2 (apply #'max (mapcar #'string-width lines)))
                         (+ 3 (string-width maf-preview--title)))))
        (append (list (maf-preview--border-row ?┌ ?┐ inner maf-preview--title))
                (mapcar (lambda (line) (maf-preview--body-row line inner)) lines)
                (list (maf-preview--border-row ?└ ?┘ inner)))))))

(defun maf-preview--place-row (row col win)
  "Draw ROW at column COL of the line at point, in WIN alone.
Text from COL to the end of the line is replaced by ROW, so the panel
occludes the stack line beneath it the way a child frame would. A line
that stops short of COL gets ROW appended after padding instead."
  (let* ((pad (- col (move-to-column col)))
         (eol (line-end-position))
         (ov (make-overlay (point) eol)))
    (overlay-put ov 'window win)
    (overlay-put ov 'priority 100)
    ;; An empty overlay can only carry a string, not a display property:
    ;; there is nothing for the property to replace.
    (if (or (> pad 0) (= (point) eol))
        (overlay-put ov 'after-string (concat (make-string (max pad 0) ?\s) row))
      (overlay-put ov 'display row))
    (push ov maf-preview--overlays)))

(defun maf-preview--overlay-hide ()
  "Take down the in-window panel, if one is shown."
  (mapc #'delete-overlay maf-preview--overlays)
  (setq maf-preview--overlays nil))

(defun maf-preview--overlay-show (str win start)
  "Draw STR as a panel at the top-right of WIN, over the buffer's own text.
START is the buffer position WIN begins its display at — the panel hangs
off the first line shown there, not off any particular stack entry."
  (maf-preview--overlay-hide)
  (with-selected-window win
    (let* ((numbers (if (bound-and-true-p display-line-numbers)
                        ;; Reported in canonical character widths, and
                        ;; fractional when the line-number face is not
                        ;; the frame's own; a column is the unit here.
                        (ceiling (line-number-display-width 'columns))
                      0))
           ;; Text columns, which is what `move-to-column' counts: the
           ;; line-number margin is part of the window body but not of
           ;; the text.
           (width (- (window-body-width win) numbers))
           (rows (maf-preview--panel-rows
                  str
                  (- width maf-preview--panel-inset)
                  (- (window-body-height win) maf-preview--panel-top))))
      (when rows
        (let ((col (- width (string-width (car rows)) maf-preview--panel-inset)))
          (save-excursion
            (goto-char start)
            ;; Screen lines, not buffer lines: a wrapped first line must
            ;; push the panel down as far as it pushes the stack.
            (vertical-motion maf-preview--panel-top)
            (while rows
              (let ((row (pop rows)))
                ;; Out of buffer lines to hang the rest of the panel on:
                ;; the last overlay carries them as screen lines of its
                ;; own, each padded out to the panel's column. Nothing
                ;; follows the end of the buffer, so nothing is pushed
                ;; down by the extra rows.
                (when (and rows (= (line-end-position) (point-max)))
                  (setq row (concat row "\n"
                                    (mapconcat (lambda (r)
                                                 (concat (make-string col ?\s) r))
                                               rows "\n"))
                        rows nil))
                (maf-preview--place-row row col win)
                (forward-line 1)))))))))

;;; Backend-agnostic display

(defvar maf-preview--state nil
  "Everything the panel currently on screen was drawn from.
Compared against the same data on each update so an unchanged panel is
left alone instead of being torn down and rebuilt every command.")

(defun maf-preview--window ()
  "Return the window the preview belongs over, or nil if there is none.
The selected one, and only when it is showing this buffer: there is a
single panel, so with the stack in two windows it goes over the one the
user is working in — which is also the window the child frame's
poshandler measures against."
  (let ((win (selected-window)))
    (and (eq (window-buffer win) (current-buffer)) win)))

(defun maf-preview--show (str win start)
  "Show STR as the preview panel over WIN, on whichever backend fits.
START is where WIN begins its display; see `maf-preview--overlay-show'."
  (if (maf-preview--posframe-p)
      (progn (maf-preview--overlay-hide)
             (maf-preview--posframe-show str))
    (maf-preview--posframe-hide)
    (maf-preview--overlay-show str win start)))

(defun maf-preview--hide ()
  "Hide the preview panel, whichever backend is showing it."
  (setq maf-preview--state nil)
  (maf-preview--posframe-hide)
  (maf-preview--overlay-hide))

(defun maf-preview--update (&optional window start)
  "Refresh the preview from the entry at point; on `post-command-hook'.
WINDOW and START name the window to draw over and the position it starts
its display at, for the callers that know them before redisplay does;
both default to what the buffer's own window reports.

Nothing is redrawn unless something the panel is made of has changed —
the entry, the window, its size, where it starts, or the buffer text the
panel hangs over — so the common case of a command that moves nothing
costs one comparison.

Errors are contained — reported, but never signalled out of the hook —
so neither a bad calc state nor an undrawable panel can leave Emacs with
the hook removed and the preview silently dead for the rest of the
session."
  (let* ((win (or window (maf-preview--window)))
         (str (and win (ignore-errors (maf-preview--render)))))
    (if (null str)
        (maf-preview--hide)
      (let* ((start (or start (window-start win)))
             (state (list str win start
                          (window-body-width win) (window-body-height win)
                          (buffer-chars-modified-tick))))
        (unless (equal state maf-preview--state)
          (setq maf-preview--state state)
          (with-demoted-errors "maf-preview: %S"
            (maf-preview--show str win start)))))))

(defun maf-preview--on-scroll (win start)
  "Redraw the panel for WIN, now starting at START; a scroll hook.
On `window-scroll-functions', which redisplay calls with the window's
new start before drawing it. The panel sits at the top of the window, so
it has to move with a scroll — and `post-command-hook' cannot see a
scroll that redisplay itself decided on (following point out of the
window, say): there, the start it reads is still the old one."
  (when (eq win (maf-preview--window))
    (maf-preview--update win start)))

(defun maf-preview--on-change (&rest _)
  "Take the in-window panel down when the text under it changes.
On `after-change-functions'. The panel's overlays hang off positions in
the stack, and calc rewrites the stack wholesale: the positions they were
placed at collapse together, so a panel left standing across a rewrite
would be drawn piled up on one line, pushing the stack down. Dropping it
costs nothing — the update at the end of the command draws it afresh."
  (when maf-preview--overlays
    (maf-preview--overlay-hide)
    (setq maf-preview--state nil)))

(defun maf-preview--on-window-change (&rest _)
  "Refresh the preview, or hide it, when the window the user is in changes.
On `window-selection-change-functions' and
`window-configuration-change-hook' while the module is on: the panel
floats over one window, so it has to go when that window is no longer
showing the stack, and to be redrawn when the window is resized, split,
or replaced — none of which is a command in the calc buffer.

Both hooks are taken globally rather than buffer-locally on purpose: the
buffer-local form of the configuration hook runs once per window showing
the buffer, each time with that window selected, which would leave the
single panel over whichever window happened to come last."
  (if (bound-and-true-p maf-preview-mode)
      (maf-preview--update)
    (maf-preview--hide)))

;;;###autoload
(define-minor-mode maf-preview-mode
  "Show the entry at point rendered in the Big display language.
As point moves over the stack, a panel at the top-right of the calc
window shows the active entry in 2D Big form, while the stack itself
stays in the normal one-line display. The panel is display-only — it
never takes focus and the window manager ignores it. It is hidden while
the whole buffer is already in Big display and during an in-place edit
session.

On a graphical frame with the `posframe' package the panel is a child
frame; otherwise — on a text terminal, or without posframe — it is
drawn inside the window itself, over the stack lines it covers."
  :lighter " preview"
  :group 'maf
  (if maf-preview-mode
      (progn
        (add-hook 'post-command-hook #'maf-preview--update nil t)
        ;; The panel is placed against the window, not the text, so a
        ;; scroll moves it even when no command of the user's is
        ;; involved. (Layout changes do too; the module takes that hook
        ;; globally, see `maf-preview--on-window-change'.)
        (add-hook 'window-scroll-functions #'maf-preview--on-scroll nil t)
        (add-hook 'after-change-functions #'maf-preview--on-change nil t)
        (maf-preview--update))
    (remove-hook 'post-command-hook #'maf-preview--update t)
    (remove-hook 'window-scroll-functions #'maf-preview--on-scroll t)
    (remove-hook 'after-change-functions #'maf-preview--on-change t)
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
  ;; The panel floats over one window, so it has to follow the view from
  ;; window to window and go when the view leaves calc; the hooks live
  ;; only while the module is on.
  (if maf-use-preview-mode
      (progn
        (add-hook 'window-selection-change-functions #'maf-preview--on-window-change)
        (add-hook 'window-configuration-change-hook #'maf-preview--on-window-change))
    (remove-hook 'window-selection-change-functions #'maf-preview--on-window-change)
    (remove-hook 'window-configuration-change-hook #'maf-preview--on-window-change)
    (maf-preview--hide)
    (when (and (featurep 'posframe) (get-buffer maf-preview--buffer))
      (posframe-delete maf-preview--buffer))))

;; Register with the module system when it is present; the mode above
;; works on its own without it.
(when (require 'maf-module nil t)
  (maf-register-module 'maf-preview #'maf-use-preview-mode
                       "Big-display preview of the entry at point, in a floating panel."))

(provide 'maf-preview)
