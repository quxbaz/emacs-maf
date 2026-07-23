;; Step test for mafcmd-equal-to / mafcmd-not-equal-to: equate the entry
;; at point with the top-of-stack argument, following the binary-command
;; convention.  Run in a live Emacs (see tests/README.md).
(maf-step
  ;; --- Basic: subject = argument, argument consumed ---

  ;; At home the top two entries join: the lower is the subject (left),
  ;; the top the argument (right).
  (maf-push "x")
  (maf-push "y")
  (goto-char (point-max))
  (call-interactively 'mafcmd-equal-to)
  (cl-assert (= (calc-stack-size) 1))
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "x = y"))
  (calc-pop (calc-stack-size))

  ;; The entry at point equates with the TOP, not an adjacent neighbour,
  ;; regardless of the entries between them.  Point on the deepest of
  ;; three: it equates with the top; the middle entry is left in place.
  (maf-push "a")            ; index 3
  (maf-push "b")            ; index 2
  (maf-push "c")            ; index 1 (top / argument)
  (progn (goto-char (point-min)) (search-forward "a") (backward-char 1))
  (call-interactively 'mafcmd-equal-to)
  (cl-assert (= (calc-stack-size) 2))
  (cl-assert (string= (math-format-value (calc-top 2 'full)) "a = c"))
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "b"))
  ;; Point stays on the subject's line (index 2 renders on buffer line 1).
  (cl-assert (= (line-number-at-pos) 1))
  (cl-assert (not (maf--at-home-p)))
  (calc-pop (calc-stack-size))

  ;; Point on the top entry shifts the pair down: the top is the argument
  ;; and the entry below the subject, so a two-entry stack equates the
  ;; same either way.
  (maf-push "p")
  (maf-push "q")
  (progn (goto-char (point-min)) (end-of-line))   ; on the top entry
  (call-interactively 'mafcmd-equal-to)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "p = q"))
  (calc-pop (calc-stack-size))

  ;; --- No simplification: the sides commit structurally ---

  (maf-push "3")
  (maf-push "3")
  (goto-char (point-max))
  (call-interactively 'mafcmd-equal-to)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "3 = 3"))
  (calc-pop (calc-stack-size))

  ;; An unsimplified subject survives intact — nothing re-normalizes it.
  (let ((calc-simplify-mode 'none))
    (calc-push '(+ (+ (var x var-x) 1) 1)))
  (calc-push '(var y var-y))
  (goto-char (point-max))
  (call-interactively 'mafcmd-equal-to)
  (cl-assert (equal (calc-top 1 'full)
                    '(calcFunc-eq (+ (+ (var x var-x) 1) 1) (var y var-y))))
  (calc-pop (calc-stack-size))

  ;; --- Inverse flag builds != via mafcmd-not-equal-to ---

  (maf-push "x")
  (maf-push "y")
  (goto-char (point-max))
  (let ((calc-inverse-flag t)) (call-interactively 'mafcmd-equal-to))
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "x != y"))
  (calc-pop (calc-stack-size))

  ;; mafcmd-not-equal-to directly does the same.
  (maf-push "x")
  (maf-push "y")
  (goto-char (point-max))
  (call-interactively 'mafcmd-not-equal-to)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "x != y"))
  (calc-pop (calc-stack-size))

  ;; --- Keep-args: operands stay, equation pushed on top ---

  (maf-push "x")
  (maf-push "y")
  (call-interactively 'calc-keep-args)
  (call-interactively 'mafcmd-equal-to)
  (cl-assert (= (calc-stack-size) 3))
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "x = y"))
  (cl-assert (string= (math-format-value (calc-top 2 'full)) "y"))
  (cl-assert (string= (math-format-value (calc-top 3 'full)) "x"))
  (calc-pop (calc-stack-size))

  ;; --- Whole-entry scope: point inside a formula still equates the
  ;; whole entry, not the sub-formula under point ---

  (maf-push "u + v")
  (maf-push "w")
  (progn (calc-cursor-stack-index 2) (beginning-of-line)
         (search-forward "v") (backward-char 1))   ; inside the lower entry
  (call-interactively 'mafcmd-equal-to)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "u + v = w"))
  (calc-pop (calc-stack-size)))
