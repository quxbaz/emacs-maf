(maf-step
  ;; Four entries: 4: 5 / 3: 7 / 2: 9 / 1: 11.
  (calc-push 5)
  (calc-push 7)
  (calc-push 9)
  (calc-push 11)
  (calc-refresh)

  ;; Mid-stack: the entry at point moves to level 1, the entries below
  ;; it rise one level each, the ones above it stay put. Point rides
  ;; along to the bottom line, on the same character of the formula.
  ;; Driven by its key, S-<return>, rather than by name: the gesture
  ;; took the key from the edit module's add-entry-below, and pressing
  ;; it is what says so.
  (progn (goto-char (point-min)) (search-forward "3:  7") (backward-char 1))
  (progn (execute-kbd-macro (kbd "S-<return>")) nil)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "7"))
  (cl-assert (string= (math-format-value (calc-top 2 'full)) "11"))
  (cl-assert (string= (math-format-value (calc-top 3 'full)) "9"))
  (cl-assert (string= (math-format-value (calc-top 4 'full)) "5"))
  (cl-assert (looking-at "7"))
  (cl-assert (= (calc-locate-cursor-element (point)) 1))

  ;; A single undo reverts the roll, and point with it.
  (progn (setq last-command nil) (call-interactively 'maf-undo))
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "11"))
  (cl-assert (string= (math-format-value (calc-top 3 'full)) "7"))
  (cl-assert (looking-at "7"))
  (cl-assert (= (calc-locate-cursor-element (point)) 3))

  ;; The deepest entry travels the whole stack.
  (progn (goto-char (point-min)) (search-forward "4:  5") (backward-char 1))
  (call-interactively 'maf-roll-to-top)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "5"))
  (cl-assert (string= (math-format-value (calc-top 2 'full)) "11"))
  (cl-assert (string= (math-format-value (calc-top 3 'full)) "9"))
  (cl-assert (string= (math-format-value (calc-top 4 'full)) "7"))
  (cl-assert (looking-at "5"))

  ;; Already on top: no-op, and point does not move home.
  (progn (goto-char (point-min)) (search-forward "1:  5") (backward-char 1))
  (call-interactively 'maf-roll-to-top)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "5"))
  (cl-assert (looking-at "5"))
  (cl-assert (not (maf--at-home-p)))

  ;; At home the top entry is the target and it is already on top:
  ;; no-op, point stays home.
  (goto-char (point-max))
  (call-interactively 'maf-roll-to-top)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "5"))
  (cl-assert (maf--at-home-p))

  ;; Point inside a formula rides along to the same sub-formula.
  (calc-pop (calc-stack-size))
  (maf-push "sin(2 x + 1)")
  (maf-push "a + b")
  (calc-push 7)
  (calc-refresh)
  (progn (goto-char (point-min)) (search-forward "3:  sin(2 x") (backward-char 1))
  (cl-assert (looking-at "x"))
  (call-interactively 'maf-roll-to-top)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "sin(2 x + 1)"))
  (cl-assert (looking-at "x"))
  (cl-assert (= (calc-locate-cursor-element (point)) 1))

  ;; ... and a selection on the travelling entry survives the roll.
  ;; A selected entry renders dotted and marks its level with a * (1*
  ;; ..... x . ..), so from here point is placed by stack level and the
  ;; values are read off the stack — selecting also encases the entry's
  ;; atoms, hence `maf--strip-encasing'.
  (progn (setq last-command nil) (call-interactively 'calc-select-here))
  (cl-assert (equal (calc-top 1 'sel) '(var x var-x)))
  (progn (calc-cursor-stack-index 3) (move-to-column 4))
  (cl-assert (looking-at "a"))
  (call-interactively 'maf-roll-to-top)
  (cl-assert (string= (math-format-value (maf--strip-encasing (calc-top 1 'full))) "a + b"))
  (cl-assert (string= (math-format-value (maf--strip-encasing (calc-top 2 'full))) "sin(2 x + 1)"))
  (cl-assert (equal (calc-top 2 'sel) '(var x var-x)))
  (cl-assert (looking-at "a"))
  (cl-assert (= (calc-locate-cursor-element (point)) 1))

  ;; From the line-number margin: point keeps its place in the margin.
  (progn (calc-cursor-stack-index 2) (beginning-of-line))
  (call-interactively 'maf-roll-to-top)
  (cl-assert (string= (math-format-value (maf--strip-encasing (calc-top 1 'full))) "sin(2 x + 1)"))
  (cl-assert (equal (calc-top 1 'sel) '(var x var-x)))
  (cl-assert (looking-at "1\\*"))
  (cl-assert (= (current-column) 0))

  ;; At end of line: point stays at end of line on the bottom line.
  (progn (setq last-command nil) (call-interactively 'calc-clear-selections))
  (progn (goto-char (point-min)) (search-forward "3:  7") (end-of-line))
  (call-interactively 'maf-roll-to-top)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "7"))
  (cl-assert (eolp))
  (cl-assert (= (calc-locate-cursor-element (point)) 1))

  ;; A single entry has nothing to move: no-op, no error.
  (calc-pop (calc-stack-size))
  (calc-push 7)
  (calc-refresh)
  (progn (goto-char (point-min)) (search-forward "1:  7") (backward-char 1))
  (call-interactively 'maf-roll-to-top)
  (cl-assert (= (calc-stack-size) 1))
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "7"))
  (cl-assert (looking-at "7"))

  ;; An empty stack is a no-op too, not an error.
  (calc-pop 1)
  (goto-char (point-max))
  (call-interactively 'maf-roll-to-top)
  (cl-assert (= (calc-stack-size) 0)))
