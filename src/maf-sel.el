;; -*- lexical-binding: t; -*-
;;
;; maf-sel.el
;;
;; maf selection functions

(require 'maf-lib)

(defun maf--active-selection-p ()
  "Return t if any stack entry has an active selection.
Must be called with the calc buffer current."
  (and calc-use-selections
       ;; calc stack entries are (val disp sel); sel is non-nil when selected.
       (seq-some (lambda (elt) (nth 2 elt)) calc-stack)
       t))

(defun maf--at-selection-p ()
  "Return t if any stack entry has an active selection (selection mode on)."
  (maf--with-calc-buffer
    (maf--active-selection-p)))

(defun maf--active-selection-at-line-p ()
  "Return t if the stack entry at point has an active selection."
  (let ((m (calc-locate-cursor-element (point))))
    (and (nth 2 (nth m calc-stack)) t)))

(defun maf--first-active-entry-m ()
  "Return the POSITION of the first stack entry with an active selection
beginning from the top of the stack, or nil if there are no active selections."
  (cl-loop for i from 1 below (length calc-stack)
           when (nth 2 (nth i calc-stack))
           return i))

(defun maf--active-entry-m-dwim ()
  "Return stack POSITION of active selection at point, or top-most selection.

Returns the stack position (m) of the active selection at the current
line. If no selection exists at point, returns the position of the first
active selection from the top of the stack. Returns nil if no selections
are active."
  (if (maf--active-selection-at-line-p)
      (calc-locate-cursor-element (point))
    (maf--first-active-entry-m)))

(provide 'maf-sel)
