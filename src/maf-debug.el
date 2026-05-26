;; -*- lexical-binding: t; -*-
;;
;; maf-debug.el
;;
;; maf debug functions

(defmacro maf-debug-slowly (delay &rest body)
  "Run each form in BODY on a timer, spaced DELAY seconds apart.
Each form runs in the buffer that was current when this macro was called.
Form 1 runs at DELAY, form 2 at 2*DELAY, form 3 at 3*DELAY, etc."
  (declare (indent 1))
  `(let ((--maf-win-- (selected-window)))
     ,@(cl-loop for form in body
                for i from 1
                collect `(run-at-time ,(* delay i) nil
                                      (lambda (win) (with-selected-window win ,form))
                                      --maf-win--))))

(defun maf-debug-use-calc-buffer ()
  "Select the calc window, moving point there permanently."
  (select-window (get-buffer-window (maf--find-calc-buffer))))

(defun maf-debug-open-calc-right ()
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
