;; -*- lexical-binding: t; -*-
;;
;; maf-hl.el
;;
;; Persistent sub-formula highlighting. `maf-hl-mode' is a buffer-local minor
;; mode for calc buffers that highlights the innermost sub-formula under point
;; as the cursor moves — live feedback on what a contextual command would
;; operate on. maf.el enables it in every calc buffer via `calc-mode-hook';
;; toggle it per buffer with M-x maf-hl-mode.

(require 'calc)
(require 'calc-ext)   ; math-comp-sel-cpos and friends are declared here
(require 'calccomp)   ; math-comp-pos, math-comp-is-flat
(require 'calc-sel)   ; calc-prepare-selection, calc-selection-cache-*
(require 'calc-yank)  ; calc-locate-cursor-element

(defface maf-hl
  '((t :inherit highlight))
  "Face for the sub-formula under point in `maf-hl-mode'."
  :group 'maf)

(defvar-local maf-hl--overlay nil
  "Overlay marking the sub-formula under point, or nil if none is shown.")

;; calccomp and calc-sel declare these with valueless defvars, which marks
;; them special only within their own files; redeclare them here so our
;; let-bindings and reads of them are dynamic too.
(defvar math-comp-pos)
(defvar math-comp-sel-tag)
(defvar calc-selection-cache-num)
(defvar calc-selection-cache-comp)
(defvar calc-selection-cache-offset)
(defvar calc-selection-true-num)

;; Flat-rendering positions of the matched tag, recorded by `maf-hl--flat-term'
;; and read by `maf-hl--find-bounds', which let-binds them around the walk.
(defvar maf-hl--flat-start)
(defvar maf-hl--flat-end)

(defun maf-hl--flat-term (c)
  "Walk composition C, resolving the tag at `math-comp-sel-cpos'.
Like `math-comp-sel-flat-term', but also records the matched tag's start and
end positions in the flat rendering into `maf-hl--flat-start' and
`maf-hl--flat-end', so locating its text needs no second render pass."
  (cond
   ((not (consp c))
    (setq math-comp-pos (+ math-comp-pos (length c))))
   ((memq (car c) '(set break)))
   ((eq (car c) 'horiz)
    (while (and (setq c (cdr c)) (< math-comp-sel-cpos 1000000))
      (maf-hl--flat-term (car c))))
   ((eq (car c) 'tag)
    (if (<= math-comp-pos math-comp-sel-cpos)
        (let ((start math-comp-pos))
          (maf-hl--flat-term (nth 2 c))
          ;; Point fell inside this tag and no inner tag claimed it first:
          ;; record it, and set cpos to the sentinel so enclosing tags and the
          ;; horiz loop stop looking.
          (when (> math-comp-pos math-comp-sel-cpos)
            (setq math-comp-sel-tag c
                  math-comp-sel-cpos 1000000
                  maf-hl--flat-start start
                  maf-hl--flat-end math-comp-pos)))
      (maf-hl--flat-term (nth 2 c))))
   (t
    (maf-hl--flat-term (nth 2 c)))))

(defun maf-hl--flat-to-pos (fpos toppt)
  "Convert flat-rendering position FPOS to a buffer position.
TOPPT is the buffer position of the start of the entry's first line. When a
long entry wraps, each continuation line's newline and indentation occupy
buffer positions but not flat positions, so walk line by line rather than
adding a single offset."
  (save-excursion
    (goto-char (+ toppt calc-selection-cache-offset))
    (while (> fpos (- (line-end-position) (point)))
      (setq fpos (- fpos (- (line-end-position) (point))))
      (forward-line 1)
      (back-to-indentation))
    (+ (point) fpos)))

(defun maf-hl--find-bounds ()
  "Return (START . END) buffer bounds of the sub-formula at point, or nil.
Mirrors `calc-find-selected-part', walking the composition prepared by
`calc-prepare-selection'. Only flat (single-height) renderings are handled;
multi-line compositions (matrices, Big language mode) return nil."
  (when (math-comp-is-flat calc-selection-cache-comp)
    (let ((line (line-beginning-position))
          (toppt nil)
          (lcount 0)
          (spaces 0))
      (save-excursion
        (calc-cursor-stack-index calc-selection-cache-num)
        (setq toppt (point))
        (while (< (point) line)
          (forward-line 1)
          (setq spaces (+ spaces (current-indentation))
                lcount (1+ lcount))))
      (when (and (>= (- (current-column) calc-selection-cache-offset) 0)
                 (> calc-selection-true-num 0))
        (let ((math-comp-sel-cpos (- (point) toppt calc-selection-cache-offset
                                     spaces lcount))
              (math-comp-sel-tag nil)
              (math-comp-pos 0)
              (maf-hl--flat-start nil)
              (maf-hl--flat-end nil))
          (maf-hl--flat-term calc-selection-cache-comp)
          (when maf-hl--flat-start
            (cons (maf-hl--flat-to-pos maf-hl--flat-start toppt)
                  (maf-hl--flat-to-pos maf-hl--flat-end toppt))))))))

(defun maf-hl--update ()
  "Move the highlight to the sub-formula under point, or hide it.
Runs on `post-command-hook'; errors are swallowed so a bad calc state can
never get the hook function disabled."
  (let ((bounds (ignore-errors
                  (let ((idx (calc-locate-cursor-element (point))))
                    (when (> idx 0)
                      (calc-prepare-selection idx)
                      (maf-hl--find-bounds))))))
    (cond
     (bounds
      (unless maf-hl--overlay
        (setq maf-hl--overlay (make-overlay 1 1))
        (overlay-put maf-hl--overlay 'face 'maf-hl))
      (move-overlay maf-hl--overlay (car bounds) (cdr bounds) (current-buffer)))
     (maf-hl--overlay
      (delete-overlay maf-hl--overlay)))))

;;;###autoload
(define-minor-mode maf-hl-mode
  "Highlight the sub-formula under point in a calc buffer.
As point moves over a stack entry, the innermost sub-formula containing
point is shown with the `maf-hl' face. Entries rendered across multiple
lines (matrices, Big language mode) are not highlighted."
  :lighter " hl"
  :group 'maf
  (if maf-hl-mode
      (progn
        (add-hook 'post-command-hook #'maf-hl--update nil t)
        (maf-hl--update))
    (remove-hook 'post-command-hook #'maf-hl--update t)
    (when maf-hl--overlay
      (delete-overlay maf-hl--overlay)
      (setq maf-hl--overlay nil))))

(provide 'maf-hl)
