;; -*- lexical-binding: t; -*-
;;
;; maf-module.el
;;
;; The module system. Major maf features that stand apart from the
;; contextual-command core — the stack timeline, sub-formula
;; highlighting, stack persistence, in-place editing — live as
;; optional modules under modules/, each toggled independently without
;; disturbing the core.
;;
;; A module is nothing but a global minor mode: it installs everything
;; it needs when enabled (hooks, advice, its own key bindings) and
;; removes it all when disabled, and it works on its own, `M-x'-toggled
;; like any other minor mode, whether or not this file is loaded.
;; "Module" is just our name for one of these modes.
;;
;; This file adds a thin registry on top. Loading a module file
;; registers its mode here under a short name; `maf-modules' (see
;; conf.el) lists the names that should be active. Two directions:
;;
;;  - On activation, `maf-modules-apply' drives the modes from the list
;;    — enabling the listed modules, disabling the rest.
;;  - When a mode is toggled directly, its hook runs
;;    `maf-module--reconcile', which writes the list back from live
;;    state, so `maf-modules' stays an accurate record of what is on.
;;
;; The registry hooks into the modes, never the reverse: a module's
;; mode body knows nothing of this file, so the feature is fully usable
;; with the registry absent — you just lose the list-driven management.

(require 'maf-conf "conf")

(defvar maf-module-registry nil
  "Alist of (NAME . MODE) for registered modules.
NAME is a symbol naming the module; MODE is its global minor-mode
function, which is also the variable holding the mode's state.")

(defvar maf-module--applying nil
  "Non-nil while `maf-modules-apply' is driving modes from `maf-modules'.
Suppresses `maf-module--reconcile' so applying the list does not turn
around and rewrite the list it is reading.")

(defun maf-module--reconcile ()
  "Set `maf-modules' from every registered module's live state.
Run from each module's mode hook, so toggling a module's minor mode
directly — \\[maf-use-hl-mode], say — keeps `maf-modules' an
accurate record of what is on. A no-op while `maf-modules-apply' runs,
which is itself driving the modes from the list.

Uses `set-default' rather than the Customize setter, so writing the
list back does not re-trigger `maf-modules-apply'."
  (unless maf-module--applying
    (set-default
     'maf-modules
     (let (active)
       (dolist (entry maf-module-registry (nreverse active))
         (when (symbol-value (cdr entry))
           (push (car entry) active)))))))

(defun maf-register-module (name mode)
  "Register module NAME with its global minor mode MODE.
Records NAME in `maf-module-registry' and adds `maf-module--reconcile'
to MODE's hook, so toggling MODE keeps `maf-modules' current.
Re-registering a NAME replaces the earlier entry, and re-adding the
shared reconcile function to the hook is idempotent, so reloading a
module file re-registers it cleanly."
  (setf (alist-get name maf-module-registry) mode)
  (add-hook (intern (concat (symbol-name mode) "-hook"))
            #'maf-module--reconcile))

(defun maf-modules-apply ()
  "Bring every registered module's state in line with `maf-modules'.
Enables the modules whose names appear in `maf-modules', disables the
rest. `maf-module--reconcile' is suppressed for the duration, so
applying the list does not rewrite it. A name in `maf-modules' whose
module has not been loaded yet is simply not in the registry, so it is
skipped until its file loads and the next apply enables it."
  (let ((maf-module--applying t))
    (dolist (entry maf-module-registry)
      (funcall (cdr entry) (if (memq (car entry) maf-modules) 1 -1)))))

(provide 'maf-module)
