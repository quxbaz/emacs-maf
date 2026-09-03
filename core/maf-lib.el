;; -*- lexical-binding: t; -*-
;;
;; maf-lib.el
;;
;; maf library functions

(require 'calc)
(require 'cl-lib)

;; Defined in lazily-loaded calc modules; calc-ext's autoload registry
;; resolves them at runtime, but the byte compiler needs declarations.
(declare-function calc-push "calc-ext")
(declare-function calc-top "calc-ext")
(declare-function calc-locate-cursor-element "calc-yank")
(declare-function calc-prepare-selection "calc-sel")
(declare-function calc-find-selected-part "calc-sel")
;; maf-comp requires maf-lib; declared to avoid the circular require.
(declare-function maf--comp-node-anchor-pos "maf-comp")
(declare-function maf--comp-node-start-pos "maf-comp")
(declare-function math-read-expr "calc-aent")

;; calc-sel declares this with a valueless defvar, which marks it
;; special only within its own file; redeclare so our read is dynamic.
(defvar calc-selection-cache-offset)

(defun maf--find-calc-buffer ()
  "Find the calc buffer.
Prefers the current buffer if it is in calc-mode, then the buffer named
*Calculator* provided it really is in calc-mode, then falls back to any
live buffer in calc-mode (catching a renamed calc buffer)."
  (cond
   ((derived-mode-p 'calc-mode) (current-buffer))
   ((let ((buf (get-buffer "*Calculator*")))
      (and buf
           (with-current-buffer buf (derived-mode-p 'calc-mode))
           buf)))
   (t (cl-find-if (lambda (buf)
                    (with-current-buffer buf (derived-mode-p 'calc-mode)))
                  (buffer-list)))))

(defmacro maf--with-calc-buffer (&rest body)
  "Evaluate BODY in the calc buffer.
Signals an error if no calc buffer exists."
  (declare (indent 0))
  `(with-current-buffer (or (maf--find-calc-buffer)
                            (error "No calc buffer found"))
     ,@body))

(defun maf--at-home-p ()
  "Return t if point is past the last stack entry (at the . line or below)."
  (maf--with-calc-buffer
    (<= (calc-locate-cursor-element (point)) 0)))

(defun maf--at-line-prefix-p ()
  "Return t if point is in the line-number prefix (e.g. '1: ') of a stack entry."
  (maf--with-calc-buffer
    (and (> (calc-locate-cursor-element (point)) 0)
         (not (eolp))
         (save-excursion
           (let ((col (current-column)))
             (beginning-of-line)
             (and (looking-at " *[0-9]+: +")
                  (< col (- (match-end 0) (point)))))))))

(defun maf--at-right-margin-p ()
  "Return t if point is at EOL on a stack entry line.
The far side of the formula text: past everything written, where a
command may read the position as carrying on rather than as pointing
at what is there."
  (maf--with-calc-buffer
    (and (> (calc-locate-cursor-element (point)) 0)
         (eolp))))

(defun maf--at-line-margin-p ()
  "Return t if point is in the line-prefix zone or at EOL on a stack entry line.
Marks the positions outside the formula text — used by the entry target in
the resolve cascade."
  (or (maf--at-right-margin-p) (maf--at-line-prefix-p)))

(defun maf--at-subexpr-p ()
  "Return t if point is on a sub-expression within an entry's formula text.
False when point is at EOL or in the line-prefix zone, even if there is a
sub-expression on the line; those positions route to equation/entry targets."
  (maf--with-calc-buffer
    (and (> (calc-locate-cursor-element (point)) 0)
         (not (maf--at-line-margin-p))
         (save-excursion
           (ignore-errors
             (calc-prepare-selection)
             (and (calc-find-selected-part) t))))))

(defun maf--strip-encasing (expr)
  "Strip the (cplx N 0) wrappers that `calc-encase-atoms' leaves in EXPR.
Selection machinery (maf-hl included) encases entry atoms in place; this
undoes it structurally, without re-normalizing the formula — unlike
`math-normalize', it cannot reorder or re-simplify anything."
  (cond
   ((and (eq (car-safe expr) 'cplx) (equal (nth 2 expr) 0))
    (maf--strip-encasing (nth 1 expr)))
   ((consp expr)
    (cons (car expr) (mapcar #'maf--strip-encasing (cdr expr))))
   (t expr)))

(defun maf--node-path (root node)
  "Return NODE's path within ROOT as (t . INDICES), or nil when it is absent.
NODE is matched by `eq', so it must be a cons taken from ROOT itself —
the encased node `calc-find-selected-part' returns, not a copy. Each
index is an operand position (1 for the first operand), so the path is
`(t)' for ROOT itself and `(t 2 1)' for the second operand's first.
Unlike `eq' on the nodes, a path survives a rebuild of the tree: the
encased copy `calc-prepare-selection' caches and the clean one a
command body sees are walked by the same indices."
  (cl-labels ((walk (cur path)
                (cond ((eq cur node) (cons t (nreverse path)))
                      ((consp cur)
                       (let ((i 0) found)
                         (dolist (kid (cdr cur) found)
                           (setq i (1+ i))
                           (unless found
                             (setq found (walk kid (cons i path))))))))))
    (walk root nil)))

(defun maf--splice-path (expr path fn)
  "Return EXPR with the node at PATH replaced by FN\='s value on it.
PATH is a list of operand indices as `maf--node-path' returns them (its
`t' head dropped); the empty path names EXPR itself. Structural: the
nodes along the way are copied rather than mutated, and nothing is
re-normalized."
  (if (null path)
      (funcall fn expr)
    (let ((copy (copy-sequence expr)))
      (setf (nth (car path) copy)
            (maf--splice-path (nth (car path) expr) (cdr path) fn))
      copy)))

(defun maf--value-list-p (val)
  "Non-nil when VAL is a list of values rather than one expression.
The shape a body commits when it means several stack entries — the
parts `mafcmd-unpack' spreads. Every calc expression is either a
number or a list headed by a symbol (`vec', `var', a `calcFunc-'
name, an operator), so a list whose head is not a symbol is a list of
them."
  (and (consp val) (not (symbolp (car val)))))

(defmacro maf--literal (&rest body)
  "Evaluate BODY with simplification off: it builds the shape that commits.
`maf--commit' pushes structurally — it hands the value to
`calc-pop-push-record-list', which does not run `calc-normalize' on
the way out — so whatever the body produces lands verbatim. Building
under `calc-simplify-mode' `none' is what keeps a deliberately
literal form intact: a factored product stays factored instead of
being distributed back out, a single fraction stays one fraction
instead of spreading over its terms.

Wraps only the construction of the result. The algebra that computes
the parts runs outside, in whatever mode is in effect, since that
stage does need to simplify."
  (declare (indent 0) (debug t))
  `(let ((calc-simplify-mode 'none)) ,@body))

(defun maf--relation-p (expr)
  "Return t if EXPR is a relation (=, !=, <, <=, >, >=)."
  (and (consp expr)
       (memq (car expr) '(calcFunc-eq calcFunc-neq calcFunc-lt
                          calcFunc-leq calcFunc-gt calcFunc-geq))
       t))

(defun maf--at-equation-p ()
  "Return t if the stack entry under point is a relation (=, !=, <, <=, >, >=)."
  (maf--with-calc-buffer
    (let ((idx (calc-locate-cursor-element (point))))
      (and (> idx 0)
           (maf--relation-p (calc-top idx 'full))))))

(defun maf--point-snapshot ()
  "Capture point's placement in the current calc buffer as an alist.
Records the buffer position (:pos), line (:line), column (:col), and
semantic affinity (:affinity): `home' when point is at or below the
. line, `eol' at end of line, `bol' in the line-number prefix, else
nil. Consumed by `maf--point-restore'."
  `((:pos      . ,(point))
    (:line     . ,(line-number-at-pos))
    (:col      . ,(current-column))
    (:affinity . ,(cond ((maf--at-home-p) 'home)
                        ((eolp) 'eol)
                        ((maf--at-line-prefix-p) 'bol)))))

(defun maf--point-restore-anchor (index landed)
  "Put point on the INDEX-th structural glyph of the committed node.
LANDED is `maf--commit's return alist (:node, :m). Return the new
position, or nil when the node's entry or its glyphs can't be located
\(entry consumed, non-flat rendering) — the caller then falls back to
the positional restore."
  (ignore-errors
    (let ((node (alist-get :node landed))
          (m    (alist-get :m landed)))
      (when (and node (integerp m) (>= m 1))
        (calc-prepare-selection m)
        (when-let ((pos (maf--comp-node-anchor-pos node index)))
          (goto-char pos))))))

(defun maf--point-restore-start (landed)
  "Put point on the first character of the committed node's rendering.
LANDED is `maf--commit's return alist (:node, :m). Where
`maf--point-restore-anchor' keeps point on the glyph it was on — right
for a command that rewrites the node in place — this lands on the node
itself, which is what a command that puts a *different* value in the
slot wants: point on what arrived, not on a column the old node's
shape happened to hold. Works for atoms too, which have no structural
glyphs. Return the new position, or nil when the node can't be located
\(entry consumed, non-flat rendering) — the caller then falls back to
the positional restore."
  (ignore-errors
    (let ((node (alist-get :node landed))
          (m    (alist-get :m landed)))
      (when (and node (integerp m) (>= m 1))
        (calc-prepare-selection m)
        (when-let ((pos (maf--comp-node-start-pos node)))
          (goto-char pos))))))

(defun maf--point-restore-head (landed)
  "Put point on the glyph that names the committed node whole.
LANDED is `maf--commit's return alist (:node, :m). Where
`maf--point-restore-start' lands on the node's first character — which
for 2 x + 1 is the atom 2 — this lands on its operator, function name,
or opening bracket (`maf--comp-node-head-pos'), so that point names the
node itself: what a command that puts a different node in the slot
wants when the next command is meant to take that node whole. Return
the new position, or nil when the node can't be located (entry
consumed, non-flat rendering) — the caller then falls back."
  (ignore-errors
    (let ((node (alist-get :node landed))
          (m    (alist-get :m landed)))
      (when (and node (integerp m) (>= m 1))
        (calc-prepare-selection m)
        (when-let ((pos (maf--comp-node-head-pos node)))
          (goto-char pos))))))

(defun maf--point-restore-margin (col)
  "Put point back at COL within the current line's line-number margin.
The margin is the only part of the line whose width the stack's own
numbering controls, and it changes under the user: a push past entry 9
widens every prefix by a column. So COL is clamped into the margin as
it now stands, keeping point in the margin without normalizing away
where in it the user was. Falls back to the line's start when the line
no longer carries a prefix at all."
  (beginning-of-line)
  (when (and col (looking-at " *[0-9]+: +"))
    (move-to-column (min col (- (match-end 0) (point) 1)))))

(defun maf--goto-entry-text (m)
  "Put point on the first character of entry M's formula text.
The formula starts past the line-number prefix, whose width the stack's
own numbering controls; the selection cache's offset measures it for the
entry as it now stands, multi-line renderings included. Returns point."
  (calc-prepare-selection m)
  (calc-cursor-stack-index m)
  (goto-char (+ (point) calc-selection-cache-offset)))

(defun maf--point-restore (snapshot)
  "Restore point from SNAPSHOT (see `maf--point-snapshot').
Calc commands that rewrite the stack buffer park point at home; this
puts it back where the user had it. A `home' snapshot is a no-op —
calc's default placement already matches. Otherwise point returns to
its previous buffer position, corrected back to the original line when
the rewrite shifted it. EOL affinity is re-applied on the line rather
than at the exact position, since the line's end moves with the
formula; BOL affinity keeps its column within the line-number margin
\(see `maf--point-restore-margin').

This is the placement of last resort: it reproduces a column, which
survives a rewrite only by luck. A command that knows where its result
landed restores through `maf--point-restore-commit' instead."
  (let ((affinity (alist-get :affinity snapshot)))
    (unless (eq affinity 'home)
      (goto-char (alist-get :pos snapshot))
      (let ((line (alist-get :line snapshot)))
        (when (/= (line-number-at-pos) line)
          (goto-char (point-min))
          (forward-line (1- line))
          ;; The raw position spilled onto another line — the
          ;; rewrite changed the text before it — so the position
          ;; is meaningless; recover the column instead (clamped
          ;; to the line's end when it shrank).
          (when-let ((col (alist-get :col snapshot)))
            (move-to-column col))))
      (pcase affinity
        ('eol (end-of-line))
        ('bol (maf--point-restore-margin
               (alist-get :col snapshot)))))))

(defun maf--point-stick-p (context)
  "Return non-nil when point should follow the node CONTEXT's command committed.
On the part targets point is the gesture that named the sub-formula, so
after the rewrite it belongs on whatever took that slot: a command
chained onto the same node (2 / then 1 +) must still resolve that node,
which a column restored across a formula that changed width does not
promise. The whole-entry targets — home, entry, equation — are not
selected by point this way, and keep the placement their margin or EOL
affinity asks for.

Two part-target cases opt out. `:keep' left the originals alone and
pushed the result as a new entry, so the entry under point is still the
one the user was reading. `:widened' means the command acted on an
ancestor of the node point was in (see `maf--resolve-widen'), whose
rendering can start far from where the user was looking."
  (and (memq (alist-get :target context) '(subexpr selection region))
       (not (alist-get :keep context))
       (not (alist-get :widened context))))

(defun maf--point-land-head-p (context)
  "Return non-nil when CONTEXT's command asked for the head-glyph landing.
A `:land head' command lands point on the glyph that names its
committed node whole (`maf--point-restore-head') — on the part targets
only, where point is the gesture that named the slot, and not under
`:keep', which left the entry under point alone and pushed the result
above it."
  (and (eq (alist-get :land context) 'head)
       (memq (alist-get :target context) '(subexpr selection region))
       (not (alist-get :keep context))))

(defun maf--point-restore-spread (context landed)
  "Place point after a commit spread a value list over the stack.
LANDED is `maf--commit's return alist with a :spread count of two or
more: the parts landed one entry each, the last of them at level :m.
\(A list of one part replaced its entry in place, and lands like any
single value.) The entry point
was on is gone, its parts standing where it stood and below, so its end
is now the end of the last part — point goes there, the way the EOL
affinity would have carried it had the entry stayed one line. In the
line-number margin point keeps to the margin, on the last part's line
\(see `maf--point-restore-margin'). Point at home stays at home, as it
does for any command. Return the new position, or nil when the last
part's line cannot be located — the caller then falls back to the
positional restore."
  (let ((m (alist-get :m landed))
        (snapshot (alist-get :point context)))
    (unless (eq (alist-get :affinity snapshot) 'home)
      (ignore-errors
        (when (and (integerp m) (>= m 1) (<= m (calc-stack-size)))
          ;; The line below entry M starts the entry beneath it (the .
          ;; line, for the top), so the character before that line's
          ;; start ends M's rendering, however many lines it takes. A
          ;; rendering may end in blank lines — Big language spaces its
          ;; entries so — and the end of the part is the end of its last
          ;; line with anything on it.
          (calc-cursor-stack-index (1- m))
          (backward-char 1)
          (skip-chars-backward "\n")
          (when (eq (alist-get :affinity snapshot) 'bol)
            (calc-cursor-stack-index m)
            (maf--point-restore-margin (alist-get :col snapshot)))
          (point))))))

(defun maf--point-restore-commit (context landed)
  "Place point after a command resolved CONTEXT and committed LANDED.
LANDED is `maf--commit's return (:node, :m), or nil when the command
signalled before committing.

The placements, in order. A commit that spread several parts over the
stack puts point at the end of the last one, where the end of the
entry it came from now is (`maf--point-restore-spread'). A `:land
head' command on a part target lands on the glyph that names its
committed node whole (`maf--point-land-head-p'). Otherwise the glyph
anchor keeps point on a structural glyph of the target it was already
on — invoked on the = of an equation, point is back on the = after the
sides swap, wherever it moved. Failing that, point sticks to the start
of the committed node when it was inside the part the command replaced
\(`maf--point-stick-p'). Failing all of these, the positional restore
from the resolve-time snapshot stands."
  (let ((anchor (alist-get :point-anchor context)))
    (or (and landed (> (or (alist-get :spread landed) 0) 1)
             (maf--point-restore-spread context landed))
        (and landed (maf--point-land-head-p context)
             (maf--point-restore-head landed))
        (and landed anchor (maf--point-restore-anchor anchor landed))
        (and landed (maf--point-stick-p context)
             (maf--point-restore-start landed))
        (maf--point-restore (alist-get :point context)))))

(defmacro maf--preserve-point (&rest forms)
  "Evaluate FORMS, then restore point's line, position, and affinity.
Snapshots point placement before FORMS run (`maf--point-snapshot') and
restores it after (`maf--point-restore')."
  (declare (indent 0))
  (let ((snapshot (gensym "snapshot-")))
    `(let ((,snapshot (maf--point-snapshot)))
       (prog1 (progn ,@forms)
         (maf--point-restore ,snapshot)))))

(defvar-local maf--home-mark-column nil
  "Column of the place the last homing trip marked, or nil.
A marker rides a push and a renumber, but not a rewrite of the entry it
sits in: re-rendering deletes the text around it and collapses it to
the start of the line, so the mark keeps the entry and loses the
column. Recorded here beside the mark for `maf-go-home's return trip
to put back. Nil when the trip left from the line-number prefix, there
being no column in the text to restore.")

(defun maf--mark-before-home (&optional pos)
  "Leave a silent mark at POS (or point) in the calc buffer.
Commands that push a new entry park point on the home line, losing the
spot the user was on. A mark left there — the marker rides the push and
renumber, so it keeps tracking the entry — lets a single
`pop-to-mark-command' return to it. Call this while point (or POS) is
still at the origin, before the push homes it. No-op at POS nil with
point already gone is the caller's concern.

The column goes into `maf--home-mark-column' alongside, for the
rewrite the marker cannot ride."
  (maf--with-calc-buffer
    (push-mark pos t)
    (setq maf--home-mark-column
          (save-excursion
            (when pos (goto-char pos))
            (and (not (maf--at-line-prefix-p)) (current-column))))))

(defvar maf-undo--cmd-point nil
  "Pre-command point snapshot for the head `calc-undo-list' group.
A list (UNDO-HEAD POST-POS SNAPSHOT). UNDO-HEAD is the `calc-undo-list'
cons captured when the recording command finished, so it is `eq' to the
current head only while that command is still the next thing undo
reverts. POST-POS is where the command left point — matching it means
the user hasn't repositioned since. When both hold, the first
`maf-undo' of a chain restores SNAPSHOT, point's placement from before
the command ran (see `maf--undo-redo').")

(defun maf--undo-record-cmd-point (snapshot)
  "Record SNAPSHOT as the pre-command point of the just-finished command.
Called at the end of every defcmd — once its undo group is final
(after digit-entry amalgamation) and point is restored — and by the
plain stack commands after their `calc-wrapper' completes."
  (setq maf-undo--cmd-point (list calc-undo-list (point) snapshot)))

(defvar maf--digit-entry-handoff nil
  "Non-nil when the last digit entry was terminated by a command key.
Set by the `calcDigit-nondigit' advice in src/minibuffer.el on every
completed digit entry — t for a command-key termination (1 +), nil for
a deliberate RET/SPC push — so it always reflects the most recent
entry. Consumed by `maf--undo-amalgamate-digit-entry'.")

(defun maf--undo-amalgamate-digit-entry ()
  "Merge a digit-entry arg push into the command's undo group.
Called after a binary command's `calc-wrapper' completes. When the
command's arg was pushed by a digit entry that dispatched the command
directly (1 + on an entry — `maf--digit-entry-handoff' is set and the
push's `calcDigit-start' is still `last-command'), the push and the
command are one gesture: fold the push's undo group into the command's
so a single undo reverts both, instead of stranding the arg back on
the stack. Deliberate pushes (1 RET, then + later) keep their own
group.

`last-command' is whichever digit-entry command last ran (the first
digit is calcDigit-start — or maf-digit-start when maf's binding wraps
it — later ones calcDigit-key); any of them means the entry directly
preceded this command."
  (when (and maf--digit-entry-handoff
             (memq last-command '(calcDigit-start calcDigit-key
                                  calcDigit-nondigit maf-digit-start))
             (cdr calc-undo-list))
    (setq calc-undo-list (cons (append (car calc-undo-list)
                                       (cadr calc-undo-list))
                               (cddr calc-undo-list))))
  (setq maf--digit-entry-handoff nil))

(defun maf-push (expr)
  "Parse algebraic EXPR and push it onto the calc stack.
A convenience over pushing a raw calc s-expression: instead of
\(calc-push \\='(+ (* 8 (var x var-x)) 4)) write (maf-push \"8 x + 4\").

EXPR is normally an algebraic string, parsed with `math-read-expr' in the
current language mode. A number or an already-parsed calc formula is pushed
as-is. Signals an error if the string does not parse."
  (interactive "sPush formula: ")
  (maf--with-calc-buffer
    (let ((val (if (stringp expr) (math-read-expr expr) expr)))
      (when (and (consp val) (eq (car val) 'error))
        (error "maf-push: cannot parse %S: %s" expr (nth 2 val)))
      (calc-push val))))

(defun maf--display-borrowing-window (buf alist)
  "Show BUF in another window on this frame, calc's for choice.
A `display-buffer' action function: the pane borrows a window the way
a help buffer does rather than carving the frame smaller, so a list
and its detail sit side by side at the frame's own split instead of
squeezing a third window in. Calc's window is picked over the
least-recently-used one because these panes are opened from calc — the
stack is what the user is least likely to be reading while looking
something up. Returns nil when there is nothing to borrow, so
`display-buffer' falls through to splitting.

Shared by the detail panes that follow point: the formulas menu's and
the saved-stacks preview."
  (let* ((cbuf (maf--find-calc-buffer))
         (win (or (and cbuf (get-buffer-window cbuf))
                  (get-lru-window nil nil t))))
    (when (and win
               (not (eq win (selected-window)))
               (not (window-dedicated-p win)))
      (window--display-buffer buf win 'reuse alist))))

;;; Command presentation metadata

;; Two strings a command may carry for the surfaces that describe it —
;; the bindings help buffer today, a completion annotation or a module
;; menu tomorrow. Symbol properties, as `maf-command' and
;; `maf-operation' already are, so any command can carry them however
;; it was defined: `maf-defcmd' writes them from its :title/:example
;; options, the mafcmd table passes the same two keywords through per
;; row, and a plain `defun' is stamped by whoever knows about it (see
;; `maf-keys-descriptions'). Neither is ever required — every reader
;; falls back, so the metadata can be filled in a command at a time
;; without any surface going wrong in the meantime.

(defun maf-command-title (command)
  "COMMAND's proper name — \"power\" for `mafcmd-pow' — or nil.
Nil rather than a guess: a name derived from the symbol would read as
one the author chose, and \"pow\" is exactly the abbreviation a proper
name is there to spell out. A caller with room for a fallback should
use the symbol itself, which at least is true."
  (get command 'maf-title))

(defun maf-command-example (command)
  "A short line showing what COMMAND does, or nil when none is written.
One line, in whatever notation reads clearest for the command — the
convention is a subject, an arrow, and the result: \"x, 2 => x^2\"."
  (get command 'maf-example))

(defun maf-set-command-doc (command &optional title example)
  "Give COMMAND its proper name TITLE and illustrative EXAMPLE.
Either may be nil, which leaves that property alone rather than
clearing it — a caller filling in one of the two does not have to
know the other. Both are plain strings; see `maf-command-title' and
`maf-command-example'."
  (when title (put command 'maf-title title))
  (when example (put command 'maf-example example))
  command)

(provide 'maf-lib)
