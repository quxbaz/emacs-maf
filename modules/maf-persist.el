;; -*- lexical-binding: t; -*-
;;
;; modules/persist.el
;;
;; Stack persistence module: each Emacs session saves its calc stack
;; under its own name and restores it in the next session, so juggling
;; several sessions never loses a stack — sessions write only their own
;; file, and the saved files are browsed in `maf-saved-stacks', a dial
;; buffer (pkg/dial) that previews, restores, names or deletes any
;; session's stack. The whole feature hangs off one switch,
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
(require 'dial)
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

(defun maf-save-stack (&optional interactive)
  "Save the calc stack to this session's file in `maf-stack-directory'.
The file holds the stack's formula values, top first, with
`calc-encase-atoms' wrappers stripped. Unchanged values since the last
save — and a session with no calc buffer at all — write nothing.
Returns non-nil when a write happened.

INTERACTIVE non-nil, as when l S runs this, reports what happened in
the echo area: the idle-timer and kill-emacs saves stay silent."
  (interactive (list t))
  (let ((buf (get-buffer "*Calculator*")))
    (cond
     ((not buf)
      (when interactive (message "maf: no calc stack to save"))
      nil)
     (t
      (let ((values (with-current-buffer buf
                      (mapcar (lambda (entry)
                                (maf--strip-encasing (car entry)))
                              (cdr calc-stack)))))
        (cond
         ((equal values maf--stack-last-saved)
          (when interactive
            (message
             (cond ((null values) "maf: nothing on the stack to save")
                   (maf--stack-session
                    (format "maf: stack unchanged, session %s already saved"
                            maf--stack-session))
                   (t "maf: stack unchanged since the last save"))))
          nil)
         (t
          (setq maf--stack-last-saved values)
          ;; Print in full: a config that caps print-length or
          ;; print-level would silently truncate the file into garbage.
          (let ((print-length nil)
                (print-level nil))
            (make-directory maf-stack-directory t)
            (with-temp-file (maf--stack-file (maf--stack-session))
              (prin1 values (current-buffer))))
          (when interactive
            (message "maf: saved %d entr%s to session %s"
                     (length values) (if (= 1 (length values)) "y" "ies")
                     maf--stack-session))
          t)))))))

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
                               "M-x maf-saved-stacks browses the others "
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

;;; The saved-stacks buffer

;; The browsing UI over the save files, in a dial buffer (pkg/dial):
;; dial provides the shell — the tabulated list, its motion and
;; controls line — and this section supplies the rows and the acts
;; they support. Each row is one saved session; moving onto a row
;; previews its stack in a window beside it, and `maf-stacks-map' lays
;; restore, delete, refresh and quit over dial's keys. The rows have
;; no values to step or defaults to reset, so those dial commands
;; either refuse for themselves or, where their refusal would talk
;; about values, sit under a shadow.

(defun maf--stacks-items ()
  "Compile the saved sessions into dial items, newest save first.
The item ID is the session name interned — dial's rows carry symbols —
and the name itself comes back with `symbol-name'.

No :group: every row is a saved session, so there is one group and
nothing for a heading to distinguish. Dial prints no Group column for
a table like that (see `dial--grouped-p'), and the names start at the
left margin."
  (mapcar (lambda (session)
            (list (intern (car session)) :label (car session)))
          (maf--stack-saved-sessions)))

(defun maf--stacks-annotation (name)
  "Return the Value column text for session NAME: size, age, liveness.
The chooser annotation, plus which sessions are alive right now — this
one by its claimed name, any other by its lock."
  (concat (string-trim-left (maf--stack-session-annotation
                             (maf--stack-file name)))
          ;; Parenthesized, where size and age are comma-separated:
          ;; those two measure the save, this says something about the
          ;; session behind it, and the bracket keeps the two kinds of
          ;; fact from reading as one list.
          (cond ((equal name maf--stack-session) " (current)")
                ((maf--stack-lock-owner name) " (live)")
                (t ""))))

(defun maf--stacks-at-point ()
  "Return the session name on the current line, or signal.
The controls line and the gaps between groups name no session."
  (let ((id (tabulated-list-get-id)))
    (unless (and id (symbolp id))
      (user-error "No session on this line"))
    (symbol-name id)))

