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

  ;; Conflicts are compile errors, not precedence accidents: another
  ;; owner claiming a module's key, and a command that prefixes a
  ;; longer claim, both refuse — toggle state notwithstanding.
  (maf-bindings-define '(test-b) "0" #'undefined)
  (cl-assert (eq 'refused (condition-case nil
                              (progn (maf-bindings-compile) 'compiled)
                            (error 'refused))))
  (maf-bindings-defprofile 'test-b)
  (maf-bindings-define '(test-b) "z" #'ignore)
  (maf-bindings-define '(test-b) "z z" #'undefined)
  (cl-assert (eq 'refused (condition-case nil
                              (progn (maf-bindings-compile) 'compiled)
                            (error 'refused))))
  (maf-bindings-defprofile 'test-b)
  (maf-bindings-module-keys 'test-mod 'maf-test-br--mode nil)
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
