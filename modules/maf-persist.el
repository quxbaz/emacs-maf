;; -*- lexical-binding: t; -*-
;;
;; modules/persist.el
;;
;; Stack persistence module: each Emacs session saves its calc stack
;; under its own name and restores it in the next session, so juggling
;; several sessions never loses a stack — sessions write only their own
;; file, and `maf-restore-stack-from' loads any other session's stack on
;; request. The whole feature hangs off one switch,
;; `maf-persist-mode' (a global minor mode); loading this
;; file changes nothing. Save files hold plain formula values: no
;; selections, trail, or undo history.
;;
;; The mode is registered with the module system as `persist' (see
;; `maf-modules'). Unlike the highlight and history modules it is not
;; in the default module set: it writes files to disk, so it stays
;; opt-in — the dev instance turns it on in project-init.el.
;;
;; Session names: a session running a server (daemon, or `server-start'
;; from init) is named by its `server-name'. Sessions without a server
;; share the name \"default\"; when several run at once, later ones
;; uniquify to \"default-2\", \"default-3\", ... — a lock file holding
;; the owner's PID marks a name as taken, in the manner of desktop.el,
;; and a lock whose owner died is stale and reclaimed. Set
;; `maf-stack-session-name' to name a session explicitly.

(require 'calc)
(require 'maf-lib)
(require 'maf-conf "conf")  ; the `maf' customize group

(defvar maf-mode-map)

(defcustom maf-stack-directory (locate-user-emacs-file "maf-stacks/")
  "Directory holding the per-session calc stack save files."
  :type 'directory
  :group 'maf)

(defcustom maf-stack-save-interval 60
  "Idle seconds between stack autosaves.
Takes effect when `maf-persist-mode' turns on; after
changing it, toggle the mode to restart the timer on the new
interval."
  :type 'natnum
  :group 'maf)

(defcustom maf-stack-session-name nil
  "Explicit session name for stack persistence, a string.
Nil derives one: `server-name' when this session runs a server, else
\"default\". Either way the name uniquifies when a live session
already holds it."
  :type '(choice (const :tag "Derive from server-name" nil) string)
  :group 'maf)

(defvar maf--stack-session nil
  "Session name claimed by this session, once resolved.")

(defvar maf--stack-save-timer nil
  "Idle timer running `maf-save-stack', while the mode is on.")

(defvar maf--stack-restored nil
  "Non-nil once `maf-restore-stack' has run in this session.")

(defvar maf--stack-last-saved nil
  "Stack values at the last save, for skipping no-change writes.")

;;; Session names and locks

(defun maf--stack-file (name &optional ext)
  "Return the path of session NAME's save file, or its EXT file."
  (expand-file-name (concat (replace-regexp-in-string "[/\\]" "-" name)
                            (or ext ".eld"))
                    maf-stack-directory))

(defun maf--stack-lock-owner (name)
  "Return the live PID owning session NAME's lock, or nil.
A lock whose process is gone is stale, and as good as no lock."
  (let ((lock (maf--stack-file name ".lock")))
    (when-let* ((pid (and (file-exists-p lock)
                          (ignore-errors
                            (with-temp-buffer
                              (insert-file-contents lock)
                              (read (current-buffer)))))))
      (and (integerp pid)
           (/= pid (emacs-pid))
           (process-attributes pid)
           pid))))

(defun maf--stack-session ()
  "Return this session's name, claiming one on first use.
The base name — `maf-stack-session-name', or `server-name' when a
server runs, or \"default\" — uniquifies past names locked by other
live sessions, and the result is locked for this session."
  (or maf--stack-session
      (let* ((base (or maf-stack-session-name
                       (and (bound-and-true-p server-process)
                            (bound-and-true-p server-name))
                       "default"))
             (name base)
             (n 1))
        (make-directory maf-stack-directory t)
        (while (maf--stack-lock-owner name)
          (setq n (1+ n)
                name (format "%s-%d" base n)))
        (write-region (number-to-string (emacs-pid)) nil
                      (maf--stack-file name ".lock") nil 'silent)
        (setq maf--stack-session name))))

(defun maf--stack-release-lock ()
  "Release this session's name lock, if it was claimed."
  (when maf--stack-session
    (let ((lock (maf--stack-file maf--stack-session ".lock")))
      (unless (maf--stack-lock-owner maf--stack-session)
        (ignore-errors (delete-file lock))))
    (setq maf--stack-session nil)))

;;; Saving and restoring

(defun maf-save-stack ()
  "Save the calc stack to this session's file in `maf-stack-directory'.
The file holds the stack's formula values, top first, with
`calc-encase-atoms' wrappers stripped. Unchanged values since the last
save — and a session with no calc buffer at all — write nothing.
Returns non-nil when a write happened."
  (interactive)
  (when-let ((buf (get-buffer "*Calculator*")))
    (let ((values (with-current-buffer buf
                    (mapcar (lambda (entry)
                              (maf--strip-encasing (car entry)))
                            (cdr calc-stack)))))
      (unless (equal values maf--stack-last-saved)
        (setq maf--stack-last-saved values)
        ;; Print in full: a config that caps print-length or
        ;; print-level would silently truncate the file into garbage.
        (let ((print-length nil)
              (print-level nil))
          (make-directory maf-stack-directory t)
          (with-temp-file (maf--stack-file (maf--stack-session))
            (prin1 values (current-buffer))))
        t))))

(defun maf--stack-read (file)
  "Read and return the stack values saved in FILE."
  (delq nil (with-temp-buffer
              (insert-file-contents file)
              (read (current-buffer)))))

(defun maf-restore-stack ()
  "Restore this session's saved calc stack, once per session.
Runs in the calc buffer, and only onto an empty stack. Without a save
file for this session the stack starts empty, mentioning
`maf-restore-stack-from' when other sessions' stacks exist. A file
that cannot be read is skipped with a message and left in place for
inspection — calc starts empty rather than failing to start."
  (interactive)
  (unless maf--stack-restored
    (setq maf--stack-restored t)
    (when (zerop (calc-stack-size))
      (let ((file (maf--stack-file (maf--stack-session))))
        (if (not (file-exists-p file))
            (when-let ((others (maf--stack-saved-sessions)))
              (message (concat "maf: no saved stack for session %s; "
                               "M-x maf-restore-stack-from loads another "
                               "(%d saved)")
                       maf--stack-session (length others)))
          (condition-case err
              (let ((values (maf--stack-read file)))
                (when values
                  ;; Values are stored top first; calc-push-list wants
                  ;; its first element deepest.
                  (calc-push-list (reverse values))
                  (calc-refresh)
                  (setq maf--stack-last-saved values)))
            (error (message "maf: calc stack not restored, %s unreadable (%s)"
                            file (error-message-string err)))))))))

;;; Choosing another session's stack

(defun maf--stack-saved-sessions ()
  "Return the saved sessions as (NAME . FILE), newest save first."
  (when (file-directory-p maf-stack-directory)
    (sort (mapcar (lambda (file)
                    (cons (file-name-base file) file))
                  (directory-files maf-stack-directory t "\\.eld\\'"))
          (lambda (a b) (time-less-p (file-attribute-modification-time
                                      (file-attributes (cdr b)))
                                     (file-attribute-modification-time
                                      (file-attributes (cdr a))))))))

(defun maf--stack-session-annotation (file)
  "Return a chooser annotation for the session saved in FILE."
  (let ((count (condition-case nil
                   (format "%d entries" (length (maf--stack-read file)))
                 (error "unreadable")))
        (age (let ((s (float-time
                       (time-since (file-attribute-modification-time
                                    (file-attributes file))))))
               (cond ((< s 90) "just now")
                     ((< s 5400) (format "%d min ago" (round s 60)))
                     ((< s 129600) (format "%d h ago" (round s 3600)))
                     (t (format "%d d ago" (round s 86400)))))))
    (format "  %s, %s" count age)))

(defun maf-restore-stack-from (session &optional keep)
  "Restore SESSION's saved stack into calc, replacing the current stack.
Interactively, choose from the saved sessions, annotated with entry
count and save age. With a prefix argument (KEEP non-nil), the loaded
entries push on top of the current stack instead of replacing it.
Either way the loaded stack is this session's now: the next save
records it under this session's own name."
  (interactive
   (let* ((sessions (or (maf--stack-saved-sessions)
                        (user-error "No saved stacks in %s"
                                    maf-stack-directory)))
          (completion-extra-properties
           (list :annotation-function
                 (lambda (name)
                   (when-let ((file (cdr (assoc name sessions))))
                     (maf--stack-session-annotation file))))))
     (list (completing-read "Restore stack of session: " sessions nil t)
           current-prefix-arg)))
  (let ((file (maf--stack-file session)))
    (unless (file-exists-p file)
      (user-error "No saved stack for session %s" session))
    (let ((values (condition-case err
                      (maf--stack-read file)
                    (error (user-error "%s unreadable (%s)"
                                       file (error-message-string err))))))
      (maf--with-calc-buffer
        (calc-wrapper
         (unless keep (calc-pop-stack (calc-stack-size)))
         (calc-push-list (reverse values))))
      (setq maf--stack-restored t)
      (message "maf: restored %d entries from session %s"
               (length values) session))))

;;; The switch

(defun maf--stack-shutdown ()
  "Save the stack and release the session lock, for `kill-emacs-hook'."
  (maf-save-stack)
  (maf--stack-release-lock))

;;;###autoload
(define-minor-mode maf-persist-mode
  "Save the Calc stack and restore it in a later Emacs session.

The stack is saved when Emacs exits and after it has been idle for
`maf-stack-save-interval' seconds. It is restored when the first Calc
buffer opens. For example, if you leave 12 and x+1 on the stack, they
return the next time you start the same session.

Press t u to save immediately. Press t l to load a stack saved by a
different session. Each session has its own file, so two running Emacs
sessions do not overwrite each other.

Only stack values are saved. Selections, undo history, and Calc's trail
are not. Files are stored in `maf-stack-directory' under the name from
`maf-stack-session-name'. Turning the mode off stops automatic saving
but does not delete existing save files."
  :global t
  :group 'maf
  (if maf-persist-mode
      (progn
        (add-hook 'kill-emacs-hook #'maf--stack-shutdown)
        (add-hook 'calc-mode-hook #'maf-restore-stack)
        ;; "Load a saved stack", beside the stack history on t d: both
        ;; keys bring back an earlier stack, the history's from this
        ;; session and this one's from any session. t l is unbound in
        ;; calc itself — its t prefix is the trail (t b d f h i k m n o
        ;; p r s y) and the date/time commands on the capitals — so
        ;; nothing is shadowed and there is nothing to cede back.
        (maf-bindings--refresh)
        ;; The load key's companion: update this session's save file now,
        ;; for a checkpoint the idle timer has not reached yet. t u is
        ;; free in calc too, and the right hand takes it without leaving
        ;; the prefix's own hand — t s, the mnemonic key, is calc's
        ;; trail isearch, whose t r twin would be left behind.
        (when maf--stack-save-timer (cancel-timer maf--stack-save-timer))
        (setq maf--stack-save-timer
              (run-with-idle-timer maf-stack-save-interval t #'maf-save-stack))
        ;; Turned on with calc already open and untouched: restore now.
        (when-let ((buf (get-buffer "*Calculator*")))
          (with-current-buffer buf (maf-restore-stack))))
    (remove-hook 'kill-emacs-hook #'maf--stack-shutdown)
    (remove-hook 'calc-mode-hook #'maf-restore-stack)
    (maf-bindings--refresh)
    (when maf--stack-save-timer
      (cancel-timer maf--stack-save-timer)
      (setq maf--stack-save-timer nil))
    ;; The save file stays; only the name lock lets go.
    (maf--stack-release-lock)))

;; Register with the module system when it is present; the mode above
;; works on its own without it.
(maf-bindings-module-keys 'maf-persist 'maf-persist-mode
  '(((calc native vim) "t l" maf-restore-stack-from)
    ((calc native vim) "t u" maf-save-stack)))

(when (require 'maf-module nil t)
  (maf-register-module 'maf-persist #'maf-persist-mode
                       "Save and restore the stack across Emacs sessions.

For example, values left on the stack return the next time you start
the same session. Press t u to save now or t l to load another
session's stack. Only values are saved, not selections or undo history."
                       "t l, t u" "Prefs"))

(provide 'maf-persist)
