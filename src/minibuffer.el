;; -*- lexical-binding: t; -*-
;;
;; minibuffer.el
;;
;; Digit-entry integration: keep point in place when a command key
;; terminates minibuffer digit entry, so the command still resolves the
;; position the user was on.

(require 'calc)
(require 'maf-lib)

(defvar maf-mode)  ; defined in maf.el; declared for the byte compiler

(defun maf--digit-entry-keep-point ()
  "Suppress stack alignment when a command key completes digit entry.
Finishing a digit entry normally parks point at home, destroying the
context the terminating command should resolve: with point on an entry,
typing 1 + would add 1 to the top of the stack instead of that entry.
Setting the `no-align' flag makes the entry's push leave point where it
was, and the entry's row survives the push (only its level number
changes), so the command that follows targets the position the user
was on. Point still goes home when it already was there, when RET or
SPC completes the entry, or when `maf-mode' is off in the calc buffer."
  (let ((command-key (not (memq last-command-event '(?\r ?\s)))))
    ;; Record how this entry completed on every run (self-clearing):
    ;; a command-key termination marks the entry's push and the command
    ;; it dispatches as one gesture for undo amalgamation.
    (setq maf--digit-entry-handoff command-key)
    (when (and (maf--with-calc-buffer maf-mode)
               (not (maf--at-home-p))
               command-key)
      (calc-set-command-flag 'no-align))))

(advice-add 'calcDigit-nondigit :before #'maf--digit-entry-keep-point)

(provide 'maf-minibuffer)
