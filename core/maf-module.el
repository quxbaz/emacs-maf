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
  "Alist of (NAME MODE DESCRIPTION KEYS GROUP) for registered modules.
NAME is a symbol naming the module; MODE is its global minor-mode
function, which is also the variable holding the mode's state;
DESCRIPTION is the module's help text, shown in the module menu (see
`maf-list-modules'), or nil; KEYS names the entry keys MODE binds
while on, written as they are shown to the user (\"s o\";
\"t l, t u\" for several), or nil for a module with none. The menu
puts KEYS beside the name heading the echoed help — the binding only
exists while the mode is on, so the menu cannot look it up from the
keymap for the modules one is reading about before enabling. GROUP
is the menu section the module files under — \"Display\",
\"Editing\", \"Memory\", \"Config\" — or nil for the fallback
\"Modules\" section; a name, not a taxonomy: a new module joins the
group whose company reads best.

A description is written in two parts: a first line saying in one
short sentence what the module does, then a blank line, then a
paragraph saying what that means in practice — the keys it puts under
your fingers, why you would want it, what it leaves alone. Three or
four lines of paragraph is the size; the whole text is echoed at once
and has to fit an echo area on a small frame.

The first line stands alone where only one line fits, so it has to
say something on its own; see `maf-module--summary'. The module's
name is not part of it — the menu puts that in front of the text it
echoes, and Customize in front of the tag it builds.")

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

(defun maf-module--summary (description)
  "Return DESCRIPTION's first line, or nil if there is none.
A description carries a summary line and a paragraph under it (see
`maf-module-registry'). Where only one line fits — a Customize
checkbox tag — this is the part that goes there."
  (and description (car (split-string description "\n"))))

(defun maf-module--custom-type ()
  "Build a Customize `:type' for `maf-modules' from `maf-module-registry'.
A checkbox per registered module, labelled with the name to set from
Lisp and the summary line of the description the module gives for
itself — a tag is one line, so only that part fits. Sorted as the menu sorts
names (see `maf-module--sort-key'): `maf-module-registry' is in
reverse registration order, an artifact of the load order in maf.el
that should not decide how the option reads."
  `(set ,@(mapcar (lambda (entry)
                    (let ((name (car entry))
                          (desc (maf-module--summary (caddr entry))))
                      `(const :tag ,(if desc
                                        (format "%s — %s" name desc)
                                      (symbol-name name))
                              ,name)))
                  (sort (copy-sequence maf-module-registry)
                        (lambda (a b)
                          (string< (maf-module--sort-key (car a))
                                   (maf-module--sort-key (car b))))))))

