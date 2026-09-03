;; -*- lexical-binding: t; -*-
;;
;; modules/maf-keys.el
;;
;; The bindings help buffer. `maf-keys' opens *maf-keys*: every key maf
;; claims in the active profile, organized by what the commands do.
;; Each item is a command headed by its proper name and its keys, over
;; an example and the first line of its docstring:
;;
;;   Power (^) ... (mafcmd-pow)
;;     x, 2 => x^2
;;     Raise the resolved expression to the top-of-stack power.
;;
;; The name and the example are the command's own — a mafcmd table row
;; declares them with :title and :example, a hand-written `maf-defcmd'
;; with the same two options, and the plain `defun's are given theirs
;; by `maf-keys-descriptions' — and a command carrying neither shows
;; its symbol over its description, as every command did before.
;;
;; The groups are this file's data (`maf-keys-groups'); the keys never
;; are — every render reads the bindings registry live, so a profile
;; switch, a suppression, or a module toggle is reflected the next time
;; the buffer renders. A command a group names that has no key right
;; now files under "Unbound" at the end instead — the M-x-only set —
;; and a bound command no group names files under "Other", so nothing
;; the registry knows can fall out of the buffer. The I/H flag-route
;; variants (arcsin under I S, vmedian under H u M, ...) are not
;; listed: they are reachable, and would double the buffer saying so.
;;
;; The buffer is a filter-view (pkg/filter-view), the same shell the
;; formula menu runs on: `/' filters as you type, RET on a group
;; header narrows to that group, TAB folds, n/p/j/k and M-n/M-p walk
;; items and groups, `o' shows a command's full documentation in the
;; detail pane, `O' makes the pane follow point, and the commands
;; described lately gather in a "Recent" group at the top (`a'/`i'
;; add one by hand, `D' drops one). RET describes the command at
;; point, selecting its help buffer; `g' re-reads the registry.
;;
;; The module's key is `l b' — `b' for bindings, under the `l' prefix
;; maf's own additions gather under. Calc keeps `l' for logarithmic
;; units and binds nothing on `l b', so the claim shadows neither
;; calc's keys nor maf's. The vim profile is the exception: `l' is
;; `forward-char' there, so no `l' prefix exists to hang this on and
;; the buffer is reached by name.