(defun maf--stacks-format (value)
  "Format VALUE as calc would display it.
In the calc buffer when one exists, where the display modes live as
buffer-locals; without one the global defaults do."
  (let ((buf (maf--find-calc-buffer)))
    (if buf
        (with-current-buffer buf (math-format-value value))
      (math-format-value value))))

(defun maf--stacks-render (name)
  "Return session NAME's saved stack, laid out as calc lays out a stack.
Deepest entry first, the top of the stack on the last line, levels
numbered the way the stack buffer numbers them. A file that cannot be
read renders as its error, the file itself left in place — the same
policy `maf-restore-stack' follows."
  (condition-case err
      (let* ((values (maf--stack-read (maf--stack-file name)))
             (level (length values)))
        (if (null values)
            "(empty stack)"
          (mapconcat (lambda (value)
                       (prog1 (format "%d: %s" level
                                      (maf--stacks-format value))
                         (setq level (1- level))))
                     (reverse values) "\n")))
    (error (format "unreadable (%s)" (error-message-string err)))))

(defun maf--stacks-neighbor ()
  "Return the row that would take the current row's place if it went.
The row below, or the one above when there is none below. Nil on the
only row left. Read before a deletion, restored after it — see
`maf--stacks-goto'."
  (save-excursion
    (let ((here (tabulated-list-get-id)))
      (dial--move-line 1)
      (if (not (eq (tabulated-list-get-id) here))
          (tabulated-list-get-id)
        ;; The last row: nothing below to move up, so point holds the
        ;; row above instead.
        (dial--move-line -1)
        (let ((above (tabulated-list-get-id)))
          (unless (eq above here) above))))))

(defun maf--stacks-goto (id)
  "Put point on the row for session ID, if the list still shows one.
Off any row — a deleted ID, or nil — point is left where the redraw
put it rather than moved somewhere arbitrary."
  (when id
    (let ((found (save-excursion
                   (goto-char (point-min))
                   (catch 'found
                     (while (not (eobp))
                       (when (eq (tabulated-list-get-id) id)
                         (throw 'found (point)))
                       (forward-line 1))
                     nil))))
      (when found
        (goto-char found)
        (dial--goto-option)))))

(defvar-local maf--stacks-previewed nil
  "The row last previewed, so resting on it redraws nothing.
Cleared wherever a file may have changed under the same row — see
`maf-stacks-refresh' — since only a change of row redraws otherwise.")

(defun maf--stacks-preview ()
  "Preview the hovered session's stack in a window beside the list.
Side by side rather than one above the other: a stack is a column of
entries and the list is a column of rows, so splitting them across
gives each its full height — a stack of any depth is read without
scrolling, which stacked windows would cost.

On `post-command-hook', the way dial's own doc echo follows point: any
motion that lands on another row redraws the preview to that row's
saved stack, dial's j and k no more than C-n or a click. Only a change
of row redraws, and landing off every row — the controls line, a gap —
leaves the last preview standing."
  (let* ((id (tabulated-list-get-id))
         (id (and (symbolp id) id)))
    (when (and id (not (eq id maf--stacks-previewed)))
      (let ((buffer (get-buffer-create "*maf-stacks preview*"))
            (text (maf--stacks-render (symbol-name id))))
        (with-current-buffer buffer
          (let ((inhibit-read-only t))
            (erase-buffer)
            (insert text)
            (goto-char (point-min)))
          (special-mode))
        ;; Marked as previewed only once the text is in: a render that
        ;; threw partway would otherwise leave the row claiming a
        ;; preview it never drew, and nothing short of another row
        ;; would try again.
        (setq maf--stacks-previewed id)
        ;; Borrow a window if the frame has one to lend — calc's,
        ;; usually — the way the formulas menu's detail pane and every
        ;; help buffer do, rather than carving the frame smaller. The
        ;; list already sits at the frame's own split, so borrowing
        ;; leaves the two panes side by side at half the width each;
        ;; asking for a width instead measured the fraction against
        ;; the whole frame, which claimed the list's own half and left
        ;; it in the two columns a window cannot go below. Failing a
        ;; window to borrow, split to the right.
        (display-buffer buffer
                        '((display-buffer-reuse-window
                           maf--display-borrowing-window
                           display-buffer-in-direction)
                          (direction . right)
                          (inhibit-same-window . t)))))))

