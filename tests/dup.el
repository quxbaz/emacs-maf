;; `maf-dup' is a real command (src/stack.el), so these steps drive it
;; directly across every resolver target. A step passes when it raises
;; no error. The contract: a copy is pushed on top, originals untouched,
;; verbatim, point parks home; keep-args makes no difference.

(maf-step
  ;; home: point at home duplicates the top entry, stack grows by one,
  ;; and the copy is structurally identical to the source.
  (maf-push "a + b c")
  (goto-char (point-max))
  (call-interactively 'maf-dup)
  (cl-assert (= (calc-stack-size) 2))
  (cl-assert (equal (calc-top 1 'full) (calc-top 2 'full)))
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "a + b c"))
  (cl-assert (maf--at-home-p))          ; point parks home
  (calc-pop (calc-stack-size))

  ;; subexpr: the sub-formula under point (here a + b, point on the +) is
  ;; pushed on its own, lifted out of the entry; the source is untouched.
  (maf-push "(a + b) c")
  (progn (goto-char (point-min)) (search-forward "+") (backward-char 1))
  (call-interactively 'maf-dup)
  (cl-assert (= (calc-stack-size) 2))
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "a + b"))
  (cl-assert (string= (math-format-value (calc-top 2 'full)) "(a + b) c"))
  (calc-pop (calc-stack-size))

  ;; entry from the margin: the whole entry is duplicated.
  (maf-push "6 x + 12")
  (progn (calc-cursor-stack-index 1) (end-of-line))
  (call-interactively 'maf-dup)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "6 x + 12"))
  (cl-assert (string= (math-format-value (calc-top 2 'full)) "6 x + 12"))
  (calc-pop (calc-stack-size))

  ;; relation from the margin: duplicated whole, not per side.
  (maf-push "x = y + z")
  (progn (calc-cursor-stack-index 1) (end-of-line))
  (call-interactively 'maf-dup)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "x = y + z"))
  (calc-pop (calc-stack-size))

  ;; relation from within: the side under point is pushed, not the relation.
  (maf-push "x = y + z")
  (progn (goto-char (point-min)) (search-forward "y"))
  (call-interactively 'maf-dup)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "y + z"))
  (calc-pop (calc-stack-size))

  ;; selection: the calc selection is what's duplicated, wherever point sits.
  (maf-push "a + b c")
  (progn (goto-char (point-min)) (search-forward "c") (backward-char 1))
  (call-interactively 'calc-select-here)
  (goto-char (point-max))
  (call-interactively 'maf-dup)
  (cl-assert (= (calc-stack-size) 2))
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "c"))
  (calc-clear-selections)
  (calc-pop (calc-stack-size))

  ;; region: a run calc cannot select (the middle of a sum) is pushed as
  ;; its fold; the source is untouched and the gesture is consumed.
  (maf-push "a + b + c + d")
  (progn (calc-cursor-stack-index 1)
         (search-forward "b + c" (line-end-position))
         (goto-char (match-beginning 0))
         (push-mark (match-end 0) t t)
         (call-interactively 'maf-dup))
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "b + c"))
  (cl-assert (string= (math-format-value (calc-top 2 'full)) "a + b + c + d"))
  (cl-assert (not (region-active-p)))
  (calc-pop (calc-stack-size))

  ;; undo: maf-undo reverts the pushed copy and returns point to where
  ;; the command was invoked (the +), not home where the push left it.
  ;; last-command is set as the command loop would (the harness can't),
  ;; so this is the first undo of a chain, taking the cmd-point path.
  (maf-push "(a + b) c")
  (progn (goto-char (point-min)) (search-forward "+") (backward-char 1))
  (call-interactively 'maf-dup)
  (progn (setq last-command nil) (call-interactively 'maf-undo))
  (cl-assert (= (calc-stack-size) 1))
  (cl-assert (eq (char-after) ?+))
  (calc-pop (calc-stack-size))

  ;; verbatim: nothing simplifies. With point on the + of an unsimplified
  ;; sub-formula the pushed copy keeps its literal form (1 + 2, not 3).
  (let ((calc-simplify-mode 'none))
    (maf-push "(1 + 2) x"))
  (progn (goto-char (point-min)) (search-forward "+") (backward-char 1))
  (call-interactively 'maf-dup)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "1 + 2"))
  (calc-pop (calc-stack-size))

  ;; keep-args makes no difference: still exactly one copy pushed.
  (maf-push "a + b c")
  (let ((calc-keep-args-flag t))
    (goto-char (point-max))
    (call-interactively 'maf-dup))
  (cl-assert (= (calc-stack-size) 2))
  (calc-pop (calc-stack-size))

  ;; empty stack: signals a user-error and the stack stays empty.
  (cl-assert (equal (condition-case e
                        (progn (goto-char (point-max))
                               (call-interactively 'maf-dup))
                      (error (cadr e)))
                    "Stack is empty"))
  (cl-assert (= (calc-stack-size) 0)))
