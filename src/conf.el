;; -*- lexical-binding: t; -*-
;;
;; conf.el
;;
;; maf's configurable settings, collected in one place: the customize
;; group and every user option. Feature code requires this and reads
;; the options; nothing here has any effect on its own.

(defgroup maf nil
  "Math-Algebra-Formulas: an alternative UX for Emacs Calc."
  :group 'calc
  :prefix "maf-")

;;; Contextual commands (stack.el)

(defcustom maf-toggle-op-pairs
  '((+ . -)
    (* . /)
    (calcFunc-ln . calcFunc-exp)
    (calcFunc-log . ^)
    (calcFunc-lt . calcFunc-gt)
    (calcFunc-leq . calcFunc-geq)
    (calcFunc-eq . calcFunc-neq)
    ;; Trig pairs with its inverse, like ln/exp. Upstream has no
    ;; arcsec/arccsc/arccot, so sec/csc/cot stay unpaired.
    (calcFunc-sin . calcFunc-arcsin)
    (calcFunc-cos . calcFunc-arccos)
    (calcFunc-tan . calcFunc-arctan)
    (calcFunc-sinh . calcFunc-arcsinh)
    (calcFunc-cosh . calcFunc-arccosh)
    (calcFunc-tanh . calcFunc-arctanh))
  "Operator pairs toggled by `mafcmd-toggle-op'.
Each pair toggles in both directions. Operands stay in place; only the
operator changes, so log(a, b) toggles to a^b and back, and a < b flips
to a > b without touching either side. Operators are calc's internal
symbols: +, -, *, /, ^, neg, or a calcFunc- name."
  :type '(alist :key-type symbol :value-type symbol)
  :group 'maf)

;;; Modules (maf-module.el)

(defcustom maf-modules '(maf-timeline maf-hl maf-edit maf-preview)
  "Names of the maf feature modules to enable.
Each major feature that stands apart from the contextual-command core
is an optional module (see maf-module.el); this list names the ones
that should be active. Setting it through Customize applies the change
at once — enabling newly-listed modules and disabling removed ones.
Set from Lisp, call `maf-modules-apply' to take effect."
  :type '(set (const :tag "Stack timeline" maf-timeline)
              (const :tag "Sub-formula highlighting" maf-hl)
              (const :tag "Stack persistence" maf-persist)
              (const :tag "In-place editing" maf-edit)
              (const :tag "Big preview of active entry" maf-preview))
  :set (lambda (sym val)
         (set-default sym val)
         (when (fboundp 'maf-modules-apply) (maf-modules-apply)))
  :group 'maf)

;;; Stack timeline (modules/maf-timeline.el)

(defcustom maf-timeline-size 100
  "Maximum number of stack states kept in the timeline.
Recording past the limit drops the oldest states. A state shares all
formula structure with the stack it was taken from, so even a large
timeline stays cheap."
  :type 'natnum
  :group 'maf)

;;; Stack persistence (modules/maf-persist.el)

(defcustom maf-stack-directory (locate-user-emacs-file "maf-stacks/")
  "Directory holding the per-session calc stack save files."
  :type 'directory
  :group 'maf)

(defcustom maf-stack-save-interval 60
  "Idle seconds between stack autosaves.
Takes effect when `maf-persist-mode' turns on; after
changing it, toggle the mode to restart the timer on the new
interval."
  :type 'natnum
  :group 'maf)

(defcustom maf-stack-session-name nil
  "Explicit session name for stack persistence, a string.
Nil derives one: `server-name' when this session runs a server, else
\"default\". Either way the name uniquifies when a live session
already holds it."
  :type '(choice (const :tag "Derive from server-name" nil) string)
  :group 'maf)

(provide 'maf-conf)
