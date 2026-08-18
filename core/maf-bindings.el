;; -*- lexical-binding: t; -*-
;;
;; core/maf-bindings.el
;;
;; Binding profiles: the registry, the compiler, and the dispatcher
;; behind maf's key layout (docs/bindings.org). A *profile* is a named
;; key layout — calc, native, vim — over one shared base map of command
;; remaps. Declarations are data owned in whole sets, compiled into one
;; generated keymap per profile; the user's own maps sit above the
;; generated ones and are never written or rebuilt by maf.
;;
;; Lookup, per profile:
;;   1. the profile's user map, then `maf-common-user-map'
;;   2. enabled-module declarations   \  one compiled map,
;;   3. profile defaults minus         > modules written after
;;      suppressions                  /  defaults
;;   4. `maf-bindings-base-map' (remaps), the compiled map's parent
;;   5. calc's own map, by minor-mode order
;;
;; The built-in profiles are declared through this same public API from
;; src/bindings.el — no privileged path.

(require 'cl-lib)
(require 'seq)

(defvar maf-bindings-base-map (make-sparse-keymap)
  "The one map every profile inherits: audited command remaps only.
A remap claims no key, so nothing here can collide with a profile's
layout; a calc command with a maf sibling runs the sibling on whatever
key reaches it. Empty until the allowlist audit (docs/bindings.org).")

(defvar maf-common-user-map (make-sparse-keymap)
  "User bindings that apply in every profile.
Never written or rebuilt by maf. Outranked only by the active
profile's own user map.")

(defvar maf-bindings--profiles nil
  "Alist NAME -> plist of the registered profiles.
Keys: :map (the compiled keymap, identity stable across recompiles),
:user-map (symbol of the profile's user map variable), :defaults
\(alist KEY-STRING -> COMMAND, declaration order), :suppressed (list of
KEY-STRING). Defaults are replaced as a set by `maf-bindings-defprofile'
\(reload safety); suppressions are user state and survive it.")

