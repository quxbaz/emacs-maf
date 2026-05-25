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

(defun maf--at-selection-p ()
  "Return t if there is an active calc selection at point."
  nil) ;; TODO

(defun maf--at-home-p ()
  "Return t if point is past the last stack entry (at the . line or below)."
  (maf--with-calc-buffer
    (<= (calc-locate-cursor-element (point)) 0)))

(defun maf--at-subexpr-p ()
  "Return t if point is inside a stack entry (implicit selection)."
  nil) ;; TODO

(defun maf--at-equation-p ()
  "Return t if point is on a stack entry that is a relation (=, !=, <, <=, >, >=)."
  nil) ;; TODO

(defun maf--at-entry-p ()
  "Return t if point selects a whole stack entry (EOL, line-prefix zone, or line mode forced)."
  nil) ;; TODO

(provide 'maf-lib)
