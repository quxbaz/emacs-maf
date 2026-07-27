;; Step test for mafcmd-remove-equal: drop the relation from the entry at
;; point, keeping the side that matters.  Run in a live Emacs (see
;; tests/README.md).
(maf-step
  ;; --- Basic: the right-hand side survives ---

  (maf-push "x = 5")
  (goto-char (point-max))
  (call-interactively 'mafcmd-remove-equal)
  (cl-assert (= (calc-stack-size) 1))
  (cl-assert (equal (calc-top 1 'full) 5))
  (calc-pop (calc-stack-size))

  (maf-push "y = 2 x + 1")
  (goto-char (point-max))
  (call-interactively 'mafcmd-remove-equal)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "2 x + 1"))
  (calc-pop (calc-stack-size))

  ;; --- Every relation qualifies, not just equality: all six of
  ;; calc-tweak-eqn-table, with sides calc cannot compare ---

  (dolist (op '("=" "!=" "<" ">" "<=" ">="))
    (maf-push (format "2 a %s 3 b" op))
    (goto-char (point-max))
    (call-interactively 'mafcmd-remove-equal)
    (cl-assert (string= (math-format-value (calc-top 1 'full)) "3 b"))
    (calc-pop (calc-stack-size)))

  ;; Set membership is not one of them — maf--relation-p draws the same
  ;; line, so `in' is no more an equation here than anywhere else in
  ;; maf.  It commits unchanged rather than as an rmeq() wrapper.
  (maf-push "x in [1 .. 5]")
  (goto-char (point-max))
  (call-interactively 'mafcmd-remove-equal)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "x in [1 .. 5]"))
  (calc-pop (calc-stack-size))

  ;; Nor are the logical connectives.
  (maf-push "a && b")
  (goto-char (point-max))
  (call-interactively 'mafcmd-remove-equal)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "a && b"))
  (calc-pop (calc-stack-size))

  ;; An assignment keeps its right side too.
  (maf-push "x := 5")
  (goto-char (point-max))
  (call-interactively 'mafcmd-remove-equal)
  (cl-assert (equal (calc-top 1 'full) 5))
  (calc-pop (calc-stack-size))

  ;; --- Upstream's tie-break: a bare variable on the right loses to an
  ;; object on the left, so a solution reads the same either way round ---

  (maf-push "5 = x")
  (goto-char (point-max))
  (call-interactively 'mafcmd-remove-equal)
  (cl-assert (equal (calc-top 1 'full) 5))
  (calc-pop (calc-stack-size))

  ;; Two non-objects: no tie-break, the right side wins as usual.
  (maf-push "2 y = x")
  (goto-char (point-max))
  (call-interactively 'mafcmd-remove-equal)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "x"))
  (calc-pop (calc-stack-size))

  ;; The tie-break is not equality-only: an inequality keeps the object
  ;; too, losing its direction along with the side.  Upstream's rule,
  ;; applied through calc-tweak-eqn-table for all six alike.
  (maf-push "5 < x")
  (goto-char (point-max))
  (call-interactively 'mafcmd-remove-equal)
  (cl-assert (equal (calc-top 1 'full) 5))
  (calc-pop (calc-stack-size))

  ;; --- Vectors map element-wise, keeping their shape ---

  (maf-push "[x = 1, y = 2]")
  (goto-char (point-max))
  (call-interactively 'mafcmd-remove-equal)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "[1, 2]"))
  (calc-pop (calc-stack-size))

  ;; An element with no relation passes through instead of coming back
  ;; wrapped in rmeq(), which is what bare calcFunc-rmeq would leave.
  (maf-push "[x = 1, 5]")
  (goto-char (point-max))
  (call-interactively 'mafcmd-remove-equal)
  (cl-assert (equal (calc-top 1 'full) '(vec 1 5)))
  (calc-pop (calc-stack-size))

  ;; --- Degenerate: nothing to remove commits unchanged ---

  (maf-push "2 x + 1")
  (goto-char (point-max))
  (call-interactively 'mafcmd-remove-equal)
  (cl-assert (= (calc-stack-size) 1))
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "2 x + 1"))
  (calc-pop (calc-stack-size))

  ;; An empty stack has nothing to act on at all.
  (cl-assert (equal (condition-case e
                        (progn (call-interactively 'mafcmd-remove-equal) 'no-error)
                      (error (error-message-string e)))
                    "Too few elements on stack"))

  ;; --- Whole-entry scope: point inside the formula, and an explicit
  ;; selection, both act on the entry as a whole ---

  ;; Point on x inside the lower entry: the entry's relation goes, the
  ;; top entry is untouched.
  (maf-push "y = 2 x + 1")
  (maf-push "9")
  (progn (calc-cursor-stack-index 2) (beginning-of-line)
         (search-forward "x") (backward-char 1))
  (call-interactively 'mafcmd-remove-equal)
  (cl-assert (= (calc-stack-size) 2))
  (cl-assert (string= (math-format-value (calc-top 2 'full)) "2 x + 1"))
  (cl-assert (equal (calc-top 1 'full) 9))
  ;; Point stays on the subject's line (index 2 renders on buffer line 1).
  (cl-assert (= (line-number-at-pos) 1))
  (calc-pop (calc-stack-size))

  ;; A sub-formula selection is bypassed, not used to narrow the target,
  ;; and the rewritten entry carries no selection.
  (maf-push "x = y + 1")
  (progn (goto-char (point-min)) (search-forward "y") (backward-char 1))
  (call-interactively 'calc-select-here)
  (call-interactively 'mafcmd-remove-equal)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "y + 1"))
  (cl-assert (not calc-any-selections))
  (calc-pop (calc-stack-size))

  ;; --- The surviving side commits structurally: nothing re-simplifies ---

  (let ((calc-simplify-mode 'none))
    (calc-push '(calcFunc-eq (var x var-x) (+ (+ (var y var-y) 1) 1))))
  (goto-char (point-max))
  (call-interactively 'mafcmd-remove-equal)
  (cl-assert (equal (calc-top 1 'full) '(+ (+ (var y var-y) 1) 1)))
  (calc-pop (calc-stack-size))

  ;; --- Keep-args: the relation stays, the side is pushed on top ---

  (maf-push "x = 5")
  (goto-char (point-max))
  (call-interactively 'calc-keep-args)
  (call-interactively 'mafcmd-remove-equal)
  (cl-assert (= (calc-stack-size) 2))
  (cl-assert (equal (calc-top 1 'full) 5))
  (cl-assert (string= (math-format-value (calc-top 2 'full)) "x = 5"))
  (calc-pop (calc-stack-size))

  ;; --- Both keys reach the command through the keymap ---

  (maf-push "p = q + 2")
  (goto-char (point-max))
  (execute-kbd-macro (kbd "M-."))
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "q + 2"))
  (calc-pop (calc-stack-size))

  (maf-push "u = v + 3")
  (goto-char (point-max))
  (execute-kbd-macro (kbd "a ."))
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "v + 3"))
  ;; One undo brings the whole relation back.
  (call-interactively 'maf-undo)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "u = v + 3"))
  (calc-pop (calc-stack-size)))
