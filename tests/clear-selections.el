;; `maf-clear-selections' and the RET dispatcher
;; `maf-dup-or-clear-selections' are real commands (src/stack.el), so
;; these steps drive them directly. The contract: clearing takes every
;; selection, leaves the stack alone, and keeps point where it was; RET
;; clears when any selection is active and duplicates otherwise, and
;; C-RET (`maf-dup-here-or-clear-selections') does the same holding
;; point.

(maf-step
  ;; A selection under point is cleared, point staying on the line and
  ;; column it was on rather than parking home.
  (maf-push "6 x + 12")
  (progn (goto-char (point-min)) (search-forward "x") (backward-char 1))
  (call-interactively 'calc-select-here)
  (cl-assert (maf--sel-any-p))
  (let ((line (line-number-at-pos)) (col (current-column)))
    (call-interactively 'maf-clear-selections)
    (cl-assert (not (maf--sel-any-p)))
    (cl-assert (= (line-number-at-pos) line))
    (cl-assert (= (current-column) col)))
  (cl-assert (not (maf--at-home-p)))
  (cl-assert (= (calc-stack-size) 1))
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "6 x + 12"))
  (calc-pop (calc-stack-size))

  ;; Every entry's selection goes, not just the one under point: two
  ;; selections, cleared from the entry that carries neither.
  (maf-push "a + b")
  (maf-push "c + d")
  (maf-push "e")
  (progn (calc-cursor-stack-index 3) (search-forward "b"))
  (call-interactively 'calc-select-here)
  (progn (calc-cursor-stack-index 2) (search-forward "d"))
  (call-interactively 'calc-select-here)
  (cl-assert (calc-top 3 'sel))
  (cl-assert (calc-top 2 'sel))
  (progn (calc-cursor-stack-index 1) (end-of-line))
  (call-interactively 'maf-clear-selections)
  (cl-assert (not (maf--sel-any-p)))
  (cl-assert (null (calc-top 3 'sel)))
  (cl-assert (null (calc-top 2 'sel)))
  (calc-pop (calc-stack-size))

  ;; Nothing selected: a no-op that still leaves the stack and point
  ;; untouched.
  (maf-push "a + b")
  (progn (goto-char (point-min)) (search-forward "+") (backward-char 1))
  (call-interactively 'maf-clear-selections)
  (cl-assert (= (calc-stack-size) 1))
  (cl-assert (eq (char-after) ?+))
  (calc-pop (calc-stack-size))

  ;; --- RET's dispatcher ---

  ;; With a selection active RET clears it; the stack does not grow, so
  ;; the sub-formula is not duplicated on the way out.
  (maf-push "a + b c")
  (progn (goto-char (point-min)) (search-forward "c") (backward-char 1))
  (call-interactively 'calc-select-here)
  (call-interactively 'maf-dup-or-clear-selections)
  (cl-assert (not (maf--sel-any-p)))
  (cl-assert (= (calc-stack-size) 1))
  (cl-assert (eq (char-after) ?c))
  (calc-pop (calc-stack-size))

  ;; A selection anywhere counts, even with point on another entry: the
  ;; clear wins over the duplicate that point would otherwise get.
  (maf-push "a + b")
  (maf-push "c + d")
  (progn (calc-cursor-stack-index 2) (search-forward "b"))
  (call-interactively 'calc-select-here)
  (progn (calc-cursor-stack-index 1) (end-of-line))
  (call-interactively 'maf-dup-or-clear-selections)
  (cl-assert (not (maf--sel-any-p)))
  (cl-assert (= (calc-stack-size) 2))
  (calc-pop (calc-stack-size))

  ;; With none active RET is the duplicate again, contextual as ever:
  ;; the sub-formula under point is pushed on its own.
  (maf-push "(a + b) c")
  (progn (goto-char (point-min)) (search-forward "+") (backward-char 1))
  (call-interactively 'maf-dup-or-clear-selections)
  (cl-assert (= (calc-stack-size) 2))
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "a + b"))
  (cl-assert (string= (math-format-value (calc-top 2 'full)) "(a + b) c"))
  (cl-assert (maf--at-home-p))
  (calc-pop (calc-stack-size))

  ;; Clearing changes no formula, so it records nothing to undo: the
  ;; head of the undo list is the same cons before and after, leaving
  ;; the next undo for the stack change that preceded it.
  (maf-push "x + 3")
  (progn (calc-cursor-stack-index 1) (search-forward "x"))
  (call-interactively 'calc-select-here)
  (let ((head calc-undo-list))
    (call-interactively 'maf-dup-or-clear-selections)
    (cl-assert (eq calc-undo-list head)))
  (cl-assert (not (maf--sel-any-p)))
  (calc-pop (calc-stack-size))

  ;; --- C-RET: the same dispatcher, holding point ---

  ;; With none active it duplicates as RET does, but point stays on what
  ;; it copied rather than parking home — the whole of the difference
  ;; between the two keys.
  (maf-push "(a + b) c")
  (progn (goto-char (point-min)) (search-forward "+") (backward-char 1))
  (call-interactively 'maf-dup-here-or-clear-selections)
  (cl-assert (= (calc-stack-size) 2))
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "a + b"))
  (cl-assert (eq (char-after) ?+))
  (cl-assert (not (maf--at-home-p)))
  (calc-pop (calc-stack-size))

  ;; With a selection active it clears, exactly as RET does: the hold has
  ;; no point-motion to vary, and the stack does not grow.
  (maf-push "a + b c")
  (progn (goto-char (point-min)) (search-forward "c") (backward-char 1))
  (call-interactively 'calc-select-here)
  (call-interactively 'maf-dup-here-or-clear-selections)
  (cl-assert (not (maf--sel-any-p)))
  (cl-assert (= (calc-stack-size) 1))
  (cl-assert (eq (char-after) ?c))
  (calc-pop (calc-stack-size))

  ;; The keys themselves: RET runs the dispatcher in the calc buffer,
  ;; C-<return> its keep-point half.
  (cl-assert (eq (key-binding (kbd "RET")) 'maf-dup-or-clear-selections))
  (cl-assert (eq (key-binding (kbd "C-<return>"))
                 'maf-dup-here-or-clear-selections)))
