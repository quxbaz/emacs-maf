;; -*- lexical-binding: t; -*-
;;
;; maf-hl-verify.el
;;
;; Programmatic verification of maf-hl-mode highlighting, written to be driven
;; by an AI assistant over emacsclient (see docs/memory/piloting-emacs.md).
;; No screenshots and no human eyeballing anywhere in the loop.
;;
;; Two levels of evidence:
;;
;;   State  — the `maf-hl--overlay' overlay exists, carries the `maf-hl' face,
;;            and covers exactly the expected text. Works in any session,
;;            including batch.
;;
;;   Render — proof the display engine actually drew the highlight. The frame
;;            rasterizes *itself* via `x-export-frames' (in-process, no window
;;            manager or screenshot tool), then ImageMagick reduces the raster
;;            to the bounding box of the pixels matching the resolved `maf-hl'
;;            background within the calc window. That box must equal the size
;;            Emacs independently predicts: `string-pixel-width' of the
;;            highlighted text x `frame-char-height'. Requires a visible GUI
;;            frame and ImageMagick; degrades to :render skipped otherwise.
;;
;; Typical AI session (fresh frame per the piloting doc):
;;
;;   emacsclient --eval '(load-file "/path/to/maf.el")'
;;   DISPLAY=:0.0 emacsclient -c -n -F '((name . "maf-verify"))'
;;   emacsclient --eval \
;;     '(with-selected-frame
;;          (seq-find (lambda (f) (equal (frame-parameter f (quote name))
;;                                       "maf-verify"))
;;                    (frame-list))
;;        (maf-hl-verify-demo))'
;;   ;; => (:ok t :checks ((atom . (...)) (subexpr . (...)) (home . (...))))
;;
;; Then clean up: delete the frame, kill *Calculator* and *Calc Trail*.

