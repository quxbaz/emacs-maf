;; -*- lexical-binding: t; -*-
;;
;; public/gen/screens.el — screenshots of maf's features, and the same
;; buffers as fontified HTML, for the site.
;;
;; Piloted in a live graphical instance: each scene sets the calc
;; buffer up, drives the feature with the keys a person would press,
;; exports the frame (`x-export-frames'), crops the image to the
;; windows the feature occupies, and writes the buffer of interest as
;; HTML/CSS through `htmlfontify-buffer'. The window layout and the
;; stack are put back afterwards. Output: media/screens/NAME.png and
;; NAME.html. Needs ImageMagick's `convert' for the crop.
;;
;;   emacsclient -s '#emacs' --eval '(progn (load-file "public/gen/screens.el") (maf-screens-run))'

(require 'htmlfontify)

(defvar maf-screens-directory
  (expand-file-name "../media/screens/"
                    (file-name-directory (or load-file-name buffer-file-name)))
  "Where the captures go.")

(defvar maf-screens-log nil
  "What the last run did: (NAME . RESULT) per scene, RESULT a string on error.")

(defun maf-screens--calc-window ()
  (or (get-buffer-window "*Calculator*")
      (progn (calc) (get-buffer-window "*Calculator*"))))

(defun maf-screens--window-box (w)
  "The pixel box (LEFT TOP RIGHT BOTTOM) of W's header line and text, tightly.
The window's own edges, cut down to what the buffer's text fills plus
a margin: a calc buffer of three entries does not need the whole
window height it stands in, a long menu takes all of it."
  (pcase-let* ((`(,left ,top ,right ,bottom) (window-pixel-edges w))
               (ileft (car (window-inside-pixel-edges w)))
               (`(,tw . ,th) (window-text-pixel-size w nil nil
                                                     (- right left) (- bottom top))))
    ;; The header line — maf-edit's banner, a menu's key legend — can
    ;; run wider than the text under it; the crop takes it whole.
    (let ((header (with-current-buffer (window-buffer w)
                    (if header-line-format
                        (string-pixel-width
                         (format-mode-line header-line-format nil w))
                      0))))
      (list left top
            (min right (max 1000 (+ ileft (max tw header) 48)))
            (min bottom (+ top (window-header-line-height w) th 24))))))

(defun maf-screens--export (name buffers)
  "Export the frame cropped to the windows showing BUFFERS as NAME.png."
  (redisplay t)
  (sit-for 0.3)
  (redisplay t)
  (let* ((png (x-export-frames nil 'png))
         (raw (make-temp-file "maf-screen" nil ".png"))
         (out (expand-file-name (concat name ".png") maf-screens-directory))
         (edges (delq nil (mapcar (lambda (b)
                                    (let ((w (get-buffer-window b)))
                                      (and w (maf-screens--window-box w))))
                                  buffers))))
    (unless edges (error "No window shows %S" buffers))
    (with-temp-file raw (set-buffer-multibyte nil) (insert png))
    (let* ((left (apply #'min (mapcar #'car edges)))
           (top (apply #'min (mapcar #'cadr edges)))
           ;; Side-by-side windows keep their full width: a tight
           ;; right edge would cut the second window's header line.
           (right (if (cdr edges)
                      (apply #'max (mapcar (lambda (b)
                                             (caddr (window-pixel-edges
                                                     (get-buffer-window b))))
                                           buffers))
                    (caddr (car edges))))
           (bottom (apply #'max (mapcar #'cadddr edges))))
      (unless (zerop (call-process "convert" nil nil nil raw "-crop"
                                   (format "%dx%d+%d+%d" (- right left) (- bottom top) left top)
                                   "+repage" out))
        (error "convert failed for %s" name)))
    (delete-file raw)
    out))

(defun maf-screens--html (name buffer)
  "Write BUFFER fontified as NAME.html."
  (with-current-buffer buffer
    (let ((hfy-optimizations (list 'skip-refontification))
          (html (htmlfontify-buffer)))
      (with-current-buffer html
        (write-region (point-min) (point-max)
                      (expand-file-name (concat name ".html") maf-screens-directory)))
      (kill-buffer html))))

(defun maf-screens--stack (&rest exprs)
  "Replace the stack with EXPRS, bottom first, point at home."
  (with-current-buffer "*Calculator*"
    (deactivate-mark)                   ; a stale region would become a target
    (calc-pop (calc-stack-size))
    (dolist (e exprs) (maf-push e))
    (calc-refresh)                      ; renumber: pushes outside a command do not
    (goto-char (point-max))))

(defun maf-screens--at (str &optional off level)
  "Put point at STR in entry LEVEL (default 1), OFF chars in, and refresh the highlight."
  (calc-cursor-stack-index (or level 1))
  (search-forward str (line-end-position))
  (goto-char (+ (match-beginning 0) (or off 0)))
  (run-hooks 'post-command-hook))

(defun maf-screens--keys (keys)
  (execute-kbd-macro (kbd keys))
  (redisplay t))

(defun maf-screens--narrow ()
  "Give the calc window a width a picture can hold.
Calc's banner pads itself to the window, so a frame-wide window makes
a frame-wide picture; a second window beside it takes the rest."
  (set-window-buffer (split-window nil 1100 'right t) "*scratch*"))

(defmacro maf-screens--scene (name buffers html-buffer &rest body)
  "Run BODY in the calc window, capture NAME over BUFFERS, HTML of HTML-BUFFER."
  (declare (indent 3))
  `(let ((config (current-window-configuration))
         ;; The entries top first, behind calc's top-of-stack marker.
         (saved (with-current-buffer "*Calculator*" (cdr (mapcar #'car calc-stack)))))
     (when (or (null maf-screens-only) (member ,name maf-screens-only))
     (condition-case err
         (progn
           (with-selected-window (maf-screens--calc-window)
             (delete-other-windows)
             ,@body
             ;; A scene whose body must tear something down after the
             ;; capture exports itself and passes nil here.
             (when ,buffers
               (maf-screens--export ,name ,buffers)
               (maf-screens--html ,name ,html-buffer)))
           (push (cons ,name t) maf-screens-log))
       (error (push (cons ,name (error-message-string err)) maf-screens-log)))
     (set-window-configuration config)
     (with-current-buffer "*Calculator*"
       (calc-pop (calc-stack-size))
       (calc-push-list (reverse saved))   ; bottom first, so the top lands last
       (calc-refresh)))))

(defun maf-screens--quit (buffer)
  "Close BUFFER's window and bury it, however the buffer wants."
  (when-let ((w (get-buffer-window buffer)))
    (with-selected-window w
      (condition-case nil (quit-window) (error (delete-window w))))))

(defvar maf-screens-only nil
  "When non-nil, the scene names `maf-screens-run' limits itself to.")

(defun maf-screens-run (&optional only)
  "Capture every scene, or just the ONLY named; see `maf-screens-log'."
  (interactive)
  (make-directory maf-screens-directory t)
  (setq maf-screens-log nil
        maf-screens-only only)
  ;; The contextual highlight: the sub-formula under point.
  (maf-screens--scene "highlight" '("*Calculator*") "*Calculator*"
    (maf-screens--narrow)
    (maf-screens--stack "[1 cm, 2 cm, 1 m]" "(x + 1)^2 = -8 (y + 2)")
    (maf-screens--at "y + 2" 2))
  ;; The equation target: one side selected by point.
  (maf-screens--scene "equation" '("*Calculator*") "*Calculator*"
    (maf-screens--narrow)
    (maf-screens--stack "x^2 + 2 x + 1 = 4")
    (maf-screens--at "x^2 + 2 x + 1" 4))
  ;; A calc selection, with the selplus badge in the header line.
  (maf-screens--scene "selection" nil nil
    (maf-screens--narrow)
    (maf-screens--stack "sin(2 x) + cos(x)^2 = 1")
    (maf-screens--at "cos" 1)
    (maf-screens--keys "j s")
    (maf-screens--at "cos" 1)
    (unwind-protect
        (progn (maf-screens--export "selection" '("*Calculator*"))
               (maf-screens--html "selection" "*Calculator*"))
      (calc-clear-selections)))
  ;; The stack as editable text, the handwriting dialect colored.
  (maf-screens--scene "edit" nil nil
    (maf-screens--narrow)
    (maf-screens--stack "2 x y + 3 cm" "(x + 1)^2 = -8 (y + 2)")
    (maf-screens--keys "SPC")
    (goto-char (point-max))
    (insert "3xy^2 + 2{cm}")
    (redisplay t)
    (unwind-protect
        (progn (maf-screens--export "edit" '("*Calculator*"))
               (maf-screens--html "edit" "*Calculator*"))
      (maf-edit-discard)))
  ;; The plot, embedded under the stack.
  (maf-screens--scene "plot" '("*Calculator*" "*maf-plot*") "*Calculator*"
    (maf-screens--stack "(x + 1)^2 = -8 (y + 2)")
    (maf-screens--keys "g l")
    ;; The stack needs three lines; the plot takes the rest. Fitting
    ;; scrolls the entry off, so the window start goes back to the top.
    (let ((w (get-buffer-window "*Calculator*")))
      (fit-window-to-buffer w nil 4)
      (set-window-start w (point-min) t))
    (redisplay t)
    (sit-for 0.8))
  ;; The bindings help.
  (maf-screens--scene "keys" '("*maf-keys*") "*maf-keys*"
    (maf-screens--stack "x^2")
    (call-interactively #'maf-keys)
    (delete-other-windows (get-buffer-window "*maf-keys*")))
  ;; The options menu.
  (maf-screens--scene "options" '("*maf-options*") "*maf-options*"
    (maf-screens--stack "x^2")
    (call-interactively #'maf-options)
    (delete-other-windows (get-buffer-window "*maf-options*")))
  ;; The module menu.
  (maf-screens--scene "modules" '("*maf-modules*") "*maf-modules*"
    (maf-screens--stack "x^2")
    (call-interactively #'maf-list-modules)
    (delete-other-windows (get-buffer-window "*maf-modules*")))
  ;; The formula library.
  (maf-screens--scene "formulas" '("*maf-formulas*" " *maf-formulas-detail*") "*maf-formulas*"
    (maf-screens--stack "x^2")
    (call-interactively #'maf-formulas)
    (redisplay t)
    (sit-for 0.5))
  ;; The stack history beside its log.
  (maf-screens--scene "history" '("*maf-history*" "*maf-history-stack*") "*maf-history*"
    (maf-screens--stack "x^2 + 2 x + 1 = 4")
    (maf-screens--keys "a f")
    (call-interactively #'maf-history))
  ;; The saved stacks of every session.
  (maf-screens--scene "saved-stacks" '("*maf-stacks*") "*maf-stacks*"
    (maf-screens--stack "x^2")
    (call-interactively #'maf-saved-stacks)
    (delete-other-windows (get-buffer-window "*maf-stacks*")))
  ;; Paper-style output: descending polynomials, e^x, general-base
  ;; logs. The modules shape what comes out of simplification, so each
  ;; entry is simplified where it stands (k k at home).
  (maf-screens--scene "paper" '("*Calculator*") "*Calculator*"
    (maf-screens--narrow)
    (maf-screens--stack "1 + x + x^2")
    (maf-screens--keys "k k")
    (dolist (e '("exp(2 x)" "3^log(x, 3) + ln(y)"))
      (maf-push e)
      (calc-refresh)
      (goto-char (point-max))
      (maf-screens--keys "k k"))
    (goto-char (point-max)))
  ;; The preview panel: the entry at point in Big display. The child
  ;; frame is a frame of its own, which the export does not see, so the
  ;; in-window panel draws it for the picture.
  (maf-screens--scene "preview" nil nil
    (maf-screens--stack "(x + 1)^2 / (2 y) = sqrt(z) + 1:3")
    (maf-screens--narrow)
    (cl-letf (((symbol-function 'maf-preview--posframe-p) (lambda () nil)))
      (maf-screens--at "sqrt(z)" 5)
      (redisplay t)
      (sit-for 0.5)
      (maf-screens--export "preview" '("*Calculator*"))
      (maf-screens--html "preview" "*Calculator*")))
  (nreverse maf-screens-log))
