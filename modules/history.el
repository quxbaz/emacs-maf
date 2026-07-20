;; -*- lexical-binding: t; -*-
;;
;; modules/history.el
;;
;; Stack history module: a browsable timeline of whole stack states.
;; With the module on, every command that changes the stack records a
;; snapshot — whatever produced the change: maf commands, plain calc
;; commands, digit entry, undo. The *maf-history* buffer shows one
;; snapshot at a time, rendered like the stack itself, with the
;; entries that changed highlighted; step through states with u/i,
;; press RET on an entry to push it onto the live stack, r to restore
;; the whole snapshot.
;;
;; Recording costs one value-list comparison per command; a snapshot
;; shares all formula structure with the stack it was taken from, so
;; keeping the history is cheap. States are deduplicated only
;; consecutively: the history is a linear log, not an undo tree.
;;
;; The feature is `maf-history-mode', a global minor mode registered
;; with the module system; the browsing buffer runs in the
;; `maf-history-list-mode' major mode.

(require 'calc)
(require 'maf-lib)
(require 'maf-module)
(require 'maf-conf "conf")

;; Defined in lazily-loaded calc modules; calc-ext's autoload registry
;; resolves them at runtime, but the byte compiler needs declarations.
(declare-function math-format-value "calc-ext")

;; The module installs its `t d' binding into this map, defined in
;; maf.el / bindings.el and current by the time the module is enabled.
(defvar maf-mode-map)

(defface maf-history-changed
  '((t :inherit warning))
  "Face for entries new in a history state relative to the state before it."
  :group 'maf)

(defvar maf-history--states nil
  "Recorded stack states, newest first, at most `maf-history-size'.
Each state is a list (VALUES LABEL): VALUES the stack's formula values
top first, with `calc-encase-atoms' wrappers stripped, and LABEL what
produced the state — the change's trail prefix (a string, \"fctr\"),
falling back to the command that ran (a symbol) when nothing was
recorded, or nil for a plain entry.")

(defvar maf-history--last-raw nil
  "Raw stack values at the last capture, for cheap change detection.")

(defvar maf-history--record-prefix nil
  "Trail prefix of the current command's `calc-record' call, stashed.
Nil when the command has not recorded; (PREFIX) when it has — PREFIX
itself is nil for a plain entry, which the trail also leaves
unlabeled. Consumed and cleared by `maf-history--capture', so a
prefix never outlives the command that recorded it.")

(defun maf-history--stash-prefix (_val &optional prefix)
  "Stash PREFIX for `maf-history--capture'; advice on `calc-record'.
The interactive command running when a stack change lands is often
noise — a minibuffer RET terminating an entry — while the trail
prefix names the operation; every recorded write passes one here."
  (setq maf-history--record-prefix (list prefix)))

(defvar-local maf-history--index 0
  "Index into `maf-history--states' of the state shown, 0 the newest.")

;;; Recording

(defun maf-history--capture ()
  "Record a stack snapshot when the stack changed; on `post-command-hook'.
Change detection is one `equal' over the entries' value slots — shared
structure makes that an `eq' per unchanged entry — so the hook costs
next to nothing on commands that leave the stack alone. Errors are
swallowed so a bad calc state can never get the hook disabled."
  (ignore-errors
    (let ((buf (if (derived-mode-p 'calc-mode)
                   (current-buffer)
                 (let ((b (get-buffer "*Calculator*")))
                   (and b
                        (with-current-buffer b (derived-mode-p 'calc-mode))
                        b)))))
      (when buf
        (with-current-buffer buf
          (let ((raw (mapcar #'car (nthcdr calc-stack-top calc-stack)))
                (prefix maf-history--record-prefix))
            ;; Consume the stash either way: a record without a stack
            ;; change was a trail message, not this change's prefix.
            (setq maf-history--record-prefix nil)
            (unless (equal raw maf-history--last-raw)
              (setq maf-history--last-raw raw)
              (maf-history--record (mapcar #'maf--strip-encasing raw)
                                   (if prefix (car prefix)
                                     (and (symbolp this-command)
                                          this-command))))))))))

(defun maf-history--record (values label)
  "Record VALUES as the newest state, produced by the command LABEL.
Skipped when VALUES matches the newest state — a selection was made or
cleared, changing the entry conses but not the formulas — and when
VALUES is an empty stack with no history yet, so the log never starts
with an empty baseline."
  (unless (or (and maf-history--states
                   (equal values (nth 0 (car maf-history--states))))
              (and (null values) (null maf-history--states)))
    (push (list values label) maf-history--states)
    (when-let ((cell (nthcdr (1- maf-history-size) maf-history--states)))
      (setcdr cell nil))
    (maf-history--refresh t)))

;;; Rendering

(defun maf-history--format-entry (val level)
  "Format VAL as calc would render it at stack level LEVEL.
The rendering is calc's own — current language, float format, big
mode — produced in the calc buffer; only the level number differs
from the \"1:\" that `math-format-stack-value' hardcodes."
  (let ((s (maf--with-calc-buffer
             (math-format-stack-value (list val 1 nil)))))
    (if (and calc-line-numbering (string-match "^1:  " s))
        ;; Calc's own 4-column level field, `calc-renumber-stack's
        ;; format: past 999 the number wraps into the 3 digits.
        (replace-match (if (> level 999)
                           (format "%03d:" (% level 1000))
                         (let ((p (int-to-string level)))
                           (concat p ":" (make-string (- 3 (length p)) ?\s))))
                       t t s)
      s)))

(defun maf-history--header (total index label)
  "Return the header line for state INDEX of TOTAL, produced by LABEL."
  (if (zerop total)
      "maf-history: no states yet"
    (format "maf-history %d/%d%s"
            (- total index) total
            (if label (format " — %s" label) ""))))

(defun maf-history--render ()
  "Render the state at `maf-history--index' into the current buffer.
Point keeps its line and column when the buffer had content; a fresh
buffer gets point on the top-of-stack entry, the likeliest RET target."
  (let* ((total (length maf-history--states))
         (index (max 0 (min maf-history--index (max 0 (1- total)))))
         (state (nth index maf-history--states))
         (values (nth 0 state))
         ;; Entries absent from the previous (older) state are what
         ;; this step produced; they get the changed face. The oldest
         ;; state has no reference to diff against.
         (prev-values (and (< (1+ index) total)
                           (nth 0 (nth (1+ index) maf-history--states))))
         (fresh (zerop (buffer-size)))
         (line (line-number-at-pos))
         (col (current-column))
         (inhibit-read-only t))
    (setq maf-history--index index)
    (erase-buffer)
    (cond
     ((null state)
      (insert (propertize "(no history yet)" 'face 'shadow) "\n"))
     ((null values)
      (insert (propertize "(empty stack)" 'face 'shadow) "\n"))
     (t
      (let ((level (length values)))
        ;; Deepest first, like the stack: level 1 renders at the bottom.
        (dolist (val (reverse values))
          (let ((start (point)))
            (insert (maf-history--format-entry val level) "\n")
            (put-text-property start (point) 'maf-history-value val)
            (when (and prev-values (not (member val prev-values)))
              (put-text-property start (point) 'face 'maf-history-changed)))
          (setq level (1- level))))))
    (setq header-line-format
          (maf-history--header total index (nth 1 state)))
    (if fresh
        (progn (goto-char (point-max)) (forward-line -1))
      (goto-char (point-min))
      (forward-line (1- line))
      (move-to-column col))))

(defun maf-history--refresh (&optional new)
  "Re-render the *maf-history* buffer, if it exists.
With NEW non-nil a state was just recorded: a view on the newest state
follows to the new one; a view on an older state stays on that state,
its index shifted under it."
  (when-let ((buf (get-buffer "*maf-history*")))
    (with-current-buffer buf
      (when (and new (> maf-history--index 0))
        (setq maf-history--index (1+ maf-history--index)))
      (maf-history--render))))

;;; The buffer

(defvar maf-history-list-mode-map (make-sparse-keymap)
  "Keymap for `maf-history-list-mode'.")

;; Bindings live outside the defvar so reloading the file applies edits
;; to the existing map.
(define-key maf-history-list-mode-map (kbd "u") #'maf-history-previous)
(define-key maf-history-list-mode-map (kbd "i") #'maf-history-next)
(define-key maf-history-list-mode-map (kbd "<") #'maf-history-oldest)
(define-key maf-history-list-mode-map (kbd ">") #'maf-history-newest)
;; Line motion between entries, for picking a RET target.
(define-key maf-history-list-mode-map (kbd "n") #'next-line)
(define-key maf-history-list-mode-map (kbd "p") #'previous-line)
(define-key maf-history-list-mode-map (kbd "j") #'next-line)
(define-key maf-history-list-mode-map (kbd "k") #'previous-line)
(define-key maf-history-list-mode-map (kbd "v") #'maf-history-visit-calc)
(define-key maf-history-list-mode-map (kbd "RET") #'maf-history-insert)
(define-key maf-history-list-mode-map (kbd "C-<return>") #'maf-history-insert-stay)
(define-key maf-history-list-mode-map (kbd "r") #'maf-history-restore)

(define-derived-mode maf-history-list-mode special-mode "maf-history"
  "Major mode for browsing calc stack history.
Each view is one whole stack state, rendered as calc renders the
stack, with the entries that step produced highlighted. \\<maf-history-list-mode-map>
\\[maf-history-previous] steps to older states and \\[maf-history-next]
to newer ones; \\[maf-history-oldest] and \\[maf-history-newest] jump
to the ends. \\[maf-history-insert] pushes the entry at point onto
the live stack and quits; \\[maf-history-insert-stay] pushes and
stays, ready to insert more. \\[maf-history-restore] replaces the
whole stack with the state shown. \\[quit-window] buries the buffer."
  (setq truncate-lines t)
  (setq-local revert-buffer-function
              (lambda (&rest _) (maf-history--render))))

(defun maf-history--buffer ()
  "Return the history buffer, creating and rendering it if needed."
  (or (get-buffer "*maf-history*")
      (with-current-buffer (get-buffer-create "*maf-history*")
        (maf-history-list-mode)
        (maf-history--render)
        (current-buffer))))

;;;###autoload
(defun maf-history ()
  "Show the stack history buffer in a window below calc, and select it.
Already visible, the window is selected as it stands. Without a calc
window the buffer opens below the selected window."
  (interactive)
  (let ((buf (maf-history--buffer)))
    (select-window
     (or (get-buffer-window buf)
         (let* ((calc-buf (maf--find-calc-buffer))
                (calc-win (and calc-buf (get-buffer-window calc-buf))))
           (with-selected-window (or calc-win (selected-window))
             (display-buffer buf '(display-buffer-below-selected))))))))

(defun maf-history-visit-calc ()
  "Select the calc window, leaving the history window open.
Without a window showing calc, one is found for it."
  (interactive)
  (let ((buf (or (maf--find-calc-buffer)
                 (user-error "No calc buffer found"))))
    (select-window (or (get-buffer-window buf)
                       (display-buffer buf)))))

;;; Browsing commands

(defun maf-history--move (n)
  "Show the state N steps older (newer when N is negative)."
  (unless maf-history--states (user-error "No history recorded yet"))
  (let* ((max (1- (length maf-history--states)))
         (target (max 0 (min (+ maf-history--index n) max))))
    (when (= target maf-history--index)
      (user-error (if (> n 0) "Already at the oldest state"
                    "Already at the newest state")))
    (setq maf-history--index target)
    (maf-history--render)))

(defun maf-history-previous (n)
  "Show the Nth previous (older) stack state."
  (interactive "p")
  (maf-history--move n))

(defun maf-history-next (n)
  "Show the Nth next (newer) stack state."
  (interactive "p")
  (maf-history--move (- n)))

(defun maf-history-oldest ()
  "Show the oldest recorded stack state."
  (interactive)
  (maf-history--move (length maf-history--states)))

(defun maf-history-newest ()
  "Show the newest recorded stack state."
  (interactive)
  (maf-history--move (- (length maf-history--states))))

;;; Acting on the live stack

(defun maf-history-insert ()
  "Push the history entry at point onto the live calc stack, and quit.
The value is pushed on top as a new entry — a copy, so later edits to
the live entry never reach back into the history — and recorded in
the history as its own step. The history window quits, as after
choosing from a list; `maf-history-insert-stay' keeps it open."
  (interactive)
  (maf-history-insert-stay)
  (quit-window))

(defun maf-history-insert-stay ()
  "Push the history entry at point onto the live calc stack.
As `maf-history-insert', but the history window stays open with point
in place, ready to insert more."
  (interactive)
  (let ((val (get-text-property (point) 'maf-history-value)))
    (unless val (user-error "No stack entry at point"))
    (setq val (copy-tree val))
    (maf--with-calc-buffer
      (calc-wrapper
       (calc-pop-push-record-list 0 "hist" (list val) 1 (list nil))))
    (message "Pushed: %s" (math-format-value val))))

(defun maf-history-restore ()
  "Replace the live calc stack with the state being viewed.
The whole stack becomes this snapshot — copies, as in
`maf-history-insert' — and the view jumps back to the newest state,
which now shows the restored stack. A single undo reverts the
restore."
  (interactive)
  (let ((state (nth maf-history--index maf-history--states)))
    (unless state (user-error "No history recorded yet"))
    (let ((values (mapcar #'copy-tree (nth 0 state))))
      (maf--with-calc-buffer
        (calc-wrapper
         (cond (values
                ;; The list runs deepest-first; values are stored top
                ;; first.
                (calc-pop-push-record-list (calc-stack-size) "hist"
                                           (reverse values)))
               ((> (calc-stack-size) 0)
                (calc-pop-stack (calc-stack-size))))))
      (setq maf-history--index 0)
      (maf-history--render)
      (message "Stack restored (%d %s)" (length values)
               (if (= (length values) 1) "entry" "entries")))))

;;; The module

;;;###autoload
(define-minor-mode maf-history-mode
  "Global minor mode recording a browsable history of calc stack states.
Enabled, every stack change is snapshotted (see this file's commentary)
and `\\[maf-history]' — bound to \\`t d' in `maf-mode' buffers — opens
the *maf-history* browser. Disabled, recording stops and the \\`t d'
key falls back to calc's own `calc-trail-display'; states already
recorded stay browsable. Managed through the module system; see
`maf-modules'."
  :global t
  :group 'maf
  (if maf-history-mode
      (progn
        (advice-add 'calc-record :after #'maf-history--stash-prefix)
        (add-hook 'post-command-hook #'maf-history--capture)
        (define-key maf-mode-map (kbd "t d") #'maf-history)
        ;; Baseline the current stack so the first change diffs against it.
        (maf-history--capture))
    (remove-hook 'post-command-hook #'maf-history--capture)
    (advice-remove 'calc-record #'maf-history--stash-prefix)
    ;; Cede the key back to calc's trail display.
    (define-key maf-mode-map (kbd "t d") nil)))

(maf-register-module 'history #'maf-history-mode)

(provide 'maf-history)
