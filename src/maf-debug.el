;; -*- lexical-binding: t; -*-
;;
;; maf-debug.el
;;
;; maf debug functions

(defmacro maf-debug-slowly (&rest body)
  "Run each form in BODY on a timer, spaced 0.3s apart.
Each form runs in the buffer that was current when this macro was called.
Form 1 runs at 0.3s, form 2 at 0.6s, form 3 at 0.9s, etc."
  (declare (indent 0))
  `(let ((--maf-buf-- (current-buffer)))
     ,@(cl-loop for form in body
                for i from 1
                collect `(run-at-time ,(* 0.3 i) nil
                                      (lambda (buf) (with-current-buffer buf ,form))
                                      --maf-buf--))))

(defun maf-debug--open-calc-right ()
  "Ensure calc is open in the right window, splitting if needed.
- One window: splits right, then shows calc in the new window.
- Right window already has calc: no-op.
- Right window exists with another buffer: replaces it with calc."
  (when (one-window-p)
    (split-window-right))
  (let ((right-win (next-window)))
    (unless (with-current-buffer (window-buffer right-win)
              (derived-mode-p 'calc-mode))
      (unless (get-buffer "*Calculator*")
        (save-window-excursion (calc)))
      (set-window-buffer right-win "*Calculator*"))))

(provide 'maf-debug)
