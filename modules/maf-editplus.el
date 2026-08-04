;; -*- lexical-binding: t; -*-
;;
;; modules/maf-editplus.el
;;
;; maf-editplus: the home for everything that changes how it feels to
;; work *inside* a maf-edit session. maf-edit itself owns the session —
;; entering, the entry/prefix machinery, committing — and its keymap is
;; deliberately thin, so that plain typing works. This module is where
;; the in-entry conveniences go: keys that only mean anything while the
;; stack is editable text, installed into `maf-edit-mode-map' and taken
;; back out when the module is off.
;;
;; What is here now are the two paren gestures, TAB and M-o, the
;; function keys L, Q and |, the exponent keys M-2 through M-9 and :,
;; and P for the constant pi.
;;
;; TAB escapes. Typing a formula runs forward past closing delimiters
;; constantly — sqrt(x^2+1), f(g(x)) — and reaching the far side of one
;; by hand means either counting right-arrows or typing a closer that
;; `electric-pair-mode' has already put there. TAB jumps point past the
;; delimiter that closes the group it stands in, once per press, so
;; nested groups peel off one level at a time and a formula can be typed
;; left to right without ever moving point backwards.
;;
;; M-o wraps. The other half of the same problem: parentheses wanted
;; around text already typed, where opening one by hand means going back
;; to find where the term starts. M-o puts them around the term before
;; point, and pressing it again widens that pair one operator at a time
;; — the paren pair walks outward instead of being placed by hand.
;;
;; L, Q and | apply a function. The term M-o would have put parens
;; around is also the term a function should be applied to, so these
;; reuse that scan and write ln, sqrt or abs in front of the pair — an
;; expression already typed becomes the log, the root or the modulus of
;; itself without going back to find where it starts.
;;
;; M-2..M-9 and : raise to a power. An exponent is two characters that
;; interrupt a formula being typed, and the digit is nearly always
;; small: the meta-digits write ^2 through ^9 outright, and : writes ^2
;; and then counts up, one press per power, for the times the exponent
;; is easier to reach for than to name.
;;
;; The scan is maf-edit's own: any closer matches any opener (calc's
;; interval notation mixes them — (1 .. 2]), machine-owned prefix
;; characters are not text, and it never leaves the entry point is in,
;; so a neighbouring entry left unbalanced mid-typing cannot drag the
;; gesture off the end of this one.
;;
;; The module toggle is `maf-use-editplus-mode', registered with the
;; module system as `maf-editplus' (see `maf-modules').

