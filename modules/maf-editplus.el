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
;; What is here now is TAB, the escape gesture. Typing a formula runs
;; forward past closing delimiters constantly — sqrt(x^2+1), f(g(x)) —
;; and reaching the far side of one by hand means either counting
;; right-arrows or typing a closer that `electric-pair-mode' has already
;; put there. TAB jumps point past the delimiter that closes the group
;; it stands in, once per press, so nested groups peel off one level at
;; a time and a formula can be typed left to right without ever moving
;; point backwards.
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

(defun maf-editplus--entry-bounds ()
  "Bounds of the maf-edit entry point is in, as a cons of positions.
Falls back to the current line for a point no entry covers — the home
line, or a line not yet adopted by the repair pass.

Entry overlays are rear-advancing and end just before the newline, so
`overlays-at' misses one when point rests at its very end — the usual
place to press an escape key. Hence the widened scan and the explicit
inclusive containment test."
  (let ((o (seq-find
            (lambda (ov)
              (and (overlay-get ov 'maf-edit-entry)
                   (<= (overlay-start ov) (point))
                   (<= (point) (overlay-end ov))))
            (overlays-in (max (point-min) (1- (point)))
                         (min (point-max) (1+ (point)))))))
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

;;; The module

(define-minor-mode maf-use-editplus-mode
  "Global minor mode installing the in-session keys into `maf-edit-mode-map'.
Enabled, TAB runs `maf-editplus-escape-group' while a maf-edit session
is up — point jumps past the delimiter that closes the group it is in,
one level per press. Disabled, the key cedes back to whatever the
global map does with it (`indent-for-tab-command', which has nothing to
indent in an edited stack).

This is the `maf-editplus' module (see `maf-modules'). The keys only
live in maf-edit's own map, so they are inert unless a session is
running, and the module is a no-op for anyone not using maf-edit."
  :global t
  :group 'maf
  (if maf-use-editplus-mode
      (define-key maf-edit-mode-map (kbd "TAB") #'maf-editplus-escape-group)
    (define-key maf-edit-mode-map (kbd "TAB") nil)))

;; Register with the module system when it is present; the mode above
;; works on its own without it.
(when (require 'maf-module nil t)
  (maf-register-module 'maf-editplus #'maf-use-editplus-mode
                       "In-session keys for maf-edit (TAB escapes a group)."))

(provide 'maf-editplus)
