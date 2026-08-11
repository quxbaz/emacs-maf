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
;; STATUS: skeleton. Three groups are populated (Numbers, Algebra,
;; Display) — enough to exercise the format and the buffer. The
;; remaining groups (Vectors, Binary, Selection, Session) are listed in
;; `maf-options--todo' at the foot of this file.

(require 'calc)
(require 'calc-ext)                     ; calc-mode-var-list
(require 'tabulated-list)
(require 'wid-edit)                     ; the `widget-field' face
(require 'maf-conf "conf")              ; the `maf' customize group

(defface maf-options-value
  '((t :inherit widget-field))
  "Face for the Value column of the options buffer.
Marks the one part of a row that can be changed — the rest is the
setting's name and where calc keeps it. Inherits from `widget-field',
which is what Customize gives an editable field, so the column reads as
one and follows the theme."
  :group 'maf)

(defface maf-options-value-changed
  '((t :inherit (highlight widget-field)))
  "Face for a Value that differs from the default calc starts with.
Distinguishes the settings this session has moved from the ones sitting
where calc left them — the same distinction \\<maf-options-mode-map>\\[maf-options-toggle-changed-only]
filters on, shown without having to filter. `highlight' leads the
inheritance so its background wins over `widget-field''s while the
column still reads as a field."
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
     :values ((nil   "off"     (maf-options--set-algebraic nil))
              (t     "partial" (maf-options--set-algebraic t))
              (total "total"   (maf-options--set-algebraic 'total))))

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
              (maple   "Maple"         (calc-maple-language))))))

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
prefix."
  (unless (eq (and (symbol-value var) t) on)
    (funcall command nil)))

(defun maf-options--set-algebraic (target)
  "Put calc in algebraic-entry mode TARGET: nil, t, or `total'.
Calc offers no command that sets this to a named value —
`calc-algebraic-mode' flips between off and partial,
`calc-total-algebraic-mode' between off and total — so reaching TARGET
means leaving the current mode first and then entering the wanted one."
  (unless (eq calc-algebraic-mode target)
    (cond ((eq calc-algebraic-mode 'total) (calc-total-algebraic-mode))
          (calc-algebraic-mode (calc-algebraic-mode nil)))
    (pcase target
      ('total (calc-total-algebraic-mode))
      ('t (calc-algebraic-mode nil)))))

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

(defun maf-options--value-string (var spec)
  "Return the Value column text for VAR under SPEC."
  (let* ((raw (maf-options--raw var))
         (shown (and (plist-get spec :show)
                     (funcall (plist-get spec :show) raw))))
    (or shown
        (nth 1 (assq (maf-options--current var spec)
                     (maf-options--values var spec)))
        (format "%S" raw))))

(defun maf-options--value-cell (text changed)
  "Return TEXT as a row's Value cell, faced to show it can be changed.
CHANGED marks a setting sitting somewhere other than the default calc
starts with, which takes the second face. Padding to the column's own
width gives the cells a straight right edge instead of a ragged one."
  (let ((width (1- (cadr (seq-find (lambda (col) (equal (car col) "Value"))
                                   tabulated-list-format)))))
    (propertize (truncate-string-to-width text width 0 ?\s)
                'face (if changed 'maf-options-value-changed 'maf-options-value))))

(defun maf-options--changed-p (var)
  "Non-nil when VAR differs from the default calc would start with.
Compares the raw values, not the keys `maf-options--current' derives:
grouping in threes differs from grouping off, and both are \"on\"."
  (not (equal (maf-options--raw var) (maf-options--default var))))

;;; The buffer

(defvar-local maf-options--changed-only nil
  "Non-nil to list only settings differing from their calc default.")

(defvar maf-options-mode-map (make-sparse-keymap)
  "Keymap for `maf-options-mode'.")

;; Bindings live outside the defvar so reloading the file applies edits
;; to the existing map.
(define-key maf-options-mode-map (kbd "RET") #'maf-options-cycle)
(define-key maf-options-mode-map (kbd "SPC") #'maf-options-cycle)
(define-key maf-options-mode-map (kbd "TAB") #'maf-options-cycle)
(define-key maf-options-mode-map (kbd "e")   #'maf-options-choose)
(define-key maf-options-mode-map (kbd "d")   #'maf-options-reset)
(define-key maf-options-mode-map (kbd "c")   #'maf-options-toggle-changed-only)
(define-key maf-options-mode-map (kbd "g")   #'maf-options-refresh)
(define-key maf-options-mode-map (kbd "j")   #'next-line)
(define-key maf-options-mode-map (kbd "k")   #'previous-line)

(defvar maf-options--controls nil
  "Commands summarized on the options buffer's controls line, in order.
Each entry is (COMMAND VERB . PREFERRED-KEY), the key optional. Keys
are otherwise looked up in the live keymap, so moving a binding — here
or in the maps this mode inherits, which is where `quit-window' comes
from — keeps the line honest.")

;; Set outside the defvar, as the bindings are, so a reload applies.
(setq maf-options--controls
      '((maf-options-cycle "cycle" . "RET")
        (maf-options-choose "choose")
        (maf-options-reset "default")
        (maf-options-toggle-changed-only "changed")
        (maf-options-refresh "refresh")
        (quit-window "quit")))

(defun maf-options--control-key (command preferred)
  "Return the key string naming COMMAND on the controls line.
PREFERRED wins while it still runs COMMAND: three keys cycle a setting,
and the line should name the same one every time rather than whichever
`where-is-internal' happens to return first."
  (or (and preferred
           (eq (lookup-key maf-options-mode-map (kbd preferred)) command)
           preferred)
      (when-let ((key (where-is-internal command maf-options-mode-map t)))
        (key-description key))
      "M-x"))

(defun maf-options--controls-line ()
  "Return the controls line printed above the list."
  (concat
   " "
   (mapconcat
    (lambda (cell)
      (pcase-let ((`(,command ,verb . ,preferred) cell))
        (concat (propertize (maf-options--control-key command preferred)
                            'face 'help-key-binding)
                " " verb)))
    maf-options--controls
    "   ")))

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
  (let ((inhibit-read-only t))
    (save-excursion
      (goto-char (point-min))
      (insert (maf-options--controls-line) "\n\n"))))

(define-derived-mode maf-options-mode tabulated-list-mode "maf-options"
  "Major mode for the maf options buffer.
Each row is one calc setting: its group, name, current value, and the
key calc itself binds it to. \\<maf-options-mode-map>\\[maf-options-cycle]
steps the setting on the current line to its next value (or prompts,
for a setting with no fixed set); \\[maf-options-choose] picks a value
by name; \\[maf-options-reset] restores calc's default;
\\[maf-options-toggle-changed-only] narrows the list to settings that
differ from their default; \\[quit-window] buries the buffer.

Values are always set by running calc's own command, so the stack
redraws and the trail records exactly as if the key had been pressed."
  (setq tabulated-list-format [("Group" 9 nil) ("Option" 18 nil)
                               ("Value" 16 nil) ("Calc key" 0 nil)]
        tabulated-list-padding 1
        ;; No sort key: rows print in registry order, which is what
        ;; keeps each :group's entries together under its heading.
        tabulated-list-sort-key nil)
  (add-hook 'tabulated-list-revert-hook #'maf-options--refresh nil t)
  (tabulated-list-init-header))

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
             (changed (maf-options--changed-p var)))
        (unless (and maf-options--changed-only (not changed))
          (unless (or (null last-group) (equal group last-group))
            (push (list (cons 'gap group) (vector "" "" "" "")) entries))
          (push (list var
                      (vector (if (equal group last-group) "" group)
                              (plist-get spec :label)
                              (maf-options--value-cell
                               (maf-options--value-string var spec) changed)
                              (or (plist-get spec :keys) "")))
                entries)
          (setq last-group group))))
    (setq tabulated-list-entries (nreverse entries))))

(defun maf-options--redraw (var spec)
  "Redraw the list, keeping point on the same row, and echo VAR's value.
SPEC is VAR's entry in `maf-options-registry'. Both are passed in from
the command that just set VAR, rather than re-read from the row, so the
echo reports what was set even if the row has moved."
  (maf-options--refresh)
  (maf-options--print t)
  (message "%s: %s" (plist-get spec :label)
           (maf-options--value-string var spec)))

(defun maf-options-refresh ()
  "Re-read every setting from calc and redraw the list."
  (interactive)
  (maf-options--refresh)
  (maf-options--print t))

(defun maf-options--spec ()
  "Return (VAR . SPEC) for the setting on the current line.
Signals on a group separator, whose id names no setting."
  (let* ((var (tabulated-list-get-id))
         (spec (and (symbolp var) (alist-get var maf-options-registry))))
    (unless spec (user-error "No setting on this line"))
    (cons var spec)))

(defun maf-options-cycle ()
  "Set the current line's setting to its next value.
With no fixed set of values, prompts for one instead."
  (interactive)
  (pcase-let* ((`(,var . ,spec) (maf-options--spec))
               (values (maf-options--values var spec)))
    (if (null values)
        (maf-options--set (plist-get spec :read))
      (let* ((current (maf-options--current var spec))
             (pos (seq-position values current (lambda (v c) (equal (car v) c))))
             (next (nth (mod (1+ (or pos -1)) (length values)) values)))
        (maf-options--set (nth 2 next))))
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
Only settings whose default is one of their listed values can be reset
this way; the rest have to be set to a value explicitly, since calc
gives no command that names the default."
  (interactive)
  (pcase-let* ((`(,var . ,spec) (maf-options--spec))
               (default (maf-options--default var))
               (entry (assq (if (plist-get spec :flag) (and default t) default)
                            (maf-options--values var spec))))
    (unless entry
      (user-error "No setter for the default of %s (%S)" var default))
    (maf-options--set (nth 2 entry))
    (maf-options--redraw var spec)))

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

;;; Not yet in the registry
;;
;; The settings below are real options with no row yet. Each needs the
;; same treatment: a value domain, and a setter form per value.
;;
;;   Vectors    calc-vector-brackets (v [), calc-matrix-brackets (v ]),
;;              calc-vector-commas (v ,), calc-full-vectors (v .),
;;              calc-break-vectors (v /), calc-matrix-just (v </=/>)
;;   Binary     calc-word-size (b w), calc-twos-complement-mode
;;   Selection  calc-show-selections (j d), calc-assoc-selections
;;   Formats    calc-frac-format (d :), calc-hms-format, calc-date-format (d d),
;;              calc-complex-format (d c/i/j), calc-group-char (d ,),
;;              calc-left-label (d {), calc-right-label (d })
;;   Session    calc-display-working-message (m w), calc-auto-why (d w),
;;              calc-display-trail, calc-window-height, calc-show-banner (d @),
;;              calc-mode-save-mode (m R), calc-settings-file-name (m F)
;;
;; Three of these — calc-assoc-selections, calc-display-trail,
;; calc-twos-complement-mode — have no key binding at all in calc, and
;; are the clearest argument for the buffer: without it they are
;; reachable only through Customize.

(defvar maf-options--todo nil
  "Placeholder; see the commentary above for the settings still to add.")

(provide 'maf-options)