(defun maf-register-module (name mode &optional description keys group values-fn)
  "Register module NAME with its global minor mode MODE.
DESCRIPTION is the help text the module gives for itself — a summary
line, a blank line, then a short paragraph (see
`maf-module-registry') — shown in the module menu (see
`maf-list-modules'), and its summary line alone on the module's
checkbox in Customize. KEYS names the entry keys MODE binds while on,
as they are shown to the user (see `maf-module-registry'), or nil for
a module with none; the menu shows it beside the name heading the
echoed help. GROUP is the menu section the module files under (see
`maf-module-registry'), or nil for the fallback section. VALUES-FN,
for the rare module that is more than a toggle, returns a plist of
dial row overrides — :values and :current — built fresh at each menu
build; absent, the row is the plain on/off.

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
  (setf (alist-get name maf-module-registry)
        (list mode description keys group values-fn))
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
      (funcall (cadr entry) (if (memq (car entry) maf-modules) 1 -1))))
  ;; After the burst, so work a mode body batched while
  ;; `maf-module--applying' was set can run once — the bindings
  ;; system compiles here instead of once per toggle.
  (run-hooks 'maf-modules-applied-hook))

;;; Module menu

;; A dial buffer (pkg/dial) over the registry: each module is an
;; on/off row whose setters call the mode function directly, so
;; `maf-module--reconcile' keeps `maf-modules' in step just as an
;; `M-x' toggle would. The description a module gives for itself is
;; the row's :doc, echoed as point rests on it — dial's convention,
;; where the old menu spent a column on it. The echo area is the
;; resting help surface here, which is why a description is a summary
;; line and a paragraph rather than the one line an options row
;; carries: a row
;; names a module you have never heard of, and the name plus "on/off"
;; says nothing about whether you want it. The name heads the echoed
;; text (see `maf-module--doc'), so help outliving the move off its
;; row still says who it is about. The echo area grows to fit what is
;; messaged, so the whole thing costs a few lines while point rests on
;; the row and nothing after — provided it stays small enough to fit,
;; which is why a description keeps to a summary and three or four
;; lines under it.
;;
;; What outgrows even that — the minor mode's own docstring, the live
;; on/off state — is a keypress away instead: ? (`dial-describe')
;; displays the module's full story in another window, w
;; (`dial-describe-visit') selects it too, and either is built fresh
;; by `maf-module--details' at each ask.

(defun maf-module--state (name)
  "Non-nil when module NAME's mode is on."
  (let ((mode (car (alist-get name maf-module-registry))))
    (and (boundp mode) (symbol-value mode) t)))

(defun maf-module--default (name)
  "Module NAME's shipped state: t when `maf-modules' ships it enabled.
Read from the option's standard value, not its current one — the
current value is exactly what the menu is editing. This is each
row's :default, so the live value wears `dial-value' on its shipped
state and `dial-changed' once toggled away, and \\<dial-mode-map>\\[dial-reset] puts the
shipped state back."
  (and (memq name (eval (car (get 'maf-modules 'standard-value)) t))
       t))

(defface maf-module-keys
  ;; Quieter than the name beside it, but a step lighter than `shadow',
  ;; whose gray sinks into the echo area's ground.
  '((((class color) (background dark))  :foreground "#a8b2bd")
    (((class color) (background light)) :foreground "#595f66"))
  "Face for a module's entry keys in the menu's echoed help."
  :group 'maf)

(defun maf-module--keys (name keys)
  "The entry keys shown for module NAME, preferring the live answer.
The bindings registry knows the module's keys in the *active
profile*, suppressions and all; the registered static KEYS is the
fallback for modules not yet declaring through it."
  (or (and (fboundp 'maf-bindings-module-display-keys)
           (maf-bindings-module-display-keys name))
      keys))

(defun maf-module--doc (name description keys)
  "Build the help echoed for module NAME from its DESCRIPTION and KEYS.
The name heads the text on a line of its own — KEYS beside it in
parens, for the modules that have entry keys, in `maf-module-keys' so
the name stays the line's loudest word — then the description as the
module wrote it (see `maf-module-registry'). Point moving off
the row leaves the help standing in the echo area, where a paragraph
with nothing above it says nothing about which module it is for — so
the row's own name comes along. Nil for a module that gave no
description, which leaves dial silent rather than echoing a bare name
the row already shows."
  (and description
       (concat (symbol-name name)
               (if keys
                   (propertize (format " (%s)" keys) 'face 'maf-module-keys)
                 "")
               "\n\n" description)))

(defun maf-module--mode-doc (mode)
  "MODE's docstring without the minor-mode boilerplate, or nil.
The generated tails — \"With prefix ARG...\", \"If called from
Lisp...\", \"This is a global minor mode...\" — are the same lecture
on toggling under every mode, so in a buffer describing one module
they are cut, leaving what the mode's author wrote. Nil for a mode
with no docstring, or one that is nothing but the lecture."
  (when-let ((doc (documentation mode)))
    (let* ((cut (string-match
                 (concat "\n?\n\\(?:This is a \\(?:global \\)?minor mode\\."
                         "\\|If called \\(?:interactively\\|from Lisp\\)"
                         "\\|With prefix ARG\\)")
                 doc))
           (text (string-trim (if cut (substring doc 0 cut) doc))))
      (and (not (string-empty-p text)) text))))

(defun maf-module--mode-sections (mode)
  "The (SYMBOL . TEXT) docstring sections shown for module mode MODE.
MODE's own first. A globalized mode defined without a docstring gets
nothing but generated text, whose \"See ... for more information\"
names the buffer-local mode it drives — where the real writing lives
— so that mode's docstring follows as a second section when the
pointer is there to chase."
  (let ((sections (list (cons mode (or (maf-module--mode-doc mode)
                                       "Not documented."))))
        (doc (documentation mode)))
    (when (and doc
               (string-match "See [`‘]\\([^'’]+\\)['’] for more information"
                             doc))
      (when-let* ((local (intern-soft (match-string 1 doc)))
                  ((fboundp local))
                  (ldoc (maf-module--mode-doc local)))
        (setq sections (nconc sections (list (cons local ldoc))))))
    sections))

(defun maf-module--details (name)
  "Build the verbose text \\<dial-mode-map>\\[dial-describe] shows for module NAME.
Everything the registry and the mode itself can say, at full length:
the heading line the echoed help uses — name and entry keys, plus the
live on/off state the echo leaves to the row — then the description
as the module wrote it, then the mode docstrings, the part that
outgrows any echo (see `maf-module--mode-sections'). Built fresh at
each show, so the state, the keys, and the docstrings are all read
live."
  (pcase-let* ((`(,mode ,description ,keys)
                (alist-get name maf-module-registry))
               (keys (maf-module--keys name keys)))
    (concat
     (propertize (symbol-name name) 'face 'bold)
     (if keys
         (propertize (format " (%s)" keys) 'face 'maf-module-keys)
       "")
     ;; The state wears `dial-value', the purple the live value wears
     ;; on the row, so the heading reads as the row does.
     " — " (propertize (if (maf-module--state name) "on" "off")
                       'face 'dial-value)
     (if description (concat "\n\n" description) "")
     "\n\n"
     (mapconcat (pcase-lambda (`(,symbol . ,text))
                  (concat (propertize (symbol-name symbol) 'face 'bold)
                          "\n\n" text))
                (maf-module--mode-sections mode)
                "\n\n"))))

