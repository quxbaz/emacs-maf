(maf-step
  ;; One variable: solve for it.
  (maf-push "x + 3 = 7")
  (goto-char (point-max))
  (call-interactively 'mafcmd-auto-solve)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "x = 4"))
  (calc-pop (calc-stack-size))

  ;; Isolate: point on a sub-expression solves the relation for it,
  ;; standing it alone on the left.
  (maf-push "a = b c")
  (progn (calc-cursor-stack-index 1) (beginning-of-line)
         (search-forward "b") (backward-char 1))
  (call-interactively 'mafcmd-auto-solve)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "b = a / c"))
  ;; Point follows the isolated expression: it now leads the entry.
  (cl-assert (eq (char-after) ?b))
  (calc-clear-selections) (calc-pop (calc-stack-size))

  ;; A compound sub-expression is isolated whole: point on the product
  ;; 30 x (its multiplication gap, just after 30) isolates 30 x, not x.
  (maf-push "y = 30 x + 12")
  (progn (calc-cursor-stack-index 1) (beginning-of-line) (search-forward "30"))
  (call-interactively 'mafcmd-auto-solve)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "30 x = y - 12"))
  ;; Point keeps its spot within the product — the gap just after 30.
  (cl-assert (and (eq (char-before) ?0) (eq (char-after) ?\s)))
  (calc-clear-selections) (calc-pop (calc-stack-size))

  ;; Point follows into a parenthesized sub-expression: on the + inside
  ;; (a + b) it lands on the + of the isolated, now unparenthesized a + b.
  (maf-push "y = (a + b) c")
  (progn (calc-cursor-stack-index 1) (beginning-of-line)
         (search-forward "+") (backward-char 1))
  (call-interactively 'mafcmd-auto-solve)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "a + b = y / c"))
  (cl-assert (eq (char-after) ?+))
  (calc-clear-selections) (calc-pop (calc-stack-size))

  ;; A compound target nested under a nonlinear operator is isolated by
  ;; substitution — calc cannot solve for it directly through the sqrt.
  (maf-push "sqrt(x + 1) = 3 y")
  (progn (calc-cursor-stack-index 1) (beginning-of-line)
         (search-forward "+") (backward-char 1))
  (call-interactively 'mafcmd-auto-solve)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "x + 1 = 9 y^2"))
  (cl-assert (eq (char-after) ?+))
  (calc-clear-selections) (calc-pop (calc-stack-size))

  ;; Isolating a fraction stays exact too.
  (maf-push "5 x = 1")
  (progn (calc-cursor-stack-index 1) (beginning-of-line)
         (search-forward "x") (backward-char 1))
  (call-interactively 'mafcmd-auto-solve)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "x = 1:5"))
  (calc-clear-selections) (calc-pop (calc-stack-size))

  ;; A bare constant is isolated too, consistent with subexpr targeting;
  ;; point follows it.
  (maf-push "x + 3 = 7")
  (progn (calc-cursor-stack-index 1) (beginning-of-line)
         (search-forward "3") (backward-char 1))
  (call-interactively 'mafcmd-auto-solve)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "3 = 7 - x"))
  (cl-assert (eq (char-after) ?3))
  (calc-clear-selections) (calc-pop (calc-stack-size))

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
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "x = 5 - y"))
  (call-interactively 'mafcmd-auto-solve)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "y = 5 - x"))
  (calc-pop (calc-stack-size))

  ;; Non-priority variables sort alphabetically (a before b).
  (maf-push "b + a = 5")
  (goto-char (point-max))
  (call-interactively 'mafcmd-auto-solve)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "a = 5 - b"))
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

  ;; Isolate a power: point on the ^ isolates the whole x^2, not the base
  ;; x, and point follows onto the operator.
  (maf-push "x^2 + 1 = 5")
  (progn (calc-cursor-stack-index 1) (beginning-of-line)
         (search-forward "^") (backward-char 1))
  (call-interactively 'mafcmd-auto-solve)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "x^2 = 4"))
  (cl-assert (eq (char-after) ?^))
  (calc-clear-selections) (calc-pop (calc-stack-size))

  ;; Isolating a multi-term sum lifts it whole to the left.
  (maf-push "y = a + b + c")
  (progn (calc-cursor-stack-index 1) (beginning-of-line)
         (search-forward "a") (backward-char 1))
  (call-interactively 'mafcmd-auto-solve)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "a = y - c - b"))
  (cl-assert (eq (char-after) ?a))
  (calc-clear-selections) (calc-pop (calc-stack-size))

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

  ;; Point on the = itself has no sub-formula to isolate, so it solves
  ;; the whole relation for a variable.
  (maf-push "x + 3 = 7")
  (progn (calc-cursor-stack-index 1) (beginning-of-line)
         (search-forward "=") (backward-char 1))
  (call-interactively 'mafcmd-auto-solve)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "x = 4"))
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

  ;; Sub-expression isolation on a lower entry: the isolate happens in
  ;; place at index 2, point follows onto the lifted factor, and the top
  ;; entry is left intact.
  (maf-push "a = b c")       ; index 2
  (maf-push "111")           ; index 1 (top)
  (progn (calc-cursor-stack-index 2) (beginning-of-line)
         (search-forward "b") (backward-char 1))
  (call-interactively 'mafcmd-auto-solve)
  (cl-assert (string= (math-format-value (calc-top 2 'full)) "b = a / c"))
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "111"))
  (cl-assert (eq (char-after) ?b))
  (calc-clear-selections) (calc-pop (calc-stack-size))

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

  ;; A constant variable standing alone is not a solve-cycle candidate.
  ;; Solve the first actual unknown rather than indexing past a missing pi.
  (maf-push "pi = x + y")
  (goto-char (point-max)) (call-interactively 'mafcmd-auto-solve)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "x = pi - y"))
  (calc-pop (calc-stack-size))

  ;; Match Calc's documented unknown-sign inequality behavior: strict <
  ;; degrades to !=, while <= cannot be partially solved and stays intact.
  (maf-push "a < b c")
  (goto-char (point-max)) (call-interactively 'mafcmd-auto-solve)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "b != a / c"))
  (calc-pop (calc-stack-size))

  (maf-push "a <= b c")
  (goto-char (point-max)) (call-interactively 'mafcmd-auto-solve)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "a <= b c"))
  (calc-pop (calc-stack-size))

  ;; An equation Calc cannot solve symbolically remains unchanged.
  (maf-push "x^6 + x + 1 = 0")
  (goto-char (point-max)) (call-interactively 'mafcmd-auto-solve)
  (cl-assert (string= (math-format-value (calc-top 1 'full))
                      "x^6 + x + 1 = 0"))
  (calc-pop (calc-stack-size))

  ;; If compound isolation fails, the documented variable fallback still
  ;; runs, but point must not jump to the relation operator as if the target
  ;; had been lifted to the left.
  (maf-push "2 x = f(y + z)")
  (progn (calc-cursor-stack-index 1) (beginning-of-line)
         (search-forward "+") (backward-char 1))
  (call-interactively 'mafcmd-auto-solve)
  (cl-assert (string= (math-format-value (calc-top 1 'full))
                      "x = f(y + z) / 2"))
  (cl-assert (eq (char-after) ?z))
  (calc-pop (calc-stack-size))

  ;; Structural substitution intentionally replaces equal occurrences of a
  ;; compound target, so two equal factors isolate as one shared expression.
  (maf-push "y = (a + b) (a + b)")
  (progn (calc-cursor-stack-index 1) (beginning-of-line)
         (search-forward "+") (backward-char 1))
  (call-interactively 'mafcmd-auto-solve)
  (cl-assert (string= (math-format-value (calc-top 1 'full))
                      "a + b = sqrt(y)"))
  (cl-assert (eq (char-after) ?+))
  (calc-pop (calc-stack-size))

  ;; Fresh substitution variables avoid every variable node, including a
  ;; Calc special constant that the normal solve-candidate collector omits.
  (cl-progv (list 'var-u0) (list '(special-const (identity 42)))
    (unwind-protect
        (progn
          (maf-push "u0 = 2 (a + b)")
          (calc-cursor-stack-index 1) (beginning-of-line)
          (search-forward "+") (backward-char 1)
          (cl-assert (equal (maf--solve-fresh-var (calc-top 1 'full))
                            '(var u1 var-u1)))
          (call-interactively 'mafcmd-auto-solve)
          (cl-assert (string= (math-format-value (calc-top 1 'full))
                              "a + b = u0 / 2")))
      (calc-pop (calc-stack-size))))

  ;; An explicit Calc selection is honored as the isolation target, then
  ;; cleared when the entry-scoped replacement lands.
  (maf-push "a = b c")
  (progn (calc-cursor-stack-index 1) (beginning-of-line)
         (search-forward "b") (backward-char 1)
         (call-interactively 'calc-select-here))
  (cl-assert (nth 2 (calc-top 1 'entry)))
  (let* ((buf (get-buffer "*Calculator*"))
         (win (get-buffer-window buf t)))
    (cl-assert win)
    (with-selected-window win
      (with-current-buffer buf
        (execute-kbd-macro (kbd "M-i")))))
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "b = a / c"))
  (cl-assert (null (nth 2 (calc-top 1 'entry))))
  (cl-assert (null calc-any-selections))
  (cl-assert (eq (char-after) ?b))
  (calc-pop (calc-stack-size))

  ;; The same selection behavior works in place on a lower entry.
  (maf-push "a = b c")
  (maf-push "777")
  (progn (calc-cursor-stack-index 2) (beginning-of-line)
         (search-forward "b") (backward-char 1)
         (call-interactively 'calc-select-here))
  (call-interactively 'mafcmd-auto-solve)
  (cl-assert (string= (math-format-value (calc-top 2 'full)) "b = a / c"))
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "777"))
  (cl-assert (null (nth 2 (calc-top 2 'entry))))
  (cl-assert (null calc-any-selections))
  (calc-pop (calc-stack-size))

  ;; Keep-args leaves the original relation below the solved result.
  (maf-push "2 x = 1")
  (call-interactively 'calc-keep-args)
  (call-interactively 'mafcmd-auto-solve)
  (cl-assert (= (calc-stack-size) 2))
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "x = 1:2"))
  (cl-assert (string= (math-format-value (calc-top 2 'full)) "2 x = 1"))
  (calc-pop (calc-stack-size))

  ;; Undo and redo restore both the entry and the original spot within the
  ;; isolated compound; this covers the command's custom point bookkeeping.
  (maf-push "y = 30 x + 12")
  (progn (calc-cursor-stack-index 1) (beginning-of-line) (search-forward "30"))
  (call-interactively 'mafcmd-auto-solve)
  (cl-assert (and (string= (math-format-value (calc-top 1 'full))
                           "30 x = y - 12")
                  (eq (char-before) ?0) (eq (char-after) ?\s)))
  (progn (setq last-command nil) (call-interactively 'maf-undo))
  (cl-assert (and (string= (math-format-value (calc-top 1 'full))
                           "y = 30 x + 12")
                  (eq (char-before) ?0) (eq (char-after) ?\s)))
  (progn (setq last-command 'maf-undo) (call-interactively 'maf-redo))
  (cl-assert (and (string= (math-format-value (calc-top 1 'full))
                           "30 x = y - 12")
                  (eq (char-before) ?0) (eq (char-after) ?\s)))
  (calc-pop (calc-stack-size))

  ;; Empty-stack invocation fails cleanly without creating an entry.
  (let (message)
    (condition-case err
        (call-interactively 'mafcmd-auto-solve)
      (error (setq message (error-message-string err))))
    (cl-assert (string= message "Too few elements on stack"))
    (cl-assert (zerop (calc-stack-size)))))
