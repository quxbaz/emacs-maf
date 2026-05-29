;; -*- lexical-binding: t; -*-
;;
;; maf-step.el
;;
;; Step-through debugger for maf/calc. `maf-step' runs a sequence of forms one
;; at a time against a freshly-created calc buffer, rendering each form and its
;; captured output (return value, *Messages*, errors) into a transcript buffer
;; (`maf-step-mode'). Self-contained: it creates and resets calc itself, with no
;; dependency on external setup.

(require 'cl-lib)

;; State is global (only one step session runs at a time) rather than closed
;; over, so `maf-step' works at call sites without lexical-binding: t.
(defvar maf--step-buffer  nil)  ; the calc buffer forms run in (created fresh per session)
(defvar maf--step-steps   nil)  ; list of thunks, one per form
(defvar maf--step-forms   nil)  ; list of quoted forms (for display)
(defvar maf--step-outputs nil)  ; list of captured output blocks
(defvar maf--step-idx     0)    ; number of forms executed so far
(defvar maf--step-total   0)
(defvar maf--step-title   nil)  ; source file/buffer, shown as a title and used by `q'
(defvar maf--step-errored nil)  ; sticky: t once any step has signaled an error

(defconst maf--step-buffer-name "*maf-step*")

;; Standard overlay-arrow (as edebug/gud do): fringe bitmap on a GUI (no gutter
;; column), or the arrow string at line-start on a terminal.
(defvar maf--step-arrow (make-marker)
  "Overlay-arrow marker for the last-executed step.")
(add-to-list 'overlay-arrow-variable-list 'maf--step-arrow)
(put 'maf--step-arrow 'overlay-arrow-string ">")

(defvar maf-step-mode-map
  (let ((map (make-sparse-keymap)))
    (define-key map (kbd "SPC") #'maf-step-next)
    (define-key map (kbd "r") #'maf-step-restart)
    (define-key map (kbd "q") #'maf-step-quit)
    map))

(define-derived-mode maf-step-mode emacs-lisp-mode "maf-step"
  "Major mode for the maf step-through transcript buffer.
The buffer is the session cockpit: SPC runs the next form (in the calc buffer,
returning here afterward), \\=`r' restarts with a fresh calc, and \\=`q' quits.
Derived from `emacs-lisp-mode' so the rendered forms are fontified."
  (setq buffer-read-only t))

;; ---------------------------------------------------------------------------
;; Calc setup (self-contained — no external setup function needed)
;; ---------------------------------------------------------------------------

(defun maf--step-kill-calc ()
  "Kill every calc buffer (stack and trail) for a totally clean slate."
  (dolist (b (buffer-list))
    (when (buffer-live-p b)
      (when (with-current-buffer b
              (or (derived-mode-p 'calc-mode 'calc-trail-mode)
                  (member (buffer-name b) '("*Calculator*" "*Calc Trail*"))))
        (let ((kill-buffer-query-functions nil))
          (kill-buffer b))))))

(defun maf--step-fresh-calc ()
  "Kill all calc buffers and create a fresh *Calculator*; return that buffer."
  (maf--step-kill-calc)
  (save-window-excursion (calc))
  (get-buffer "*Calculator*"))

(defun maf--step-setup-windows ()
  "Lay out the cockpit in the current frame: `*maf-step*' left, calc right.
Selects the `*maf-step*' window."
  (let ((stepbuf (get-buffer-create maf--step-buffer-name)))
    (with-current-buffer stepbuf
      (unless (derived-mode-p 'maf-step-mode) (maf-step-mode)))
    (delete-other-windows)
    (switch-to-buffer stepbuf)
    (set-window-buffer (split-window-right) maf--step-buffer)
    (select-window (get-buffer-window stepbuf))))

(defun maf--step-begin ()
  "Start or restart a session: fresh calc, reset counters, lay out, render.
Reuses the already-captured `maf--step-steps' / `maf--step-forms' /
`maf--step-total', so it serves both initial run and `maf-step-restart'."
  (setq maf--step-buffer  (maf--step-fresh-calc)
        maf--step-idx     0
        maf--step-errored nil
        maf--step-outputs (make-list maf--step-total nil))
  (maf--step-setup-windows)
  (maf--step-render))

;; ---------------------------------------------------------------------------
;; Rendering
;; ---------------------------------------------------------------------------

(defun maf--step-comment (text prefix)
  "Comment-prefix each line of TEXT with PREFIX (e.g. \";; \" or \";;! \")."
  (mapconcat (lambda (line) (concat prefix line))
             (split-string (string-trim-right text) "\n")
             "\n"))

(defun maf--step-render ()
  "Re-render the title, status header, forms, and captured output.
The last-executed form gets the overlay-arrow marker; before any step has run,
point sits at the top."
  (let ((buf     (get-buffer-create maf--step-buffer-name))
        (forms   maf--step-forms)
        (outputs maf--step-outputs)
        (marked  (1- maf--step-idx)))
    (with-current-buffer buf
      (let ((inhibit-read-only t)
            (mark-pos nil))
        (erase-buffer)
        (insert (format ";; maf-step: %s\n"
                        (if (and maf--step-title
                                 (file-name-absolute-p maf--step-title))
                            (file-name-nondirectory maf--step-title)
                          maf--step-title)))
        (insert (format ";; [%d/%d]%s%s\n\n"
                        maf--step-idx maf--step-total
                        (if (>= maf--step-idx maf--step-total) " DONE" "")
                        (if maf--step-errored " ERROR" "")))
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
        (let ((pos (or mark-pos (point-min)))
              (w   (get-buffer-window buf)))
          (set-marker maf--step-arrow mark-pos buf)  ; nil clears the arrow
          (goto-char pos)
          (when w (set-window-point w pos)))))))

;; ---------------------------------------------------------------------------
;; Commands
;; ---------------------------------------------------------------------------

(defun maf-step-next ()
  "Run the next form in the calc buffer and render its output here."
  (interactive)
  (when (>= maf--step-idx maf--step-total)
    (user-error "maf-step: no more forms"))
  (setq current-prefix-arg nil)
  (let* ((i        maf--step-idx)
         (msg-buf  (messages-buffer))
         (msg-mark (with-current-buffer msg-buf (copy-marker (point-max))))
         (result nil)
         (err nil))
    ;; Run in the calc buffer (`maf--step-buffer'), selecting its window when
    ;; visible so point ops affect the display. inhibit-message keeps output
    ;; out of the echo area but still logs to *Messages*, which we diff below.
    ;; Errors are folded into the captured output rather than halting.
    (cl-flet ((run ()
                (deactivate-mark t)
                (condition-case e
                    (let ((inhibit-message t))
                      (setq result (funcall (nth i maf--step-steps))))
                  (error (setq err e)))
                (deactivate-mark t)))
      (let ((win (get-buffer-window maf--step-buffer)))
        (if (window-live-p win)
            (with-selected-window win (run))
          (with-current-buffer maf--step-buffer (run)))))
    (when err (setq maf--step-errored t))
    ;; Output block: the return value (or error) directly under the form, then
    ;; the *Messages* delta beneath. Append so the transcript builds up.
    (let* ((delta (with-current-buffer msg-buf
                    (buffer-substring-no-properties msg-mark (point-max))))
           (block (concat
                   (if err
                       (concat (maf--step-comment
                                (format "error: %s" (error-message-string err))
                                ";;! ")
                               "\n")
                     (concat (maf--step-comment (format "=> %S" result) ";; ")
                             "\n"))
                   (when (> (length (string-trim delta)) 0)
                     (concat (maf--step-comment delta ";; ") "\n")))))
      (setf (nth i maf--step-outputs)
            (concat (or (nth i maf--step-outputs) "") block)))
    (cl-incf maf--step-idx)
    (maf--step-render)))

(defun maf-step-restart ()
  "Restart the session from the top with a fresh calc buffer.
Replays the captured forms in memory — no file reload, no dependency on the
source file still existing or being unedited."
  (interactive)
  (maf--step-begin))

(defun maf-step-quit ()
  "Quit the step buffer and return to the source that invoked it.
Always shows the source (the file/buffer recorded in `maf--step-title') in the
step window and selects it — unlike `quit-window', which would restore whatever
that window happened to display before (e.g. *Messages*)."
  (interactive)
  (let ((win (get-buffer-window maf--step-buffer-name))
        (src (cond
              ((not (stringp maf--step-title)) nil)
              ((find-buffer-visiting maf--step-title))
              ((get-buffer maf--step-title))
              ((file-exists-p maf--step-title)
               (find-file-noselect maf--step-title)))))
    (when (get-buffer maf--step-buffer-name)
      (bury-buffer (get-buffer maf--step-buffer-name)))
    (when win
      (cond
       ((buffer-live-p src)
        (set-window-buffer win src)
        (select-window win))
       (t
        (quit-window nil win)
        (when (window-live-p win) (select-window win)))))))

;; ---------------------------------------------------------------------------
;; Entry macro
;; ---------------------------------------------------------------------------

(defmacro maf-step (&rest body)
  "Run each form in BODY step by step against a fresh calc buffer.
Kills any existing calc buffers and creates a clean *Calculator*, lays out the
cockpit (`*maf-step*' left, calc right), and enters `maf-step-mode': SPC runs
the next form in calc (returning here), `r' restarts, `q' quits. Each form's
return value, *Messages* output, and any error render beneath it."
  (declare (indent 0))
  ;; Resolve the source label at expansion time (the current buffer is still
  ;; the source then). `load-file-name' covers `load'; `buffer-file-name'
  ;; covers eval-buffer/eval-region from the file's buffer.
  (let ((title (or load-file-name buffer-file-name)))
    `(progn
       (setq maf--step-steps (list ,@(mapcar (lambda (f) `(lambda () ,f)) body))
             maf--step-forms (list ,@(mapcar (lambda (f) `',f) body))
             maf--step-total ,(length body)
             maf--step-title (or ,title (buffer-name)))
       (maf--step-begin)
       nil)))

(provide 'maf-step)
