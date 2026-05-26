;; -*- lexical-binding: t; -*-
;;
;; maf-sel.el
;;
;; maf selection functions

(require 'maf-lib)

(defun maf--sel-any-p ()
  "Return t if any stack entry has an active selection."
  (maf--with-calc-buffer
    (and calc-use-selections
         ;; stack entries are (formula lines selection); selection is non-nil when active.
         (seq-some (lambda (elt) (nth 2 elt)) calc-stack)
         t)))

(defun maf--sel-at-point-p ()
  "Return t if the stack entry at point has an active selection."
  (maf--with-calc-buffer
    (let ((m (calc-locate-cursor-element (point))))
      (and (> m 0) (calc-top m 'sel) t))))

(defun maf--sel-topmost-m ()
  "Return stack position of the top-most selected entry, or nil if none."
  (maf--with-calc-buffer
    ;; Walk the cons cells once (O(n)) rather than using calc-top which re-indexes
    ;; from the head each iteration (O(n^2)). nthcdr skips the sentinel and any
    ;; entries hidden by calc-stack-top truncation, so i=1 lands on the first
    ;; visible entry — matching calc-top's notion of position M.
    (cl-loop for elt in (nthcdr calc-stack-top calc-stack)
             for i from 1
             when (nth 2 elt)
             return i)))

(defun maf--sel-effective-m ()
  "Return the stack position of the selection to operate on.

Prefers the selection at the entry under point, falling back to the top-most
active selection. Returns nil if no selections are active."
  (maf--with-calc-buffer
    (let ((m (calc-locate-cursor-element (point))))
      (if (and (> m 0) (calc-top m 'sel))
          m
        (maf--sel-topmost-m)))))

(provide 'maf-sel)
