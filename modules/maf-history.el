;; -*- lexical-binding: t; -*-
;;
;; modules/maf-history.el
;;
;; Stack history module: a browsable history of whole stack states.
;; With the module on, every command that changes the stack records a
;; snapshot — whatever produced the change: maf commands, plain calc
;; commands, digit entry, undo. Browsing is two side-by-side windows:
;; *maf-history* on the left is the action log, one line per recorded
;; state, newest at the top, the current one marked; *maf-history-stack*
;; on the right shows that state's whole stack, rendered like the stack
;; itself with the entries that step produced highlighted. Moving in
;; the log re-renders the stack beside it: n/p/j/k step through the
;; states. Press RET on an entry in the stack to push it onto the live
;; stack, r to restore the whole snapshot.
;;
;; Recording costs one value-list comparison per command; a snapshot
;; shares all formula structure with the stack it was taken from, so
;; keeping the history is cheap. States are deduplicated only
;; consecutively: the history is a linear log, not an undo tree.
;;
;; The feature is `maf-use-history-mode', a global minor mode registered
;; with the module system; the two browsing buffers run in the
;; `maf-history-mode' and `maf-history-stack-mode' major modes.

(require 'calc)
(require 'maf-lib)
(require 'maf-conf "conf")  ; the `maf' customize group

;; Defined in lazily-loaded calc modules; calc-ext's autoload registry
;; resolves them at runtime, but the byte compiler needs declarations.
(declare-function math-format-value "calc-ext")

;; The module installs its `M-h' binding into this map, defined in
;; maf.el / bindings.el and current by the time the module is enabled.
(defvar maf-mode-map)

(defface maf-history-changed
  '((t :inherit warning))
  "Face for entries new in a history state relative to the state before it."
  :group 'maf)

(defface maf-history-current
  '((t :inherit warning :weight bold))
  "Face for the current state's action in the history log."
  :group 'maf)

;; The log's change markers, coloured the way a git UI colours a diff
;; stat. The core semantic faces rather than the `diff-*' ones: every
;; theme styles these three, while `diff-changed' is commonly left
;; unspecified.
(defface maf-history-added
  '((t :inherit success))
  "Face for the marker on a state that added a stack entry."
  :group 'maf)

(defface maf-history-removed
  '((t :inherit error))
  "Face for the marker on a state that removed stack entries."
  :group 'maf)

(defface maf-history-modified
  '((t :inherit warning))
  "Face for the marker on a state that changed the stack in place."
  :group 'maf)

(defcustom maf-history-log-width (/ 1.0 3)
  "Share of the width given to the action log in the history browser.
`maf-history' shows the log on the left and the state's stack on the
right; this fraction of the space the pair is opened in goes to the
log, the rest to the stack. A third of it by default, so the two run
1:2 — enough for a log line to carry its label and the command name
after it (see `maf-history--command-name') without the formulas beside
it losing the room to render. Either window can still be resized by
hand afterwards."
  :type 'float
  :group 'maf)

(defcustom maf-history-size 100
  "Maximum number of stack states kept in the history.
Recording past the limit drops the oldest states. A state shares all
formula structure with the stack it was taken from, so even a large
history stays cheap."
  :type 'natnum
  :group 'maf)

(defvar maf-history--states nil
  "Recorded stack states, newest first, at most `maf-history-size'.
Each state is a list (VALUES LABEL COMMAND): VALUES the stack's formula
values top first, with `calc-encase-atoms' wrappers stripped; LABEL
what produced the state — the change's trail prefix (a string,
\"fctr\"), else \"undo\"/\"redo\", else a structural classification of
the change against the previous stack (see `maf-history--classify');
and COMMAND the `this-command' the change landed under, the precise
name behind a label that names an operation rather than a command.
COMMAND is nil for a state recorded outside any command.")

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

(defvar maf-history--index 0
  "Index into `maf-history--states' of the state shown, 0 the newest.
Global rather than per-buffer: the log and the stack beside it are two
views on one selection, so both read the same index.")

(defconst maf-history--log-buffer "*maf-history*"
  "Name of the buffer holding the action log, the browser's left window.")

(defconst maf-history--stack-buffer "*maf-history-stack*"
  "Name of the buffer holding the selected state's stack, on the right.")

;;; Recording

(defun maf-history--diff (old new)
  "Return (INDEX OLD-COUNT NEW-COUNT), where NEW differs from OLD.
Both are top-first stack value lists, compared by `equal'. The entries
the two stacks share at the bottom are matched off first and the ones
they share at the top after, leaving one contiguous region: the
OLD-COUNT entries at INDEX in OLD are the NEW-COUNT entries at INDEX in
NEW. Matching the bottom first settles the ambiguous case — after
duplicating an entry either copy could be called the new one — on the
copy nearest the top, the end calc pushes to."
  (let ((no (length old)) (nn (length new))
        (tail 0) (head 0))
    (let ((o (reverse old)) (n (reverse new)))
      (while (and o n (equal (car o) (car n)))
        (setq tail (1+ tail) o (cdr o) n (cdr n))))
    (let ((o old) (n new) (limit (- (min no nn) tail)))
      (while (and (< head limit) (equal (car o) (car n)))
        (setq head (1+ head) o (cdr o) n (cdr n))))
    (list head (- no tail head) (- nn tail head))))

(defun maf-history--classify (old new)
  "Label the change from OLD to NEW stack values, both top-first lists.
For a change with no trail prefix, name it structurally, off the region
`maf-history--diff' finds: `new' when one entry was added (the rest
unchanged, wherever it landed), `dupe' when that added entry is a copy
of one the stack already held, `edit' when exactly one value changed in
place, `del' when entries were removed, else `change' (several changes
at once, a reorder). Distinguishes adding an entry from editing one —
the common single-entry cases exactly, the rest best-effort."
  (pcase-let ((`(,index ,old-count ,new-count) (maf-history--diff old new)))
    (cond
     ((and (= old-count 0) (= new-count 1))
      (if (member (nth index new) old) "dupe" "new"))
     ((and (= old-count 1) (= new-count 1)) "edit")
     ((< (length new) (length old)) "del")
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
                       (t (maf-history--typed old raw prefix)))))
                (setq maf-history--last-raw raw)
                (maf-history--record (mapcar #'maf--strip-encasing raw)
                                      label this-command)))))))))

(defun maf-history--typed (old new prefix)
  "Classify OLD to NEW, reading a typed value as new input, not a copy.
`maf-history--classify' calls an added entry the stack already held a
duplication, which is what it looks like from the stack alone. Typing a
value that happens to be on the stack already is not one, though: the
user entered it rather than copying it, and the log's business is the
action. Calc tells the two apart without a roster of commands to keep —
an entry goes through `calc-record' and lands a trail line, so PREFIX
is a stashed (PREFIX) even when the prefix itself is nil, while the dup
commands push with `calc-push' and record nothing, leaving PREFIX nil."
  (let ((kind (maf-history--classify old new)))
    (if (and (equal kind "dupe") prefix) "new" kind)))

(defun maf-history--record (values label &optional command)
  "Record VALUES as the newest state, named LABEL and made by COMMAND.
Skipped when VALUES matches the newest state — a selection was made or
cleared, changing the entry conses but not the formulas — and when
VALUES is an empty stack with no history yet, so the log never starts
with an empty baseline."
  (unless (or (and maf-history--states
                   (equal values (nth 0 (car maf-history--states))))
              (and (null values) (null maf-history--states)))
    (push (list values label command) maf-history--states)
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

(defun maf-history--label (state)
  "Return the display string for STATE's label in the action log.
A trail-prefix string shows as-is and a command symbol as its name.
States with no named operation read as `entry' — a plain entry (nil
label) and calc's `...' continuation prefix (the extra values of a
multi-value push) — so unnamed steps stay legible and 1:1 with `u'/`i'."
  (let ((label (nth 1 state)))
    (cond ((member label '(nil "" "...")) "entry")
          ((stringp label) label)
          ((symbolp label) (symbol-name label))
          (t "entry"))))

(defun maf-history--command-name (state)
  "Return the name of the command that made STATE, or nil to show none.
The label names the operation and is what the log leads with — a trail
prefix like \"fctr\", or a structural reading like \"dupe\" — while the
command is the code that ran, which no prefix says. A label that is
already the command's name says it once and takes no echo; a state
recorded outside any command has no name to give."
  (let ((command (nth 2 state)))
    (and command
         (symbolp command)
         (let ((name (symbol-name command)))
           (and (not (equal name (maf-history--label state))) name)))))

(defun maf-history--marker (values older has-older)
  "Return (CHAR . FACE) marking how VALUES changed the stack from OLDER.
The kinds a git UI shows: `+' for a state that added an entry, `-' for
one that removed entries, `~' for one that changed the stack in place
— an entry edited, or several changes at once. HAS-OLDER says whether
OLDER is a state at all rather than merely an empty one; the oldest
recorded state has nothing to diff against and takes a neutral `·'.
The classification is `maf-history--classify's, so the marker and a
structural label agree by construction."
  (if (not has-older)
      (cons ?· 'shadow)
    (pcase (maf-history--classify older values)
      ((or "new" "dupe") (cons ?+ 'maf-history-added))
      ("del"             (cons ?- 'maf-history-removed))
      (_                 (cons ?~ 'maf-history-modified)))))

(defvar maf-history--controls nil
  "Commands summarized on the legend line, in order.
Each entry is (COMMAND VERB . PREFERRED-KEYS), the shape dial's
controls line uses (see `dial-default-controls'): COMMAND one command
or a list that reads as one control, and the keys the ones to show
for it, kept only while each still runs it.")

;; Set outside the defvar so a reload applies edits to the list.
;; n/p/j/k and </> move within whichever window they are pressed in —
;; between states in the log, between lines in the stack — so each
;; control names both meanings and the legend stays true wherever it
;; is rendered. It names n/p and < >, leaving j/k and C-< / C-> as
;; unadvertised aliases rather than spending the width on every pair.
(setq maf-history--controls
      '(((maf-history-previous maf-history-next next-line previous-line)
         "move" "n" "p")
        ((maf-history-oldest maf-history-newest
          maf-history-stack-first maf-history-stack-last)
         "ends" "<" ">")
        ;; TAB crosses too, by naming the side it leads to rather than
        ;; toggling, so it belongs to this control even though it runs a
        ;; different command in each window — which is also why the
        ;; commands are listed: a preferred key is kept only while it
        ;; still runs one of them.
        ((maf-history-switch maf-history-focus-log maf-history-focus-stack)
         "switch" "TAB" "o" "t")
        (maf-history-insert "insert" "RET")
        (maf-history-restore "restore" "r" "RET")
        (maf-history-delete "delete" "D")
        ;; Beside D, the one state at a time it is the whole-log
        ;; counterpart of; the chord is what keeps the two apart on the
        ;; keyboard, so the legend showing it is what says the wipe is
        ;; deliberately out of fingerslip range.
        (maf-history-clear "clear" "C-M-k")
        (maf-history-quit "quit" "q")))

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
  "Return the key legend, the header line over the stack window.
The shape of the *maf-options* controls line: each control's keys in
the binding face, its verb after. Keys are looked up in the current
buffer's live keymaps, so the legend follows a rebinding — and shows
the keys that window actually uses, the two browsing maps differing on
a few. It heads the stack window rather than the log because that is
the wide one; the pair is one UI, and the keys drive both.

Controls are set two spaces apart rather than three: the line has
grown past what three would fit, and the keys carry `help-key-binding'
while the verbs are plain, so the two already read apart without the
extra column. A header line truncates rather than wraps, so the width
it costs comes off the end of the line."
  (concat
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
    "  ")))

(defun maf-history--render-log ()
  "Render the action log into the current buffer, the browser's left window.
One line per recorded state, newest at the top and oldest at the
bottom, so the latest work is where the eye starts. Each line is a
change marker (see `maf-history--marker') and the action that produced
the state — its label, and after it the command that ran (see
`maf-history--command-name') — the current one marked and on
`maf-history-current'. Each line carries its state's index, so point
lands on a state rather than merely near one, and point is left on the
current line — in the log the selection is where point is. The header
line carries the position counter."
  (let ((total (length maf-history--states))
        (index maf-history--index)
        (target nil)
        (inhibit-read-only t))
    (erase-buffer)
    (if (null maf-history--states)
        (insert (propertize "(no states yet)" 'face 'shadow) "\n")
      (dotimes (i total)
        (let* ((state (nth i maf-history--states))
               (has-older (< (1+ i) total))
               (marker (maf-history--marker
                        (nth 0 state)
                        (and has-older (nth 0 (nth (1+ i) maf-history--states)))
                        has-older))
               (current (= i index))
               (start (point)))
          (insert (if current "▸ " "  "))
          (let ((mstart (point)))
            (insert (car marker) " ")
            (put-text-property mstart (1+ mstart) 'face (cdr marker)))
          (insert (maf-history--label state))
          ;; The command that ran, after the operation it goes by, in
          ;; the parentheses an elisp name is read in. On `shadow', so
          ;; the label still carries the line and the name reads as the
          ;; footnote it is; the log truncates rather than wraps, so a
          ;; narrow window drops the echo and keeps the label.
          (when-let ((name (maf-history--command-name state)))
            (insert " " (propertize (format "(%s)" name) 'face 'shadow)))
          (insert "\n")
          (put-text-property start (point) 'maf-history-index i)
          (when current
            ;; Appended, so the marker keeps its own colour and only
            ;; picks up the current state's weight.
            (add-face-text-property start (point) 'maf-history-current t)
            (setq target start)))))
    (setq header-line-format
          (if (zerop total) "maf-history"
            (format "maf-history  %d/%d" (- total index) total)))
    (goto-char (or target (point-min)))
    (dolist (win (get-buffer-window-list nil nil t))
      (set-window-point win (point)))))

(defun maf-history--render-stack (&optional follow)
  "Render the selected state\='s stack into the current buffer, the right window.
Rendered as calc renders the stack, deepest entry first, with the
entries this step produced highlighted — the region `maf-history--diff'
finds against the state before it, so a duplicate highlights the copy
it added rather than nothing at all; the oldest state has no reference
to diff against and highlights nothing. Every line carries its entry\='s
value, so RET works anywhere on the row, continuation lines of a
multi-line entry included. The header line carries the key legend (see
`maf-history--legend').

Point keeps its line and column, so a re-render under an unchanged
selection leaves it be; with FOLLOW non-nil — the selection moved, or
a fresh buffer — it moves to the top-of-stack entry, the likeliest
RET target."
  (let* ((total (length maf-history--states))
         (index maf-history--index)
         (state (nth index maf-history--states))
         (values (nth 0 state))
         ;; The older state itself, not its values: a state whose stack
         ;; was empty is still something to diff against, and everything
         ;; here is then new.
         (prev (and (< (1+ index) total)
                    (nth (1+ index) maf-history--states)))
         (fresh (zerop (buffer-size)))
         (line (line-number-at-pos))
         (col (current-column))
         (target nil)
         (inhibit-read-only t))
    (erase-buffer)
    (cond
     ((null state)
      (insert (propertize "(no states yet)" 'face 'shadow) "\n"))
     ((null values)
      (insert (propertize "(empty stack)" 'face 'shadow) "\n"))
     (t
      ;; Which entries this step produced is a matter of position, not of
      ;; membership: duplicating an entry leaves a copy that the state
      ;; before it also held, and that copy is exactly what to highlight.
      (pcase-let* ((`(,from ,_ ,count) (if prev
                                           (maf-history--diff (nth 0 prev) values)
                                         (list 0 0 0)))
                   (level (length values)))
        (dolist (val (reverse values))
          (let* ((entry (1- level))
                 (changed (and (>= entry from) (< entry (+ from count)))))
            (setq target (point))
            (let ((start (point)))
              (insert (maf-history--format-entry val level) "\n")
              (put-text-property start (point) 'maf-history-value val)
              (when changed
                (put-text-property start (point)
                                   'face 'maf-history-changed))))
          (setq level (1- level))))))
    (setq header-line-format (maf-history--legend))
    (if (not (or fresh follow))
        (progn (goto-char (point-min))
               (forward-line (1- line))
               (move-to-column col))
      ;; `target' is the last entry written, which is level 1.
      (goto-char (or target (point-min))))
    ;; Windows showing the buffer keep their own point; move it too, so
    ;; the stack beside the log follows the selection even while the
    ;; log window is the selected one.
    (dolist (win (get-buffer-window-list nil nil t))
      (set-window-point win (point)))))

(defun maf-history--render (&optional follow)
  "Render the browser: the action log and the selected state\='s stack.
Each goes to its own buffer, whichever of the two exist (see
`maf-history--render-log' and `maf-history--render-stack'); FOLLOW is
passed to the stack, moving its point onto the top-of-stack entry.
The index is clamped here, so both views render the same selection."
  (let ((total (length maf-history--states)))
    (setq maf-history--index
          (max 0 (min maf-history--index (max 0 (1- total))))))
  (when-let ((buf (get-buffer maf-history--log-buffer)))
    (with-current-buffer buf (maf-history--render-log)))
  (when-let ((buf (get-buffer maf-history--stack-buffer)))
    (with-current-buffer buf (maf-history--render-stack follow))))

(defun maf-history--refresh (&optional new)
  "Re-render the browser, if it is open.
With NEW non-nil a state was just recorded: a view on the newest state
follows to the new one; a view on an older state stays on that state,
its index shifted under it. The new line lands at the top of the log
and the rest move down a row, but the log puts point back on the
selected state either way."
  (when (get-buffer maf-history--log-buffer)
    (let ((follow (and new (zerop maf-history--index))))
      (when (and new (> maf-history--index 0))
        (setq maf-history--index (1+ maf-history--index)))
      (maf-history--render follow))))

;;; The buffer

(defvar maf-history-mode-map (make-sparse-keymap)
  "Keymap for `maf-history-mode', the action log window.")

(defvar maf-history-stack-mode-map (make-sparse-keymap)
  "Keymap for `maf-history-stack-mode', the stack window.
Inherits `maf-history-mode-map', so the browsing, restore and quit
keys work from either window; what it overrides is the keys that must
mean something else beside a stack — line motion and RET.")

;; Bindings live outside the defvars so reloading the file applies edits
;; to the existing maps.

;; The log: every line is a state, so plain motion and stepping are the
;; same thing, and the keys follow the display rather than the clock.
;; The log runs newest-at-top, so down (j/n) walks back in time and up
;; (k/p) walks forward — the way n/p move through the items of any
;; Emacs list buffer, whatever order the list is in.
(define-key maf-history-mode-map (kbd "j") #'maf-history-previous)
(define-key maf-history-mode-map (kbd "n") #'maf-history-previous)
(define-key maf-history-mode-map (kbd "k") #'maf-history-next)
(define-key maf-history-mode-map (kbd "p") #'maf-history-next)
(define-key maf-history-mode-map (kbd "M-n") #'maf-history-previous)
(define-key maf-history-mode-map (kbd "M-p") #'maf-history-next)
;; The ends follow the display too, as the step keys do: the log runs
;; newest-first, so < reaches the top of it and > the bottom. C-< and
;; C-> are the same two under a modifier, for a hand already holding
;; control down; they are GUI events a terminal cannot deliver, so the
;; unmodified pair stays the one the legend names and the one a tty
;; has.
(define-key maf-history-mode-map (kbd "<") #'maf-history-newest)
(define-key maf-history-mode-map (kbd ">") #'maf-history-oldest)
(define-key maf-history-mode-map (kbd "C-<") #'maf-history-newest)
(define-key maf-history-mode-map (kbd "C->") #'maf-history-oldest)
;; Either of these crosses between the two windows, either way.
(define-key maf-history-mode-map (kbd "o") #'maf-history-switch)
(define-key maf-history-mode-map (kbd "t") #'maf-history-switch)
(define-key maf-history-mode-map (kbd "TAB") #'maf-history-focus-stack)
;; RET on a log row takes that state: choosing an item from the log is
;; choosing the stack it names, as RET on a completion candidate takes
;; it. Picking one entry out of a state instead is RET in the stack.
(define-key maf-history-mode-map (kbd "RET") #'maf-history-restore)
(define-key maf-history-mode-map (kbd "r") #'maf-history-restore)
;; Capital, so a fingerslip on the motion keys cannot reach a delete.
(define-key maf-history-mode-map (kbd "D") #'maf-history-delete)
;; A deliberate chord for wiping the whole log, well out of fingerslip
;; range of the single-key commands.
(define-key maf-history-mode-map (kbd "C-M-k") #'maf-history-clear)
;; ? describes the command a row names, the reading that makes the
;; echoed command name useful rather than only informative. It shadows
;; the `describe-mode' special-mode puts here, which stays on h.
(define-key maf-history-mode-map (kbd "?") #'maf-history-describe-command)
(define-key maf-history-mode-map (kbd "q") #'maf-history-quit)

;; The stack: the same keys navigate this buffer instead of the log —
;; n/j down a line, p/k up, </> to the ends — so they always move
;; within the window the hand is in. Stepping states is the log's job;
;; t crosses back to it. Everything not overridden here (t, r, D, q,
;; C-M-k) is inherited and works from either window.
(set-keymap-parent maf-history-stack-mode-map maf-history-mode-map)
(define-key maf-history-stack-mode-map (kbd "n") #'next-line)
(define-key maf-history-stack-mode-map (kbd "j") #'next-line)
(define-key maf-history-stack-mode-map (kbd "p") #'previous-line)
(define-key maf-history-stack-mode-map (kbd "k") #'previous-line)
(define-key maf-history-stack-mode-map (kbd "<") #'maf-history-stack-first)
(define-key maf-history-stack-mode-map (kbd ">") #'maf-history-stack-last)
(define-key maf-history-stack-mode-map (kbd "C-<") #'maf-history-stack-first)
(define-key maf-history-stack-mode-map (kbd "C->") #'maf-history-stack-last)
(define-key maf-history-stack-mode-map (kbd "RET") #'maf-history-insert)
(define-key maf-history-stack-mode-map (kbd "C-<return>")
            #'maf-history-insert-stay)
(define-key maf-history-stack-mode-map (kbd "TAB") #'maf-history-focus-log)

(define-derived-mode maf-history-mode special-mode "maf-history"
  "Major mode for the calc stack history\='s action log.
The left window of the browser: one line per recorded state, newest at
the top, each a change marker (+ added, - removed, ~ changed in place)
and the action that produced it — the operation it goes by, and after
it the command that ran — the current one marked.
The stack that action left shows in `maf-history-stack-mode' beside
it, following point as it moves. \<maf-history-mode-map>
\[maf-history-previous] steps to older states and \[maf-history-next]
to newer ones; \[maf-history-oldest] and \[maf-history-newest] jump
to the ends. \[maf-history-restore] takes the state at point, making
it the live stack again, and quits. \[maf-history-switch] crosses into
the stack instead, to take one entry out of a state rather than the
whole of it. \[maf-history-delete] deletes the state shown from the
log; \[maf-history-clear] clears the whole log.
\[maf-history-describe-command] describes the command the row at point
names, and \[describe-mode] this help. \[maf-history-quit] buries the
browser."
  (setq truncate-lines t)
  (setq-local revert-buffer-function
              (lambda (&rest _) (maf-history--render))))

(define-derived-mode maf-history-stack-mode special-mode "maf-stack"
  "Major mode for the stack of the state selected in the history log.
The right window of the browser, rendered as calc renders the stack,
with the entries the selected step produced highlighted.
\<maf-history-stack-mode-map>
\[maf-history-insert] pushes the entry at point onto the live stack
and quits; \[maf-history-insert-stay] pushes and stays, ready to
insert more. The motion keys move between the entries of this stack
rather than between states — stepping states is the log's job, and
\[maf-history-switch] crosses back to it."
  (setq truncate-lines t)
  (setq-local revert-buffer-function
              (lambda (&rest _) (maf-history--render))))

(defun maf-history--stack-buffer ()
  "Return the stack buffer, creating it if needed."
  (or (get-buffer maf-history--stack-buffer)
      (with-current-buffer (get-buffer-create maf-history--stack-buffer)
        (maf-history-stack-mode)
        (current-buffer))))

(defun maf-history--buffer ()
  "Return the action log buffer, creating the browser\='s pair if needed.
The log and the stack beside it are one UI, so this makes both and
renders them; the windows are `maf-history\='s business."
  (or (get-buffer maf-history--log-buffer)
      (with-current-buffer (get-buffer-create maf-history--log-buffer)
        (maf-history-mode)
        (maf-history--stack-buffer)
        (maf-history--render t)
        (current-buffer))))

;;;###autoload
(defun maf-history ()
  "Browse the stack history in two windows below calc, and select the log.
The action log opens on the left, `maf-history-log-width' columns
wide, and the stack of the selected state on the right. The view
always starts on the newest state, wherever a previous browse left it.
Windows already showing either buffer are reused as they stand;
without a calc window the pair opens below the selected window."
  (interactive)
  (let ((log (maf-history--buffer))
        (stack (maf-history--stack-buffer)))
    (setq maf-history--index 0)
    (maf-history--render t)
    (let ((logwin (or (get-buffer-window log)
                      (let* ((calc-buf (maf--find-calc-buffer))
                             (calc-win (and calc-buf (get-buffer-window calc-buf))))
                        (with-selected-window (or calc-win (selected-window))
                          (display-buffer log '(display-buffer-below-selected)))))))
      (unless (get-buffer-window stack)
        ;; Measured before the split, so the share is of the whole
        ;; space the pair ends up sharing.
        (let ((total (window-width logwin)))
          ;; `display-buffer' rather than a hand-rolled `split-window':
          ;; it records the quit-restore parameter, so `maf-history-quit'
          ;; takes the window back down instead of leaving it behind
          ;; showing whatever was there before.
          (with-selected-window logwin
            (display-buffer stack '((display-buffer-in-direction)
                                    (direction . right))))
          ;; The split halves the log window; give it its share instead.
          (when (window-live-p logwin)
            (let ((delta (- (max window-min-width
                                 (round (* total maf-history-log-width)))
                            (window-width logwin))))
              (unless (zerop delta)
                (ignore-errors (window-resize logwin delta t)))))))
      ;; Both buffers were rendered before their windows existed, so
      ;; each window still holds a stale point of its own.
      (dolist (buf (list log stack))
        (dolist (win (get-buffer-window-list buf nil t))
          (set-window-point win (with-current-buffer buf (point)))))
      (select-window logwin))))

(defun maf-history-focus-log ()
  "Select the window showing the action log."
  (interactive)
  (select-window (or (get-buffer-window (maf-history--buffer))
                     (progn (maf-history) (selected-window)))))

(defun maf-history-focus-stack ()
  "Select the window showing the selected state\='s stack."
  (interactive)
  (let ((win (get-buffer-window (maf-history--stack-buffer))))
    (unless win (maf-history) (setq win (get-buffer-window maf-history--stack-buffer)))
    (when win (select-window win))))

(defun maf-history-stack-first ()
  "Move to the deepest entry of the stack shown."
  (interactive)
  (goto-char (point-min)))

(defun maf-history-stack-last ()
  "Move to the top-of-stack entry of the stack shown.
Not `end-of-buffer': every entry line ends in a newline, so that lands
on the empty line past the last one, where there is no entry for RET
to push."
  (interactive)
  (goto-char (point-max))
  (forward-line (if (bolp) -1 0))
  (beginning-of-line))

(defun maf-history--state-at-point ()
  "Return the state point names, else the one the browser has selected.
Every log row carries its state's index, so in the log this is the row
under point even where point has drifted off the selection. The stack
window has no rows of states to read, and there falls back to the
selected state, which is the one it is showing."
  (let ((index (or (get-text-property (point) 'maf-history-index)
                   maf-history--index)))
    (nth index maf-history--states)))

(defun maf-history-describe-command ()
  "Describe the command that produced the state at point.
The log names the operation and echoes the command that ran beside it
\(see `maf-history--command-name'); this opens that command's own help,
so a name read off the log leads to what it does without leaving the
browser to look it up. Point picks the state in the log; the stack
window describes the state it is showing.

On \\`?', where `special-mode' puts `describe-mode'. The mode's own
help stays on \\`h', which runs it too."
  (interactive)
  (let* ((state (or (maf-history--state-at-point)
                    (user-error "No states recorded yet")))
         (command (nth 2 state)))
    (unless (and command (symbolp command) (fboundp command))
      (user-error "No command recorded for this state (%s)"
                  (maf-history--label state)))
    (describe-function command)))

(defun maf-history-switch ()
  "Switch between the action log and the stack beside it.
Selects whichever of the browser's two windows is not the current
one, so one key crosses either way. `maf-history-focus-log' and
`maf-history-focus-stack' name a side instead; TAB runs whichever of
them leads out of the window it is pressed in."
  (interactive)
  (if (derived-mode-p 'maf-history-stack-mode)
      (maf-history-focus-log)
    (maf-history-focus-stack)))

(defun maf-history-quit ()
  "Bury the browser, quitting both its windows.
The log and the stack are one UI, so quitting from either takes both
down; the recorded history itself is untouched."
  (interactive)
  (dolist (name (list maf-history--stack-buffer maf-history--log-buffer))
    (when-let ((buf (get-buffer name)))
      (dolist (win (get-buffer-window-list buf nil t))
        (quit-window nil win)))))

(defun maf-history-visit-calc ()
  "Select the calc window, leaving the browser's windows open.
Without a window showing calc, one is found for it."
  (interactive)
  (let ((buf (or (maf--find-calc-buffer)
                 (user-error "No calc buffer found"))))
    (select-window (or (get-buffer-window buf)
                       (display-buffer buf)))))

;;; Browsing commands

(defun maf-history--move (n)
  "Select the state N steps older (newer when N is negative).
Both windows re-render on the new selection: the log moves its mark
and point onto it, the stack shows what it left."
  (unless maf-history--states (user-error "No states recorded yet"))
  (let* ((max (1- (length maf-history--states)))
         (target (max 0 (min (+ maf-history--index n) max))))
    (when (= target maf-history--index)
      (user-error (if (> n 0) "Already at the oldest state"
                    "Already at the newest state")))
    (setq maf-history--index target)
    (maf-history--render t)))

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
Point is in the stack window, on the entry to take. The value is
pushed on top as a new entry — a copy, so later edits to the live
entry never reach back into the history — and recorded in the history
as its own step. The browser quits, as after choosing from a list;
`maf-history-insert-stay' keeps it open."
  (interactive)
  (maf-history-insert-stay)
  (maf-history-quit))

(defun maf-history-insert-stay ()
  "Push the history entry at point onto the live calc stack.
As `maf-history-insert', but the browser stays open with point in
place, ready to insert more."
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
restore. The browser quits, as after `maf-history-insert': a restore
is the end of a browse."
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
      (maf-history--render t)
      (message "Stack restored (%d %s)" (length values)
               (if (= (length values) 1) "entry" "entries"))
      (maf-history-quit))))

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
      (maf-history--render t)
      (message "Deleted state %d/%d (%s)" (- total index) total
               (maf-history--label state)))))

(defun maf-history-clear ()
  "Discard every recorded stack state, keeping the live stack.
The history is a log of what happened rather than part of the calc
state, so nothing here is undoable and the stack is untouched — the
next change starts a fresh log, baselined against the stack as it
stands. Recording carries on if it was on; this only empties what was
recorded. Nothing else empties the log — `maf-reset' wipes the session
but deliberately leaves the history standing — so this is the one way
to discard it.

In the browser this is on \\`C-M-k' — a deliberate chord, so wiping
the whole log stays well out of fingerslip range of \\`D''s one state
at a time."
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
    (setq maf-history--index 0)
    (maf-history--render t)
    (when (called-interactively-p 'interactive)
      (message "History cleared (%d %s)" n (if (= n 1) "state" "states")))
    n))

;;; The module

;;;###autoload
(define-minor-mode maf-use-history-mode
  "Record and browse earlier versions of the Calc stack.

Each command that changes the stack saves a snapshot. Press M-h to
open the browser: the action log on the left, the stack of the
selected action on the right. There, n and p move through snapshots,
l crosses to the stack where RET pushes the entry at point onto the
current stack, r restores the whole snapshot, D deletes it from the
history, and C-M-k clears the whole log.

For example, after several calculations you can return to the stack as
it looked before the last three commands, or copy just one old entry.

Turning this mode off stops recording. Snapshots already recorded stay
available until they are deleted or Emacs exits."
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
    (maf-bindings--refresh)))

;; M-h: h for history, a single chord for the browse the history is
;; for. It shadows only the global `mark-paragraph', which has no
;; meaning in the stack buffer. Calc's trail and its `t' bindings
;; (t d and friends) stay untouched — the history is an alternative
;; to the trail, not a replacement.
(maf-bindings-module-keys 'maf-history 'maf-use-history-mode
  '(((calc native vim) "M-h" maf-history)))

;; Register with the module system when it is present; the mode above
;; works on its own without it.
(when (require 'maf-module nil t)
  (maf-register-module 'maf-history #'maf-use-history-mode
                       "Browse past stack states and bring any of them back.

Every stack change records a snapshot. Press M-h to browse them: the
log of actions on the left, the stack each one left on the right. Use
n and p to move through time, l then RET to copy one old entry, or r
to restore the whole stack."
                       "M-h" "Memory"))

(provide 'maf-history)