(require 'cl-lib)
(require 'seq)
(require 'maf-conf "conf")  ; the `maf' customize group
(require 'maf-lib)          ; `maf--display-borrowing-window', the pane's lender
(require 'maf-bindings)     ; the registry every render reads
(require 'dial)             ; first, so filter-view's chrome inherits its
(require 'filter-view)      ; the menu shell: filtering, groups, the pane

;; Read when present; the buffer renders without them.
(defvar maf-cmds--table)
(declare-function maf-register-module "maf-module")

;;; Faces

(defface maf-keys-command
  '((t :inherit help-key-binding))
  "Face for a command's symbol in the bindings help buffer.
The keys' own face: the symbol in parens is what you would type at
\\[execute-extended-command] where the keys are what you would press,
so the head names its two ways in in the one style — the parens left
unfaced around each, the text inside them coloured."
  :group 'maf)

(defface maf-keys-binding
  '((t :inherit help-key-binding))
  "Face for the keys beside a command in the bindings help buffer."
  :group 'maf)

(defface maf-keys-doc
  '((((background dark))  :foreground "grey68")
    (((background light)) :foreground "grey35")
    (t :inherit shadow))
  "Face for a command's one-line description in the bindings help buffer.
A step lighter than `shadow', which the example wears too (see
`maf-keys-example'): between them those two lines are most of the
entry, and read at length rather than glanced at the way a shadowed
label is. Grey still — the head above is what the eye scans by."
  :group 'maf)

(defface maf-keys-title
  '((t :inherit font-lock-function-name-face))
  "Face for a command's proper name, leading its head.
The color the symbol itself used to wear, and now the one thing in
the entry wearing it: the name is what the head is read by, where the
symbol and the keys after it are the two ways in, and the lines below
are grey."
  :group 'maf)

(defface maf-keys-example
  '((t :inherit font-lock-doc-face))
  "Face for a command's one-line example.
Its own color under the head and above the grey description: the
example is the line that says what the command does without prose,
and it is worth telling from the sentence below it at a glance."
  :group 'maf)

(defcustom maf-keys-recent-max 10
  "How many recently-described commands the \"Recent\" group holds.
Zero drops the group entirely. The list is per-session; nothing is
written to disk."
  :type 'integer
  :group 'maf)

;;; The groups

(defvar maf-keys-groups nil
  "The buffer's taxonomy: (TITLE COMMAND...) in reading order.
Group membership is data about the command, not about its key, so a
command keeps its group when its key moves. A listed command that is
not `fboundp' is skipped; one with no key in the active profile files
under \"Unbound\" at the end; a bound command no group lists files
under \"Other\" — so this list can lag the code without the buffer
lying, and a new command shows up (misfiled but visible) before
anyone edits it in.")

;; Set outside the defvar so a reload applies edits to the data.
(setq maf-keys-groups
      '(("Arithmetic"
         mafcmd-add mafcmd-sub mafcmd-mul mafcmd-div mafcmd-pow
         mafcmd-sqrt mafcmd-sqr mafcmd-isqrt mafcmd-inv mafcmd-neg
         mafcmd-negate mafcmd-mod mafcmd-abs mafcmd-abssqr mafcmd-min
         mafcmd-max mafcmd-round mafcmd-decrement mafcmd-increment
         mafcmd-decr mafcmd-incr mafcmd-fact mafcmd-mant mafcmd-xpon
         mafcmd-scf)
        ("Algebra & rewriting"
         mafcmd-esimplify mafcmd-simplify mafcmd-evaluate mafcmd-expand
         mafcmd-factor mafcmd-factor-by mafcmd-factor-gcd
         mafcmd-factor-powers mafcmd-prfac mafcmd-apart mafcmd-collect
         mafcmd-collect-fractions mafcmd-collect-terms mafcmd-nrat
         mafcmd-pgcd mafcmd-pdiv mafcmd-prem mafcmd-pdivrem
         mafcmd-poly-lcm mafcmd-match mafcmd-rewrite mafcmd-substitute
         mafcmd-let mafcmd-complete-square mafcmd-commute
         maf-commute-left maf-commute-right maf-distribute maf-merge
         mafcmd-toggle-op mafcmd-log-exp mafcmd-swap-vars
         mafcmd-unique-groups mafcmd-float-frac mafcmd-subscr)
        ("Equations & solving"
         mafcmd-eq mafcmd-neq mafcmd-lt mafcmd-gt mafcmd-leq mafcmd-geq
         mafcmd-in mafcmd-equal-to mafcmd-remove-equal mafcmd-evalto
         mafcmd-assign mafcmd-solve mafcmd-solve-for mafcmd-isolate
         mafcmd-auto-solve mafcmd-abs-ineq mafcmd-inverse-function
         mafcmd-mapeq mafcmd-roots mafcmd-roots-for mafcmd-poly-roots
         mafcmd-raise)
        ("Calculus"
         mafcmd-deriv mafcmd-integ)
        ("Trig & angles"
         mafcmd-sin mafcmd-cos mafcmd-tan mafcmd-arctan2 mafcmd-hypot
         mafcmd-cath mafcmd-unit-cath mafcmd-to-degrees
         mafcmd-to-radians mafcmd-mod-360 mafcmd-ref-angle
         mafcmd-supplement mafcmd-complement mafcmd-deg mafcmd-rad
         mafcmd-hms mafcmd-coordinate-toggle maf-pi)
        ("Logs & exponentials"
         mafcmd-ln mafcmd-exp mafcmd-log mafcmd-expm1 mafcmd-ilog)
        ("Complex numbers"
         mafcmd-conj mafcmd-re mafcmd-im mafcmd-arg mafcmd-sign)
        ("Combinatorics & number theory"
         mafcmd-choose mafcmd-perm mafcmd-gcd mafcmd-lcm mafcmd-bern
         mafcmd-euler mafcmd-moebius mafcmd-nextprime mafcmd-random
         mafcmd-shuffle)
        ("Special functions"
         mafcmd-gamma mafcmd-gammaP mafcmd-beta mafcmd-erf mafcmd-besJ
         mafcmd-besY mafcmd-utpc mafcmd-utpp mafcmd-utpt)
        ("Vectors & sets"
         mafcmd-vconcat mafcmd-pack mafcmd-unpack mafcmd-unwrap
         mafcmd-flatten maf-index mafcmd-index mafcmd-fold mafcmd-accum
         mafcmd-apply mafcmd-outer mafcmd-inner mafcmd-head
         mafcmd-rtail mafcmd-nth-element mafcmd-cons mafcmd-vlen
         mafcmd-rev mafcmd-sort mafcmd-grade mafcmd-arrange
         mafcmd-cvec mafcmd-diag mafcmd-vexp mafcmd-find mafcmd-vmask
         mafcmd-mcol mafcmd-mrow mafcmd-trn mafcmd-det mafcmd-cross
         mafcmd-tr mafcmd-rnorm mafcmd-cnorm mafcmd-venum
         mafcmd-vfloor mafcmd-histogram mafcmd-vunion mafcmd-vint
         mafcmd-vdiff mafcmd-vxor mafcmd-vcompl mafcmd-vcard
         mafcmd-vspan mafcmd-rdup mafcmd-bracket mafcmd-lud)
        ("Statistics"
         mafcmd-vmean mafcmd-vsdev mafcmd-vmin mafcmd-vmax mafcmd-vcov
         mafcmd-vgmean mafcmd-rms)
        ("Binary, logic & finance"
         mafcmd-and mafcmd-or mafcmd-xor mafcmd-diff mafcmd-not
         mafcmd-clip mafcmd-lsh mafcmd-rsh mafcmd-ash mafcmd-rash
         mafcmd-rot mafcmd-vpack mafcmd-vunpack mafcmd-lnot
         mafcmd-land mafcmd-lor mafcmd-irr mafcmd-npv mafcmd-relch)
        ("Date & time"
         mafcmd-date mafcmd-incmonth mafcmd-julian mafcmd-newmonth
         mafcmd-newweek mafcmd-newyear mafcmd-unixtime)
        ("Variables & recall"
         maf-quick-variable maf-browse-variables maf-recall-variable
         maf-recall-quick maf-recall-previous maf-recall-next
         maf-save-stack maf-saved-stacks maf-restore-stack
         maf-restore-stack-from)
        ("Stack editing"
         maf-undo maf-redo maf-del maf-kill maf-copy maf-yank
         maf-dup-or-clear-selections maf-dup-here-or-clear-selections
         maf-dup maf-dup-here maf-dup-go maf-clear-selections
         maf-swap-up maf-roll-to-bottom maf-roll-to-top maf-carry-up
         maf-carry-down maf-edit maf-edit-entry-at-home
         maf-edit-add-entry-above maf-edit-add-entry-below
         maf-edit-add-vector)
        ("Digit entry"
         maf-digit-start maf-digit-commit-here
         maf-digit-commit-contextual maf-digit-jump maf-digit-sqr
         maf-digit-mod-360 maf-digit-equal-to maf-digit-pi
         maf-digit-colon maf-digit-quit)
        ("Navigation"
         maf-beginning-of-entry maf-forward-noun maf-backward-noun
         maf-forward-operand maf-backward-operand maf-up-expression
         maf-goto-left-side maf-goto-right-side maf-goto-other-side
         maf-jump-equals maf-backward-char)
        ("Mapping & modes"
         mafcmd-map-flag mafcmd-map mafcmd-map-stack
         maf-toggle-simplify maf-reset maf-reset-settings)
        ("Modules & menus"
         maf-keys maf-list-modules maf-options maf-formulas maf-history
         maf-history-clear maf-preview-show maf-pretty maf-plot-embed
         maf-plot-desmos maf-plot-gnuplot)))

;;; Presentation strings for the commands that carry none of their own

(defvar maf-keys-descriptions nil
  "Proper names and examples for commands defined outside `maf-defcmd'.
Rows of (COMMAND TITLE EXAMPLE), either string nil to leave it unsaid.
Applied with `maf-set-command-doc' when this file loads, so the
strings end up where every other command's do — on the symbol, read
back through `maf-command-title' and `maf-command-example'.

The contextual commands declare their own: a mafcmd table row carries
:title and :example, and so does a hand-written `maf-defcmd'. What is
left is the plain `defun's — the stack editing, digit entry,
navigation and menu commands — which have no such option to declare
in, and this is their place. It sits beside `maf-keys-groups' for the
same reason that list does: it is data about how a command reads,
which the buffer owns rather than the command.")

;; Set outside the defvar so a reload applies edits to the data.
(setq maf-keys-descriptions
      '((maf-undo "undo" nil)
        (maf-redo "redo" nil)
        (maf-del "delete" nil)
        (maf-kill "kill" nil)
        (maf-copy "copy" nil)
        (maf-yank "yank" nil)
        (maf-dup "duplicate" "3 => 3, 3")
        (maf-swap-up "swap up" nil)
        (maf-edit "edit" nil)
        (maf-roll-to-top "roll to top" nil)
        (maf-roll-to-bottom "roll to bottom" nil)
        (maf-carry-up "carry up" nil)
        (maf-carry-down "carry down" nil)
        (maf-beginning-of-entry "beginning of entry" nil)
        (maf-forward-noun "forward noun" nil)
        (maf-backward-noun "backward noun" nil)
        (maf-forward-operand "forward operand" nil)
        (maf-backward-operand "backward operand" nil)
        (maf-up-expression "up expression" nil)
        (maf-goto-left-side "go to the left side" nil)
        (maf-goto-right-side "go to the right side" nil)
        (maf-goto-other-side "go to this side, then the other" nil)
        (maf-jump-equals "jump to the relation" nil)
        (maf-quick-variable "quick variable" nil)
        (maf-browse-variables "browse variables" nil)
        (maf-recall-variable "recall a variable" nil)
        (maf-save-stack "save the stack" nil)
        (maf-saved-stacks "saved stacks" nil)
        (maf-restore-stack "restore the stack" nil)
        (maf-list-modules "modules" nil)
        (maf-options "options" nil)
        (maf-formulas "formulas" nil)
        (maf-keys "key bindings" nil)
        (maf-history "history" nil)
        (maf-preview-show "preview" nil)
        (maf-pretty "typeset display" nil)
        (maf-toggle-simplify "toggle simplification" nil)
        (maf-reset "reset" nil)
        (maf-pi "pi" "=> 3.14159265359")
        (mafcmd-negate "flip the sign" "x = 2 => -x = -2")
        (mafcmd-collect-terms "collect a variable's terms" "2 x = x + 3 => x = 3")
        (mafcmd-substitute "substitute" "x + 1, x, y => y + 1")
        (maf-commute-left "move a term left" "a + b + c => b + a + c")
        (maf-commute-right "move a term right" "a + b + c => a + c + b")
        (maf-distribute "distribute inward" "2 (x + 1) => 2 x + 2")
        (maf-merge "merge outward" "2 x + 2 => 2 (x + 1)")
        (mafcmd-swap-vars "swap two variables" "a x + b y => b x + a y")
        (mafcmd-solve-for "solve for a variable" "2 x = 6, x => x = 3")
        (mafcmd-isolate "isolate" "2 x = 6 => x = 3")
        (mafcmd-auto-solve "solve, cycling variables" "x + y = 1 => x = 1 - y")
        (mafcmd-roots-for "roots for a variable" "x^2 = 4, x => [2, -2]")
        (maf-index "index vector" "5 => [1, 2, 3, 4, 5]")
        (mafcmd-fold "fold" "[1, 2, 3] by + => 6")
        (mafcmd-accum "accumulate" "[1, 2, 3] by + => [1, 3, 6]")
        (mafcmd-apply "apply elementwise" "[1, 4] by sqrt => [1, 2]")
        (mafcmd-outer "outer product" "[1, 2], [3, 4] by * => [[3, 4], [6, 8]]")
        (mafcmd-inner "inner product" "[1, 2], [3, 4] by + and * => 11")
        (mafcmd-map "map a formula" "[1, 2] by 2 x => [2, 4]")
        (mafcmd-map-stack "map the stack's formula" "[1, 2], 2 x => [2, 4]")
        (mafcmd-map-flag "map the next command" nil)
        (maf-dup-or-clear-selections "duplicate or clear selections" "3 => 3, 3")
        (maf-dup-here-or-clear-selections "duplicate, keeping point" "3 => 3, 3")
        (maf-recall-quick "recall a quick variable" nil)
        (maf-recall-previous "recall the previous entry" nil)
        (maf-recall-next "recall the next entry" nil)
        (maf-edit-entry-at-home "edit the top entry" nil)
        (maf-digit-start "start a number" nil)
        (maf-digit-commit-here "commit the number, keeping point" nil)
        (maf-digit-commit-contextual "commit the number into the formula" nil)
        (maf-digit-jump "jump to the entry typed" nil)
        (maf-digit-sqr "square the number typed" "3 : => 9")
        (maf-digit-mod-360 "wrap the number typed" "370 o => 10")
        (maf-digit-equal-to "equate with the number typed" "x, 2 e => x = 2")
        (maf-digit-pi "multiply the number typed by pi" "2 n => 2 pi")
        (maf-digit-colon "type a fraction colon" "1 ; 2 => 1:2")
        (maf-digit-quit "abort the number" nil)
        (maf-backward-char "backward character" nil)
        (maf-reset-settings "reset the settings" nil)
        (maf-plot-embed "plot the entry below Calc (H: the stack)" nil)
        (maf-plot-desmos "plot the entry in Desmos (H: the stack)" nil)
        (maf-plot-gnuplot "plot the entry in a gnuplot window (H: the stack)" nil)
        (maf-clear-selections "clear the selections" nil)
        (maf-dup-go "duplicate onto the top" nil)
        (maf-dup-here "duplicate, keeping point" nil)
        (maf-edit-add-entry-above "edit a new entry above" nil)
        (maf-edit-add-entry-below "edit a new entry below" nil)
        (maf-edit-add-vector "edit a new vector" nil)
        (maf-history-clear "clear the history" nil)
        (maf-restore-stack-from "restore a saved stack" nil)))

(dolist (row maf-keys-descriptions)
  (apply #'maf-set-command-doc row))

(defvar maf-keys--flag-routed
  '(mafcmd-mod-180 mafcmd-float-all mafcmd-frac mafcmd-float
    mafcmd-identify mafcmd-not-equal-to mafcmd-remove-nth-element)
  "Keyless commands reachable through I/H flags on a bound key.
The mafcmd table's :inv/:hyp/:invhyp links are read from
`maf-cmds--table', but a hand-written `maf-defcmd' bakes its
:inverse/:hyperbolic routes into the function body, where no render
can see them — so those variants are named here instead, to keep them
out of \"Unbound\", which they are not. A new hand-written variant
missed here costs one extra row there: visible, and an edit here.")

;;; The key index

(defvar maf-keys--unbound-title "Unbound (M-x only)"
  "Title of the trailing group of commands with no key.")

(defun maf-keys--key-norm (key)
  "KEY with its function-key event names folded onto the ASCII twins.
The registry declares some keys twice — TAB and <tab>, M-RET and
M-<return> — so both terminal and GUI frames get them; the buffer
shows one."
  (dolist (pair '(("<return>" . "RET") ("<tab>" . "TAB")
                  ("<backspace>" . "DEL")))
    (setq key (replace-regexp-in-string (regexp-quote (car pair))
                                        (cdr pair) key t t)))
  key)

(defun maf-keys--index-add (idx cmd key)
  "Record KEY as one of CMD's keys in IDX, unless a twin is already there."
  (when (and cmd (symbolp cmd))
    (let ((cur (gethash cmd idx))
          (norm (maf-keys--key-norm key)))
      (unless (seq-some (lambda (k) (equal (maf-keys--key-norm k) norm)) cur)
        (puthash cmd (append cur (list key)) idx)))))

(defun maf-keys--keymap-claims (map &optional prefix)
  "Every (KEY-DESCRIPTION . COMMAND) MAP binds, prefixes walked."
  (let (claims)
    (map-keymap
     (lambda (ev def)
       (let ((keys (vconcat prefix (vector ev))))
         (cond ((keymapp def)
                (setq claims (nconc claims
                                    (maf-keys--keymap-claims def keys))))
               ((commandp def)
                (push (cons (key-description keys) def) claims)))))
     map)
    (nreverse claims)))

(defun maf-keys--index ()
  "Hash COMMAND -> its display keys in the active profile, in order.
Reads the registry live: the profile's effective defaults minus its
suppressions, every module's claims on the profile — a disabled
module's marked [off] — the escape map's way back in, and the
digit-entry overrides."
  (let ((idx (make-hash-table :test #'eq)))
    ;; The profile's defaults. ignore-errors: with no profile
    ;; registered (a bare module load) the buffer still renders,
    ;; everything filing under Unbound.
    (ignore-errors
      (let ((suppressed (plist-get (maf-bindings--profile
                                    maf-bindings-profile)
                                   :suppressed)))
        (dolist (claim (maf-bindings--effective-defaults
                        maf-bindings-profile))
          (unless (maf-bindings--suppressed-p (car claim) suppressed)
            (maf-keys--index-add idx (cdr claim) (car claim))))))
    ;; Module claims, disabled modules' keys marked rather than hidden:
    ;; the key is one module toggle away, and the buffer saying nothing
    ;; would file the command under Unbound, which is not where it is.
    (dolist (m maf-bindings--modules)
      (let* ((entry (cdr m))
             (on (and (boundp (plist-get entry :mode))
                      (symbol-value (plist-get entry :mode)))))
        (dolist (spec (plist-get entry :keys))
          (pcase-let ((`(,profiles ,key ,cmd) spec))
            (when (or (eq profiles :all)
                      (memq maf-bindings-profile profiles))
              (maf-keys--index-add idx cmd
                                   (if on key (concat key " [off]"))))))))
    ;; The escape map: the keys that exist whatever the binding state.
    (dolist (claim (maf-keys--keymap-claims maf-bindings-escape-map))
      (maf-keys--index-add idx (cdr claim) (car claim)))
    ;; The digit-entry overrides, live only while typing a number; the
    ;; "Digit entry" group says so where the keys alone could not.
    (pcase-dolist (`(,key ,cmd ,_expected) maf-bindings--digit)
      (maf-keys--index-add idx cmd key))
    idx))

(defun maf-keys--reachable (idx)
  "Hash of the keyless commands the I/H flags reach from a bound key.
The mafcmd table's variant links, taken only from rows whose base
command has a key in IDX, plus the hand-written routes named in
`maf-keys--flag-routed'."
  (let ((reach (make-hash-table :test #'eq)))
    (dolist (cmd maf-keys--flag-routed)
      (puthash cmd t reach))
    (when (boundp 'maf-cmds--table)
      (dolist (row maf-cmds--table)
        (when (gethash (car row) idx)
          (dolist (v (nthcdr 4 row))
            (when v (puthash v t reach))))))
    reach))

(defun maf-keys--groups ()
  "Compile the render's group list: (TITLE (COMMAND . KEYS)...).
`maf-keys-groups' in its own order, then \"Other\" (bound, unlisted),
then \"Unbound\" (listed or swept up, no key, no flag route). KEYS is
nil throughout the Unbound group."
  (let* ((idx (maf-keys--index))
         (reach (maf-keys--reachable idx))
         (claimed (make-hash-table :test #'eq))
         groups unbound)
    (dolist (g maf-keys-groups)
      (let (items)
        (dolist (cmd (cdr g))
          (when (fboundp cmd)
            (puthash cmd t claimed)
            (cond ((gethash cmd idx)
                   (push (cons cmd (gethash cmd idx)) items))
                  ((not (gethash cmd reach))
                   (push cmd unbound)))))
        (when items
          (setq groups (nconc groups
                              (list (cons (car g) (nreverse items))))))))
    (let (other)
      (maphash (lambda (cmd keys)
                 (unless (gethash cmd claimed)
                   (push (cons cmd keys) other)))
               idx)
      (when other
        (setq groups
              (nconc groups
                     (list (cons "Other"
                                 (sort other
                                       (lambda (a b)
                                         (string< (car a) (car b))))))))))
    ;; Sweep the mafcmd- namespace for what no group lists; the maf-
    ;; namespace is not swept — it holds every module's own buffer
    ;; commands, which have keys of their own elsewhere — so a
    ;; keyless maf- stack command reaches Unbound by being listed in a
    ;; group above. Double-dashed internals stay out.
    (mapatoms
     (lambda (s)
       (let ((name (symbol-name s)))
         (when (and (commandp s)
                    (string-prefix-p "mafcmd-" name)
                    (not (string-prefix-p "mafcmd--" name))
                    (not (gethash s idx))
                    (not (gethash s reach))
                    (not (gethash s claimed)))
           (push s unbound)))))
    (when unbound
      (setq groups
            (nconc groups
                   (list (cons maf-keys--unbound-title
                               (mapcar #'list
                                       (sort (delete-dups unbound)
                                             #'string<)))))))
    groups))

(defun maf-keys--doc (cmd)
  "CMD's docstring first line, the item's one-line description."
  (let ((doc (ignore-errors (documentation cmd t))))
    (if (and doc (not (string-empty-p doc)))
        (let ((line (car (split-string doc "\n"))))
          (if (fboundp 'substitute-quotes) (substitute-quotes line) line))
      "Not documented.")))

;;; The menu

(defun maf-keys--title (cmd)
  "CMD's proper name, capitalized for the head, or nil when it has none.
The first letter only, as the formula menu capitalizes its own
derived titles: a name is written lowercase where it is declared —
\"greatest common divisor\" — because it is a phrase, and only the
line it heads makes it a heading."
  (when-let ((title (maf-command-title cmd)))
    (concat (upcase (substring title 0 1)) (substring title 1))))

(defun maf-keys--row (item _ctx)
  "ITEM's entry: the command headed by its name and keys, then its text.
ITEM is (COMMAND . KEYS), KEYS nil throughout the Unbound group. The
head reads

  Power (^) ... (mafcmd-pow)

— the proper name and the keys it answers, then the symbol
they run — over the
command's example and the first line of its docstring. The name and
the example are what the command carries (`maf-command-title',
`maf-command-example'); a command carrying neither shows neither, and
its entry is the head over the description alone.

A blank line closes the row: an entry runs to several lines here, and
run together the list reads as one block rather than as its commands."
  (let* ((cmd (car item)) (keys (cdr item))
         (title (maf-keys--title cmd))
         (example (maf-command-example cmd)))
    (concat "  "
            (when title (propertize title 'face 'maf-keys-title))
            (when keys
              (concat " ("
                      (mapconcat (lambda (k)
                                   (propertize k 'face 'maf-keys-binding))
                                 keys ", ")
                      ")"))
            (when (or title keys) (propertize " ... " 'face 'shadow))
            "(" (propertize (symbol-name cmd) 'face 'maf-keys-command) ")"
            (when example
              (concat "\n    "
                      (propertize example 'face 'maf-keys-example)))
            "\n    "
            (propertize (maf-keys--doc (car item)) 'face 'maf-keys-doc)
            ;; Two: the first ends the doc line — the shell only
            ;; terminates a row that left one open — and the second is
            ;; the blank.
            "\n\n")))

(defun maf-keys--fields (item group)
  "What the filter matches for ITEM: its names, text, GROUP and keys.
The proper name is searched beside the symbol, so the word a command
is known by finds it — \"power\" reaches mafcmd-pow, which spells it
nowhere else."
  (append (list (symbol-name (car item))
                (or (maf-command-title (car item)) "")
                (or (maf-command-example (car item)) "")
                (maf-keys--doc (car item))
                group)
          (cdr item)))

(defun maf-keys--detail (item _width)
  "The detail pane's text for ITEM: the command's full documentation.
The same head the row wears — the command beside its keys — over the
whole docstring, where the row shows only its first line. Flush left
from the first line: a docstring already carries its own layout, and
the pane adds no margin of its own."
  (let* ((cmd (car item)) (keys (cdr item))
         (title (maf-keys--title cmd))
         (example (maf-command-example cmd))
         (doc (or (ignore-errors (documentation cmd))
                  "Not documented.")))
    (concat
     (when title (propertize title 'face 'maf-keys-title))
     (when keys
       (concat " ("
               (mapconcat (lambda (k)
                            (propertize k 'face 'maf-keys-binding))
                          keys ", ")
               ")"))
     (when (or title keys) (propertize " ... " 'face 'shadow))
     "(" (propertize (symbol-name cmd) 'face 'maf-keys-command) ")"
     (when example
       (concat "\n" (propertize example 'face 'maf-keys-example)))
     "\n\n" doc "\n")))

(defun maf-keys--describe (item)
  "Describe ITEM's command, selecting its help buffer.
The RET action: where the detail pane is a glance, this is the full
help buffer, its links live, for reading and following on."
  (describe-function (car item))
  (pop-to-buffer (help-buffer)))

(defun maf-keys--config ()
  "The filter-view CONFIG the bindings help buffer opens with.
One place for the open command and a test to share; see filter-view's
commentary for what each key means."
  (list :name "maf-keys"
        :select-verb "describes"
        :groups #'maf-keys--groups
        :render #'maf-keys--row
        ;; The entries are two lines apiece with a blank between, so
        ;; a header run straight into the first of them would read as
        ;; one more command.
        :group-blank t
        :key #'car
        :title (lambda (item) (symbol-name (car item)))
        :fields #'maf-keys--fields
        :select #'maf-keys--describe
        :detail #'maf-keys--detail
        ;; Borrow a window if the frame has one to lend, as the
        ;; formula menu's pane does.
        :detail-actions '(display-buffer-reuse-window
                          maf--display-borrowing-window
                          display-buffer-in-direction)
        ;; Closed until asked for: the rows already carry a line of
        ;; description each, so a pane following by default would
        ;; mostly repeat the list beside itself.
        :pane-default nil
        ;; A function, so the defcustom is consulted live.
        :recent-max (lambda () maf-keys-recent-max)))

;;;###autoload
(defun maf-keys ()
  "Show maf's key bindings, organized by group.
If the buffer is already on screen, go to its window and re-read the
registry there, so the keys shown are the keys in force. The buffer
is a filter-view; see `filter-view-mode' for the keys.
\\<filter-view-mode-map>\\[filter-view-select] describes the command
at point in the help buffer — on a group header it narrows to that
group. \\[filter-view-show-detail] shows the full documentation in
the detail pane instead, \\[filter-view-filter] filters as you type,
\\[filter-view-refresh] re-reads the bindings registry."
  (interactive)
  (let ((shown (get-buffer-window "*maf-keys*" 0)))
    (apply #'filter-view-open "*maf-keys*" (maf-keys--config))
    (when shown (filter-view-refresh))))

;;; The module

;;;###autoload
(define-minor-mode maf-use-keys-mode
  "Add the bindings help buffer to Calc.

Press l b to open *maf-keys*. Every key maf binds in the active
profile is listed there, organized by subject, each command with a
one-line description; the commands with no key close the list. RET
shows a command's full documentation, and / filters the list as you
type.

The buffer itself works whether or not this mode is on; the mode is
the module's toggle, owning the key. You can still open the menu
with M-x maf-keys."
  :global t
  :group 'maf
  (maf-bindings--refresh))

(maf-bindings-module-keys 'maf-keys 'maf-use-keys-mode
  ;; Not vim: `l' is `forward-char' there, so it cannot take a
  ;; prefix — the registry refuses the claim rather than shadowing
  ;; the motion. That profile reaches the buffer by name for now.
  '(((calc native) "l b" maf-keys)))

(defun maf-keys--module-values ()
  "The module row's dial overrides: a single [show] action, no toggle.
The minor mode is real — it owns the l b claim — but on and off
is not what the row is for: what anyone wants from the module menu is
the buffer itself. So the row is :inert, carrying one action, show:
stepping the row (TAB/SPC) and RET (the menu's :ret) both run it, and
the chip stays in the shadowed face — an action has no live state to
wear the purple, or to move off a default into the gold."
  (list :values '((show "show" (maf-keys)))
        :inert t
        :ret '(maf-keys)))

(when (require 'maf-module nil t)
  (maf-register-module 'maf-keys #'maf-use-keys-mode
                       "Browse maf's key bindings, organized by group.

Press l b to open the list: every key in the active profile
beside its command and a one-line description, the unbound commands
at the end. RET describes the command at point; / filters, TAB
folds."
                       "l b" "Help"
                       #'maf-keys--module-values))

(provide 'maf-keys)
