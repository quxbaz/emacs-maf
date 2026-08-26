;; The bindings registry and compiler (core/maf-bindings.el), exercised
;; on toy profiles so nothing touches the live layout: declarations,
;; whole-set replacement, cloning, suppression (prefix included),
;; module keys following their toggle, conflict validation, and the
;; digit tracker's install criterion. docs/bindings.org phase 2.

(defvar maf-test-br--mode nil)

(defun maf-test-br--map (name)
  "NAME's compiled map."
  (plist-get (maf-bindings--profile name) :map))

(defun maf-test-br--lookup (name key)
  "KEY's binding in NAME's compiled map; nil when unbound.
`lookup-key' answers a number for a key reaching past an unbound
prefix — as absent as nil, for these assertions."
  (let ((b (lookup-key (maf-test-br--map name) (kbd key))))
    (if (numberp b) nil b)))

(maf-step
  ;; Two toy profiles; the second clones the first at definition time.
  (maf-bindings-defprofile 'test-a)
  (maf-bindings-define '(test-a) "z z" #'ignore)
  (maf-bindings-define '(test-a) "y" #'undefined)
  (maf-bindings-defprofile 'test-b :clone 'test-a)
  (maf-bindings-define '(test-b) "q" #'ignore)
  (maf-bindings-compile)

  ;; Declarations landed; the clone carried test-a's defaults but not
  ;; its later changes, and test-a never sees test-b's additions.
  (cl-assert (eq (maf-test-br--lookup 'test-a "z z") 'ignore))
  (cl-assert (eq (maf-test-br--lookup 'test-b "z z") 'ignore))
  (cl-assert (eq (maf-test-br--lookup 'test-b "q") 'ignore))
  (cl-assert (null (maf-test-br--lookup 'test-a "q")))

  ;; The generated user maps exist under the short names, empty.
  (cl-assert (keymapp maf-test-a-user-map))
  (cl-assert (keymapp maf-test-b-user-map))

  ;; Both compiled maps inherit the base map: a remap placed there is
  ;; visible through every profile.
  (define-key maf-bindings-base-map [remap forward-char] #'ignore)
  (cl-assert (eq (lookup-key (maf-test-br--map 'test-b) [remap forward-char])
                 'ignore))
  (define-key maf-bindings-base-map [remap forward-char] nil)

  ;; The escape hatch: the escape map is base's parent, so m c reaches
  ;; the module menu through every compiled map — a toy profile that
  ;; never declared it included — and it stays as `maf-mode-map's whole
  ;; parent while the module is off, so the menu is never further away
  ;; than m c whatever the binding state.
  (cl-assert (eq (keymap-parent maf-bindings-base-map)
                 maf-bindings-escape-map))
  (cl-assert (eq (maf-test-br--lookup 'test-a "m c") 'maf-list-modules))
  (let ((was maf-use-bindings-mode))
    (unwind-protect
        (progn
          (maf-use-bindings-mode -1)
          (cl-assert (eq (keymap-parent maf-mode-map)
                         maf-bindings-escape-map))
          (cl-assert (eq (lookup-key maf-mode-map (kbd "m c"))
                         'maf-list-modules))
          ;; ...and nothing else: a profile key is gone while off.
          (cl-assert (not (commandp (lookup-key maf-mode-map (kbd "k k"))))))
      (when was (maf-use-bindings-mode 1))))

  ;; Redeclaring the same key in the same profile replaces (one owner,
  ;; last say); redefprofile replaces the whole default set.
  (maf-bindings-define '(test-a) "y" #'ignore)
  (maf-bindings-compile)
  (cl-assert (eq (maf-test-br--lookup 'test-a "y") 'ignore))
  (maf-bindings-defprofile 'test-a)
  (maf-bindings-compile)
  (cl-assert (null (maf-test-br--lookup 'test-a "y")))
  (cl-assert (null (maf-test-br--lookup 'test-a "z z")))
  ;; ...while test-b's copy is a snapshot, untouched by the reset.
  (cl-assert (eq (maf-test-br--lookup 'test-b "z z") 'ignore))

  ;; Suppression omits the generated key; a suppressed prefix takes its
  ;; descendants; restore brings the default back.
  (maf-bindings-unbind 'test-b "q")
  (cl-assert (null (maf-test-br--lookup 'test-b "q")))
  (maf-bindings-unbind 'test-b "z")
  (cl-assert (null (maf-test-br--lookup 'test-b "z z")))
  (maf-bindings-restore 'test-b "q")
  (maf-bindings-restore 'test-b "z")
  (cl-assert (eq (maf-test-br--lookup 'test-b "q") 'ignore))
  (cl-assert (eq (maf-test-br--lookup 'test-b "z z") 'ignore))

  ;; Module keys compile in only while the module's mode variable is
  ;; on; the toggle is a recompile, never a map mutation.
  (setq maf-test-br--mode nil)
  (maf-bindings-module-keys 'test-mod 'maf-test-br--mode
                            '(((test-b) "0" ignore)))
  (cl-assert (null (maf-test-br--lookup 'test-b "0")))
  (setq maf-test-br--mode t)
  (maf-bindings-compile)
  (cl-assert (eq (maf-test-br--lookup 'test-b "0") 'ignore))

  ;; A default beneath a module's key is a shadow, not a conflict: the
  ;; module's command holds the key while the mode is on, and the
  ;; default comes back — unmutated, never overwritten — when it goes
  ;; off.
  (maf-bindings-define '(test-b) "0" #'undefined)
  (maf-bindings-compile)
  (cl-assert (eq (maf-test-br--lookup 'test-b "0") 'ignore))
  (setq maf-test-br--mode nil)
  (maf-bindings-compile)
  (cl-assert (eq (maf-test-br--lookup 'test-b "0") 'undefined))
  (setq maf-test-br--mode t)
  (maf-bindings-compile)

  ;; What a shadow is not: two modules on one key have no toggle to
  ;; tell them apart, so that stays a compile error — toggle state
  ;; notwithstanding. A declaration refreshes, so the refusal can
  ;; surface there rather than at the explicit compile; the assertion
  ;; covers both, and the claim is withdrawn either way.
  (cl-assert (eq 'refused
                 (condition-case nil
                     (progn (maf-bindings-module-keys
                             'test-mod-2 'maf-test-br--mode
                             '(((test-b) "0" undefined)))
                            (maf-bindings-compile)
                            'compiled)
                   (error 'refused))))
  (maf-bindings-module-keys 'test-mod-2 'maf-test-br--mode nil)

  ;; And a shadow covers the whole key and no more: a module may not
  ;; bury a default's prefix family under a command of its own, which
  ;; no toggle could put back the way it found it.
  (maf-bindings-defprofile 'test-b)
  (maf-bindings-define '(test-b) "z z" #'undefined)
  (cl-assert (eq 'refused
                 (condition-case nil
                     (progn (maf-bindings-module-keys
                             'test-mod 'maf-test-br--mode
                             '(((test-b) "z" ignore)))
                            (maf-bindings-compile)
                            'compiled)
                   (error 'refused))))
  (maf-bindings-module-keys 'test-mod 'maf-test-br--mode nil)

  ;; A command that prefixes a longer claim refuses among defaults too.
  (maf-bindings-defprofile 'test-b)
  (maf-bindings-define '(test-b) "z" #'ignore)
  (maf-bindings-define '(test-b) "z z" #'undefined)
  (cl-assert (eq 'refused (condition-case nil
                              (progn (maf-bindings-compile) 'compiled)
                            (error 'refused))))
  (maf-bindings-defprofile 'test-b)
  (maf-bindings-compile)

  ;; The digit tracker: installs only onto the declared stock binding,
  ;; leaves a user's own customization alone, and restores only what it
  ;; installed. Driven on a scratch key of calc-digit-map.
  ;; The declaration and installed lists are let-bound to the scratch
  ;; entry alone, so the sync cannot disturb the real overrides.
  (let ((stock (lookup-key calc-digit-map "Z"))
        (maf-bindings--digit nil)
        (maf-bindings--digit-installed nil))
    (unwind-protect
        (progn
          (maf-bindings-digit-define "Z" #'ignore stock)
          (let ((maf-bindings--active t))
            (maf-bindings--digit-sync)
            (cl-assert (eq (lookup-key calc-digit-map "Z") 'ignore)))
          (let ((maf-bindings--active nil))
            (maf-bindings--digit-sync)
            (cl-assert (eq (lookup-key calc-digit-map "Z") stock)))
          ;; A pre-existing user customization blocks the install.
          (define-key calc-digit-map "Z" #'undefined)
          (let ((maf-bindings--active t))
            (maf-bindings--digit-sync)
            (cl-assert (eq (lookup-key calc-digit-map "Z") 'undefined)))
          (let ((maf-bindings--active nil))
            (maf-bindings--digit-sync)
            (cl-assert (eq (lookup-key calc-digit-map "Z") 'undefined))))
      (define-key calc-digit-map "Z" stock)
      (setq maf-bindings--digit
            (cl-remove "Z" maf-bindings--digit :key #'car :test #'equal))))

  ;; The laziness contract: declaration changes while the dispatcher is
  ;; inactive compile nothing — they mark the maps dirty and the next
  ;; flush pays once. Switching profiles never compiles by itself.
  (let ((maf-bindings--active nil)
        (before maf-bindings--compile-count))
    (maf-bindings-define '(test-b) "9" #'ignore)
    (maf-bindings-module-keys 'test-mod 'maf-test-br--mode
                              '(((test-b) "8" ignore)))
    (setq maf-test-br--mode nil)
    (cl-assert (= maf-bindings--compile-count before))
    (cl-assert maf-bindings--dirty))
  (let ((before maf-bindings--compile-count))
    (maf-bindings-compile)
    (setq maf-bindings--dirty nil)
    (cl-assert (= maf-bindings--compile-count (1+ before))))
  (let ((maf-bindings--active t)
        (before maf-bindings--compile-count))
    ;; Clean maps: a profile switch repoints without compiling...
    (maf-bindings-set-profile maf-bindings-profile)
    (cl-assert (= maf-bindings--compile-count before))
    ;; ...and a live declaration change compiles exactly once.
    (maf-bindings-define '(test-b) "7" #'ignore)
    (maf-bindings--refresh)
    (cl-assert (= maf-bindings--compile-count (1+ before))))

  ;; Every mutator marks dirty on its own — a defprofile, a define, a
  ;; digit declaration — so the documented custom-profile flow
  ;; (defprofile, define, set-profile) compiles and lands its keys.
  (progn (setq maf-bindings--dirty nil)
         (maf-bindings-defprofile 'test-c)
         (cl-assert maf-bindings--dirty))
  (progn (setq maf-bindings--dirty nil)
         (maf-bindings-define '(test-c) "5" #'ignore)
         (cl-assert maf-bindings--dirty))
  (progn (setq maf-bindings--dirty nil)
         (maf-bindings-digit-define "Z" #'ignore 'ignore)
         (cl-assert maf-bindings--dirty)
         (setq maf-bindings--digit
               (cl-remove "Z" maf-bindings--digit :key #'car :test #'equal)))
  (let ((maf-bindings--active t)
        (before maf-bindings--compile-count))
    (maf-bindings-set-profile 'test-c)
    (cl-assert (= maf-bindings--compile-count (1+ before)))
    (cl-assert (eq (maf-test-br--lookup 'test-c "5") 'ignore))
    (maf-bindings-set-profile 'native))
  (maf-bindings--forget 'test-c)

  ;; Toy state out of the registry.
  (maf-bindings--forget 'test-a)
  (maf-bindings--forget 'test-b)
  (setq maf-bindings--modules (assq-delete-all 'test-mod maf-bindings--modules))
  (cl-assert (null (assq 'test-a maf-bindings--profiles))))
