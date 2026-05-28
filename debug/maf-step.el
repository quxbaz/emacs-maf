;; -*- lexical-binding: t; -*-
;;
;; maf-step.el
;;
;; Step-through debugger: run a sequence of forms one at a time, rendering each
;; form and its captured output (return value, *Messages*, errors) into a
;; transcript buffer. See `maf--debug-step'.

(require 'cl-lib)

;; State is global (only one step session runs at a time) rather than closed
;; over, so maf--debug-step works at call sites without lexical-binding: t, and
;; so the minor mode can be enabled in both the run buffer and the step buffer
;; with shared state. The forms and their captured output are rendered into a
;; separate display buffer (`maf--debug-step-buffer-name').
(defvar maf--debug-step-win     nil)  ; window the forms run in (calc)
(defvar maf--debug-step-steps   nil)  ; list of thunks, one per form
(defvar maf--debug-step-forms   nil)  ; list of quoted forms (for display)
(defvar maf--debug-step-outputs nil)  ; list of captured output blocks
(defvar maf--debug-step-idx     0)    ; number of forms executed so far
(defvar maf--debug-step-total   0)
(defvar maf--debug-step-title   nil)  ; source file or buffer, shown as a title

(defconst maf--debug-step-buffer-name "*maf-step*")

;; Use the standard overlay-arrow mechanism (as edebug/gud do) to mark the
;; current step: a fringe bitmap on graphical frames (no extra gutter column),
;; or the arrow string at line-start on a terminal.
(defvar maf--debug-step-arrow (make-marker)
  "Overlay-arrow marker for the last-executed step in the step buffer.")
(add-to-list 'overlay-arrow-variable-list 'maf--debug-step-arrow)
(put 'maf--debug-step-arrow 'overlay-arrow-string ">")

(defvar maf-debug-step-mode-map
  (let ((map (make-sparse-keymap)))
    (define-key map (kbd ".") #'maf--debug-step-next)
    (define-key map (kbd "q") #'maf--debug-step-quit)
    map))

(define-minor-mode maf-debug-step-mode
  "Step through debug forms one at a time; \\=`.' advances, \\=`q' quits.
Enabled in both the run buffer (calc) and the step buffer so the keys work
from either; `minor-mode-overriding-map-alist' makes them beat other minor
modes (e.g. calc's own SPC/. bindings)."
  :lighter " [step]"
  :keymap maf-debug-step-mode-map
  (setq minor-mode-overriding-map-alist
        (assq-delete-all 'maf-debug-step-mode minor-mode-overriding-map-alist))
  (when maf-debug-step-mode
    (push (cons 'maf-debug-step-mode maf-debug-step-mode-map)
          minor-mode-overriding-map-alist)))

(defun maf--debug-step-set-mode (on)
  "Enable (ON non-nil) or disable `maf-debug-step-mode' in both the run buffer
and the step buffer, so `.'/`q' work from either."
  (dolist (buf (list (and (window-live-p maf--debug-step-win)
                          (window-buffer maf--debug-step-win))
                     (get-buffer maf--debug-step-buffer-name)))
    (when (buffer-live-p buf)
      (with-current-buffer buf
        (maf-debug-step-mode (if on 1 -1))))))

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
      (unless (derived-mode-p 'emacs-lisp-mode) (emacs-lisp-mode)))
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
        (insert (format ";;maf-step: %s\n\n"
                        (if (and maf--debug-step-title
                                 (file-name-absolute-p maf--debug-step-title))
                            (abbreviate-file-name maf--debug-step-title)
                          maf--debug-step-title)))
        (cl-loop for form in forms
                 for i from 0
                 do (when (= i marked) (setq mark-pos (point)))
                    (insert (pp-to-string form))
                    (let ((out (nth i outputs)))
                      (when (and out (> (length out) 0))
                        (insert out)))
                    (insert "\n"))
        (setq buffer-read-only t)
        (if mark-pos
            (progn
              (set-marker maf--debug-step-arrow mark-pos buf)
              (let ((w (get-buffer-window buf)))
                (when w (set-window-point w mark-pos))))
          (set-marker maf--debug-step-arrow nil))))))

(defun maf--debug-step-next ()
  (interactive)
  (setq current-prefix-arg nil)
  (let* ((i        maf--debug-step-idx)
         (msg-buf  (messages-buffer))
         (msg-mark (with-current-buffer msg-buf (copy-marker (point-max))))
         (result nil)
         (err nil))
    ;; Run the form in the calc window. inhibit-message keeps it out of the
    ;; echo area but still logs to *Messages*, which we diff below. Errors are
    ;; folded into the captured output rather than halting the session.
    (with-selected-window maf--debug-step-win
      (deactivate-mark t)
      (condition-case e
          (let ((inhibit-message t))
            (setq result (funcall (nth i maf--debug-step-steps))))
        (error (setq err e)))
      (deactivate-mark t))
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
    (maf--debug-step-render)
    (when (>= maf--debug-step-idx maf--debug-step-total)
      (maf--debug-step-set-mode nil))))

(defun maf--debug-step-quit ()
  (interactive)
  (maf--debug-step-set-mode nil))

(defmacro maf--debug-step (&rest body)
  "Run each form in BODY step by step, capturing output into a step buffer.
Forms run in the window current when this macro is called (typically calc).
Renders the forms into `maf--debug-step-buffer-name' in another window, then
enables `maf-debug-step-mode': press `.' to run the next form, `q' to quit.
Each form's return value, *Messages* output, and any error are shown beneath
it, building a transcript. If already stepping, this abandons the current
sequence."
  (declare (indent 0))
  `(progn
     (setq maf--debug-step-win     (selected-window))
     (setq maf--debug-step-steps   (list ,@(mapcar (lambda (f) `(lambda () ,f)) body)))
     (setq maf--debug-step-forms   (list ,@(mapcar (lambda (f) `',f) body)))
     (setq maf--debug-step-outputs (make-list ,(length body) nil))
     (setq maf--debug-step-idx     0)
     (setq maf--debug-step-total   ,(length body))
     ;; Title: the file being loaded, else the originating buffer.
     (setq maf--debug-step-title   (or load-file-name buffer-file-name (buffer-name)))
     (maf--debug-step-display)
     (maf--debug-step-render)
     (maf--debug-step-set-mode t)
     nil))

(provide 'maf-step)
