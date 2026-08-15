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

(require 'dial)
(require 'maf-conf "conf")

(defvar maf-module-registry nil
  "Alist of (NAME MODE DESCRIPTION) for registered modules.
NAME is a symbol naming the module; MODE is its global minor-mode
function, which is also the variable holding the mode's state;
DESCRIPTION is a one-line string shown in the module menu (see
`maf-list-modules'), or nil.")

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
         (when (symbol-value (cadr entry))
           (push (car entry) active)))))))

(defun maf-module--custom-type ()
  "Build a Customize `:type' for `maf-modules' from `maf-module-registry'.
A checkbox per registered module, labelled with the name to set from
Lisp and the description the module gives for itself. Sorted by name:
`maf-module-registry' is in reverse registration order, an artifact of
the load order in maf.el that should not decide how the option reads."
  `(set ,@(mapcar (lambda (entry)
                    (let ((name (car entry))
                          (desc (caddr entry)))
                      `(const :tag ,(if desc
                                        (format "%s — %s" name desc)
                                      (symbol-name name))
                              ,name)))
                  (sort (copy-sequence maf-module-registry)
                        (lambda (a b) (string< (car a) (car b)))))))

(defun maf-register-module (name mode &optional description)
  "Register module NAME with its global minor mode MODE.
DESCRIPTION is a one-line string the module gives for itself, shown in
the module menu (see `maf-list-modules') and on the module's checkbox
in Customize.

Records the entry in `maf-module-registry' and adds
`maf-module--reconcile' to MODE's hook, so toggling MODE keeps
`maf-modules' current. Re-registering a NAME replaces the earlier
entry, and re-adding the shared reconcile function to the hook is
idempotent, so reloading a module file re-registers it cleanly.

Also refreshes `maf-modules' Customize type from the registry, so the
option offers exactly the modules that have registered — see
`maf-module--custom-type'. Registering is the only thing that changes
the registry, so recomputing here keeps the type current without
conf.el naming a single module."
  (setf (alist-get name maf-module-registry) (list mode description))
  (put 'maf-modules 'custom-type (maf-module--custom-type))
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
      (funcall (cadr entry) (if (memq (car entry) maf-modules) 1 -1)))))

;;; Module menu

;; A dial buffer (pkg/dial) over the registry: each module is an
;; on/off row whose setters call the mode function directly, so
;; `maf-module--reconcile' keeps `maf-modules' in step just as an
;; `M-x' toggle would. The description a module gives for itself is
;; the row's :doc, echoed as point rests on it — dial's convention,
;; where the old menu spent a column on it.

(defun maf-module--state (name)
  "Non-nil when module NAME's mode is on."
  (let ((mode (car (alist-get name maf-module-registry))))
    (and (boundp mode) (symbol-value mode) t)))

(defun maf-module--items ()
  "Compile `maf-module-registry' into dial items, sorted by name.
The registry is in reverse registration order, an artifact of the load
order in maf.el that should not decide how the menu reads."
  (mapcar (lambda (entry)
            (pcase-let ((`(,name ,mode ,description) entry))
              (cons name
                    (list :group "Modules"
                          :label (symbol-name name)
                          :doc description
                          :values `((t   "on"  (,mode 1))
                                    (nil "off" (,mode -1)))))))
          (sort (copy-sequence maf-module-registry)
                (lambda (a b) (string< (car a) (car b))))))

(defvar maf-module--controls nil
  "The module menu's controls line.
Dial's default names controls this buffer has no use for — resetting,
filtering by changed, a save — so the line is written out: flipping a
module is the whole interface.")

;; Set outside the defvar so a reload applies edits to the list.
(setq maf-module--controls
      '(((dial-next-value dial-previous-value) "toggle" "TAB")
        (dial-refresh "refresh")
        (quit-window "quit")))

;;;###autoload
(defun maf-list-modules ()
  "Show the maf module toggle buffer in another window and select it.
Each registered module is a row; TAB flips the one on the current line,
and its description echoes as point rests on it (see `dial-mode'). The
buffer is dial's; this command supplies it the registry."
  (interactive)
  (dial-open "*maf-modules*" (maf-module--items)
             :name "maf-modules"
             :controls maf-module--controls
             :raw #'maf-module--state))

(provide 'maf-module)
