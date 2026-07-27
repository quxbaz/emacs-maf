;; maf-roll-to-bottom: bury the entry at point at the deepest stack level.

(maf-step
  ;; Three entries: 3: 5 / 2: 7 / 1: 9.
  (calc-push 5)
  (calc-push 7)
  (calc-push 9)
  (calc-refresh)

  ;; At home the top entry is buried: 9 sinks to level 3, the rest slide
  ;; down one. Point stays home.
  (goto-char (point-max))
  (call-interactively 'maf-roll-to-bottom)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "7"))
  (cl-assert (string= (math-format-value (calc-top 2 'full)) "5"))
  (cl-assert (string= (math-format-value (calc-top 3 'full)) "9"))
  (cl-assert (maf--at-home-p))

  ;; Mid-stack (level 2): 5 sinks to level 3, the entry that was one line
  ;; above (9) lands on the line at point, level 1 untouched.
  (progn (goto-char (point-min)) (search-forward "2:  5") (backward-char 1))
  (call-interactively 'maf-roll-to-bottom)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "7"))
  (cl-assert (string= (math-format-value (calc-top 2 'full)) "9"))
  (cl-assert (string= (math-format-value (calc-top 3 'full)) "5"))
  (cl-assert (= (calc-locate-cursor-element (point)) 2))
  (cl-assert (looking-at "9"))

  ;; A single undo reverts the roll, point included.
  (progn (setq last-command nil) (call-interactively 'maf-undo))
  (cl-assert (string= (math-format-value (calc-top 2 'full)) "5"))
  (cl-assert (string= (math-format-value (calc-top 3 'full)) "9"))
  (cl-assert (= (calc-locate-cursor-element (point)) 2))

  ;; The deepest entry is already at the bottom: no-op, point untouched,
  ;; and no undo group recorded for it (the next undo still reverts the
  ;; push, not a phantom roll).
  (progn (goto-char (point-min)) (search-forward "3:  9") (backward-char 1))
  (call-interactively 'maf-roll-to-bottom)
  (cl-assert (string= (math-format-value (calc-top 3 'full)) "9"))
  (cl-assert (= (calc-locate-cursor-element (point)) 3))
  (cl-assert (looking-at "9"))

  ;; Point in the line-number prefix keeps its column in the margin.
  (progn (goto-char (point-min)) (search-forward "1:  ") (backward-char 3))
  (cl-assert (maf--at-line-prefix-p))
  (call-interactively 'maf-roll-to-bottom)
  (cl-assert (= (calc-locate-cursor-element (point)) 1))
  (cl-assert (maf--at-line-prefix-p))

  ;; A single entry has nothing to bury: no-op, no error.
  (calc-pop 2)
  (progn (goto-char (point-min)) (search-forward "1:  ") (backward-char 0))
  (call-interactively 'maf-roll-to-bottom)
  (cl-assert (= (calc-stack-size) 1))

  ;; An empty stack is a no-op too, not an error.
  (calc-pop 1)
  (goto-char (point-max))
  (call-interactively 'maf-roll-to-bottom)
  (cl-assert (= (calc-stack-size) 0))

  ;; Selections travel with their entries, and the rolled values are not
  ;; spliced into them (calc's own roll corrupts the entry here).
  (maf-push "20 x + 10")
  (maf-push "7")
  (maf-push "9")
  (calc-refresh)
  (progn (goto-char (point-min)) (search-forward "3:  ") (backward-char 0))
  (call-interactively 'calc-select-here)
  (cl-assert (string= (math-format-value (calc-top 3 'sel)) "20"))
  (goto-char (point-max))
  (call-interactively 'maf-roll-to-bottom)
  ;; 9 buried; "20 x + 10" slid from level 3 to level 2, intact...
  (cl-assert (string= (math-format-value (calc-top 3 'full)) "9"))
  (cl-assert (string= (math-format-value (calc-top 2 'full)) "20 x + 10"))
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "7"))
  ;; ...carrying its selection to the level it landed on.
  (cl-assert (string= (math-format-value (calc-top 2 'sel)) "20"))
  (cl-assert (null (calc-top 3 'sel)))
  (calc-clear-selections)

  ;; Entries of differing width: the column is kept, clamped to the end
  ;; of the arriving entry's line.
  (calc-pop (calc-stack-size))
  (maf-push "1")
  (maf-push "sin(2 x + 1)")
  (maf-push "3")
  (calc-refresh)
  (progn (goto-char (point-min)) (search-forward "2:  sin(2 x") (backward-char 1))
  (cl-assert (= (current-column) 10))
  (call-interactively 'maf-roll-to-bottom)
  ;; "sin(2 x + 1)" buried at level 3; "1" arrives at level 2 and is far
  ;; shorter than point's column, so point clamps to its end of line.
  (cl-assert (string= (math-format-value (calc-top 3 'full)) "sin(2 x + 1)"))
  (cl-assert (string= (math-format-value (calc-top 2 'full)) "1"))
  (cl-assert (= (calc-locate-cursor-element (point)) 2))
  (cl-assert (eolp))

  ;; End-of-line affinity stays at end of line, on whatever arrives.
  (progn (goto-char (point-min)) (search-forward "3:  sin(2 x + 1)") (end-of-line))
  (call-interactively 'maf-roll-to-bottom)
  (cl-assert (= (calc-locate-cursor-element (point)) 3))
  (cl-assert (eolp))

  ;; Multi-line entries: point returns to its stack level, not to the
  ;; screen line it was on — the block heights change under it.
  (calc-pop (calc-stack-size))
  (calc-big-language)
  (maf-push "1")
  (maf-push "x/y")
  (maf-push "3")
  (calc-refresh)
  (progn (goto-char (point-min)) (search-forward "1:") (backward-char 2))
  (cl-assert (= (calc-locate-cursor-element (point)) 1))
  (call-interactively 'maf-roll-to-bottom)
  ;; 3 buried at level 3; the three-line x/y block now occupies level 1.
  ;; Structural comparison: `math-format-value' renders multi-line here.
  (cl-assert (equal (calc-top 3 'full) 3))
  (cl-assert (equal (calc-top 1 'full) '(/ (var x var-x) (var y var-y))))
  (cl-assert (= (calc-locate-cursor-element (point)) 1))
  ;; Point is on the first line of that block, where the level index
  ;; puts it — a line-based restore would have left it on the last.
  (cl-assert (= (point) (save-excursion (calc-cursor-stack-index 1) (point))))
  (calc-normal-language))
