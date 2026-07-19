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

;;; Stack persistence (persist.el)

(defcustom maf-stack-directory (locate-user-emacs-file "maf-stacks/")
  "Directory holding the per-session calc stack save files."
  :type 'directory
  :group 'maf)

(defcustom maf-stack-save-interval 60
  "Idle seconds between stack autosaves.
Takes effect when `maf-stack-persistence-mode' turns on; after
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
