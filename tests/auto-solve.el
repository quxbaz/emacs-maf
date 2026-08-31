(maf-step
  ;; One variable: solve for it.
  (maf-push "x + 3 = 7")
  (goto-char (point-max))
  (call-interactively 'mafcmd-auto-solve)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "x = 4"))
  (calc-pop (calc-stack-size))

  ;; The whole entry is the subject wherever point rests within it: on
  ;; the 12 the command still solves for x, where `mafcmd-isolate' would
  ;; lift the 12 to the left (see tests/isolate.el).
  (maf-push "y = 30 x + 12")
  (progn (calc-cursor-stack-index 1) (beginning-of-line)
         (search-forward ":  ") (search-forward "12") (backward-char 2))
  (call-interactively 'mafcmd-auto-solve)
  (cl-assert (string= (math-format-value (calc-top 1 'full))
                      "x = y / 30 - 2:5"))
  (calc-clear-selections) (calc-pop (calc-stack-size))

  ;; An explicit calc selection does not narrow it either — the entry is
  ;; the subject however deliberately a part was marked out, and the
  ;; selection is gone once the replacement lands.
  (maf-push "y = 30 x + 12")
  (progn (calc-cursor-stack-index 1) (beginning-of-line)
         (search-forward ":  ") (search-forward "12") (backward-char 2)
         (call-interactively 'calc-select-here))
  (cl-assert (nth 2 (calc-top 1 'entry)))
  (call-interactively 'mafcmd-auto-solve)
  (cl-assert (string= (math-format-value (calc-top 1 'full))
                      "x = y / 30 - 2:5"))
  (cl-assert (null (nth 2 (calc-top 1 'entry))))
  (cl-assert (null calc-any-selections))
  (calc-pop (calc-stack-size))

  ;; Symbolic constants carry through.
  (maf-push "x + a = b")
  (goto-char (point-max))
  (call-interactively 'mafcmd-auto-solve)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "x = b - a"))
  (calc-pop (calc-stack-size))

  ;; A quadratic still solves for the variable (one branch).
  (maf-push "x^2 = 4")
  (goto-char (point-max))
  (call-interactively 'mafcmd-auto-solve)
  (cl-assert (eq (car-safe (calc-top 1 'full)) 'calcFunc-eq))
  (calc-pop (calc-stack-size))

  ;; Non-integer solutions stay exact — a fraction, not a float.
  (maf-push "2 x = 1")
  (goto-char (point-max))
  (call-interactively 'mafcmd-auto-solve)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "x = 1:2"))
  (calc-pop (calc-stack-size))

  ;; A root stays symbolic, not floated.
  (maf-push "x^2 = 2")
  (goto-char (point-max))
  (call-interactively 'mafcmd-auto-solve)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "x = sqrt(2)"))
  (calc-pop (calc-stack-size))

  ;; Two variables: the priority one (x) is solved for first, and a
  ;; repeat cycles to the next.
  (maf-push "x + y = 5")
  (goto-char (point-max))
  (call-interactively 'mafcmd-auto-solve)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "x = -y + 5"))
  (call-interactively 'mafcmd-auto-solve)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "y = -x + 5"))
  (calc-pop (calc-stack-size))

  ;; Non-priority variables sort alphabetically (a before b).
  (maf-push "b + a = 5")
  (goto-char (point-max))
  (call-interactively 'mafcmd-auto-solve)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "a = -b + 5"))
  (calc-pop (calc-stack-size))

  ;; Three variables cycle x -> y -> z -> x.
  (maf-push "x + y + z = 0")
  (goto-char (point-max))
  (cl-flet ((solved-var () (nth 1 (nth 1 (calc-top 1 'full)))))
    (call-interactively 'mafcmd-auto-solve) (cl-assert (eq (solved-var) 'x))
    (call-interactively 'mafcmd-auto-solve) (cl-assert (eq (solved-var) 'y))
    (call-interactively 'mafcmd-auto-solve) (cl-assert (eq (solved-var) 'z))
    (call-interactively 'mafcmd-auto-solve) (cl-assert (eq (solved-var) 'x)))
  (calc-pop (calc-stack-size))

  ;; Inequalities are solved too, keeping the relation.
  (maf-push "2 x - 3 < 7")
  (goto-char (point-max))
  (call-interactively 'mafcmd-auto-solve)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "x < 5"))
  (calc-pop (calc-stack-size))

  ;; != relations likewise.
  (maf-push "x + 3 != 7")
  (goto-char (point-max))
  (call-interactively 'mafcmd-auto-solve)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "x != 4"))
  (calc-pop (calc-stack-size))

  ;; No variable: the entry is left unchanged.
  (maf-push "3 = 3")
  (goto-char (point-max))
  (call-interactively 'mafcmd-auto-solve)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "3 = 3"))
  (calc-pop (calc-stack-size))

  ;; --- More complex expressions ---

  ;; Symbolic coefficients: the solution is a compound quotient.
  (maf-push "a x + b = c")
  (goto-char (point-max))
  (call-interactively 'mafcmd-auto-solve)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "x = (c - b) / a"))
  (calc-pop (calc-stack-size))

  ;; Fractional coefficients combine to an exact integer.
  (maf-push "x/2 + x/3 = 5")
  (goto-char (point-max))
  (call-interactively 'mafcmd-auto-solve)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "x = 6"))
  (calc-pop (calc-stack-size))

  ;; The variable appears on both sides and inside parens; calc expands
  ;; and collects to a single value.
  (maf-push "3 (x - 1) = 2 x + 4")
  (goto-char (point-max))
  (call-interactively 'mafcmd-auto-solve)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "x = 7"))
  (calc-pop (calc-stack-size))

  ;; --- Inequality flavors and sense ---

  ;; <= and >= are solved keeping their sense.
  (maf-push "2 x - 3 <= 7")
  (goto-char (point-max))
  (call-interactively 'mafcmd-auto-solve)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "x <= 5"))
  (calc-pop (calc-stack-size))

  (maf-push "x + 1 >= 4")
  (goto-char (point-max))
  (call-interactively 'mafcmd-auto-solve)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "x >= 3"))
  (calc-pop (calc-stack-size))

  ;; With the variable on the greater side, calc isolates it on the right
  ;; and keeps the relation reading correctly (3 > x, not x < 3).
  (maf-push "5 - x > 2")
  (goto-char (point-max))
  (call-interactively 'mafcmd-auto-solve)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "3 > x"))
  (calc-pop (calc-stack-size))

  ;; A negative coefficient flips the sense; here the flip lands the
  ;; variable on the right as -3 < x (i.e. x > -3).
  (maf-push "-2 x < 6")
  (goto-char (point-max))
  (call-interactively 'mafcmd-auto-solve)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "-3 < x"))
  (calc-pop (calc-stack-size))

  ;; --- Point on the relation operator ---

  ;; Point on the = itself, like anywhere else on the line, solves the
  ;; whole relation for a variable.
  (maf-push "x + 3 = 7")
  (progn (calc-cursor-stack-index 1) (beginning-of-line)
         (search-forward "=") (backward-char 1))
  (call-interactively 'mafcmd-auto-solve)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "x = 4"))
  (calc-clear-selections) (calc-pop (calc-stack-size))

  ;; --- Where point lands ---

  ;; Point lands on the variable the solve isolated, wherever within the
  ;; entry the command was invoked from.
  (maf-push "y = 30 x + 12")
  (progn (calc-cursor-stack-index 1) (beginning-of-line)
         (search-forward ":  ") (search-forward "12") (backward-char 2))
  (call-interactively 'mafcmd-auto-solve)
  (cl-assert (string= (math-format-value (calc-top 1 'full))
                      "x = y / 30 - 2:5"))
  (cl-assert (eq (char-after) ?x))
  (calc-clear-selections) (calc-pop (calc-stack-size))

  ;; Which side the variable ends up on is calc's call — solving 5 - x > 2
  ;; gives 3 > x — so the landing finds the side rather than assuming the
  ;; left one.
  (maf-push "5 - x > 2")
  (progn (calc-cursor-stack-index 1) (goto-char (line-end-position)))
  (call-interactively 'mafcmd-auto-solve)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "3 > x"))
  (cl-assert (eq (char-after) ?x))
  (calc-pop (calc-stack-size))

  ;; An entry the solve leaves alone leaves point alone with it: nothing
  ;; was isolated, so there is nothing to land on.
  (maf-push "x^6 + x + 1 = 0")
  (progn (calc-cursor-stack-index 1) (beginning-of-line)
         (search-forward ":  ") (search-forward "^") (backward-char 1))
  (call-interactively 'mafcmd-auto-solve)
  (cl-assert (string= (math-format-value (calc-top 1 'full))
                      "x^6 + x + 1 = 0"))
  (cl-assert (eq (char-after) ?^))
  (calc-clear-selections) (calc-pop (calc-stack-size))

  ;; Invoked from home, point stays home — calc's own placement, as for
  ;; every other command.
  (maf-push "x + 3 = 7")
  (goto-char (point-max))
  (call-interactively 'mafcmd-auto-solve)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "x = 4"))
  (cl-assert (maf--at-home-p))
  (calc-pop (calc-stack-size))

  ;; Undo returns point to where the command ran, not to where it landed.
  (maf-push "y = 30 x + 12")
  (progn (calc-cursor-stack-index 1) (beginning-of-line)
         (search-forward ":  ") (search-forward "12") (backward-char 2))
  (call-interactively 'mafcmd-auto-solve)
  (cl-assert (eq (char-after) ?x))
  (progn (setq last-command nil) (call-interactively 'maf-undo))
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "y = 30 x + 12"))
  (cl-assert (eq (char-after) ?1))
  (calc-clear-selections) (calc-pop (calc-stack-size))

  ;; --- Various stack positions ---

  ;; Point on a lower entry solves that entry, leaving the top untouched.
  (maf-push "3 x + 1 = 7")   ; lands at index 2 after the next push
  (maf-push "y - 2 = 8")     ; the top decoy (index 1)
  (progn (calc-cursor-stack-index 2) (beginning-of-line)
         (goto-char (line-end-position)))
  (call-interactively 'mafcmd-auto-solve)
  (cl-assert (string= (math-format-value (calc-top 2 'full)) "x = 2"))
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "y - 2 = 8"))
  (calc-pop (calc-stack-size))

  ;; --- Robust across calc modes ---

  ;; The command forces symbolic + prefer-frac internally, so the result
  ;; stays exact even when both global modes are off.
  (let ((calc-symbolic-mode nil) (calc-prefer-frac nil))
    (maf-push "x^2 = 2")
    (goto-char (point-max))
    (call-interactively 'mafcmd-auto-solve)
    (cl-assert (string= (math-format-value (calc-top 1 'full)) "x = sqrt(2)"))
    (calc-pop (calc-stack-size))

    (maf-push "2 x = 1")
    (goto-char (point-max))
    (call-interactively 'mafcmd-auto-solve)
    (cl-assert (string= (math-format-value (calc-top 1 'full)) "x = 1:2"))
    (calc-pop (calc-stack-size)))

  ;; --- Hardening and interaction boundaries ---

  ;; Exercise the actual maf-mode binding from home. A bare expression is
  ;; treated as = 0 and solved without requiring an explicit relation.
  (maf-push "x + 3")
  (let* ((buf (get-buffer "*Calculator*"))
         (win (get-buffer-window buf t)))
    (cl-assert win)
    (with-selected-window win
      (with-current-buffer buf
        (execute-kbd-macro (kbd "M-i")))))
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "x = -3"))
  (calc-pop (calc-stack-size))

  ;; The binding means the same thing from inside the formula: M-i on the
  ;; 12 solves for x rather than isolating what point sits on.
  (maf-push "y = 30 x + 12")
  (let* ((buf (get-buffer "*Calculator*"))
         (win (get-buffer-window buf t)))
    (cl-assert win)
    (with-selected-window win
      (with-current-buffer buf
        (calc-cursor-stack-index 1) (beginning-of-line)
        (search-forward ":  ") (search-forward "12") (backward-char 2)
        (execute-kbd-macro (kbd "M-i")))))
  (cl-assert (string= (math-format-value (calc-top 1 'full))
                      "x = y / 30 - 2:5"))
  (calc-clear-selections) (calc-pop (calc-stack-size))

  ;; A constant variable standing alone is not a solve-cycle candidate.
  ;; Solve the first actual unknown rather than indexing past a missing pi.
  (maf-push "pi = x + y")
  (goto-char (point-max)) (call-interactively 'mafcmd-auto-solve)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "x = -y + pi"))
  (calc-pop (calc-stack-size))

  ;; An unknown-sign inequality no longer degrades (calc alone turns
  ;; strict < into != and fails <= outright): linear in the variable, it
  ;; splits on the sign of the leading coefficient as calc's if. Note
  ;; a < b c cycles to b — a already stands alone on one side.
  (maf-push "a < b c")
  (goto-char (point-max)) (call-interactively 'mafcmd-auto-solve)
  (cl-assert (string= (math-format-value (calc-top 1 'full))
                      "c > 0 ? b > a / c : c < 0 ? b < a / c : a < 0"))
  (calc-pop (calc-stack-size))

  (maf-push "a <= b c")
  (goto-char (point-max)) (call-interactively 'mafcmd-auto-solve)
  (cl-assert (string= (math-format-value (calc-top 1 'full))
                      "c > 0 ? b >= a / c : c < 0 ? b <= a / c : a <= 0"))
  (calc-pop (calc-stack-size))

  ;; The reported bug: 2 x k - 2 < 0 came back x != 1/k, the direction
  ;; thrown away.
  (maf-push "2 x k - 2 < 0")
  (goto-char (point-max)) (call-interactively 'mafcmd-auto-solve)
  (cl-assert (string= (math-format-value (calc-top 1 'full))
                      "2 k > 0 ? x < 1 / k : 2 k < 0 ? x > 1 / k : -2 < 0"))
  (calc-pop (calc-stack-size))

  ;; Past linear the direction cannot be kept at all: the entry stays
  ;; unchanged (calc alone would commit x != 2).
  (maf-push "x^2 < 4")
  (goto-char (point-max)) (call-interactively 'mafcmd-auto-solve)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "x^2 < 4"))
  (calc-pop (calc-stack-size))

  ;; Substituting the coefficient collapses the split to the case that
  ;; holds — positive, negative, and zero, strict and non-strict; the
  ;; zero case lands plain truth, never a division by zero.
  (progn (setq maf-solve-test--lt
               (maf--solve-relation (math-read-expr "2 x k - 2 < 0")
                                    (math-read-expr "x"))
               maf-solve-test--geq
               (maf--solve-relation (math-read-expr "2 x k - 2 >= 0")
                                    (math-read-expr "x")))
         nil)
  (cl-flet ((at (split k)
              (math-format-value
               (math-evaluate-expr
                (math-expr-subst split (math-read-expr "k") k))
               100)))
    (cl-assert (string= (at maf-solve-test--lt 2) "x < 0.5"))
    (cl-assert (string= (at maf-solve-test--lt -2) "x > -0.5"))
    (cl-assert (string= (at maf-solve-test--lt 0) "1"))
    (cl-assert (string= (at maf-solve-test--geq 2) "x >= 0.5"))
    (cl-assert (string= (at maf-solve-test--geq -2) "x <= -0.5"))
    (cl-assert (string= (at maf-solve-test--geq 0) "0")))

  ;; An equation Calc cannot solve symbolically remains unchanged.
  (maf-push "x^6 + x + 1 = 0")
  (goto-char (point-max)) (call-interactively 'mafcmd-auto-solve)
  (cl-assert (string= (math-format-value (calc-top 1 'full))
                      "x^6 + x + 1 = 0"))
  (calc-pop (calc-stack-size))

  ;; A power of a compound base peels (`maf--solve-peel'): degree 8 is
  ;; past the whole-equation solver, but the base's own equation is
  ;; not, and the layer's solution carries the solve home.
  (maf-push "(x - 8)^8 = 256")
  (goto-char (point-max)) (call-interactively 'mafcmd-auto-solve)
  (cl-assert (string= (math-format-flat-expr
                       (maf--strip-encasing (calc-top 1 'full)) 0)
                      "x = 10"))
  (calc-pop (calc-stack-size))

  ;; Keep-args leaves the original relation below the solved result.
  (maf-push "2 x = 1")
  (call-interactively 'calc-keep-args)
  (call-interactively 'mafcmd-auto-solve)
  (cl-assert (= (calc-stack-size) 2))
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "x = 1:2"))
  (cl-assert (string= (math-format-value (calc-top 2 'full)) "2 x = 1"))
  (calc-pop (calc-stack-size))

  ;; Empty-stack invocation fails cleanly without creating an entry.
  (let (message)
    (condition-case err
        (call-interactively 'mafcmd-auto-solve)
      (error (setq message (error-message-string err))))
    (cl-assert (string= message "Too few elements on stack"))
    (cl-assert (zerop (calc-stack-size)))))
