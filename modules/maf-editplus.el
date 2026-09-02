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
;; What is here now are the four delimiter gestures, TAB, M-o, C-RET
;; and the shifted arrows, the function keys L, Q, |, S, C, T and B,
;; the exponent keys M-2 through M-9 and :, P for the constant pi and
;; J for the multiplication sign, the union U that commit trades for
;; calc's ||, and DEL and C-d, which delete a power whole from either
;; side of its operator.
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
;; S-up and S-down retype a pair. The third thing wanted of a group
;; already typed, after escaping it and widening it: the parens around
;; it turning out to have been meant as the brackets of a vector. Both
;; ends move at once, which is what the character typed by hand cannot
;; do — except on an interval, where `[' and `(' say included and
;; excluded rather than merely opening the group, and the end point is
;; at moves alone.
;;
;; C-RET duplicates a pair. The fourth thing wanted of a group already
;; typed: a second one beside it differing in a character. (x+1)(x-1)
;; is the shape of half the algebra there is, and typing the copy out
;; again is the work the key saves — it writes the group after itself
;; and puts point at the matching place inside the copy, so the sign to
;; flip is where the fingers already are.
;;
;; L, Q, |, S, C, T and B apply a function. Point inside the text names
;; a sub-expression the way it does on the stack — the character under
;; point decides, an operand taking itself and an operator the node it
;; heads — and these write ln, sqrt, abs, sin, cos, tan or log around
;; that. At the end of the entry there is no character under point,
;; and the smallest complete unit ending at point is the argument
;; instead — the same unit `:' raises there — so a term just typed
;; becomes the log, the root, the modulus or a trig function of itself
;; without going back to find where it starts.
;;
;; M-2..M-9 and : raise to a power. An exponent is two characters that
;; interrupt a formula being typed, and the digit is nearly always
;; small: the meta-digits write ^2 through ^9 outright, and : squares
;; and then counts up, one press per power, for the times the exponent
;; is easier to reach for than to name. `:' names what it raises the
;; way L and Q name what they wrap — the sub-expression under point,
;; parenthesized where the text needs it — while the meta-digits write
;; their two characters at point and look at nothing.
;;
;; DEL and C-d un-raise. A power deleted is deleted whole: deleting
;; the caret from either side takes the exponent with it, since the
;; alternative is text that quietly means something else — x^3 minus
;; its caret reads as the one name x3. The parentheses the base
;; carried for the power's sake go too, where dropping them cannot
;; regroup the neighbours, so the keys give back what the raise
;; wrote. Everywhere else each is the plain deletion it always was.
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
(require 'cl-lib)            ; cl-labels, for the parse in this file
(require 'maf-edit)          ; the session this module extends
(require 'maf-conf "conf")   ; the `maf' customize group

(defconst maf-editplus--openers '(?\( ?\[ ?\{)
  "Characters that open a group, as maf-edit counts depth.")

(defconst maf-editplus--closers '(?\) ?\] ?\})
  "Characters that close a group, as maf-edit counts depth.
Any closer matches any opener — see `maf-edit--depth'.")

(defun maf-editplus--entry-at-point ()
  "The maf-edit entry overlay covering point, or nil.
maf-edit owns the entry machinery and the scan with it
\(`maf-edit--entry-at-point'); this is the name the keys here reach it
by."
  (maf-edit--entry-at-point))

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

(defun maf-editplus--digit-p (c)
  "Non-nil when C is a decimal digit."
  (and c (<= ?0 c) (<= c ?9)))

(defun maf-editplus--exponent-sign-p (pos)
  "Non-nil when the sign at POS is a number's exponent sign.
Calc reads 1e-3 as the one number (float 1 -3), so the `-' between
the exponent marker and its digits is not the operator it is
everywhere else: it lies inside the atom, and a scan that stops there
cuts a number in half.

Only between a digit and a digit. `x*e-3' and `ae-3' are the
subtractions they look like, the marker in each being part of a name
rather than the tail of a number."
  (and (memq (char-after pos) '(?- ?+))
       (memq (char-before pos) '(?e ?E))
       (maf-editplus--digit-p (char-before (1- pos)))
       (maf-editplus--digit-p (char-after (1+ pos)))))

(defun maf-editplus--radix-mark-p (pos)
  "Non-nil when the `#' at POS is a number's radix mark.
Calc writes a number in another base as 16#ff, one atom whose mark
sits between the base and its digits."
  (and (eq (char-after pos) ?#)
       (maf-editplus--digit-p (char-before pos))
       (maf-editplus--name-char-p (char-after (1+ pos)))))

(defun maf-editplus--atom-char-p (pos)
  "Non-nil when the character at POS carries on the atom before it.
Name characters do, and so does one of `maf-editplus--atom-inner' with
a digit after it, an exponent's sign (`maf-editplus--exponent-sign-p')
and a radix mark (`maf-editplus--radix-mark-p') — each of them
punctuation that lies inside one number rather than between two."
  (let ((c (char-after pos)))
    (and c
         (or (maf-editplus--name-char-p c)
             (and (memq c maf-editplus--atom-inner)
                  (maf-editplus--digit-p (char-after (1+ pos))))
             (maf-editplus--exponent-sign-p pos)
             (maf-editplus--radix-mark-p pos)))))

(defun maf-editplus--atom-before-p (pos)
  "Non-nil when the character before POS is part of an atom.
The counterpart of `maf-editplus--atom-char-p' for the other side of
point: a name character, or inner punctuation with the number's first
half in front of it, so 2.|5 counts as standing inside 2.5 — and
likewise the exponent sign and radix mark, whose far halves are
digits of the same number."
  (let ((c (char-before pos)))
    (and c
         (or (maf-editplus--name-char-p c)
             (and (memq c maf-editplus--atom-inner)
                  (maf-editplus--name-char-p (char-before (1- pos))))
             (maf-editplus--exponent-sign-p (1- pos))
             (maf-editplus--radix-mark-p (1- pos))))))

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
         ;; A number's exponent sign is not the operator it looks like:
         ;; 1e-3 is one atom, and stopping at the sign would wrap the
         ;; three alone.
         ((maf-editplus--exponent-sign-p (1- pos)) (setq pos (1- pos)))
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

(defun maf-editplus--wrap (start end &optional name tail)
  "Put parentheses around START..END, leaving point after the closer.
With NAME, the pair is the argument list of a call to it — NAME(...)
rather than (...). With TAIL, TAIL goes in between the wrapped text
and the closer: the further arguments of the call, so log with its
base is NAME(..., 10) from the one wrap.

Point lands where the next press expects it, so wrapping and widening
are the same key pressed again.

A NAME written directly after a letter would fuse with it into one
identifier heading the call — wrapping the b of ab as asqrt(b) — so a
space keeps the name its own word there: a sqrt(b), the product it
means."
  (let ((m (copy-marker end t))
        (sep (and name
                  (let ((c (char-before start)))
                    (and c (string-match-p "[[:alpha:]_]" (char-to-string c))
                         " ")))))
    (save-excursion
      (goto-char m) (insert (concat tail ")"))
      (goto-char start) (insert (concat sep name "(")))
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

;;; Toggling a group's delimiters

(defconst maf-editplus--bracket-toggle
  '((?\( . ?\[) (?\) . ?\])
    (?\[ . ?\() (?\] . ?\))
    (?\{ . ?\() (?\} . ?\)))
  "What each delimiter becomes when the group it belongs to is toggled.
Parens and brackets trade places. Braces are calc's third spelling of
a vector — it reads {1,2} as [1,2] and renders it back with brackets —
so they have no state of their own to hold: a brace group becomes a
paren group, and toggles between the two thereafter.")

(defun maf-editplus--enclosing-open (from limit)
  "Position of the opener of the group enclosing FROM, or nil.
Scans back to LIMIT for the first opener not closed again before FROM
— the mirror of `maf-editplus--group-end', and unlike
`maf-editplus--group-start' it starts from a point inside the group
rather than from just after its closer."
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
            (if (zerop depth) (setq found pos) (setq depth (1- depth))))))))
    found))

(defun maf-editplus--group-at-point (limit bound)
  "The group point is at, as a cons of its opener and closer positions.
Nil when there is none within LIMIT..BOUND, and nil too when only one
half of one is in range — a group still being typed has no pair to
toggle.

Point sitting on an opener takes the group that opens there, so a
press with point before `(' reads forward as the eye does. Failing
that, a closer just behind point takes the group that ends there, and
otherwise the group point stands inside."
  (let* ((open (cond
                ((memq (char-after) maf-editplus--openers) (point))
                ((memq (char-before) maf-editplus--closers)
                 (maf-editplus--group-start (point) limit))
                (t (maf-editplus--enclosing-open (point) limit))))
         (close (and open
                     (let ((end (maf-editplus--group-end (1+ open) bound)))
                       (and end (1- end))))))
    (and open close (cons open close))))

(defun maf-editplus--interval-dots (open close)
  "Position of the `..' making OPEN..CLOSE an interval, or nil.
Only at the group's own level: the dots of a nested interval belong to
that one, and the `.' of a decimal is never doubled. Prefix and pad
characters are skipped, as in the other scans."
  (let ((pos (1+ open))
        (depth 0)
        (found nil))
    (while (and (not found) (< pos close))
      (unless (get-text-property pos 'maf-edit-prefix)
        (let ((c (char-after pos)))
          (cond
           ((memq c maf-editplus--openers) (setq depth (1+ depth)))
           ((memq c maf-editplus--closers) (setq depth (1- depth)))
           ((and (zerop depth) (eq c ?.) (eq (char-after (1+ pos)) ?.))
            (setq found pos)))))
      (setq pos (1+ pos)))
    found))

(defun maf-editplus-toggle-brackets ()
  "Toggle the delimiters of the group at point between ( ) and [ ].
Both ends move together, so a group typed as parens becomes the vector
it was meant to be without the pair ever being mismatched:

  (1,2|)     =>  [1,2]
  |(a+b)     =>  [a+b]
  [1,2]|     =>  (1,2)

The group is the one point stands on or inside, so the gesture works
from where the typing left off rather than only with point parked on a
delimiter. A brace group becomes a paren group, calc reading {1,2} as
the same vector [1,2] denotes.

An interval is the exception, and moves one end only:

  [1 .. 3|)  =>  [1 .. 3]
  [|1 .. 3)  =>  (1 .. 3)

There a delimiter is not punctuation around a group but a value in its
own right — `[' saying the bound is included and `(' that it is not —
so the two ends are independent and a mixed pair is the notation
working, not a group left broken. The end that moves is the end point
is at: before the `..' the lower one, after it the upper. To move both,
press once on each side.

With no complete group in the entry — none at point, or one whose
other half has not been typed yet — nothing is changed. Runs only
during a maf-edit session, and only inside an entry."
  (interactive)
  (unless maf-edit-mode
    (user-error "maf-edit is not active"))
  (let* ((entry (or (maf-editplus--entry-at-point)
                    (user-error "Point is not in a stack entry")))
         (limit (+ (overlay-start entry)
                   (maf-edit--leading-prefix-run (overlay-start entry))))
         (pair (or (maf-editplus--group-at-point limit (overlay-end entry))
                   (user-error "No complete group at point")))
         (open (car pair))
         (close (cdr pair))
         (dots (maf-editplus--interval-dots open close)))
    ;; Replaced in place rather than deleted and reinserted: the entry
    ;; overlay keeps its bounds, and point keeps its position even when
    ;; it is sitting on one of the characters. Closer first, so that a
    ;; group edited whole is edited from the far end inwards.
    (dolist (pos (cond
                  ((null dots) (list close open))
                  ;; Point on the opener is at or before the dots; point
                  ;; past the closer is after them. The one comparison
                  ;; covers standing on an end and working inside one.
                  ((<= (point) dots) (list open))
                  (t (list close))))
      (subst-char-in-region
       pos (1+ pos) (char-after pos)
       (cdr (assq (char-after pos) maf-editplus--bracket-toggle))))))

;;; Duplicating a group

(defun maf-editplus--call-start (open limit)
  "Start of the group at OPEN, taking in the name that heads it.
A function call is one unit — sqrt(3) copied whole rather than left
without its head — but juxtaposition is not: the 2 of 2(a+b) is a
factor multiplying the group, not a name the group belongs to. What
tells them apart is what tells calc: a name begins with a letter or an
underscore, so x2(a+b) is a call and 2(a+b) is a product. Only a
paren group can be called, as the parser reads it too
\(`maf-editplus--parse'): a name before a bracket or a brace is a
factor — x[1, 2] is the product to calc, and x{foo} is x times foo
under the editvars dialect — so those groups begin at OPEN. LIMIT
bounds the scan, as everywhere else here."
  (let ((start (maf-editplus--skip-name-back open limit)))
    (if (and (eq (char-after open) ?\()
             (< start open)
             (string-match-p "[[:alpha:]_]" (string (char-after start))))
        start
      open)))

(defun maf-editplus--flat-copy (start end mark)
  "Text of START..END as one line, and where MARK falls inside it.
Returns a cons of the text and the offset into it that corresponds to
the buffer position MARK — the place point should land when the text
is written down again elsewhere.

Machine-owned characters are dropped and every run of whitespace,
a line break and the pad that follows it included, becomes a single
space: the same reading `maf-edit--entry-text' gives the parser. A
copy is expression text going back into an entry, and the prefixes
belong to the lines they were stamped on, not to the expression."
  (let ((pos start) (chars nil) (n 0) (idx nil))
    (while (< pos end)
      (when (and (null idx) (>= pos mark)) (setq idx n))
      (let ((c (char-after pos)))
        (cond
         ((get-text-property pos 'maf-edit-prefix))
         ((memq c '(?\s ?\t ?\n))
          (unless (eq (car chars) ?\s)
            (push ?\s chars)
            (setq n (1+ n))))
         (t (push c chars) (setq n (1+ n)))))
      (setq pos (1+ pos)))
    (cons (apply #'string (nreverse chars)) (or idx n))))

(defun maf-editplus-duplicate-group ()
  "Duplicate the group at point, the copy landing just after it.
Point moves to the matching place inside the copy, which is what makes
the gesture worth a key: the second pair is nearly always the first
with one character changed, and that character ends up where the
fingers already are.

  (x+|1)     =>  (x+1)(x+|1)      DEL - then gives (x+1)(x-1)
  sqrt(3)|   =>  sqrt(3)sqrt(3)|
  |(a+b)     =>  (a+b)|(a+b)

Nothing is written between the two: calc reads juxtaposition as
multiplication, so (x+1)(x-1) is the product it looks like — and
[1,2][1,2] is the product calc means for two vectors, their dot.

The group is the one point stands on or inside, as it is for
`maf-editplus-toggle-brackets': the opener point sits before, else the
closer just behind point, else the group enclosing point. A call is
copied whole, name and all — the name in front of an argument list
belongs to it — while a number in that place does not, 2(a+b) being a
product of two things and not one call.

A group spanning lines is copied as a single line, its prefixes and
line breaks coming out as the whitespace they are to the parser.

With no complete group in the entry — none at point, or one whose
other half has not been typed yet — nothing is changed. Runs only
during a maf-edit session, and only inside an entry."
  (interactive)
  (unless maf-edit-mode
    (user-error "maf-edit is not active"))
  (let* ((entry (or (maf-editplus--entry-at-point)
                    (user-error "Point is not in a stack entry")))
         (limit (+ (overlay-start entry)
                   (maf-edit--leading-prefix-run (overlay-start entry))))
         (pair (or (maf-editplus--group-at-point limit (overlay-end entry))
                   (user-error "No complete group at point")))
         (start (maf-editplus--call-start (car pair) limit))
         (end (1+ (cdr pair)))
         (copy (maf-editplus--flat-copy start end (point))))
    ;; Point sits at END in the press-after-the-closer case, and the
    ;; excursion's marker does not advance over an insert made there —
    ;; so the copy always goes in ahead of point, and the goto below is
    ;; the one thing that moves it.
    (save-excursion
      (goto-char end)
      (insert (car copy)))
    (goto-char (+ end (cdr copy)))))
;;; The sub-expression at point

;; On the stack, "what is point on" has a structural answer: maf's
;; subexpr target hands the position to calc's own selection machinery
;; and gets back the innermost sub-formula whose rendering covers it
;; (`maf--resolve-target-subexpr'). An edit session cannot ask that
;; question — the text is the user's own, mid-typing and often not
;; parsable at all, and calc has no formula to render — so it is
;; answered here by reading the text: a tolerant precedence parse of
;; the entry into spans, and the innermost span covering point.
;;
;; The two agree on what point means. The character *after* point names
;; the node, as the column does on the stack: point on an operand takes
;; that operand, and point on an operator — or on the space beside it,
;; or on a delimiter — takes the node the operator heads. So a+|b*c
;; takes b, a+b|*c takes b*c, and a|+b*c takes the whole sum.
;;
;; Tolerance is the difference from a real parser. Nothing here can
;; fail: an unclosed group runs to the end of the entry, a stray closer
;; is dropped, an operator with nothing after it keeps the node it
;; opened, and a character the scan has no reading for becomes an atom
;; of its own. The text is being typed, and a parse that gave up would
;; leave the gesture with nothing to act on.

(defconst maf-editplus--op-strings
  '("+/-" ".." "<=" ">=" "!=" "==" ":=" "::" "=>" "**" "&&" "||" "!!"
    "+" "-" "*" "/" "\\" "%" "^" "=" "<" ">" "|" "!")
  "Operator spellings the scan reads, longest match first.
Two-character operators come before the one-character operators they
begin with, so `<=' is one boundary rather than `<' and a stray `=',
and `**' is the power calc reads it as rather than two products —
and `+/-' one error form rather than a sum over a quotient.

Calc's own table (`math-expr-ops') is longer than this. What is left
out is what a node under point would gain nothing from: the
conditional `?:', whose ternary shape the parse has no operand for,
and the ported-logic operators beside it. An operator the scan does
not know becomes an atom of its own, so a press beside one names that
character rather than the expression around it — wrong, but confined
to the node point stands on.

The word operator `mod' is not spelled here: it is an identifier to
the scan, and `maf-editplus--tokens' turns that one identifier into an
operator.")

(defconst maf-editplus--assign-ops '(":=" "=>" "::")
  "The three operators binding looser than everything else.
Each is its own level, and they are listed here for the reader rather
than parsed together: `=>' is loosest, then the rewrite condition
`::', then assignment — so x = y => z is the evaluation of the
equation, not an equation about an evaluation.")

(defconst maf-editplus--relation-ops '("=" "==" "!=" "<" ">" "<=" ">=")
  "The relations, all of one precedence, as calc reads them.
`==' is calc's second spelling of `='.")

(defun maf-editplus--atom-start-p (pos)
  "Non-nil when an atom begins at POS.
A name character starts one, and so does the point of a number
written without its leading zero — .5 is one atom, while the two dots
of an interval are not. A name the editvars dialect quotes, {cm}, is
not an atom but a brace group, and the group scans read it as one
unit the way they read any delimited group."
  (or (maf-editplus--name-char-p (char-after pos))
      (and (eq (char-after pos) ?.)
           (maf-editplus--digit-p (char-after (1+ pos))))))

(defun maf-editplus--atom-run (pos bound)
  "End of the atom beginning at POS, no further than BOUND.
`maf-editplus--atom-char-p's run, which keeps a number's own
punctuation (2.5, calc's fraction 3:4) and stops at everything else."
  (let ((p pos))
    (while (and (< p bound) (maf-editplus--atom-char-p p))
      (setq p (1+ p)))
    (max p (1+ pos))))

(defun maf-editplus--calc-syntax-p ()
  "Non-nil when the entry text is calc's own input syntax.
An input dialect sets `maf-edit-parse-text-function' to its
translator, and what the text means is then that module's to say. It
matters to one token: calc's word operator `mod' is an operator only
where a run of letters is one identifier. Under the editvars dialect
a bare run of letters is a run of factors — `mod' commits as the
product m o d, calc's operator being unreachable without the quoting
braces — so the scan must not read it as one, or it would name a node
the commit does not agree exists."
  (eq maf-edit-parse-text-function #'identity))

(defun maf-editplus--split-run-p (start end)
  "Non-nil when the atom at START..END is a run the input dialect splits.
Calc reads a run of letters as one identifier, and under calc's own
syntax that is what the text commits as — xy^2 already means the one
variable xy squared. An input dialect reads the same run as a run of
factors (`maf-editplus--calc-syntax-p'), so an operator written after
it takes only the last factor: there xy is the product x y, and
squaring the run whole needs the parentheses. A quoted run, {xy}, is
a brace group — one unit under either reading, as any delimited group
is; an exempt run \(`maf-editvars-exempt-names'), pi bare, is one
name under either; a string literal is one string, and a bare number
is one number."
  (and (not (maf-editplus--calc-syntax-p))
       (> (- end start) 1)
       (not (memq (char-after start) maf-editplus--openers))
       (not (eq (char-after start) ?\"))
       (let ((run (buffer-substring-no-properties start end)))
         (and (string-match-p "[[:alpha:]]" run)
              (not (and (fboundp 'maf-editvars-exempt-p)
                        (maf-editvars-exempt-p run)))))))

(defun maf-editplus--call-name-p (pos)
  "Non-nil when the atom at POS can head a function call.
A name can — sqrt(3) is a call — and a number cannot: 2(x+1) is the
product it reads as, not a call to 2."
  (let ((c (char-after pos)))
    (and c (string-match-p "[[:alpha:]_]" (char-to-string c)))))

(defun maf-editplus--operand-start-p (pos bound)
  "Non-nil when the token beginning at POS reads as an operand.
The tokenizer's classification (`maf-editplus--tokens'), asked of one
position, and told by exclusion as the tokenizer tells it: a closer,
a comma, an operator spelling, and the atom the tokenizer files as
calc's word operator — the run mod under calc's own syntax — begin
no operand. Every other token does, the lone character the tokenizer
keeps as an atom of its own included, so the two never drift apart.
modulus is still the name it looks like, the atom run having taken
the whole of it; BOUND stops the runs at the end of the entry."
  (let ((c (char-after pos)))
    (and c
         (not (memq c maf-editplus--closers))
         (not (memq c '(?, ?\;)))
         (if (maf-editplus--atom-start-p pos)
             (not (and (maf-editplus--calc-syntax-p)
                       (string= (buffer-substring-no-properties
                                 pos (maf-editplus--atom-run pos bound))
                                "mod")))
           (not (maf-editplus--operator-run pos bound))))))

(defun maf-editplus--string-run (pos bound)
  "End of the string literal opening at POS, no further than BOUND.
A string's contents are not syntax, so the whole literal is one atom.
An unterminated quote runs to BOUND — the safe way to be wrong here,
as in `maf-edit--top-level-comma-p': the rest of the entry is text
rather than structure the scan would misread."
  (let ((p (1+ pos)))
    (while (and (< p bound) (not (eq (char-after p) ?\")))
      (setq p (if (eq (char-after p) ?\\) (+ p 2) (1+ p))))
    (min bound (1+ p))))

(defun maf-editplus--operator-run (pos bound)
  "The `maf-editplus--op-strings' entry spelled at POS, or nil.
BOUND stops the match at the end of the entry, so a two-character
operator half-typed at the end reads as the one character it is."
  (seq-find (lambda (op)
              (and (<= (+ pos (length op)) bound)
                   (string= op (buffer-substring-no-properties
                                pos (+ pos (length op))))))
            maf-editplus--op-strings))

(defun maf-editplus--tokens (limit bound)
  "Tokens of the entry text between LIMIT and BOUND.
Each is (KIND START END TEXT), KIND one of `atom', `open', `close',
`comma' or `op'; TEXT is the operator's spelling or the delimiter's
character, and nil for an atom.

Whitespace and machine-owned characters drop out
\(`maf-editplus--skip-fill-forward'), so a line break inside a
multi-line entry is nothing to the parse and the entry tokenizes as
the one expression it is."
  (let ((pos limit)
        (toks nil))
    (while (< (setq pos (maf-editplus--skip-fill-forward pos bound)) bound)
      (let* ((c (char-after pos))
             (op (and (not (maf-editplus--atom-start-p pos))
                      (maf-editplus--operator-run pos bound)))
             (tok
              (cond
               ((memq c maf-editplus--openers) (list 'open pos (1+ pos) c))
               ((memq c maf-editplus--closers) (list 'close pos (1+ pos) c))
               ((memq c '(?, ?\;)) (list 'comma pos (1+ pos) c))
               ((eq c ?\")
                (list 'atom pos (maf-editplus--string-run pos bound) nil))
               ((maf-editplus--atom-start-p pos)
                (let ((end (maf-editplus--atom-run pos bound)))
                  ;; `mod' is calc's one word operator: an identifier
                  ;; to read, an operator to parse. A name that merely
                  ;; begins with it — modulus — is the name it looks
                  ;; like, the atom run having taken the whole of it.
                  (if (and (maf-editplus--calc-syntax-p)
                           (string= (buffer-substring-no-properties pos end)
                                    "mod"))
                      (list 'op pos end "mod")
                    (list 'atom pos end nil))))
               (op (list 'op pos (+ pos (length op)) op))
               ;; No reading for this character: an atom of its own, so
               ;; the parse carries on past it rather than stopping.
               (t (list 'atom pos (1+ pos) nil)))))
        (push tok toks)
        (setq pos (nth 2 tok))))
    (nreverse toks)))

(defun maf-editplus--make-node (kind start end inner children)
  "A parse node of KIND spanning START..END, holding CHILDREN.
START..END is the span point is tested against. INNER, a cons of
positions or nil for START..END itself, is what a command acts on:
the two differ only for a group in bare parentheses, where the parens
are punctuation the writer supplied and a function call brings its
own — so ln(a+b) is written where the span would have said
ln((a+b)).

KIND is what the text spells the node with: `atom', `call', `group'
for a vector or an argument list, `juxta' for a product written as
nothing but a space, and otherwise the operator's own spelling. A
command reads it to know whether the node can take an operator after
it as it stands — see `maf-editplus--node-atomic-p'."
  (list start end (or inner (cons start end)) children kind))

(defun maf-editplus--node-start (node)
  "Where NODE's span begins."
  (nth 0 node))

(defun maf-editplus--node-end (node)
  "Where NODE's span ends."
  (nth 1 node))

(defun maf-editplus--node-inner (node)
  "The bounds a command should act on for NODE, as a cons."
  (nth 2 node))

(defun maf-editplus--node-children (node)
  "NODE's direct operands, in order."
  (nth 3 node))

(defun maf-editplus--node-kind (node)
  "What the text spells NODE with (see `maf-editplus--make-node')."
  (nth 4 node))

(defun maf-editplus--node-parenthesized-p (node)
  "Non-nil when NODE's span already carries a bare pair of parentheses.
Such a node is its own group: an operator written after it applies to
the whole of it, and a call written around it would only double the
pair."
  (let ((start (maf-editplus--node-start node))
        (end (maf-editplus--node-end node)))
    (and (not (equal (maf-editplus--node-inner node) (cons start end)))
         (eq (char-after start) ?\()
         (eq (char-before end) ?\)))))

(defun maf-editplus--node-vacant-p (node)
  "Non-nil when NODE is a bracketed pair with nothing inside it.
The pair a writer has only just opened — electric parens leave point
between them, and the parse has a group there holding no expression
at all. Such a pair is a place for a sub-expression rather than one
itself, so there is nothing in it a command could act on."
  (and (eq (maf-editplus--node-kind node) 'group)
       (null (maf-editplus--node-children node))
       (let* ((start (maf-editplus--node-start node))
              (end (maf-editplus--node-end node))
              (inner-end (if (memq (char-before end) maf-editplus--closers)
                             (1- end)
                           end)))
         (and (> inner-end start)
              (string-blank-p
               (buffer-substring-no-properties (1+ start) inner-end))))))

(defun maf-editplus--node-atomic-p (node)
  "Non-nil when NODE can take an operator after it as it stands.
A number or name, a function call and a bracketed group each read as
one unit already, so a^2 and sqrt(3)^2 mean what they say. Everything
the text spells with an operator of its own does not: a+b squared is
\(a+b)^2, and the parentheses are the difference.

Under an input dialect a bare run of letters is one atom to the scan
but a run of factors to the commit (`maf-editplus--split-run-p'), so
it cannot take the operator as it stands either — xy^2 would commit
as x times y squared."
  (and (memq (maf-editplus--node-kind node) '(atom call group))
       (not (and (eq (maf-editplus--node-kind node) 'atom)
                 (maf-editplus--split-run-p
                  (maf-editplus--node-start node)
                  (maf-editplus--node-end node))))))

(defun maf-editplus--parse (limit bound)
  "Parse the entry text between LIMIT and BOUND into a tree of spans.
Returns the root node, or nil when the text holds nothing at all.

The grammar is calc's, to the depth this gesture needs. Loosest
first: `=>', the rewrite condition `::', assignment `:=', `||',
`&&', the relations, vector concatenation `|', the interval `..',
`+' and `-', then the multiplications — `/', `%' and `\\' with `*'
and juxtaposition binding tighter inside them, or all five on one
level where `calc-multiplication-has-precedence' is off — then a
leading sign, then `^' and `**', then the postfix factorials, then
the error form `+/-', and tightest of all `mod'. Which is why
2^3 mod 5 raises 2 to (3 mod 5), and a +/- b^2 raises the error form.

Most of it folds left. `^', `:=', `+/-', `mod' and — where it has a
precedence of its own — `*' fold right, as calc reads them: a mod b
mod c is a mod (b mod c), so its first operator names the whole run.

A name in front of a parenthesized list is the call it heads, so
sqrt(3) is one node with the 3 inside it.

Several expressions in a row with nothing joining them — the shape
half-deleted text leaves behind — become the children of a root
spanning the whole entry, so point still names something."
  (let ((toks (maf-editplus--tokens limit bound)))
    (cl-labels
        ((kind () (car-safe (car toks)))
         (text () (nth 3 (car toks)))
         (eat () (pop toks))
         (opp (ops) (and (eq (kind) 'op) (member (text) ops)))
         ;; KIND first, as in `maf-editplus--make-node'; INNER is only
         ;; ever the span itself here, a bare pair being the one node
         ;; built by hand below.
         (node (kind start end children)
           (maf-editplus--make-node kind start end nil children))
         ;; A binary run: LEFT joined to each right operand in turn.
         ;; An operator with nothing after it keeps the node it opened,
         ;; ending the run — a+ mid-typing is still the sum a+.
         ;; RIGHT folds the run to the right instead of the left, for
         ;; the operators calc reads that way: a mod b mod c is
         ;; a mod (b mod c), so the first `mod' names the whole of it.
         (chain (ops sub &optional right)
           (let ((left (funcall sub))
                 (stop nil))
             (while (and left (not stop))
               (cond
                ((opp ops)
                 (let* ((op (eat))
                        (rest (if right (chain ops sub right) (funcall sub))))
                   (setq left (node (nth 3 op)
                                    (maf-editplus--node-start left)
                                    (if rest
                                        (maf-editplus--node-end rest)
                                      (nth 2 op))
                                    (if rest (list left rest) (list left))))
                   (when (or right (not rest)) (setq stop t))))
                (t (setq stop t))))
             left))
         ;; Loosest to tightest, as calc binds them: `=>', the rewrite
         ;; condition, assignment — which folds right — then the
         ;; logical pair, the relations, vector concatenation, then the
         ;; interval, which is calc's only in name, `..' meaning
         ;; nothing outside the delimiters that carry it.
         (expr () (chain '("=>") #'condition))
         (condition () (chain '("::") #'assignment))
         (assignment () (chain '(":=") #'disjunction t))
         (disjunction () (chain '("||") #'conjunction))
         (conjunction () (chain '("&&") #'relation))
         (relation () (chain maf-editplus--relation-ops #'concatenation))
         (concatenation () (chain '("|") #'interval))
         (interval () (chain '("..") #'sum))
         (sum () (chain '("+" "-") #'product))
         ;; `calc-multiplication-has-precedence', which is on by
         ;; default, gives `*' a precedence of its own: it binds
         ;; tighter than `/' and folds right, so a/b*c is a/(b*c) and
         ;; a*b*c is a*(b*c). Off, the four share one left-folding
         ;; level. The setting is read here rather than remembered,
         ;; the user being free to turn it over between presses.
         (product ()
           (if calc-multiplication-has-precedence
               (chain '("/" "%" "\\") #'multiplication)
             (factors '("*" "/" "%" "\\") nil)))
         (multiplication () (factors '("*") t))
         ;; The multiplications, explicit and juxtaposed alike:
         ;; calc reads 2 x as the product OPS spell out, so the space
         ;; between two factors is an operator like any other.
         (factors (ops right)
           (let ((left (unary))
                 (stop nil))
             (while (and left (not stop))
               (cond
                ((opp ops)
                 (let* ((op (eat))
                        (rest (if right (factors ops right) (unary))))
                   (setq left (node (nth 3 op)
                                    (maf-editplus--node-start left)
                                    (if rest
                                        (maf-editplus--node-end rest)
                                      (nth 2 op))
                                    (if rest (list left rest) (list left))))
                   (when (or right (not rest)) (setq stop t))))
                ((memq (kind) '(atom open))
                 (let ((rest (if right (factors ops right) (unary))))
                   (if rest
                       (setq left (node 'juxta
                                        (maf-editplus--node-start left)
                                        (maf-editplus--node-end rest)
                                        (list left rest)))
                     (setq stop t))
                   (when right (setq stop t))))
                (t (setq stop t))))
             left))
         (unary ()
           (if (opp '("-" "+" "!"))
               (let* ((op (eat))
                      (operand (unary)))
                 (node (nth 3 op)
                       (nth 1 op)
                       (if operand (maf-editplus--node-end operand) (nth 2 op))
                       (and operand (list operand))))
             (power)))
         ;; Right-associative, and the exponent takes a sign of its
         ;; own: 2^-3 is one node, and -a^2 signs the power.
         (power ()
           (let ((base (error-form)))
             (if (and base (opp '("^" "**")))
                 (let* ((op (eat))
                        (exp (unary)))
                   (node "^"
                         (maf-editplus--node-start base)
                         (if exp (maf-editplus--node-end exp) (nth 2 op))
                         (if exp (list base exp) (list base))))
               base)))
         ;; Both tighter than the power that contains them, which is
         ;; how calc reads them: 2^3 mod 5 is 2 raised to (3 mod 5),
         ;; and a +/- b^2 raises the error form. `mod' is tighter than
         ;; `+/-' in turn, and both fold right.
         (error-form () (chain '("+/-") #'modulo t))
         (modulo () (chain '("mod") #'postfix t))
         (postfix ()
           (let ((n (primary)))
             (while (and n (opp '("!" "!!")))
               (let ((op (eat)))
                 (setq n (node (nth 3 op) (maf-editplus--node-start n)
                               (nth 2 op) (list n)))))
             n))
         (primary ()
           (pcase (kind)
             ('atom
              (let* ((tok (eat))
                     (start (nth 1 tok)))
                (if (and (maf-editplus--call-name-p start)
                         (eq (kind) 'open)
                         (eq (text) ?\())
                    ;; The call the name heads: one node, its arguments
                    ;; inside it.
                    (pcase (group)
                      (`(,_open ,end ,elems ,_commas ,_delim)
                       (node 'call start end elems)))
                  (node 'atom start (nth 2 tok) nil))))
             ('open
              (pcase (group)
                (`(,open ,end ,elems ,commas ,delim)
                 (cond
                  ;; An interval's delimiters are values, not
                  ;; punctuation: `[' says the bound is included and
                  ;; `(' that it is not, and `..' means nothing without
                  ;; them — calc does not read it as an operator at all
                  ;; (`math-expr-ops' has no entry for it). So the group
                  ;; is the node, whichever pair it was written with,
                  ;; and the endpoints are its operands: the dots name
                  ;; the interval rather than a sub-expression that
                  ;; could be lifted out of it.
                  ((and (null commas)
                        (= (length elems) 1)
                        (equal (maf-editplus--node-kind (car elems)) ".."))
                   (node 'group open end
                         (maf-editplus--node-children (car elems))))
                  ;; Bare parentheses group what is already one node:
                  ;; the span grows to cover them so point on either
                  ;; one names the node, while what a command acts on
                  ;; stays the expression inside. The kind is the inner
                  ;; node's own — what the parentheses hold is what the
                  ;; node is, and they are furniture around it.
                  ((and (eq delim ?\() (null commas) (= (length elems) 1))
                   (let ((inner (car elems)))
                     (maf-editplus--make-node
                      (maf-editplus--node-kind inner)
                      open end
                      (maf-editplus--node-inner inner)
                      (maf-editplus--node-children inner))))
                  (t (node 'group open end elems))))))
             (_ nil)))
         ;; The raw shape of a delimited group: (OPEN END ELEMENTS
         ;; COMMAS DELIM). Its readings differ — an argument list, a
         ;; vector, a bare grouping pair — so the caller builds the node.
         (group ()
           (let* ((open (eat))
                  (delim (nth 3 open))
                  (elems nil)
                  (commas nil)
                  (end nil))
             (while (and toks (not end))
               (pcase (kind)
                 ('close (setq end (nth 2 (eat))))
                 ('comma (eat) (setq commas t))
                 (_ (let ((e (expr)))
                      (if e (push e elems) (eat))))))
             ;; An unclosed group runs to the end of the entry — the
             ;; state every group is in while it is being typed.
             (list (nth 1 open) (or end bound) (nreverse elems) commas delim))))
      (let ((nodes nil))
        (while toks
          (let ((n (expr)))
            (if n (push n nodes) (eat))))
        (cond
         ((null nodes) nil)
         ((null (cdr nodes)) (car nodes))
         ;; No kind: several expressions side by side is not a shape
         ;; the text spells, so nothing may assume it reads as one.
         (t (maf-editplus--make-node nil limit bound nil (nreverse nodes))))))))

(defun maf-editplus--node-at (node pos)
  "The innermost node of NODE's tree whose span covers POS, or nil.
Covering is inclusive of the start and exclusive of the end, so POS
names the character after point — the same character the column names
on the stack."
  (when (and node
             (<= (maf-editplus--node-start node) pos)
             (< pos (maf-editplus--node-end node)))
    (or (seq-some (lambda (kid) (maf-editplus--node-at kid pos))
                  (maf-editplus--node-children node))
        node)))

(defun maf-editplus--subexpr-node ()
  "The parse node point names, or nil.
The edit-session counterpart of maf's subexpr target: the innermost
node of the entry's parse whose span covers point (see
`maf-editplus--parse').

Nil when there is nothing under point — the end of the entry, where a
command's own scan for the term behind point takes over — and nil
outside an entry, where there is no text to parse.

Nil also on a closer: electric parens leave point in front of the
closer for the whole time the argument is being typed, so a press
there means the term just typed — ln(x y|) raising y, (1 + r|)
raising r — and the same term-behind scan takes over, as at the end
of the entry. With nothing complete behind point — an operator, a
separator, the opener — the press is in an empty slot, and names
nothing at all: the command's own answer for no target is an empty
call opened at point, (a + ln(|)), which is what a writer who has
just typed the operator is reaching for. Wrapping the enclosure
from inside its own closer is never what the press means; the
enclosure is reachable from its opener.

Nil likewise on padding whitespace with a complete unit ending at
point: the space beside a spelled operator, or a wrapped line's
break, is furniture, and a press there means the term just typed —
2 x| + 1 names the x — with the same term-behind scan taking over.
The one space that is not padding is a juxtaposed product's own
operator glyph, told apart by what follows it: 2 |x runs on into an
operand and names the product, the way any operator names its node
\(`maf-editplus--operand-start-p' — which knows calc's word operator,
so x |mod y is the mod's padding and names the x)."
  (let ((entry (maf-editplus--entry-at-point)))
    (when entry
      (let* ((limit (+ (overlay-start entry)
                       (maf-edit--leading-prefix-run (overlay-start entry))))
             (bound (overlay-end entry))
             (pos (max (point) limit)))
        (when (< (maf-editplus--skip-fill-forward pos bound) bound)
          (let* ((tree (maf-editplus--parse limit bound))
                 (at pos)
                 (node (or (maf-editplus--node-at tree at)
                           ;; Point in front of the entry's first token
                           ;; — leading whitespace — still names the
                           ;; text it is in front of.
                           (progn
                             (setq at (maf-editplus--skip-fill-forward
                                       pos bound))
                             (maf-editplus--node-at tree at)))))
            (cond
             ;; An empty pair holds no expression, so a press inside
             ;; one names nothing at all — the pair is where a
             ;; sub-expression is going to be, not one that is there.
             ;; The command's own answer for no target takes over, and
             ;; what it writes goes inside the pair the writer opened:
             ;; e^(ln(|)), not a call wrapped around the empty pair.
             ((and node
                   (maf-editplus--node-vacant-p node)
                   (> at (maf-editplus--node-start node)))
              nil)
             ((and node
                   (= at (1- (maf-editplus--node-end node)))
                   (memq (char-after at) maf-editplus--closers))
              nil)
             ;; A separator is punctuation the same way a closer is:
             ;; the argument list it divides is not a sub-expression a
             ;; command could act on, so a press on one means the
             ;; argument just typed — log(x|, 5) naming the x, exactly
             ;; as the closer after the last argument does — or, with
             ;; nothing complete behind point, an empty slot: f(|, b)
             ;; names nothing, and the empty call opens in the slot.
             ;; Without this the innermost node covering the comma is
             ;; the call itself, and the key would wrap the whole call
             ;; from inside its own argument list.
             ((and node
                   (memq (char-after at) '(?, ?\;)))
              nil)
             ;; Padding whitespace with a complete unit ending at
             ;; point reads as the end of the entry does: the press
             ;; means the term just typed — 2 x| + 1 names the x, not
             ;; the sum whose padding point stands on. The one space
             ;; that is not padding is a juxtaposed product's own
             ;; operator glyph, told apart by what follows: 2 |x runs
             ;; on into an operand, an operator's padding into the
             ;; operator itself.
             ((and node
                   (memq (char-after at) '(?\s ?\t ?\n))
                   (not (maf-editplus--operand-start-p
                         (maf-editplus--skip-fill-forward at bound)
                         bound))
                   (maf-editplus--unit-before at limit))
              nil)
             (t node))))))))

(defun maf-editplus--wrap-node (node name &optional tail)
  "Write a call to NAME around NODE; return where the call begins.
With TAIL, TAIL goes in before the closer, as in `maf-editplus--wrap'.
The argument is NODE's inner text, so a pair of bare parentheses the
writer put around it is not wrapped a second time — and when the call
makes that pair redundant it goes, ln(a+b) being written where
ln((a+b)) would have been. That is what the stack does with the same
gesture: the sub-formula is re-rendered, and its parentheses are only
ever the ones its place demands.

The pair goes only when both halves are there. One still being typed
is left alone — deleting the opener of a group with no closer would
restructure text the writer is in the middle of."
  (let* ((inner (maf-editplus--node-inner node))
         (start (maf-editplus--node-start node))
         (end (maf-editplus--node-end node))
         (bare (maf-editplus--node-parenthesized-p node))
         ;; Markers, so the argument's bounds survive the pair's removal.
         (m1 (copy-marker (car inner)))
         (m2 (copy-marker (cdr inner) t)))
    (when bare
      (delete-region (1- end) end)
      (delete-region start (1+ start)))
    (prog1 (marker-position m1)
      (maf-editplus--wrap (marker-position m1) (marker-position m2) name tail)
      (set-marker m1 nil)
      (set-marker m2 nil))))

;;; The common target

(defun maf-editplus--number-end (pos bound)
  "Position just past the number beginning at POS, no further than BOUND.
POS must start a number: a digit, or the point of one written without
its leading zero. Covers what calc's number syntax reaches past a
bare digit run, as `maf-editvars--number-end' does over strings: the
inner punctuation with a digit after it (2.5, calc's fraction 3:4), a
radix form, whose digits run past nine (16#ff), and a float's
exponent with its sign (1e5, 1.5e-3). A letter past all of that is
where the number ends and a name begins — 24x ends at the x."
  (let ((p pos))
    (while (and (< p bound)
                (or (maf-editplus--digit-p (char-after p))
                    (and (memq (char-after p) maf-editplus--atom-inner)
                         (maf-editplus--digit-p (char-after (1+ p))))))
      (setq p (1+ p)))
    (if (and (< p bound) (eq (char-after p) ?#))
        (progn
          (setq p (1+ p))
          (while (and (< p bound)
                      (or (maf-editplus--name-char-p (char-after p))
                          (eq (char-after p) ?.)))
            (setq p (1+ p))))
      (when (and (< p bound) (memq (char-after p) '(?e ?E)))
        (let ((q (1+ p)))
          (when (and (< q bound) (memq (char-after q) '(?+ ?-)))
            (setq q (1+ q)))
          (when (and (< q bound) (maf-editplus--digit-p (char-after q)))
            (setq p (1+ q))
            (while (and (< p bound)
                        (maf-editplus--digit-p (char-after p)))
              (setq p (1+ p)))))))
    p))

(defun maf-editplus--unit-before (pos limit)
  "Bounds of the smallest complete unit ending exactly at POS, or nil.
An atom with its own punctuation — a name, a number, a string literal
— or a delimited group taken with the call name that heads it; a
quoted name, {cm}, is such a group. Nil when the character behind POS
completes nothing: whitespace, an operator, the head of the entry. No
whitespace is crossed on the way in: this is the unit a power typed
at POS would bind to, and a power does not reach back across a space.

A run that begins with a number and runs on into letters is that
number times a name — calc reads 24x as 24 x — so the unit ending at
POS is the name alone, exactly what the power typed there would bind
to. The number's own letters stay its own: 24e3x is 24e3 times x
\(`maf-editplus--number-end')."
  (when (> pos limit)
    (let ((c (char-before pos)))
      (cond
       ((memq c maf-editplus--closers)
        (let ((open (maf-editplus--group-start pos limit)))
          (when open
            (cons (maf-editplus--call-start open limit) pos))))
       ;; A string's contents are not syntax, so its closing quote
       ;; completes the whole literal. Quotes pair forward — scanned
       ;; backward, a closer cannot be told from the opener of a
       ;; string still being typed, and in \"a\"+\" the scan would
       ;; pair across the two — so the strings are walked from the
       ;; head of the entry, escapes skipped as in
       ;; `maf-editplus--string-run', and the unit is a literal whose
       ;; own closer sits just before POS. An unfinished quote
       ;; completes nothing.
       ((eq c ?\")
        (let ((p limit)
              (found nil))
          (while (and (not found) (< p pos))
            (if (not (eq (char-after p) ?\"))
                (setq p (1+ p))
              (let ((q (1+ p)))
                (while (and (< q pos) (not (eq (char-after q) ?\")))
                  (setq q (if (eq (char-after q) ?\\) (+ q 2) (1+ q))))
                (if (and (= q (1- pos)) (eq (char-after q) ?\"))
                    (setq found (cons p pos))
                  (setq p (1+ q))))))
          found))
       ((maf-editplus--atom-char-p (1- pos))
        (let ((beg (1- pos)))
          (while (and (> beg limit)
                      (maf-editplus--atom-char-p (1- beg)))
            (setq beg (1- beg)))
          ;; A run led by a number is the number times the name after
          ;; it, and the name is the smaller unit ending at POS.
          (when (or (maf-editplus--digit-p (char-after beg))
                    (and (eq (char-after beg) ?.)
                         (maf-editplus--digit-p (char-after (1+ beg)))))
            (let ((split (maf-editplus--number-end beg pos)))
              (when (< split pos)
                (setq beg split))))
          (cons beg pos)))))))

(defun maf-editplus--unit-last-factor (beg end)
  "Start of the last factor of the unit at BEG..END, or BEG.
Under an input dialect a bare run of letters is a run of factors — ab
is a times b — and the smallest expression ending at END is the last
letter alone. Everything else is one unit already and BEG stands: a
run with a digit in it (x3) is one identifier the dialect spells as
calc does, an exempt run (pi) is one name under either reading, and
under calc's own syntax the whole run is the one variable it names.

This is the reading the whole subexpression family shares: a typed
^2 after the run binds to its last factor, the power key writes
exactly that, and the wrap keys take the same smallest expression —
as each does behind a number's coefficient. The run whole stays
reachable by marking it."
  (if (and (> (- end beg) 1)
           (not (maf-editplus--calc-syntax-p))
           (let ((run (buffer-substring-no-properties beg end)))
             (and (string-match-p "\\`[[:alpha:]]+\\'" run)
                  (not (and (fboundp 'maf-editvars-exempt-p)
                            (maf-editvars-exempt-p run))))))
      (1- end)
    beg))

(defun maf-editplus--resolve-target ()
  "Resolve what a subexpression key acts on at point; the commands' root.
Every subexpression command — the wrap keys and the power key — asks
this one question and differs only in what it does with the answer.
The region comes first, an explicit answer outranking any reading of
point; then the node the character under point belongs to
\(`maf-editplus--subexpr-node'); then the smallest complete unit
ending at point (`maf-editplus--unit-before'). Returns
\(region BEG END), (node . NODE), (unit BEG END), or nil — nothing at
all, which each command answers in its own shape: an empty call, a
bare power.

Point outside any entry opens a fresh one at the dot first, the same
place typed text would start one, so every subexpression key behaves
like typing there. The mark is deactivated when the region was the
answer — the marks are spent by being read, and the next press should
read point anew."
  (unless maf-edit-mode
    (user-error "maf-edit is not active"))
  (let* ((entry (or (maf-editplus--entry-at-point)
                    (maf-edit--open-at-dot)))
         (limit (+ (overlay-start entry)
                   (maf-edit--leading-prefix-run (overlay-start entry)))))
    (cond
     ((use-region-p)
      (let ((beg (max (region-beginning) limit))
            (end (region-end)))
        (when (> end (overlay-end entry))
          (user-error "Region reaches past the entry"))
        (when (>= beg end)
          (user-error "Nothing marked to act on"))
        (deactivate-mark)
        (list 'region beg end)))
     ((when-let ((node (maf-editplus--subexpr-node)))
        (cons 'node node)))
     ((when-let ((unit (maf-editplus--unit-before (point) limit)))
        (list 'unit (car unit) (cdr unit)))))))

;;; Applying a function

(defun maf-editplus--apply-function (name)
  "Wrap what point names in a call to NAME.
The subject is `maf-editplus--resolve-target's answer: the region as
marked, the node the character under point belongs to, or the
smallest complete unit ending at point — the unit the power key
raises there, so the whole subexpression family reads point one way.

Point lands on the call when a node was the subject — the call is the
node under point now, and a second press nests rather than reaching
past it — and after the closer otherwise, where typing carries on.

A unit that is itself a bare pair loses it: the call supplies the
grouping the pair was there for, ln(a+b) being written where
ln((a+b)) would have been. An interval keeps its delimiters — they
are notation, not grouping.

With no subject at all — the head of an entry, just after an
operator, inside a pair of brackets with nothing in it yet, the fresh
entry the resolver opened when point was outside any — an empty call
opens at point, point inside it: NAME() is a call waiting for its
argument."
  (maf-editplus--apply-call (maf-editplus--resolve-target) name nil))

(defun maf-editplus--apply-call (target name tail)
  "Wrap TARGET in a call to NAME; the shared half of the wrap keys.
TARGET is `maf-editplus--resolve-target's answer, resolved by the
caller — the base of a log call is read off the entry before anything
is written, so the resolution cannot be this function's own. TAIL,
when given, goes in between the argument and the closer
\(`maf-editplus--wrap'): the call's further arguments, already spelled
out. With no target at all the empty call is NAME(TAIL) with point on
the argument slot, in front of the comma the tail brings with it."
  (pcase target
    (`(region ,beg ,end)
     (maf-editplus--wrap beg end name tail))
    (`(node . ,node)
     ;; Point lands on the call rather than after it: the node it
     ;; named is now the call written around that node, and point
     ;; stays on the node it named, as it does when a command commits
     ;; on the stack.
     (goto-char (maf-editplus--wrap-node node name tail)))
    (`(unit ,beg ,end)
     ;; A run the dialect splits gives up all but its last factor —
     ;; the smallest expression ending at point (see
     ;; `maf-editplus--unit-last-factor').
     (setq beg (maf-editplus--unit-last-factor beg end))
     ;; An interval keeps its parens — they are notation, not
     ;; grouping, and ln(1 .. 2) would not parse back.
     (if (and (eq (char-after beg) ?\()
              (eq (char-before end) ?\))
              (not (maf-editplus--interval-dots beg (1- end))))
         (progn
           (delete-region (1- end) end)
           (delete-region beg (1+ beg))
           (maf-editplus--wrap beg (- end 2) name tail))
       (maf-editplus--wrap beg end name tail)))
    (_
     (insert name "(" (or tail "") ")")
     (backward-char (1+ (length (or tail "")))))))

(defun maf-editplus-wrap-ln ()
  "Apply ln to the sub-expression at point.
Point inside the text names the argument as it names maf's subexpr
target on the stack — the innermost sub-expression the character
under point belongs to — and point stays on the call written around
it:

  a+|b*c       =>  a+ln(b)*c      (point on an operand: that operand)
  a+b|*c       =>  a+ln(b*c)      (point on an operator: its node)
  a|+b*c       =>  ln(a+b*c)      (the sum the + heads)
  |(a+b)*c     =>  ln(a+b)*c      (a bare pair is punctuation)
  2 x| + 1     =>  2 ln(x) + 1    (padding space: the unit behind it)
  2 |x + 1     =>  ln(2 x) + 1    (the space that is the product)

At the end of the entry there is no character under point, and the
smallest complete unit ending at point is the argument instead — the
unit `:' raises there — with point left after the closing paren so
typing carries on:

  x+2|         =>  x+ln(2)
  a+b*c|       =>  a+b*ln(c)
  24x|         =>  24ln(x)        (24x is 24 times x: the x alone)
  ab|          =>  a ln(b)        (dialect: ab is a times b — the b
                                   alone, spaced so the name stays its
                                   own word)
  27/sqrt(3)|  =>  27/ln(sqrt(3))
  ln(x)|       =>  ln(ln(x))
  x = |        =>  x = ln(|)

An active region becomes the argument exactly as marked. With nothing
behind point an empty ln() is opened instead, point inside it. A pair
the writer has only just opened is that same case — it holds nothing
to name, so the call goes inside the pair rather than around it — and
outside any entry, on the dot line or an empty stack, a fresh entry
opens at the bottom to hold it, as typing would have started one:

  e^(|)        =>  e^(ln(|))
  .|           =>  1+  ln(|)
                       .

Bound to `L' in `maf-edit-mode-map', so a capital L is no longer
self-inserting during a session — see `maf-use-editplus-mode' on what
that costs."
  (interactive)
  (maf-editplus--apply-function "ln"))

(defun maf-editplus-wrap-sqrt ()
  "Apply sqrt to the sub-expression at point.
`maf-editplus-wrap-ln' with a different name written in front of the
pair — point names the argument the same way, and the same rules
apply to the end of the entry, to a region, and to a press with
nothing behind point:

  a+b|*c     =>  a+sqrt(b*c)
  x+2|       =>  x+sqrt(2)
  x = |      =>  x = sqrt(|)

Bound to `Q' in `maf-edit-mode-map', the letter calc gives the root on
the stack, so a capital Q is no longer self-inserting during a session."
  (interactive)
  (maf-editplus--apply-function "sqrt"))

(defun maf-editplus-wrap-abs ()
  "Apply abs to the sub-expression at point.
`maf-editplus-wrap-ln' with a different name written in front of the
pair — point names the argument the same way, and the same rules
apply to the end of the entry, to a region, and to a press with
nothing behind point:

  a+|b*c     =>  a+abs(b)*c
  a+b*c|     =>  a+b*abs(c)
  x = |      =>  x = abs(|)

Bound to `|' in `maf-edit-mode-map', which costs the character its own
key for the length of a session — calc reads it as vector
concatenation, and one wanted literally has to be yanked in. The
union `||' is the exception, and it is spelled U instead
\(`maf-editplus--commit-union')."
  (interactive)
  (maf-editplus--apply-function "abs"))

(defun maf-editplus-wrap-sin ()
  "Apply sin to the sub-expression at point.
`maf-editplus-wrap-ln' with a different name written in front of the
pair — point names the argument the same way, and the same rules
apply to the end of the entry, to a region, and to a press with
nothing behind point:

  a+|b*c     =>  a+sin(b)*c
  x+2|       =>  x+sin(2)
  x = |      =>  x = sin(|)

Bound to `S' in `maf-edit-mode-map', the key calc gives the sine on
the stack, so a capital S is no longer self-inserting during a
session."
  (interactive)
  (maf-editplus--apply-function "sin"))

(defun maf-editplus-wrap-cos ()
  "Apply cos to the sub-expression at point.
`maf-editplus-wrap-ln' with a different name written in front of the
pair — point names the argument the same way, and the same rules
apply to the end of the entry, to a region, and to a press with
nothing behind point:

  a+|b*c     =>  a+cos(b)*c
  x+2|       =>  x+cos(2)
  x = |      =>  x = cos(|)

Bound to `C' in `maf-edit-mode-map', the key calc gives the cosine on
the stack, so a capital C is no longer self-inserting during a
session — a variable wanting the bare letter has to be yanked in."
  (interactive)
  (maf-editplus--apply-function "cos"))

(defun maf-editplus-wrap-tan ()
  "Apply tan to the sub-expression at point.
`maf-editplus-wrap-ln' with a different name written in front of the
pair — point names the argument the same way, and the same rules
apply to the end of the entry, to a region, and to a press with
nothing behind point:

  a+|b*c     =>  a+tan(b)*c
  x+2|       =>  x+tan(2)
  x = |      =>  x = tan(|)

Bound to `T' in `maf-edit-mode-map', the key calc gives the tangent on
the stack, so a capital T is no longer self-inserting during a
session."
  (interactive)
  (maf-editplus--apply-function "tan"))

;;; The general logarithm

;; log is the one function key whose call has a second argument, and
;; the base is the whole of what is different about it. The wrap is the
;; family's — point names the argument the way it names ln's — and the
;; base is written out rather than prompted for: a minibuffer read
;; mid-session is the thing `maf-edit-insert-semicolon' exists to avoid,
;; and a base spelled in the text is one the next press can read back.
;; That reading is the default: a log already in the entry says what
;; base the work is in, so the nearest one at or before the target
;; lends its base, and the first log of an entry, with nothing to
;; inherit, writes no base at all. Spelled once, a base propagates by
;; itself.
;;
;; On commit the visible spelling is traded for calc's: the bare
;; log(x) — which calc itself would read as ln — and a log(x, 10)
;; typed by hand both mean the common logarithm here, and
;; `maf-editplus--commit-log10' rewrites each as log10(x) through
;; `maf-edit-transform-value-functions'. The text kept the notation
;; short while it could still be edited; the stack gets the name calc
;; gives the common logarithm.

(defun maf-editplus--call-name (node)
  "The name heading NODE, when NODE is a call; nil otherwise.
A call node's span starts on its name — `maf-editplus--parse' builds
it from the atom and the group together — so the name is the atom run
at the span's head."
  (when (eq (maf-editplus--node-kind node) 'call)
    (let ((start (maf-editplus--node-start node)))
      (buffer-substring-no-properties
       start
       (maf-editplus--atom-run start (maf-editplus--node-end node))))))

(defun maf-editplus--log-inherited-base (target)
  "The base text the log written at TARGET inherits, or nil.
The entry is parsed and its two-argument log calls collected; the one
starting nearest to — at or before — TARGET's own start lends its
base, as the text spells it: 2, b and n+1 are each a base worth
carrying forward. At-or-before rather than strictly before, so a log
being wrapped in another log lends its own base to the wrap.

Nil with no such call: the first log of an entry has nothing to
inherit, and the caller writes no base. A one-argument log(x) has
no base written and lends nothing."
  (let ((entry (maf-editplus--entry-at-point)))
    (when entry
      (let* ((limit (+ (overlay-start entry)
                       (maf-edit--leading-prefix-run (overlay-start entry))))
             (bound (overlay-end entry))
             (pos (pcase target
                    (`(region ,beg ,_) beg)
                    (`(node . ,node) (maf-editplus--node-start node))
                    (`(unit ,beg ,_) beg)
                    (_ (point))))
             (best nil)
             (base nil))
        (cl-labels
            ((walk (node)
               (when node
                 (let ((kids (maf-editplus--node-children node)))
                   (when (and (equal (maf-editplus--call-name node) "log")
                              (= (length kids) 2)
                              (<= (maf-editplus--node-start node) pos)
                              (or (null best)
                                  (> (maf-editplus--node-start node) best)))
                     (setq best (maf-editplus--node-start node)
                           base (cadr kids)))
                   (mapc #'walk kids)))))
          (walk (maf-editplus--parse limit bound)))
        (when base
          ;; Flattened as a copy is (`maf-editplus--flat-copy'): a base
          ;; continued across a line break carries over as one line.
          (car (maf-editplus--flat-copy
                (maf-editplus--node-start base)
                (maf-editplus--node-end base)
                (maf-editplus--node-start base))))))))

(defun maf-editplus-wrap-log (base)
  "Apply log to the sub-expression at point, its base written out.
`maf-editplus-wrap-ln' with a second argument: point names the log's
argument the same way, and the same rules apply to the end of the
entry, to a region, and to a press with nothing behind point — where
the empty call opens with point on the argument slot, an inherited
base already in place after it:

  a+b|*c     =>  a+log(b*c)
  x+2|       =>  x+log(2)
  x = |      =>  x = log(|)

The base is defaulted, never prompted for. A numeric prefix names it
outright — \\[universal-argument] 2 then the key writes log(x, 2) —
and otherwise the entry itself is read: the two-argument log call
starting nearest at or before the target lends its base, whatever
expression the text spells there. With no log to inherit from none
is written — the bare log(x) means the common logarithm — so a base
is only ever missing on the first log of an entry, and spelling it
there carries it to the rest:

  log(a,2)+x|  =>  log(a,2)+log(x, 2)

On commit the bare call gets calc's name for what it means: every
log(x) — and every log(x, 10) typed by hand — in a changed entry
commits as log10(x), the spelling calc itself uses for the common
logarithm (`maf-editplus--commit-log10'); to calc an unrewritten
log(x) would mean ln. A base the text inherited or was given stays
as written.

Bound to `B' in `maf-edit-mode-map', the key calc gives the logarithm
on the stack (and maf keeps for `mafcmd-log'), so a capital B is no
longer self-inserting during a session."
  (interactive "P")
  (let* ((target (maf-editplus--resolve-target))
         (base (cond ((integerp base) (number-to-string base))
                     ((maf-editplus--log-inherited-base target)))))
    (maf-editplus--apply-call target "log" (and base (concat ", " base)))))

(defun maf-editplus--commit-log10 (expr)
  "EXPR with every log(x) and log(x, 10) rewritten as calc's log10(x).
On `maf-edit-transform-value-functions' while the module is on, so
the bare call `maf-editplus-wrap-log' writes — and a log(x, 10)
typed by hand — commits in calc's own spelling; to calc itself a
one-argument log(x) would mean ln. Only a missing base or the exact
integer 10: log(x, 10.) and log(x, b) mean what they say and pass
through untouched, as does everything else in EXPR."
  (cond
   ((not (consp expr)) expr)
   ((and (eq (car expr) 'calcFunc-log)
         (or (= (length expr) 2)
             (and (= (length expr) 3)
                  (eql (nth 2 expr) 10))))
    (list 'calcFunc-log10 (maf-editplus--commit-log10 (nth 1 expr))))
   (t (cons (car expr) (mapcar #'maf-editplus--commit-log10 (cdr expr))))))

;;; The union

;; A solution set is written with a union — x < -1 || x > 1, the shape
;; `a k' and `a S' hand back — and the vertical bar is not a character
;; an edit session can type: `|' is the modulus key here, and pressing
;; it twice only wraps twice. So the union is spelled U, the letter
;; drawn like the sign, and commit trades it for calc's own || .
;;
;; The trade is the log key's, one layer further down. log(x)
;; parses as itself and wants only renaming, so it rides
;; `maf-edit-transform-value-functions'; a U does not parse as an
;; operator at all — calc reads a lone U as a variable, and
;; x<-1 U x>1 as nothing — so this one rewrites the text before the
;; parser sees it, on `maf-edit-transform-text-functions'.
;;
;; Which U: one standing between two operands with whitespace on both
;; sides — [1,2] U [3], x < -1 U x > 1. A U inside a name is part of
;; the name; a U written tight against a neighbour is a factor; and a
;; U with an operator rather than an operand beside it is the variable
;; it looks like, so E = U + K commits as written. What the rule does
;; cost is a spaced-out U used as a factor — a U b — a product nobody
;; writes that way while * has a key of its own.

(defun maf-editplus--top-level-dotdots (text)
  "Indexes of TEXT's .. tokens at bracket depth zero, outside strings.
The token calc reads only inside interval delimiters — so one at the
top level means the delimiters were left off."
  (let ((strings (maf-edit--string-regions text))
        (depth 0) (hits nil) (i 0) (n (length text)))
    (while (< i n)
      (let ((c (aref text i)))
        (cond
         ((seq-find (lambda (r) (and (>= i (car r)) (< i (cdr r)))) strings)
          nil)
         ((memq c '(?\( ?\[ ?\{)) (setq depth (1+ depth)))
         ((memq c '(?\) ?\] ?\})) (setq depth (1- depth)))
         ((and (zerop depth) (eq c ?.) (< (1+ i) n)
               (eq (aref text (1+ i)) ?.))
          (push i hits) (setq i (1+ i)))))
      (setq i (1+ i)))
    (nreverse hits)))

(defun maf-editplus--interval-open-p (endpoint)
  "Whether ENDPOINT of a bare interval takes the open delimiter.
An infinity does — no set closes at inf — anything else the closed
one, the tighter reading of a bare range."
  (member (string-trim endpoint) '("inf" "-inf" "+inf" "uinf" "-uinf")))

(defun maf-editplus--commit-interval (text)
  "TEXT with a bare interval's delimiters filled in as it commits.
A range typed without its brackets — the .. token at the top level,
where calc reads it only inside interval delimiters — is wrapped
with the pair it means: open at an infinite end, closed at a finite
one (`maf-editplus--interval-open-p'), so -inf..-1 commits as
\=(-inf .. -1] and 1..5 as [1 .. 5]. On
`maf-edit-transform-text-functions' while the module is on.

Only the entry that is one bare interval whole: exactly one top-level
.. and no top-level comma. A delimited interval has its .. at depth
one and passes through untouched, spelling and all; anything more
composite is left to say what it says."
  (let ((trimmed (string-trim text)))
    (if (or (string-empty-p trimmed)
            (maf-edit--top-level-comma-p trimmed))
        text
      (let ((dots (maf-editplus--top-level-dotdots trimmed)))
        (if (/= (length dots) 1)
            text
          (let* ((i (car dots))
                 (lhs (substring trimmed 0 i))
                 (rhs (substring trimmed (+ i 2))))
            (if (or (string-blank-p lhs) (string-blank-p rhs))
                text
              (concat (if (maf-editplus--interval-open-p lhs) "(" "[")
                      trimmed
                      (if (maf-editplus--interval-open-p rhs) ")" "]")))))))))

(defconst maf-editplus--union-space '(?\s ?\t ?\n)
  "Whitespace separating the union U from its operands.")

(defconst maf-editplus--union-enders '(?\) ?\] ?\} ?\")
  "Non-name characters that can end the operand before a union U.")

(defconst maf-editplus--union-starters '(?\( ?\[ ?\{ ?\" ?- ?+)
  "Non-name characters that can start the operand after a union U.")

(defun maf-editplus--union-at-p (text i)
  "Non-nil when the U at index I of TEXT stands as the union operator.
Whitespace on both sides, an operand ending somewhere before it and
another starting somewhere after — a name character or one of
`maf-editplus--union-enders' and `maf-editplus--union-starters'. Nil
for a U at either end of TEXT, one touching a neighbour, and one
whose neighbour is an operator: those are names and factors, and the
text means them as it spells them."
  (let ((n (length text)))
    (and (> i 0)
         (< (1+ i) n)
         (memq (aref text (1- i)) maf-editplus--union-space)
         (memq (aref text (1+ i)) maf-editplus--union-space)
         (let ((j (1- i))
               (k (1+ i)))
           (while (and (>= j 0)
                       (memq (aref text j) maf-editplus--union-space))
             (setq j (1- j)))
           (while (and (< k n)
                       (memq (aref text k) maf-editplus--union-space))
             (setq k (1+ k)))
           (and (>= j 0)
                (< k n)
                (let ((before (aref text j))
                      (after (aref text k)))
                  (and (or (maf-editplus--name-char-p before)
                           (memq before maf-editplus--union-enders))
                       (or (maf-editplus--name-char-p after)
                           (memq after maf-editplus--union-starters)))))))))

(defun maf-editplus--commit-union (text)
  "TEXT with each union U rewritten as the || calc reads.
On `maf-edit-transform-text-functions' while the module is on, so a
union can be typed at all: the vertical bar has no key in an edit
session, `|' being the modulus (`maf-editplus-wrap-abs'), and U is
the letter drawn like the sign.

Only a U standing between two operands, whitespace on both sides
\(`maf-editplus--union-at-p'), and only outside a string literal —
where a U is text like any other character. Everything else in TEXT
passes through untouched."
  (let ((strings (maf-edit--string-regions text))
        (parts nil)
        (last 0)
        (i 0)
        (n (length text)))
    (while (< i n)
      (when (and (eq (aref text i) ?U)
                 (not (seq-find (lambda (r) (and (>= i (car r)) (< i (cdr r))))
                                strings))
                 (maf-editplus--union-at-p text i))
        (push (substring text last i) parts)
        (push "||" parts)
        (setq last (1+ i)))
      (setq i (1+ i)))
    (if (null parts)
        text
      (push (substring text last) parts)
      (apply #'concat (nreverse parts)))))

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

(defun maf-editplus--digit-exponent (node)
  "The bounds of NODE's exponent, when it is a run of digits, or nil.
Only a power written with its exponent spelled out can be counted up
in place. x^y is a power all the same; there the key squares it, as
it does anything else."
  (when (equal (maf-editplus--node-kind node) "^")
    (let ((exp (cadr (maf-editplus--node-children node))))
      (when exp
        (let ((start (maf-editplus--node-start exp))
              (end (maf-editplus--node-end exp)))
          (when (string-match-p
                 "\\`[0-9]+\\'" (buffer-substring-no-properties start end))
            (cons start end)))))))

(defun maf-editplus--raise-span (beg end)
  "Square BEG..END as one parenthesized unit; point lands on the caret.
The parens are not optional: the span is a region that only the marks
say to treat whole, and a bare caret would take just its tail. As in
`maf-editplus--raise-node', the opener goes
in first, so the closer's position is the span's end shifted by the
one character — and with point on the caret, the next press finds a
power to count up."
  (save-excursion (goto-char beg) (insert "("))
  (save-excursion (goto-char (1+ end)) (insert ")^2"))
  (goto-char (+ end 2)))

(defun maf-editplus--raise-node (node)
  "Raise the sub-expression NODE names to the next power.
Returns where the caret ended up, which is where point belongs: the
node under point is then the power itself, so the next press counts
that up rather than squaring its exponent.

A power whose exponent is written in digits is counted up in place —
x^2 becomes x^3. Anything else is squared, with parentheses when the
text needs them to mean it: a+b squared is (a+b)^2, while a number, a
name, a call, a bracketed group and a node already in a bare pair
each take the caret as they stand."
  (let ((digits (maf-editplus--digit-exponent node))
        (start (maf-editplus--node-start node))
        (end (maf-editplus--node-end node)))
    (cond
     (digits
      (let ((power (string-to-number (buffer-substring-no-properties
                                      (car digits) (cdr digits)))))
        (save-excursion
          (delete-region (car digits) (cdr digits))
          (goto-char (car digits))
          (insert (number-to-string (1+ power)))))
      ;; The caret is the text character in front of the run.
      (1- (maf-editplus--skip-fill-back (car digits) start)))
     ((or (maf-editplus--node-atomic-p node)
          (maf-editplus--node-parenthesized-p node))
      (save-excursion (goto-char end) (insert "^2"))
      end)
     (t
      ;; The opener goes in first, so the closer's position is the
      ;; node's end shifted by the one character.
      (save-excursion (goto-char start) (insert "("))
      (save-excursion (goto-char (1+ end)) (insert ")^2"))
      (+ end 2)))))

(defun maf-editplus-raise-power (n)
  "Raise the sub-expression at point to the next power, N times.
The second press is the point: an exponent reached for rather than
named, one power per keypress.

  x|         =>  x^2  =>  x^3  =>  x^4

Point inside the text names what is raised the way it names the
argument of `maf-editplus-wrap-ln' — the innermost sub-expression the
character under point belongs to — and the parentheses that keeps the
text honest go in with it:

  a+b|*c     =>  a+(b*c)^2      (point on an operator: its node)
  a+|b*c     =>  a+b^2*c        (point on an operand: that operand)

Point is left on the caret, so pressing again counts the power up
rather than squaring the exponent.

An active region is raised exactly as marked, the way it names the
argument of `maf-editplus-wrap-ln', in the parentheses that keep the
marked text one unit whatever it holds — ln(xy) with xy marked
becomes ln((xy)^2). Point lands on the caret here too, so the next
press counts the power up.

At the end of the entry there is no character under point, and what
counts as the exponent is a run of digits immediately behind point
with the caret in front of it — anything else and a fresh ^2 goes in.
So x^2 y counts as no exponent at all, and x^2* neither. Under the
input dialect a bare run of letters is a run of factors, and the
caret binds to the last of them, the same smallest expression the
wrap keys take there:

  ab|        =>  ab^2           (dialect: a times b squared)

Bound to \\=' and `W' in `maf-edit-mode-map'."
  (interactive "p")
  (dotimes (_ n)
    (pcase (maf-editplus--resolve-target)
      (`(region ,beg ,end)
       (maf-editplus--raise-span beg end))
      (`(node . ,node)
       (goto-char (maf-editplus--raise-node node)))
      (`(unit ,beg ,end)
       (let ((text (buffer-substring-no-properties beg end)))
         (cond
          ;; A power's spelled-out exponent counts up in place.
          ((and (string-match-p "\\`[0-9]+\\'" text)
                (eq (char-before beg) ?^))
           (delete-region beg end)
           (goto-char beg)
           (insert (number-to-string (1+ (string-to-number text)))))
          ;; A run the dialect splits needs nothing extra: the caret
          ;; binds to its last factor, the same smallest expression
          ;; the wrap keys take there (`maf-editplus--unit-last-factor'),
          ;; so ab| becomes ab^2 — a times b squared. The run whole
          ;; stays reachable by marking it.
          (t
           (goto-char end)
           (insert "^2")))))
      (_
       (insert "^2")))))

;;; Deleting a power whole

(defun maf-editplus--power-op-before (pos limit)
  "Start of the power operator ending just before POS, or nil.
The caret, or the second star of `**' — calc's other spelling of the
power, two characters that are one operator, which is why its tail is
not a `*' to backspace alone. LIMIT bounds the look behind, and
machine-owned characters are furniture, never operators."
  (cond
   ((<= pos limit) nil)
   ((get-text-property (1- pos) 'maf-edit-prefix) nil)
   ((eq (char-before pos) ?^) (1- pos))
   ((and (eq (char-before pos) ?*)
         (> (1- pos) limit)
         (eq (char-before (1- pos)) ?*)
         (not (get-text-property (- pos 2) 'maf-edit-prefix)))
    (- pos 2))))

(defun maf-editplus--power-op-at (pos limit)
  "Start of the power operator whose character POS stands on, or nil.
The caret under point, or either star of `**' — deleting forward into
any character of the operator is deleting the operator, and its other
half must not be left behind as the `*' it is not. LIMIT bounds the
look behind for the pair's first half, and machine-owned characters
are furniture, never operators."
  (cond
   ((get-text-property pos 'maf-edit-prefix) nil)
   ((eq (char-after pos) ?^) pos)
   ((eq (char-after pos) ?*)
    (cond
     ((and (eq (char-after (1+ pos)) ?*)
           (not (get-text-property (1+ pos) 'maf-edit-prefix)))
      pos)
     ((and (> pos limit)
           (eq (char-before pos) ?*)
           (not (get-text-property (1- pos) 'maf-edit-prefix)))
      (1- pos))))))

(defun maf-editplus--whole-element-p (start end limit bound)
  "Non-nil when START..END stands alone as one element of the entry.
Nothing but fill lies between it and the entry's own ends, a
delimiter, or a comma — the places any expression stands unbracketed,
so a bare pair around such a span is furniture whatever it holds. An
operator on either side fails the test: there dropping a pair can
regroup its neighbours, and whether it would is precedence this check
deliberately does not weigh — a pair kept is never wrong, a pair
dropped can be."
  (let ((before (maf-editplus--skip-fill-back start limit))
        (after (maf-editplus--skip-fill-forward end bound)))
    (and (or (<= before limit)
             (memq (char-before before)
                   (append maf-editplus--openers '(?, ?\;))))
         (or (>= after bound)
             (memq (char-after after)
                   (append maf-editplus--closers '(?, ?\;)))))))

(defun maf-editplus--delete-power-at (op entry limit)
  "Delete the power whose operator starts at OP; non-nil when one did.
The node the operator's own character lies in is the power it heads:
the base ends before the operator and the exponent starts after, so
no child of the power covers it. Anything else under the character —
an atom holding a stray caret, a string — is not a power, and nil
comes back with nothing deleted.

The operator and its exponent go together; the base keeps whatever it
wears — a pair of parens around it was typed or written for grouping,
and deleting the power has no claim on it. Point lands after the
base."
  (let ((node (maf-editplus--node-at
               (maf-editplus--parse limit (overlay-end entry))
               op)))
    (when (and node (equal (maf-editplus--node-kind node) "^"))
      (delete-region op (maf-editplus--node-end node))
      (goto-char op)
      t)))

(defun maf-editplus-delete-backward (n)
  "Delete backward; a power's operator takes its exponent with it.
Backspacing onto `^' — or onto the second star of `**', calc's other
spelling — deletes the whole power tail rather than leaving text that
quietly means something else: x^3 minus its caret alone would read as
the one name x3. The exponent goes with the operator whatever its
shape — digits, a name, a call, a signed number, a tower folded to
the right:

  x^|3        =>  x
  x^|(a+b)    =>  x
  x^|2^3      =>  x          (the exponent of the first caret)
  x^2^|3      =>  x^2

The base keeps its parentheses: a pair around it groups, and deleting
the power is not a claim on the grouping —

  (x + 1)^|(a + b)  =>  (x + 1)
  2*(x+1)^|2        =>  2*(x+1)

What the caret heads is the parse's answer (`maf-editplus--parse'),
so a `^' the entry does not read as a power — inside a string, or
with no base in front of it — is just a character, and deletes as
one. Everywhere else the key is what DEL always was: plain backward
deletion, one character per press, N of them with an argument — the
join gesture on a prefix, the entry-merging delete at an entry's
head, all of it unchanged. C-d is the same gesture from the other
side of the operator (`maf-editplus-delete-forward').

Runs only during a maf-edit session, where the key is bound; outside
one there is no entry text for the gesture to read."
  (interactive "p")
  (unless maf-edit-mode
    (user-error "maf-edit is not active"))
  (dotimes (_ n)
    (let* ((entry (maf-editplus--entry-at-point))
           (limit (and entry
                       (+ (overlay-start entry)
                          (maf-edit--leading-prefix-run
                           (overlay-start entry)))))
           (op (and entry
                    (maf-editplus--power-op-before (point) limit))))
      (unless (and op (maf-editplus--delete-power-at op entry limit))
        (delete-char -1)))))

(defun maf-editplus-delete-forward (n)
  "Delete forward; a power's operator takes its exponent with it.
The forward twin of `maf-editplus-delete-backward': pressed with
point on the caret — or on either star of `**', whose other half
must not be left behind as the `*' it is not — the operator and its
exponent go together, rather than leaving text that quietly means
something else:

  1 / (x|^2 - 1)  =>  1 / (x - 1)
  x|^2^3          =>  x
  (a+b)|^2        =>  (a+b)
  2*(x+1)|^2      =>  2*(x+1)

The rules are the backward key's own (`maf-editplus--delete-power-at'):
the parse names the power the operator heads, the exponent goes whole
whatever its shape, and the base keeps its parentheses. Point lands
after the base. On any
other character the key is what C-d always was — plain forward
deletion, one character per press, N of them with an argument.

Runs only during a maf-edit session, where the key is bound; outside
one there is no entry text for the gesture to read."
  (interactive "p")
  (unless maf-edit-mode
    (user-error "maf-edit is not active"))
  (dotimes (_ n)
    (let* ((entry (maf-editplus--entry-at-point))
           (limit (and entry
                       (+ (overlay-start entry)
                          (maf-edit--leading-prefix-run
                           (overlay-start entry)))))
           (op (and entry (maf-editplus--power-op-at (point) limit))))
      (unless (and op (maf-editplus--delete-power-at op entry limit))
        (delete-char 1)))))

(defun maf-editplus--number-before-p ()
  "Non-nil when the text just before point ends a bare number.
The digit run before point belongs to a number — not to an identifier
\(x2) or a radix form (16#22), whose next character it would swallow —
so a name written directly against it stays a separate token: calc
and the editvars dialect both read 2pi as a product."
  (save-excursion
    (let ((from (point)))
      (skip-chars-backward "0-9")
      (and (< (point) from)
           (not (eq (char-before) ?#))
           (not (maf-editplus--name-char-p (char-before)))))))

(defun maf-editplus-insert-pi (n)
  "Insert the constant pi, N times, on the unmodified `P' key.
Two characters for the price of one keypress; a capital P is no
longer self-inserting during a session — see `maf-use-editplus-mode'
on what that costs.

After a name character a space goes in first, so `x' becomes the
product `x pi' and not the unrelated variable `xpi'. A number takes
the name directly — `44pi', the way it is written by hand — but a
digit that is the tail of an identifier or a radix form still gets
the space: `x2pi' is one name calc has never heard of, where `x2 pi'
is the product meant (`maf-editplus--number-before-p').

Under the maf-editvars dialect the name goes in as that module
spells it (`maf-editvars-quote-name'): bare while pi is exempt, the
default, and quoted — `{pi}' — where the exemption has been withdrawn
and a bare run of letters is a run of factors. With the module absent or standing down the plain name is
what goes in."
  (interactive "p")
  (let ((name (if (fboundp 'maf-editvars-quote-name)
                  (maf-editvars-quote-name "pi")
                "pi")))
    (dotimes (_ n)
      (when (and (char-before)
                 (string-match-p "[[:alnum:]]" (string (char-before)))
                 (not (maf-editplus--number-before-p)))
        (insert " "))
      (insert name))))

(defun maf-editplus-insert-times (n)
  "Insert the multiplication sign, N times, on the unmodified `J' key.
J is what maf gives multiplication on the stack (`mafcmd-mul'), and
this carries the letter into the session: it types `*', by the same
self-insertion the `*' key itself runs, so the operator keeps one key
on both sides of a maf-edit session and reaching across for shift-8
mid-formula is optional rather than required.

A capital J is no longer self-inserting during a session — see
`maf-use-editplus-mode' on what that costs."
  (interactive "p")
  (self-insert-command n ?*))

;;; The module

(define-minor-mode maf-use-editplus-mode
  "Add formula-editing shortcuts to maf-edit.

These keys work only while a maf-edit session is active:

  TAB           Move past the closing parenthesis or bracket.
  M-o           Put parentheses around the term before point.
  C-RET         Duplicate the group at point.
  S-up/S-down   Change parentheses to brackets, or back.
  L, Q, \\, |   Wrap the target in ln, sqrt, or abs.
  S/C/T         Wrap the target in sin, cos, or tan.
  B             Wrap the target in log with an explicit base.
  M-2..M-9      Type ^2 through ^9.
  : or W        Square the target; repeat to raise the power.
  P             Type pi.
  J             Type *, as the `*' key does.
  DEL/C-d       Delete a whole power when deleting next to ^.

For example, press Q on x in x+1 to get sqrt(x)+1. Press W on x to
get x^2, then press it again to get x^3. B uses base 10 unless an
earlier nearby log supplies another base or you give a numeric prefix.

A U with a space on either side is the union: type x < -1 U x > 1 and
it commits as x < -1 || x > 1, the bar having no key of its own here.

The single-character shortcuts replace normal insertion of those
characters during the edit session. Yank a literal character if needed.
Turning this mode off restores the ordinary editing keys."
  :global t
  :group 'maf
  (let ((on maf-use-editplus-mode))
    (dolist (b '(("TAB" . maf-editplus-escape-group)
                 ("M-o" . maf-editplus-wrap-parens)
                 ("C-<return>" . maf-editplus-duplicate-group)
                 ("S-<up>"   . maf-editplus-toggle-brackets)
                 ("S-<down>" . maf-editplus-toggle-brackets)
                 ("L"   . maf-editplus-wrap-ln)
                 ("Q"   . maf-editplus-wrap-sqrt)
                 ("\\"  . maf-editplus-wrap-sqrt)
                 ("|"   . maf-editplus-wrap-abs)
                 ("S"   . maf-editplus-wrap-sin)
                 ("C"   . maf-editplus-wrap-cos)
                 ("T"   . maf-editplus-wrap-tan)
                 ("B"   . maf-editplus-wrap-log)
                 (":"   . maf-editplus-raise-power)
                 ("W"   . maf-editplus-raise-power)
                 ("P"   . maf-editplus-insert-pi)
                 ("J"   . maf-editplus-insert-times)
                 ("DEL" . maf-editplus-delete-backward)
                 ("C-d" . maf-editplus-delete-forward)))
      (define-key maf-edit-mode-map (kbd (car b)) (and on (cdr b))))
    ;; One command behind eight keys — it reads the digit off the key
    ;; that ran it.
    (dolist (d '(?2 ?3 ?4 ?5 ?6 ?7 ?8 ?9))
      (define-key maf-edit-mode-map (kbd (format "M-%c" d))
                  (and on #'maf-editplus-insert-power)))
    ;; The commit-time half of B: the base-10 default trades its
    ;; visible spelling for calc's log10 as the entry leaves the text.
    ;; The union U is the same trade one layer down — it never parsed,
    ;; so it is traded in the text rather than in the value.
    (if on
        (progn
          (add-hook 'maf-edit-transform-value-functions
                    #'maf-editplus--commit-log10)
          (add-hook 'maf-edit-transform-text-functions
                    #'maf-editplus--commit-union)
          (add-hook 'maf-edit-transform-text-functions
                    #'maf-editplus--commit-interval))
      (remove-hook 'maf-edit-transform-value-functions
                   #'maf-editplus--commit-log10)
      (remove-hook 'maf-edit-transform-text-functions
                   #'maf-editplus--commit-union)
      (remove-hook 'maf-edit-transform-text-functions
                   #'maf-editplus--commit-interval))))

;; Register with the module system when it is present; the mode above
;; works on its own without it.
(when (require 'maf-module nil t)
  (maf-register-module 'maf-editplus #'maf-use-editplus-mode
                       "Add shortcuts for writing formulas inside maf-edit.

For example, Q wraps x as sqrt(x), W changes x to x^2, and M-3 types
^3. TAB moves out of parentheses, M-o adds them, and DEL or C-d
removes a whole power cleanly. J types the multiplication sign, and a
spaced-out U commits as the union ||. These keys work only while
editing."
                       nil "Editing"))

(provide 'maf-editplus)
