;; -*- lexical-binding: t; -*-
;;
;; modules/maf-recall.el
;;
;; Recall ring: M-p / M-n walk back through the entries you typed and
;; put one back — into the edit session you are in, or onto the stack
;; as a fresh entry. It exists to retire the defensive pattern of
;; duplicating or storing an entry before a calculation, just in case
;; the calculation mangles it.
;;
;; What the ring holds is the whole design: *what you typed*, never
;; what the stack held. maf-history already records stack states and
;; pushes any past entry back; a ring that also carried computed
;; results would be a worse history — filled with every intermediate
;; value, and re-rendering a value to text is lossy, which is why
;; `maf-edit-commit' never reparses an untouched entry. So only
;; brand-new entries feed the ring:
;;
;;   maf-edit         entries started from empty (the N+ lines),
;;                    recorded when the commit succeeds
;;   digit entry      numbers left on the stack as an entry of their own
;;                    (RET, C-<return>), by either of
;;                    `maf-digit-start's two routes
;;   algebraic entry  expressions the ' key leaves as an entry of their
;;                    own
;;
;; The two entry-command paths share one rule, since neither hands out
;; the string that was typed: watch the stack across the command, and
;; record when exactly one value was inserted. That is what makes a
;; modification a modification — an edited existing entry, a number
;; committed contextually into a sub-formula (SPC), a number consumed
;; as a command's argument (2 +, 5 e), an expression built from the
;; values it replaced (' 2+$) — none of them insert an entry, so none
;; of them reach the ring. A discarded session is out too — discarding
;; means it, and since recording rides a successful commit, a failed
;; parse is out for free.
;;
;; Recalling never reorders the ring, so M-p M-p M-p lands on the same
;; item every time; only newly typed entries feed it, and recording
;; dedupes by text. Running off either end stops with a message rather
;; than wrapping.
;;
;; In an edit session the keys replace the text of the entry point is
;; in, minibuffer-style, with whatever was there stashed as slot 0 so
;; M-n brings it back; at home, where there is no entry to fill, one
;; opens at the bottom to hold what is recalled. An entry that came off
;; the stack may be overwritten like any other, and then the value it
;; held goes into the ring as the newest item — the one place something
;; the stack held does belong there, since getting it back is what
;; makes overwriting it safe. Out on the stack the keys push the item
;; at home as a real entry, and repeated presses replace that entry in
;; place — yank/yank-pop, the whole cycle collapsing into a single undo
;; step.
;;
;; A ring item is a (TEXT . VALUE) pair. The entry commands know the
;; value they left behind, so the stack path pushes it back losslessly;
;; edit entries carry text alone and are parsed on demand, which is
;; what committing them did in the first place.
;;
;; The feature is `maf-use-recall-mode', a global minor mode registered
;; with the module system as `maf-recall' (see `maf-modules').

