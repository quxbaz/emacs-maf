;; -*- lexical-binding: t; -*-
;;
;; modules/maf-history.el
;;
;; Stack history module: a browsable history of whole stack states.
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
;; The feature is `maf-use-history-mode', a global minor mode registered
;; with the module system; the browsing buffer runs in the
;; `maf-history-mode' major mode.

(require 'calc)
(require 'maf-lib)
(require 'maf-conf "conf")  ; the `maf' customize group

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

(defface maf-history-strip-current
  '((t :inherit warning :weight bold))
  "Face for the current operation in the history strip."
  :group 'maf)

(defface maf-history-legend
  ;; The band dial's controls line wears (see `dial-controls'), copied
  ;; rather than inherited so the module does not require dial: the
  ;; legend should read like the *maf-options* one.
  '((((class color) (background dark))  :background "#1c2733" :extend t)
    (((class color) (background light)) :background "#e2eaf3" :extend t)
    (t :inverse-video t))
  "Face for the key legend above the history."
  :group 'maf)

(defcustom maf-history-size 100
  "Maximum number of stack states kept in the history.
Recording past the limit drops the oldest states. A state shares all
formula structure with the stack it was taken from, so even a large
history stays cheap."
  :type 'natnum
  :group 'maf)

(defcustom maf-history-strip-radius 3
  "Operations shown on each side of the current one in the history strip.
The `*maf-history*' buffer shows a horizontal strip of nearby operation
labels beneath its header; this is how many appear on each side of the
current item."
  :type 'natnum
  :group 'maf)

(defvar maf-history--states nil
  "Recorded stack states, newest first, at most `maf-history-size'.
Each state is a list (VALUES LABEL): VALUES the stack's formula values
top first, with `calc-encase-atoms' wrappers stripped, and LABEL what
produced the state — the change's trail prefix (a string, \"fctr\"),
else \"undo\"/\"redo\", else a structural classification of the change
against the previous stack (see `maf-history--classify').")

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
noise — a minibuffer RET terminating an entry — while the trail prefix
names the operation. The FIRST prefix of a command wins: a multi-value
push records its first value with the real prefix and the rest with
calc's \"...\" continuation marker, so keeping the first preserves the
operation name instead of the meaningless continuation."
  (unless maf-history--record-prefix
    (setq maf-history--record-prefix (list prefix))))

(defvar-local maf-history--index 0
  "Index into `maf-history--states' of the state shown, 0 the newest.")

;;; Recording

(defun maf-history--one-inserted-p (short long)
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

(defun maf-history--classify (old new)
  "Label the change from OLD to NEW stack values, both top-first lists.
For a change with no trail prefix, name it structurally: `new' when one
entry was added (the rest unchanged, wherever it landed), `edit' when
exactly one value changed in place, `del' when entries were removed,
else `change' (several changes at once, a reorder). Distinguishes
adding an entry from editing one — the common single-entry cases
exactly, the rest best-effort."
  (let ((no (length old)) (nn (length new)))
    (cond
     ((and (= nn (1+ no)) (maf-history--one-inserted-p old new)) "new")
     ((and (= nn no)
           (= 1 (let ((d 0) (o old) (n new))
                  (while o
                    (unless (equal (car o) (car n)) (setq d (1+ d)))
                    (setq o (cdr o) n (cdr n)))
                  d)))
      "edit")
     ((< nn no) "del")
     (t "change"))))

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
              (let* ((old maf-history--last-raw)
                     (trail (and prefix (car prefix)))
                     ;; maf-edit's "edit" prefix is a blanket label, so
                     ;; describe what it did structurally (new/edit/del);
                     ;; undo/redo keep their identity (a diff would
                     ;; mislabel them); a named trail prefix otherwise
                     ;; wins, falling back to a structural classification.
                     (label
                      (cond
                       ((eq this-command 'maf-edit-commit)
                        (maf-history--classify old raw))
                       ((memq this-command '(maf-undo calc-undo)) "undo")
                       ((memq this-command '(maf-redo calc-redo)) "redo")
                       ((and (stringp trail) (> (length trail) 0)) trail)
                       (t (maf-history--classify old raw)))))
                (setq maf-history--last-raw raw)
                (maf-history--record (mapcar #'maf--strip-encasing raw)
                                      label)))))))))

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

(defun maf-history--strip-label (state)
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

(defun maf-history--strip (total index)
  "Return the horizontal operation strip around INDEX of TOTAL states.
Older operations to the left, newer to the right, the current one
highlighted; `maf-history-strip-radius' slots show on each side, with
a `…' at an end when more states lie beyond the window."
  (let* ((radius maf-history-strip-radius)
         (hi (min (1- total) (+ index radius)))   ; oldest shown, leftmost
         (lo (max 0 (- index radius)))            ; newest shown, rightmost
         (parts nil)
         (i hi))
    ;; Walk older -> newer so `nreverse' yields left-to-right order.
    (while (>= i lo)
      (let ((label (maf-history--strip-label (nth i maf-history--states))))
        (push (propertize label 'face
                          (if (= i index) 'maf-history-strip-current 'shadow))
              parts))
      (setq i (1- i)))
    (concat (if (< hi (1- total)) "… " "")
            (string-join (nreverse parts) " · ")
            (if (> lo 0) " …" ""))))

(defvar maf-history--controls nil
  "Commands summarized on the legend line, in order.
Each entry is (COMMAND VERB . PREFERRED-KEYS), the shape dial's
controls line uses (see `dial-default-controls'): COMMAND one command
or a list that reads as one control, and the keys the ones to show
for it, kept only while each still runs it.")

;; Set outside the defvar so a reload applies edits to the list.
(setq maf-history--controls
      '(((maf-history-previous maf-history-next) "step" "h" "l" "u" "i")
        ((maf-history-oldest maf-history-newest) "ends" "<" ">")
        (maf-history-insert "insert" "RET")
        (maf-history-restore "restore" "r")
        (maf-history-delete "delete" "D")
        (maf-history-visit-calc "calc" "v")
        (quit-window "quit" "q")))

(defun maf-history--control-keys (command preferred)
  "Return the key strings naming COMMAND on the legend line.
COMMAND is one command or a list of them. Each PREFERRED key is kept
only while it still runs one of COMMAND in this buffer, so a binding
moved away drops out of the legend rather than misleading; with none
left the live keymap decides."
  (or (seq-filter (lambda (key)
                    (memq (key-binding (kbd key)) (ensure-list command)))
                  (ensure-list preferred))
      (when-let ((key (where-is-internal (car (ensure-list command)) nil t)))
        (list (key-description key)))
      (list "M-x")))

(defun maf-history--legend ()
  "Return the key legend line shown at the top of the buffer.
The shape of the *maf-options* controls line: each control's keys in
the binding face, its verb after, the whole line on the
`maf-history-legend' band. Keys are looked up in the buffer's live
keymaps, so the legend follows a rebinding. Ends in its own newline,
which carries the band face so its `:extend' reaches the window edge."
  (let ((line (concat
               " "
               (mapconcat
                (lambda (cell)
                  (pcase-let ((`(,command ,verb . ,preferred) cell))
                    (concat (mapconcat (lambda (key)
                                         (propertize key 'face 'help-key-binding))
                                       (maf-history--control-keys command preferred)
                                       "/")
                            " " verb)))
                maf-history--controls
                "   ")
               "\n")))
    (add-face-text-property 0 (length line) 'maf-history-legend t line)
    line))

(defun maf-history--render ()
  "Render the state at `maf-history--index' into the current buffer.
A key legend (see `maf-history--legend') sits at the top, then a
one-line operation strip (see `maf-history--strip'), then the stack
state. Point keeps its line and column when the buffer had content; a
fresh buffer gets point on the top-of-stack entry, the likeliest RET
target."
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
    ;; The legend, then the operation strip: a row of nearby operations
    ;; beneath the header, above the stack state. Neither carries the
    ;; `maf-history-value' property, so RET ignores them.
    (insert (maf-history--legend) "\n")
    (when (> total 0)
      (insert (maf-history--strip total index) "\n\n"))
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
            (insert (maf-history--format-entry val level) "\n")
            (put-text-property start (point) 'maf-history-value val)
            (when (and prev-values (not (member val prev-values)))
              (put-text-property start (point) 'face 'maf-history-changed)))
          (setq level (1- level))))))
    ;; The current op is highlighted in the strip, so the header keeps
    ;; only the position counter.
    (setq header-line-format
          (maf-history--header total index nil))
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

(defvar maf-history-mode-map (make-sparse-keymap)
  "Keymap for `maf-history-mode'.")

;; Bindings live outside the defvar so reloading the file applies edits
;; to the existing map.
(define-key maf-history-mode-map (kbd "u") #'maf-history-previous)
(define-key maf-history-mode-map (kbd "i") #'maf-history-next)
;; h/l step older/newer too, matching the strip's left-older orientation.
(define-key maf-history-mode-map (kbd "h") #'maf-history-previous)
(define-key maf-history-mode-map (kbd "l") #'maf-history-next)
(define-key maf-history-mode-map (kbd "M-p") #'maf-history-previous)
(define-key maf-history-mode-map (kbd "M-n") #'maf-history-next)
(define-key maf-history-mode-map (kbd "<") #'maf-history-oldest)
(define-key maf-history-mode-map (kbd ">") #'maf-history-newest)
;; Line motion between entries, for picking a RET target.
(define-key maf-history-mode-map (kbd "n") #'next-line)
(define-key maf-history-mode-map (kbd "p") #'previous-line)
(define-key maf-history-mode-map (kbd "j") #'next-line)
(define-key maf-history-mode-map (kbd "k") #'previous-line)
(define-key maf-history-mode-map (kbd "v") #'maf-history-visit-calc)
(define-key maf-history-mode-map (kbd "RET") #'maf-history-insert)
(define-key maf-history-mode-map (kbd "C-<return>") #'maf-history-insert-stay)
(define-key maf-history-mode-map (kbd "r") #'maf-history-restore)
;; Capital, so a fingerslip on the motion keys cannot reach a delete.
(define-key maf-history-mode-map (kbd "D") #'maf-history-delete)

(define-derived-mode maf-history-mode special-mode "maf-history"
  "Major mode for browsing calc stack history.
Each view is one whole stack state, rendered as calc renders the
stack, with the entries that step produced highlighted. \\<maf-history-mode-map>
\\[maf-history-previous] steps to older states and \\[maf-history-next]
to newer ones; \\[maf-history-oldest] and \\[maf-history-newest] jump
to the ends. \\[maf-history-insert] pushes the entry at point onto
the live stack and quits; \\[maf-history-insert-stay] pushes and
stays, ready to insert more. \\[maf-history-restore] replaces the
whole stack with the state shown and quits. \\[maf-history-delete]
deletes the state shown from the log. \\[quit-window] buries the
buffer."
  (setq truncate-lines t)
  (setq-local revert-buffer-function
              (lambda (&rest _) (maf-history--render))))

(defun maf-history--buffer ()
  "Return the history buffer, creating and rendering it if needed."
  (or (get-buffer "*maf-history*")
      (with-current-buffer (get-buffer-create "*maf-history*")
        (maf-history-mode)
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
  (unless maf-history--states (user-error "No states recorded yet"))
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
  "Replace the live calc stack with the state being viewed, and quit.
The whole stack becomes this snapshot — copies, as in
`maf-history-insert' — and the view jumps back to the newest state,
which now shows the restored stack. A single undo reverts the
restore. The history window quits, as after `maf-history-insert':
a restore is the end of a browse."
  (interactive)
  (let ((state (nth maf-history--index maf-history--states)))
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
      (setq maf-history--index 0)
      (maf-history--render)
      (message "Stack restored (%d %s)" (length values)
               (if (= (length values) 1) "entry" "entries"))
      (quit-window))))

(defun maf-history-delete ()
  "Delete the state being viewed from the history log.
The live stack is untouched — the history is a log of what happened,
and this drops one record from it, so like `maf-history-clear' it is
not undoable. The view lands on the next older state, or on the
newest remaining when the oldest was the one deleted."
  (interactive)
  (let ((state (nth maf-history--index maf-history--states)))
    (unless state (user-error "No states recorded yet"))
    (let ((total (length maf-history--states))
          (index maf-history--index))
      (if (zerop index)
          (setq maf-history--states (cdr maf-history--states))
        (let ((cell (nthcdr (1- index) maf-history--states)))
          (setcdr cell (cddr cell))))
      (maf-history--render)
      (message "Deleted state %d/%d (%s)" (- total index) total
               (maf-history--strip-label state)))))

(defun maf-history-clear ()
  "Discard every recorded stack state, keeping the live stack.
The history is a log of what happened rather than part of the calc
state, so nothing here is undoable and the stack is untouched — the
next change starts a fresh log, baselined against the stack as it
stands. Recording carries on if it was on; this only empties what was
recorded. Nothing else empties the log — `maf-reset' wipes the session
but deliberately leaves the history standing — so this is the one way
to discard it.

Deliberately unbound in the browser: wiping the whole log a fingerslip
away from \\`r' would be far worse than \\`D''s one state at a time.
Reach it as \\[maf-history-clear]."
  (interactive)
  (let ((n (length maf-history--states)))
    (setq maf-history--states nil
          maf-history--record-prefix nil)
    ;; Rebaseline on the live stack rather than on nil: with the stack
    ;; left standing, a nil baseline would make the next capture record
    ;; the whole stack as if it had just been built.
    (setq maf-history--last-raw
          (let ((buf (maf--find-calc-buffer)))
            (and buf (with-current-buffer buf
                       (mapcar #'car (nthcdr calc-stack-top calc-stack))))))
    (when-let ((buf (get-buffer "*maf-history*")))
      (with-current-buffer buf
        (setq maf-history--index 0)
        (maf-history--render)))
    (when (called-interactively-p 'interactive)
      (message "History cleared (%d %s)" n (if (= n 1) "state" "states")))
    n))

;;; The module

;;;###autoload
(define-minor-mode maf-use-history-mode
  "Global minor mode recording a browsable history of calc stack states.
Enabled, every stack change is snapshotted (see this file's commentary)
and `\\[maf-history]' — bound to \\`t d' in `maf-mode' buffers — opens
the *maf-history* browser. Disabled, recording stops and the \\`t d'
key falls back to calc's own `calc-trail-display'; states already
recorded stay browsable. Managed through the module system; see
`maf-modules'."
  :global t
  :group 'maf
  (if maf-use-history-mode
      (progn
        (advice-add 'calc-record :after #'maf-history--stash-prefix)
        (add-hook 'post-command-hook #'maf-history--capture)
        (maf-bindings--refresh)
        ;; Baseline the current stack so the first change diffs against it.
        (maf-history--capture))
    (remove-hook 'post-command-hook #'maf-history--capture)
    (advice-remove 'calc-record #'maf-history--stash-prefix)
    ;; The recompile cedes the key back to calc's trail display.
    (maf-bindings--refresh)))

;; M-h beside t d: h for history, a single chord for the browse the
;; history is for. It shadows only the global `mark-paragraph', which
;; has no meaning in the stack buffer.
(maf-bindings-module-keys 'maf-history 'maf-use-history-mode
  '(((calc native vim) "t d" maf-history)
    ((calc native vim) "M-h" maf-history)))

;; Register with the module system when it is present; the mode above
;; works on its own without it.
(when (require 'maf-module nil t)
  (maf-register-module 'maf-history #'maf-use-history-mode
                       "Browse past stack states and bring any of them back.

Every command that changes the stack records a snapshot. The
*maf-history* buffer shows one state at a time with the entries that
changed highlighted: u and i step through them, RET pushes the entry
at point onto the live stack, r restores the whole state, D deletes
a state from the log."
                       "t d, M-h" "Memory"))

(provide 'maf-history)
