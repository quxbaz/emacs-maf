;;; Tests for maf--home-snap -- point may rest at home only on the dot.

;; The snap runs on the calc buffer's local `post-command-hook', which
;; the cockpit's own keypresses do not reach, so each case calls the
;; hook function directly after placing point.

(defvar maf-test--mark nil
  "The mark before a snap, for the no-mark-churn checks.")

(maf-step
  (calc-wrapper (maf-push "6 x + 12") (maf-push "a + b"))

  ;; Every off-dot spot in the home section snaps onto the dot:
  ;; below the home line...
  (progn (goto-char (point-max)) (maf--home-snap) nil)
  (cl-assert (looking-at "\\.$"))
  ;; ...the line's tail...
  (progn (end-of-line) (maf--home-snap) nil)
  (cl-assert (looking-at "\\.$"))
  ;; ...and its leading margin.
  (progn (forward-line 0) (maf--home-snap) nil)
  (cl-assert (looking-at "\\.$"))

  ;; On the dot already: a no-op.
  (progn (maf--home-snap) nil)
  (cl-assert (looking-at "\\.$"))

  ;; No mark is pushed by any of it.
  (cl-assert (null (mark t)))

  ;; On a stack entry the snap keeps its hands off.
  (progn (goto-char (point-min)) (search-forward "6 x") (maf--home-snap) nil)
  (cl-assert (looking-back "6 x" (line-beginning-position)))

  ;; A region reaching into home is left standing: point is its live
  ;; end, and moving it would resize the selection.
  (progn (goto-char (point-min)) (search-forward "6 x")
         (push-mark (point) t t) (goto-char (point-max))
         (setq maf-test--mark (point))
         (cl-assert (use-region-p))
         (maf--home-snap)
         (cl-assert (= (point) maf-test--mark))
         (deactivate-mark) nil)

  ;; With line numbering off the dot sits at column 0; the snap lands
  ;; there all the same.
  (calc-line-numbering 0)
  (progn (goto-char (point-max)) (maf--home-snap) nil)
  (cl-assert (looking-at "\\.$"))
  (cl-assert (= (current-column) 0))
  (calc-line-numbering 1))