(require 'calc)
(require 'seq)
(require 'subr-x)
(require 'maf-lib)
(require 'maf-edit)          ; the session the edit path recalls into
(require 'maf-conf "conf")   ; the `maf' customize group

;; Defined in lazily-loaded calc modules; calc-ext's autoload registry
;; resolves them at runtime, but the byte compiler needs declarations.
(declare-function math-read-expr "calc-aent")
(declare-function math-format-flat-expr "calc-ext")
(declare-function calc-pop-push-record-list "calc-ext")
(declare-function calc-algebraic-entry "calc-aent")

;; Defined in maf.el / bindings.el and src/minibuffer.el, both loaded
;; by the time this module is enabled.
(defvar maf-mode-map)
(defvar savehist-additional-variables)
(declare-function maf-digit-start "maf-minibuffer")

(defcustom maf-recall-size 100
  "Maximum number of typed entries kept in the recall ring.
Recording past the limit drops the oldest. Items are small — a string
and a formula value that shares structure with the one on the stack —
so a large ring costs little."
  :type 'natnum
  :group 'maf)

(defvar maf-recall--ring nil
  "Entries you have typed, newest first, at most `maf-recall-size'.
Each item is a cons (TEXT . VALUE): TEXT what you would type to get it
back, VALUE its formula value, or nil for an item whose text has never
been parsed (see `maf-recall--value'). Deduplicated by TEXT.")

;;; Recording

(defun maf-recall--record (text &optional value)
  "Put TEXT at the front of the ring, carrying VALUE when known.
An identical TEXT already in the ring is removed first, so a re-typed
entry moves to the front instead of appearing twice. Blank text is
ignored."
  (when (and (stringp text) (not (string-blank-p text)))
    (setq maf-recall--ring
          (cons (cons text value)
                (seq-remove (lambda (item) (equal (car item) text))
                            maf-recall--ring)))
    (when-let ((cell (nthcdr (1- maf-recall-size) maf-recall--ring)))
      (setcdr cell nil))))

(defun maf-recall--new-entry-texts ()
  "Texts of the running edit session's entries that started from empty.
An entry overlay carries `maf-edit-val' only when it came from the
stack, so an entry without one was typed from nothing — the entries
this ring is for. Blank ones (an emptied entry, deleted at commit) are
left out."
  (delq nil
        (mapcar (lambda (o)
                  (and (not (overlay-get o 'maf-edit-val))
                       (let ((text (maf-edit--entry-text o)))
                         (and (not (string-blank-p text)) text))))
                (maf-edit--overlays))))

(defun maf-recall--record-edit (fn &rest args)
  "Record a session's new entries when its commit succeeds.
Advice around `maf-edit-commit'. The texts are read before the commit
runs, since the session — and with it every entry overlay — is gone
once it returns; they are recorded after, and only if it returned at
all. A commit that cannot parse signals and leaves the session
standing, and a discard never comes through here, so both stay out of
the ring without a test of their own.

Buffer order is deepest-first, so the bottom-most new entry is
recorded last and ends up the ring's newest — the order the entries
were added in."
  (let ((texts (and maf-edit-mode (maf-recall--new-entry-texts))))
    (prog1 (apply fn args)
      (dolist (text texts) (maf-recall--record text)))))

(defun maf-recall--stack-values ()
  "The stack's formula values, top first."
  (mapcar #'car (nthcdr calc-stack-top calc-stack)))

(defun maf-recall--inserted (old new)
  "The single value NEW holds that OLD does not, or nil.
Both are top-first stack value lists. Found by comparing the two
stacks rather than by reading the top, so an entry rolled into place
after its push is still found wherever it landed. A change that is not
exactly one insertion — the pop-push of a command that consumed the
number — yields nil, and nothing is recorded."
  (when (= (length new) (1+ (length old)))
    (let ((o old) (n new) found)
      (while (and n (not found))
        (if (and o (equal (car o) (car n)))
            (setq o (cdr o) n (cdr n))
          (setq found (car n))))
      found)))

(defun maf-recall--record-inserted (before)
  "Record the entry a finished entry command added, given the stack BEFORE.
The shared rule of the entry paths: exactly one value inserted means
the command left an entry of its own, which is what the ring is for.
Anything else was a modification of what was already there — a
contextual commit, an entry consumed as an argument, an expression
built from the values it replaced (' 2+$) — and is left alone. So is
an incomplete object still under construction (the .. interval).

TEXT is the value's flat rendering rather than the keystrokes, which
none of these commands hand out: `maf-digit-pi' turns a typed 5 into
5 pi, and \"ff\" typed under hex entry would not read back under
another radix. The visible cost is that recall offers a number in
canonical form — .5 comes back as 0.5.

Wrapped: an entry that works is worth more than a ring item, so a
failure here reports itself and gets out of the way."
  (condition-case err
      (when-let* ((val (maf-recall--inserted before (maf-recall--stack-values)))
                  (val (maf--strip-encasing val))
                  ((not (eq (car-safe val) 'incomplete))))
        (maf-recall--record (math-format-flat-expr val 0) val))
    (error (message "maf-recall: not recorded — %S" err))))

(defun maf-recall--record-digit (fn &rest args)
  "Record a digit entry that left an entry of its own on the stack.
Advice around `maf-digit-start', which is where both digit-entry
routes meet: at a sub-formula it commits through its own cond, and
anywhere else — at home above all — it hands the entry to calc's
`calcDigit-start' and never reaches maf's push at all. Watching the
stack across the whole command covers both, and covers the pi
shortcut and the escape to algebraic with them.

`maf--digit-entry-handoff' marks the one case the stack cannot tell
apart on its own: a number a command key claimed as its argument
(2 +, 5 e) is pushed as an entry before the command consumes it, so
an entry that ends that way is skipped outright."
  (let ((before (maf-recall--stack-values)))
    (prog1 (apply fn args)
      (unless maf--digit-entry-handoff
        (maf-recall--record-inserted before)))))

(defun maf-recall--record-algebraic (fn &rest args)
  "Record an algebraic entry that left an entry of its own on the stack.
Advice around `calc-algebraic-entry', the ' key — calc's own command,
which maf does not shadow. Same rule as the digit path, and the same
reason for it: an expression typed from nothing is exactly what the
ring is for, however it was typed. The stack comparison does the
whole job here — an entry that builds on what is already on the stack
(' 2+$ consumes the top) is not an insertion, so it stays out without
a test of its own.

The escape from a digit entry into algebraic goes through
`calc-alg-entry', not this command, and is already covered by
`maf-recall--record-digit'; nothing is recorded twice."
  (let ((before (maf-recall--stack-values)))
    (prog1 (apply fn args)
      (maf-recall--record-inserted before))))

;;; Ring access

(defun maf-recall--value (item)
  "Formula value of ring ITEM, parsing its text when it carries none.
Edit-path items hold text alone: it is the user's own source, and
reading it here is exactly what committing it did. Signals when the
text no longer parses — input modes can have moved under it."
  (or (cdr item)
      (let ((val (math-read-expr (car item))))
        (if (eq (car-safe val) 'error)
            (user-error "maf-recall: cannot read %s" (car item))
          val))))

(defun maf-recall--announce (i)
  "Message ring item I's text and its place in the ring."
  (message "maf-recall %d/%d: %s"
           (1+ i) (length maf-recall--ring) (car (nth i maf-recall--ring))))

;;; Recall in an edit session

(defvar-local maf-recall--edit-overlay nil
  "Entry overlay the running edit-session cycle is filling, or nil.")

(defvar-local maf-recall--edit-index nil
  "Ring index the edit-session cycle is showing; nil for the stash.")

(defvar-local maf-recall--edit-stash nil
  "Entry text displaced by the first recall of the current cycle.
Slot 0 of the cycle: \\[maf-recall-next] past the newest ring item
puts it back, so a recall started over half-typed text — or over an
entry the session took off the stack — never costs the user that
text.")

(defvar-local maf-recall--edit-text nil
  "Entry text this feature last inserted, for detecting outside edits.
A cycle continues only while the entry still holds what recall put
there; typing over it starts a fresh one, with the typed text as the
new stash.")

(defun maf-recall--entry-at-point ()
  "The maf-edit entry overlay point is in, or nil.
Entry overlays are rear-advancing and end just before the newline, so
containment is tested inclusively — point at an entry's very end is
still in it."
  (seq-find (lambda (o)
              (and (<= (overlay-start o) (point))
                   (<= (point) (overlay-end o))))
            (maf-edit--overlays)))

(defun maf-recall--edit-replace (o text)
  "Replace entry O's text with TEXT, leaving point at its end.
The edit runs with maf-edit's change hooks inhibited and a single
repair after, the way its own structural gestures do: a delete that
empties the entry would otherwise reach `maf-edit--drop-empty' and
take the overlay with it before the insert could refill it."
  (let* ((bol (save-excursion (goto-char (overlay-start o))
                              (line-beginning-position)))
         (start (+ bol (maf-edit--leading-prefix-run bol))))
    (let ((maf-edit--inhibit t)
          (inhibit-modification-hooks t))
      (maf-edit--clear-errors)
      (delete-region start (overlay-end o))
      (goto-char start)
      (insert text)
      (maf-edit--repair))
    (maf-edit--snap-point-out-of-run)))

(defun maf-recall--edit-displace (o)
  "Put entry O's text at the front of the ring, if it came from the stack.
Returns non-nil when it did. Recall over an existing entry overwrites
a value the user has — the one case where something the stack held
belongs in the ring, since being able to get it back is the whole
point of overwriting it deliberately. It goes in as the newest item,
so it is one \\[maf-recall-next] away for the rest of the session and
recallable anywhere after.

The value rides along when the entry is untouched — `maf-edit-val' is
what the session took off the stack, and what a commit would have put
back — so recalling it later restores the object rather than a reading
of its text. An entry edited before the recall carries text alone."
  (let ((text (maf-edit--entry-text o)))
    (when (and (overlay-get o 'maf-edit-val) (not (string-blank-p text)))
      (maf-recall--record text
                          (and (equal text (overlay-get o 'maf-edit-text))
                               (overlay-get o 'maf-edit-val)))
      t)))

(defun maf-recall--edit-move (n)
  "Move N steps back through the ring in the running edit session."
  (let ((o (or (maf-recall--entry-at-point)
               ;; At home there is no entry to fill, so recall makes
               ;; one: a blank entry opens at the bottom and the cycle
               ;; runs in it, which is what recalling from home means
               ;; out on the stack too. Only a backward step opens it —
               ;; a forward one from nothing has nowhere to go, and an
               ;; empty entry left behind would be a surprise.
               (and (> n 0) (maf-edit--open-at-dot))
               (user-error "maf-recall: no later entry"))))
    ;; A cycle continues only in the entry it started in, and only
    ;; while that entry still holds what recall last put there.
    (unless (and (eq o maf-recall--edit-overlay)
                 (equal (maf-edit--entry-text o) maf-recall--edit-text))
      (setq maf-recall--edit-overlay o
            maf-recall--edit-index nil
            maf-recall--edit-stash (maf-edit--entry-text o))
      ;; Displacing an existing entry banks it as the ring's newest
      ;; first, which is then what the entry is showing — so the cycle
      ;; starts standing on item 0 and the first step moves off it,
      ;; instead of replacing the entry with what it already holds.
      ;; Only going backwards displaces anything: a forward step from a
      ;; fresh cycle has nowhere to go and says so.
      (when (and (> n 0) (maf-recall--edit-displace o))
        (setq maf-recall--edit-index 0)))
    (let ((i (+ (or maf-recall--edit-index -1) n)))
      (cond
       ((< i -1) (user-error "maf-recall: no later entry"))
       ((>= i (length maf-recall--ring))
        (user-error "maf-recall: no earlier entry"))
       ((= i -1)
        (setq maf-recall--edit-index nil)
        (maf-recall--edit-replace o maf-recall--edit-stash)
        (message "maf-recall: back to the entry you started from"))
       (t
        (setq maf-recall--edit-index i)
        (maf-recall--edit-replace o (car (nth i maf-recall--ring)))
        (maf-recall--announce i)))
      (setq maf-recall--edit-text (maf-edit--entry-text o)))))

;;; Recall on the stack

(defvar-local maf-recall--stack-index nil
  "Ring index the stack cycle is showing, or nil outside a cycle.
Meaningful only while `last-command' is one of the recall commands:
any other command ends the cycle and leaves the recalled entry
standing.")

(defvar-local maf-recall--stack-value nil
  "Value the stack cycle last put at level 1, or nil outside a cycle.
A cycle replaces its own entry, so it may only continue while that
entry is still the one on top. Without the check a press whose
`last-command' says \"cycle\" but whose stack has moved on — undone,
or changed by something that never ran as a command — would pop-push
over an entry it never pushed.")

(defun maf-recall--amalgamate ()
  "Fold calc's newest undo group into the one before it.
Cycling replaces the recalled entry over and over, and each
replacement is an undo group of its own; unwinding a cycle one
candidate at a time is never what the user means. Folding each step
into the step before leaves the whole cycle as a single undo, the
trick `maf--undo-amalgamate-digit-entry' plays on an arg push."
  (when (cdr calc-undo-list)
    (setq calc-undo-list
          (cons (append (car calc-undo-list) (cadr calc-undo-list))
                (cddr calc-undo-list)))))

(defun maf-recall--stack-move (n)
  "Move N steps back through the ring out on the stack.
The first step pushes a new entry at home; further steps replace it,
so a cycle leaves exactly one entry behind however long it ran."
  (let* ((cycling (and (memq last-command
                             '(maf-recall-previous maf-recall-next))
                       maf-recall--stack-index
                       (> (calc-stack-size) 0)
                       (equal (maf--strip-encasing (calc-top 1))
                              maf-recall--stack-value)))
         (i (+ (if cycling maf-recall--stack-index -1) n)))
    (cond
     ((< i 0) (user-error "maf-recall: no later entry"))
     ((>= i (length maf-recall--ring))
      (user-error "maf-recall: no earlier entry"))
     (t
      (let ((val (maf-recall--value (nth i maf-recall--ring))))
        (if cycling
            (progn
              (calc-wrapper
               (calc-pop-push-record-list 1 "rcl" (list val) 1 (list nil)))
              (maf-recall--amalgamate))
          ;; The push parks point at home; mark where the user was so a
          ;; single `pop-to-mark-command' returns there, as a homing
          ;; digit-entry RET does.
          (unless (maf--at-home-p) (maf--mark-before-home))
          (calc-wrapper
           (calc-pop-push-record-list 0 "rcl" (list val) 1 (list nil))))
        (setq maf-recall--stack-index i
              maf-recall--stack-value (maf--strip-encasing (calc-top 1)))
        (maf-recall--announce i))))))

;;; Commands

(defun maf-recall--move (n)
  "Recall N steps back through the ring, in whichever mode is running."
  (unless maf-recall--ring
    (user-error "maf-recall: nothing typed yet"))
  (if maf-edit-mode
      (maf-recall--edit-move n)
    (maf-recall--stack-move n)))

(defun maf-recall-previous ()
  "Recall the previous entry you typed.
In a maf-edit session, fills the entry point is in with it — the text
it displaces comes back with \\[maf-recall-next], and when that text
was an entry off the stack it also enters the ring as its newest item.
At home in a session there is no entry to fill, so one opens at the
bottom to hold it. Out on the stack, pushes it as a new entry at home;
pressing again replaces that entry with the item before it, so a cycle
leaves one entry behind and a single undo removes it.

The ring holds entries you typed from nothing, on both the maf-edit
and digit-entry paths — never a result a command computed, which is
`maf-history's business."
  (interactive)
  (maf-recall--move 1))

(defun maf-recall-next ()
  "Recall the next entry you typed, walking back toward the newest.
The counterpart of \\[maf-recall-previous]; in an edit session it goes
one step further than the newest item, to the text the cycle
displaced."
  (interactive)
  (maf-recall--move -1))

;;; Persistence

;; Typed text is worth more than one Emacs session. maf-persist saves
;; stacks; this rides savehist, which is where input histories live.
(with-eval-after-load 'savehist
  (add-to-list 'savehist-additional-variables 'maf-recall--ring))

;;; The module

(define-minor-mode maf-use-recall-mode
  "Recall entries you typed earlier with M-p and M-n.

For example, after entering 2x+1 and using it in a calculation, press
M-p to bring 2x+1 back. Press M-p again for an older entry or M-n to
move forward. In maf-edit, the recalled text is inserted into the edit
session. On the stack, it is pushed as a new entry.

The recall ring stores what you typed through digit entry, algebraic
entry, or maf-edit. It does not store calculated results. Turning the
mode off stops recording and removes the keys, but keeps the existing
ring for when the mode is turned on again."
  :global t
  :group 'maf
  (if maf-use-recall-mode
      (progn
        (advice-add 'maf-edit-commit :around #'maf-recall--record-edit)
        (advice-add 'maf-digit-start :around #'maf-recall--record-digit)
        (advice-add 'calc-algebraic-entry :around
                    #'maf-recall--record-algebraic)
        (maf-bindings--refresh)
        (define-key maf-edit-mode-map (kbd "M-p") #'maf-recall-previous)
        (define-key maf-edit-mode-map (kbd "M-n") #'maf-recall-next))
    (advice-remove 'maf-edit-commit #'maf-recall--record-edit)
    (advice-remove 'maf-digit-start #'maf-recall--record-digit)
    (advice-remove 'calc-algebraic-entry #'maf-recall--record-algebraic)
    (maf-bindings--refresh)
    (define-key maf-edit-mode-map (kbd "M-p") nil)
    (define-key maf-edit-mode-map (kbd "M-n") nil)))

(maf-bindings-module-keys 'maf-recall 'maf-use-recall-mode
  '(((calc native vim) "M-p" maf-recall-previous)
    ((calc native vim) "M-n" maf-recall-next)))

;; Register with the module system when it is present; the mode above
;; works on its own without it.
(when (require 'maf-module nil t)
  (maf-register-module 'maf-recall #'maf-use-recall-mode
                       "Bring back an entry you typed earlier.

For example, after entering 2x+1, press M-p to bring it back and M-n
to move forward again. Recall stores what you typed, not calculated
results. It works both on the stack and inside maf-edit."
                       "M-p, M-n" "Memory"))

(provide 'maf-recall)