(defvar maf-bindings--modules nil
  "Alist MODULE -> plist of module key declarations.
Keys: :mode (the module's global minor mode variable, read to decide
whether its keys compile in), :keys (list of (PROFILES KEY COMMAND)).
Replaced as a set per module by `maf-bindings-module-keys'.")

(defvar maf-bindings--active nil
  "Non-nil once the dispatcher owns `maf-mode-map'.
Set by the maf-bindings module; while nil, compiles are just data.")

(defun maf-bindings--profile (name)
  "Return NAME's registry entry, or signal."
  (or (cdr (assq name maf-bindings--profiles))
      (error "maf-bindings: no profile named `%s'" name)))

(defun maf-bindings--user-map-symbol (name)
  "The generated user-map variable name for profile NAME.
maf-<name>-user-map: short, since it is what users type."
  (intern (format "maf-%s-user-map" name)))

(defun maf-bindings--clear-keymap (map)
  "Remove MAP's own entries, keeping its identity and its parent."
  (setcdr map (keymap-parent map)))

(defun maf-bindings-defprofile (name &rest opts)
  "Register profile NAME, replacing its default declarations as a set.
OPTS may carry :clone SOURCE, seeding the defaults with a copy of
SOURCE's current default declarations — a snapshot, not a link; later
changes to SOURCE do not flow. The profile's user map variable
\(maf-NAME-user-map) is created if absent and never touched again, and
its suppression list survives redefinition: both are user state, not
declarations. Returns NAME."
  (let* ((clone (plist-get opts :clone))
         (seed (and clone (copy-alist (plist-get (maf-bindings--profile clone)
                                                 :defaults))))
         (entry (assq name maf-bindings--profiles))
         (user-sym (maf-bindings--user-map-symbol name)))
    (unless (boundp user-sym)
      (set user-sym (make-sparse-keymap)))
    (if entry
        (setcdr entry (plist-put (cdr entry) :defaults seed))
      (let ((map (make-sparse-keymap)))
        (set-keymap-parent map maf-bindings-base-map)
        (push (cons name (list :map map :user-map user-sym
                               :defaults seed :suppressed nil))
              maf-bindings--profiles)))
    name))

(defun maf-bindings--forget (name)
  "Drop profile NAME from the registry. For tests; user maps remain."
  (setq maf-bindings--profiles (assq-delete-all name maf-bindings--profiles)))

(defun maf-bindings-define (profiles key command)
  "Declare KEY -> COMMAND as a default of each profile in PROFILES.
PROFILES is a list of registered profile names, or `:all' for every
profile registered now. KEY is a `kbd' string. A later declaration of
the same key in the same profile replaces the earlier — within one
owner, last say wins; across owners the compiler refuses instead."
  (dolist (name (if (eq profiles :all) (mapcar #'car maf-bindings--profiles)
                  profiles))
    (let* ((entry (maf-bindings--profile name))
           (cell (assoc key (plist-get entry :defaults))))
      (if cell
          (setcdr cell command)
        (plist-put entry :defaults
                   (append (plist-get entry :defaults)
                           (list (cons key command))))))))

(defun maf-bindings-module-keys (module mode-var specs)
  "Declare MODULE's keys, replacing its previous set.
MODE-VAR is the module's global minor mode variable; the keys compile
in only while it is non-nil, so a toggle is a recompile away and no
map mutation can erase a user's key. SPECS is a list of
\(PROFILES KEY COMMAND) as in `maf-bindings-define'."
  (let ((entry (assq module maf-bindings--modules))
        (val (list :mode mode-var :keys specs)))
    (if entry (setcdr entry val)
      (push (cons module val) maf-bindings--modules))
    (maf-bindings--refresh)))

(defun maf-bindings-unbind (profile key)
  "Suppress KEY in PROFILE: generated declarations for it are omitted.
The one intent a keymap entry cannot state. KEY falls through to
calc's layout (base remaps still apply — a calc command with a maf
sibling still runs the sibling). Suppressing a prefix key omits every
generated key beneath it. `maf-bindings-restore' is the inverse."
  (let ((entry (maf-bindings--profile profile)))
    (unless (member key (plist-get entry :suppressed))
      (plist-put entry :suppressed (cons key (plist-get entry :suppressed)))))
  (maf-bindings--refresh))

(defun maf-bindings-restore (profile key)
  "Drop KEY's suppression in PROFILE; the generated default returns."
  (let ((entry (maf-bindings--profile profile)))
    (plist-put entry :suppressed (remove key (plist-get entry :suppressed))))
  (maf-bindings--refresh))

;;; Compilation

(defun maf-bindings--suppressed-p (key suppressed)
  "Non-nil when kbd-string KEY is SUPPRESSED, itself or under a prefix."
  (let ((kv (kbd key)))
    (seq-some (lambda (s)
                (let ((sv (kbd s)))
                  (and (<= (length sv) (length kv))
                       (equal sv (seq-take kv (length sv))))))
              suppressed)))

(defun maf-bindings--module-claims (name)
  "The (KEY . COMMAND) claims of every registered module on profile NAME.
Enabled and disabled alike — conflicts must not depend on toggle
state. Second value: the same list restricted to enabled modules."
  (let (all enabled)
    (dolist (m maf-bindings--modules)
      (let ((on (and (boundp (plist-get (cdr m) :mode))
                     (symbol-value (plist-get (cdr m) :mode)))))
        (dolist (spec (plist-get (cdr m) :keys))
          (pcase-let ((`(,profiles ,key ,cmd) spec))
            (when (or (eq profiles :all) (memq name profiles))
              (push (cons key cmd) all)
              (when on (push (cons key cmd) enabled)))))))
    (list (nreverse all) (nreverse enabled))))

(defun maf-bindings--validate (name defaults module-claims)
  "Signal on conflicting claims for profile NAME.
Two owners on one key with different commands, or a key that is both
a command and a live prefix of another claim, are errors — never
precedence accidents."
  (let ((claims (append defaults module-claims))
        (seen (make-hash-table :test #'equal)))
    (dolist (claim claims)
      (let ((prior (gethash (car claim) seen)))
        (when (and prior (not (eq prior (cdr claim))))
          (error "maf-bindings: %s: key %S claimed as %s and %s"
                 name (car claim) prior (cdr claim))))
      (puthash (car claim) (cdr claim) seen))
    (dolist (claim claims)
      (let ((kv (kbd (car claim))))
        (dolist (other claims)
          (let ((ov (kbd (car other))))
            (when (and (< (length kv) (length ov))
                       (equal kv (seq-take ov (length kv))))
              (error "maf-bindings: %s: %S is a command but a prefix of %S"
                     name (car claim) (car other)))))))))

(defun maf-bindings-compile ()
  "Rebuild every profile's generated map from the registry.
Validates first; the maps keep their identity, so a composition that
references them stays live."
  (dolist (p maf-bindings--profiles)
    (pcase-let* ((`(,name . ,entry) p)
                 (defaults (plist-get entry :defaults))
                 (suppressed (plist-get entry :suppressed))
                 (`(,all-mods ,on-mods) (maf-bindings--module-claims name))
                 (map (plist-get entry :map)))
      (maf-bindings--validate name defaults all-mods)
      (maf-bindings--clear-keymap map)
      ;; Defaults first, enabled modules after: within one flat map the
      ;; later write wins, which is the documented order — and the
      ;; validator has already refused real conflicts.
      (dolist (claim (append defaults on-mods))
        (unless (maf-bindings--suppressed-p (car claim) suppressed)
          (define-key map (kbd (car claim)) (cdr claim)))))))

;;; The dispatcher

(defcustom maf-bindings-profile 'native
  "The active binding profile's name.
Set before maf loads, switch live with `maf-bindings-set-profile', or
set through Customize; a plain setq after load does not re-apply."
  :type '(choice (const calc) (const native) (const vim)
                 (symbol :tag "Custom profile"))
  :set (lambda (sym val)
         (set-default sym val)
         (when (and (featurep 'maf-bindings) maf-bindings--active)
           (maf-bindings--refresh)))
  :group 'maf)

(defun maf-bindings--apply ()
  "Point `maf-mode-map' at the active profile.
The map keeps its identity — external references stay valid — and its
own table stays empty; everything lives in the parent composition:
the profile's user map, then `maf-common-user-map', then the compiled
profile map (whose own parent is the base map)."
  (let ((entry (maf-bindings--profile maf-bindings-profile)))
    (set-keymap-parent
     maf-mode-map
     (make-composed-keymap
      (list (symbol-value (plist-get entry :user-map))
            maf-common-user-map
            (plist-get entry :map))))))

(defun maf-bindings--refresh ()
  "Recompile, and re-apply when the dispatcher is live."
  (maf-bindings-compile)
  (when maf-bindings--active
    (maf-bindings--apply)
    (maf-bindings--digit-sync)))

(defun maf-bindings-set-profile (name)
  "Switch to binding profile NAME, live."
  (interactive
   (list (intern (completing-read
                  "Binding profile: "
                  (mapcar (lambda (p) (symbol-name (car p)))
                          maf-bindings--profiles)
                  nil t))))
  (maf-bindings--profile name)
  (setq maf-bindings-profile name)
  (maf-bindings--refresh)
  (message "maf bindings: %s profile" name))

;;; Digit-entry overrides

(defvar maf-bindings--digit nil
  "List of (KEY COMMAND EXPECTED): maf's calc-digit-map overrides.
EXPECTED names the stock calc binding the declaration replaces —
installation's criterion and removal's restore value.")

(defvar maf-bindings--digit-installed nil
  "Alist KEY -> SAVED of overrides actually installed, for restoring.")

(defun maf-bindings-digit-define (key command expected)
  "Declare a calc-digit-map override, replacing any prior one for KEY."
  (setq maf-bindings--digit
        (cons (list key command expected)
              (cl-remove key maf-bindings--digit :key #'car :test #'equal))))

(defun maf-bindings--digit-sync ()
  "Install or remove the digit overrides to match the active state.
Install only when the current binding is the declared stock one — a
user's direct customization is left untouched; remove only when the
current binding is still the one maf installed."
  (if maf-bindings--active
      (pcase-dolist (`(,key ,cmd ,expected) maf-bindings--digit)
        (when (and (not (assoc key maf-bindings--digit-installed))
                   (eq (lookup-key calc-digit-map (kbd key)) expected))
          (define-key calc-digit-map (kbd key) cmd)
          (push (cons key expected) maf-bindings--digit-installed)))
    (pcase-dolist (`(,key ,cmd ,_expected) maf-bindings--digit)
      (let ((saved (assoc key maf-bindings--digit-installed)))
        (when (and saved (eq (lookup-key calc-digit-map (kbd key)) cmd))
          (define-key calc-digit-map (kbd key) (cdr saved)))
        (setq maf-bindings--digit-installed
              (delq saved maf-bindings--digit-installed))))))

(defun maf-bindings-module-display-keys (module)
  "MODULE's entry keys in the active profile, as a display string.
Derived from the module's declarations rather than stored, so a
profile switch or a suppression is always reflected. Nil when the
module declared no keys, or none reach the active profile."
  (let ((entry (cdr (assq module maf-bindings--modules)))
        (suppressed (ignore-errors
                      (plist-get (maf-bindings--profile maf-bindings-profile)
                                 :suppressed)))
        keys)
    (dolist (spec (plist-get entry :keys))
      (pcase-let ((`(,profiles ,key ,_cmd) spec))
        (when (and (or (eq profiles :all) (memq maf-bindings-profile profiles))
                   (not (maf-bindings--suppressed-p key suppressed)))
          (push key keys))))
    (and keys (mapconcat #'identity (nreverse keys) ", "))))

;;; Module

;;;###autoload
(define-minor-mode maf-use-bindings-mode
  "Global minor mode putting maf's key layout on `maf-mode-map'.
Enabled, the active profile's compiled bindings — with the user maps
above them — become `maf-mode-map's parent, and the digit-entry
overrides install. Disabled, maf binds nothing at all: every key falls
through to calc, and commands stay reachable by name. Managed through
the module system; see `maf-modules'."
  :global t
  :group 'maf
  (if maf-use-bindings-mode
      (progn (setq maf-bindings--active t)
             (maf-bindings--refresh))
    (setq maf-bindings--active nil)
    (set-keymap-parent maf-mode-map nil)
    (maf-bindings--digit-sync)))

;; Register with the module system when it is present; the mode above
;; works on its own without it.
(defun maf-bindings--module-values ()
  "Dial row values for the module menu: off, then every profile.
The menu row is a profile picker rather than a toggle — stepping onto
a profile turns the module on and switches to it; off is the module
off. Built fresh per menu build, so a user-defined profile appears the
moment it is registered."
  (list :values
        (append '((nil "off" (maf-use-bindings-mode -1)))
                (mapcar (lambda (p)
                          (let ((name (car p)))
                            (list name (symbol-name name)
                                  `(progn (maf-use-bindings-mode 1)
                                          (maf-bindings-set-profile ',name)))))
                        (reverse maf-bindings--profiles)))
        :current (lambda (raw) (and raw maf-bindings-profile))))

(when (require 'maf-module nil t)
  (maf-register-module 'maf-bindings #'maf-use-bindings-mode
                       "Key layouts as switchable profiles.

Every maf key lives in a binding profile — calc, native, or vim — over
one shared base, compiled from declarations. Switch live with
`maf-bindings-set-profile'; personal keys go in the per-profile user
maps (maf-native-user-map and kin) with plain define-key. Disabled,
maf binds no keys at all."
                       nil #'maf-bindings--module-values))

(provide 'maf-bindings)
