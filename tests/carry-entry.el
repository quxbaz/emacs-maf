(maf-step
  ;; Four entries: 4: 5 / 3: 7 / 2: 9 / 1: 11.
  (calc-push 5)
  (calc-push 7)
  (calc-push 9)
  (calc-push 11)
  (calc-refresh)

  ;; Carry up: the entry at point and the one above it exchange levels,
  ;; and point rides the entry it started on — a line up the screen,
  ;; still on the same character of the same formula.
  (progn (goto-char (point-min)) (search-forward "1:  11") (backward-char 2))
  (call-interactively 'maf-carry-up)
  (cl-assert (string= (math-format-value (calc-top 2 'full)) "11"))
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "9"))
  (cl-assert (string= (math-format-value (calc-top 3 'full)) "7"))
  (cl-assert (string= (math-format-value (calc-top 4 'full)) "5"))
  (cl-assert (= (calc-locate-cursor-element (point)) 2))
  (cl-assert (looking-at "11"))

  ;; A second press walks the same entry one level further: point is
  ;; still on it, so the gesture repeats on the entry rather than on
  ;; whatever landed on the line.
  (call-interactively 'maf-carry-up)
  (cl-assert (string= (math-format-value (calc-top 3 'full)) "11"))
  (cl-assert (string= (math-format-value (calc-top 2 'full)) "7"))
  (cl-assert (= (calc-locate-cursor-element (point)) 3))
  (cl-assert (looking-at "11"))

  ;; A single undo reverts one carry, and point with it.
  (progn (setq last-command nil) (call-interactively 'maf-undo))
  (cl-assert (string= (math-format-value (calc-top 2 'full)) "11"))
  (cl-assert (string= (math-format-value (calc-top 3 'full)) "7"))
  (cl-assert (= (calc-locate-cursor-element (point)) 2))
  (cl-assert (looking-at "11"))

  ;; Carry down is the mirror: back to level 1, point riding along.
  (call-interactively 'maf-carry-down)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "11"))
  (cl-assert (string= (math-format-value (calc-top 2 'full)) "9"))
  (cl-assert (= (calc-locate-cursor-element (point)) 1))
  (cl-assert (looking-at "11"))

  ;; Already on top: the stack is a ring, so carrying down wraps to the
  ;; deepest level, the entries below each dropping one to make room.
  (call-interactively 'maf-carry-down)
  (cl-assert (string= (math-format-value (calc-top 4 'full)) "11"))
  (cl-assert (string= (math-format-value (calc-top 3 'full)) "5"))
  (cl-assert (string= (math-format-value (calc-top 2 'full)) "7"))
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "9"))
  (cl-assert (= (calc-locate-cursor-element (point)) 4))
  (cl-assert (looking-at "11"))

  ;; And from the deepest, carrying up wraps back round to level 1 —
  ;; undoing the wrap above.
  (call-interactively 'maf-carry-up)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "11"))
  (cl-assert (string= (math-format-value (calc-top 2 'full)) "9"))
  (cl-assert (string= (math-format-value (calc-top 3 'full)) "7"))
  (cl-assert (string= (math-format-value (calc-top 4 'full)) "5"))
  (cl-assert (= (calc-locate-cursor-element (point)) 1))
  (cl-assert (looking-at "11"))

  ;; A prefix argument counts lines: three at once, the entries passed
  ;; each dropping one level and keeping their order.
  (let ((current-prefix-arg 3)) (call-interactively 'maf-carry-up))
  (cl-assert (string= (math-format-value (calc-top 4 'full)) "11"))
  (cl-assert (string= (math-format-value (calc-top 3 'full)) "5"))
  (cl-assert (string= (math-format-value (calc-top 2 'full)) "7"))
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "9"))
  (cl-assert (= (calc-locate-cursor-element (point)) 4))
  (cl-assert (looking-at "11"))

  ;; The count wraps rather than clamping: nine lines up a four-entry
  ;; stack laps it twice over and lands one further, at level 1.
  (let ((current-prefix-arg 9)) (call-interactively 'maf-carry-up))
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "11"))
  (cl-assert (string= (math-format-value (calc-top 2 'full)) "9"))
  (cl-assert (string= (math-format-value (calc-top 3 'full)) "7"))
  (cl-assert (string= (math-format-value (calc-top 4 'full)) "5"))
  (cl-assert (= (calc-locate-cursor-element (point)) 1))
  (cl-assert (looking-at "11"))

  ;; A count that laps the stack exactly brings the entry home again:
  ;; nothing happens at all, not even a redraw that moves point.
  (let ((current-prefix-arg 4)) (call-interactively 'maf-carry-up))
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "11"))
  (cl-assert (= (calc-locate-cursor-element (point)) 1))
  (cl-assert (looking-at "11"))

  ;; A negative count reverses the direction — and wraps the same way.
  (let ((current-prefix-arg -2)) (call-interactively 'maf-carry-up))
  (cl-assert (string= (math-format-value (calc-top 3 'full)) "11"))
  (cl-assert (string= (math-format-value (calc-top 4 'full)) "5"))
  (cl-assert (string= (math-format-value (calc-top 2 'full)) "7"))
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "9"))
  (cl-assert (= (calc-locate-cursor-element (point)) 3))
  (let ((current-prefix-arg -1)) (call-interactively 'maf-carry-down))
  (cl-assert (string= (math-format-value (calc-top 4 'full)) "11"))
  (cl-assert (= (calc-locate-cursor-element (point)) 4))

  ;; A whole prefixed carry is one undo group.
  (progn (setq last-command nil) (call-interactively 'maf-undo))
  (cl-assert (string= (math-format-value (calc-top 3 'full)) "11"))
  (progn (setq last-command nil) (call-interactively 'maf-undo))
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "11"))
  (cl-assert (string= (math-format-value (calc-top 2 'full)) "9"))

  ;; Point inside a formula carries the whole entry — the sub-formula
  ;; travels with it rather than being traded away, which is what
  ;; `maf-swap-up' does with it — and point stays on that sub-formula.
  ;; The entries are of different heights on the line; point is an
  ;; offset into the entry's own text, so it rides regardless.
  (calc-pop (calc-stack-size))
  (maf-push "sin(2 x + 1)")
  (calc-push 7)
  (calc-refresh)
  (progn (goto-char (point-min)) (search-forward "2:  sin(2 x") (backward-char 1))
  (cl-assert (looking-at "x"))
  (call-interactively 'maf-carry-down)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "sin(2 x + 1)"))
  (cl-assert (string= (math-format-value (calc-top 2 'full)) "7"))
  (cl-assert (= (calc-locate-cursor-element (point)) 1))
  (cl-assert (looking-at "x"))

  ;; A selection travels with its entry, and point with the selection.
  ;; A selected entry renders dotted and marks its level with a *
  ;; (1* ..... x . ..); selecting also encases the entry's atoms, hence
  ;; `maf--strip-encasing'.
  (progn (setq last-command nil) (call-interactively 'calc-select-here))
  (cl-assert (equal (calc-top 1 'sel) '(var x var-x)))
  (call-interactively 'maf-carry-up)
  (cl-assert (string= (math-format-value (maf--strip-encasing (calc-top 2 'full)))
                      "sin(2 x + 1)"))
  (cl-assert (equal (calc-top 2 'sel) '(var x var-x)))
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "7"))
  (cl-assert (= (calc-locate-cursor-element (point)) 2))
  (cl-assert (looking-at "x"))
  (progn (setq last-command nil) (call-interactively 'calc-clear-selections))

  ;; From the line-number margin: point keeps its place in the margin,
  ;; on the line the entry reached.
  (progn (calc-cursor-stack-index 1) (beginning-of-line))
  (call-interactively 'maf-carry-up)
  (cl-assert (string= (math-format-value (calc-top 2 'full)) "7"))
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "sin(2 x + 1)"))
  (cl-assert (= (calc-locate-cursor-element (point)) 2))
  (cl-assert (= (current-column) 0))

  ;; At end of line: point stays at end of line, on the entry it rode.
  (progn (calc-cursor-stack-index 1) (end-of-line))
  (call-interactively 'maf-carry-up)
  (cl-assert (string= (math-format-value (calc-top 2 'full)) "sin(2 x + 1)"))
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "7"))
  (cl-assert (= (calc-locate-cursor-element (point)) 2))
  (cl-assert (eolp))

  ;; At home there is no entry at point to carry: both directions are
  ;; no-ops and point stays home. (`maf-swap-up' is the command that
  ;; moves the top entry from home.)
  (goto-char (point-max))
  (call-interactively 'maf-carry-up)
  (call-interactively 'maf-carry-down)
  (cl-assert (string= (math-format-value (calc-top 2 'full)) "sin(2 x + 1)"))
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "7"))
  (cl-assert (maf--at-home-p))

  ;; A single entry is a ring of one: it wraps onto itself, so both
  ;; directions are no-ops rather than errors.
  (calc-pop (calc-stack-size))
  (calc-push 7)
  (calc-refresh)
  (progn (goto-char (point-min)) (search-forward "1:  7") (backward-char 1))
  (call-interactively 'maf-carry-up)
  (call-interactively 'maf-carry-down)
  (cl-assert (= (calc-stack-size) 1))
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "7"))
  (cl-assert (looking-at "7"))

  ;; An empty stack is a no-op too, not an error.
  (calc-pop 1)
  (goto-char (point-max))
  (call-interactively 'maf-carry-up)
  (call-interactively 'maf-carry-down)
  (cl-assert (= (calc-stack-size) 0)))
