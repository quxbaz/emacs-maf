;; -*- lexical-binding: t; -*-
;;
;; minibuffer.el
;;
;; Digit-entry integration: contextual digit entry (`maf-digit-start'),
;; the shortcuts maf takes in the entry minibuffer (`;' for the fraction
;; colon, `n'/`P' for a multiple of pi, `e' to equate, SPC to commit the
;; number into the formula at point, `j' to jump to the entry it names),
;; and keeping point in place when a command key or C-g terminates
;; minibuffer digit entry, so the command still resolves the position
;; the user was on.

(require 'calc)
(require 'seq)
(require 'maf-lib)
(require 'maf-defcmd)

;; These live in lazily-loaded calc modules; calc-ext's autoload registry
;; resolves them at runtime, but the byte compiler needs declarations.
(declare-function calc-alg-entry "calc-aent")
(declare-function calc-dots "calc-incom")
(declare-function calcDigit-nondigit "calc")
(declare-function calcDigit-key "calc")
(declare-function calc-algebraic-entry "calc-aent")
(declare-function calc-roll-down "calc-misc")
(declare-function calc-cursor-stack-index "calc")
(declare-function calc-record "calc")
(declare-function calc-push-list "calc")
(declare-function calcDigit-letter "calc-misc")
(declare-function calc-temp-minibuffer-message "calc-misc")

(defvar maf-mode)  ; defined in maf.el; declared for the byte compiler

;; Dynamic state of calc's digit-entry minibuffer commands. calc.el
;; declares these without values, which doesn't make them special here;
;; re-declare so let-binding them in `maf-digit-start' is dynamic.
(defvar calc-digit-value)
(defvar calc-prev-char)
(defvar calc-prev-prev-char)

(defvar maf--digit-commit-in-place nil
  "Non-nil while `maf-digit-commit-here' drives `calcDigit-nondigit'.
It spoofs a RET termination to suppress calc's command re-dispatch, so
the keep-point advice would otherwise mistake it for a homing RET and
drop a mark. This flag tells the advice the entry keeps point by design.")

(defvar maf--digit-contextual nil
  "Non-nil when the finished digit entry commits into the formula at point.
Set by `maf-digit-commit-contextual' (SPC), and by `maf-digit-pi' for
the completion it stands for, whenever the entry is one maf itself is
reading on a sub-formula; read by `maf-digit-start', which then applies
the number there instead of pushing it, and by the keep-point advice,
for which a contextual commit is an in-place edit that moves nothing.
Cleared at the start of every entry. nil for every other completion —
RET included, which pushes as it does in plain calc.")

(defun maf--digit-entry-keep-point ()
  "Keep or mark point when a digit entry completes, by how it completed.
Finishing a digit entry normally parks point at home, destroying the
context the terminating command should resolve: with point on an entry,
typing 1 + would add 1 to the top of the stack instead of that entry.

A command-key termination (1 +) sets the `no-align' flag so the push
leaves point where it was — the entry's row survives, only its level
number changes — and the command that follows targets that position.
SPC's contextual commit edits the sub-formula under point, so it keeps
point too; C-<return> is the explicit keep-point commit.

A RET does park point home — it pushes the number onto the stack, as in
plain calc — as does the SPC that falls through to a push, at a margin
or wherever else `maf-digit-commit-contextual' steps aside. Before it
does, drop a mark where the user was, so a single `pop-to-mark-command'
brings them back from the home line. The mark's marker rides the push,
tracking the entry as it renumbers.

Point already at home, or `maf-mode' off in the calc buffer, is a no-op
\(plain calc behavior, no maf state touched)."
  (when (maf--with-calc-buffer maf-mode)
    (let ((command-key (not (memq last-command-event '(?\r ?\s)))))
      ;; Record how this entry completed on every run (self-clearing):
      ;; a command-key termination marks the entry's push and the command
      ;; it dispatches as one gesture for undo amalgamation.
      (setq maf--digit-entry-handoff command-key)
      (cond
       ;; Already home: nothing to preserve, nowhere to return from.
       ((maf--at-home-p))
       ;; 1 + and friends: keep point on the entry the command resolves.
       (command-key (calc-set-command-flag 'no-align))
       ;; C-<return>'s keep-point commit stays put by design.
       (maf--digit-commit-in-place)
       ;; SPC's contextual commit edits the sub-formula in place.
       (maf--digit-contextual)
       ;; A RET/SPC that pushes homes point with it: mark the origin so
       ;; the user can pop back. Point (in the calc buffer) is still on the
       ;; entry about to be vacated.
       (t (maf--mark-before-home))))))

(advice-add 'calcDigit-nondigit :before #'maf--digit-entry-keep-point)

(defun maf--algebraic-entry-leave-mark (&rest _)
  "Mark point before `calc-algebraic-entry' pushes an entry and homes.
Pressing ' to start an entry runs calc's own `calc-algebraic-entry',
which maf does not shadow; from a real position it pushes the result and
parks point home. Leave a mark first — as a homing digit-entry RET or
`maf-dup' do — so a single `pop-to-mark-command' returns there. Point is
still at the origin when this :before advice runs. At home, or with
`maf-mode' off in the calc buffer, a no-op. A mark is left even when the
entry is then aborted; that stray mark sits at point and pops to a no-op."
  (when (and (maf--with-calc-buffer maf-mode) (not (maf--at-home-p)))
    (maf--mark-before-home)))

(advice-add 'calc-algebraic-entry :before #'maf--algebraic-entry-leave-mark)

(defun maf-digit-quit ()
  "Abort digit entry, leaving point where the entry began.
Calc binds C-g in the entry minibuffer to plain `abort-recursive-edit';
the quit unwinds through `calc-do', whose epilogue still aligns the
stack window and parks point at home. Set `no-align' first so the
position the user was on survives the abort. At home, or with
`maf-mode' off in the calc buffer, alignment proceeds as in plain calc."
  (interactive)
  (when (and (maf--with-calc-buffer maf-mode)
             (not (maf--at-home-p)))
    ;; On the calcDigit-start paths the flag lands in the innermost
    ;; `calc-do' let-binding, whose unwind then skips the align. On
    ;; `maf-digit-start's own read there is no wrapper to unwind — the
    ;; setq hits the global, which every calc-do shadows; harmless.
    (calc-set-command-flag 'no-align))
  (abort-recursive-edit))

(define-key calc-digit-map "\C-g" #'maf-digit-quit)

(defun maf--incomplete-entry-p ()
  "Non-nil while calc is entering an incomplete object.
`[' or `(' starts one — a vector, matrix, complex number, or interval,
built up element by element and held on the stack as an `incomplete'
object until its closing bracket. Scans the whole stack, as
`calc-find-first-incomplete' does: the object need not be on top."
  (maf--with-calc-buffer
    (seq-some (lambda (x) (eq (car-safe (car-safe x)) 'incomplete))
              (nthcdr calc-stack-top calc-stack))))

(defun maf-digit-colon ()
  "Type the fraction colon in the digit-entry minibuffer, on `;'.
Fractions are entered often enough to be worth a key with no modifier:
`;' is the unshifted twin of `:', so 3 ; 4 RET enters 3:4.

The key is a pure alias, not an insertion: it re-dispatches calc's own
`calcDigit-key' with the event spoofed to `:', so every part of calc's
colon handling applies — the leading 1 supplied for a bare `;', the
second colon of the mixed number 1:2:3, radix and format validation.
Naming `calcDigit-key' as `this-command' keeps the run of digit keys
unbroken for the next key's `last-command' test (calc's `..' path).

While an incomplete object is being entered the key is calc's own
again: `;' is the row separator of matrix entry ([ 1 , 2 ; 3 , 4 ]),
which is typed from inside digit entry, and taking it there would make
matrices untypeable on the stack. A fraction inside one still goes in
on `:'."
  (interactive)
  (if (maf--incomplete-entry-p)
      ;; The stock binding: terminate the entry and re-dispatch `;',
      ;; which reaches `calc-semi' in `calc-mode-map' as it always did.
      (calcDigit-nondigit)
    (setq this-command 'calcDigit-key)
    (let ((last-command-event ?:))
      (calcDigit-key))))

(define-key calc-digit-map ";" #'maf-digit-colon)

(defun maf--digit-shortcuts-live-p ()
  "Non-nil when maf's shortcuts in the digit-entry map apply.
The map they live in is calc's own — `calc-digit-map' has no maf state
and belongs to no buffer — so a key installed there fires during every
calc digit entry, `maf-mode' on or off. Gate on the mode in the buffer
the entry belongs to: `calc-buffer', which calc's `calcDigit-start' and
`maf-digit-start' both bind around the read, names that buffer exactly,
where `maf--with-calc-buffer' would only guess at it from the buffer
list. With the mode off the keys stay calc's and digit entry behaves as
it does in plain calc."
  (and (buffer-live-p calc-buffer)
       (with-current-buffer calc-buffer maf-mode)))

(defun maf--digit-radix-entry-p ()
  "Non-nil when the digit entry carries an explicit radix prefix.
Inside 16#ff a letter is a digit, and which letters count — and whether
`e' and `n' still mean exponent and sign flip — depends on the radix;
calc's own digit keys decide all of it. maf's letter shortcuts in the
entry step aside there, so radix numbers stay typeable. The test is
calc's, the regexp `calcDigit-key' uses for the same question."
  (calc-minibuffer-contains ".*#.*"))

(defun maf--digit-contextual-p ()
  "Non-nil when a value committed now belongs in the formula at point.
The question `maf-digit-start' asked before the read, asked again at
the end of it: with maf's shortcuts live, algebraic mode off, no
incomplete object in progress, and point on a sub-formula, the entry
is maf's own and a value commits into that sub-formula. Anywhere else
the entry is calc's and a value is pushed.

Point cannot have moved in between — the calc buffer sits untouched
behind the minibuffer — so the two answers agree, which is what lets a
terminator decide its destination without knowing which read it is in."
  (and (maf--digit-shortcuts-live-p)
       (not (maf--incomplete-entry-p))
       (not (with-current-buffer calc-buffer calc-algebraic-mode))
       (maf--at-subexpr-p)))

(defun maf-digit-pi ()
  "Commit the digit entry multiplied by pi, on `n' and `P'.
Angles and periods are entered as multiples of pi often enough to be
worth a key inside digit entry: 2 n commits 2 pi, and 1:3 n the third
of it. Calc's leading-1 rule applies as it does to `:' and `e' — with
nothing but a sign typed, `_ n' commits -pi.

The multiplication is `math-mul', so a multiple of 1 is pi alone, and
pi stays the symbolic constant either way: nothing is evaluated to a
float.

Where the product lands is not this key's business. It hands the value
out of the entry in `calc-digit-value', as calc's own
`calcDigit-algebraic' (') hands out its string, so the entry completes
by its normal route: the completion goes where a value goes from this
position. From home or a margin the product is pushed (and the push
homes point, leaving a mark to pop back to, as RET's does); on a
sub-formula it commits contextually, as SPC does, where 2 n on the 3 of
3 x gives (2 pi) x — the product goes in as one factor, built as
literally as any other contextual commit. Being a value and its
terminator in one key, `n' has no second key to split the two
destinations across. Inside an incomplete object the element being
typed is the multiple, so a vector or matrix can be filled with
multiples of pi.

Both keys are calc's elsewhere: `n' is the entry's own sign flip, which
stays on the `_' beside it, and `P' is `calc-pi' out in the stack. They
are calc's here too inside a radix-prefixed entry, and with `maf-mode'
off in the calc buffer the entry belongs to."
  (interactive)
  (if (or (not (maf--digit-shortcuts-live-p))
          (maf--digit-radix-entry-p))
      ;; Calc's own key: maf-mode is off, or this is a digit and only
      ;; calc knows which — `calcDigit-letter' upcases P for the radices
      ;; that have a P digit, `calcDigit-key' does the same for n and
      ;; flips the sign for the radices that do not. Naming the function
      ;; as `this-command' keeps the run of digit keys unbroken for the
      ;; next key's `last-command' test, as `maf-digit-colon' does.
      (let ((fn (if (eq last-command-event ?n)
                    'calcDigit-key
                  'calcDigit-letter)))
        (setq this-command fn)
        (funcall fn))
    ;; Calc's leading-1 rule, on calc's own test for it: with only a
    ;; sign or a separator typed, the multiple is 1.
    (when (calc-minibuffer-contains "\\([-+]?\\|.* \\)\\'")
      (insert "1"))
    ;; Read the entry in the calc buffer, whose radix and format
    ;; settings decide what it means — `calcDigit-nondigit' takes the
    ;; string out of the minibuffer and reads it there in the same way.
    (let* ((str (minibuffer-contents))
           (n (with-current-buffer calc-buffer (math-read-number str))))
      (if (null n)
          ;; `calcDigit-nondigit's answer to an entry it cannot read:
          ;; refuse it and stay in the minibuffer.
          (progn (beep) (calc-temp-minibuffer-message " [Bad format]"))
        (setq calc-digit-value (math-mul n '(var pi var-pi))
              ;; Where the product lands, decided as SPC decides it.
              maf--digit-contextual (maf--digit-contextual-p))
        ;; Exiting directly bypasses `calcDigit-nondigit', where the
        ;; advice that does maf's point bookkeeping lives — so run it
        ;; for the plain terminator this completion stands for (the
        ;; advice treats RET and SPC alike; the flag above is what
        ;; tells the two destinations apart).
        (let ((last-command-event ?\r))
          (maf--digit-entry-keep-point))
        (exit-minibuffer)))))

(define-key calc-digit-map "n" #'maf-digit-pi)
(define-key calc-digit-map "P" #'maf-digit-pi)

(defun maf-digit-equal-to ()
  "End the digit entry on `e' and equate with the number entered.
`e' is `mafcmd-equal-to' out in the stack (see src/bindings.el); this
gives the entry minibuffer the same key, so an equation can be built
without stopping to push its right side:

  1:  x|    5 e  =>   1:  x = 5

It is calc's own command-key termination and nothing more — the entry
ends and the `e' re-dispatches, exactly as the `+' of 1 + does: the
number becomes the command's argument, point stays on the entry the
command resolves, and the push folds into the command's undo group. So
the command's routes come with it: the entry at point equates with the
number whatever its depth, and at home the top two join.

Its Inverse route is the one thing out of reach this way — calc's I
flag does not survive a digit entry, so I 5 e fails exactly as I 5 +
does. A != wants the number pushed first: 5 RET I e.

The cost is the e-notation this key was: 1e6 goes in through algebraic
entry (' 1e6) instead — except where the key is still calc's own, and
there e-notation is untouched."
  (interactive)
  (if (or (not (maf--digit-shortcuts-live-p))
          (maf--digit-radix-entry-p)
          (maf--incomplete-entry-p))
      ;; The key is calc's own here — e-notation, and no equation. With
      ;; maf-mode off there is no command to dispatch to in the first
      ;; place. In a radix-prefixed entry the key is a digit (16#3e) or
      ;; that radix's exponent marker (8#1.2e5). And while an incomplete
      ;; object is being entered there is nothing to equate — the vector
      ;; or matrix under construction is not an entry yet — so
      ;; terminating would equate the incomplete object itself.
      (progn (setq this-command 'calcDigit-key)
             (calcDigit-key))
    ;; Named as calc's own terminator, which is what this key is: the
    ;; undo amalgamation of the arg push tests `last-command' for the
    ;; digit-entry commands (`maf--undo-amalgamate-digit-entry'), and
    ;; without the name the push would survive an undo of the equation.
    (setq this-command 'calcDigit-nondigit)
    (calcDigit-nondigit)))

(define-key calc-digit-map "e" #'maf-digit-equal-to)

(defvar maf--digit-jump-level nil
  "Stack level a finished digit entry should send point to, or nil.
Set by `maf-digit-jump' (`j') to the level the entry named; read by
`maf-digit-start' once the entry has completed with nothing committed,
which then moves point there. nil for every other completion.")

(defvar maf--digit-jump-origin nil
  "Buffer position point stood at when the current digit entry began.
Set by `maf-digit-start' before the read; where a `j' completion jumps
from and leaves its mark. Point itself cannot serve — the calc-side
completion parks it at home before the jump runs — and the position
stays valid because a jump commits nothing, so the buffer is unchanged.")

(defun maf-digit-jump ()
  "Send point to the stack entry the digit entry names, on `j'.
Reaching a distant entry is otherwise a run of C-p; this makes the
level number the address, typed as a number because a number is what
the digit keys already start:

  3:  c              3 j  =>  3:  c|
  2:  b                       2:  b
  1:  a|                      1:  a

Nothing is entered or pushed — the number is a destination, not a
value. Point lands at the entry's end, its margin, so the next command
takes the whole entry; level 0 is home. A level past the top of the
stack lands on the top entry, as a jump past the end of a buffer lands
on its last line. The place point left is marked, so C-u C-SPC returns
to it — home excepted, being one keystroke away already.

An entry that is not a whole number names no level: it is refused and
left standing to be corrected, as an unreadable entry is.

The key is calc's `j' selection prefix out in the stack, which maf
lends its own sequences (j l, j r, j e); the cost here is the
command-key termination it was, so 3 j e no longer pushes the 3 and
runs the prefix on it. Push first (3 RET) and the prefix is itself
again. `j' addressing a level is the same reading as calc's own j,
which addresses a part of an entry.

`j' stays calc's own where the number is plainly a value and not an
address: inside a radix-prefixed entry, where a stack level would be
written in base 16 — and where `j' is itself a digit from base 20 up;
while an incomplete object is being entered, where half a vector is no
place to leave from; and with `maf-mode' off in the calc buffer."
  (interactive)
  (if (or (not (maf--digit-shortcuts-live-p))
          (maf--digit-radix-entry-p)
          (maf--incomplete-entry-p))
      ;; The stock binding: `calcDigit-letter', which takes `j' as a
      ;; digit in the radices that have one and otherwise ends the
      ;; entry, re-dispatching `j' as the prefix it is out in the
      ;; stack. Named as itself, as `maf-digit-pi' names the same
      ;; function, so nothing about the fallback path differs from
      ;; plain calc.
      (progn (setq this-command 'calcDigit-letter)
             (calcDigit-letter))
    (let* ((str (minibuffer-contents))
           ;; Read in the calc buffer, whose radix and format settings
           ;; decide what the string means, as `calcDigit-nondigit' does.
           (n (with-current-buffer calc-buffer (math-read-number str))))
      (cond
       ;; `calcDigit-nondigit's answer to an entry it cannot read, and
       ;; the same one for an entry that reads but names no level (1:2,
       ;; -3): refuse it and stay in the minibuffer.
       ((null n) (beep) (calc-temp-minibuffer-message " [Bad format]"))
       ((not (natnump n)) (beep) (calc-temp-minibuffer-message " [Bad level]"))
       (t
        (setq maf--digit-jump-level n
              ;; Nothing is committed, so there is no arg push for a
              ;; following command to fold into its undo group.
              maf--digit-entry-handoff nil)
        ;; Leave the entry empty: neither `calcDigit-start' nor
        ;; `maf-digit-start' then finds a value to commit, and the jump
        ;; happens back in the calc buffer once the read returns.
        (delete-minibuffer-contents)
        (exit-minibuffer))))))

(define-key calc-digit-map "j" #'maf-digit-jump)

(defun maf-digit-commit-contextual ()
  "Commit the digit entry into the sub-formula at point, on SPC.
SPC is maf's edit key out in the stack (`maf-edit' opens the entry at
point as text), and it edits here too: the number goes into the
formula under point rather than onto the stack.

  12| x + 3     5 SPC  =>  5 x + 3        (numeric leaf: replaced)
  x| + 3        5 SPC  =>  5 x + 3        (sub-formula: multiplied)
  2 + (a| + b)  5 SPC  =>  2 + 5 (a + b)  (literal: no distributing)

`maf-digit-start' does the committing (`maf--digit-apply' decides which
of those three it is); this key only marks the completion as
contextual. Point stays on the sub-formula it edited — nothing was
pushed, so there is no push to home after.

Everywhere a value is pushed instead — at home, in the line prefix, at
EOL, in algebraic mode, while an incomplete object is being entered
\(where SPC separates a vector's elements), and with `maf-mode' off —
the key is calc's own terminator, which is exactly a push: the
unshifted twin of RET, doing what RET does."
  (interactive)
  ;; nil here is also the clear: SPC is the only key that sets the flag
  ;; by hand, and it must not carry a stale t into a pushing entry.
  (setq maf--digit-contextual (maf--digit-contextual-p))
  ;; Calc's own terminator either way — SPC is one of the two keys
  ;; (with RET) that end the entry without re-dispatching a command.
  ;; Named as itself for the same reason `maf-digit-equal-to' names it:
  ;; `last-command' after the entry must still be one of the
  ;; digit-entry commands.
  (setq this-command 'calcDigit-nondigit)
  (calcDigit-nondigit))

(define-key calc-digit-map " " #'maf-digit-commit-contextual)

(defun maf--digit-take-jump ()
  "Send point to the level `maf-digit-jump' asked for, if it asked.
Runs in the calc buffer once a digit entry has finished, jumping from
`maf--digit-jump-origin'. Level 0 is home; a level past the top of the
stack lands on the top entry. Point rests at the entry's EOL, its
margin, so the next command takes the whole entry."
  (when-let ((n (prog1 maf--digit-jump-level
                  (setq maf--digit-jump-level nil))))
    (let ((from maf--digit-jump-origin)
          (m (min n (calc-stack-size))))
      (if (zerop m)
          (progn (calc-cursor-stack-index 0)
                 ;; The dot sits past the line-number margin when
                 ;; numbering is on, at the line's start when it is off.
                 (skip-chars-forward " "))
        (calc-cursor-stack-index m)
        (end-of-line))
      ;; Mark the place the jump left so a single `pop-to-mark-command'
      ;; returns to it, as every maf command that moves point off an
      ;; entry does. Home is never marked (`maf-go-home' reaches it in
      ;; one key), and with a region up the marks are left alone — the
      ;; mark is the selection's anchor, and a target here.
      (unless (or (= (point) from)
                  (use-region-p)
                  (save-excursion (goto-char from) (maf--at-home-p)))
        (maf--mark-before-home from)))))

(defvar maf--digit-keep-point nil
  "Non-nil when the digit entry's push should leave point where it is.
Set by `maf-digit-commit-here' (C-<return>); read by `maf-digit-start',
which then pushes with `no-align' and carries point through instead of
letting the push home it. The let-bound `maf--digit-commit-in-place' —
which says the same thing to the advice — cannot serve: its binding is
gone by the time the read returns.")

(defun maf-digit-commit-here ()
  "Push the digit entry like RET, but keep point instead of homing.
The keep-point sibling of RET in the digit-entry minibuffer, on
C-<return>: the number is pushed onto the stack exactly as RET pushes
it, but point stays on the entry it was on rather than dropping to the
home line, so the next command still resolves there. At home there is
nowhere to stay, so it matches RET. With `maf-mode' off in the calc
buffer, plain calc behavior.

It follows RET onto the stack rather than into the formula at point:
the contextual commit is SPC's, and SPC keeps point already — the edit
happens where point stands, so there is nothing for a keep-point
sibling of it to do.

`calcDigit-nondigit' is calc's own terminator; binding `last-command-event'
to RET around it takes its RET path — commit, no command re-dispatch (so
this never triggers `mafcmd-let', C-<return>'s stack-mode
binding) — while `no-align' is what carries point through the push. The
flag is set both here and, via `maf--digit-keep-point', inside the
wrapper `maf-digit-start' pushes from: on calc's own read this code
runs within the `calc-do' whose flags the push consults, but maf's own
read happens outside any wrapper, where a flag set now would be lost to
the fresh binding `calc-do' makes later."
  (interactive)
  (setq maf--digit-keep-point t)
  (when (and (maf--with-calc-buffer maf-mode) (not (maf--at-home-p)))
    (calc-set-command-flag 'no-align))
  (let ((last-command-event ?\r)
        (maf--digit-commit-in-place t))
    (calcDigit-nondigit)))

(define-key calc-digit-map (kbd "C-<return>") #'maf-digit-commit-here)

(defvar maf--digit-below-level nil
  "Stack level a digit entry should be inserted just below, or nil.
Set by `maf-digit-commit-below' (S-<return>) to the level point was on;
read by `maf-digit-start' once the number has been pushed on top, which
rolls it down into that slot. nil for every other completion.")

(defun maf-digit-commit-below ()
  "Commit the digit entry as a new stack entry just below the one at point.
The S-<return> sibling of RET in the digit-entry minibuffer, mirroring
`maf-edit-add-entry-below' (S-<return> in stack mode): where RET pushes
the number on top, this inserts it at point's own level, so it lands just
below the entry point was on and bumps that entry up one. On the top
entry or at home it lands on top, as RET does; point rests on the new
entry.

Like `maf-digit-commit-here' it commits through `calcDigit-nondigit's RET
path (no command re-dispatch); the number pushes on top as usual, and
`maf-digit-start' then rolls it down to `maf--digit-below-level'."
  (interactive)
  (setq maf--digit-below-level
        (maf--with-calc-buffer (max 1 (calc-locate-cursor-element (point)))))
  (let ((last-command-event ?\r)
        (maf--digit-commit-in-place t))
    (calcDigit-nondigit)))

;; Matching `maf-edit-add-entry-below's key in stack mode: the gesture is
;; the same one, and which map is live depends only on whether a digit
;; entry happens to be in progress.
(define-key calc-digit-map (kbd "S-<return>") #'maf-digit-commit-below)

(defun maf--digit-relocate-below (m)
  "Roll the just-pushed top entry down to level M, point resting on it.
The number was pushed on top; move it just below where point was — level
M, bumping the entry that was there up one — and leave point at its
margin. M of 1 (the top entry, or home) needs no roll.

The roll — and the undo fold that keeps the whole S-<return> gesture
a single `maf-undo' — is `maf--roll-top-below'; this adds the digit
entry's own point placement on top."
  (maf--roll-top-below m)
  (calc-cursor-stack-index m)
  (end-of-line))

(defun maf--digit-push (val keep-point)
  "Push VAL onto the stack, the tail of calc's own digit entry.
With KEEP-POINT the push leaves point on the entry it was on instead of
parking it at home: `no-align' stops the home jump, and
`maf--preserve-point' carries point through the renumbering the push
itself causes, which `no-align' does nothing about. The flag has to be
set inside the wrapper — `calc-do' binds `calc-command-flags' fresh, so
one set during the minibuffer read would never be seen."
  (if keep-point
      (maf--preserve-point
        (calc-wrapper
         (calc-set-command-flag 'no-align)
         (calc-push-list (list (calc-record (calc-normalize val))))))
    (calc-wrapper
     (calc-push-list (list (calc-record (calc-normalize val)))))))

(defvar maf--digit-value nil
  "The number a contextual digit entry read, for `maf--digit-apply'.
Bound around the call by `maf-digit-start'.")

(maf-defcmd maf--digit-apply (expr _arg commit)
  "Commit `maf--digit-value' contextually at point.
The commit half of `maf-digit-start': a numeric leaf is replaced by the
entered number; a relation under point gets both sides multiplied by
it; any other sub-formula is multiplied, number on the left. Products
are built literally — nothing is normalized, so 5 on (a + b) gives
5 (a + b) without distributing."
  :arity unary
  :prefix "dgt"
  :map -1
  (commit (cond
           ((Math-numberp expr) maf--digit-value)
           ((maf--relation-p expr)
            (list (car expr)
                  (list '* maf--digit-value (nth 1 expr))
                  (list '* maf--digit-value (nth 2 expr))))
           (t (list '* maf--digit-value expr)))))

(defun maf-digit-start ()
  "Start a numeric entry, committed by the key that ends it.

  12| x + 3     5 SPC  =>  5 x + 3        (numeric leaf: replaced)
  x| + 3        5 SPC  =>  5 x + 3        (sub-formula: multiplied)
  2 + (a| + b)  5 SPC  =>  2 + 5 (a + b)  (literal: no distributing)

RET pushes the number onto the stack, exactly as in plain calc,
wherever point is. SPC is the contextual commit: on a sub-formula the
entered number replaces it when it is a numeric leaf and multiplies it
otherwise, number on the left and the product built literally; on a
relation node it multiplies both sides. The split is the same one maf
draws out in the stack, where SPC is the edit key and RET the push.

Away from a sub-formula there is nothing to edit and SPC pushes too —
at home, in the line prefix, at EOL, in algebraic mode, for entries
that escape to algebraic, and for interval entry (..), whose
incomplete-object flow is inseparable from the stack.

The entry minibuffer is calc's own (`calc-digit-map'), so the in-entry
keys — _, :, @, #, .. — work unchanged; only where the result lands
differs. The exceptions are the keys maf takes in that map: `;' as the
fraction colon, `n' and `P' for a multiple of pi, `e' to equate with
the number entered, SPC to commit it into the formula at point, and
`j' to jump to the entry it names."
  (interactive)
  ;; Where point stands now, for a `j' completion to mark and to jump
  ;; from; the calc-side completion parks point at home before the jump
  ;; runs. Nothing is committed on that path, so the buffer — and this
  ;; position with it — is unchanged when it is used.
  (setq maf--digit-jump-origin (point)
        ;; Cleared before the read, so a level or a flag left over from
        ;; an entry that never finished cannot carry into this one.
        maf--digit-jump-level nil
        maf--digit-contextual nil
        maf--digit-keep-point nil)
  (if (or calc-algebraic-mode
          (and (> calc-number-radix 14) (eq last-command-event ?e))
          (not (maf--at-subexpr-p)))
      ;; calc's own entry pushes on top; S-<return> (set during the read)
      ;; then relocates that push just below where point was.
      (let ((size0 (calc-stack-size)))
        (call-interactively #'calcDigit-start)
        ;; This path only pushes, and C-<return>'s no-align reached the
        ;; live `calc-do' from inside the read: neither flag has
        ;; anything left to say, and neither may outlive the entry.
        (setq maf--digit-contextual nil
              maf--digit-keep-point nil)
        (let ((below maf--digit-below-level))
          (setq maf--digit-below-level nil)
          (when (and below (> (calc-stack-size) size0))
            (maf--digit-relocate-below below))))
    ;; The read half of `calcDigit-start', verbatim: same prompt, map,
    ;; and dynamic state, so every in-entry key behaves identically.
    ;; Reading happens before any calc state is touched — C-g aborts
    ;; with nothing to unwind.
    (let* ((calc-digit-value nil)
           (calc-prev-char last-command-event)
           (calc-prev-prev-char nil)
           (calc-buffer (current-buffer))
           (buf (let ((old-esc (lookup-key global-map "\e")))
                  (unwind-protect
                      (progn
                        (define-key global-map "\e" nil)
                        (read-from-minibuffer
                         "Calc: " (calc-digit-start-entry) calc-digit-map))
                    (define-key global-map "\e" old-esc))))
           (val (or calc-digit-value (math-read-number buf)))
           ;; S-<return>'s target level, and C-<return>'s hold on point,
           ;; captured and cleared before the cond so a stale flag never
           ;; carries to the next entry.
           (below (prog1 maf--digit-below-level
                    (setq maf--digit-below-level nil)))
           (keep-point (prog1 maf--digit-keep-point
                         (setq maf--digit-keep-point nil))))
      (cond
       ;; S-<return>: add the number as a new entry, not a contextual
       ;; edit. Push it, then roll it just below the entry point was on.
       ((and below val (not (stringp val)) (not (eq calc-prev-char 'dots)))
        (maf--digit-push val nil)
        (maf--digit-relocate-below below))
       ;; .. switched to interval entry: replicate calc's tail (push
       ;; the endpoint, hand off to the incomplete-interval machinery).
       ((eq calc-prev-char 'dots)
        (calc-wrapper
         (when val
           (calc-push-list (list (calc-record (calc-normalize val)))))
         (require 'calc-ext)
         (calc-dots)))
       ;; Entry escaped to algebraic (' or an operator character):
       ;; plain algebraic entry, as in calc.
       ((stringp val) (calc-wrapper (calc-alg-entry val)))
       ;; Empty or unreadable entry: nothing to commit.
       ((null val) nil)
       ;; SPC (or the `n' that stands for it): the number is an edit of
       ;; the sub-formula point is on, not a value for the stack.
       (maf--digit-contextual
        (unwind-protect
            (let ((maf--digit-value (math-normalize val)))
              (maf--digit-apply))
          ;; The contextual commit is a complete edit of its own, not
          ;; an arg push: a command key that terminated the entry
          ;; must not fold this edit into its undo group.
          (setq maf--digit-entry-handoff nil)))
       ;; A command key terminated the entry (2 +): the number is that
       ;; command's arg, not an edit here. Push it, keeping point on the
       ;; sub-formula the command should resolve (this path only runs at
       ;; a subexpr, never at home), and leave `maf--digit-entry-handoff'
       ;; set so the command folds the push into its undo group.
       (maf--digit-entry-handoff (maf--digit-push val t))
       ;; RET: push, exactly as plain calc does, point homing after it
       ;; with a mark left behind. C-<return> is the same push holding
       ;; point where it stands.
       (t (maf--digit-push val keep-point)))))
  ;; A `j' completion committed nothing on either path above; all it
  ;; left is the level to travel to.
  (maf--digit-take-jump))

(provide 'maf-minibuffer)
