;; -*- lexical-binding: t; -*-
;;
;; maf-hl-sweep.el
;;
;; Exhaustive regression sweep of maf-hl-mode over many expression types.
;; For every character position of every rendered entry, the maf-hl overlay
;; is compared against two oracles that share no code with maf-hl:
;;
;;   presence — `calc-find-selected-part': what calc's own selection
;;              machinery resolves at point.
;;   extent   — calc's selection renderer: render the entry with the found
;;              part as the selection and `calc-show-selections' t, so every
;;              unselected char becomes "."; the visible span must equal the
;;              overlay span (single-line entries only).
;;
;; Positions where calc's own resolution is known to drift are classified
;; as :quirks, not failures; see docs/memory/calc-selection-quirks.md.
;;
;; Run headless (seconds, no GUI needed):
;;
;;   emacs --batch -l maf.el -l debug/maf-hl-sweep.el \
;;         --eval '(pp (maf-hl-sweep-main "/tmp/hl-sweep-report.el"))'
;;
;; or in a live session over emacsclient (see
;; docs/memory/piloting-emacs.md):
;;
;;   emacsclient --eval '(progn (load-file ".../debug/maf-hl-sweep.el")
;;                              (maf-hl-sweep-main "/tmp/hl-sweep-report.el"))'
;;
;; The return value is a compact summary; the full per-expression report
;; (display text, distinct highlight spans, mismatches, quirks, errors) is
;; pretty-printed to OUT-FILE. A clean run has :problem-exprs nil.

