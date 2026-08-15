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
;;    list still supplies the defaults, which is how resetting knows
;;    what to reset to.
;;
;;  - The buffer, which is dial's (pkg/dial): dial provides the shell —
;;    the tabulated buffer, its rendering, motion and keys — and this
;;    file specifies the content, handing `dial-open' the registry
;;    (compiled by `maf-options--items') and the calc plumbing below
;;    that reads and sets the variables.
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
(require 'dial)
(require 'maf-conf "conf")              ; the `maf' customize group

;; The outline defcustom moved to dial with the rest of the buffer. A
;; customization saved under the old name still has to land: carry any
;; early-set value over first, since `defvaralias' keeps the base
;; variable's value, then alias so later setters reach dial's.
(when (and (boundp 'maf-options-outline)
           (not (eq (symbol-value 'maf-options-outline) dial-outline)))
  (setq dial-outline (symbol-value 'maf-options-outline)))
(define-obsolete-variable-alias 'maf-options-outline 'dial-outline "0.0.1")

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
;; — and SPEC a plist in dial's item format (see pkg/dial/dial.el for
;; the full key list), plus one key of this file's own:
;;
;;   :flag    COMMAND, for a plain on/off option, in place of :values:
;;            the two entries are synthesized by `maf-options--items'.
;;            See `maf-options--set-flag' for why this is not just
;;            shorthand.
;;
;; :keys holds calc's own key(s) for the setting, shown in the Calc key
;; column. Informational: the menu never presses them, and they stay
;; meaningful if maf later takes the prefix over.
;;
;; A setter is a form rather than a command name because calc's own
;; commands do not uniformly take a value. Some are one command per
;; value (three for the angle modes), some take a numeric argument
;; naming the value (`calc-working' 0/1/2), some are toggles that only
;; flip (`calc-algebraic-mode'), and reaching a definite value through
;; a toggle takes a conditional — see `maf-options--set-algebraic'.
;; Every setter is evaluated by `maf-options--set' with the calc buffer
;; current.

(defvar maf-options-registry nil
  "Table of calc settings the options menu offers.
Each entry is (VAR . SPEC); see this file's commentary for SPEC's keys
and for why the setters are forms rather than command names.")

;; Filled outside the defvar so reloading the file applies edits to the
;; table rather than leaving the value bound from the first load.
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
     ;; dial buffer current, and the mode variables are local to calc's.
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
     ;; Fixed point is the one value whose setter must ask — for the
     ;; digit count — so its entry says :prompts, which is what keeps
     ;; stepping from stopping dead on it (see `dial-next-value').
     :values ((float "normal"      (calc-normal-notation nil))
              (fix   "fixed point" (call-interactively #'calc-fix-notation)
                     :prompts t)
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
     ;; The setting holds a string; the symbol keys above only name
     ;; the three pairs calc has commands for, and :current maps the
     ;; string onto them. Any other string calc has been left holding
     ;; is passed through to match no key at all, rather than falling
     ;; to nil and lighting "none".
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
  "The calc buffer this options buffer reads and sets.
Local to the dial buffer, planted there by `maf-options' at open.")

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

(defun maf-options--default (var)
  "Return VAR's calc default, from `calc-mode-var-list'."
  (nth 1 (assq var calc-mode-var-list)))

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

(defun maf-options--save ()
  "Write every setting's current value to calc's settings file.
Runs calc's own `calc-save-modes', the \\`m m' command, rather than
writing the file here: it is the same list of settings either way, and
one writer means the file keeps the shape calc reads back.

Note that this saves calc's settings, not maf's — the buffer is a way
of reaching them, not a second place they live."
  (unless calc-settings-file
    (user-error "No `calc-settings-file' to save to"))
  (maf-options--set '(calc-save-modes))
  (message "Settings saved in %s" (abbreviate-file-name calc-settings-file)))

;;; The dial buffer

(defun maf-options--items ()
  "Compile `maf-options-registry' into dial items.
The one registry key dial does not read is :flag, this file's shorthand
for a plain on/off option: its two value entries are synthesized here,
closing over the toggling command, along with the :current that reads a
group size or a break column as still meaning on. Everything else
passes through — the registry is already written in dial's item format."
  (mapcar (lambda (entry)
            (let* ((var (car entry))
                   (spec (copy-sequence (cdr entry)))
                   (command (plist-get spec :flag)))
              (when command
                (setq spec (plist-put
                            spec :values
                            `((t   "on"  (maf-options--set-flag ',var #',command t))
                              (nil "off" (maf-options--set-flag ',var #',command nil))))
                      spec (plist-put spec :current
                                      (lambda (raw) (and raw t)))))
              (cons var spec)))
          maf-options-registry))

(defvar maf-options--controls nil
  "The options buffer's controls line: dial's own, reworded for calc.
Only \\`K' reads differently — \"calc keys\", since the column it
toggles holds calc's bindings, not dial's.")

;; Set outside the defvar so a reload applies edits to the list.
(setq maf-options--controls
      '(((dial-next-value dial-previous-value) "select" "TAB")
        (dial-set "set" "RET")
        (dial-reset "reset")
        (dial-toggle-changed-only "changed")
        (dial-toggle-keys "calc keys")
        (dial-save "save")
        ((dial-next-group dial-previous-group) "group" "M-n" "M-p")
        (dial-refresh "refresh")
        (quit-window "quit")))

;;;###autoload
(defun maf-options ()
  "Show the maf options buffer in another window and select it.
Lists calc's settings with their current values; TAB steps the setting
on the current line to its next value (see `dial-mode'). The buffer is
dial's; this command supplies it the registry and the calc plumbing —
where values live, how a setter runs, what the defaults are."
  (interactive)
  (let ((calc-buffer (if (derived-mode-p 'calc-mode)
                         (current-buffer)
                       (get-buffer "*Calculator*"))))
    (dial-open "*maf-options*" (maf-options--items)
               :name "maf-options"
               :keys-name "Calc key"
               :controls maf-options--controls
               :raw #'maf-options--raw
               :default #'maf-options--default
               :apply #'maf-options--set
               :write (lambda (var value)
                        (maf-options--set `(maf-options--change ',var ',value)))
               :save #'maf-options--save
               ;; Before the first render, so the very first read of a
               ;; calc variable already goes to the right calc buffer.
               :init (lambda ()
                       (setq-local maf-options--calc-buffer calc-buffer)))))

;;; Module

;;;###autoload
(define-minor-mode maf-use-options-mode
  "Global minor mode giving calc's settings a single browsable buffer.
Enabled, `\\[maf-options]' — bound to \\`?' in `maf-mode' buffers —
opens the *maf-options* menu, where every setting in
`maf-options-registry' shows its current value and can be set without
recalling its key. Calc's own option keys are untouched. Managed
through the module system; see `maf-modules'."
  :global t
  :group 'maf
  (if maf-use-options-mode
      ;; ? shadows calc-help: the settings menu is the glanceable
      ;; answer to "what state am I in", which is most of what the
      ;; help key gets asked; calc's help summary stays on h.
      (define-key maf-mode-map (kbd "?") #'maf-options)
    (define-key maf-mode-map (kbd "?") nil)))

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
