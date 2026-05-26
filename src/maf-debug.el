;; -*- lexical-binding: t; -*-
;;
;; maf-debug.el
;;
;; maf debug functions

(defun maf--debug-setup-test ()
  "Prepare the frame for a human test.
Opens calc in the right window if needed, focuses it, and resets the stack."
  (maf--debug-open-calc-right)
  (maf--debug-use-calc-buffer)
  (calc-reset 0))

(defmacro maf--debug-slowly (delay &rest body)
  "Run each form in BODY on a timer, spaced DELAY seconds apart.
Each form runs in the buffer that was current when this macro was called.
Form 1 runs at DELAY, form 2 at 2*DELAY, form 3 at 3*DELAY, etc."
  (declare (indent 1))
  ;; Capture the window, not just the buffer. Point is per-window in Emacs,
  ;; so operations like goto-char and calc-select-here must run with the
  ;; correct window selected or they read/write the wrong point.
  ;;
  ;; The window value is passed via run-at-time's extra-args rather than
  ;; closed over, so this works regardless of whether the call site uses
  ;; lexical or dynamic binding.
  `(let ((--maf-win-- (selected-window)))
     ,@(cl-loop for form in body
                for i from 1
                collect `(run-at-time ,(* delay i) nil
                                      (lambda (win)
                                        ;; Clear eval-command residue: prefix arg
                                        ;; and active mark (e.g. from C-u C-c C-c)
                                        ;; so they don't affect interactive calls
                                        ;; inside the body.
                                        (setq current-prefix-arg nil)
                                        (with-selected-window win
                                          (deactivate-mark t)
                                          ,form
                                          (deactivate-mark t)))
                                      --maf-win--))
     nil))

(defmacro maf--debug-slowly-each (delay after &rest body)
  "Like `maf--debug-slowly', but run AFTER immediately after each form in BODY.
AFTER runs in the same window/timer context as the form it follows, so it
can inspect state (e.g. point, calc stack) as left by that form."
  (declare (indent 2))
  `(let ((--maf-win-- (selected-window)))
     ,@(cl-loop for form in body
                for i from 1
                collect `(run-at-time ,(* delay i) nil
                                      (lambda (win)
                                        (setq current-prefix-arg nil)
                                        (with-selected-window win
                                          (deactivate-mark t)
                                          ,form
                                          (princ "\n")
                                          (prin1 ',form)
                                          ,after
                                          (deactivate-mark t)))
                                      --maf-win--))
     nil))

(defun maf--debug-use-calc-buffer ()
  "Select the calc window, moving point there permanently."
  (select-window (get-buffer-window (maf--find-calc-buffer))))

(defun maf--debug-open-calc-right ()
  "Ensure calc is open in the right window, splitting if needed.
- One window: splits right, then shows calc in the new window.
- Right window already has calc: no-op.
- Right window exists with another buffer: replaces it with calc."
  (when (one-window-p)
    (split-window-right))
  (let ((right-win (next-window)))
    (unless (with-current-buffer (window-buffer right-win)
              (derived-mode-p 'calc-mode))
      ;; Start calc without disturbing the window layout, then place the
      ;; resulting buffer in right-win explicitly. set-window-buffer replaces
      ;; whatever is there rather than splitting beneath it.
      (unless (get-buffer "*Calculator*")
        (save-window-excursion (calc)))
      (set-window-buffer right-win "*Calculator*"))))

;; TEMP: Convenient way to run a specific test from anywhere.
(let ((test "human-test-mult-at-selection-keep.el")
      (dir  (expand-file-name "human-tests/" (file-name-directory (locate-library "maf")))))
  (global-set-key (kbd "<f4>") (lambda ()
                                 (interactive)
                                 (load-file (expand-file-name test dir))))
  (global-set-key (kbd "<S-f4>") (lambda ()
                                   (interactive)
                                   (find-file (expand-file-name test dir)))))

(provide 'maf-debug)
