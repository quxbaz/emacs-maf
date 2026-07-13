;; -*- lexical-binding: t; -*-
;;
;; maf-lib.el
;;
;; maf library functions

(require 'calc)

;; Defined in lazily-loaded calc modules; calc-ext's autoload registry
;; resolves them at runtime, but the byte compiler needs declarations.
(declare-function calc-push "calc-ext")
(declare-function calc-top "calc-ext")
(declare-function calc-locate-cursor-element "calc-yank")
(declare-function calc-prepare-selection "calc-sel")
(declare-function calc-find-selected-part "calc-sel")
(declare-function math-read-expr "calc-aent")

(defun maf--find-calc-buffer ()
  "Find the calc buffer.
Prefers the current buffer if it is in calc-mode, then the buffer named
*Calculator* provided it really is in calc-mode, then falls back to any
live buffer in calc-mode (catching a renamed calc buffer)."
  (cond
   ((derived-mode-p 'calc-mode) (current-buffer))
   ((let ((buf (get-buffer "*Calculator*")))
      (and buf
           (with-current-buffer buf (derived-mode-p 'calc-mode))
           buf)))
   (t (cl-find-if (lambda (buf)
                    (with-current-buffer buf (derived-mode-p 'calc-mode)))
                  (buffer-list)))))

(defmacro maf--with-calc-buffer (&rest body)
  "Evaluate BODY in the calc buffer.
Signals an error if no calc buffer exists."
  (declare (indent 0))
  `(with-current-buffer (or (maf--find-calc-buffer)
                            (error "No calc buffer found"))
     ,@body))

(defun maf--at-home-p ()
  "Return t if point is past the last stack entry (at the . line or below)."
  (maf--with-calc-buffer
    (<= (calc-locate-cursor-element (point)) 0)))

(defun maf--at-line-prefix-p ()
  "Return t if point is in the line-number prefix (e.g. '1: ') of a stack entry."
  (maf--with-calc-buffer
    (and (> (calc-locate-cursor-element (point)) 0)
         (not (eolp))
         (save-excursion
           (let ((col (current-column)))
             (beginning-of-line)
             (and (looking-at " *[0-9]+: +")
                  (< col (- (match-end 0) (point)))))))))

(defun maf--at-line-margin-p ()
  "Return t if point is in the line-prefix zone or at EOL on a stack entry line.
Marks the positions outside the formula text — used by the entry target in
the resolve cascade."
  (maf--with-calc-buffer
    (and (> (calc-locate-cursor-element (point)) 0)
         (or (eolp) (maf--at-line-prefix-p)))))

(defun maf--at-subexpr-p ()
  "Return t if point is on a sub-expression within an entry's formula text.
False when point is at EOL or in the line-prefix zone, even if there is a
sub-expression on the line; those positions route to equation/entry targets."
  (maf--with-calc-buffer
    (and (> (calc-locate-cursor-element (point)) 0)
         (not (maf--at-line-margin-p))
         (save-excursion
           (ignore-errors
             (calc-prepare-selection)
             (and (calc-find-selected-part) t))))))

(defun maf--relation-p (expr)
  "Return t if EXPR is a relation (=, !=, <, <=, >, >=)."
  (and (consp expr)
       (memq (car expr) '(calcFunc-eq calcFunc-neq calcFunc-lt
                          calcFunc-leq calcFunc-gt calcFunc-geq))
       t))

(defun maf--at-equation-p ()
  "Return t if the stack entry under point is a relation (=, !=, <, <=, >, >=)."
  (maf--with-calc-buffer
    (let ((idx (calc-locate-cursor-element (point))))
      (and (> idx 0)
           (maf--relation-p (calc-top idx 'full))))))

(defun maf--point-snapshot ()
  "Capture point's placement in the current calc buffer as an alist.
Records the buffer position (:pos), line (:line), and semantic affinity
\(:affinity): `home' when point is at or below the . line, `eol' at end
of line, `bol' in the line-number prefix, else nil. Consumed by
`maf--point-restore'."
  `((:pos      . ,(point))
    (:line     . ,(line-number-at-pos))
    (:affinity . ,(cond ((maf--at-home-p) 'home)
                        ((eolp) 'eol)
                        ((maf--at-line-prefix-p) 'bol)))))

(defun maf--point-restore (snapshot)
  "Restore point from SNAPSHOT (see `maf--point-snapshot').
Calc commands that rewrite the stack buffer park point at home; this
puts it back where the user had it. A `home' snapshot is a no-op —
calc's default placement already matches. Otherwise point returns to
its previous buffer position, corrected back to the original line when
the rewrite shifted it, and EOL/BOL affinity is re-applied on the line
rather than the exact position."
  (let ((affinity (alist-get :affinity snapshot)))
    (unless (eq affinity 'home)
      (goto-char (alist-get :pos snapshot))
      (let ((line (alist-get :line snapshot)))
        (when (/= (line-number-at-pos) line)
          (goto-char (point-min))
          (forward-line (1- line))))
      (pcase affinity
        ('eol (end-of-line))
        ('bol (beginning-of-line))))))

(defmacro maf--preserve-point (&rest forms)
  "Evaluate FORMS, then restore point's line, position, and affinity.
Snapshots point placement before FORMS run (`maf--point-snapshot') and
restores it after (`maf--point-restore')."
  (declare (indent 0))
  (let ((snapshot (gensym "snapshot-")))
    `(let ((,snapshot (maf--point-snapshot)))
       (prog1 (progn ,@forms)
         (maf--point-restore ,snapshot)))))

(defun maf-push (expr)
  "Parse algebraic EXPR and push it onto the calc stack.
A convenience over pushing a raw calc s-expression: instead of
\(calc-push \\='(+ (* 8 (var x var-x)) 4)) write (maf-push \"8 x + 4\").

EXPR is normally an algebraic string, parsed with `math-read-expr' in the
current language mode. A number or an already-parsed calc formula is pushed
as-is. Signals an error if the string does not parse."
  (interactive "sPush formula: ")
  (maf--with-calc-buffer
    (let ((val (if (stringp expr) (math-read-expr expr) expr)))
      (when (and (consp val) (eq (car val) 'error))
        (error "maf-push: cannot parse %S: %s" expr (nth 2 val)))
      (calc-push val))))

(provide 'maf-lib)
