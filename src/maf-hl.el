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
(require 'calc-sel)   ; calc-prepare-selection
(require 'calc-yank)  ; calc-locate-cursor-element
(require 'maf-comp)   ; maf--comp-find-bounds

(defface maf-hl
  '((t :inherit highlight))
  "Face for the sub-formula under point in `maf-hl-mode'."
  :group 'maf)

(defvar-local maf-hl--overlay nil
  "Overlay marking the sub-formula under point, or nil if none is shown.")

(defun maf-hl--update ()
  "Move the highlight to the sub-formula under point, or hide it.
Runs on `post-command-hook'; errors are swallowed so a bad calc state can
never get the hook function disabled."
  (let ((bounds (ignore-errors
                  (let ((idx (calc-locate-cursor-element (point))))
                    (when (> idx 0)
                      (calc-prepare-selection idx)
                      (maf--comp-find-bounds))))))
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
