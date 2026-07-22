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
  (calc-pop (calc-stack-size)))
