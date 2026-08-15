;; -*- lexical-binding: t; -*-
;;
;; sandbox/options-spec.el
;;
;; Characterization spec for the *maf-options* buffer, recorded ahead
;; of the dial refactor so the refactored buffer can be checked against
;; the original mechanically rather than by eye. Not a maf-step test —
;; it drives the options UI, not the stack — which is why it lives in
;; sandbox/ and not tests/.
;;
;; Usage, in the live dev instance:
;;
;;   (load-file "sandbox/options-spec.el")
;;   (maf-options-spec-record)   ; before the refactor: writes options-spec.eld
;;   (maf-options-spec-check)    ; after: re-captures and diffs against it
;;
;; The capture resets calc, opens the buffer with `maf-options', and
;; walks a scripted tour, recording at each step what the user could
;; observe. What is pinned:
;;
;;  - The rendered buffer: full text, header line, and every faced
;;    stretch of text with its resolved attributes — colors, underline,
;;    weight, box — so appearance is compared, not markup.
;;  - Where point lands: on the Option column of the first setting at
;;    open, and after every motion key. n/p/j/k step settings, skipping
;;    the gaps between groups and echoing each row's doc line; M-n/M-p
;;    step groups, erroring at the edges; motion off the last row stays
;;    put.
;;  - Value stepping: TAB/backtab set each value as they land on it,
;;    wrapping at the row's ends, with the echo naming the new value and
;;    the calc variable in *Calculator* actually moving — the spec reads
;;    the variable, so a repaint that stopped reaching calc would fail.
;;  - The pending mark: a value whose setter prompts (Float format's
;;    "fixed point") is stepped onto, outlined and announced, but not
;;    set; the next TAB moves past it and sets normally; d restores the
;;    calc default.
;;  - TAB on an open-domain row (Precision) refuses with the message
;;    naming RET.
;;  - c narrows the list to changed settings and back; K adds and
;;    removes the Calc key column; both keep point on its row.
;;  - The controls line text, including the key names it shows.
;;  - Key bindings, compared by role: command names are stripped of
;;    their package prefix first, so maf-options-set matching dial-set
;;    is not drift, but TAB moving to a different role is.
;;  - An invariant: after the whole tour the buffer renders exactly as
;;    it did at open — every setting the tour touched came back.
;;
;; Deliberately not pinned: command and face names (see above), the S
;; save command's effect (it writes calc's settings file; only its
;; binding is recorded), and the prompts themselves behind :read
;; setters, which cannot be driven non-interactively.

(require 'cl-lib)
(require 'calc)

(defconst maf-options-spec-file
  (expand-file-name "options-spec.eld"
                    (file-name-directory (or load-file-name buffer-file-name)))
  "File the recorded spec is written to and checked against.")

;;; Observing the buffer

(defmacro maf-options-spec--in-buffer (&rest body)
  "Run BODY in the *maf-options* buffer, in its window when it has one.
Through the window when possible, so commands that consult the selected
window behave as they do for the user."
  (declare (indent 0) (debug t))
  `(let* ((buf (or (get-buffer "*maf-options*")
                   (error "No *maf-options* buffer")))
          (win (get-buffer-window buf t)))
     (if win
         (with-selected-window win ,@body)
       (with-current-buffer buf ,@body))))

