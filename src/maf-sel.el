;; -*- lexical-binding: t; -*-
;;
;; maf-sel.el
;;
;; maf selection functions

(require 'maf-lib)

(defun maf--any-selection-p ()
  "Return t if any stack entry has an active selection."
  (maf--with-calc-buffer
    (and calc-use-selections
         ;; calc stack entries are (val disp sel); sel is non-nil when selected.
         (seq-some (lambda (elt) (nth 2 elt)) calc-stack)
         t)))

(defun maf--selection-on-line-p ()
  "Return t if the stack entry at point has an active selection."
  (maf--with-calc-buffer
    (let ((m (calc-locate-cursor-element (point))))
      (and (nth 2 (nth m calc-stack)) t))))

(defun maf--topmost-selection-pos ()
  "Return the stack position of the top-most entry with an active selection,
or nil if no entry has one."
  (maf--with-calc-buffer
    (cl-loop for i from 1 below (length calc-stack)
             when (nth 2 (nth i calc-stack))
             return i)))

(defun maf--selection-pos-dwim ()
  "Return the stack position of the selection to operate on.

Prefers the selection at the current line, falling back to the top-most
active selection. Returns nil if no selections are active."
  (maf--with-calc-buffer
    (if (maf--selection-on-line-p)
        (calc-locate-cursor-element (point))
      (maf--topmost-selection-pos))))

(provide 'maf-sel)
