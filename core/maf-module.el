;; -*- lexical-binding: t; -*-
;;
;; maf-module.el
;;
;; The module system. Major maf features that stand apart from the
;; contextual-command core — the stack history, sub-formula
;; highlighting, stack persistence, in-place editing — live as
;; optional modules under modules/, each toggled independently without
;; disturbing the core.
;;
;; A module is a global minor mode that installs everything it needs
;; when enabled (hooks, advice, its own key bindings) and removes it
;; all when disabled; loading the module file only defines the mode,
;; changing nothing until it is turned on. Each module registers its
;; toggle here under a short name. `maf-modules' (see conf.el) lists
;; the names that should be active, and `maf-modules-apply' brings the
;; live state in line with that list — enabling the listed modules,
;; disabling the rest.

(require 'maf-conf "conf")

(defvar maf-module-registry nil
  "Alist of (NAME . TOGGLE) for registered modules.
NAME is a symbol naming the module; TOGGLE is its global minor-mode
function, called with 1 to enable and -1 to disable.")

(defun maf-register-module (name toggle)
  "Register module NAME with TOGGLE, its minor-mode function.
Re-registering a NAME replaces the earlier toggle, so reloading a
module file re-registers it cleanly."
  (setf (alist-get name maf-module-registry) toggle))

(defun maf-modules-apply ()
  "Bring every registered module's state in line with `maf-modules'.
Enables the modules whose names appear in `maf-modules', disables the
rest. A name in `maf-modules' whose module has not been loaded yet is
simply not in the registry, so it is skipped until its file loads and
the next apply enables it."
  (dolist (entry maf-module-registry)
    (funcall (cdr entry) (if (memq (car entry) maf-modules) 1 -1))))

(provide 'maf-module)