(defun maf-options-spec--press (key)
  "Dispatch KEY in the options buffer through its keymaps.
Returns (:messages MESSAGES :error ERROR): every `message' the press
produced, in order, and the text of the error it signaled, if any.
Dispatching with `execute-kbd-macro' rather than calling the command
keeps the spec blind to command names — only the key and its effect are
recorded."
  (let (msgs err)
    (let ((real (symbol-function 'message)))
      (cl-letf (((symbol-function 'message)
                 (lambda (fmt &rest args)
                   (when fmt (push (apply #'format fmt args) msgs))
                   (apply real fmt args))))
        (condition-case e
            (maf-options-spec--in-buffer
              (execute-kbd-macro (kbd key)))
          (error (setq err (error-message-string e))))))
    (list :messages (nreverse msgs) :error err)))

(defun maf-options-spec--where ()
  "Point's line, column and line text in the options buffer."
  (maf-options-spec--in-buffer
    (list :line (line-number-at-pos)
          :column (current-column)
          :text (buffer-substring-no-properties
                 (line-beginning-position) (line-end-position)))))

(defun maf-options-spec--text ()
  "The whole options buffer, as plain text."
  (maf-options-spec--in-buffer
    (buffer-substring-no-properties (point-min) (point-max))))

(defun maf-options-spec--header ()
  "The rendered header line."
  (maf-options-spec--in-buffer
    (substring-no-properties (format-mode-line header-line-format))))

;;; Faces, compared by what they look like

(defconst maf-options-spec--attributes
  '(:foreground :background :underline :weight :box :inverse-video :extend)
  "Face attributes the spec compares.
The ones maf-options' faces actually vary; comparing all attributes
would pin theme noise instead of the buffer's own styling.")

(defun maf-options-spec--resolve-face (face)
  "Resolve FACE, a `face' text property value, to an attribute alist.
Face names are not recorded — a rename that keeps the look is not drift
— so each attribute is resolved through inheritance to what the frame
would draw. FACE may be a symbol, an attribute plist, or a list of
either, earlier entries winning, as the display engine merges them."
  (let ((faces (cond ((null face) nil)
                     ((symbolp face) (list face))
                     ((keywordp (car-safe face)) (list face))
                     (t face)))
        out)
    (dolist (attr maf-options-spec--attributes)
      (let ((val 'unspecified))
        (dolist (f faces)
          (when (eq val 'unspecified)
            (cond ((and (symbolp f) (facep f))
                   (setq val (face-attribute f attr nil t)))
                  ((keywordp (car-safe f))
                   (when (plist-member f attr)
                     (setq val (plist-get f attr)))))))
        (unless (memq val '(unspecified nil))
          (push (cons attr val) out))))
    (nreverse out)))

(defun maf-options-spec--segments (beg end)
  "Every faced stretch between BEG and END: (LINE TEXT ATTRIBUTES).
Unfaced text is skipped — it is already pinned by the plain-text
capture — so this records where the styling sits and what it does."
  (let ((pos beg) segs)
    (while (< pos end)
      (let ((next (next-single-property-change pos 'face nil end))
            (face (get-text-property pos 'face)))
        (when face
          (push (list (line-number-at-pos pos)
                      (buffer-substring-no-properties pos next)
                      (maf-options-spec--resolve-face face))
                segs))
        (setq pos next)))
    (nreverse segs)))

(defun maf-options-spec--faces ()
  "Faced stretches of the whole options buffer."
  (maf-options-spec--in-buffer
    (maf-options-spec--segments (point-min) (point-max))))

(defun maf-options-spec--line-faces ()
  "Faced stretches of the current line."
  (maf-options-spec--in-buffer
    (maf-options-spec--segments (line-beginning-position)
                                (line-end-position))))

;;; Reaching into calc

(defun maf-options-spec--calc-var (var)
  "VAR's value in the calc buffer, where the mode variables are local."
  (buffer-local-value var (get-buffer "*Calculator*")))

;;; The tour

(defconst maf-options-spec--keys
  '("TAB" "<backtab>" "SPC" "RET" "d" "c" "K" "S" "g" "l" "h"
    "j" "k" "n" "p" "M-n" "M-p" "q")
  "Keys whose bindings the spec records.")

(defun maf-options-spec--bindings ()
  "Alist of key to the command it runs in the options buffer.
Compared after prefix-stripping — see `maf-options-spec--normalize'."
  (maf-options-spec--in-buffer
    (mapcar (lambda (key)
              (cons key (let ((cmd (key-binding (kbd key))))
                          (and (symbolp cmd) cmd))))
            maf-options-spec--keys)))

(defun maf-options-spec--steps (keys &optional extra)
  "Press each of KEYS in turn, recording what each press did.
Each step holds the key, its messages and error, and where point ended
up. EXTRA, when given, is called after each press for scenario-specific
state — a calc variable, the row's rendering — appended as :extra."
  (mapcar (lambda (key)
            (append (list :key key)
                    (maf-options-spec--press key)
                    (list :at (maf-options-spec--where))
                    (when extra (list :extra (funcall extra)))))
          keys))

(defun maf-options-spec-capture ()
  "Drive *maf-options* in the live instance; return what it observably did.
Resets calc first, so the capture always starts from the same world —
without that, record and check would compare different settings, not
different code. Kills any existing options buffer for a clean open.

The tour's stops, by section: `open' pins the fresh buffer; `bindings'
the keymap; `motion' walks rows and groups from the first row, into the
edges; `step-values' cycles Angle measure there and back; then from the
Precision row, `no-fixed-values' takes the TAB refusal; `pending' walks
to Float format for the prompting-value dance; `changed-only' walks
back to Angle measure, moves it, filters, and resets; `keys-column'
toggles the Calc key column twice; `final' pins the buffer again, which
must match `open'."
  (unless (featurep 'maf-options)
    (error "maf-options is not loaded"))
  (when (get-buffer "*maf-options*")
    (kill-buffer "*maf-options*"))
  (unless (get-buffer "*Calculator*")
    (save-window-excursion (calc)))
  (with-current-buffer "*Calculator*"
    ;; Factory defaults, not saved modes: a nil arg would re-read
    ;; `calc-settings-file', whose `setq' forms run while calc's
    ;; buffer-locals are down and so land on the globals — leaking the
    ;; user's saved modes into every calc buffer made afterwards. The
    ;; zero arg restores `calc-mode-var-list' defaults and never touches
    ;; the file, which also unhooks the recording from whatever that
    ;; file happens to hold.
    (calc-reset 0)
    (maf-options))
  (let ((angle-extra
         (lambda () (list :angle (maf-options-spec--calc-var 'calc-angle-mode)
                          :row (maf-options-spec--line-faces))))
        (float-extra
         (lambda () (list :float (maf-options-spec--calc-var 'calc-float-format)
                          :row (maf-options-spec--line-faces))))
        (filter-extra
         (lambda () (list :angle (maf-options-spec--calc-var 'calc-angle-mode)
                          :buffer (maf-options-spec--text))))
        (column-extra
         (lambda () (list :header (maf-options-spec--header)
                          :buffer (maf-options-spec--text)))))
    (list
     (cons 'open (list :buffer (maf-options-spec--text)
                       :header (maf-options-spec--header)
                       :at (maf-options-spec--where)
                       :faces (maf-options-spec--faces)))
     (cons 'bindings (maf-options-spec--bindings))
     ;; Angle → Precision → Fraction → Symbolic → back to Angle, one
     ;; step past the top (stays), then group motion to Display and
     ;; back, one step past the first group (errors).
     (cons 'motion
           (maf-options-spec--steps
            '("n" "n" "j" "k" "p" "p" "p" "M-n" "M-n" "M-p" "M-p" "M-p")))
     ;; On Angle measure: deg → rad → hms → deg, then backwards around.
     (cons 'step-values
           (maf-options-spec--steps
            '("TAB" "TAB" "TAB" "<backtab>" "<backtab>" "<backtab>")
            angle-extra))
     ;; Down to Precision, whose values are open: TAB refuses.
     (cons 'no-fixed-values (maf-options-spec--steps '("n" "TAB")))
     ;; Over to Float format: TAB onto "fixed point" marks it pending,
     ;; TAB again moves past and sets scientific, d restores the default.
     (cons 'pending
           (maf-options-spec--steps
            '("M-n" "M-n" "n" "TAB" "TAB" "d")
            float-extra))
     ;; Back up to Angle measure: move it, narrow to changed, widen,
     ;; reset.
     (cons 'changed-only
           (maf-options-spec--steps
            '("M-p" "M-p" "M-p" "TAB" "c" "c" "d")
            filter-extra))
     (cons 'keys-column (maf-options-spec--steps '("K" "K") column-extra))
     (cons 'final (list :buffer (maf-options-spec--text)
                        :header (maf-options-spec--header)
                        :at (maf-options-spec--where))))))

;;; Recording and checking

(defun maf-options-spec-record ()
  "Capture the live behavior and write it to `maf-options-spec-file'."
  (interactive)
  (let ((spec (maf-options-spec-capture))
        (print-length nil)
        (print-level nil))
    (with-temp-file maf-options-spec-file
      (pp spec (current-buffer))))
  (format "recorded %s" maf-options-spec-file))

(defun maf-options-spec-check ()
  "Re-capture and diff against the recording.
Returns a summary string; mismatches are listed in *options-spec-diff*."
  (interactive)
  (unless (file-exists-p maf-options-spec-file)
    (error "No recording — run `maf-options-spec-record' first"))
  (let* ((expected (with-temp-buffer
                     (insert-file-contents maf-options-spec-file)
                     (read (current-buffer))))
         (actual (maf-options-spec-capture))
         (diffs (maf-options-spec--diff expected actual nil)))
    (if (null diffs)
        "options spec: PASS"
      (maf-options-spec--report diffs)
      (format "options spec: FAIL — %d mismatches, see *options-spec-diff*"
              (length diffs)))))

(defun maf-options-spec--normalize (value path)
  "Strip the package prefix off a command name under the bindings section.
The refactor renames commands; what the spec holds is the key's role,
so maf-options-set and dial-set compare equal while a key that changed
roles does not."
  (if (and (memq 'bindings path) value (symbolp value))
      (intern (string-remove-prefix
               "maf-"
               (string-remove-prefix
                "dial-"
                (string-remove-prefix "maf-options-" (symbol-name value)))))
    value))

(defun maf-options-spec--diff (exp act path)
  "Structural diff of EXP against ACT: a list of (PATH EXPECTED ACTUAL).
PATH labels the route down to each mismatching leaf — section names,
plist keys, alist cars, list indices — so a failure says which step of
which scenario moved, not just that something did."
  (let ((exp (maf-options-spec--normalize exp path))
        (act (maf-options-spec--normalize act path)))
    (cond
     ((equal exp act) nil)
     ;; A tagged section: (NAME :key value ...). Descend into the plist
     ;; under the name.
     ((and (consp exp) (consp act)
           (symbolp (car exp)) (car exp) (not (keywordp (car exp)))
           (equal (car exp) (car act))
           (keywordp (car-safe (cdr exp))))
      (maf-options-spec--diff (cdr exp) (cdr act) (cons (car exp) path)))
     ((and (proper-list-p exp) (proper-list-p act)
           exp act (= (length exp) (length act)))
      (if (keywordp (car exp))
          ;; A plist: compare value by key.
          (cl-loop for (k v) on exp by #'cddr
                   for (k2 v2) on act by #'cddr
                   append (if (eq k k2)
                              (maf-options-spec--diff v v2 (cons k path))
                            (list (list (reverse path) exp act))))
        ;; A list: element by element, labelled by an element's own car
        ;; when it has a stable one, else by position.
        (cl-loop for e in exp
                 for a in act
                 for i from 0
                 append (maf-options-spec--diff
                         e a
                         (cons (if (and (consp e) (consp a)
                                        (atom (car e)) (not (keywordp (car e)))
                                        (equal (car e) (car a)))
                                   (car e)
                                 i)
                               path)))))
     ((and (consp exp) (consp act))
      (append (maf-options-spec--diff (car exp) (car act) (cons 'car path))
              (maf-options-spec--diff (cdr exp) (cdr act) (cons 'cdr path))))
     (t (list (list (reverse path) exp act))))))

(defun maf-options-spec--show (value other)
  "Render VALUE for the report, trimmed around its divergence from OTHER.
A whole-buffer string dumped twice buries the one character that
differs; showing the neighborhood of the first mismatch is what makes
the report readable."
  (if (and (stringp value) (stringp other)
           (> (max (length value) (length other)) 120))
      (let* ((n (min (length value) (length other)))
             (i 0))
        (while (and (< i n) (eq (aref value i) (aref other i)))
          (setq i (1+ i)))
        (format "…%S… (diverges at %d)"
                (substring value (max 0 (- i 40))
                           (min (length value) (+ i 60)))
                i))
    (format "%S" value)))

(defun maf-options-spec--report (diffs)
  "Write DIFFS into the *options-spec-diff* buffer."
  (with-current-buffer (get-buffer-create "*options-spec-diff*")
    (erase-buffer)
    (dolist (d diffs)
      (pcase-let ((`(,path ,exp ,act) d))
        (insert (format "at %S\n  recorded: %s\n  now:      %s\n\n"
                        path
                        (maf-options-spec--show exp act)
                        (maf-options-spec--show act exp)))))
    (goto-char (point-min))))

(provide 'maf-options-spec)
