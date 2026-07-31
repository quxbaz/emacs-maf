;; -*- lexical-binding: t; -*-
;;
;; modules/maf-selplus.el
;;
;; Selection extras: the home for everything that makes calc's
;; sub-formula selections easier to live with, beyond the commands that
;; act on a selection (those are core — see maf-sel.el and stack.el).
;;
;; What is here now is the state badge. A selection is a mode in all but
;; name — while one is active, keys act on the selected sub-formula
;; rather than on the entry — but calc gives it no indicator, so it is
;; easy to forget one is standing. `maf-selplus-mode' puts a badge in
;; the calc buffer's header line for as long as any entry carries a
;; selection, with the gesture that clears it, in the shape maf-edit
;; uses for its own editing banner.
;;
;; The calc buffer's header line is not free — calc keeps its own
;; centered "Emacs Calculator Mode" banner there, rebuilt from scratch
;; on every `calc-refresh'. The badge takes the line outright for as
;; long as the selection stands, as maf-edit's banner does: a mode
;; indicator that shares its line with a decorative banner reads as
;; part of the decoration, and the banner says nothing that matters
;; while a selection is redirecting every key. The displaced line is
;; kept and put back when the selection clears. During a maf-edit
;; session the header line is that mode's banner, and this module keeps
;; its hands off it entirely.
;;
;; The module toggle is `maf-use-selplus-mode', which turns the
;; buffer-local mode on in every calc buffer and registers with the
;; module system as `maf-selplus' (see `maf-modules').

(require 'calc)
(require 'seq)
(require 'maf-sel)           ; maf--sel-any-p
(require 'maf-conf "conf")   ; the `maf' customize group

(defface maf-selplus-badge
  '((t :inherit warning :inverse-video t))
  "Face for the selection badge in the calc header line.
The same colors as maf-edit's banner badge — `warning' under inverse
video, a filled box — so the two mode indicators read as one thing in
two states rather than as two unrelated decorations. The badge's text
says which state it is."
  :group 'maf)

(defcustom maf-selplus-badge-label " selection "
  "Text of the selection badge, shown in `maf-selplus-badge' face.
The surrounding spaces are the box's padding — inverse video colors
them in."
  :type 'string
  :group 'maf)

(defvar-local maf-selplus--header nil
  "The header line this module put up, or nil if it has none up.
Compared with `header-line-format' by `eq' to tell a badged line of
ours from one that arrived some other way — notably calc's own banner,
which `calc-refresh' rebuilds as a fresh string every time.")

(defvar-local maf-selplus--base nil
  "The header line the badge displaced, put back when it comes down.
Calc's banner, normally; nil in a buffer that has no header line of its
own.")

;; Looked up rather than called, and quoted rather than sharp-quoted:
;; the commands live in the maf core, which a module does not require.
(defvar maf-selplus--clear-commands
  '(maf-dup-or-clear-selections maf-clear-selections)
  "Commands whose key the badge offers as the way out of a selection.
The first one bound in the live keymaps wins; `maf-dup-or-clear-selections'
is what maf puts on RET, `maf-clear-selections' the plain clear it calls.")

(defun maf-selplus--clear-key ()
  "Key description for the gesture that clears the selections, or nil.
Found in the live keymaps rather than named outright, so the badge
follows a rebinding, and says nothing at all when no key reaches the
command — as when maf-mode is off in this buffer."
  (let ((key (seq-some (lambda (cmd) (where-is-internal cmd nil t))
                       maf-selplus--clear-commands)))
    (and key (key-description key))))

(defun maf-selplus--header-line ()
  "Header line to fly while a selection is active: badge plus the way out.
The shape maf-edit's own banner uses — a filled box naming the state,
then the gesture that leaves it."
  (let ((key (maf-selplus--clear-key)))
    (concat (propertize maf-selplus-badge-label 'face 'maf-selplus-badge)
            (when key
              (concat " " (propertize key 'face 'help-key-binding)
                      " clear")))))

(defun maf-selplus--update ()
  "Put the selection badge up or take it down, to match calc's state.
Runs on `post-command-hook': a selection only ever comes and goes by a
command. Errors are swallowed so a bad calc state cannot get the hook
function disabled.

A header line that is not the one this module last installed is taken
to be the buffer's own and remembered as the line to put back — which
is how the badge survives `calc-refresh' rebuilding the banner under
it, and still hands back a current banner when the selection clears.

Does nothing at all while `maf-edit-mode' is on: that mode flies its own
banner in the header line, saving and restoring what was there, and a
badge written over it would be both a nuisance and short-lived."
  (unless (bound-and-true-p maf-edit-mode)
    (ignore-errors
      (let ((ours (and maf-selplus--header
                       (eq header-line-format maf-selplus--header))))
        (unless ours
          (setq maf-selplus--base header-line-format
                maf-selplus--header nil))
        (if (maf--sel-any-p)
            (let ((line (maf-selplus--header-line)))
              ;; Re-installing an equal line would be a no-op on screen
              ;; but still mark the line for redisplay, every command.
              (unless (and ours (equal line maf-selplus--header))
                (setq maf-selplus--header line
                      header-line-format line)))
          (when ours
            (setq header-line-format maf-selplus--base
                  maf-selplus--header nil)))))))

(defun maf-selplus--hide ()
  "Take the badge down, restoring the header line it displaced."
  (when (and maf-selplus--header
             (eq header-line-format maf-selplus--header))
    (setq header-line-format maf-selplus--base))
  (setq maf-selplus--header nil
        maf-selplus--base nil))

;;;###autoload
(define-minor-mode maf-selplus-mode
  "Selection extras for a calc buffer.
While any stack entry carries a selection, a badge in the header line
says so, along with the key that clears it — calc itself gives the
state no indicator, and a forgotten selection quietly redirects every
command that follows onto the selected sub-formula.

The badge takes the header line for itself, displacing the line the
buffer already has — calc's own banner — which comes back when the
selection clears. While a maf-edit session is up the header line is
that mode's banner, and the badge stays away."
  :lighter " sel+"
  :group 'maf
  (if maf-selplus-mode
      (progn
        (add-hook 'post-command-hook #'maf-selplus--update nil t)
        (maf-selplus--update))
    (remove-hook 'post-command-hook #'maf-selplus--update t)
    (maf-selplus--hide)))

;;; The module

(defun maf-selplus--turn-on ()
  "Enable `maf-selplus-mode' in the current buffer if it is a calc buffer.
The per-buffer arm of `maf-use-selplus-mode'."
  (when (derived-mode-p 'calc-mode)
    (maf-selplus-mode 1)))

;;;###autoload
(define-globalized-minor-mode maf-use-selplus-mode
  maf-selplus-mode maf-selplus--turn-on
  :group 'maf)

;; Register with the module system when it is present; the mode above
;; works on its own without it.
(when (require 'maf-module nil t)
  (maf-register-module 'maf-selplus #'maf-use-selplus-mode
                       "Badge in the calc header line while a selection is active."))

(provide 'maf-selplus)
