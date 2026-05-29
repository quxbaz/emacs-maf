;; -*- lexical-binding: t; -*-
;;
;; maf-step.el
;;
;; Step-through debugger: run a sequence of forms one at a time, rendering each
;; form and its captured output (return value, *Messages*, errors) into a
;; transcript buffer. See `maf--debug-step'.

(require 'cl-lib)

;; State is global (only one step session runs at a time) rather than closed
;; over, so maf--debug-step works at call sites without lexical-binding: t. The
;; *maf-step* buffer (`maf-step-mode') is the cockpit: all bindings live there,
;; and forms execute in the target window before control returns. Forms and
;; their captured output render into `maf--debug-step-buffer-name'.
(defvar maf--debug-step-buffer  nil)  ; the target buffer forms run in (e.g. *Calculator*)
(defvar maf--debug-step-win     nil)  ; window that buffer was in when stepping started
(defvar maf--debug-step-steps   nil)  ; list of thunks, one per form
(defvar maf--debug-step-forms   nil)  ; list of quoted forms (for display)
(defvar maf--debug-step-outputs nil)  ; list of captured output blocks
(defvar maf--debug-step-idx     0)    ; number of forms executed so far
(defvar maf--debug-step-total   0)
(defvar maf--debug-step-title   nil)  ; source file or buffer, shown as a title
(defvar maf--debug-step-errored nil)  ; sticky: t once any step has signaled an error

(defconst maf--debug-step-buffer-name "*maf-step*")

;; Use the standard overlay-arrow mechanism (as edebug/gud do) to mark the
;; current step: a fringe bitmap on graphical frames (no extra gutter column),
;; or the arrow string at line-start on a terminal.
(defvar maf--debug-step-arrow (make-marker)
  "Overlay-arrow marker for the last-executed step in the step buffer.")
(add-to-list 'overlay-arrow-variable-list 'maf--debug-step-arrow)
(put 'maf--debug-step-arrow 'overlay-arrow-string ">")

(defvar maf-step-mode-map
  (let ((map (make-sparse-keymap)))
    (define-key map (kbd "SPC") #'maf--debug-step-next)
    (define-key map (kbd "q") #'maf--debug-step-quit)
    map))

(define-derived-mode maf-step-mode emacs-lisp-mode "maf-step"
  "Major mode for the maf step-through transcript buffer.
The buffer is the session cockpit: SPC runs the next form (in the target
buffer, returning here afterward) and \\=`q' quits. Derived from
`emacs-lisp-mode' so the rendered forms are fontified."
  (setq buffer-read-only t))

(defun maf--debug-step-comment (text prefix)
  "Comment-prefix each line of TEXT with PREFIX (e.g. \";; \" or \";;! \")."
  (mapconcat (lambda (line) (concat prefix line))
             (split-string (string-trim-right text) "\n")
             "\n"))

(defun maf--debug-step-display ()
  "Show the step buffer in a window other than the run window; return it.
Replaces whatever is in that window (typically the left one, with calc on the
right)."
  (let* ((buf (get-buffer-create maf--debug-step-buffer-name))
         (win (or (get-buffer-window buf)
                  (seq-find (lambda (w) (not (eq w maf--debug-step-win)))
                            (window-list))
                  (split-window maf--debug-step-win nil 'left))))
    (with-current-buffer buf
      (unless (derived-mode-p 'maf-step-mode) (maf-step-mode)))
    (set-window-buffer win buf)
    win))

(defun maf--debug-step-render ()
  "Re-render all forms and their captured output into the step buffer.
The last-executed form (index `maf--debug-step-idx' - 1) gets the overlay-arrow
marker (fringe arrow on a GUI, `>' at line-start on a terminal)."
  (let ((buf     (get-buffer-create maf--debug-step-buffer-name))
        (forms   maf--debug-step-forms)
        (outputs maf--debug-step-outputs)
        (marked  (1- maf--debug-step-idx)))
    (with-current-buffer buf
      (let ((inhibit-read-only t)
            (mark-pos nil))
        (erase-buffer)
        (insert (format ";; maf-step: %s\n"
                        (if (and maf--debug-step-title
                                 (file-name-absolute-p maf--debug-step-title))
                            (file-name-nondirectory maf--debug-step-title)
                          maf--debug-step-title)))
        (insert (format ";; [%d/%d]%s%s\n\n"
                        maf--debug-step-idx maf--debug-step-total
                        (if (>= maf--debug-step-idx maf--debug-step-total) " DONE" "")
                        (if maf--debug-step-errored " ERROR" "")))
        (cl-loop for form in forms
                 for i from 0
                 do (when (= i marked) (setq mark-pos (point)))
                    (insert (pp-to-string form))
                    (let ((out (nth i outputs)))
                      (when (and out (> (length out) 0))
                        (insert out)))
                    (insert "\n"))
        ;; Drop the trailing blank line left by the last form's separator.
        (skip-chars-backward "\n")
        (delete-region (point) (point-max))
        (setq buffer-read-only t)
        ;; Place point on the last-executed form, or at the top before any
        ;; step has run (rather than leaving it at EOF after rendering).
        (let ((pos (or mark-pos (point-min)))
              (w   (get-buffer-window buf)))
          (set-marker maf--debug-step-arrow mark-pos buf)  ; nil clears the arrow
          (goto-char pos)
          (when w (set-window-point w pos)))))))

(defun maf--debug-step-next ()
  (interactive)
  (when (>= maf--debug-step-idx maf--debug-step-total)
    (user-error "maf-step: no more forms"))
  (setq current-prefix-arg nil)
  (let* ((i        maf--debug-step-idx)
         (msg-buf  (messages-buffer))
         (msg-mark (with-current-buffer msg-buf (copy-marker (point-max))))
         (result nil)
         (err nil))
    ;; Run the form in the *target buffer*, resolving its current window fresh
    ;; (selecting a window only makes its buffer current, so tracking by window
    ;; would run forms in whatever that window now shows — e.g. *maf-step*). If
    ;; the target is visible, select its window so point ops affect the display;
    ;; otherwise just make it current. inhibit-message keeps output out of the
    ;; echo area but still logs to *Messages*, which we diff below. Errors are
    ;; folded into the captured output rather than halting the session.
    (cl-flet ((run ()
                (deactivate-mark t)
                (condition-case e
                    (let ((inhibit-message t))
                      (setq result (funcall (nth i maf--debug-step-steps))))
                  (error (setq err e)))
                (deactivate-mark t)))
      (let ((win (get-buffer-window maf--debug-step-buffer)))
        (if (window-live-p win)
            (with-selected-window win (run))
          (with-current-buffer maf--debug-step-buffer (run)))))
    (when err (setq maf--debug-step-errored t))
    ;; Build this form's output block: the return value (or error) directly
    ;; under the form, then the *Messages* delta beneath that. Append it so the
    ;; transcript builds up across steps.
    (let* ((delta (with-current-buffer msg-buf
                    (buffer-substring-no-properties msg-mark (point-max))))
           (block (concat
                   (if err
                       (concat (maf--debug-step-comment
                                (format "error: %s" (error-message-string err))
                                ";;! ")
                               "\n")
                     (concat (maf--debug-step-comment
                              (format "=> %S" result) ";; ")
                             "\n"))
                   (when (> (length (string-trim delta)) 0)
                     (concat (maf--debug-step-comment delta ";; ") "\n")))))
      (setf (nth i maf--debug-step-outputs)
            (concat (or (nth i maf--debug-step-outputs) "") block)))
    (cl-incf maf--debug-step-idx)
    (maf--debug-step-render)))

(defun maf--debug-step-quit ()
  "Bury the step buffer and return to the original buffer.
`quit-window' restores the buffer the step window replaced, and selecting
that window returns point there."
  (interactive)
  (let ((win (get-buffer-window maf--debug-step-buffer-name)))
    (when win
      (quit-window nil win)
      (when (window-live-p win)
        (select-window win)))))

