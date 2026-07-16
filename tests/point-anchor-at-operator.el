(maf-step
  ;; The motivating case: commuting an equation from its = leaves point
  ;; on the =, wherever it moved.
  (maf-push "sin(y) = k")
  (progn (goto-char (point-min)) (search-forward "=") (backward-char 1))
  (call-interactively 'mafcmd-commute)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "k = sin(y)"))
  (cl-assert (eq (char-after) ?=))
  (calc-pop 1)

  ;; Generalizes to other operators — even when the rewrite changes the
  ;; glyph itself (commute flips < to >).
  (maf-push "x < y")
  (progn (goto-char (point-min)) (search-forward "<") (backward-char 1))
  (call-interactively 'mafcmd-commute)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "y > x"))
  (cl-assert (eq (char-after) ?>))
  (calc-pop 1)

  ;; And to non-operator structural glyphs: the comma of a call.
  (maf-push "log(b, x)")
  (progn (goto-char (point-min)) (search-forward ",") (backward-char 1))
  (call-interactively 'mafcmd-commute)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "log(x, b)"))
  (cl-assert (eq (char-after) ?,))
  (calc-pop 1)

  ;; Through relation mapping too: factoring from the = runs per side,
  ;; and point re-anchors on the = of the rebuilt relation.
  (maf-push "6 x + 12 = 18 y + 6")
  (progn (goto-char (point-min)) (search-forward "=") (backward-char 1))
  (call-interactively 'mafcmd-factor-gcd)
  (cl-assert (string= (math-format-value (calc-top 1 'full))
                      "6 (x + 2) = 6 (3 y + 1)"))
  (cl-assert (eq (char-after) ?=))
  (calc-pop 1)

  ;; Point on an atom still restores positionally (no anchor).
  (maf-push "6 x + 12")
  (progn (goto-char (point-min)) (search-forward "x") (backward-char 1))
  (call-interactively 'mafcmd-commute)
  (cl-assert (eq (char-after) ?x))
  (calc-pop 1))
