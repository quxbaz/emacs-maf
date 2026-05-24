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

(defun maf--at-home-p ()
  "Return t if point is past the last stack entry (at the . line or below)."
  (with-current-buffer (maf--find-calc-buffer)
    (<= (calc-locate-cursor-element (point)) 0)))

(provide 'maf-lib)