(defmacro maf--debug-step (&rest body)
  "Run each form in BODY step by step, capturing output into a step buffer.
Forms run in the window current when this macro is called (the target,
typically calc). Renders the forms into `maf--debug-step-buffer-name' in
another window and selects it (`maf-step-mode'): press SPC to run the next
form in the target buffer (returning here afterward), `q' to quit. Each form's
return value, *Messages* output, and any error are shown beneath it, building a
transcript. If already stepping, this abandons the current sequence."
  (declare (indent 0))
  ;; Resolve the source at expansion time. `load-file-name' works when the file
  ;; is loaded (e.g. f4). Under eval-buffer it is nil and the current buffer is
  ;; already *Calculator* (setup switched to it before we expand), so fall back
  ;; at runtime to whatever `maf--debug-setup-test' recorded beforehand.
  (let ((title (or load-file-name buffer-file-name)))
  `(progn
     ;; Prefer a target designated by `maf--debug-setup-test' (the calc buffer).
     ;; Fall back to the current buffer only if none was set, because under
     ;; eval-buffer (current-buffer) here is unreliable: each top-level form
     ;; runs in `save-selected-window', so setup's `select-window' is already
     ;; reverted by the time this runs.
     (unless (buffer-live-p maf--debug-step-buffer)
       (setq maf--debug-step-buffer (current-buffer)))
     (setq maf--debug-step-win     (selected-window))
     (setq maf--debug-step-steps   (list ,@(mapcar (lambda (f) `(lambda () ,f)) body)))
     (setq maf--debug-step-forms   (list ,@(mapcar (lambda (f) `',f) body)))
     (setq maf--debug-step-outputs (make-list ,(length body) nil))
     (setq maf--debug-step-idx     0)
     (setq maf--debug-step-total   ,(length body))
     (setq maf--debug-step-errored nil)
     (setq maf--debug-step-title   (or ,title maf--debug-step-title))
     ;; Select the step window so its `maf-step-mode' keymap drives the session.
     (let ((win (maf--debug-step-display)))
       (maf--debug-step-render)
       (select-window win))
     nil)))

(provide 'maf-step)
