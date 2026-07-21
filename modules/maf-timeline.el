;; -*- lexical-binding: t; -*-
;;
;; modules/maf-timeline.el
;;
;; Stack timeline module: a browsable timeline of whole stack states.
;; With the module on, every command that changes the stack records a
;; snapshot — whatever produced the change: maf commands, plain calc
;; commands, digit entry, undo. The *maf-timeline* buffer shows one
;; snapshot at a time, rendered like the stack itself, with the
;; entries that changed highlighted; step through states with u/i,
;; press RET on an entry to push it onto the live stack, r to restore
;; the whole snapshot.
;;
;; Recording costs one value-list comparison per command; a snapshot
;; shares all formula structure with the stack it was taken from, so
;; keeping the timeline is cheap. States are deduplicated only
;; consecutively: the timeline is a linear log, not an undo tree.
;;
;; The feature is `maf-use-timeline-mode', a global minor mode registered
;; with the module system; the browsing buffer runs in the
;; `maf-timeline-mode' major mode.

(require 'calc)
(require 'maf-lib)
(require 'maf-conf "conf")

;; Defined in lazily-loaded calc modules; calc-ext's autoload registry
;; resolves them at runtime, but the byte compiler needs declarations.
(declare-function math-format-value "calc-ext")

;; The module installs its `t d' binding into this map, defined in
;; maf.el / bindings.el and current by the time the module is enabled.
(defvar maf-mode-map)

(defface maf-timeline-changed
  '((t :inherit warning))
  "Face for entries new in a timeline state relative to the state before it."
  :group 'maf)

(defface maf-timeline-strip-current
  '((t :inherit warning :weight bold))
  "Face for the current operation in the timeline strip."
  :group 'maf)

(defvar maf-timeline--states nil
  "Recorded stack states, newest first, at most `maf-timeline-size'.
Each state is a list (VALUES LABEL): VALUES the stack's formula values
top first, with `calc-encase-atoms' wrappers stripped, and LABEL what
produced the state — the change's trail prefix (a string, \"fctr\"),
else \"undo\"/\"redo\", else a structural classification of the change
against the previous stack (see `maf-timeline--classify').")

(defvar maf-timeline--last-raw nil
  "Raw stack values at the last capture, for cheap change detection.")

(defvar maf-timeline--record-prefix nil
  "Trail prefix of the current command's `calc-record' call, stashed.
Nil when the command has not recorded; (PREFIX) when it has — PREFIX
itself is nil for a plain entry, which the trail also leaves
unlabeled. Consumed and cleared by `maf-timeline--capture', so a
prefix never outlives the command that recorded it.")

(defun maf-timeline--stash-prefix (_val &optional prefix)
  "Stash PREFIX for `maf-timeline--capture'; advice on `calc-record'.
The interactive command running when a stack change lands is often
noise — a minibuffer RET terminating an entry — while the trail prefix
names the operation. The FIRST prefix of a command wins: a multi-value
push records its first value with the real prefix and the rest with
calc's \"...\" continuation marker, so keeping the first preserves the
operation name instead of the meaningless continuation."
  (unless maf-timeline--record-prefix
    (setq maf-timeline--record-prefix (list prefix))))

(defvar-local maf-timeline--index 0
  "Index into `maf-timeline--states' of the state shown, 0 the newest.")

;;; Recording

(defun maf-timeline--one-inserted-p (short long)
  "Non-nil if LONG is SHORT with exactly one element inserted anywhere.
Both are top-first value lists; comparison is by `equal'."
  (and (= (length long) (1+ (length short)))
       (let ((s short) (l long) (skipped nil) (ok t))
         (while (and l ok)
           (cond
            ((and s (equal (car s) (car l))) (setq s (cdr s) l (cdr l)))
            ((not skipped) (setq skipped t l (cdr l)))  ; the inserted one
            (t (setq ok nil))))
         (and ok (null s)))))

(defun maf-timeline--classify (old new)
  "Label the change from OLD to NEW stack values, both top-first lists.
For a change with no trail prefix, name it structurally: `new' when one
entry was added (the rest unchanged, wherever it landed), `edit' when
exactly one value changed in place, `del' when entries were removed,
else `change' (several changes at once, a reorder). Distinguishes
adding an entry from editing one — the common single-entry cases
exactly, the rest best-effort."
  (let ((no (length old)) (nn (length new)))
    (cond
     ((and (= nn (1+ no)) (maf-timeline--one-inserted-p old new)) "new")
     ((and (= nn no)
           (= 1 (let ((d 0) (o old) (n new))
                  (while o
                    (unless (equal (car o) (car n)) (setq d (1+ d)))
                    (setq o (cdr o) n (cdr n)))
                  d)))
      "edit")
     ((< nn no) "del")
     (t "change"))))

(defun maf-timeline--capture ()
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
                (prefix maf-timeline--record-prefix))
            ;; Consume the stash either way: a record without a stack
            ;; change was a trail message, not this change's prefix.
            (setq maf-timeline--record-prefix nil)
            (unless (equal raw maf-timeline--last-raw)
              (let* ((old maf-timeline--last-raw)
                     (trail (and prefix (car prefix)))
                     ;; maf-edit's "edit" prefix is a blanket label, so
                     ;; describe what it did structurally (new/edit/del);
                     ;; undo/redo keep their identity (a diff would
                     ;; mislabel them); a named trail prefix otherwise
                     ;; wins, falling back to a structural classification.
                     (label
                      (cond
                       ((eq this-command 'maf-edit-commit)
                        (maf-timeline--classify old raw))
                       ((memq this-command '(maf-undo calc-undo)) "undo")
                       ((memq this-command '(maf-redo calc-redo)) "redo")
                       ((and (stringp trail) (> (length trail) 0)) trail)
                       (t (maf-timeline--classify old raw)))))
                (setq maf-timeline--last-raw raw)
                (maf-timeline--record (mapcar #'maf--strip-encasing raw)
                                      label)))))))))

(defun maf-timeline--record (values label)
  "Record VALUES as the newest state, produced by the command LABEL.
Skipped when VALUES matches the newest state — a selection was made or
cleared, changing the entry conses but not the formulas — and when
VALUES is an empty stack with no timeline yet, so the log never starts
with an empty baseline."
  (unless (or (and maf-timeline--states
                   (equal values (nth 0 (car maf-timeline--states))))
              (and (null values) (null maf-timeline--states)))
    (push (list values label) maf-timeline--states)
    (when-let ((cell (nthcdr (1- maf-timeline-size) maf-timeline--states)))
      (setcdr cell nil))
    (maf-timeline--refresh t)))

;;; Rendering

(defun maf-timeline--format-entry (val level)
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

(defun maf-timeline--header (total index label)
  "Return the header line for state INDEX of TOTAL, produced by LABEL."
  (if (zerop total)
      "maf-timeline: no states yet"
    (format "maf-timeline %d/%d%s"
            (- total index) total
            (if label (format " — %s" label) ""))))

(defun maf-timeline--strip-label (state)
  "Return the display string for STATE's label in the operation strip.
A trail-prefix string shows as-is and a command symbol as its name.
States with no named operation read as `entry' — a plain entry (nil
label) and calc's `...' continuation prefix (the extra values of a
multi-value push) — so unnamed steps stay legible and 1:1 with `u'/`i'."
  (let ((label (nth 1 state)))
    (cond ((member label '(nil "" "...")) "entry")
          ((stringp label) label)
          ((symbolp label) (symbol-name label))
          (t "entry"))))

(defun maf-timeline--strip (total index)
  "Return the horizontal operation strip around INDEX of TOTAL states.
Older operations to the left, newer to the right, the current one
highlighted; `maf-timeline-strip-radius' slots show on each side, with
a `…' at an end when more states lie beyond the window."
  (let* ((radius maf-timeline-strip-radius)
         (hi (min (1- total) (+ index radius)))   ; oldest shown, leftmost
         (lo (max 0 (- index radius)))            ; newest shown, rightmost
         (parts nil)
         (i hi))
    ;; Walk older -> newer so `nreverse' yields left-to-right order.
    (while (>= i lo)
      (let ((label (maf-timeline--strip-label (nth i maf-timeline--states))))
        (push (propertize label 'face
                          (if (= i index) 'maf-timeline-strip-current 'shadow))
              parts))
      (setq i (1- i)))
    (concat (if (< hi (1- total)) "… " "")
            (string-join (nreverse parts) " · ")
            (if (> lo 0) " …" ""))))

(defun maf-timeline--render ()
  "Render the state at `maf-timeline--index' into the current buffer.
A one-line operation strip (see `maf-timeline--strip') sits at the top,
above the stack state. Point keeps its line and column when the buffer
had content; a fresh buffer gets point on the top-of-stack entry, the
likeliest RET target."
  (let* ((total (length maf-timeline--states))
         (index (max 0 (min maf-timeline--index (max 0 (1- total)))))
         (state (nth index maf-timeline--states))
         (values (nth 0 state))
         ;; Entries absent from the previous (older) state are what
         ;; this step produced; they get the changed face. The oldest
         ;; state has no reference to diff against.
         (prev-values (and (< (1+ index) total)
                           (nth 0 (nth (1+ index) maf-timeline--states))))
         (fresh (zerop (buffer-size)))
         (line (line-number-at-pos))
         (col (current-column))
         (inhibit-read-only t))
    (setq maf-timeline--index index)
    (erase-buffer)
    ;; The operation strip: a row of nearby operations beneath the
    ;; header, above the stack state. No `maf-timeline-value' property,
    ;; so RET/r ignore it.
    (when (> total 0)
      (insert (maf-timeline--strip total index) "\n\n"))
    (cond
     ((null state)
      (insert (propertize "(no states yet)" 'face 'shadow) "\n"))
     ((null values)
      (insert (propertize "(empty stack)" 'face 'shadow) "\n"))
     (t
      (let ((level (length values)))
        ;; Deepest first, like the stack: level 1 renders at the bottom.
        (dolist (val (reverse values))
          (let ((start (point)))
            (insert (maf-timeline--format-entry val level) "\n")
            (put-text-property start (point) 'maf-timeline-value val)
            (when (and prev-values (not (member val prev-values)))
              (put-text-property start (point) 'face 'maf-timeline-changed)))
          (setq level (1- level))))))
    ;; The current op is highlighted in the strip, so the header keeps
    ;; only the position counter.
    (setq header-line-format
          (maf-timeline--header total index nil))
    (if fresh
        (progn (goto-char (point-max)) (forward-line -1))
      (goto-char (point-min))
      (forward-line (1- line))
      (move-to-column col))))

(defun maf-timeline--refresh (&optional new)
  "Re-render the *maf-timeline* buffer, if it exists.
With NEW non-nil a state was just recorded: a view on the newest state
follows to the new one; a view on an older state stays on that state,
its index shifted under it."
  (when-let ((buf (get-buffer "*maf-timeline*")))
    (with-current-buffer buf
      (when (and new (> maf-timeline--index 0))
        (setq maf-timeline--index (1+ maf-timeline--index)))
      (maf-timeline--render))))

;;; The buffer

(defvar maf-timeline-mode-map (make-sparse-keymap)
  "Keymap for `maf-timeline-mode'.")

;; Bindings live outside the defvar so reloading the file applies edits
;; to the existing map.
(define-key maf-timeline-mode-map (kbd "u") #'maf-timeline-previous)
(define-key maf-timeline-mode-map (kbd "i") #'maf-timeline-next)
(define-key maf-timeline-mode-map (kbd "M-p") #'maf-timeline-previous)
(define-key maf-timeline-mode-map (kbd "M-n") #'maf-timeline-next)
(define-key maf-timeline-mode-map (kbd "<") #'maf-timeline-oldest)
(define-key maf-timeline-mode-map (kbd ">") #'maf-timeline-newest)
;; Line motion between entries, for picking a RET target.
(define-key maf-timeline-mode-map (kbd "n") #'next-line)
(define-key maf-timeline-mode-map (kbd "p") #'previous-line)
(define-key maf-timeline-mode-map (kbd "j") #'next-line)
(define-key maf-timeline-mode-map (kbd "k") #'previous-line)
(define-key maf-timeline-mode-map (kbd "v") #'maf-timeline-visit-calc)
(define-key maf-timeline-mode-map (kbd "RET") #'maf-timeline-insert)
(define-key maf-timeline-mode-map (kbd "C-<return>") #'maf-timeline-insert-stay)
(define-key maf-timeline-mode-map (kbd "r") #'maf-timeline-restore)

(define-derived-mode maf-timeline-mode special-mode "maf-timeline"
  "Major mode for browsing calc stack timeline.
Each view is one whole stack state, rendered as calc renders the
stack, with the entries that step produced highlighted. \\<maf-timeline-mode-map>
\\[maf-timeline-previous] steps to older states and \\[maf-timeline-next]
to newer ones; \\[maf-timeline-oldest] and \\[maf-timeline-newest] jump
to the ends. \\[maf-timeline-insert] pushes the entry at point onto
the live stack and quits; \\[maf-timeline-insert-stay] pushes and
stays, ready to insert more. \\[maf-timeline-restore] replaces the
whole stack with the state shown. \\[quit-window] buries the buffer."
  (setq truncate-lines t)
  (setq-local revert-buffer-function
              (lambda (&rest _) (maf-timeline--render))))

(defun maf-timeline--buffer ()
  "Return the timeline buffer, creating and rendering it if needed."
  (or (get-buffer "*maf-timeline*")
      (with-current-buffer (get-buffer-create "*maf-timeline*")
        (maf-timeline-mode)
        (maf-timeline--render)
        (current-buffer))))

;;;###autoload
(defun maf-timeline ()
  "Show the stack timeline buffer in a window below calc, and select it.
Already visible, the window is selected as it stands. Without a calc
window the buffer opens below the selected window."
  (interactive)
  (let ((buf (maf-timeline--buffer)))
    (select-window
     (or (get-buffer-window buf)
         (let* ((calc-buf (maf--find-calc-buffer))
                (calc-win (and calc-buf (get-buffer-window calc-buf))))
           (with-selected-window (or calc-win (selected-window))
             (display-buffer buf '(display-buffer-below-selected))))))))

(defun maf-timeline-visit-calc ()
  "Select the calc window, leaving the timeline window open.
Without a window showing calc, one is found for it."
  (interactive)
  (let ((buf (or (maf--find-calc-buffer)
                 (user-error "No calc buffer found"))))
    (select-window (or (get-buffer-window buf)
                       (display-buffer buf)))))

;;; Browsing commands

(defun maf-timeline--move (n)
  "Show the state N steps older (newer when N is negative)."
  (unless maf-timeline--states (user-error "No states recorded yet"))
  (let* ((max (1- (length maf-timeline--states)))
         (target (max 0 (min (+ maf-timeline--index n) max))))
    (when (= target maf-timeline--index)
      (user-error (if (> n 0) "Already at the oldest state"
                    "Already at the newest state")))
    (setq maf-timeline--index target)
    (maf-timeline--render)))

(defun maf-timeline-previous (n)
  "Show the Nth previous (older) stack state."
  (interactive "p")
  (maf-timeline--move n))

(defun maf-timeline-next (n)
  "Show the Nth next (newer) stack state."
  (interactive "p")
  (maf-timeline--move (- n)))

(defun maf-timeline-oldest ()
  "Show the oldest recorded stack state."
  (interactive)
  (maf-timeline--move (length maf-timeline--states)))

(defun maf-timeline-newest ()
  "Show the newest recorded stack state."
  (interactive)
  (maf-timeline--move (- (length maf-timeline--states))))

;;; Acting on the live stack

(defun maf-timeline-insert ()
  "Push the timeline entry at point onto the live calc stack, and quit.
The value is pushed on top as a new entry — a copy, so later edits to
the live entry never reach back into the timeline — and recorded in
the timeline as its own step. The timeline window quits, as after
choosing from a list; `maf-timeline-insert-stay' keeps it open."
  (interactive)
  (maf-timeline-insert-stay)
  (quit-window))

(defun maf-timeline-insert-stay ()
  "Push the timeline entry at point onto the live calc stack.
As `maf-timeline-insert', but the timeline window stays open with point
in place, ready to insert more."
  (interactive)
  (let ((val (get-text-property (point) 'maf-timeline-value)))
    (unless val (user-error "No stack entry at point"))
    (setq val (copy-tree val))
    (maf--with-calc-buffer
      (calc-wrapper
       (calc-pop-push-record-list 0 "hist" (list val) 1 (list nil))))
    (message "Pushed: %s" (math-format-value val))))

(defun maf-timeline-restore ()
  "Replace the live calc stack with the state being viewed.
The whole stack becomes this snapshot — copies, as in
`maf-timeline-insert' — and the view jumps back to the newest state,
which now shows the restored stack. A single undo reverts the
restore."
  (interactive)
  (let ((state (nth maf-timeline--index maf-timeline--states)))
    (unless state (user-error "No states recorded yet"))
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
      (setq maf-timeline--index 0)
      (maf-timeline--render)
      (message "Stack restored (%d %s)" (length values)
               (if (= (length values) 1) "entry" "entries")))))

;;; The module

;;;###autoload
(define-minor-mode maf-use-timeline-mode
  "Global minor mode recording a browsable timeline of calc stack states.
Enabled, every stack change is snapshotted (see this file's commentary)
and `\\[maf-timeline]' — bound to \\`t d' in `maf-mode' buffers — opens
the *maf-timeline* browser. Disabled, recording stops and the \\`t d'
key falls back to calc's own `calc-trail-display'; states already
recorded stay browsable. Managed through the module system; see
`maf-modules'."
  :global t
  :group 'maf
  (if maf-use-timeline-mode
      (progn
        (advice-add 'calc-record :after #'maf-timeline--stash-prefix)
        (add-hook 'post-command-hook #'maf-timeline--capture)
        (define-key maf-mode-map (kbd "t d") #'maf-timeline)
        ;; Baseline the current stack so the first change diffs against it.
        (maf-timeline--capture))
    (remove-hook 'post-command-hook #'maf-timeline--capture)
    (advice-remove 'calc-record #'maf-timeline--stash-prefix)
    ;; Cede the key back to calc's trail display.
    (define-key maf-mode-map (kbd "t d") nil)))

;; Register with the module system when it is present; the mode above
;; works on its own without it.
(when (require 'maf-module nil t)
  (maf-register-module 'maf-timeline #'maf-use-timeline-mode
                       "Browsable timeline of stack states; step through and restore snapshots."))

(provide 'maf-timeline)
