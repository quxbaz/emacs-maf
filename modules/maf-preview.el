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
;; module system as `maf-preview' (see `maf-modules'). What it decides
;; is whether a panel *follows point*, and that is all it decides:
;; `maf-preview-show' (G) opens the entry at point in the preview
;; window below the stack — the pretty module's window, in an even
;; split that takes focus and hands it back on q (see
;; modules/maf-pretty.el), drawn in Big rather than typeset — module
;; on or off, without the buffer-local mode. So the two states are one
;; panel always, or a look when asked for; there is no third to
;; configure.

(require 'calc)
(require 'calc-yank)         ; calc-locate-cursor-element
(require 'seq)
(require 'mule-util)         ; truncate-string-to-width, truncate-string-ellipsis
(require 'posframe nil t)    ; optional; the child-frame backend needs it
(require 'maf-conf "conf")   ; the `maf' customize group

;; Rendered on demand; the byte compiler needs the declarations.
(declare-function math-format-value "calc-ext")
(declare-function maf-pretty--show-text "maf-pretty")
(declare-function posframe-show "posframe")
(declare-function posframe-hide "posframe")
(declare-function posframe-delete "posframe")
(declare-function posframe-workable-p "posframe")
(declare-function maf-register-module "maf-module")

(defconst maf-preview--buffer " *maf-preview*"
  "Name of the buffer backing the preview child frame.")

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

