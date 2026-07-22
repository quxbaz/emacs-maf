;; -*- lexical-binding: t; -*-
;;
;; modules/maf-hl.el
;;
;; Sub-formula highlighting module. `maf-hl-mode' is a buffer-local
;; minor mode for calc buffers that highlights the innermost
;; sub-formula under point as the cursor moves — live feedback on what
;; a contextual command would operate on.
;;
;; The module toggle is `maf-use-hl-mode', which turns the
;; buffer-local mode on in every calc buffer and registers with the
;; module system as `maf-hl' (see `maf-modules'). M-x maf-hl-mode
;; still toggles the highlight in a single buffer, standalone.

(require 'calc)
(require 'calc-sel)   ; calc-prepare-selection
(require 'calc-yank)  ; calc-locate-cursor-element
(require 'maf-comp)   ; maf--comp-find-bounds
(require 'maf-lib)    ; maf--at-line-margin-p

;; Set by `calc-prepare-selection'; declared for the dynamic reads below.
(defvar calc-selection-cache-num)
(defvar calc-selection-cache-offset)

(defface maf-hl
  '((t :inherit highlight))
  "Face for the sub-formula under point in `maf-hl-mode'."
  :group 'maf)

(defvar-local maf-hl--overlay nil
  "Overlay marking the sub-formula under point, or nil if none is shown.")

(defun maf-hl--entry-bounds ()
  "Return (START . END) buffer bounds of the whole entry under point.
Uses the selection cache `maf-hl--update' prepared. Returns nil for a
multi-line entry (a matrix), which has no single flat range to mark, as
with the sub-formula highlight."
  (save-excursion
    (calc-cursor-stack-index calc-selection-cache-num)
    (let ((beg (+ (point) calc-selection-cache-offset))
          (below (save-excursion
                   (calc-cursor-stack-index (1- calc-selection-cache-num))
                   (point))))
      (goto-char beg)
      ;; Single-line only: the next entry down begins right after this
      ;; line's newline, one column past its end.
      (when (= below (1+ (line-end-position)))
        (cons beg (line-end-position))))))

(defun maf-hl--update ()
  "Move the highlight to the sub-formula under point, or hide it.
Runs on `post-command-hook'; errors are swallowed so a bad calc state can
never get the hook function disabled. While a region is active the
highlight steps aside — its overlay would fight the region's own — and
returns on the next command once the region is gone. At the line prefix
or EOL, where no sub-formula is under point, the whole entry is marked."
  (let ((bounds (unless (region-active-p)
                  (ignore-errors
                    (let ((idx (calc-locate-cursor-element (point))))
                      (when (> idx 0)
                        (calc-prepare-selection idx)
                        (or (maf--comp-find-bounds)
                            ;; Prefix/EOL: no sub-formula, so mark the
                            ;; whole entry — the entry target's subject.
                            (and (maf--at-line-margin-p)
                                 (maf-hl--entry-bounds)))))))))
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
point is shown with the `maf-hl' face. At the line prefix or end of line
— where no sub-formula sits under point — the whole entry is marked, the
subject the entry target would act on. A matrix or other multi-line
entry is not highlighted. Under the Big display language `maf-use-hl-mode'
disables this mode entirely, since a sub-formula there has no single
flat range to mark."
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

;;; The module

(defun maf-hl--turn-on ()
  "Enable `maf-hl-mode' in the current buffer if it is a calc buffer.
The per-buffer arm of `maf-use-hl-mode', run in every buffer as its
major mode settles; highlighting only makes sense in a calc buffer, and
only in a flat rendering — never under the Big display language."
  (when (and (derived-mode-p 'calc-mode)
             (not (eq calc-language 'big)))
    (maf-hl-mode 1)))

(defun maf-hl--sync-language (&rest _)
  "Track the display language: `maf-hl-mode' off under Big, on otherwise.
Advice on `calc-set-language' while `maf-use-hl-mode' is on. Highlighting
maps a sub-formula to one flat character range, which the Big language's
multi-line rendering has no equivalent for, so the mode steps aside in
Big mode and returns when the display goes back to normal."
  (let ((big (eq calc-language 'big)))
    (dolist (buf (buffer-list))
      (with-current-buffer buf
        (when (derived-mode-p 'calc-mode)
          (cond ((and big maf-hl-mode) (maf-hl-mode -1))
                ((and (not big) (not maf-hl-mode)) (maf-hl-mode 1))))))))

;;;###autoload
(define-globalized-minor-mode maf-use-hl-mode
  maf-hl-mode maf-hl--turn-on
  :group 'maf
  ;; React to display-language changes so the mode follows Big mode in
  ;; and out; advice lives only while the module is on.
  (if maf-use-hl-mode
      (advice-add 'calc-set-language :after #'maf-hl--sync-language)
    (advice-remove 'calc-set-language #'maf-hl--sync-language)))

;; Register with the module system when it is present; the mode above
;; works on its own without it.
(when (require 'maf-module nil t)
  (maf-register-module 'maf-hl #'maf-use-hl-mode
                       "Highlight the innermost sub-formula under point as the cursor moves."))

(provide 'maf-hl)
