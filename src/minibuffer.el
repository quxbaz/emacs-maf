;; -*- lexical-binding: t; -*-
;;
;; minibuffer.el
;;
;; Digit-entry integration: contextual digit entry (`maf-digit-start'),
;; and keeping point in place when a command key or C-g terminates
;; minibuffer digit entry, so the command still resolves the position
;; the user was on.

(require 'calc)
(require 'maf-lib)
(require 'maf-defcmd)

;; These live in lazily-loaded calc modules; calc-ext's autoload registry
;; resolves them at runtime, but the byte compiler needs declarations.
(declare-function calc-alg-entry "calc-aent")
(declare-function calc-dots "calc-incom")
(declare-function calcDigit-nondigit "calc")
(declare-function calc-algebraic-entry "calc-aent")
(declare-function calc-roll-down "calc-misc")
(declare-function calc-cursor-stack-index "calc")
(declare-function calc-record "calc")
(declare-function calc-push-list "calc")

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

(defun maf--digit-entry-keep-point ()
  "Keep or mark point when a digit entry completes, by how it completed.
Finishing a digit entry normally parks point at home, destroying the
context the terminating command should resolve: with point on an entry,
typing 1 + would add 1 to the top of the stack instead of that entry.

A command-key termination (1 +) sets the `no-align' flag so the push
leaves point where it was — the entry's row survives, only its level
number changes — and the command that follows targets that position. A
sub-formula RET commits contextually and keeps point too; C-<return> is
the explicit keep-point commit.

A plain RET or SPC at a margin, though, does park point home. Before it
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
       ;; A sub-formula RET commits contextually and keeps point.
       ((maf--at-subexpr-p))
       ;; RET/SPC at a margin pushes and homes point: mark the origin so
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

(defun maf-digit-commit-here ()
  "Commit the digit entry like RET, but keep point instead of homing.
The keep-point sibling of RET in the digit-entry minibuffer, on
C-<return>: the number commits exactly where RET would put it — pushed
onto the stack from a margin, applied to the sub-formula under point on a
subexpr — but point stays on the entry it was on rather than dropping to
the home line. At home there is nowhere to stay, so it matches RET. With
`maf-mode' off in the calc buffer, plain calc behavior.

`calcDigit-nondigit' is calc's own terminator; binding `last-command-event'
to RET around it takes its RET path — commit, no command re-dispatch (so
this never triggers `maf-edit-add-entry', C-<return>'s stack-mode
binding) — while `no-align', set first, is what carries point through the
push."
  (interactive)
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

(define-key calc-digit-map (kbd "S-<return>") #'maf-digit-commit-below)

(defun maf--digit-relocate-below (m)
  "Roll the just-pushed top entry down to level M, point resting on it.
The number was pushed on top; move it just below where point was — level
M, bumping the entry that was there up one — and leave point at its
margin. M of 1 (the top entry, or home) needs no roll.

The roll is folded into the push's undo group so a single `maf-undo'
reverts the whole S-<return> gesture rather than just the roll."
  (when (> m 1)
    (calc-wrapper (calc-roll-down m))
    (when (cdr calc-undo-list)
      (setq calc-undo-list (cons (append (car calc-undo-list)
                                         (cadr calc-undo-list))
                                 (cddr calc-undo-list)))))
  (calc-cursor-stack-index m)
  (end-of-line))

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
  "Start a numeric entry, committed contextually by point.

  12| x + 3     5 RET  =>  5 x + 3        (numeric leaf: replaced)
  x| + 3        5 RET  =>  5 x + 3        (sub-formula: multiplied)
  2 + (a| + b)  5 RET  =>  2 + 5 (a + b)  (literal: no distributing)

With point on a sub-formula, the entered number replaces it when it
is a numeric leaf and multiplies it otherwise, number on the left and
the product built literally; on a relation node it multiplies both
sides. At home, in the line prefix, or at EOL the number is pushed
onto the stack, exactly as in plain calc — as it is in algebraic
mode, for entries that escape to algebraic, and for interval entry
(..), whose incomplete-object flow is inseparable from the stack.

The entry minibuffer is calc's own (`calc-digit-map'), so the
in-entry keys — e, _, :, n, @ — work unchanged; only where the result
lands differs."
  (interactive)
  (if (or calc-algebraic-mode
          (and (> calc-number-radix 14) (eq last-command-event ?e))
          (not (maf--at-subexpr-p)))
      ;; calc's own entry pushes on top; S-<return> (set during the read)
      ;; then relocates that push just below where point was.
      (let ((size0 (calc-stack-size)))
        (call-interactively #'calcDigit-start)
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
           ;; S-<return>'s target level, captured and cleared before the
           ;; cond so a stale flag never carries to the next entry.
           (below (prog1 maf--digit-below-level
                    (setq maf--digit-below-level nil))))
      (cond
       ;; S-<return>: add the number as a new entry, not a contextual
       ;; edit. Push it, then roll it just below the entry point was on.
       ((and below val (not (stringp val)) (not (eq calc-prev-char 'dots)))
        (calc-wrapper (calc-push-list (list (calc-record (calc-normalize val)))))
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
       ;; A command key terminated the entry (2 +): the number is that
       ;; command's arg, not an edit here. Push it plainly — calc's own
       ;; digit-entry tail — leaving `maf--digit-entry-handoff' set so
       ;; the command folds the push into its undo group. no-align
       ;; keeps point on the sub-formula the command should resolve
       ;; (this path only runs at a subexpr, never at home).
       (maf--digit-entry-handoff
        ;; no-align only stops the home jump; the push's renumbering
        ;; still disturbs point, and the command about to dispatch
        ;; resolves whatever position it finds — preserve it for real.
        (maf--preserve-point
          (calc-wrapper
           (calc-set-command-flag 'no-align)
           (calc-push-list (list (calc-record (calc-normalize val)))))))
       (t (unwind-protect
              (let ((maf--digit-value (math-normalize val)))
                (maf--digit-apply))
            ;; The contextual commit is a complete edit of its own, not
            ;; an arg push: a command key that terminated the entry
            ;; must not fold this edit into its undo group.
            (setq maf--digit-entry-handoff nil)))))))

(provide 'maf-minibuffer)