(defvar maf-module--group-order
  '("Prefs" "Display" "Rewrite" "Editing" "Memory")
  "The menu's groups in reading order.
A group not listed here files after all of these, alphabetically —
so a new group still shows up without an edit here, just not in a
chosen spot.")

(defvar maf-module--follows '((maf-pretty . maf-preview))
  "Modules that read directly under another, not at their own letter.
Each entry is (MODULE . ANCHOR): MODULE files right after ANCHOR
wherever modules are sorted by name — for a module that extends
another and reads best beneath it, as pretty retints the panel that
preview puts up. Anchor and follower should register the same group,
or the group ordering separates them anyway.")

(defun maf-module--sort-key (name)
  "Return the string module NAME sorts by among its neighbors.
A module listed in `maf-module--follows' borrows its anchor's name
with its own appended behind a `~' — which outsorts every letter, so
the follower lands directly after the anchor and before whatever
followed the anchor alphabetically."
  (let ((anchor (alist-get name maf-module--follows)))
    (if anchor
        (concat (symbol-name anchor) "~" (symbol-name name))
      (symbol-name name))))

(defun maf-module--items ()
  "Compile `maf-module-registry' into dial items, grouped and sorted.
Each module files under the group it registered — the menu's sections
— and reads alphabetically within it. The groups themselves follow
`maf-module--group-order'. The registry itself is in reverse
registration order, an artifact of the load order in maf.el that
should not decide how the menu reads."
  (mapcar (lambda (entry)
            (pcase-let ((`(,name ,mode ,description ,keys ,group ,values-fn)
                         entry))
              (cons name
                    (append
                     (list :group (or group "Modules")
                           :label (symbol-name name)
                           :doc (maf-module--doc
                                 name description
                                 (maf-module--keys name keys))
                           :details (lambda (_id)
                                      (maf-module--details name)))
                     ;; A module that is more than a toggle brings its
                     ;; own values — rebuilt each time, so a value set
                     ;; that grows (binding profiles) stays current —
                     ;; and may state its own :default (the profile
                     ;; picker's is native); a plain toggle's default
                     ;; is its shipped state, so the row can wear gold
                     ;; once toggled away from it.
                     (let ((values (or (and values-fn (funcall values-fn))
                                       `(:values ((t   "on"  (,mode 1))
                                                  (nil "off" (,mode -1)))))))
                       (if (plist-member values :default)
                           values
                         (append values
                                 (list :default
                                       (maf-module--default name)))))))))
          (sort (copy-sequence maf-module-registry)
                (lambda (a b)
                  ;; Group first, name within: dial sections are runs
                  ;; of adjacent rows, so a group must sit together —
                  ;; in the order `maf-module--group-order' lays out.
                  (let* ((ga (or (nth 4 a) "Modules"))
                         (gb (or (nth 4 b) "Modules"))
                         (ia (seq-position maf-module--group-order ga))
                         (ib (seq-position maf-module--group-order gb)))
                    (cond ((string= ga gb)
                           (string< (maf-module--sort-key (car a))
                                    (maf-module--sort-key (car b))))
                          ((and ia ib) (< ia ib))
                          (ia t)
                          (ib nil)
                          (t (string< ga gb))))))))

(defvar maf-module--controls nil
  "The module menu's controls line.
Dial's default names controls this buffer has no use for — filtering
by changed, a save — so the line is written out: flipping a module is
most of the interface. Reset stays on it for the rare row that
carries a :default of its own (the maf-bindings profile picker);
dial's availability gate drops it again should no such row remain.")

;; Set outside the defvar so a reload applies edits to the list.
(setq maf-module--controls
      '(((dial-next-value dial-previous-value) "toggle" "TAB" "SPC")
        ((dial-describe-visit dial-describe) "details" "w" "?")
        (dial-reset "reset")
        (dial-refresh "refresh")
        (quit-window "quit" "q" "RET")))

;;;###autoload
(defun maf-list-modules ()
  "Show the maf module toggle buffer in another window and select it.
Each registered module is a row; TAB or SPC flips the one on the
current line, and what that module is for echoes as point rests on it
— its name, a line saying what it does, and a paragraph on what that
means in practice (see `dial-mode' and `maf-module-registry').
\\<dial-mode-map>\\[dial-describe] goes further: the module's full
details — state, description, and its minor mode's own docstring —
shown in another window (see `maf-module--details'). The
buffer is dial's, keys and all — flipping is dial's value stepping,
which on a two-value row is a toggle — and this command only supplies
the registry."
  (interactive)
  (dial-open "*maf-modules*" (maf-module--items)
             :name "maf-modules"
             :controls maf-module--controls
             :raw #'maf-module--state
             :init #'maf-module--menu-keys))

(defun maf-module--menu-keys ()
  "Give the menu's buffer its own keys over `dial-mode's.
RET quits: dial's RET is `dial-set', the run-the-pending step for a
value whose setter prompts — and no module row prompts, so here the
key could only ever complain. Reading it as done-here instead suits
the menu's use: drop in, flip a switch, leave."
  (use-local-map
   (let ((map (make-sparse-keymap)))
     (set-keymap-parent map dial-mode-map)
     (define-key map (kbd "RET") #'quit-window)
     map)))

(provide 'maf-module)