(defface maf-preview-big
  '((t :inherit default :height 1.1))
  "Face for the Big-rendered text of the child-frame panel.
A little larger than the buffer's own text, so the second view reads
at a glance instead of blending into the stack beside it. Only the
child frame honors it: the in-window panel draws its rows in
`maf-preview-panel', whose column arithmetic needs canonical-width
characters."
  :group 'maf)

;;; Rendering the entry

(defvar maf-preview-render-function nil
  "Function drawing the panel's contents, or nil for the Big rendering.

Called with the value the panel is standing over — the selected
sub-formula where there is a selection, the whole entry otherwise, the
same value the Big rendering below would have received — and returns
the string to draw, or nil to leave this entry to that rendering. The
string may carry a display property, an image included, so a module can
put something in the panel that Calc has no display language for.

It is consulted only where the panel can show that much (see
`maf-preview--rich-p'), so what it returns is never asked to survive as
characters. Errors are contained the same way a nil is: the Big
rendering draws instead, and the panel stays up.

The pretty module sets this while `maf-use-pretty-mode' is on, which is
how a typeset entry reaches this panel without this file knowing what
LaTeX is.")

(defun maf-preview--render ()
  "Return the active entry rendered for the panel, or nil.
The active entry is the one at point, or the top entry when point is at
home. Returns nil when there is nothing to preview: an empty stack, an
active maf-edit session (whose text the stack no longer matches), or a
buffer already showing the Big language with nothing but the Big
rendering to offer (the panel would be redundant).

`maf-preview-render-function' is asked first where the panel can show
what it draws. A rendering of its own is never redundant with the
buffer's language, so the Big test guards only the Big fallback: a
typeset panel over a Big stack is still the second view it was turned
on to be."
  (unless (bound-and-true-p maf-edit-mode)
    (let ((size (calc-stack-size)))
      (unless (zerop size)
        (let* ((idx (calc-locate-cursor-element (point)))
               (level (if (> idx 0) (min idx size) 1))
               ;; The stored value, via `calc-top' rather than
               ;; `calc-top-n': the preview is a second view of the
               ;; entry as it stands on the stack, so it must show what
               ;; the stack line shows. `calc-top-n' normalizes, which
               ;; under a simplification mode would preview
               ;; `6 x + 12 = 18 y + 6' as `x + 1 = 3 y' — a different
               ;; formula from the one being worked on. This is the
               ;; value calc itself composes the stack line from.
               (value (calc-top level)))
          (or (and maf-preview-render-function
                   (maf-preview--rich-p)
                   (ignore-errors (funcall maf-preview-render-function value)))
              ;; Rendered in Big without disturbing the buffer's own
              ;; display language (see this file's commentary). Long
              ;; vectors are always abbreviated (`[1, 2, 3, ..., 100]'),
              ;; whatever the buffer's `v .' setting: a full 100-element
              ;; vector would make the panel taller than the window it
              ;; sits in.
              (unless (eq calc-language 'big)
                (let ((calc-language 'big)
                      (calc-full-vectors nil))
                  (propertize (math-format-value value)
                              'face 'maf-preview-big)))))))))

;;; The child-frame backend

(defconst maf-preview--posframe-inset 18
  "Pixels between the child frame's right edge and the window's.
The top margin is derived from this so the frame sits equidistant
from the window's text area: see `maf-preview--poshandler'.")

(defun maf-preview--poshandler (info)
  "Position the preview inset from the calc window's top-right corner.
The right margin is `maf-preview--posframe-inset' in from the window's
pixel edge. Part of that run is dead space text never reaches — the
fringe, and any scroll bar or divider — while above the frame every
pixel below the header line is text area. An inset repeated verbatim
therefore reads top-heavy, so the top margin is the same inset less
that right-edge padding: equidistant from the text area, which is the
margin the eye measures. A posframe poshandler; see `posframe-show'."
  (let* ((win (plist-get info :parent-window))
         ;; Frame-relative text-area edges, past the fringes and below
         ;; the header and tab lines — like the window coordinates in
         ;; INFO, which posframe reads off the same frame.
         (edges (window-inside-pixel-edges win))
         (window-right (+ (plist-get info :parent-window-left)
                          (plist-get info :parent-window-width)))
         (pad (- window-right (nth 2 edges))))
    (cons (- window-right (plist-get info :posframe-width)
             maf-preview--posframe-inset)
          (+ (nth 1 edges)
             (max 0 (- maf-preview--posframe-inset pad))))))

(defun maf-preview--posframe-p ()
  "Non-nil when the child-frame backend can be used on this frame.
False on a text terminal, and whenever posframe is not installed."
  (and (featurep 'posframe) (posframe-workable-p)))

(defun maf-preview--rich-p ()
  "Non-nil when the panel can show more than the characters of a string.
The child frame is a real buffer in a real frame, so a display property
draws there as it draws anywhere. The in-window panel is rows of text
laid over stack lines, sized and clipped in columns and spliced into
`display' properties of its own — an image has no column width that
arithmetic could use, and nowhere to go once the row is one."
  (and (display-graphic-p) (maf-preview--posframe-p)))

(defconst maf-preview--posframe-pad '(3 . 2)
  "Vertical padding inside the child frame, in pixels (TOP . BOTTOM).
For content carrying a display property — a RaTeX rendering, which
brings a margin of its own inside the image. The bottom runs tighter:
a rendered formula carries a sliver of clearance of its own below the
baseline, and matching the top's padding verbatim reads bottom-heavy.
Both numbers were set by eye against the RaTeX rendering.")

(defconst maf-preview--posframe-text-pad '(7 . 6)
  "Vertical padding inside the child frame for plain text (TOP . BOTTOM).
Bare text has no margin of its own the way an image does, so it gets
a larger allowance — plus a space column each side, added where these
numbers are used — to meet the border at about the distance the RaTeX
rendering keeps.")

(defvar maf-preview--frame nil
  "The child frame `posframe-show' last handed back, or nil.
Kept so `maf-preview--on-screen-p' can ask the panel whether it is
really displayed without searching `frame-list' or reaching into
posframe's own variables.")

(defun maf-preview--posframe-show (str)
  "Show STR in the preview child frame.
The frame's border is its visible edge, so the room between it and the
content is made here: the fringes pad the sides, and STR is framed by
two blank lines of exactly `maf-preview--posframe-pad' pixels — each a
stretch glyph, with the top line's newline shrunk under it so no
full-height glyph props the line open. Plain text is padded more than
an image — see `maf-preview--posframe-text-pad'."
  (let* ((imagep (get-text-property 0 'display str))
         (pad (if imagep maf-preview--posframe-pad
                maf-preview--posframe-text-pad))
         (body (if imagep str
                 (mapconcat (lambda (line) (concat " " line " "))
                            (split-string str "\n") "\n")))
         (frame (posframe-show
                maf-preview--buffer
                :string (concat
                         (propertize " " 'face '(:height 0.1)
                                     'display `(space :height (,(car pad))))
                         (propertize "\n" 'face '(:height 0.1))
                         body
                         "\n"
                         (propertize " " 'display `(space :height (,(cdr pad)))))
                :poshandler #'maf-preview--poshandler
                :internal-border-width 2
                :internal-border-color "gray50"
                :left-fringe 5
                :right-fringe 5
                :accept-focus nil)))
    ;; posframe-show can leave a previously-hidden child frame
    ;; iconified rather than visible on some window managers; force it
    ;; visible.
    (when (frame-live-p frame)
      (setq maf-preview--frame frame)
      (make-frame-visible frame))))

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


(defun maf-preview--border-row (left right inner)
  "Return a horizontal panel border INNER columns wide between LEFT and RIGHT.
LEFT and RIGHT are the corner characters."
  (propertize (concat (string left)
                      (make-string inner ?─)
                      (string right))
              'face 'maf-preview-border))

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
    (when (and (>= body-width 1) (>= body-height 1))
      (let* ((lines (split-string str "\n"))
             (lines (if (> (length lines) body-height)
                        (append (seq-take lines (1- body-height))
                                (list (truncate-string-ellipsis)))
                      lines))
             (lines (mapcar (lambda (line)
                              (truncate-string-to-width line body-width nil nil t))
                            lines))
             (inner (+ 2 (apply #'max (mapcar #'string-width lines)))))
        (append (list (maf-preview--border-row ?┌ ?┐ inner))
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
             ;; posframe measures its parent window from the selected
             ;; one, and WIN is not necessarily selected — the mode can
             ;; be switched on from another window (the module menu).
             (with-selected-window win
               (maf-preview--posframe-show str)))
    (maf-preview--posframe-hide)
    (maf-preview--overlay-show str win start)))

(defun maf-preview--hide ()
  "Hide the preview panel, whichever backend is showing it."
  (setq maf-preview--state nil)
  (maf-preview--posframe-hide)
  (maf-preview--overlay-hide))

(defun maf-preview--on-screen-p ()
  "Non-nil when the panel is really displayed, not merely drawn once.

The child frame can be taken down without the module hearing of it — a
window manager iconifying it, or another posframe user hiding the whole
set — and `maf-preview--state' would still describe it as drawn. Asking
the panel itself is what tells the two apart.

`frame-visible-p' answers `icon' for an iconified frame, which is
non-nil, so nothing short of an `eq' to t distinguishes on screen from
merely existing. The in-window backend's equivalent is whether its
overlays are still attached to a buffer."
  (if (maf-preview--posframe-p)
      (and (frame-live-p maf-preview--frame)
           (eq (frame-visible-p maf-preview--frame) t))
    (and maf-preview--overlays
         (seq-every-p #'overlay-buffer maf-preview--overlays))))

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
        ;; An unchanged panel is left alone — unless it is not actually
        ;; up, where the cache would go on suppressing the one call that
        ;; puts it back. Nothing outside reports the child frame being
        ;; iconified, so the panel is asked on every update instead.
        ;;
        ;; Compared including text properties, because a rendering need
        ;; not be in the characters: what
        ;; `maf-preview-render-function' returns is one space carrying
        ;; a display property, so every entry it draws has the same
        ;; string and only the property tells them apart. Plain `equal'
        ;; read them all as one panel and left the first one up for the
        ;; rest of the session.
        (unless (and (equal-including-properties state maf-preview--state)
                     (maf-preview--on-screen-p))
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

(defun maf-preview--target-window ()
  "Return the window the panel belongs over, or nil if there is none.
The first window on the frame showing a buffer with
`maf-preview-mode' on — and `window-list' starts from the selected
window, so with the stack in two windows the panel goes over the one
the user is working in. Unlike `maf-preview--window' this does not
need the user to be in the stack at all: the mode toggled from the
module menu, or an echo area growing or shrinking under the menu,
still finds the calc window on display beside it."
  (seq-find (lambda (win)
              (buffer-local-value 'maf-preview-mode (window-buffer win)))
            (window-list)))

(defun maf-preview--on-window-change (&rest _)
  "Refresh the preview, or hide it, when the window layout changes.
On `window-selection-change-functions' and
`window-configuration-change-hook' while the module is on: the panel
floats over one window, so it has to go when no window shows the stack
any more, and to be redrawn when that window is resized, split, or
replaced — none of which is a command in the calc buffer.

Both hooks are taken globally rather than buffer-locally on purpose: the
buffer-local form of the configuration hook runs once per window showing
the buffer, each time with that window selected, which would leave the
single panel over whichever window happened to come last.

The window to draw over is searched for (see
`maf-preview--target-window') rather than read off the current buffer's
`maf-preview-mode': these hooks run with whatever buffer redisplay has
current — the module menu's, say, when toggling a module resizes the
echo area under it — and the mode is nil in any buffer but the stack's,
which had the panel hide itself the moment something else was current.

The panel's own arrival is itself a window change, and these hooks then
run with the child frame's buffer current; that event is passed over
rather than answered with a redraw of the panel it is about. Only
redisplay runs these hooks, so a keyboard macro never saw it and a real
keypress always did."
  (unless (eq (current-buffer) (get-buffer maf-preview--buffer))
    (let ((win (maf-preview--target-window)))
      (if win
          (with-current-buffer (window-buffer win)
            (maf-preview--update win))
        (maf-preview--hide)))))

;;;###autoload
(define-minor-mode maf-preview-mode
  "Show the stack entry at point in Calc's two-dimensional display.

The stack stays compact, with one entry per line, while a panel in the
top-right shows the current entry as it would look in Big display. For
example, (x+1)/2 is shown with x+1 above a fraction bar and 2 below it.

This mode is the panel that follows point. With it off, G
\(`maf-preview-show') still previews the entry at point on request,
for as long as it takes the next command to arrive.

The panel is for viewing only and never takes keyboard focus. It hides
while the whole Calc buffer uses Big display and while maf-edit is
active. On graphical frames it uses `posframe' when available;
otherwise it is drawn inside the Calc window."
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
        ;; Against the buffer's window, not the selected one: the mode
        ;; can be switched on from another window — the module menu —
        ;; and the panel should appear there and then, not on the next
        ;; command in the calc window. (`get-buffer-window' prefers the
        ;; selected window, so turning the mode on from the calc buffer
        ;; itself draws where it always did.)
        (maf-preview--update (get-buffer-window)))
    (remove-hook 'post-command-hook #'maf-preview--update t)
    (remove-hook 'window-scroll-functions #'maf-preview--on-scroll t)
    (remove-hook 'after-change-functions #'maf-preview--on-change t)
    (maf-preview--hide)))

;;;###autoload
(defun maf-preview-show ()
  "Show the entry at point in Calc's two-dimensional Big display.

The entry appears in a preview window below Calc — the same even
split, focus move, and q dismissal as `maf-pretty', which shadows
this key while the pretty module is on to give the same look typeset.
The stack, point, and Calc display language are unchanged. Works
whether or not the preview module is on: the module is the panel that
follows point, and this is a look asked for by hand."
  (interactive)
  (unless (derived-mode-p 'calc-mode)
    (user-error "Not in a Calc buffer"))
  (require 'maf-pretty)    ; loaded with maf; standalone loads catch up here
  (let ((str (ignore-errors (maf-preview--render))))
    (if (not str)
        (message "Nothing to preview")
      (maf-pretty--show-text str))))

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
;; works on its own without it. A plain on/off row, and no entry key of
;; the module's own: G is `maf-preview-show', bound whether the module
;; is on or off (src/bindings.el), so it is not a key the toggle brings
;; and takes away.
(when (require 'maf-module nil t)
  (maf-register-module 'maf-preview #'maf-use-preview-mode
                       "Keep the entry at point shown in a big 2D display.

A panel follows point, showing the entry you are on as it would look
in Calc's Big display — (x+1)/2 as a vertical fraction — while the
stack itself stays compact, one entry per line. Module on or off, G
still opens the entry at point in a preview window below the stack —
one look, asked for by hand and dismissed with q."
                       nil "Display"))

(provide 'maf-preview)
