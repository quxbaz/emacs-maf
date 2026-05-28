;; -*- lexical-binding: t; -*-
;;
;; maf-debug.el
;;
;; maf debug functions

(require 'cl-lib)

(defun maf--debug-setup-test ()
  "Prepare the frame for a human test.
Opens calc in the right window if needed, focuses it, and resets the stack."
  (maf--debug-open-calc-right)
  (maf--debug-use-calc-buffer)
  (calc-reset 0))

(defmacro maf--debug-slowly (&rest args)
  "Run each form in BODY on a timer, spaced DELAY seconds apart.
Optional :delay N at the start sets the interval (default 0.5).
Each form runs in the buffer that was current when this macro was called.
Form 1 runs at DELAY, form 2 at 2*DELAY, form 3 at 3*DELAY, etc."
  (declare (indent defun))
  (let* ((delay (if (eq (car args) :delay) (cadr args) 0.3))
         (body  (if (eq (car args) :delay) (cddr args) args)))
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
     nil)))

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

;; ---------------------------------------------------------------------------
;; Step-through debugger
;; ---------------------------------------------------------------------------

;; All state is stored in buffer-local vars (in the calc/run buffer) rather
;; than a closure, so maf--debug-step works at call sites without
;; lexical-binding: t. The forms and their captured output are rendered into a
;; separate display buffer (`maf--debug-step-buffer-name').
(defvar-local maf--debug-step-win     nil)  ; window the forms run in (calc)
(defvar-local maf--debug-step-steps   nil)  ; list of thunks, one per form
(defvar-local maf--debug-step-forms   nil)  ; list of quoted forms (for display)
(defvar-local maf--debug-step-outputs nil)  ; list of captured output blocks
(defvar-local maf--debug-step-idx     0)    ; number of forms executed so far
(defvar-local maf--debug-step-total   0)

(defconst maf--debug-step-buffer-name "*maf-step*")

(defvar maf-debug-step-mode-map
  (let ((map (make-sparse-keymap)))
    (define-key map (kbd ".") #'maf--debug-step-next)
    (define-key map (kbd "q") #'maf--debug-step-quit)
    map))

(define-minor-mode maf-debug-step-mode
  "Step through debug forms one at a time; \\=`.' advances, \\=`q' quits."
  :lighter " [step]"
  :keymap maf-debug-step-mode-map
  (if maf-debug-step-mode
      (push (cons 'maf-debug-step-mode maf-debug-step-mode-map)
            minor-mode-overriding-map-alist)
    (setq minor-mode-overriding-map-alist
          (assq-delete-all 'maf-debug-step-mode minor-mode-overriding-map-alist))))

(defun maf--debug-step-comment (text prefix)
  "Comment-prefix each line of TEXT with PREFIX (e.g. \";; \" or \";;! \")."
  (mapconcat (lambda (line) (concat prefix line))
             (split-string (string-trim-right text) "\n")
             "\n"))

(defun maf--debug-step-display ()
  "Show the step buffer in a window other than the run window; return it.
Replaces whatever is in that window (typically the left one, with calc on the
right). Sets a left margin so the `>' current-step marker has somewhere to go."
  (let* ((buf (get-buffer-create maf--debug-step-buffer-name))
         (win (or (get-buffer-window buf)
                  (seq-find (lambda (w) (not (eq w maf--debug-step-win)))
                            (window-list))
                  (split-window maf--debug-step-win nil 'left))))
    (with-current-buffer buf
      (unless (derived-mode-p 'emacs-lisp-mode) (emacs-lisp-mode))
      (setq-local left-margin-width 2))
    (set-window-buffer win buf)
    (set-window-margins win 2 0)
    win))

(defun maf--debug-step-render ()
  "Re-render all forms and their captured output into the step buffer.
The last-executed form (index `maf--debug-step-idx' - 1) gets a `>' marker in
the left margin."
  (let ((buf     (get-buffer-create maf--debug-step-buffer-name))
        (forms   maf--debug-step-forms)
        (outputs maf--debug-step-outputs)
        (marked  (1- maf--debug-step-idx)))
    (with-current-buffer buf
      (let ((inhibit-read-only t)
            (mark-pos nil))
        (erase-buffer)
        (remove-overlays)
        (cl-loop for form in forms
                 for i from 0
                 do (when (= i marked) (setq mark-pos (point)))
                    (insert (pp-to-string form))
                    (let ((out (nth i outputs)))
                      (when (and out (> (length out) 0))
                        (insert out)))
                    (insert "\n"))
        (setq buffer-read-only t)
        (when mark-pos
          (let ((ov (make-overlay mark-pos mark-pos)))
            (overlay-put ov 'before-string
                         (propertize " " 'display
                                     `((margin left-margin)
                                       ,(propertize ">" 'face 'font-lock-warning-face)))))
          (let ((w (get-buffer-window buf)))
            (when w (set-window-point w mark-pos))))))))

(defun maf--debug-step-next ()
  (interactive)
  (setq current-prefix-arg nil)
  (let* ((i        maf--debug-step-idx)
         (msg-buf  (messages-buffer))
         (msg-mark (with-current-buffer msg-buf (copy-marker (point-max))))
         (err nil))
    ;; Run the form in the calc window. inhibit-message keeps it out of the
    ;; echo area but still logs to *Messages*, which we diff below. Errors are
    ;; folded into the captured output rather than halting the session.
    (with-selected-window maf--debug-step-win
      (deactivate-mark t)
      (condition-case e
          (let ((inhibit-message t))
            (funcall (nth i maf--debug-step-steps)))
        (error (setq err e)))
      (deactivate-mark t))
    ;; Capture the *Messages* delta plus any error, comment-prefixed, and
    ;; append it under this form (the transcript builds up across steps).
    (let* ((delta (with-current-buffer msg-buf
                    (buffer-substring-no-properties msg-mark (point-max))))
           (block (concat
                   (when (> (length (string-trim delta)) 0)
                     (concat (maf--debug-step-comment delta ";; ") "\n"))
                   (when err
                     (concat (maf--debug-step-comment
                              (format "error: %s" (error-message-string err))
                              ";;! ")
                             "\n")))))
      (setf (nth i maf--debug-step-outputs)
            (concat (or (nth i maf--debug-step-outputs) "") block)))
    (cl-incf maf--debug-step-idx)
    (maf--debug-step-render)
    (when (>= maf--debug-step-idx maf--debug-step-total)
      (maf-debug-step-mode -1))))

(defun maf--debug-step-quit ()
  (interactive)
  (maf-debug-step-mode -1))

(defmacro maf--debug-step (&rest body)
  "Run each form in BODY step by step, capturing output into a step buffer.
Forms run in the window current when this macro is called (typically calc).
Renders the forms into `maf--debug-step-buffer-name' in another window, then
enables `maf-debug-step-mode': press `.' to run the next form, `q' to quit.
Each form's *Messages* output (and any error) is shown beneath it, building a
transcript. If already stepping, this abandons the current sequence."
  (declare (indent 0))
  `(let ((--maf-win-- (selected-window))
         (--steps--   (list ,@(mapcar (lambda (f) `(lambda () ,f)) body)))
         (--forms--   (list ,@(mapcar (lambda (f) `',f) body)))
         (--total--   ,(length body)))
     (with-selected-window --maf-win--
       (setq maf--debug-step-win     --maf-win--)
       (setq maf--debug-step-steps   --steps--)
       (setq maf--debug-step-forms   --forms--)
       (setq maf--debug-step-outputs (make-list --total-- nil))
       (setq maf--debug-step-idx     0)
       (setq maf--debug-step-total   --total--)
       (maf--debug-step-display)
       (maf--debug-step-render)
       (maf-debug-step-mode 1))
     nil))

(provide 'maf-debug)