(require 'seq)
(require 'maf-edit)          ; the session this module extends
(require 'maf-conf "conf")   ; the `maf' customize group

(defconst maf-editplus--openers '(?\( ?\[ ?\{)
  "Characters that open a group, as maf-edit counts depth.")

(defconst maf-editplus--closers '(?\) ?\] ?\})
  "Characters that close a group, as maf-edit counts depth.
Any closer matches any opener — see `maf-edit--depth'.")

(defun maf-editplus--entry-at-point ()
  "The maf-edit entry overlay covering point, or nil.
Nil means point is somewhere no entry covers: the home line, or a
blank line not yet adopted by the repair pass.

Entry overlays are rear-advancing and end just before the newline, so
`overlays-at' misses one when point rests at its very end — the usual
place to press one of these keys. Hence the widened scan and the
explicit inclusive containment test."
  (seq-find
   (lambda (ov)
     (and (overlay-get ov 'maf-edit-entry)
          (<= (overlay-start ov) (point))
          (<= (point) (overlay-end ov))))
   (overlays-in (max (point-min) (1- (point)))
                (min (point-max) (1+ (point))))))

(defun maf-editplus--entry-bounds ()
  "Bounds of the maf-edit entry point is in, as a cons of positions.
Falls back to the current line for a point no entry covers."
  (let ((o (maf-editplus--entry-at-point)))
    (if o
        (cons (overlay-start o) (overlay-end o))
      (cons (line-beginning-position) (line-end-position)))))

(defun maf-editplus--group-end (from limit)
  "Position just after the closer of the group enclosing FROM, or nil.
Scans forward from FROM to LIMIT tracking delimiter depth: an opener
deepens it, and the first closer met at depth zero is the one that
closes the group point stands in. Returns nil when no such closer is
reached — point is at the top level of the entry, or inside a group
whose closer has not been typed yet.

Prefix and pad characters are skipped, as in `maf-edit--depth'. They
hold no delimiters today, so this changes nothing on its own; it keeps
the scan honest about what is entry text and what is furniture."
  (let ((depth 0)
        (found nil))
    (save-excursion
      (goto-char from)
      (while (and (not found) (< (point) limit))
        (unless (get-text-property (point) 'maf-edit-prefix)
          (let ((c (char-after)))
            (cond
             ((memq c maf-editplus--openers) (setq depth (1+ depth)))
             ((memq c maf-editplus--closers)
              (if (zerop depth)
                  (setq found (1+ (point)))
                (setq depth (1- depth)))))))
        (forward-char)))
    found))

(defun maf-editplus-escape-group ()
  "Move point past the delimiter closing the group it stands in.
Repeated invocations escape nested groups one level at a time:
sqrt(x^2+1) typed with point still on the 1 goes to just after the
closing paren, and a second press would leave the group enclosing
that one.

With no enclosing group left — point already at the entry's top level,
or inside a group whose closer is not typed yet — point goes to the end
of the entry instead, which is where escaping outward runs out. Never
leaves the entry it started in.

Only runs during a maf-edit session, as `maf-edit-commit' and
`maf-edit-discard' do. Outside one there are no entry overlays to
bound the scan, and the fallback to line bounds would walk point
across calc's rendered stack — a buffer this command has no business
in, and which the key never reaches anyway (it is bound in
`maf-edit-mode-map' alone; \\[execute-extended-command] is the only
way here)."
  (interactive)
  (unless maf-edit-mode
    (user-error "maf-edit is not active"))
  (let* ((bounds (maf-editplus--entry-bounds))
         (end (maf-editplus--group-end (point) (cdr bounds))))
    (goto-char (or end (cdr bounds)))))

;;; Wrapping in parentheses

(defconst maf-editplus--wrap-ops '(?+ ?- ?* ?/ ?^ ?% ?= ?< ?> ?, ?\;)
  "Characters that separate one term from the next.
Point standing just after one of these has no term behind it yet, and
the widening step crosses a whole run of them at once — so a
two-character operator (<=, !=) is one boundary rather than two, and
the opening paren can never land between its halves.")

(defconst maf-editplus--wrap-stops '(?\( ?\[ ?\{ ?, ?\; ?= ?< ?> ?+ ?- ?/ ?^ ?%)
  "Characters that end the backward scan for the term to wrap.
`maf-editplus--wrap-ops' apart from `*', plus the openers — a group's
own opener bounds the term written inside it, and is the one boundary
widening never crosses.

`*' is deliberately absent: a product is the innermost term worth
wrapping, so a+b*c wraps b*c and not c alone. `/' is present because
a denominator is a unit of its own — 27/sqrt(3) wraps the root.")

(defconst maf-editplus--wrap-tight '(?/ ?^ ?%)
  "Stops that bind at least as tightly as the `*' the scan crosses.
Meeting one of these after crossing a `*' means the parentheses would
regroup rather than merely group: a/b*c is not a/(b*c). The term is
cut back to the `*' there, so the first press never changes what the
entry means; a second press widens past the `/' deliberately.")

(defun maf-editplus--name-char-p (c)
  "Non-nil when C can appear in a function or variable name.
Tested by hand rather than through `char-syntax', for the same reason
the delimiter scans are hand-rolled: calc-mode's syntax table is not
the authority on what maf-edit's text means."
  (and c (string-match-p "[[:alnum:]_]" (char-to-string c))))

(defun maf-editplus--group-start (from limit)
  "Position of the opener of the group closing just before FROM, or nil.
FROM must be a position whose preceding character is a closer. Scans
backward to LIMIT tracking depth, the mirror of
`maf-editplus--group-end'; returns nil when the opener is not in
range — an entry whose opener has not been typed yet."
  (let ((depth 0)
        (pos from)
        (found nil))
    (while (and (not found) (> pos limit))
      (setq pos (1- pos))
      (unless (get-text-property pos 'maf-edit-prefix)
        (let ((c (char-after pos)))
          (cond
           ((memq c maf-editplus--closers) (setq depth (1+ depth)))
           ((memq c maf-editplus--openers)
            (setq depth (1- depth))
            (when (zerop depth) (setq found pos)))))))
    found))

(defun maf-editplus--skip-fill-back (pos limit)
  "POS moved back over whitespace and machine-owned characters, to LIMIT.
Prefix and pad runs are furniture, not entry text — `maf-edit--entry-text'
drops them and joins the lines with a space — so a line break inside a
multi-line entry is just more whitespace to this scan."
  (while (and (> pos limit)
              (or (get-text-property (1- pos) 'maf-edit-prefix)
                  (memq (char-before pos) '(?\s ?\t ?\n))))
    (setq pos (1- pos)))
  pos)

(defun maf-editplus--skip-fill-forward (pos bound)
  "POS moved forward over whitespace and machine-owned characters, to BOUND.
The forward counterpart of `maf-editplus--skip-fill-back': it keeps an
opening paren off the furniture and off the space that follows an
operator, so `= pi+2' wraps as `= (pi+2)'."
  (while (and (< pos bound)
              (or (get-text-property pos 'maf-edit-prefix)
                  (memq (char-after pos) '(?\s ?\t ?\n))))
    (setq pos (1+ pos)))
  pos)

(defun maf-editplus--skip-name-back (pos limit)
  "POS moved back over the identifier ending just before it, to LIMIT.
The name in front of an argument list belongs to it: sqrt(3) is one
unit to the wrap scan, not a group with a stray sqrt beside it."
  (while (and (> pos limit)
              (maf-editplus--name-char-p (char-before pos)))
    (setq pos (1- pos)))
  pos)

(defconst maf-editplus--atom-inner '(?. ?:)
  "Punctuation that lies inside a number: 2.5, and calc's fraction 3:4.
Each only counts with a digit on the far side of it, which is what
keeps the `..' of an interval — and the `:' of a conditional — out.")

(defun maf-editplus--atom-char-p (pos)
  "Non-nil when the character at POS carries on the atom before it.
Name characters do, and so does one of `maf-editplus--atom-inner' with
a digit after it."
  (let ((c (char-after pos)))
    (and c
         (or (maf-editplus--name-char-p c)
             (and (memq c maf-editplus--atom-inner)
                  (let ((next (char-after (1+ pos))))
                    (and next (<= ?0 next) (<= next ?9))))))))

(defun maf-editplus--atom-before-p (pos)
  "Non-nil when the character before POS is part of an atom.
The counterpart of `maf-editplus--atom-char-p' for the other side of
point: a name character, or inner punctuation with the number's first
half in front of it, so 2.|5 counts as standing inside 2.5."
  (let ((c (char-before pos)))
    (and c
         (or (maf-editplus--name-char-p c)
             (and (memq c maf-editplus--atom-inner)
                  (maf-editplus--name-char-p (char-before (1- pos))))))))

(defun maf-editplus--atom-end (pos bound)
  "POS moved forward past the atom it stands inside, no further than BOUND.
Point between two characters of one number or name is inside an atom,
not between two terms: 1|2 is the number 12, and wrapping there must
take both digits. An argument list comes along with the name it
belongs to, so a press inside sqrt(3) wraps the call and does not cut
the head off it.

POS is returned untouched unless point really is inside an atom —
just before one is still just after whatever precedes it, and that is
what the wrap is about."
  (if (not (and (maf-editplus--atom-before-p pos)
                (maf-editplus--atom-char-p pos)))
      pos
    (while (and (< pos bound) (maf-editplus--atom-char-p pos))
      (setq pos (1+ pos)))
    (or (and (memq (char-after pos) maf-editplus--openers)
             (maf-editplus--group-end (1+ pos) bound))
        pos)))

(defun maf-editplus--term-start (from limit)
  "Start of the term ending at FROM, scanning back no further than LIMIT.
Ordinary characters are crossed one at a time, a balanced group (with
its function name) is crossed as a single unit, and the scan stops
before the first character in `maf-editplus--wrap-stops'. An
unbalanced closer stops it where it stands, so a group whose opener
has not been typed yet cannot drag the term past it.

A leading sign is part of the term it signs — 2*-3 wraps as 2*(-3) —
so the scan crosses it and stops there, nothing further left being
able to join that term.

Crossing a `*' is taken back when the scan then stops at a tighter
operator — see `maf-editplus--wrap-tight'."
  (let ((pos from) (star nil) (stop nil))
    (while (and (not stop) (> pos limit))
      (let ((c (char-before pos)))
        (cond
         ((get-text-property (1- pos) 'maf-edit-prefix) (setq pos (1- pos)))
         ((memq c maf-editplus--wrap-stops)
          (let ((before (maf-editplus--skip-fill-back (1- pos) limit)))
            (if (and (memq c '(?- ?+))
                     ;; Unary: a sign opening the entry, or following
                     ;; another operator or an opener.
                     (or (<= before limit)
                         (memq (char-before before) maf-editplus--wrap-ops)
                         (memq (char-before before) maf-editplus--openers)))
                ;; What stopped the scan is then whatever precedes the
                ;; sign, which still decides the `*' question below.
                (setq pos (1- pos)
                      stop (or (char-before before) t))
              (setq stop c))))
         ((memq c maf-editplus--closers)
          (let ((open (maf-editplus--group-start pos limit)))
            (if open
                (setq pos (maf-editplus--skip-name-back open limit))
              (setq stop t))))
         (t
          (when (eq c ?*) (setq star (1- pos)))
          (setq pos (1- pos))))))
    (if (and star (memq stop maf-editplus--wrap-tight))
        (1+ star)
      pos)))

(defun maf-editplus--wrap-open (from limit)
  "Position of the `(' of a bare parenthesized group ending at FROM, or nil.
A pair this command could have placed: parens (not brackets or
braces), with no identifier in front of them. An argument list —
sqrt(3) — and a vector are structure, and widening them would mean
deleting a delimiter the entry needs."
  (let ((open (maf-editplus--group-start from limit)))
    (and open
         (eq (char-after open) ?\()
         (not (maf-editplus--name-char-p
               (char-before (maf-editplus--skip-fill-back open limit))))
         open)))

(defun maf-editplus--wrap (start end &optional name)
  "Put parentheses around START..END, leaving point after the closer.
With NAME, the pair is the argument list of a call to it — NAME(...)
rather than (...).

Point lands where the next press expects it, so wrapping and widening
are the same key pressed again."
  (let ((m (copy-marker end t)))
    (save-excursion
      (goto-char m) (insert ")")
      (goto-char start) (insert (concat name "(")))
    (goto-char m)
    (set-marker m nil)
    nil))

(defun maf-editplus-wrap-parens ()
  "Wrap the term before point in parentheses; press again to widen.
The term is what the backward scan finds: a number or name, a
function call or bracketed group taken whole, a product — stopping at
the first looser operator (`maf-editplus--wrap-stops'). Point ends up
just after the closing paren.

  pi+2|        =>  pi+(2)
  a+b*c|       =>  a+(b*c)
  27/sqrt(3)|  =>  27/(sqrt(3))
  2*-3|        =>  2*(-3)

The first press only ever groups what is already one term, so it
never changes what the entry means: a/b*c wraps c alone, since
a/(b*c) is a different expression. An atom is never split either —
pressed with point inside the number 12 the parens go around both
digits, not between them.

From there the same key widens the pair it just placed, one operator
at a time, rather than nesting a second pair inside it: pi+(2) becomes
\(pi+2), and widening is where a regrouping can happen — deliberately,
one press at a time. Only a bare pair widens; an argument list and a
vector are structure, and a press beside one wraps it instead. When
there is nothing left to take in, the pair stays as it is.

With an active region the region is wrapped exactly as marked, and
point again ends after the closer, so widening can carry on from
there.

Runs only during a maf-edit session, and only inside an entry: the
home line and a blank pending line have no term to wrap."
  (interactive)
  (unless maf-edit-mode
    (user-error "maf-edit is not active"))
  (let ((entry (or (maf-editplus--entry-at-point)
                   (user-error "Point is not in a stack entry"))))
    (let ((limit (+ (overlay-start entry)
                    (maf-edit--leading-prefix-run (overlay-start entry)))))
      (if (use-region-p)
          (let ((beg (max (region-beginning) limit))
                (end (region-end)))
            (when (> end (overlay-end entry))
              (user-error "Region reaches past the entry"))
            (when (>= beg end)
              (user-error "Nothing to wrap"))
            (deactivate-mark)
            (maf-editplus--wrap beg end))
        ;; Trailing whitespace is not part of the term, and skipping it
        ;; is also what makes a press after `) ' widen rather than nest.
        ;; An atom point stands inside is not split: 1|2 wraps as (12).
        (let* ((end (maf-editplus--atom-end
                     (maf-editplus--skip-fill-back (point) limit)
                     (overlay-end entry)))
               (open (and (eq (char-before end) ?\))
                          (maf-editplus--wrap-open end limit))))
          (if open
              ;; Widen. The closer already sits at the end of the term,
              ;; so only the opener travels; point, being past the
              ;; closer, is left where it stands by the two edits.
              (let* ((outer (maf-editplus--skip-fill-back open limit))
                     ;; Cross the operator that stopped the previous
                     ;; scan, then scan on from there. Anything else in
                     ;; front of the pair — a closer, a name — the scan
                     ;; takes as the unit it is, and an opener is a wall
                     ;; it stops at, leaving the pair where it is.
                     (from (let ((p outer))
                             (while (and (> p limit)
                                         (memq (char-before p)
                                               maf-editplus--wrap-ops))
                               (setq p (1- p)))
                             p))
                     (start (maf-editplus--skip-fill-forward
                             (maf-editplus--term-start from limit) open)))
                (when (>= start outer)
                  (user-error "Nothing left to wrap"))
                (save-excursion
                  (goto-char open) (delete-char 1)
                  (goto-char start) (insert "(")))
            ;; Just after an operator there is no term yet — the legacy
            ;; version wrapped one into an empty pair.
            (when (memq (char-before end) maf-editplus--wrap-ops)
              (user-error "Nothing to wrap"))
            (let ((start (maf-editplus--skip-fill-forward
                          (maf-editplus--term-start end limit) end)))
              (when (>= start end)
                (user-error "Nothing to wrap"))
              (maf-editplus--wrap start end))))))))

;;; Applying a function

(defun maf-editplus--apply-function (name)
  "Wrap the term before point, or the active region, in a call to NAME.
The same scan `maf-editplus-wrap-parens' uses decides what the term is,
so the two gestures always take hold of the same text — this one just
writes a name in front of the pair.

With no term behind point — the head of an entry, or just after an
operator — an empty call is inserted instead and point goes inside it,
so the argument can be typed next. That is the one place this differs
from wrapping in bare parens, which refuses there: an empty pair means
nothing, while NAME() is a call waiting for its argument."
  (unless maf-edit-mode
    (user-error "maf-edit is not active"))
  (let* ((entry (or (maf-editplus--entry-at-point)
                    (user-error "Point is not in a stack entry")))
         (limit (+ (overlay-start entry)
                   (maf-edit--leading-prefix-run (overlay-start entry)))))
    (if (use-region-p)
        (let ((beg (max (region-beginning) limit))
              (end (region-end)))
          (when (> end (overlay-end entry))
            (user-error "Region reaches past the entry"))
          (when (>= beg end)
            (user-error "Nothing to wrap"))
          (deactivate-mark)
          (maf-editplus--wrap beg end name))
      (let* ((end (maf-editplus--atom-end
                   (maf-editplus--skip-fill-back (point) limit)
                   (overlay-end entry)))
             (start (unless (memq (char-before end) maf-editplus--wrap-ops)
                      (maf-editplus--skip-fill-forward
                       (maf-editplus--term-start end limit) end))))
        (if (and start (< start end))
            (maf-editplus--wrap start end name)
          ;; No term: open an empty call at point rather than at END,
          ;; which the scan has already pulled back over any trailing
          ;; whitespace — `2 + ' should become `2 + ln()', not `2 +ln() '.
          (insert name "()")
          (backward-char))))))

(defun maf-editplus-wrap-ln ()
  "Apply ln to the term before point.
The term is what `maf-editplus-wrap-parens' would wrap — a number or
name, a function call or bracketed group taken whole, a product — and
point ends up just after the closing paren:

  x+2|         =>  x+ln(2)
  27/sqrt(3)|  =>  27/ln(sqrt(3))
  ln(x)|       =>  ln(ln(x))
  x = |        =>  x = ln(|)

An active region becomes the argument exactly as marked. With nothing
behind point an empty ln() is opened instead, point inside it.

Bound to `L' in `maf-edit-mode-map', so a capital L is no longer
self-inserting during a session — see `maf-use-editplus-mode' on what
that costs."
  (interactive)
  (maf-editplus--apply-function "ln"))

(defun maf-editplus-wrap-sqrt ()
  "Apply sqrt to the term before point.
`maf-editplus-wrap-ln' with a different name written in front of the
pair — the same scan decides what the term is, and the same rules
apply to a region and to a press with nothing behind point:

  x+2|       =>  x+sqrt(2)
  x = |      =>  x = sqrt(|)

Bound to `Q' in `maf-edit-mode-map', the letter calc gives the root on
the stack, so a capital Q is no longer self-inserting during a session."
  (interactive)
  (maf-editplus--apply-function "sqrt"))

(defun maf-editplus-wrap-abs ()
  "Apply abs to the term before point.
`maf-editplus-wrap-ln' with a different name written in front of the
pair — the same scan decides what the term is, and the same rules
apply to a region and to a press with nothing behind point:

  a+b*c|     =>  a+abs(b*c)
  x = |      =>  x = abs(|)

Bound to `|' in `maf-edit-mode-map', which costs the character its own
key for the length of a session — calc reads it as vector
concatenation, and one wanted literally has to be yanked in."
  (interactive)
  (maf-editplus--apply-function "abs"))

;;; Raising to a power

(defun maf-editplus-insert-power ()
  "Insert `^N' for the digit of the key that invoked this command.
Bound to M-2 through M-9, so the exponent a formula wants next is one
keypress rather than two characters typed around the shift key:

  x|         =>  x^3      (M-3)

The digit is taken from the key itself, so the eight bindings are one
command. Nothing is examined behind point: an exponent already there
is left alone and this one stacks on it, x^2 M-3 giving the tower
x^2^3. It is `maf-editplus-raise-power' that edits an exponent in
place.

The keys are the meta-digits Emacs otherwise reads as a numeric
prefix, which a maf-edit session therefore takes by \\[universal-argument]
alone."
  (interactive)
  (let ((d (event-basic-type last-command-event)))
    (unless (and (integerp d) (<= ?2 d) (<= d ?9))
      (user-error "Not a power key"))
    (insert ?^ d)))

(defun maf-editplus-raise-power (n)
  "Insert `^2', or count an exponent already before point up by one.
N times, from the prefix argument. The second press is the point: an
exponent reached for rather than named, one power per keypress.

  x|         =>  x^2  =>  x^3  =>  x^4

Only a run of digits immediately behind point, with the caret in front
of it, counts as that exponent — anything else and a fresh ^2 goes in.
So x^2 y counts as no exponent at all, and x^2* neither.

Bound to `:' in `maf-edit-mode-map'. The character itself is not lost:
`;' types it \(`maf-edit-insert-colon'), fractions being the reason it
has a key with no modifier at all."
  (interactive "p")
  (dotimes (_ n)
    (let* ((limit (line-beginning-position))
           (start (save-excursion (skip-chars-backward "0-9" limit) (point))))
      (if (and (< start (point)) (eq (char-before start) ?^))
          (let ((power (string-to-number
                        (buffer-substring-no-properties start (point)))))
            (delete-region start (point))
            (insert (number-to-string (1+ power))))
        (insert "^2")))))

(defun maf-editplus-insert-pi (n)
  "Insert the constant pi, N times, on the unmodified `P' key.
Two characters for the price of one keypress; a capital P is no
longer self-inserting during a session — see `maf-use-editplus-mode'
on what that costs.

After a name character a space goes in first, so `x' becomes the
product `x pi' and not the unrelated variable `xpi'. Digits get the
space too: `2pi' would read back fine, but `x2' would not, and the
spaced form parses the same either way."
  (interactive "p")
  (dotimes (_ n)
    (when (and (char-before)
               (string-match-p "[[:alnum:]]" (string (char-before))))
      (insert " "))
    (insert "pi")))

;;; The module

(define-minor-mode maf-use-editplus-mode
  "Global minor mode installing the in-session keys into `maf-edit-mode-map'.
Enabled, and while a maf-edit session is up:

  TAB  `maf-editplus-escape-group' — point jumps past the delimiter
       that closes the group it is in, one level per press
  M-o  `maf-editplus-wrap-parens' — parentheses go around the term
       before point, and a further press widens that pair
  L    `maf-editplus-wrap-ln' — the same term becomes the argument of
       an ln call
  Q    `maf-editplus-wrap-sqrt' — and of a sqrt call
  |    `maf-editplus-wrap-abs' — and of an abs call
  M-2..M-9
       `maf-editplus-insert-power' — `^' and the digit pressed
  :    `maf-editplus-raise-power' — `^2', counting up a press at a time
  P    `maf-editplus-insert-pi' — the constant pi, typed as one key

Disabled, the keys cede back to whatever the global map does with them
\(`indent-for-tab-command', which has nothing to indent in an edited
stack, `self-insert-command' for the printable ones, `digit-argument'
for the meta-digits, and nothing at all for M-o, which Emacs 30 leaves
free). M-o runs `mafcmd-mod-360' in `maf-mode-map', which is not
competition: maf-mode is off for the duration of an edit session.

L, Q, |, : and P are unmodified printable keys, as
`maf-edit-insert-colon' already is: each costs its self-insertion for
the length of a session, and there is no cheap way back to the
character — \\[quoted-insert] is not one, since pausing to read a
character re-locks the calc buffer under the session and the insert
that follows fails (`maf-edit-insert-semicolon' exists for that
reason). Yanking one in is what is left. `:' is the cheapest of them,
`;' typing it anyway; the rest is the legacy config's trade, where the
wrap helpers were plain capitals too. The meta-digits cost the numeric
prefix its short form, leaving \\[universal-argument].

This is the `maf-editplus' module (see `maf-modules'). The keys only
live in maf-edit's own map, so they are inert unless a session is
running, and the module is a no-op for anyone not using maf-edit."
  :global t
  :group 'maf
  (let ((on maf-use-editplus-mode))
    (dolist (b '(("TAB" . maf-editplus-escape-group)
                 ("M-o" . maf-editplus-wrap-parens)
                 ("L"   . maf-editplus-wrap-ln)
                 ("Q"   . maf-editplus-wrap-sqrt)
                 ("|"   . maf-editplus-wrap-abs)
                 (":"   . maf-editplus-raise-power)
                 ("P"   . maf-editplus-insert-pi)))
      (define-key maf-edit-mode-map (kbd (car b)) (and on (cdr b))))
    ;; One command behind eight keys — it reads the digit off the key
    ;; that ran it.
    (dolist (d '(?2 ?3 ?4 ?5 ?6 ?7 ?8 ?9))
      (define-key maf-edit-mode-map (kbd (format "M-%c" d))
                  (and on #'maf-editplus-insert-power)))))

;; Register with the module system when it is present; the mode above
;; works on its own without it.
(when (require 'maf-module nil t)
  (maf-register-module 'maf-editplus #'maf-use-editplus-mode
                       "In-session keys for maf-edit (TAB escapes a group, M-o wraps one, L/Q/| apply ln/sqrt/abs, M-2..M-9 and : raise to a power, P types pi)."))

(provide 'maf-editplus)
