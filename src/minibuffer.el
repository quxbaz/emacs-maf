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

(defvar maf-mode)  ; defined in maf.el; declared for the byte compiler

;; Dynamic state of calc's digit-entry minibuffer commands. calc.el
;; declares these without values, which doesn't make them special here;
;; re-declare so let-binding them in `maf-digit-start' is dynamic.
(defvar calc-digit-value)
(defvar calc-prev-char)
(defvar calc-prev-prev-char)

(defun maf--digit-entry-keep-point ()
  "Suppress stack alignment when a command key completes digit entry.
Finishing a digit entry normally parks point at home, destroying the
context the terminating command should resolve: with point on an entry,
typing 1 + would add 1 to the top of the stack instead of that entry.
Setting the `no-align' flag makes the entry's push leave point where it
was, and the entry's row survives the push (only its level number
changes), so the command that follows targets the position the user
was on. Point still goes home when it already was there or when RET
or SPC completes the entry. With `maf-mode' off in the calc buffer
the whole function is a no-op — plain calc behavior, no maf state
touched."
  (when (maf--with-calc-buffer maf-mode)
    (let ((command-key (not (memq last-command-event '(?\r ?\s)))))
      ;; Record how this entry completed on every run (self-clearing):
      ;; a command-key termination marks the entry's push and the command
      ;; it dispatches as one gesture for undo amalgamation.
      (setq maf--digit-entry-handoff command-key)
      (when (and (not (maf--at-home-p))
                 command-key)
        (calc-set-command-flag 'no-align)))))

(advice-add 'calcDigit-nondigit :before #'maf--digit-entry-keep-point)

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
      (call-interactively #'calcDigit-start)
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
           (val (or calc-digit-value (math-read-number buf))))
      (cond
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