(require 'seq)
(require 'maf-hl)

(defun maf-hl-verify--color-hex (color frame)
  "Return COLOR resolved on FRAME as a 8-bit-per-channel hex string."
  (apply #'format "#%02x%02x%02x"
         (mapcar (lambda (v) (/ v 256)) (color-values color frame))))

(defun maf-hl-verify--state ()
  "Return a plist describing the maf-hl overlay in the current buffer."
  (let* ((ov maf-hl--overlay)
         (live (and (overlayp ov) (overlay-buffer ov) t)))
    (list :mode maf-hl-mode
          :overlay-live live
          :face (and live (overlay-get ov 'face))
          :text (and live (buffer-substring-no-properties
                           (overlay-start ov) (overlay-end ov)))
          :covers-point (and live
                             (<= (overlay-start ov) (point))
                             (< (point) (overlay-end ov))))))

(defun maf-hl-verify--glyph-xy (pos window)
  "Raster pixel coordinates of the top-left of the glyph at POS in WINDOW.
`x-export-frames' rasterizes the native frame area, so convert the glyph's
absolute screen coordinates to raster coordinates by subtracting the frame's
native origin. Return (X Y), or nil when POS is not visible."
  (let ((abs (window-absolute-pixel-position pos window))
        (native (frame-edges (window-frame window) 'native-edges)))
    (when abs
      (list (- (car abs) (nth 0 native))
            (- (cdr abs) (nth 1 native))))))

(defun maf-hl-verify--block-bbox (png color rect min-area im)
  "Union bounding box of COLOR blobs of MIN-AREA pixels or more in RECT.
RECT is (W H X Y) in raster pixels of image PNG. Uses ImageMagick
executable IM. Return (W H X Y) raster-relative, or nil when nothing
qualifies.

Blobs smaller than MIN-AREA are ignored: a theme can use the exact face
color for small decorations nearby (observed: the 7x1 px dashes of the calc
window's header line), and those must not stretch the measured box. A
highlighted cell whose background is fragmented by glyph ink still
contributes, since its fragments are much larger than decorations."
  (pcase-let ((`(,w ,h ,x ,y) rect))
    (with-temp-buffer
      (when (zerop (call-process
                    im nil t nil
                    png
                    "-crop" (format "%dx%d+%d+%d" w h x y) "+repage"
                    "-fill" "white" "-opaque" color
                    "-fill" "black" "+opaque" "white"
                    "-define" "connected-components:verbose=true"
                    "-define" "connected-components:area-threshold=1"
                    "-connected-components" "8" "null:"))
        (goto-char (point-min))
        (let (x1 y1 x2 y2)
          (while (re-search-forward
                  (concat "^ *[0-9]+: \\([0-9]+\\)x\\([0-9]+\\)"
                          "\\+\\([0-9]+\\)\\+\\([0-9]+\\) [0-9.,e+-]+ "
                          "\\([0-9]+\\) "
                          "\\(?:srgb(255,255,255)\\|gray(255)\\|white\\)$")
                  nil t)
            (let ((bw (string-to-number (match-string 1)))
                  (bh (string-to-number (match-string 2)))
                  (bx (string-to-number (match-string 3)))
                  (by (string-to-number (match-string 4)))
                  (area (string-to-number (match-string 5))))
              (when (>= area min-area)
                (setq x1 (min (or x1 bx) bx)
                      y1 (min (or y1 by) by)
                      x2 (max (or x2 0) (+ bx bw))
                      y2 (max (or y2 0) (+ by bh))))))
          (when x1
            (list (- x2 x1) (- y2 y1) (+ x x1) (+ y y1))))))))

(defun maf-hl-verify--coverage (png color rect im)
  "Fraction of pixels in RECT of image PNG that match COLOR exactly.
RECT is (W H X Y) in raster pixels. Uses ImageMagick executable IM. Return
a float in [0, 1], or nil when the crop fails (e.g. RECT out of bounds)."
  (pcase-let ((`(,w ,h ,x ,y) rect))
    (with-temp-buffer
      (when (zerop (call-process
                    im nil t nil
                    png
                    "-crop" (format "%dx%d+%d+%d" w h x y) "+repage"
                    "-fill" "white" "-opaque" color
                    "-fill" "black" "+opaque" "white"
                    "-format" "%[fx:mean]" "info:"))
        (string-to-number (buffer-string))))))

(defun maf-hl-verify--render ()
  "Check that the maf-hl overlay is actually drawn on screen.
Return a plist whose :render is ok, fail, or skipped (with :reason).
Skipped is used whenever a rendering check is not possible in this session;
it is not a failure."
  (let* ((ov maf-hl--overlay)
         (window (get-buffer-window (current-buffer) t))
         (frame (and window (window-frame window)))
         (im (or (executable-find "magick") (executable-find "convert"))))
    ;; A window manager may have iconified the frame (observed with
    ;; StumpWM); bring it back before giving up. `make-frame-visible' alone
    ;; is not always honored — focusing the frame is, at the cost of
    ;; stealing input focus (acceptable for a debug tool).
    (when (and frame
               (display-graphic-p frame)
               (not (eq t (frame-visible-p frame))))
      (make-frame-visible frame)
      (raise-frame frame)
      (select-frame-set-input-focus frame)
      (let ((n 0))
        (while (and (< n 10) (not (eq t (frame-visible-p frame))))
          (sit-for 0.1)
          (setq n (1+ n)))))
    (cond
     ((not (and (overlayp ov) (overlay-buffer ov)))
      (list :render 'skipped :reason "no overlay to render"))
     ((not window)
      (list :render 'skipped :reason "buffer not displayed in a visible window"))
     ((not (display-graphic-p frame))
      (list :render 'skipped :reason "not a GUI frame"))
     ((not (eq t (frame-visible-p frame)))
      (list :render 'skipped :reason "frame invisible or iconified"))
     ((not im)
      (list :render 'skipped :reason "ImageMagick (magick/convert) not found"))
     ((not (fboundp 'x-export-frames))
      (list :render 'skipped :reason "x-export-frames unavailable"))
     ((/= (line-number-at-pos (overlay-start ov))
          (line-number-at-pos (overlay-end ov)))
      (list :render 'skipped :reason "highlight spans multiple lines"))
     (t
      (let ((bg (face-attribute 'maf-hl :background frame t)))
        (if (memq bg '(nil unspecified))
            (list :render 'skipped :reason "maf-hl resolves to no background")
          (let* ((text (buffer-substring-no-properties
                        (overlay-start ov) (overlay-end ov)))
                 (w (string-pixel-width text))
                 (h (frame-char-height frame))
                 (cw (frame-char-width frame))
                 (color (maf-hl-verify--color-hex bg frame))
                 (file (make-temp-file "maf-hl-verify-" nil ".png"))
                 (had-local (local-variable-p 'cursor-type))
                 (old-cursor cursor-type)
                 xy)
            (unwind-protect
                (progn
                  ;; Hide the cursor while exporting: a solid cursor paints
                  ;; over the overlay background and punches a cell-sized
                  ;; hole in the block we measure.
                  (setq-local cursor-type nil)
                  (unwind-protect
                      (progn
                        (redisplay t)
                        (setq xy (maf-hl-verify--glyph-xy
                                  (overlay-start ov) window))
                        (let ((coding-system-for-write 'binary))
                          (write-region (x-export-frames frame 'png)
                                        nil file nil 'silent)))
                    (if had-local
                        (setq-local cursor-type old-cursor)
                      (kill-local-variable 'cursor-type)))
                  (if (not xy)
                      (list :render 'skipped
                            :reason "highlight start not visible in window")
                    ;; A block of the face color, exactly the size Emacs
                    ;; predicts for the highlighted text, must exist in the
                    ;; predicted column — searched over a ±2-line strip
                    ;; because glyph-position APIs and the exported raster
                    ;; can disagree vertically by a line (observed with snap
                    ;; Emacs). It must be mostly filled (glyph ink punches
                    ;; holes) and must stop where predicted: the neighboring
                    ;; cell on each side has to be free of the face color.
                    (pcase-let* ((`(,x ,y) xy)
                                 (strip (list w (* 5 h) x (max 0 (- y (* 2 h)))))
                                 (min-area (max 10 (/ (* cw h) 20)))
                                 (block (maf-hl-verify--block-bbox
                                         file color strip min-area im))
                                 (by (and block (nth 3 block)))
                                 (inside (and block (maf-hl-verify--coverage
                                                     file color block im)))
                                 (left (and by (maf-hl-verify--coverage
                                                file color
                                                (list cw h (- x cw) by) im)))
                                 (right (and by (maf-hl-verify--coverage
                                                 file color
                                                 (list cw h (+ x w) by) im))))
                      (list :render (if (and block
                                             (= (nth 0 block) w)
                                             (= (nth 1 block) h)
                                             (>= (or inside 0) 0.5)
                                             (< (or left 0) 0.05)
                                             (< (or right 0) 0.05))
                                        'ok
                                      'fail)
                            :expected-size (list w h)
                            :block block
                            :y-offset (and by (- by y))
                            :coverage inside
                            :left-bleed left
                            :right-bleed right
                            :bg color))))
              (delete-file file)))))))))

(defun maf-hl-verify-at (target &optional expected-text)
  "Verify sub-formula highlighting at TARGET in the current calc buffer.
Search for the string TARGET from the top of the buffer, place point on its
last character, run the highlight update, and judge the result. With
EXPECTED-TEXT a string, the highlight must cover exactly that text; with
EXPECTED-TEXT nil, there must be no highlight at TARGET.

Return a plist: :ok is the verdict, the remaining keys are the evidence.
State keys come from `maf-hl-verify--state'; when the state check passes and
the buffer is shown in a visible GUI frame, :render reports whether the
highlight is actually drawn (see `maf-hl-verify--render')."
  (goto-char (point-min))
  (search-forward target)
  (backward-char 1)
  (maf-hl--update)
  (let* ((state (maf-hl-verify--state))
         (state-ok
          (if expected-text
              (and (plist-get state :overlay-live)
                   (eq (plist-get state :face) 'maf-hl)
                   (plist-get state :covers-point)
                   (equal (plist-get state :text) expected-text))
            (not (plist-get state :overlay-live))))
         (render (if (and expected-text state-ok)
                     (maf-hl-verify--render)
                   (list :render 'skipped
                         :reason "state check failed or negative check")))
         (render-ok (memq (plist-get render :render) '(ok skipped))))
    (append (list :ok (and state-ok render-ok t)
                  :target target
                  :expected expected-text)
            state render)))

(defun maf-hl-verify-demo ()
  "Self-contained programmatic check of maf-hl-mode; return a verdict plist.
Open calc in the selected frame, push 2 (3 x + 4), enable `maf-hl-mode', and
verify three positions: the atom at \"x\", the enclosing sum at \"+\", and
the absence of a highlight on the home line. In a visible GUI session the
positive checks include pixel-level render verification.

Starts from a fresh calc: any existing *Calculator* and *Calc Trail* buffers
are killed first (as `maf-step' does), which also clears stray overlays from
earlier experiments — do not run this on a calc stack you care about. Cleans
nothing up afterwards (inspect the calc buffer on failure); kill
*Calculator* and *Calc Trail* when done.

Return (:ok BOOL :checks ((LABEL . PLIST) ...))."
  (interactive)
  (dolist (name '("*Calculator*" "*Calc Trail*"))
    (when (get-buffer name)
      (kill-buffer name)))
  (let ((calc-display-trail nil))
    (calc))
  ;; (calc) may reuse or create a window on another (possibly invisible)
  ;; frame; the render check needs the buffer shown in the selected frame.
  (with-selected-window (or (get-buffer-window "*Calculator*" (selected-frame))
                            (display-buffer
                             "*Calculator*"
                             '(display-buffer-below-selected
                               . ((window-height . 12)))))
    ;; The author's personal config enables a legacy highlighter
    ;; (my/calc-debug-highlight-mode) in every calc buffer; it draws an
    ;; identical overlay that would mask maf-hl failures, so switch it off.
    (when (and (fboundp 'my/calc-debug-highlight-mode)
               (bound-and-true-p my/calc-debug-highlight-mode))
      (my/calc-debug-highlight-mode -1))
    ;; The stack survives killing the buffer (calc keeps it in global
    ;; state), so empty it explicitly for determinism.
    (when (> (calc-stack-size) 0)
      (calc-pop (calc-stack-size)))
    (calc-push '(* 2 (+ (* 3 (var x var-x)) 4)))
    (maf-hl-mode 1)
    (let ((checks (list (cons 'atom (maf-hl-verify-at "x" "x"))
                        (cons 'subexpr (maf-hl-verify-at "+" "(3 x + 4)"))
                        (cons 'home (maf-hl-verify-at "." nil)))))
      (list :ok (and (seq-every-p (lambda (c) (plist-get (cdr c) :ok)) checks) t)
            :checks checks))))

(provide 'maf-hl-verify)
