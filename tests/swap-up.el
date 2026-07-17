(maf-step
  ;; Three entries: 3: 5 / 2: 7 / 1: 9.
  (calc-push 5)
  (calc-push 7)
  (calc-push 9)
  (calc-refresh)

  ;; At home: the top two swap, point stays home.
  (goto-char (point-max))
  (call-interactively 'maf-swap-up)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "7"))
  (cl-assert (string= (math-format-value (calc-top 2 'full)) "9"))
  (cl-assert (maf--at-home-p))

  ;; On the bottom line (level 1): its entry moves up to level 2; point
  ;; keeps its line, now holding the former level-2 entry.
  (progn (goto-char (point-min)) (search-forward "1:  7") (backward-char 1))
  (call-interactively 'maf-swap-up)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "9"))
  (cl-assert (string= (math-format-value (calc-top 2 'full)) "7"))
  (cl-assert (looking-at "9"))
  (cl-assert (= (line-number-at-pos) 3))

  ;; Mid-stack (level 2): levels 2 and 3 swap; point keeps its line.
  (progn (goto-char (point-min)) (search-forward "2:  7") (backward-char 1))
  (call-interactively 'maf-swap-up)
  (cl-assert (string= (math-format-value (calc-top 2 'full)) "5"))
  (cl-assert (string= (math-format-value (calc-top 3 'full)) "7"))
  (cl-assert (looking-at "5"))
  (cl-assert (= (line-number-at-pos) 2))

  ;; The highest entry has nothing above it: no-op, no error.
  (progn (goto-char (point-min)) (search-forward "3:  7") (backward-char 1))
  (call-interactively 'maf-swap-up)
  (cl-assert (string= (math-format-value (calc-top 3 'full)) "7"))
  (cl-assert (looking-at "7"))

  ;; A single undo reverts one swap.
  (progn (setq last-command nil) (call-interactively 'maf-undo))
  (cl-assert (string= (math-format-value (calc-top 2 'full)) "7"))
  (cl-assert (string= (math-format-value (calc-top 3 'full)) "5"))

  ;; Prefix argument: roll the top 3 by one — level 1 moves to level 3 —
  ;; regardless of point.
  (let ((current-prefix-arg 3)) (call-interactively 'maf-swap-up))
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "7"))
  (cl-assert (string= (math-format-value (calc-top 2 'full)) "5"))
  (cl-assert (string= (math-format-value (calc-top 3 'full)) "9"))

  ;; A single entry has nothing to swap: no-op, no error.
  (calc-pop 2)
  (progn (goto-char (point-min)) (search-forward "9") (backward-char 1))
  (call-interactively 'maf-swap-up)
  (cl-assert (= (calc-stack-size) 1))
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "9"))
  (cl-assert (looking-at "9"))

  ;; Entries of different lengths: point is a screen position — same
  ;; line, same column, whatever entry lands there.
  (calc-pop 1)
  (maf-push "sin(2 x + 1)")
  (maf-push "7")
  (calc-refresh)
  (progn (goto-char (point-min)) (search-forward "1:  7") (backward-char 1))
  (call-interactively 'maf-swap-up)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "sin(2 x + 1)"))
  (cl-assert (= (line-number-at-pos) 2))
  (cl-assert (= (current-column) 4))
  (cl-assert (looking-at "sin"))

  ;; ... and clamps to end of line when the arriving entry is shorter
  ;; than point's column.
  (progn (goto-char (point-min)) (forward-line 1) (end-of-line) (backward-char 1))
  (call-interactively 'maf-swap-up)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "7"))
  (cl-assert (= (line-number-at-pos) 2))
  (cl-assert (eolp))
  (cl-assert (= (current-column) 5)))
