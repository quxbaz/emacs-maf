;; -*- lexical-binding: t; -*-
;;
;; maf-sel.el
;;
;; maf selection functions

(require 'maf-lib)

(defun maf--stack-selection-p ()
  "Return t if any stack entry has an active selection."
  (maf--with-calc-buffer
    (and calc-use-selections
         ;; stack entries are (formula lines selection); selection is non-nil when active.
         (seq-some (lambda (elt) (nth 2 elt)) calc-stack)
         t)))

(defun maf--selection-at-point-p ()
  "Return t if the stack entry at point has an active selection."
  (maf--with-calc-buffer
    (let ((m (calc-locate-cursor-element (point))))
      (and (> m 0) (calc-top m 'sel) t))))

(defun maf--topmost-selection-m ()
  "Return the stack position of the top-most entry with an active selection,
or nil if no entry has one."
  (maf--with-calc-buffer
    (cl-loop for i from 1 to (calc-stack-size)
             when (calc-top i 'sel)
             return i)))

(defun maf--effective-selection-m ()
  "Return the stack position of the selection to operate on.

Prefers the selection at the current line, falling back to the top-most
active selection. Returns nil if no selections are active."
  (maf--with-calc-buffer
    (let ((m (calc-locate-cursor-element (point))))
      (if (and (> m 0) (calc-top m 'sel))
          m
        (maf--topmost-selection-m)))))

(provide 'maf-sel)
