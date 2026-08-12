;; -*- lexical-binding: t; -*-
;;
;; modules/maf-options.el
;;
;; The omni options menu. Calc's settings are spread over six prefix
;; maps — `m' and `d' mostly, but also `p', `b w', `v'/`V', `j d', `u
;; a', `g N' — across some ninety key bindings that collapse to around
;; forty actual options: fifteen of those bindings are the one
;; display-language setting, six are the one simplification setting,
;; four the one radix. This module puts the options in a single buffer
;; showing each one's current value, so a setting can be found by
;; reading rather than recalled by key.
;;
;; Two halves:
;;
;;  - `maf-options-registry', a hand-written table of option specs. It
;;    has to be hand-written. Calc's `calc-mode-var-list' names all
;;    sixty-nine mode variables and their defaults, but carries no
;;    label, type, domain or owning command, and includes internals
;;    (`math-2-word-size', `calc-user-parse-tables') that are not
;;    settings at all. The registry supplies what that list lacks; the
;;    list still supplies the defaults, which is how `d' below knows
;;    what to reset to.
;;
;;  - `maf-options', a tabulated-list buffer over the registry, in the
;;    shape of the module menu in core/maf-module.el.
;;
;; Two rules the setters follow, both learned the hard way:
;;
;;  - Never assign the variable. Every setter runs calc's own command,
;;    which is what invalidates caches, redraws the stack, updates the
;;    mode line and records to the trail. A bare `setq' of, say,
;;    `calc-internal-prec' leaves the display stale and the caches
;;    wrong.
;;
;;  - Always run it with a calc buffer current. Calling a calc mode
;;    command from another buffer signals no error — the mode variables
;;    are buffer-local in the calc buffer, so the command quietly
;;    creates a local binding wherever it ran and leaves calc itself
;;    untouched. `maf-options--set' is the only entry point for that
;;    reason.
;;
;; Seven groups: Numbers, Algebra, Display, Formats, Vectors, Binary,
;; Selection, Session. What is deliberately left out, and why, is at
;; the foot of this file.

(require 'calc)
(require 'calc-ext)                     ; calc-mode-var-list
(require 'tabulated-list)
(require 'maf-conf "conf")              ; the `maf' customize group

(defface maf-options-value
  ;; Both halves pinned, and pinned against each other rather than
  ;; against the theme: the live value is the one thing in the buffer
  ;; worth finding at a glance, so it is the one place that takes a
  ;; contrast rather than a shade. Dark enough to carry white, so it
  ;; reads the same under either theme.
  ;;
  ;; One face for every live value, whether or not the setting has
  ;; moved: which value is the default is the underline the row carries
  ;; (see `maf-options--value-face'), and a second colour on that second
  ;; axis would read as a third state.
  '((((class color)) :background "#553280" :foreground "white")
    (t :inverse-video t))
  "Face for the value a setting is currently on.
The other values a setting can take are shadowed beside it, so this
face is what picks the live one out of the row."
  :group 'maf)

(defface maf-options-controls
  ;; Dark and drained where the live value is saturated: the band
  ;; should read as chrome above the list, not as another row in it.
  ;; Extends, so it runs the width of the window.
  '((((class color) (background dark))  :background "#1c2733" :extend t)
    (((class color) (background light)) :background "#e2eaf3" :extend t)
    (t :inverse-video t))
  "Face for the controls line above the options list."
  :group 'maf)

(defface maf-options-selection
  ;; `:box' would be the obvious outline and is what a graphical frame
  ;; gets. A terminal ignores it entirely, so the outline there has to
  ;; be characters — see `maf-options--outline'. Bold under both, since
  ;; it is the one attribute neither the highlight nor the default's
  ;; underline is using, and so stacks on either.
  '((((type graphic)) :box (:line-width -1) :weight bold)
    (t :weight bold))
  "Face for a value stepped onto but still waiting for its input.
See `maf-options--pending'."
  :group 'maf)

(defcustom maf-options-outline '("[" . "]")
  "Characters drawn around a value that is waiting for input.
A terminal cannot render the `:box' of `maf-options-selection', so the
outline is drawn rather than styled. Set to nil on a graphical frame,
where the box is real."
  :type '(choice (const :tag "None — rely on the face's box" nil)
                 (cons (string :tag "Before") (string :tag "After")))
  :group 'maf)

;; Loaded lazily by calc; the setters below name them directly.
(declare-function calc-degrees-mode "calc-mode")
(declare-function calc-radians-mode "calc-mode")
(declare-function calc-hms-mode "calc-mode")
(declare-function calc-symbolic-mode "calc-mode")
(declare-function calc-infinite-mode "calc-mode")
(declare-function calc-frac-mode "calc-frac")
(declare-function calc-precision "calc-ext")
(declare-function calc-total-algebraic-mode "calc-mode")
(declare-function calc-matrix-mode "calc-mode")
(declare-function calc-auto-recompute "calc-mode")
(declare-function calc-vector-brackets "calc-vec")
(declare-function calc-vector-braces "calc-vec")
(declare-function calc-vector-parens "calc-vec")
(declare-function calc-word-size "calc-bin")
(declare-function calc-working "calc-mode")
(declare-function calc-auto-why "calc-mode")
(declare-function calc-mode-record-mode "calc-mode")
(declare-function calc-toggle-banner "calc-ext")
(declare-function calc-save-modes "calc-mode")

;;; The registry

;; Each entry is (VAR . SPEC), where VAR is the calc variable holding
;; the setting — also the key into `calc-mode-var-list' for its default
;; — and SPEC a plist:
;;
;;   :group   Section heading. Rows print in registry order, so an
;;            entry's group is decided by where it sits in the table.
;;   :label   Name shown in the Option column.
;;   :keys    Calc's own key(s) for the setting, shown in the Keys
;;            column. Informational: the menu never presses them, and
;;            they stay meaningful if maf later takes the prefix over.
;;   :doc     One line, echoed when point rests on the row.
;;   :values  ((VALUE LABEL SETTER) ...) for an option with a fixed
;;            domain. VALUE is what VAR holds when the option is set
;;            that way; SETTER is a form putting calc there, evaluated
;;            by `maf-options--set' with the calc buffer current.
;;   :flag    COMMAND, for a plain on/off option, in place of :values:
;;            the two entries are synthesized. See
;;            `maf-options--set-flag' for why this is not just
;;            shorthand.
;;   :read    Setter form that prompts for a value, for options whose
;;            domain is open (a precision, a radix, a character). May
;;            appear alongside :values, where the values are the common
;;            choices and :read reaches the rest.
;;   :current Function mapping VAR's raw value to the VALUE matched
;;            against :values. For settings calc stores decomposed —
;;            `calc-float-format' is (fix 3), not `fix'.
;;   :show    Function rendering VAR's raw value for the Value column,
;;            when the matched :values label does not say enough.
;;   :vars    Other variables the row speaks for, when calc spreads one
;;            setting over more than one. They count towards whether
;;            the row has moved off its default.
;;   :default The value key the row starts on, for a row whose default
;;            cannot be derived — see `maf-options--default-value'.
;;   :reset   Setter form putting the row back to its default, for the
;;            few settings whose command does more than the generic
;;            reset can — see `maf-options-reset'.
;;
;; A setter is a form rather than a command name because calc's own
;; commands do not uniformly take a value. Some are one command per
;; value (three for the angle modes), some take a numeric argument
;; naming the value (`calc-working' 0/1/2), some are toggles that only
;; flip (`calc-algebraic-mode'), and reaching a definite value through
;; a toggle takes a conditional — see `maf-options--set-algebraic'.

(defvar maf-options-registry nil
  "Table of calc settings the options menu offers.
Each entry is (VAR . SPEC); see this file's commentary for SPEC's keys
and for why the setters are forms rather than command names.")

;; Filled outside the defvar, as the keymap below is, so reloading the
;; file applies edits to the table rather than leaving the value bound
;; from the first load.
(setq maf-options-registry
  `(;;; Numbers
    (calc-angle-mode
     :group "Numbers" :label "Angle measure" :keys "m d/r/h"
     :doc "Units trigonometric functions read and produce."
     ;; `calc-degrees-mode' takes a numeric prefix, not a raw one, and
     ;; errors on anything but 1, 2 or 3 — the sibling commands its 2
     ;; and 3 delegate to.
     :values ((deg "degrees" (calc-degrees-mode 1))
              (rad "radians" (calc-radians-mode))
              (hms "HMS"     (calc-hms-mode))))

    (calc-internal-prec
     :group "Numbers" :label "Precision" :keys "p"
     :doc "Significant digits kept in floating-point results."
     :read (call-interactively #'calc-precision))

    (calc-prefer-frac
     :group "Numbers" :label "Fraction mode" :keys "m f"
     :doc "Leave integer quotients as fractions rather than floats."
     :flag calc-frac-mode)

    (calc-symbolic-mode
     :group "Numbers" :label "Symbolic mode" :keys "m s"
     :doc "Defer inexact results like sqrt(2) in symbolic form."
     :flag calc-symbolic-mode)

    (calc-infinite-mode
     :group "Numbers" :label "Infinite mode" :keys "m i"
     :doc "Let 1/0 produce an infinity instead of an error."
     :flag calc-infinite-mode)

    (calc-complex-mode
     :group "Numbers" :label "Complex form" :keys "m p"
     :doc "Form complex results are given in."
     :values ((cplx  "rectangular" (calc-polar-mode 0))
              (polar "polar"       (calc-polar-mode 1))))

    ;;; Algebra
    (calc-simplify-mode
     :group "Algebra" :label "Simplification" :keys "m O/N/I/B/A/E/U"
     :doc "How far results are simplified automatically."
     :values ((none   "none"      (calc-no-simplify-mode t))
              (num    "numeric"   (calc-num-simplify-mode t))
              (nil    "basic"     (calc-basic-simplify-mode t))
              (binary "binary"    (calc-bin-simplify-mode t))
              (alg    "algebraic" (calc-alg-simplify-mode t))
              (ext    "extended"  (calc-ext-simplify-mode t))
              (units  "units"     (calc-units-simplify-mode t))))

    (calc-algebraic-mode
     :group "Algebra" :label "Algebraic entry" :keys "m a, m t"
     :doc "Whether digit keys start an algebraic entry."
     :values ((nil        "off"        (maf-options--set-algebraic nil))
              (t          "partial"    (maf-options--set-algebraic t))
              (incomplete "incomplete" (maf-options--set-algebraic 'incomplete))
              (total      "total"      (maf-options--set-algebraic 'total)))
     ;; Two variables, one setting: incomplete mode is its own flag
     ;; alongside `calc-algebraic-mode', and the two are never both on.
     ;; :vars names the second so the row counts as moved when it is the
     ;; one that moved, and :default states what deriving cannot reach —
     ;; this :current reads a live variable, so applied to a default it
     ;; would answer with the present.
     :vars (calc-incomplete-algebraic-mode)
     :default nil
     ;; Read through `maf-options--raw': the rows are built with the
     ;; options buffer current, and the mode variables are local to
     ;; calc's.
     :current ,(lambda (raw)
                 (if (and (null raw)
                          (maf-options--raw 'calc-incomplete-algebraic-mode))
                     'incomplete
                   raw)))

    (calc-matrix-mode
     :group "Algebra" :label "Matrix mode" :keys "m v"
     :doc "Whether unknown variables are assumed matrices or scalars."
     :values ((nil      "unknown"        (calc-matrix-mode -1))
              (matrix   "matrix"         (calc-matrix-mode -2))
              (sqmatrix "square matrix"  (calc-matrix-mode '(4)))
              (scalar   "scalar"         (calc-matrix-mode 0)))
     ;; A positive prefix sets a dimension instead, which no fixed
     ;; value names; show the number when calc holds one.
     :show ,(lambda (raw) (when (integerp raw) (format "%dx%d matrix" raw raw))))

    (calc-auto-recompute
     :group "Algebra" :label "Auto-recompute" :keys "m C"
     :doc "Recompute => formulas when a variable they use changes."
     :flag calc-auto-recompute)

    ;;; Display
    (calc-number-radix
     :group "Display" :label "Radix" :keys "d 0/2/8/6, d r"
     :doc "Base numbers are displayed in."
     :values ((10 "decimal"     (calc-decimal-radix))
              (2  "binary"      (calc-binary-radix))
              (8  "octal"       (calc-octal-radix))
              (16 "hexadecimal" (calc-hex-radix)))
     :read (call-interactively #'calc-radix)
     :show ,(lambda (raw) (unless (memq raw '(10 2 8 16)) (format "base %d" raw))))

    (calc-float-format
     :group "Display" :label "Float format" :keys "d n/f/s/e"
     :doc "Notation floating-point numbers print in."
     :values ((float "normal"      (calc-normal-notation nil))
              (fix   "fixed point" (call-interactively #'calc-fix-notation))
              (sci   "scientific"  (calc-sci-notation nil))
              (eng   "engineering" (calc-eng-notation nil)))
     ;; Stored as (STYLE DIGITS), with 0 digits meaning "as many as
     ;; the precision allows".
     :current ,#'car
     :show ,(lambda (raw)
              (unless (zerop (nth 1 raw))
                (format "%s %d"
                        (pcase (car raw)
                          ('float "normal") ('fix "fixed point")
                          ('sci "scientific") ('eng "engineering"))
                        (nth 1 raw)))))

    (calc-group-digits
     :group "Display" :label "Digit grouping" :keys "d g"
     :doc "Separate long numbers into groups of digits."
     :flag calc-group-digits
     ;; A positive prefix sets the group size rather than turning
     ;; grouping on, so the variable can hold a number.
     :show ,(lambda (raw) (when (integerp raw) (format "groups of %d" raw))))

    (calc-leading-zeros
     :group "Display" :label "Leading zeros" :keys "d z"
     :doc "Pad numbers to the current word size with leading zeros."
     :flag calc-leading-zeros)

    (calc-line-numbering
     :group "Display" :label "Line numbers" :keys "d l"
     :doc "Show the stack level at the left of each entry."
     :flag calc-line-numbering)

    (calc-line-breaking
     :group "Display" :label "Line breaking" :keys "d b"
     :doc "Wrap entries too wide for the window."
     :flag calc-line-breaking
     ;; As with grouping, a prefix sets the width to break at.
     :show ,(lambda (raw) (when (integerp raw) (format "at %d columns" raw))))

    (calc-display-just
     :group "Display" :label "Justification" :keys "d </=/>"
     :doc "Where entries sit in the calc window."
     :values ((nil    "left"   (calc-left-justify nil))
              (center "center" (calc-center-justify nil))
              (right  "right"  (calc-right-justify nil))))

    (calc-point-char
     :group "Display" :label "Decimal point" :keys "d ."
     :doc "Character printed as the decimal point."
     :read (call-interactively #'calc-point-char))

    (calc-display-strings
     :group "Display" :label "Strings" :keys "d \""
     :doc "Print vectors of character codes as strings."
     :flag calc-display-strings)

    (calc-display-raw
     :group "Display" :label "Raw display" :keys "d '"
     :doc "Print calc's internal form of an entry instead of the entry."
     :flag calc-display-raw)

    (calc-language
     :group "Display" :label "Language" :keys "d N/B/C/… (15 keys)"
     :doc "Notation entries are parsed and printed in."
     :values ((nil     "normal"        (calc-normal-language))
              (flat    "flat"          (calc-flat-language))
              (big     "big"           (calc-big-language))
              (unform  "unformatted"   (calc-unformatted-language))
              (c       "C"             (calc-c-language))
              ;; The five languages with a variant (Pascal's hex
              ;; syntax, TeX's math delimiters) take an argument
              ;; choosing it; nil is the plain form.
              (pascal  "Pascal"        (calc-pascal-language nil))
              (fortran "FORTRAN"       (calc-fortran-language nil))
              (tex     "TeX"           (calc-tex-language nil))
              (latex   "LaTeX"         (calc-latex-language nil))
              (eqn     "eqn"           (calc-eqn-language nil))
              (yacas   "Yacas"         (calc-yacas-language))
              (maxima  "Maxima"        (calc-maxima-language))
              (giac    "Giac"          (calc-giac-language))
              (math    "Mathematica"   (calc-mathematica-language))
              (maple   "Maple"         (calc-maple-language))))

    ;;; Formats
    (calc-complex-format
     :group "Formats" :label "Complex numbers" :keys "d c/i/j"
     :doc "Notation complex numbers print in."
     :values ((nil "(x,y)" (calc-complex-notation))
              (i   "x+yi"  (calc-i-notation))
              (j   "x+yj"  (calc-j-notation))))

    (calc-frac-format
     :group "Formats" :label "Fractions" :keys "d o"
     :doc "Separator between a fraction's numerator and denominator."
     :read (call-interactively #'calc-over-notation)
     :show ,(lambda (raw) (format "%s%s" (car raw) (if (nth 1 raw) " (:/)" ""))))

    (calc-hms-format
     :group "Formats" :label "HMS" :keys "d h"
     :doc "Layout of hours-minutes-seconds forms."
     :read (call-interactively #'calc-hms-notation)
     ;; `calc-hms-notation' mirrors the format into the global value as
     ;; well, for the minibuffer's benefit, so putting only the calc
     ;; buffer's copy back would leave a new calc buffer inheriting the
     ;; format this was undoing. Reset through the command instead.
     :reset (calc-hms-notation "@ ' \""))

    (calc-date-format
     :group "Formats" :label "Dates" :keys "d d"
     :doc "Layout of date forms."
     :read (call-interactively #'calc-date-notation)
     ;; Held as a tree of format codes, not the string that was typed,
     ;; and calc has no inverse of its parser. Flattening the tree
     ;; recovers the codes in order, which is the readable form bar the
     ;; brackets around an optional part.
     :show ,(lambda (raw)
              (mapconcat (lambda (part) (format "%s" part))
                         (flatten-tree raw) "")))

    (calc-group-char
     :group "Formats" :label "Group separator" :keys "d ,"
     :doc "Character separating groups of digits."
     :read (call-interactively #'calc-group-char))

    (calc-left-label
     :group "Formats" :label "Left label" :keys "d {"
     :doc "Text printed to the left of every stack entry."
     :read (call-interactively #'calc-left-label)
     :show ,(lambda (raw) (if (equal raw "") "none" raw)))

    (calc-right-label
     :group "Formats" :label "Right label" :keys "d }"
     :doc "Text printed to the right of every stack entry."
     :read (call-interactively #'calc-right-label)
     :show ,(lambda (raw) (if (equal raw "") "none" raw)))

    ;;; Vectors
    (calc-vector-brackets
     :group "Vectors" :label "Vector brackets" :keys "v [/{/("
     :doc "Delimiters printed around a vector."
     :values ((\[\] "[ ]"  (maf-options--set-vector-brackets "[]"))
              ({}   "{ }"  (maf-options--set-vector-brackets "{}"))
              (\(\) "( )"  (maf-options--set-vector-brackets "()"))
              (nil  "none" (maf-options--set-vector-brackets nil)))
     ;; The setting holds a string, so the keys above are only names
     ;; for the three calc has commands for — symbols, since `assq'
     ;; would never find a string one. Any other string calc has been
     ;; left holding is passed through to match no key at all, rather
     ;; than falling to nil and lighting "none".
     :current ,(lambda (raw)
                 (pcase raw ("[]" '\[\]) ("{}" '{}) ("()" '\(\)) (_ raw))))

    (calc-vector-commas
     :group "Vectors" :label "Vector commas" :keys "v ,"
     :doc "Separate vector elements with commas rather than spaces."
     :flag calc-vector-commas)

    (calc-full-vectors
     :group "Vectors" :label "Long vectors" :keys "v ."
     :doc "Print long vectors in full rather than abbreviated."
     :flag calc-full-vectors)

    (calc-break-vectors
     :group "Vectors" :label "One per line" :keys "v /"
     :doc "Print each vector element on its own line."
     :flag calc-break-vectors)

    (calc-full-trail-vectors
     :group "Vectors" :label "Trail vectors" :keys ""
     :doc "Record long vectors in the trail in full."
     :flag calc-full-trail-vectors)

    (calc-matrix-just
     :group "Vectors" :label "Matrix columns" :keys "v </=/>"
     :doc "How matrix elements sit within their column."
     :values ((nil    "left"   (calc-matrix-left-justify))
              (center "center" (calc-matrix-center-justify))
              (right  "right"  (calc-matrix-right-justify))))

    (calc-matrix-brackets
     :group "Vectors" :label "Matrix brackets" :keys "v ]"
     :doc "Which brackets a matrix prints: rows, outer, commas."
     :read (call-interactively #'calc-matrix-brackets)
     :show ,(lambda (raw) (if raw (mapconcat #'symbol-name raw " ") "none")))

    ;;; Binary
    (calc-word-size
     :group "Binary" :label "Word size" :keys "b w"
     :doc "Bits the binary operations work in."
     :values ((8  "8"  (calc-word-size 8))
              (16 "16" (calc-word-size 16))
              (32 "32" (calc-word-size 32))
              (64 "64" (calc-word-size 64)))
     :read (call-interactively #'calc-word-size)
     :show ,(lambda (raw) (unless (memq raw '(8 16 32 64)) (format "%d" raw))))

    (calc-twos-complement-mode
     :group "Binary" :label "Two's complement" :keys ""
     :doc "Print negative binary numbers in two's complement."
     :values ((t   "on"  (maf-options--change 'calc-twos-complement-mode t))
              (nil "off" (maf-options--change 'calc-twos-complement-mode nil))))

    ;;; Selection
    (calc-show-selections
     :group "Selection" :label "Show selection" :keys "j d"
     :doc "Highlight the selected sub-formula rather than the rest."
     :flag calc-show-selections)

    (calc-assoc-selections
     :group "Selection" :label "Associative" :keys ""
     :doc "Let a selection cover a whole run of the same operator."
     :values ((t   "on"  (maf-options--change 'calc-assoc-selections t))
              (nil "off" (maf-options--change 'calc-assoc-selections nil))))

    ;;; Session
    (calc-display-working-message
     :group "Session" :label "Working message" :keys "m w"
     :doc "Report progress while a long computation runs."
     :values ((nil  "off"      (calc-working 0))
              (t    "brief"    (calc-working 1))
              (lots "detailed" (calc-working 2))))

    (calc-auto-why
     :group "Session" :label "Explain results" :keys "d w"
     :doc "Say why a result was left unsimplified."
     :values ((nil "never"     (calc-auto-why 0))
              (1   "sometimes" (calc-auto-why 1))
              (t   "always"    (calc-auto-why 2)))
     ;; Anything non-nil short of t is the middle state, and the
     ;; default calc ships is spelled `maybe' rather than 1.
     :current ,(lambda (raw) (cond ((null raw) nil) ((eq raw t) t) (t 1))))

    (calc-display-trail
     :group "Session" :label "Trail window" :keys ""
     :doc "Show the trail beside the stack."
     :values ((t   "on"  (maf-options--set-trail t))
              (nil "off" (maf-options--set-trail nil))))

    (calc-show-banner
     :group "Session" :label "Banner" :keys "d @"
     :doc "Show the greeting above the stack."
     :flag calc-toggle-banner)

    (calc-window-height
     :group "Session" :label "Window height" :keys ""
     :doc "Lines the calc window opens with."
     :read (maf-options--change
            'calc-window-height
            (read-number "Calc window height: " calc-window-height)))

    (calc-shift-prefix
     :group "Session" :label "Shifted prefixes" :keys "m S"
     :doc "Let a shifted letter stand in for its prefix key."
     :flag calc-shift-prefix)

    (calc-always-load-extensions
     :group "Session" :label "Load extensions" :keys "m x"
     :doc "Load calc's extensions at startup rather than on demand."
     :flag calc-always-load-extensions)

    (calc-autorange-units
     :group "Session" :label "Autorange units" :keys "u a"
     :doc "Move a unit to the prefix that keeps its number readable."
     :flag calc-autorange-units)

    (calc-mode-save-mode
     :group "Session" :label "Record modes" :keys "m R"
     :doc "Where a mode change is written down, if anywhere."
     :values ((nil    "nowhere"  (calc-mode-record-mode 0))
              (local  "local"    (calc-mode-record-mode 1))
              (edit   "edit"     (calc-mode-record-mode 2))
              (perm   "perm"     (calc-mode-record-mode 3))
              (global "global"   (calc-mode-record-mode 4))
              (save   "settings" (calc-mode-record-mode 5))))))

;;; Reading and setting

(defvar-local maf-options--calc-buffer nil
  "The calc buffer this options buffer reads and sets.")

(defun maf-options--calc-buffer ()
  "Return the calc buffer the menu acts on, or signal.
The buffer the menu was opened from when that was a calc buffer,
recorded at open time, so a second calc buffer is not silently
mistaken for the first."
  (or (and (buffer-live-p maf-options--calc-buffer) maf-options--calc-buffer)
      (get-buffer "*Calculator*")
      (user-error "No calc buffer")))

(defun maf-options--raw (var)
  "Return VAR's value in the calc buffer.
Most calc mode variables are buffer-local there, so reading them
anywhere else gets the global default rather than what calc is using."
  (buffer-local-value var (maf-options--calc-buffer)))

(defun maf-options--set (form)
  "Evaluate setter FORM with the calc buffer current.
Calc's mode commands are only correct there: run elsewhere they signal
nothing and set a local binding in the wrong buffer."
  (with-current-buffer (maf-options--calc-buffer)
    (eval form t)))

(defun maf-options--set-flag (var command on)
  "Turn the on/off setting VAR ON, by toggling it with COMMAND.
COMMAND is called with nil, the argument every calc mode command reads
as \"flip this\". It is never called with a number, because a number
does not uniformly mean on: `calc-symbolic-mode' reads 1 as on, but
`calc-group-digits' reads it as \"group in ones\" and
`calc-line-breaking' as \"break at column 1\". Toggling from the value
we can see is the one form that means the same thing for all of them,
and it saves the registry from recording each command's reading of a
prefix.

Some of these commands take no argument at all — `calc-toggle-banner'
and `calc-vector-commas' only ever flip — so the nil is passed only
where there is somewhere to put it."
  (unless (eq (and (symbol-value var) t) on)
    (if (eql (cdr (func-arity command)) 0)
        (funcall command)
      (funcall command nil))))

(defun maf-options--change (var value)
  "Set VAR to VALUE through `calc-change-mode'.
For the handful of settings calc binds to no command at all: it has the
variable and the manual entry, and nothing to press. This is still
calc's own machinery rather than an assignment — it redraws the stack,
updates the mode line, tells an embedded buffer, and writes the
settings file when the save mode says to. A bare `setq' does none of
that, which is the rule the whole registry follows."
  (calc-wrapper (calc-change-mode var value t)))

(defun maf-options--set-trail (on)
  "Show calc's trail window when ON, hide it otherwise.
Through `calc-trail-display' rather than the variable: the variable
alone only decides whether the next calc to open shows a trail, so
setting it leaves this session's windows as they were and disagreeing
with what the row now claims.

Run from the calc window when one is on screen, because
`calc-trail-display' splits the selected window — called from the
options buffer it would put the trail beside the options rather than
beside the stack."
  (let ((window (get-buffer-window (current-buffer))))
    (if window
        (with-selected-window window (calc-trail-display (if on 1 0)))
      (calc-trail-display (if on 1 0)))))

(defun maf-options--set-vector-brackets (target)
  "Put `calc-vector-brackets' on TARGET: \"[]\", \"{}\", \"()\" or nil.
Each of calc's three commands only flips its own pair against no
brackets at all, so reaching a named pair means clearing whichever pair
is there before asking for the one wanted."
  (unless (equal calc-vector-brackets target)
    (pcase calc-vector-brackets
      ("[]" (calc-vector-brackets))
      ("{}" (calc-vector-braces))
      ("()" (calc-vector-parens)))
    (pcase target
      ("[]" (calc-vector-brackets))
      ("{}" (calc-vector-braces))
      ("()" (calc-vector-parens)))))

(defun maf-options--set-algebraic (target)
  "Put calc in algebraic-entry mode TARGET: nil, t, `incomplete' or `total'.
Calc offers no command that sets this to a named value —
`calc-algebraic-mode' flips between off and partial and, given an
argument, between off and incomplete; `calc-total-algebraic-mode'
between off and total — so reaching TARGET means leaving the current
mode first and then entering the wanted one.

Incomplete mode is a second variable rather than a third value of the
first, so leaving it takes its own call."
  (let ((from (cond ((eq calc-algebraic-mode 'total) 'total)
                    (calc-algebraic-mode t)
                    (calc-incomplete-algebraic-mode 'incomplete))))
    (unless (eq from target)
      (pcase from
        ('total (calc-total-algebraic-mode))
        ('t (calc-algebraic-mode nil))
        ('incomplete (calc-algebraic-mode t)))
      (pcase target
        ('total (calc-total-algebraic-mode))
        ('t (calc-algebraic-mode nil))
        ('incomplete (calc-algebraic-mode t))))))

(defun maf-options--values (var spec)
  "Return SPEC's value entries, synthesizing the pair for a :flag option."
  (or (plist-get spec :values)
      (when-let ((command (plist-get spec :flag)))
        `((t   "on"  (maf-options--set-flag ',var #',command t))
          (nil "off" (maf-options--set-flag ',var #',command nil))))))

(defun maf-options--current (var spec)
  "Return the value key naming VAR's current state under SPEC."
  (let ((raw (maf-options--raw var)))
    (cond ((plist-get spec :current) (funcall (plist-get spec :current) raw))
          ;; A flag's variable may hold a group size or a break column
          ;; rather than t; both still mean on.
          ((plist-get spec :flag) (and raw t))
          (t raw))))

(defun maf-options--default (var)
  "Return VAR's calc default, from `calc-mode-var-list'."
  (nth 1 (assq var calc-mode-var-list)))

(defun maf-options--default-value (var spec)
  "Return the value key naming VAR's calc default under SPEC.
Normalized the way `maf-options--current' normalizes the live value, so
the two are comparable: a flag defaulting to a group size still answers
`t', the key its \"on\" entry is filed under.

SPEC's :default is taken as the answer when it has one. Normalizing
through :current only works while :current looks at nothing but the raw
value it is handed — a :current that consults a second variable would
read that variable's *live* value and report whatever the setting is
on now as the value it starts on. A row like that states its default
rather than deriving one."
  (if (plist-member spec :default)
      (plist-get spec :default)
    (let ((default (maf-options--default var)))
      (cond ((plist-get spec :current)
             (funcall (plist-get spec :current) default))
            ((plist-get spec :flag) (and default t))
            (t default)))))

(defun maf-options--value-string (var spec)
  "Return the Value column text for VAR under SPEC."
  (let* ((raw (maf-options--raw var))
         (shown (and (plist-get spec :show)
                     (funcall (plist-get spec :show) raw))))
    (or shown
        (nth 1 (assq (maf-options--current var spec)
                     (maf-options--values var spec)))
        ;; A string setting is shown as the string, not as its printed
        ;; form: the separator is a comma, not "\",\"".
        (if (stringp raw) raw (format "%S" raw)))))

(defvar-local maf-options--pending nil
  "(VAR . INDEX) for a value stepped onto but not set, or nil.
Only ever one: a step onto another setting's value replaces it, so the
mark cannot be left behind on a row nobody is working on. Point does
not move to it — the step walks the setting, not the buffer — so the
row has to carry the mark itself, which is what this is read for.")

(defun maf-options--pending-index (var)
  "Return the index of VAR's stepped-onto value, if it has one."
  (and (eq (car maf-options--pending) var) (cdr maf-options--pending)))

(defun maf-options--outline (label selected)
  "Return LABEL, drawn inside `maf-options-outline' when SELECTED.
Only a value waiting for its input is ever outlined, so the width the
outline costs is paid on one value at a time and never on a settled
row."
  (if (and selected maf-options-outline)
      (concat (car maf-options-outline) label (cdr maf-options-outline))
    label))

(defun maf-options--value-face (live default selected)
  "Return the face for a value that is LIVE, is the DEFAULT, or SELECTED.
The default is underlined only when it is not the live one. A mark on
every row is a constant rather than a signal — every setting has a
default, so saying so everywhere says nothing — and on the row where
the two coincide the highlight has already said it. Left to appear
exactly where it carries something: this setting has moved, and that is
where it came from. It also makes the rows \\<maf-options-mode-map>\\[maf-options-toggle-changed-only]
would keep visible without filtering, as they are the underlined ones.

An underline shows through a background, so it composes with the
highlight rather than competing with it, and costs no width. SELECTED
composes over either the same way — it only ever appears on a value
that could not be set, so it has to sit beside the highlight rather
than take its place."
  (let ((base (cond (live '(maf-options-value))
                    (default '(underline shadow))
                    (t '(shadow)))))
    (if selected (cons 'maf-options-selection base) base)))

(defun maf-options--value-column (var spec)
  "Return the Value column for VAR under SPEC: every value it can take.
The one calc is on wears `maf-options-value', the rest are shadowed —
the row doubles as the list \\<maf-options-mode-map>\\[maf-options-next-value]
steps through, so what a step will reach is on show rather than found by
stepping to it. The default is underlined, but only where it is not
already the value calc is on — see `maf-options--value-face'. A setting
with no fixed set of values, and one sitting on a value outside its
set, shows that value alone.

A value stepped onto but not set is marked too — see
`maf-options--pending'."
  (let* ((values (maf-options--values var spec))
         (current (maf-options--current var spec))
         (default (maf-options--default-value var spec))
         (show (plist-get spec :show))
         (pending (maf-options--pending-index var))
         (chips (seq-map-indexed
                 (lambda (v i)
                   (propertize
                    (maf-options--outline (nth 1 v) (eql i pending))
                    'face (maf-options--value-face
                           (equal (car v) current)
                           (equal (car v) default)
                           (eql i pending))))
                 values))
         ;; What no chip can say: the value of a setting with an open
         ;; domain, and the detail behind a chip that only names a
         ;; state — grouping is "on", but on in threes.
         (extra (or (and show (funcall show (maf-options--raw var)))
                    (unless (assoc current values)
                      (maf-options--value-string var spec)))))
    ;; The values carry no padding of their own: a face spanning the
    ;; space beside a value reads as highlighting something that is not
    ;; there. The gap between them is the separator, unfaced.
    (mapconcat #'identity
               (if extra
                   (append chips
                           (list (propertize extra 'face 'maf-options-value)))
                 chips)
               "  ")))

(defun maf-options--changed-p (var spec)
  "Non-nil when VAR, or any of SPEC's :vars, has moved off calc's default.
Compares the raw values, not the keys `maf-options--current' derives:
grouping in threes differs from grouping off, and both are \"on\".

:vars names the other variables a row speaks for. A row that covers two
and asks about only one calls itself unchanged while half of what it
shows has moved — and then hides itself from the filter that exists to
find exactly that."
  (seq-some (lambda (v)
              (not (equal (maf-options--raw v) (maf-options--default v))))
            (cons var (plist-get spec :vars))))

;;; The buffer

(defvar-local maf-options--changed-only nil
  "Non-nil to list only settings differing from their calc default.")

(defvar-local maf-options--show-keys nil
  "Non-nil to show the Calc key column.
Off to start: the column is a reference for the keys this buffer exists
to save anyone reaching for, and the widest of them costs twenty
columns that the values put to better use.")

(defun maf-options--apply-format ()
  "Set `tabulated-list-format' for the columns currently shown.
Value goes last because it holds every value the setting can take,
which for the display language is fifteen of them — no fixed width
would hold that, and nothing may sit to the right of it. Calc key comes
and goes with `maf-options--show-keys', so the format is built rather
than written out."
  (setq tabulated-list-format
        (vconcat [("Group" 9 nil) ("Option" 18 nil)]
                 (when maf-options--show-keys [("Calc key" 20 nil)])
                 [("Value" 0 nil)]))
  (tabulated-list-init-header))

(defvar maf-options-mode-map (make-sparse-keymap)
  "Keymap for `maf-options-mode'.")

;; Bindings live outside the defvar so reloading the file applies edits
;; to the existing map.
(define-key maf-options-mode-map (kbd "TAB")     #'maf-options-next-value)
(define-key maf-options-mode-map (kbd "<backtab>") #'maf-options-previous-value)
;; SPC before RET: `define-key' pushes onto the front of a sparse
;; keymap, so the key defined last is the one `where-is-internal' finds
;; first, and RET is the one to name for a command two keys reach.
(define-key maf-options-mode-map (kbd "SPC")     #'maf-options-set)
(define-key maf-options-mode-map (kbd "RET")     #'maf-options-set)
(define-key maf-options-mode-map (kbd "e")   #'maf-options-choose)
(define-key maf-options-mode-map (kbd "d")   #'maf-options-reset)
(define-key maf-options-mode-map (kbd "c")   #'maf-options-toggle-changed-only)
(define-key maf-options-mode-map (kbd "K")   #'maf-options-toggle-keys)
(define-key maf-options-mode-map (kbd "S")   #'maf-options-save)
(define-key maf-options-mode-map (kbd "g")   #'maf-options-refresh)
;; h/l alongside TAB, as j/k sit alongside n/p: the values run across
;; the row, so stepping them is the horizontal motion.
(define-key maf-options-mode-map (kbd "l")   #'maf-options-next-value)
(define-key maf-options-mode-map (kbd "h")   #'maf-options-previous-value)
(define-key maf-options-mode-map (kbd "j")   #'maf-options-next-line)
(define-key maf-options-mode-map (kbd "k")   #'maf-options-previous-line)
(define-key maf-options-mode-map (kbd "n")   #'maf-options-next-line)
(define-key maf-options-mode-map (kbd "p")   #'maf-options-previous-line)
(define-key maf-options-mode-map (kbd "M-n") #'maf-options-next-group)
(define-key maf-options-mode-map (kbd "M-p") #'maf-options-previous-group)

(defvar maf-options--controls nil
  "Commands summarized on the options buffer's controls line, in order.
Each entry is (COMMAND VERB . PREFERRED-KEYS), the keys optional. Keys
are otherwise looked up in the live keymap, so moving a binding — here
or in the maps this mode inherits, which is where `quit-window' comes
from — keeps the line honest.

COMMAND may be a list of commands, for a pair that reads as one control
rather than two: \\`M-n' and \\`M-p' are one \"group\" entry, not a next
and a previous.")

;; Set outside the defvar, as the bindings are, so a reload applies.
(setq maf-options--controls
      '(((maf-options-next-value maf-options-previous-value) "select" "TAB")
        (maf-options-set "set" "RET")
        (maf-options-choose "choose")
        (maf-options-reset "reset")
        (maf-options-toggle-changed-only "changed")
        (maf-options-toggle-keys "calc keys")
        (maf-options-save "save")
        ((maf-options-next-group maf-options-previous-group) "group" "M-n" "M-p")
        (maf-options-refresh "refresh")
        (quit-window "quit")))

(defun maf-options--control-keys (command preferred)
  "Return the key strings naming COMMAND on the controls line.
COMMAND is one command or a list of them. PREFERRED names the keys to
show, in order, and each is kept only while it still runs one of
COMMAND — so a binding moved away drops out of the line rather than
misleading. With none given, or none left, the keymap decides, which
for a command reachable several ways picks whichever key
`where-is-internal' returns first."
  (or (seq-filter (lambda (key)
                    (memq (lookup-key maf-options-mode-map (kbd key))
                          (ensure-list command)))
                  (ensure-list preferred))
      (when-let ((key (where-is-internal (car (ensure-list command))
                                         maf-options-mode-map t)))
        (list (key-description key)))
      (list "M-x")))

(defun maf-options--key (command preferred)
  "Return the key string naming COMMAND in a message, PREFERRED first.
`substitute-command-keys' would name whichever key the map yields
first, which for a command two keys reach is not the one to tell
someone about."
  (car (maf-options--control-keys command preferred)))

(defun maf-options--controls-line ()
  "Return the controls line printed above the list.
Ends with the legend for the mark the rows carry, which is the one
thing on the line that is not a key — hence \\`d' reading \"reset\"
rather than \"default\", which would have said two things here."
  (concat
   " "
   (mapconcat
    (lambda (cell)
      (pcase-let ((`(,command ,verb . ,preferred) cell))
        (concat (mapconcat (lambda (key)
                             (propertize key 'face 'help-key-binding))
                           (maf-options--control-keys command preferred)
                           "/")
                " " verb)))
    maf-options--controls
    "   ")
   "   " (propertize "underlined" 'face '(underline shadow))
   (propertize " = default" 'face 'shadow)))

(defun maf-options--setting-line-p ()
  "Non-nil when point is on a row that names a setting.
False on the controls line, the blank line under it, and the blank rows
between groups — everything motion should step over rather than land
on."
  (let ((id (tabulated-list-get-id)))
    (and id (symbolp id))))

(defun maf-options--goto-option ()
  "Put point on the first character of the current row's Option column.
Found by the column name tabulated-list stamps on the printed text, so
a column widening or disappearing ahead of it needs no change here."
  (let ((pos (line-beginning-position))
        (end (line-end-position))
        found)
    ;; Scanned rather than `text-property-any', which compares with
    ;; `eq' and so never matches a column name that is a string.
    (while (and (not found) (< pos end))
      (if (equal (get-text-property pos 'tabulated-list-column-name) "Option")
          (setq found pos)
        (setq pos (next-single-property-change
                   pos 'tabulated-list-column-name nil end))))
    (when found (goto-char found))))

(defun maf-options--move-line (n)
  "Move N setting rows on, backwards for a negative N.
Point lands on the first character of the Option column rather than
holding whatever column it was in, so a row is picked out by its name;
the blank rows between groups are stepped over rather than landed on.
Staying put where there is no row left to reach."
  (let ((start (point))
        (step (if (> n 0) 1 -1)))
    (dotimes (_ (abs n))
      (let ((from (point)))
        (forward-line step)
        (while (and (not (maf-options--setting-line-p))
                    (if (> step 0) (not (eobp)) (not (bobp))))
          (forward-line step))
        (unless (maf-options--setting-line-p) (goto-char from))))
    (if (maf-options--setting-line-p)
        (maf-options--goto-option)
      (goto-char start))))

(defun maf-options--echo-doc ()
  "Echo the current row's :doc line, if it has one.
What a row is for cannot be read off the row: the Option column has
room for a name, not for a sentence. So the sentence follows point
instead, which is why every registry entry carries a :doc.

Not logged. This runs on every motion key, and a line of help repeated
down a list is not what *Messages* is for. Silent on a row with no doc
rather than blanking the echo area, so whatever was last said — the
value just set, a value waiting for input — survives the move."
  (let ((doc (plist-get (alist-get (tabulated-list-get-id)
                                   maf-options-registry)
                        :doc)))
    (when doc
      (let ((message-log-max nil))
        (message "%s" doc)))))

(defun maf-options-next-line (&optional n)
  "Move to the next setting, or N settings on, and echo what it does."
  (interactive "p")
  (maf-options--move-line (or n 1))
  (maf-options--echo-doc))

(defun maf-options-previous-line (&optional n)
  "Move to the previous setting, or N settings back, and echo what it does."
  (interactive "p")
  (maf-options--move-line (- (or n 1)))
  (maf-options--echo-doc))

(defun maf-options--print (&optional remember-pos)
  "Print the controls line and the list, honoring REMEMBER-POS.
`tabulated-list-print' erases the buffer, so the controls are written
again after every print rather than once. Every path that reprints goes
through here, \\`g' included — it runs `maf-options-refresh' rather
than `revert-buffer' so that reverting cannot drop the line.

The line goes in the buffer rather than the header line, which is
already showing the column names, and is inserted after printing so
REMEMBER-POS still measures against the rows alone."
  (tabulated-list-print remember-pos)
  (let ((inhibit-read-only t)
        (line (concat (maf-options--controls-line) "\n")))
    ;; Appended rather than propertized on, so the band fills in behind
    ;; the keys without painting over the face that picks them out.
    (add-face-text-property 0 (length line) 'maf-options-controls t line)
    (save-excursion
      (goto-char (point-min))
      (insert line "\n")))
  (if (maf-options--setting-line-p)
      (maf-options--goto-option)
    (goto-char (point-min))
    (maf-options--move-line 1)))

(define-derived-mode maf-options-mode tabulated-list-mode "maf-options"
  "Major mode for the maf options buffer.
Each row is one calc setting: its group, name, every value it can take
with the live one highlighted, and the key calc itself binds it to.

\\<maf-options-mode-map>\\[maf-options-next-line] and
\\[maf-options-previous-line] move between settings, echoing a line on
what the one under point does; \\[maf-options-next-group] and
\\[maf-options-previous-group] move a whole group at a time.

\\[maf-options-next-value] steps point along
the row's values without setting any of them, and \\[maf-options-set]
sets the one point is on — two acts on two keys, because a setter is
free to prompt and stepping cannot be made to wait on it.
\\[maf-options-choose] picks a value by name instead;
\\[maf-options-reset] restores calc's default;
\\[maf-options-toggle-changed-only] narrows the list to settings that
differ from their default; \\[maf-options-toggle-keys] shows the calc
keys; \\[quit-window] buries the buffer.

Values are always set by running calc's own command, so the stack
redraws and the trail records exactly as if the key had been pressed."
  (setq tabulated-list-padding 1
        ;; No sort key: rows print in registry order, which is what
        ;; keeps each :group's entries together under its heading.
        tabulated-list-sort-key nil)
  (add-hook 'tabulated-list-revert-hook #'maf-options--refresh nil t)
  (maf-options--apply-format))

(defun maf-options--refresh ()
  "Rebuild `tabulated-list-entries' from `maf-options-registry'.
A blank row separates each :group from the next. Its id is a cons
rather than a variable name, which is what `maf-options--spec' reads as
\"no setting on this line\" — and being distinct per group, it also
leaves `tabulated-list-print' able to put point back where it was."
  (let (entries last-group)
    (dolist (entry maf-options-registry)
      (let* ((var (car entry))
             (spec (cdr entry))
             (group (plist-get spec :group))
             (changed (maf-options--changed-p var spec)))
        (unless (and maf-options--changed-only (not changed))
          (unless (or (null last-group) (equal group last-group))
            (push (list (cons 'gap group)
                        (make-vector (length tabulated-list-format) ""))
                  entries))
          (push (list var
                      (vconcat
                       (vector (if (equal group last-group) "" group)
                               (plist-get spec :label))
                       (when maf-options--show-keys
                         (vector (or (plist-get spec :keys) "")))
                       (vector (maf-options--value-column var spec))))
                entries)
          (setq last-group group))))
    (setq tabulated-list-entries (nreverse entries))))

(defun maf-options--redraw (var spec)
  "Redraw the list, keeping point on the same row, and echo VAR's value.
SPEC is VAR's entry in `maf-options-registry'. Both are passed in from
the command that just set VAR, rather than re-read from the row, so the
echo reports what was set even if the row has moved.

Clears `maf-options--pending' — every path through here has just set
the setting, by whatever route, so a value still waiting to be set is
no longer waiting for anything. `maf-options-next-value' redraws
without this when it is the one leaving a value pending."
  (setq maf-options--pending nil)
  (maf-options--refresh)
  (maf-options--print t)
  (message "%s: %s" (plist-get spec :label)
           (maf-options--value-string var spec)))

(defun maf-options-refresh ()
  "Re-read every setting from calc and redraw the list."
  (interactive)
  (maf-options--refresh)
  (maf-options--print t))

(defun maf-options--group-starts ()
  "Return the position of each group's first setting, in buffer order.
Read off the printed rows rather than the registry, so the filtered
list navigates by the groups it is actually showing."
  (save-excursion
    (goto-char (point-min))
    (let (starts last)
      (while (not (eobp))
        (let ((id (tabulated-list-get-id)))
          (when (and id (symbolp id))
            (let ((group (plist-get (alist-get id maf-options-registry) :group)))
              (unless (equal group last)
                (push (line-beginning-position) starts)
                (setq last group)))))
        (forward-line 1))
      (nreverse starts))))

(defun maf-options--goto-group (n)
  "Move N groups on, backwards for a negative N.
Moving back from inside a group lands on its own first row before going
any further, the way paragraph motion does."
  (let* ((starts (maf-options--group-starts))
         (here (line-beginning-position))
         (pos here))
    (dotimes (_ (abs n))
      (setq pos (or (if (> n 0)
                        (seq-find (lambda (p) (> p pos)) starts)
                      (car (last (seq-filter (lambda (p) (< p pos)) starts))))
                    pos)))
    (when (= pos here)
      (user-error "No %s group" (if (> n 0) "next" "previous")))
    (goto-char pos)
    (maf-options--goto-option)))

(defun maf-options-next-group (&optional n)
  "Move to the first setting of the next group, or N groups on."
  (interactive "p")
  (maf-options--goto-group (or n 1))
  (maf-options--echo-doc))

(defun maf-options-previous-group (&optional n)
  "Move to the first setting of the previous group, or N groups back."
  (interactive "p")
  (maf-options--goto-group (- (or n 1)))
  (maf-options--echo-doc))

(defun maf-options--spec ()
  "Return (VAR . SPEC) for the setting on the current line.
Signals on a group separator, whose id names no setting."
  (let* ((var (tabulated-list-get-id))
         (spec (and (symbolp var) (alist-get var maf-options-registry))))
    (unless spec (user-error "No setting on this line"))
    (cons var spec)))

;; Stepping through a row sets each value as it lands on it — the point
;; of the row is to try the values, and having to confirm every one
;; would halve the speed of the thing.
;;
;; With one exception, which is why setting has a key of its own: a
;; setter is free to prompt, and `calc-fix-notation' asks for a digit
;; count. Applying "fixed point" on the way past it would stop dead,
;; and the step could not reach "scientific" until the prompt was
;; answered. So a prompting value is stepped onto and left alone, and
;; `maf-options-set' is what runs it.

(defun maf-options--prompts-p (setter)
  "Non-nil when SETTER asks the user for the value it sets.
A setter that needs input is written as a `call-interactively' of the
calc command that reads it, so the form says so itself and the registry
needs no separate flag for it."
  (and (listp setter) (memq 'call-interactively (flatten-tree setter))))

(defun maf-options-next-value (&optional n)
  "Set this row's setting to its next value, or the one N values on.
Wraps at the end of the row, and steps on from the value last stepped
onto rather than from the live one, so a value that could not be set
is still a place to carry on from.

A value whose setter prompts is stepped onto and marked, not set:
running it would stop for an answer, and the step could not reach the
value after it until that answer came. \\<maf-options-mode-map>\\[maf-options-set]
runs that one."
  (interactive "p")
  (pcase-let* ((`(,var . ,spec) (maf-options--spec))
               (values (maf-options--values var spec))
               (count (length values)))
    (when (zerop count)
      (user-error "%s takes no fixed set of values — %s prompts for one"
                  (plist-get spec :label)
                  (maf-options--key #'maf-options-set "RET")))
    (let* ((from (or (maf-options--pending-index var)
                     (seq-position values (maf-options--current var spec)
                                   (lambda (v c) (equal (car v) c)))
                     0))
           (index (mod (+ from (or n 1)) count))
           (value (nth index values)))
      (if (maf-options--prompts-p (nth 2 value))
          (progn
            (setq maf-options--pending (cons var index))
            (maf-options--refresh)
            (maf-options--print t)
            (message "%s needs a value — %s to enter it" (nth 1 value)
                     (maf-options--key #'maf-options-set "RET")))
        (setq maf-options--pending nil)
        (maf-options--set (nth 2 value))
        (maf-options--redraw var spec)))))

(defun maf-options-previous-value (&optional n)
  "Set this row's setting to its previous value, or the one N values back."
  (interactive "p")
  (maf-options-next-value (- (or n 1))))

(defun maf-options-set ()
  "Set this row's setting to the value stepped onto but not yet set.
That is the one case \\<maf-options-mode-map>\\[maf-options-next-value]
leaves undone, since running it means answering a prompt. With nothing
stepped onto, prompts anyway when the setting takes no fixed set of
values — for those, being asked is the only way to set them at all."
  (interactive)
  (pcase-let* ((`(,var . ,spec) (maf-options--spec))
               (values (maf-options--values var spec))
               (index (maf-options--pending-index var)))
    (cond (index (maf-options--set (nth 2 (nth index values)))
                 (setq maf-options--pending nil))
          ((plist-get spec :read) (maf-options--set (plist-get spec :read)))
          (t (user-error "Nothing waiting to be set — %s steps through the values"
                         (maf-options--key #'maf-options-next-value "TAB"))))
    (maf-options--redraw var spec)))

(defun maf-options-choose ()
  "Pick a value for the current line's setting by name."
  (interactive)
  (pcase-let* ((`(,var . ,spec) (maf-options--spec))
               (values (maf-options--values var spec))
               (read (plist-get spec :read)))
    (if (null values)
        (maf-options--set read)
      (let* ((labels (mapcar (lambda (v) (nth 1 v)) values))
             (labels (if read (append labels '("other…")) labels))
             (pick (completing-read (format "%s: " (plist-get spec :label))
                                    labels nil t)))
        (maf-options--set
         (if (equal pick "other…")
             read
           (nth 2 (seq-find (lambda (v) (equal (nth 1 v) pick)) values))))))
    (maf-options--redraw var spec)))

(defun maf-options-reset ()
  "Restore the current line's setting to the default calc starts with.
A setting with a named value for its default is put back by asking for
that value, so calc's own command runs and does whatever else it does —
the display language rebuilds its parse tables, the word size
recomputes the modulo.

A setting whose values are open has no such command: all calc offers is
a prompt, and a prompt cannot be told to answer itself. Those go back
through `maf-options--change', which is the mode-setting call those
commands make once they have read their answer — unless the spec gives
a :reset form, which is how a setting whose command does more than that
call says so."
  (interactive)
  (pcase-let* ((`(,var . ,spec) (maf-options--spec))
               (default (maf-options--default var))
               (entry (assq (maf-options--default-value var spec)
                            (maf-options--values var spec))))
    (maf-options--set (cond ((plist-get spec :reset))
                            (entry (nth 2 entry))
                            (t `(maf-options--change ',var ',default))))
    (maf-options--redraw var spec)))

(defun maf-options-save ()
  "Write every setting's current value to calc's settings file.
Runs calc's own `calc-save-modes', the \\`m m' command, rather than
writing the file here: it is the same list of settings either way, and
one writer means the file keeps the shape calc reads back.

Note that this saves calc's settings, not maf's — the buffer is a way
of reaching them, not a second place they live."
  (interactive)
  (unless calc-settings-file
    (user-error "No `calc-settings-file' to save to"))
  (maf-options--set '(calc-save-modes))
  (message "Settings saved in %s" (abbreviate-file-name calc-settings-file)))

(defun maf-options-toggle-keys ()
  "Show or hide the Calc key column."
  (interactive)
  (setq maf-options--show-keys (not maf-options--show-keys))
  (maf-options--apply-format)
  (maf-options--refresh)
  (maf-options--print t))

(defun maf-options-toggle-changed-only ()
  "Toggle between all settings and only those changed from default."
  (interactive)
  (setq maf-options--changed-only (not maf-options--changed-only))
  (maf-options--refresh)
  (maf-options--print t)
  (message "Showing %s settings"
           (if maf-options--changed-only "changed" "all")))

;;;###autoload
(defun maf-options ()
  "Show the maf options buffer in another window and select it.
Lists calc's settings with their current values; RET steps the setting
on the current line to its next value (see `maf-options-mode')."
  (interactive)
  (let ((calc-buffer (if (derived-mode-p 'calc-mode)
                         (current-buffer)
                       (get-buffer "*Calculator*")))
        (buf (get-buffer-create "*maf-options*")))
    (with-current-buffer buf
      (maf-options-mode)
      (setq maf-options--calc-buffer calc-buffer)
      (maf-options--refresh)
      (maf-options--print))
    (pop-to-buffer buf)))

;;; Module

;;;###autoload
(define-minor-mode maf-use-options-mode
  "Global minor mode giving calc's settings a single browsable buffer.
Enabled, `\\[maf-options]' — bound to \\`m o' in `maf-mode' buffers —
opens the *maf-options* menu, where every setting in
`maf-options-registry' shows its current value and can be set without
recalling its key. Calc's own option keys are untouched. Managed
through the module system; see `maf-modules'."
  :global t
  :group 'maf
  (if maf-use-options-mode
      ;; `m' is calc's mode prefix, where a settings buffer belongs;
      ;; `m o' is unbound in calc itself, as `m c' is for the module
      ;; menu. Freeing the rest of the prefix is a separate decision
      ;; from offering this buffer, and is not made here.
      (define-key maf-mode-map (kbd "m o") #'maf-options)
    (define-key maf-mode-map (kbd "m o") nil)))

;; Register with the module system when it is present; the mode above
;; works on its own without it.
(when (require 'maf-module nil t)
  (maf-register-module 'maf-options #'maf-use-options-mode
                       "Browse and set all of calc's options from one buffer."))

;;; Not in the registry
;;
;; Every setting calc treats as a mode now has a row, bar these:
;;
;;   calc-settings-file (m F) names the file the settings are written
;;   to. It is not in `calc-mode-var-list', so there is no default to
;;   show or reset to, and naming a file is an errand rather than a
;;   setting -- m F still does it.
;;
;;   calc-full-trail-vectors, calc-previous-modulo, calc-language-option
;;   and the graph and gnuplot settings are held by calc but driven by
;;   the commands that use them, not chosen ahead of time.
(provide 'maf-options)
