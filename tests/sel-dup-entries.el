;; calc-prepare-selection validates its cache by `equal' on the stack
;; entry alone (calc-sel.el), so with two entries holding the identical
;; formula, preparing one while the other was cached was a false hit:
;; calc-selection-cache-num kept naming the other level, and maf-hl's
;; whole-entry highlight marked the other line (stock calc's j s
;; selects there too). Both entries must have been prepared once —
;; the cache fill encases the entry's atoms in place, so a fresh
;; duplicate is unequal until its own first prepare — which a cursor
;; pass over the lines supplies. maf--comp-prepare-fresh
;; (core/maf-comp.el) empties the cache when the prepared level
;; differs from the cached one.

(defun dup-sel--overlay-line ()
  "Line number the maf-hl overlay starts on, or nil when hidden."
  (and maf-hl--overlay (overlay-buffer maf-hl--overlay)
       (line-number-at-pos (overlay-start maf-hl--overlay))))

(defun dup-sel--visit (line &optional eol)
  "Move point into stack LINE (1-based from the top) and re-highlight.
Point lands mid-formula, or at end of line with EOL."
  (goto-char (point-min))
  (forward-line (1- line))
  (if eol (end-of-line)
    (progn (search-forward "x" (line-end-position)) (backward-char 1)))
  (maf-hl--update))

(maf-step
  (calc-push (math-read-expr "x + 1"))
  (calc-push (math-read-expr "x + 1"))
  (maf-hl-mode 1)

  ;; A pass over both lines prepares (and encases) both entries.
  (progn (dup-sel--visit 1) (dup-sel--visit 2) nil)
  (cl-assert (eql calc-selection-cache-num 1))

  ;; Back on the level-2 line: the cache must follow, not false-hit.
  (progn (dup-sel--visit 1) nil)
  (cl-assert (eql calc-selection-cache-num 2))
  (cl-assert (eql (dup-sel--overlay-line) 1))

  ;; The reported gesture: C-e on the level-1 line highlighted the
  ;; level-2 line while the cache still named level 2.
  (progn (dup-sel--visit 2 'eol) nil)
  (cl-assert (eql calc-selection-cache-num 1))
  (cl-assert (eql (dup-sel--overlay-line) 2))

  ;; And the mirror: end of the level-2 line marks its own line.
  (progn (dup-sel--visit 1 'eol) nil)
  (cl-assert (eql calc-selection-cache-num 2))
  (cl-assert (eql (dup-sel--overlay-line) 1))

  (maf-hl-mode -1)
  (calc-pop (calc-stack-size)))