(defun maf-stacks-restore (&optional keep)
  "Restore the saved stack on the current line, replacing calc's stack.
With a prefix argument (KEEP non-nil) the entries push on top of the
current stack instead. Either way the buffer closes — the stack asked
for is on the stack now — and `maf-restore-stack-from''s rule holds:
the loaded stack is this session's, and the next save records it under
this session's own name."
  (interactive "P")
  (maf-restore-stack-from (maf--stacks-at-point) keep)
  (maf-stacks-quit))

(defun maf-stacks-name (name)
  "Give the session on the current line the name NAME.
Its save file moves to the new name, and the row with it. Prompts
with the name the row carries now.

Naming this very session — the row marked current — names the running
session: the name lock moves with the file, and every later save lands
under NAME. The name holds for as long as this Emacs runs; to keep it
across restarts, set `maf-stack-session-name'.

A name some other saved stack already holds is refused. So is the row
of a session live in another Emacs: that session goes on saving under
its own name, which would bring the old row straight back. A dead
session's leftover lock is dropped along the way — it named nothing."
  (interactive
   (let ((old (maf--stacks-at-point)))
     (list (read-string (format "Name session %s: " old) old))))
  (let ((old (maf--stacks-at-point))
        (name (string-trim name)))
    (when (string-empty-p name)
      (user-error "Session name cannot be empty"))
    (when (string-match-p "[/\\]" name)
      (user-error "Session name cannot contain a slash"))
    (unless (equal name old)
      (when (and (not (equal old maf--stack-session))
                 (maf--stack-lock-owner old))
        (user-error "Session %s is live in another Emacs" old))
      (when (or (file-exists-p (maf--stack-file name))
                (maf--stack-lock-owner name))
        (user-error "Session %s already taken" name))
      (rename-file (maf--stack-file old) (maf--stack-file name))
      (ignore-errors (delete-file (maf--stack-file old ".lock")))
      (when (equal old maf--stack-session)
        (write-region (number-to-string (emacs-pid)) nil
                      (maf--stack-file name ".lock") nil 'silent)
        (setq maf--stack-session name
              maf-stack-session-name name))
      (maf-stacks-refresh)
      (maf--stacks-goto (intern name))
      (message "Session %s is now %s" old name))))

(defun maf-stacks-delete ()
  "Delete the saved stack on the current line, without asking.
Removes the session's save file — and its lock, when no live session
holds it — then drops the row. Deleting the last row closes the
buffer. A live session's row can be deleted too: only the file goes,
and that session writes a fresh one the next time its stack changes.

No confirmation: the row about to go is the one previewed beside the
list, so what is being deleted has just been read rather than named
from memory. Nothing undoes it — the file is gone, and only the
session that wrote it can write it again.

Point stays where it is, on the row that moves up into the deleted
one's place — the last row's neighbour is the one above it. So a run
of deletions is a run of D presses, rather than each one throwing
point back to the top of the list to be walked down again."
  (interactive)
  (let* ((name (maf--stacks-at-point))
         (file (maf--stack-file name))
         (neighbor (maf--stacks-neighbor)))
    (delete-file file)
    (unless (or (equal name maf--stack-session)
                (maf--stack-lock-owner name))
      (ignore-errors (delete-file (maf--stack-file name ".lock"))))
    (setq dial-items (assq-delete-all (intern name) dial-items)
          maf--stacks-previewed nil)
    (if dial-items
        (progn (dial-refresh)
               (maf--stacks-goto neighbor)
               (message "Deleted saved stack of session %s" name))
      (maf-stacks-quit)
      (message "Deleted saved stack of session %s — none left" name))))

(defun maf-stacks-refresh ()
  "Re-read the saved sessions from disk and redraw the list.
Dial's own refresh redraws the rows it has; this one also picks up
sessions saved or deleted since the buffer opened, and redraws the
preview, whose file may have changed under it. An emptied directory
closes the buffer."
  (interactive)
  (setq dial-items (maf--stacks-items)
        maf--stacks-previewed nil)
  (if dial-items
      (dial-refresh)
    (maf-stacks-quit)
    (message "No saved stacks in %s" maf-stack-directory)))

(defun maf-stacks-quit ()
  "Close the saved-stacks buffer and its preview window."
  (interactive)
  (when-let ((window (get-buffer-window "*maf-stacks preview*")))
    (quit-window nil window))
  (quit-window))

(defvar maf-stacks-map (make-sparse-keymap)
  "Keys the saved-stacks buffer lays over `dial-mode-map'.
Composed in front of dial's map at open, so dial's motion — n, p, j,
k — stays underneath while the row acts are these.")

;; Bindings live outside the defvar so reloading the file applies
;; edits to the existing map, as dial's own do.
(define-key maf-stacks-map (kbd "RET") #'maf-stacks-restore)
(define-key maf-stacks-map (kbd "R")   #'maf-stacks-name)
(define-key maf-stacks-map (kbd "D")   #'maf-stacks-delete)
(define-key maf-stacks-map (kbd "g")   #'maf-stacks-refresh)
(define-key maf-stacks-map (kbd "q")   #'maf-stacks-quit)
;; A session is not a setting: there are no values to step along the
;; row, and dial's stepping keys would refuse in terms of values and
;; of RET setting one — wrong twice over here, so they go dark.
(define-key maf-stacks-map (kbd "TAB")       #'undefined)
(define-key maf-stacks-map (kbd "<backtab>") #'undefined)
(define-key maf-stacks-map (kbd "SPC")       #'undefined)
(define-key maf-stacks-map (kbd "h")         #'undefined)
(define-key maf-stacks-map (kbd "l")         #'undefined)

(defvar maf--stacks-controls nil
  "The saved-stacks buffer's controls line.
Dial's default speaks of setting values; these rows are sessions, and
the acts are restore, name and delete.")

;; Set outside the defvar so a reload applies edits to the list.
(setq maf--stacks-controls
      '((maf-stacks-restore "restore" "RET")
        (maf-stacks-name "name" "R")
        (maf-stacks-delete "delete" "D")
        (maf-stacks-refresh "refresh" "g")
        (maf-stacks-quit "quit" "q")))

(defun maf-saved-stacks ()
  "Browse every session's saved stack in one buffer.
Each row is one session's save file with its size, age and liveness
beside the name. Moving onto a row previews that stack in a window to
the right, laid out as calc would show it; the buffer is dial's (see
`dial-mode'), so n, p, j and k move between rows.

\\<maf-stacks-map>\\[maf-stacks-restore] restores the row's stack in
place of the current one — on top of it, with a prefix argument —
\\[maf-stacks-name] gives the row's session another name, and
\\[maf-stacks-delete] deletes its save file. `maf-restore-stack-from'
is the plain-minibuffer way to the same restore."
  (interactive)
  (unless (maf--stack-saved-sessions)
    (user-error "No saved stacks in %s" maf-stack-directory))
  (dial-open "*maf-stacks*" (maf--stacks-items)
             :name "maf-stacks"
             :controls maf--stacks-controls
             :raw (lambda (id) (maf--stacks-annotation (symbol-name id)))
             :init (lambda ()
                     (use-local-map (make-composed-keymap maf-stacks-map
                                                          dial-mode-map))
                     (add-hook 'post-command-hook
                               #'maf--stacks-preview nil t))))

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

Press l S to save immediately. Press l R to browse every session's
saved stack — preview, restore or delete one. Each session has its own
file, so two running Emacs sessions do not overwrite each other.

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
        ;; The pair rides maf's custom-letter family on capitals:
        ;; l S saves this session's file now — a checkpoint the idle
        ;; timer has not reached yet — and l R browses the stacks
        ;; saved by every session, beside the stack history on t d
        ;; (both bring back an earlier stack). The lowercase keys belong to
        ;; complete-square (l s) and to-radians (l r); the capitals
        ;; are free in every profile. In vim, where l is a motion,
        ;; the pair rides the family's o home as o S and o R.
        (maf-bindings--refresh)
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
  '(((calc native) "l R" maf-saved-stacks)
    ((calc native) "l S" maf-save-stack)
    ((vim) "o R" maf-saved-stacks)
    ((vim) "o S" maf-save-stack)))

(when (require 'maf-module nil t)
  (maf-register-module 'maf-persist #'maf-persist-mode
                       "Save and restore the stack across Emacs sessions.

For example, values left on the stack return the next time you start
the same session. Press l S to save now or l R to browse, preview,
restore or delete the saved stacks. Only values are saved, not
selections or undo history."
                       "l R, l S" "Prefs"))

(provide 'maf-persist)
