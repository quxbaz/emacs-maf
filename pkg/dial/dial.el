;; -*- lexical-binding: t; -*-
;;
;; dial.el — a buffer for browsing and setting a table of options
;;
;; Dial renders an alist of option specs as a tabulated-list buffer:
;; each row is one option showing every value it can take with the live
;; one highlighted, and the whole table is driven from the keyboard —
;; step a row's values to set them, reset to defaults, narrow to what
;; has changed. Dial owns the shell: the buffer, its rendering, motion,
;; faces and keymap. What the options *are* — how one is read, how a
;; value is applied, where defaults come from — is the consumer's, told
;; to `dial-open' as a table of items and a handful of functions.
;;
;; An item is (ID . SPEC), ID any symbol the consumer's functions
;; understand, SPEC a plist:
;;
;;   :group   Section heading. Rows print in table order, so an item's
;;            group is decided by where it sits in the table.
;;   :label   Name shown in the Option column.
;;   :keys    Text for the optional reference-key column, shown when
;;            the consumer names that column (see `dial-open') and the
;;            user toggles it in.
;;   :doc     What the row is for, echoed when point rests on it.
;;            A line is the usual size; a consumer whose rows need
;;            more may send several, the echo area growing to fit.
;;   :details Fuller text about the row, shown in another window on
;;            demand — see `dial-describe' — for what outgrows even a
;;            several-line :doc. A string, or a function (ID) -> string
;;            called at each show, so it may read live state. A row
;;            without one is described by its :doc.
;;   :values  ((VALUE LABEL SETTER PROP...) ...) for an option with a
;;            fixed domain. VALUE is what the option's current key
;;            equals when it is set that way; SETTER is an opaque form
;;            handed to the consumer's :apply function. The PROPs are
;;            an optional plist about the entry; the one dial reads is
;;            :prompts, non-nil when the setter asks the user for
;;            input — see `dial-next-value' for what that changes.
;;            Metadata rather than inspection, because the setter is
;;            opaque: dial reading its code for tell-tale symbols
;;            would misjudge any form it did not anticipate.
;;   :read    Setter form that prompts for a value, for options whose
;;            domain is open. May appear alongside :values, where the
;;            values are the common choices and :read reaches the rest.
;;   :current Function mapping the raw value to the VALUE matched
;;            against :values, for options stored decomposed.
;;   :show    Function rendering the raw value for the Value column,
;;            when the matched :values label does not say enough.
;;   :example Function mapping a value key to a short sample of the
;;            output the option produces set that way, or to nil when
;;            no example applies. Called after a step has applied the
;;            value, so it may read live state; only stepping echoes
;;            it — see `dial--example'.
;;   :describe Function mapping a value key to a short description of
;;            what the value means, echoed on stepping as the value's
;;            label over the text. For rows whose values are choices
;;            to explain rather than settings to sample; wins over
;;            :example when both are present — see `dial--describe'.
;;   :vars    Other IDs the row speaks for, when one setting is spread
;;            over several. They count towards whether the row has
;;            moved off its default.
;;   :default The value key the row starts on, for a row whose default
;;            cannot be derived — see `dial--default-value'.
;;   :reset   Setter form putting the row back to its default, for the
;;            few options whose reset does more than writing the
;;            default value back.
;;
;; A setter is a form rather than a function because the systems dial
;; fronts do not uniformly take a value — some have one command per
;; value, some take an argument naming it, some only toggle — and the
;; consumer's :apply function is what knows where and how to run one.
;; Dial never evaluates a setter itself.

(require 'cl-lib)
(require 'seq)
(require 'tabulated-list)

(defgroup dial nil
  "A tabulated buffer for browsing and setting options."
  :group 'convenience)

(defface dial-value
  ;; Coloured text, no background: against the shadowed values beside
  ;; it, the live one is picked out by colour alone. Two shades, one
  ;; for each theme's ground, both unmistakably purple.
  '((((class color) (background dark))  :foreground "#b48ee0")
    (((class color) (background light)) :foreground "#553280")
    (t :weight bold))
  "Face for the value a setting is currently on, when it is the default.
The other values a setting can take are shadowed beside it, so this
face is what picks the live one out of the row. A setting moved off its
default wears `dial-changed' instead."
  :group 'dial)

(defface dial-changed
  ;; Gold text against the purple of `dial-value': the same weight of
  ;; mark, so a moved setting is still found the same way, in a colour
  ;; that says so on its own — the two states are the two colours, and
  ;; nothing else on the row has to carry the difference. Bright on a
  ;; dark ground, deep on a light one.
  '((((class color) (background dark))  :foreground "#e6b422")
    (((class color) (background light)) :foreground "#a06f00")
    (t :weight bold :inverse-video t))
  "Face for the value a setting is currently on, when it is not the default.
See `dial-value'."
  :group 'dial)

(defface dial-group
  ;; Blue text, no background: a heading should be found at a glance
  ;; without competing with the purple and gold the values wear.
  ;; Two shades, one for each theme's ground, both unmistakably blue.
  '((((class color) (background dark))  :foreground "#6fa8f5")
    (((class color) (background light)) :foreground "#1f4e99")
    (t :weight bold))
  "Face for a group's heading in the first column."
  :group 'dial)

(defface dial-controls
  ;; Dark and drained where the live value is bright: the band
  ;; should read as chrome above the list, not as another row in it.
  ;; Extends, so it runs the width of the window.
  '((((class color) (background dark))  :background "#1c2733" :extend t)
    (((class color) (background light)) :background "#e2eaf3" :extend t)
    (t :inverse-video t))
  "Face for the controls line above the options list."
  :group 'dial)

(defface dial-selection
  ;; `:box' would be the obvious outline and is what a graphical frame
  ;; gets. A terminal ignores it entirely, so the outline there has to
  ;; be characters — see `dial--outline'. Bold under both, since it is
  ;; the one attribute the highlights are not using, and so stacks on
  ;; either.
  '((((type graphic)) :box (:line-width -1) :weight bold)
    (t :weight bold))
  "Face for a value stepped onto but still waiting for its input.
See `dial--pending'."
  :group 'dial)

(defcustom dial-outline '("[" . "]")
  "Characters drawn around a value that is waiting for input.
A terminal cannot render the `:box' of `dial-selection', so the outline
is drawn rather than styled. Set to nil on a graphical frame, where the
box is real."
  :type '(choice (const :tag "None — rely on the face's box" nil)
                 (cons (string :tag "Before") (string :tag "After")))
  :group 'dial)

