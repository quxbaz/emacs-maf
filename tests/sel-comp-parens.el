;; The selection composition must keep the parens DIV forces around a
;; denominator product (maf--comp-compose-keep-div in core/maf-comp.el).
;; Upstream drops them, so on this entry every column after "(" resolved
;; shifted and the last two columns — the ":" and final "3" of the
;; trailing frac — resolved to nothing: RET errored and j e did nothing.

(maf-step
  (maf-push "y = 8 / (3 x^3) - 5:3")
  (cl-assert (string= (buffer-substring-no-properties
                       (point-min) (progn (goto-char (point-min))
                                          (line-end-position)))
                      "1:  y = 8 / (3 x^3) - 5:3"))

  ;; Every column of the formula text resolves to some sub-formula —
  ;; before the fix the walk ran off the end two columns early.
  (progn (goto-char (point-min))
         (re-search-forward "^1: +")
         (cl-loop for pos from (point) below (line-end-position)
                  do (goto-char pos)
                     (calc-prepare-selection)
                     (cl-assert (calc-find-selected-part) nil
                                "no sub-formula at column %d"
                                (current-column))))

  ;; All three columns of the frac resolve to the frac itself, and the
  ;; "(" to the product it brackets — WYSIWYG, not shifted.
  (progn (goto-char (point-min))
         (search-forward "5:3")
         (cl-loop for pos from (match-beginning 0) below (match-end 0)
                  do (goto-char pos)
                     (calc-prepare-selection)
                     (cl-assert (equal (calc-find-selected-part)
                                       '(frac 5 3)))))
  (progn (goto-char (point-min))
         (search-forward "(")
         (backward-char 1)
         (calc-prepare-selection)
         (cl-assert (equal (maf--strip-encasing (calc-find-selected-part))
                           '(* 3 (^ (var x var-x) 3)))))

  ;; RET on the ":" dups the frac.
  (progn (goto-char (point-min)) (search-forward "5:3") (backward-char 2))
  (call-interactively 'maf-dup-or-clear-selections)
  (cl-assert (= (calc-stack-size) 2))
  (cl-assert (equal (calc-top 1 'full) '(frac 5 3)))
  (calc-pop 1)

  ;; j e on the ":" moves the frac across the equation, and the
  ;; committed render keeps the denominator's parens — the rewrite
  ;; re-renders from the selection composition, so a dropped DIV showed
  ;; here as "8 / 3 x^3" until the next refresh.
  (progn (goto-char (point-min)) (search-forward "5:3") (backward-char 2))
  (call-interactively 'maf-jump-equals)
  (cl-assert (string= (buffer-substring-no-properties
                       (point-min) (progn (goto-char (point-min))
                                          (line-end-position)))
                      "1:  y + 5:3 = 8 / (3 x^3)"))
  (cl-assert (equal (maf--strip-encasing (calc-top 1 'full))
                    '(calcFunc-eq (+ (var y var-y) (frac 5 3))
                                  (/ 8 (* 3 (^ (var x var-x) 3))))))
  (calc-pop 1)

  ;; The classic shape from the quirks doc. Prec-forced parens (the
  ;; numerator's) always survived tagging; DIV-forced parens (the
  ;; denominator's) now do too, so every column is WYSIWYG — before the
  ;; fix the ( of (e f) named e, the space named f, and f named nothing.
  (maf-push "(a + b)^(c - d) / (e f)")
  (progn (goto-char (point-min))
         (re-search-forward "^1: +")
         (cl-loop for pos from (point) below (line-end-position)
                  do (goto-char pos)
                     (calc-prepare-selection)
                     (cl-assert (calc-find-selected-part) nil
                                "no sub-formula at column %d"
                                (current-column))))
  (progn (goto-char (point-min)) (search-forward "(e") (backward-char 2)
         (calc-prepare-selection)
         (cl-assert (equal (maf--strip-encasing (calc-find-selected-part))
                           '(* (var e var-e) (var f var-f)))))
  (progn (goto-char (point-min)) (search-forward "f)") (backward-char 2)
         (calc-prepare-selection)
         (cl-assert (equal (maf--strip-encasing (calc-find-selected-part))
                           '(var f var-f))))
  (progn (goto-char (point-min)) (search-forward "f)") (backward-char 1)
         (calc-prepare-selection)
         (cl-assert (equal (maf--strip-encasing (calc-find-selected-part))
                           '(* (var e var-e) (var f var-f)))))
  (progn (goto-char (point-min)) (search-forward "(a") (backward-char 2)
         (calc-prepare-selection)
         (cl-assert (equal (maf--strip-encasing (calc-find-selected-part))
                           '(+ (var a var-a) (var b var-b)))))
  ;; Whole-formula extent — once two columns short of the display.
  (progn (goto-char (point-min)) (search-forward " / ") (backward-char 2)
         (calc-prepare-selection)
         (let ((bounds (maf--comp-find-bounds)))
           (cl-assert (string= (buffer-substring-no-properties
                                (car bounds) (cdr bounds))
                               "(a + b)^(c - d) / (e f)"))))
  (calc-pop 1)

  ;; The selected-display path: rendering an active selection composes
  ;; through `math-comp-selected' and hits the same dropped-DIV branch,
  ;; so a selected denominator lost its parens on screen (". . e f").
  (maf-push "2 / (e f)")
  (progn (goto-char (point-min)) (search-forward "(e ") (backward-char 1)
         (calc-select-here nil))
  (cl-assert (string-match-p "1\\*  \\. \\. (e f)"
                             (buffer-substring-no-properties
                              (point-min)
                              (progn (goto-char (point-min))
                                     (line-end-position)))))
  (progn (calc-unselect 1) (calc-pop 1)))