(require 'cl-lib)
(require 'seq)
(require 'calc)
(require 'calc-aent)
(require 'calc-lang)
(require 'calc-sel)
(require 'calc-yank)
(require 'maf-hl)

;; Valueless defvars elsewhere are special only in their own files;
;; redeclare so our let-bindings and reads of them are dynamic.
(defvar math-comp-pos)
(defvar math-comp-sel-tag)
(defvar calc-selection-cache-comp)
(defvar calc-selection-cache-offset)
(defvar maf--comp-flat-start)
(defvar maf--comp-flat-end)

(defvar maf-hl-sweep-exprs
  '("2 (3 x + 4)"
    "x^2 + 2 x + 1"
    "(a + b)^(c - d) / (e f)"
    "sin(2 pi t) + cos(omega t)"
    "sqrt(x^2 + y^2)"
    "3:4 + 5:7 x"
    "1.5e10 + 2.25 y"
    "(2, 3) * (1, -1)"
    "[1, 2, 3, x]"
    "[[1, 2], [3, 4]]"
    "x = 2 y + 1"
    "a <= b + c"
    "-x - 5"
    "abs(-x) + floor(y / 2)"
    "[1 .. 5)"
    "12 mod 7"
    "x_1 + x_2^2"
    "f(x, y) + g(z)"
    "deriv(sin(x) x^2, x)"
    "exp(x) / (1 + exp(x))"
    "2^(n + 1) - 1"
    "((((a + 1) b + 2) c + 3) d + 4)"
    "16#FF + 2#1010"
    "2@ 30' 15\""
    "inf - uinf"
    "phi^2 - phi - 1")
  "Algebraic strings covering distinct calc formula types.")

(defun maf-hl-sweep--mask-span (part beg)
  "Expected (START . END) of PART per calc's selection renderer, or nil.
BEG is the buffer position of the entry's first line. Returns strict
bounds; boundary chars that are spaces or dots in the source are ambiguous
in the mask, so callers should tolerate small differences there. Only
valid for single-line entries."
  (let* ((entry calc-selection-cache-entry)
         (mask (let ((calc-show-selections t)
                     (calc-highlight-selections-with-faces nil))
                 (math-format-stack-value (list (car entry) (nth 1 entry) part))))
         (offset calc-selection-cache-offset)
         (first nil) (last nil))
    (unless (string-match-p "\n" mask)
      (dotimes (i (- (length mask) offset))
        (let ((c (aref mask (+ offset i))))
          (unless (memq c '(?. ?\s))
            (unless first (setq first i))
            (setq last i))))
      (when first
        (cons (+ beg offset first) (+ beg offset last 1))))))

(defun maf-hl-sweep--walker-length ()
  "Total character length of the cached composition per the flat walker.
When this differs from the rendered text length, the renderer synthesized
characters (parens from set/break level markers) that calc's selection
walker does not count — an upstream calc quirk that shifts selection
resolution at positions after them."
  (let ((math-comp-pos 0)
        (math-comp-sel-cpos -1)
        (math-comp-sel-tag nil)
        (maf--comp-flat-start nil)
        (maf--comp-flat-end nil))
    (maf--comp-flat-term calc-selection-cache-comp)
    math-comp-pos))

(defun maf-hl-sweep-entry (m)
  "Sweep every position of stack entry M; return a result plist."
  (let* ((beg (save-excursion (calc-cursor-stack-index m) (point)))
         (end (save-excursion (calc-cursor-stack-index (1- m)) (point)))
         (single-line (not (string-match-p
                            "\n" (buffer-substring beg (1- end)))))
         (synth-parens nil)
         (spans (make-hash-table :test 'equal))
         (flat 'unknown)
         (positions 0)
         mismatches quirks errors)
    (goto-char beg)
    (while (< (point) end)
      (setq positions (1+ positions))
      (condition-case e
          (let* ((part
                  (save-excursion
                    (let ((idx (calc-locate-cursor-element (point))))
                      (when (> idx 0)
                        (calc-prepare-selection idx)
                        (when (eq flat 'unknown)
                          (setq flat (and (math-comp-is-flat
                                           calc-selection-cache-comp)
                                          t))
                          (when (and (eq flat t) single-line)
                            (setq synth-parens
                                  (/= (maf-hl-sweep--walker-length)
                                      (- (- end beg 1)
                                         calc-selection-cache-offset)))))
                        (calc-find-selected-part)))))
                 (ov (progn
                       (maf-hl--update)
                       (and maf-hl--overlay (overlay-buffer maf-hl--overlay)
                            (cons (overlay-start maf-hl--overlay)
                                  (overlay-end maf-hl--overlay))))))
            ;; Geometry invariants.
            (when ov
              (cl-incf (gethash (buffer-substring-no-properties
                                 (car ov) (cdr ov))
                                spans 0))
              (unless (and (<= (car ov) (point)) (< (point) (cdr ov)))
                ;; calc resolves the preceding term at line-break gaps and
                ;; after synthesized parens; mirroring that is intended.
                (if (or synth-parens (memq (char-after) '(?\s ?\n)))
                    (push (list (point) 'not-covering-point ov) quirks)
                  (push (list (point) 'not-covering-point ov) mismatches)))
              (unless (and (>= (car ov) beg) (< (cdr ov) end))
                (push (list (point) 'outside-entry ov) mismatches)))
            ;; Presence must match calc's resolver (flat entries only;
            ;; non-flat renderings legitimately show no highlight).
            (cond
             ((and (eq flat t) part (not ov))
              (push (list (point) 'missing-highlight) mismatches))
             ((and (eq flat t) ov (not part))
              (push (list (point) 'spurious-highlight ov) mismatches))
             ((and (not (eq flat t)) ov)
              (push (list (point) 'highlight-on-nonflat ov) mismatches)))
            ;; Extent must match calc's selection renderer.
            (when (and (eq flat t) single-line part ov)
              (let ((want (save-excursion (maf-hl-sweep--mask-span part beg))))
                (when (and want (not (equal want ov)))
                  ;; Tolerate boundary chars the mask cannot express:
                  ;; spaces and literal dots at the span edges.
                  (unless (and (<= (abs (- (car want) (car ov))) 1)
                               (<= (abs (- (cdr want) (cdr ov))) 1)
                               (seq-every-p
                                (lambda (p) (memq (char-after p) '(?. ?\s)))
                                (number-sequence
                                 (min (car want) (car ov))
                                 (1- (max (car want) (car ov))))))
                    ;; With synthesized parens the walker's (and thus calc's
                    ;; own) coordinates drift from the rendered text; extent
                    ;; divergence there is upstream.
                    (let ((item (list (point) 'extent
                                      :got (buffer-substring-no-properties
                                            (car ov) (cdr ov))
                                      :want (buffer-substring-no-properties
                                             (car want) (cdr want)))))
                      (if synth-parens
                          (push item quirks)
                        (push item mismatches))))))))
        (error (push (list (point) e) errors)))
      (forward-char 1))
    (list :flat flat :single-line single-line :synth-parens synth-parens
          :positions positions
          :spans (let (l)
                   (maphash (lambda (k v) (push (cons k v) l)) spans)
                   (sort l (lambda (a b) (< (length (car a)) (length (car b))))))
          :mismatches (nreverse mismatches)
          :quirks (nreverse quirks)
          :errors (nreverse errors))))

(defun maf-hl-sweep--display (m)
  (save-excursion
    (let ((beg (progn (calc-cursor-stack-index m) (point)))
          (end (progn (calc-cursor-stack-index (1- m)) (point))))
      (buffer-substring-no-properties beg (1- end)))))

(defun maf-hl-sweep-run ()
  "Run the full sweep in the current calc buffer; return the report."
  (let (report)
    ;; One entry at a time, every expression type.
    (dolist (s maf-hl-sweep-exprs)
      (let ((v (math-read-expr s)))
        (if (and (consp v) (eq (car v) 'error))
            (push (list :expr s :parse-error (nth 2 v)) report)
          (calc-push v)
          (push (append (list :expr s :display (maf-hl-sweep--display 1))
                        (maf-hl-sweep-entry 1))
                report)
          (calc-pop 1))))
    ;; Entry other than the top of the stack.
    (calc-push (math-read-expr "a + b"))
    (calc-push (math-read-expr "c (d - e)"))
    (calc-push (math-read-expr "f^2"))
    (push (append (list :expr "c (d - e) [at stack level 2]"
                        :display (maf-hl-sweep--display 2))
                  (maf-hl-sweep-entry 2))
          report)
    (calc-pop 3)
    ;; Wrapped entry: long formula spanning continuation lines.
    (calc-push (math-read-expr
                (mapconcat (lambda (i)
                             (format "%d longvariablename%d" (* 1111 i) i))
                           '(1 2 3 4 5 6) " + ")))
    (push (append (list :expr "long wrapped sum"
                        :display (maf-hl-sweep--display 1))
                  (maf-hl-sweep-entry 1))
          report)
    (calc-pop 1)
    ;; No line numbers: prefix offset changes.
    (let ((calc-line-numbering nil))
      (calc-refresh)
      (calc-push (math-read-expr "sin(x)^2 + cos(x)^2"))
      (push (append (list :expr "sin(x)^2 + cos(x)^2 [no line numbers]"
                          :display (maf-hl-sweep--display 1))
                    (maf-hl-sweep-entry 1))
            report)
      (calc-pop 1))
    (calc-refresh)
    ;; Big language mode: multi-line rendering, expect no highlights.
    (calc-big-language)
    (calc-push (math-read-expr "x / (y + 1) + z^2"))
    (push (append (list :expr "x / (y + 1) + z^2 [Big mode]"
                        :display (maf-hl-sweep--display 1))
                  (maf-hl-sweep-entry 1))
          report)
    (calc-pop 1)
    (calc-normal-language)
    (nreverse report)))

(defun maf-hl-sweep-main (out-file)
  "Fresh calc, run the sweep, write the full report to OUT-FILE.
Return a compact summary plist; a clean run has :problem-exprs nil."
  (dolist (name '("*Calculator*" "*Calc Trail*"))
    (when (get-buffer name) (kill-buffer name)))
  (let ((calc-display-trail nil)) (calc))
  (with-current-buffer "*Calculator*"
    (when (and (fboundp 'my/calc-debug-highlight-mode)
               (bound-and-true-p my/calc-debug-highlight-mode))
      (my/calc-debug-highlight-mode -1))
    (when (> (calc-stack-size) 0)
      (calc-pop (calc-stack-size)))
    (maf-hl-mode 1)
    (let* ((report (maf-hl-sweep-run))
           (bad (seq-filter (lambda (r) (or (plist-get r :mismatches)
                                            (plist-get r :errors)
                                            (plist-get r :parse-error)))
                            report)))
      (with-temp-file out-file
        (pp report (current-buffer)))
      (list :exprs (length report)
            :positions (apply #'+ (mapcar (lambda (r)
                                            (or (plist-get r :positions) 0))
                                          report))
            :distinct-spans (apply #'+ (mapcar (lambda (r)
                                                 (length (plist-get r :spans)))
                                               report))
            :calc-quirks (apply #'+ (mapcar (lambda (r)
                                              (length (plist-get r :quirks)))
                                            report))
            :problem-exprs (mapcar (lambda (r)
                                     (list (plist-get r :expr)
                                           (plist-get r :parse-error)
                                           (length (plist-get r :mismatches))
                                           (length (plist-get r :errors))))
                                   bad)))))

(provide 'maf-hl-sweep)