;;; What the consumer supplies

(defvar-local dial-items nil
  "The options this buffer shows: an alist of (ID . SPEC).
See this file's commentary for SPEC's keys. Set by `dial-open'.")

(defvar-local dial--raw-fn nil
  "Function returning an item's raw value, given its ID.")

(defvar-local dial--default-fn nil
  "Function returning an item's default raw value, given its ID.
Nil when the consumer has no notion of defaults, which quietly disables
the changed-only filter's idea of changed and resetting by value, and
leaves the changed highlight to rows stating a :default of their own.")

(defvar-local dial--apply-fn nil
  "Function evaluating a setter form wherever the consumer needs it run.")

(defvar-local dial--write-fn nil
  "Function writing a raw value straight to an item: (ID VALUE).
The reset path for an item whose default matches none of its :values
and that gives no :reset form — all that is left is putting the default
value back directly, and only the consumer knows how.")

(defvar-local dial--save-fn nil
  "Function persisting the settings, or nil when there is nowhere to.")

(defvar-local dial--keys-name nil
  "Header for the reference-key column, or nil when there is none.")

(defvar-local dial-controls nil
  "This buffer's controls-line entries, when the consumer supplies them.
Falls back to `dial-default-controls'; see that variable for the entry
format.")

(defun dial--raw (id)
  "Return ID's raw value, through the consumer."
  (funcall dial--raw-fn id))

(defun dial--default (id)
  "Return ID's default raw value, through the consumer."
  (funcall dial--default-fn id))

(defun dial--apply (form)
  "Hand setter FORM to the consumer to evaluate."
  (funcall dial--apply-fn form))

;;; Reading an item

(defun dial--values (spec)
  "Return SPEC's value entries."
  (plist-get spec :values))

(defun dial--current (id spec)
  "Return the value key naming ID's current state under SPEC."
  (let ((raw (dial--raw id)))
    (if (plist-get spec :current)
        (funcall (plist-get spec :current) raw)
      raw)))

(defconst dial--no-default (make-symbol "dial--no-default")
  "What `dial--default-value' answers when there is no default to name.
A symbol no value key can equal, so \"no default\" cannot collide with
an option whose default is nil.")

(defun dial--default-value (id spec)
  "Return the value key naming ID's default under SPEC.
Normalized the way `dial--current' normalizes the live value, so the
two are comparable.

SPEC's :default is taken as the answer when it has one. Normalizing
through :current only works while :current looks at nothing but the raw
value it is handed — a :current that consults live state would report
whatever the setting is on now as the value it starts on. A row like
that states its default rather than deriving one."
  (cond ((plist-member spec :default) (plist-get spec :default))
        ((null dial--default-fn) dial--no-default)
        (t (let ((default (dial--default id)))
             (if (plist-get spec :current)
                 (funcall (plist-get spec :current) default)
               default)))))

(defun dial--value-string (id spec)
  "Return the Value column text for ID under SPEC."
  (let* ((raw (dial--raw id))
         (shown (and (plist-get spec :show)
                     (funcall (plist-get spec :show) raw))))
    (or shown
        ;; `assoc', as everywhere a value key is looked up: the chips
        ;; compare keys with `equal', and a string key found there but
        ;; missed here would render highlighted yet report raw.
        (nth 1 (assoc (dial--current id spec) (dial--values spec)))
        ;; A string setting is shown as the string, not as its printed
        ;; form: the separator is a comma, not "\",\"".
        (if (stringp raw) raw (format "%S" raw)))))

(defvar-local dial--pending nil
  "(ID . INDEX) for a value stepped onto but not set, or nil.
Only ever one: a step onto another setting's value replaces it, so the
mark cannot be left behind on a row nobody is working on. Point does
not move to it — the step walks the setting, not the buffer — so the
row has to carry the mark itself, which is what this is read for.")

(defun dial--pending-index (id)
  "Return the index of ID's stepped-onto value, if it has one."
  (and (eq (car dial--pending) id) (cdr dial--pending)))

(defun dial--outline (label selected)
  "Return LABEL, drawn inside `dial-outline' when SELECTED.
Only a value waiting for its input is ever outlined, so the width the
outline costs is paid on one value at a time and never on a settled
row."
  (if (and selected dial-outline)
      (concat (car dial-outline) label (cdr dial-outline))
    label))

(defun dial--value-face (live changed selected)
  "Return the face for a value that is LIVE, on a CHANGED row, or SELECTED.
The live value stands out of the shadowed row in purple: bare
(`dial-value') on a row sitting on its default, over a tinted ground
(`dial-changed') on one that has moved. The ground carries the state,
so nothing marks the default value itself — a mark on every row is a
constant rather than a signal, and where the setting has moved, the
tint already says so. The tinted rows are the ones
\\<dial-mode-map>\\[dial-toggle-changed-only] would keep visible without
filtering.

SELECTED composes over either — it only ever appears on a value that
could not be set, so it has to sit beside the highlight rather than
take its place."
  (let ((base (cond ((and live changed) '(dial-changed))
                    (live '(dial-value))
                    (t '(shadow)))))
    (if selected (cons 'dial-selection base) base)))

(defun dial--moved-p (id spec)
  "Non-nil when ID's row is known to be off its default under SPEC.
Through the consumer's raw values where it supplies defaults — the same
answer the changed-only filter gives, see `dial--changed-p' — and
otherwise by the value key against a :default the row states for
itself. Nil, not \"changed\", when no default is known at all."
  (if dial--default-fn
      (dial--changed-p id spec)
    (let ((default (dial--default-value id spec)))
      (and (not (eq default dial--no-default))
           (not (equal (dial--current id spec) default))))))

(defun dial--value-column (id spec)
  "Return the Value column for ID under SPEC: every value it can take.
The one the setting is on wears `dial-value', the rest are shadowed —
the row doubles as the list \\<dial-mode-map>\\[dial-next-value]
steps through, so what a step will reach is on show rather than found by
stepping to it. The live value sits on a tinted ground where the
setting has moved off its default — see `dial--value-face'. A setting
with no fixed set of values, and one sitting on a value outside its
set, shows that value alone.

A value stepped onto but not set is marked too — see `dial--pending'."
  (let* ((values (dial--values spec))
         (current (dial--current id spec))
         (moved (dial--moved-p id spec))
         (live-face (if moved 'dial-changed 'dial-value))
         (show (plist-get spec :show))
         (pending (dial--pending-index id))
         (chips (seq-map-indexed
                 (lambda (v i)
                   (propertize
                    (dial--outline (nth 1 v) (eql i pending))
                    'face (dial--value-face
                           (equal (car v) current)
                           moved
                           (eql i pending))))
                 values))
         ;; What no chip can say: the value of a setting with an open
         ;; domain, and the detail behind a chip that only names a
         ;; state.
         (extra (or (and show (funcall show (dial--raw id)))
                    (unless (assoc current values)
                      (dial--value-string id spec)))))
    ;; The values carry no padding of their own: a face spanning the
    ;; space beside a value reads as highlighting something that is not
    ;; there. The gap between them is the separator, unfaced.
    (mapconcat #'identity
               (if extra
                   (append chips
                           (list (propertize extra 'face live-face)))
                 chips)
               "  ")))

(defun dial--changed-p (id spec)
  "Non-nil when ID, or any of SPEC's :vars, has moved off its default.
Compares the raw values, not the keys `dial--current' derives: a
detail's worth of difference within one value key is still a change.

:vars names the other IDs a row speaks for. A row that covers two and
asks about only one calls itself unchanged while half of what it shows
has moved — and then hides itself from the filter that exists to find
exactly that."
  (and dial--default-fn
       (seq-some (lambda (v)
                   (not (equal (dial--raw v) (dial--default v))))
                 (cons id (plist-get spec :vars)))))

;;; The buffer

(defvar-local dial--changed-only nil
  "Non-nil to list only settings differing from their default.")

(defvar-local dial--show-keys nil
  "Non-nil to show the reference-key column.
Off to start: the column is a reference for keys the buffer exists to
save anyone reaching for, and the widest of them costs twenty columns
that the values put to better use.")

(defun dial--keys-shown-p ()
  "Non-nil when the reference-key column is present."
  (and dial--show-keys dial--keys-name))

(defun dial--apply-format ()
  "Set `tabulated-list-format' for the columns currently shown.
Value goes last because it holds every value the setting can take — no
fixed width would hold that, and nothing may sit to the right of it.
The reference-key column comes and goes with `dial--show-keys', so the
format is built rather than written out."
  (setq tabulated-list-format
        (vconcat [("Group" 9 nil) ("Option" 18 nil)]
                 (when (dial--keys-shown-p) `[(,dial--keys-name 20 nil)])
                 [("Value" 0 nil)]))
  (tabulated-list-init-header))

(defvar dial-mode-map (make-sparse-keymap)
  "Keymap for `dial-mode'.")

;; Bindings live outside the defvar so reloading the file applies edits
;; to the existing map.
(define-key dial-mode-map (kbd "TAB")       #'dial-next-value)
(define-key dial-mode-map (kbd "<backtab>") #'dial-previous-value)
;; SPC steps with TAB, not with RET: stepping is the act a dial buffer
;; lives on, and a toggle-shaped row makes SPC the flip key. TAB stays
;; the key messages and the controls line name it by.
(define-key dial-mode-map (kbd "SPC")  #'dial-next-value)
(define-key dial-mode-map (kbd "RET")  #'dial-set)
(define-key dial-mode-map (kbd "d")    #'dial-reset)
(define-key dial-mode-map (kbd "c")    #'dial-toggle-changed-only)
(define-key dial-mode-map (kbd "K")    #'dial-toggle-keys)
(define-key dial-mode-map (kbd "S")    #'dial-save)
(define-key dial-mode-map (kbd "g")    #'dial-refresh)
;; Shadows `special-mode''s ? (`describe-mode'): in a dial buffer the
;; question one asks is about the row, not the mode — the controls
;; line already summarizes the mode's keys. w, on the home row beside
;; the h/j/k/l motion, goes further: it selects the window too.
(define-key dial-mode-map (kbd "?")    #'dial-describe)
(define-key dial-mode-map (kbd "w")    #'dial-describe-visit)
;; h/l alongside TAB, as j/k sit alongside n/p: the values run across
;; the row, so stepping them is the horizontal motion.
(define-key dial-mode-map (kbd "l")    #'dial-next-value)
(define-key dial-mode-map (kbd "h")    #'dial-previous-value)
(define-key dial-mode-map (kbd "j")    #'dial-next-line)
(define-key dial-mode-map (kbd "k")    #'dial-previous-line)
(define-key dial-mode-map (kbd "n")    #'dial-next-line)
(define-key dial-mode-map (kbd "p")    #'dial-previous-line)
(define-key dial-mode-map (kbd "M-n")  #'dial-next-group)
(define-key dial-mode-map (kbd "M-p")  #'dial-previous-group)

(defvar dial-default-controls nil
  "Commands summarized on the controls line, in order.
Each entry is (COMMAND VERB . PREFERRED-KEYS), the keys optional. Keys
are otherwise looked up in the live keymap, so moving a binding — here
or in the maps this mode inherits, which is where `quit-window' comes
from — keeps the line honest.

COMMAND may be a list of commands, for a pair that reads as one control
rather than two: \\`M-n' and \\`M-p' are one \"group\" entry, not a next
and a previous.

The default for a buffer whose consumer sets no `dial-controls' of its
own.")

;; Set outside the defvar, as the bindings are, so a reload applies.
(setq dial-default-controls
      '(((dial-next-value dial-previous-value) "select" "TAB")
        (dial-set "set" "RET")
        (dial-reset "reset")
        (dial-toggle-changed-only "changed")
        (dial-toggle-keys "keys")
        (dial-save "save")
        ((dial-next-group dial-previous-group) "group" "M-n" "M-p")
        ((dial-describe-visit dial-describe) "details" "w" "?")
        (dial-refresh "refresh")
        (quit-window "quit")))

(defun dial--control-keys (command preferred)
  "Return the key strings naming COMMAND on the controls line.
COMMAND is one command or a list of them. PREFERRED names the keys to
show, in order, and each is kept only while it still runs one of
COMMAND — so a binding moved away drops out of the line rather than
misleading. With none given, or none left, the keymap decides, which
for a command reachable several ways picks whichever key
`where-is-internal' returns first.

Looked up through the buffer's live keymaps, not `dial-mode-map': a
consumer is free to rebind in a buffer-local map, and the line has to
tell the truth about the buffer it heads."
  (or (seq-filter (lambda (key)
                    (memq (key-binding (kbd key))
                          (ensure-list command)))
                  (ensure-list preferred))
      (when-let ((key (where-is-internal (car (ensure-list command))
                                         nil t)))
        (list (key-description key)))
      (list "M-x")))

(defun dial--key (command preferred)
  "Return the key string naming COMMAND in a message, PREFERRED first.
`substitute-command-keys' would name whichever key the map yields
first, which for a command two keys reach is not the one to tell
someone about."
  (car (dial--control-keys command preferred)))

(defun dial--default-entry (id spec)
  "Return the :values entry matching ID's default under SPEC, if any.
This entry is what `dial-reset' runs when the row has no :reset form of
its own — so a default that matches no entry, or an open-domain row
with no entries at all, cannot reset that way.

Matched with `assoc', because the chips match with `equal': a string
key the renderer treats as the default would otherwise be one the
buffer claims it cannot reset to."
  (let ((default (dial--default-value id spec)))
    (and (not (eq default dial--no-default))
         (assoc default (dial--values spec)))))

(defun dial--resettable-p (id spec)
  "Non-nil when `dial-reset' on ID's row has a path that works.
The same three paths the command tries, by the same truthiness — a
:reset that is present but nil counts for nothing there, so it counts
for nothing here: a truthy :reset form, a value entry matching the
derived default, or the two callbacks that let the default raw value
be written back directly."
  (or (plist-get spec :reset)
      (dial--default-entry id spec)
      (and dial--write-fn dial--default-fn)))

(defun dial--any-default-p ()
  "Non-nil when some row knows its default, and so can show as changed.
Every row does with a :default callback; without one, only rows stating
a :default of their own. A buffer where no row can tell earns no legend
describing a highlight that cannot appear."
  (and (seq-some (lambda (entry)
                   (not (eq (dial--default-value (car entry) (cdr entry))
                            dial--no-default)))
                 dial-items)
       t))

(defun dial--any-reset-p ()
  "Non-nil when `dial-reset' would succeed on some row."
  (and (seq-some (lambda (entry)
                   (dial--resettable-p (car entry) (cdr entry)))
                 dial-items)
       t))

(defun dial--control-available-p (command)
  "Non-nil when COMMAND has something to do in this buffer.
Dial's optional capabilities each hang off a piece the consumer may
not have supplied — defaults, a save function, a keys column — and a
control the buffer cannot honor is left off the line rather than
advertised. The commands stay bound either way and say for themselves
what is missing.

Reset and the changed-only filter gate differently: a row's own
:default or :reset makes it resettable with no :default callback at
all, but the filter compares raw values through the callback and
works only with one."
  (pcase (car (ensure-list command))
    ('dial-save (and dial--save-fn t))
    ('dial-toggle-keys (and dial--keys-name t))
    ('dial-toggle-changed-only (and dial--default-fn t))
    ('dial-reset (dial--any-reset-p))
    ((or 'dial-describe 'dial-describe-visit)
     (and (seq-some (lambda (entry)
                      (or (plist-get (cdr entry) :details)
                          (plist-get (cdr entry) :doc)))
                    dial-items)
          t))
    (_ t)))

(defun dial--controls-line ()
  "Return the controls line printed above the list.
Controls whose capability the consumer left unsupplied are omitted —
see `dial--control-available-p'. Ends with the legend for the colour of
a value sitting on its default — the shorter of the two states to name,
and the gold of a moved one follows from it. It is the one thing on the
line that is not a key — hence \\`d' reading \"reset\" rather than
\"default\", which would have said two things here. No defaults means
neither colour means anything, so the legend goes with them."
  (concat
   " "
   (mapconcat
    (lambda (cell)
      (pcase-let ((`(,command ,verb . ,preferred) cell))
        (concat (mapconcat (lambda (key)
                             (propertize key 'face 'help-key-binding))
                           (dial--control-keys command preferred)
                           "/")
                " " verb)))
    (seq-filter (lambda (cell) (dial--control-available-p (car cell)))
                (or dial-controls dial-default-controls))
    "   ")
   (when (dial--any-default-p)
     (concat "   " (propertize "value" 'face 'dial-value)
             (propertize " = default" 'face 'shadow)))))

(defun dial--setting-line-p ()
  "Non-nil when point is on a row that names a setting.
False on the controls line, the blank line under it, and the blank rows
between groups — everything motion should step over rather than land
on."
  (let ((id (tabulated-list-get-id)))
    (and id (symbolp id))))

(defun dial--goto-option ()
  "Put point on the first character of the current row's Option column.
Found by the column name tabulated-list stamps on the printed text, so
a column widening or disappearing ahead of it needs no change here."
  (let ((pos (line-beginning-position))
        (end (line-end-position))
        found)
    ;; Scanned rather than `text-property-any', which compares with
    ;; `eq' and so never matches a column name that is a string.
    (while (and (not found) (< pos end))
      (if (equal (get-text-property pos 'tabulated-list-column-name) "Option")
          (setq found pos)
        (setq pos (next-single-property-change
                   pos 'tabulated-list-column-name nil end))))
    (when found (goto-char found))))

(defun dial--move-line (n)
  "Move N setting rows on, backwards for a negative N.
Point lands on the first character of the Option column rather than
holding whatever column it was in, so a row is picked out by its name;
the blank rows between groups are stepped over rather than landed on.
Staying put where there is no row left to reach."
  (let ((start (point))
        (step (if (> n 0) 1 -1)))
    (dotimes (_ (abs n))
      (let ((from (point)))
        (forward-line step)
        (while (and (not (dial--setting-line-p))
                    (if (> step 0) (not (eobp)) (not (bobp))))
          (forward-line step))
        (unless (dial--setting-line-p) (goto-char from))))
    (if (dial--setting-line-p)
        (dial--goto-option)
      (goto-char start))))

(defun dial--echo-doc ()
  "Echo the current row's :doc, if it has one.
What a row is for cannot be read off the row: the Option column has
room for a name, not for a sentence. So the sentence follows point
instead, which is why an item carries a :doc. A doc running to
several lines is echoed whole — the echo area grows to fit it.

Not logged. This runs on every motion key, and a line of help repeated
down a list is not what *Messages* is for. Silent on a row with no doc
rather than blanking the echo area, so whatever was last said — the
value just set, a value waiting for input — survives the move."
  (let ((doc (plist-get (alist-get (tabulated-list-get-id) dial-items)
                        :doc)))
    (when doc
      (let ((message-log-max nil))
        (message "%s" doc)))))

(defun dial-next-line (&optional n)
  "Move to the next setting, or N settings on, and echo what it does."
  (interactive "p")
  (dial--move-line (or n 1))
  (dial--echo-doc))

(defun dial-previous-line (&optional n)
  "Move to the previous setting, or N settings back, and echo what it does."
  (interactive "p")
  (dial--move-line (- (or n 1)))
  (dial--echo-doc))

(defvar-local dial--echoed-row nil
  "The row whose :doc was echoed last, for `dial--echo-on-move'.
Compared by row identity, so a command that leaves point on the same
setting says nothing again.")

(defun dial--echo-on-move ()
  "Echo the row's :doc when a command has moved point onto another row.
On `post-command-hook', so that the ordinary motion keys — C-n and
C-p, the arrows, scrolling, a mouse click — read the help off the row
they land on just as \\<dial-mode-map>\\[dial-next-line] and
\\[dial-previous-line] do, rather than the help being a privilege of
dial's own keys. Only a change of row speaks: staying on the row, or
stepping along its values, must not repeat the doc over whatever the
command itself just said. Rows without an id — the controls line, the
gaps between groups — echo nothing and count as no row."
  (let ((row (dial--item-id-at-point)))
    (unless (equal row dial--echoed-row)
      (setq dial--echoed-row row)
      (when row (dial--echo-doc)))))

(defun dial--item-id-at-point ()
  "The item ID of the row point is on, or nil off any setting row."
  (and (dial--setting-line-p) (tabulated-list-get-id)))

(defun dial--print (&optional remember-pos)
  "Print the controls line and the list, honoring REMEMBER-POS.
`tabulated-list-print' erases the buffer, so the controls are written
again after every print rather than once. Every path that reprints goes
through here, \\`g' included — it runs `dial-refresh' rather than
`revert-buffer' so that reverting cannot drop the line.

The line goes in the buffer rather than the header line, which is
already showing the column names, and is inserted after printing so
REMEMBER-POS still measures against the rows alone."
  (tabulated-list-print remember-pos)
  (let ((inhibit-read-only t)
        (line (concat (dial--controls-line) "\n")))
    ;; Appended rather than propertized on, so the band fills in behind
    ;; the keys without painting over the face that picks them out.
    (add-face-text-property 0 (length line) 'dial-controls t line)
    (save-excursion
      (goto-char (point-min))
      (insert line "\n")))
  (if (dial--setting-line-p)
      (dial--goto-option)
    (goto-char (point-min))
    (dial--move-line 1)))

(define-derived-mode dial-mode tabulated-list-mode "dial"
  "Major mode for a dial options buffer.
Each row is one setting: its group, name, every value it can take with
the live one highlighted, and optionally a reference key.

\\<dial-mode-map>\\[dial-next-line] and
\\[dial-previous-line] move between settings, echoing a line on
what the one under point does — as does any motion that lands on
another row, C-n and C-p included; \\[dial-next-group] and
\\[dial-previous-group] move a whole group at a time.

\\[dial-next-value] steps point along
the row's values without setting any of them, and \\[dial-set]
sets the one point is on — two acts on two keys, because a setter is
free to prompt and stepping cannot be made to wait on it.
\\[dial-reset] restores the default;
\\[dial-toggle-changed-only] narrows the list to settings that
differ from their default; \\[dial-toggle-keys] shows the reference
keys; \\[quit-window] buries the buffer.

Dial buffers are built by `dial-open', which is where the settings
themselves come from."
  (setq tabulated-list-padding 1
        ;; No sort key: rows print in table order, which is what keeps
        ;; each :group's entries together under its heading.
        tabulated-list-sort-key nil)
  (add-hook 'tabulated-list-revert-hook #'dial--refresh nil t)
  (add-hook 'post-command-hook #'dial--echo-on-move nil t)
  (dial--apply-format))

(defun dial--refresh ()
  "Rebuild `tabulated-list-entries' from `dial-items'.
A blank row separates each :group from the next. Its id is a cons
rather than an item ID, which is what `dial--item' reads as \"no
setting on this line\" — and being distinct per group, it also leaves
`tabulated-list-print' able to put point back where it was."
  (let (entries last-group)
    (dolist (entry dial-items)
      (let* ((id (car entry))
             (spec (cdr entry))
             (group (plist-get spec :group))
             (changed (dial--changed-p id spec)))
        (unless (and dial--changed-only (not changed))
          (unless (or (null last-group) (equal group last-group))
            (push (list (cons 'gap group)
                        (make-vector (length tabulated-list-format) ""))
                  entries))
          (push (list id
                      (vconcat
                       (vector (if (equal group last-group)
                                   ""
                                 (propertize group 'face 'dial-group))
                               (plist-get spec :label))
                       (when (dial--keys-shown-p)
                         (vector (or (plist-get spec :keys) "")))
                       (vector (dial--value-column id spec))))
                entries)
          (setq last-group group))))
    (setq tabulated-list-entries (nreverse entries))))

(defun dial--redraw (id spec &optional echo)
  "Redraw the list, keeping point on the same row, and echo ID's value.
SPEC is ID's entry in `dial-items'. Both are passed in from the command
that just set ID, rather than re-read from the row, so the echo reports
what was set even if the row has moved. ECHO, when non-nil, is said in
place of the label-and-value message — how the stepping path shows a
row's example instead.

Clears `dial--pending' — every path through here has just set the
setting, by whatever route, so a value still waiting to be set is no
longer waiting for anything. `dial-next-value' redraws without this
when it is the one leaving a value pending."
  (setq dial--pending nil)
  (dial--refresh)
  (dial--print t)
  (message "%s" (or echo
                    (format "%s: %s" (plist-get spec :label)
                            (dial--value-string id spec)))))

(defun dial-refresh ()
  "Re-read every setting and redraw the list."
  (interactive)
  (dial--refresh)
  (dial--print t))

(defun dial--group-starts ()
  "Return the position of each group's first setting, in buffer order.
Read off the printed rows rather than the item table, so the filtered
list navigates by the groups it is actually showing."
  (save-excursion
    (goto-char (point-min))
    (let (starts last)
      (while (not (eobp))
        (let ((id (tabulated-list-get-id)))
          (when (and id (symbolp id))
            (let ((group (plist-get (alist-get id dial-items) :group)))
              (unless (equal group last)
                (push (line-beginning-position) starts)
                (setq last group)))))
        (forward-line 1))
      (nreverse starts))))

(defun dial--goto-group (n)
  "Move N groups on, backwards for a negative N.
Moving back from inside a group lands on its own first row before going
any further, the way paragraph motion does."
  (let* ((starts (dial--group-starts))
         (here (line-beginning-position))
         (pos here))
    (dotimes (_ (abs n))
      (setq pos (or (if (> n 0)
                        (seq-find (lambda (p) (> p pos)) starts)
                      (car (last (seq-filter (lambda (p) (< p pos)) starts))))
                    pos)))
    (when (= pos here)
      (user-error "No %s group" (if (> n 0) "next" "previous")))
    (goto-char pos)
    (dial--goto-option)))

(defun dial-next-group (&optional n)
  "Move to the first setting of the next group, or N groups on."
  (interactive "p")
  (dial--goto-group (or n 1))
  (dial--echo-doc))

(defun dial-previous-group (&optional n)
  "Move to the first setting of the previous group, or N groups back."
  (interactive "p")
  (dial--goto-group (- (or n 1)))
  (dial--echo-doc))

(defun dial--item ()
  "Return (ID . SPEC) for the setting on the current line.
Signals on a group separator, whose id names no setting."
  (let* ((id (tabulated-list-get-id))
         (spec (and (symbolp id) (alist-get id dial-items))))
    (unless spec (user-error "No setting on this line"))
    (cons id spec)))

;; Stepping through a row sets each value as it lands on it — the point
;; of the row is to try the values, and having to confirm every one
;; would halve the speed of the thing.
;;
;; With one exception, which is why setting has a key of its own: a
;; setter is free to prompt. Applying a prompting value on the way past
;; it would stop dead, and the step could not reach the value after it
;; until the prompt was answered. So a prompting value is stepped onto
;; and left alone, and `dial-set' is what runs it.

(defun dial--describe (spec value)
  "The description echo for stepping onto VALUE, or nil.
Nil without a :describe function, and nil when the function answers
nil. The value's label heads the text —

  native

  maf's opinionated layout (the default)

— so the echo names where the step landed before saying what it means."
  (when-let* ((fn (plist-get spec :describe))
              (text (funcall fn (car value))))
    (format "%s

%s" (nth 1 value) text)))

(defun dial--example (spec value)
  "Return the example echoed after stepping SPEC's item to value entry VALUE.
Nil without an :example function, and nil when the function answers nil
— how a row says no example applies to this value. Called after the
setter has run, so the function may read the state the value just
produced.

Two lines: the option and the value just landed on, then the example —

  Digit grouping: off
  Example: 999999

— so what changed is legible without looking back at the row.

Only the stepping path shows this, in place of the label-and-value
echo: stepping is a tour of the values, which is where a sample of each
one's output earns its keep. `dial-set' and `dial-reset' land on a
value already chosen, so they keep the plain echo."
  (when-let* ((fn (plist-get spec :example))
              (sample (funcall fn (car value))))
    (format "%s: %s\nExample: %s"
            (plist-get spec :label) (nth 1 value) sample)))

(defun dial--prompts-p (value)
  "Non-nil when VALUE's setter asks the user for the value it sets.
Declared by the entry itself — :prompts in the plist after the setter —
because the setter is an opaque form: whether the consumer wrote it as
a `call-interactively', a prompting helper, or anything else is not
dial's to guess at."
  (plist-get (cdddr value) :prompts))

(defun dial-next-value (&optional n)
  "Set this row's setting to its next value, or the one N values on.
Wraps at the end of the row, and steps on from the value last stepped
onto rather than from the live one, so a value that could not be set
is still a place to carry on from.

A value whose setter prompts is stepped onto and marked, not set:
running it would stop for an answer, and the step could not reach the
value after it until that answer came. \\<dial-mode-map>\\[dial-set]
runs that one."
  (interactive "p")
  (pcase-let* ((`(,id . ,spec) (dial--item))
               (values (dial--values spec))
               (count (length values)))
    (when (zerop count)
      (user-error "%s takes no fixed set of values — %s prompts for one"
                  (plist-get spec :label)
                  (dial--key #'dial-set "RET")))
    (let* ((from (or (dial--pending-index id)
                     (seq-position values (dial--current id spec)
                                   (lambda (v c) (equal (car v) c)))
                     0))
           (index (mod (+ from (or n 1)) count))
           (value (nth index values)))
      (if (dial--prompts-p value)
          (progn
            (setq dial--pending (cons id index))
            (dial--refresh)
            (dial--print t)
            (message "%s needs a value — %s to enter it" (nth 1 value)
                     (dial--key #'dial-set "RET")))
        (setq dial--pending nil)
        (dial--apply (nth 2 value))
        (dial--redraw id spec (or (dial--describe spec value)
                                  (dial--example spec value)))))))

(defun dial-previous-value (&optional n)
  "Set this row's setting to its previous value, or the one N values back."
  (interactive "p")
  (dial-next-value (- (or n 1))))

(defun dial-set ()
  "Set this row's setting to the value stepped onto but not yet set.
That is the one case \\<dial-mode-map>\\[dial-next-value]
leaves undone, since running it means answering a prompt. With nothing
stepped onto, prompts anyway when the setting takes no fixed set of
values — for those, being asked is the only way to set them at all."
  (interactive)
  (pcase-let* ((`(,id . ,spec) (dial--item))
               (values (dial--values spec))
               (index (dial--pending-index id)))
    (cond (index (dial--apply (nth 2 (nth index values)))
                 (setq dial--pending nil))
          ((plist-get spec :read) (dial--apply (plist-get spec :read)))
          (t (user-error "Nothing waiting to be set — %s steps through the values"
                         (dial--key #'dial-next-value "TAB"))))
    (dial--redraw id spec)))

(defun dial-reset ()
  "Restore the current line's setting to its default.
A setting with a named value for its default is put back by asking for
that value, so whatever else its setter does still happens. A setting
whose values are open has no such setter: those go back through the
consumer's write function, which puts the default value where the
setting lives — unless the spec gives a :reset form, which is how a
setting whose reset does more than that says so."
  (interactive)
  (pcase-let* ((`(,id . ,spec) (dial--item))
               (entry (dial--default-entry id spec)))
    (cond ((plist-get spec :reset) (dial--apply (plist-get spec :reset)))
          (entry (dial--apply (nth 2 entry)))
          ((and dial--write-fn dial--default-fn)
           (funcall dial--write-fn id (dial--default id)))
          (t (user-error "No default to reset to")))
    ;; Landing on a named value echoes as stepping onto it would —
    ;; the description or example belongs to the value, not the path
    ;; that reached it.
    (dial--redraw id spec (and entry
                               (or (dial--describe spec entry)
                                   (dial--example spec entry))))))

(defun dial-save ()
  "Persist every setting's current value, however the consumer does that."
  (interactive)
  (unless dial--save-fn
    (user-error "Nowhere to save these settings"))
  (funcall dial--save-fn))

(defun dial-toggle-keys ()
  "Show or hide the reference-key column."
  (interactive)
  (unless dial--keys-name
    (user-error "No key column here"))
  (setq dial--show-keys (not dial--show-keys))
  (dial--apply-format)
  (dial--refresh)
  (dial--print t))

(defun dial-toggle-changed-only ()
  "Toggle between all settings and only those changed from default.
Refuses without a default function to compare against — without one
every row would count as unchanged, and the filter would empty the
buffer rather than narrow it."
  (interactive)
  (unless dial--default-fn
    (user-error "No defaults here to filter by"))
  (setq dial--changed-only (not dial--changed-only))
  (dial--refresh)
  (dial--print t)
  (message "Showing %s settings"
           (if dial--changed-only "changed" "all")))

(defun dial-describe (&optional select)
  "Show the current row's details in another window.
The help echoed as point rests on a row is transient — the next
message replaces it — and sized to the echo area. This puts the row's
full text in a buffer instead, displayed without leaving the list, so
it stands while the rows are worked. The text is the row's :details,
built fresh when it is a function so it can read live state, or its
echoed :doc for a row that carries nothing fuller; a row with neither
has nothing to show and says so.

One details buffer per dial buffer, named after its mode-line name,
so asking about another row replaces the text rather than piling up
buffers — and two dial buffers open at once keep separate ones.

With SELECT — interactively, a prefix argument — the details window
is also selected, for reading at length; `dial-describe-visit' is
the key that says it directly."
  (interactive "P")
  (pcase-let* ((`(,id . ,spec) (dial--item))
               (details (plist-get spec :details))
               (text (cond ((functionp details) (funcall details id))
                           (details details)
                           (t (plist-get spec :doc)))))
    (unless text (user-error "No details for this setting"))
    (let ((buffer (get-buffer-create
                   (format "*%s details*" (format-mode-line mode-name)))))
      (with-current-buffer buffer
        (let ((inhibit-read-only t))
          (erase-buffer)
          (insert text)
          (goto-char (point-min)))
        (special-mode))
      (if select
          (pop-to-buffer buffer)
        (display-buffer buffer)))))

(defun dial-describe-visit ()
  "Show the current row's details in another window and go there.
`dial-describe' with the window selected: for reading at length —
scrolling, searching, copying — where the glance leaves point on the
list. \`q' in the details buffer comes back."
  (interactive)
  (dial-describe t))

;;; Opening

(cl-defun dial-open (buffer items &key raw default apply write save
                            keys-name controls name init)
  "Show a dial buffer named BUFFER over ITEMS; return the buffer.
ITEMS is an alist of (ID . SPEC) — see this file's commentary. The
keyword arguments are the consumer's half of the contract:

  :raw       Function (ID) -> the item's current raw value.
  :default   Function (ID) -> the item's default raw value, or nil
             when defaults are not a meaningful notion here.
  :apply     Function (FORM) evaluating a setter form wherever it
             needs to run. Defaults to plain evaluation.
  :write     Function (ID VALUE) writing a raw value directly, the
             reset path of last resort — see `dial-reset'.
  :save      Function () persisting the settings, or nil to make
             \\<dial-mode-map>\\[dial-save] refuse.
  :keys-name Header for the reference-key column, or nil for none.

Each optional capability left nil also drops its control from the
controls line — no :save loses the save control, no :keys-name the
key-column toggle, no :default the changed-only filter. Reset and the
changed highlight outlive the :default callback wherever an item carries
its own :default or :reset — see `dial--control-available-p'.
  :controls  Controls-line entries overriding `dial-default-controls'.
  :name      Mode-line name for the buffer, in place of \"dial\".
  :init      Function () run in the buffer after the mode starts and
             before the first render, for consumer buffer-locals the
             other functions read.

Reopening an existing BUFFER rebuilds it from scratch."
  (let ((buf (get-buffer-create buffer)))
    (with-current-buffer buf
      (dial-mode)
      (when name (setq mode-name name))
      (setq dial-items items
            dial--raw-fn (or raw #'symbol-value)
            dial--default-fn default
            dial--apply-fn (or apply (lambda (form) (eval form t)))
            dial--write-fn write
            dial--save-fn save
            dial--keys-name keys-name
            dial-controls controls)
      (when init (funcall init))
      (dial--apply-format)
      (dial--refresh)
      (dial--print))
    (pop-to-buffer buf)
    buf))

(provide 'dial)
