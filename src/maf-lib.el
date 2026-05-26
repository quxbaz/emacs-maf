;; -*- lexical-binding: t; -*-
;;
;; maf-lib.el
;;
;; maf library functions

(defun maf--find-calc-buffer ()
  "Find the calc buffer.
Prefers the current buffer if it is in calc-mode, then looks for
*Calculator* by name, then falls back to any live buffer in calc-mode."
  (cond
   ((derived-mode-p 'calc-mode) (current-buffer))
   ((get-buffer "*Calculator*"))
   (t (cl-find-if (lambda (buf)
                    (with-current-buffer buf (derived-mode-p 'calc-mode)))
                  (buffer-list)))))

(defmacro maf--with-calc-buffer (&rest body)
  "Evaluate BODY in the calc buffer."
  (declare (indent 0))
  `(with-current-buffer (maf--find-calc-buffer)
     ,@body))

(defun maf--at-home-p ()
  "Return t if point is past the last stack entry (at the . line or below)."
  (maf--with-calc-buffer
    (<= (calc-locate-cursor-element (point)) 0)))

(defun maf--at-line-prefix-p ()
  "Return t if point is in the line-number prefix (e.g. \"1: \") of a stack entry."
  (maf--with-calc-buffer
    (and (> (calc-locate-cursor-element (point)) 0)
         (not (eolp))
         (save-excursion
           (let ((col (current-column)))
             (beginning-of-line)
             (and (looking-at " *[0-9]+: +")
                  (< col (- (match-end 0) (point)))))))))

(defun maf--at-subexpr-p ()
  "Return t if point is on a sub-expression within an entry's formula text.
False when point is at EOL or in the line-prefix zone, even if there is a
sub-expression on the line; those positions route to equation/entry targets."
  (maf--with-calc-buffer
    (and (> (calc-locate-cursor-element (point)) 0)
         (not (eolp))
         (not (maf--at-line-prefix-p))
         (save-excursion
           (ignore-errors
             (calc-prepare-selection)
             (and (calc-find-selected-part) t))))))

(defun maf--at-equation-p ()
  "Return t if the stack entry under point is a relation (=, !=, <, <=, >, >=)."
  (maf--with-calc-buffer
    (let* ((idx (calc-locate-cursor-element (point)))
           (expr (and (> idx 0) (calc-top idx 'full))))
      (and (consp expr)
           (memq (car expr) '(calcFunc-eq calcFunc-neq
                              calcFunc-lt calcFunc-leq
                              calcFunc-gt calcFunc-geq))
           t))))

(defun maf--at-entry-p ()
  "Return t if point is on a stack entry line.
This is the catch-all when no more specific target (selection, subexpr,
equation) matches in the priority cascade."
  (maf--with-calc-buffer
    (> (calc-locate-cursor-element (point)) 0)))

(provide 'maf-lib)
