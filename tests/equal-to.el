;; Step test for mafcmd-equal-to / mafcmd-not-equal-to: equate the entry
;; at point with the top-of-stack argument, following the binary-command
;; convention.  Run in a live Emacs (see tests/README.md).
(maf-step
  ;; Both native-profile keys reach the same command.
  (cl-assert (eq (key-binding (kbd "e")) 'mafcmd-equal-to))
  (cl-assert (eq (key-binding (kbd "=")) 'mafcmd-equal-to))

  ;; --- Basic: subject = argument, argument consumed ---

  ;; At home the top two entries join: the lower is the subject (left),
  ;; the top the argument (right).
  (maf-push "x")
  (maf-push "y")
  (goto-char (point-max))
  (execute-kbd-macro (kbd "="))
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

  ;; --- Side order: the stack's, with the one definition reorder ---

  ;; A subject with no variable equated with a bare variable is that
  ;; variable's definition, and the definition leads with its name
  ;; (`maf--equal-to-sides').
  (maf-push "5")
  (maf-push "x")
  (goto-char (point-max))
  (call-interactively 'mafcmd-equal-to)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "x = 5"))
  (calc-pop (calc-stack-size))

  ;; A variable-free expression counts the same as a number, and pi is
  ;; no variable.
  (maf-push "sqrt(2) + pi")
  (maf-push "x")
  (goto-char (point-max))
  (call-interactively 'mafcmd-equal-to)
  (cl-assert (string= (math-format-value (calc-top 1 'full))
                      "x = sqrt(2) + pi"))
  (calc-pop (calc-stack-size))

  ;; A constant is not an unknown: pi on top earns no reorder.
  (maf-push "42")
  (maf-push "pi")
  (goto-char (point-max))
  (call-interactively 'mafcmd-equal-to)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "42 = pi"))
  (calc-pop (calc-stack-size))

  ;; A compound argument is not a bare variable: no reorder.
  (maf-push "5")
  (maf-push "x + 1")
  (goto-char (point-max))
  (call-interactively 'mafcmd-equal-to)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "5 = x + 1"))
  (calc-pop (calc-stack-size))

  ;; The variable as subject keeps the left, like any subject.
  (maf-push "x")
  (maf-push "5")
  (goto-char (point-max))
  (call-interactively 'mafcmd-equal-to)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "x = 5"))
  (calc-pop (calc-stack-size))

  ;; Two bare variables: subject stays left.
  (maf-push "y")
  (maf-push "x")
  (goto-char (point-max))
  (call-interactively 'mafcmd-equal-to)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "y = x"))
  (calc-pop (calc-stack-size))

  ;; Two objects: subject stays left.
  (maf-push "2 a")
  (maf-push "b + 1")
  (goto-char (point-max))
  (call-interactively 'mafcmd-equal-to)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "2 a = b + 1"))
  (calc-pop (calc-stack-size))

  ;; A compound in the variable too: subject keeps the left.
  (maf-push "5")
  (maf-push "2 x")
  (goto-char (point-max))
  (call-interactively 'mafcmd-equal-to)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "5 = 2 x"))
  (calc-pop (calc-stack-size))

  ;; != keeps the pair as it sat, the same way.
  (maf-push "5")
  (maf-push "x")
  (goto-char (point-max))
  (call-interactively 'mafcmd-not-equal-to)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "5 != x"))
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

  ;; Had the subject narrowed to the v under point, this would read
  ;; v = w + 1.
  (maf-push "u + v")
  (maf-push "w + 1")
  (progn (calc-cursor-stack-index 2) (beginning-of-line)
         (search-forward "v") (backward-char 1))   ; inside the lower entry
  (call-interactively 'mafcmd-equal-to)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "u + v = w + 1"))
  (calc-pop (calc-stack-size)))
