(maf-step
  ;; Point on a sub-expression solves the relation for it, standing it
  ;; alone on the left.
  (maf-push "a = b c")
  (progn (calc-cursor-stack-index 1) (beginning-of-line)
         (search-forward "b") (backward-char 1))
  (call-interactively 'mafcmd-isolate)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "b = a / c"))
  ;; Point follows the isolated expression: it now leads the entry.
  (cl-assert (eq (char-after) ?b))
  (calc-clear-selections) (calc-pop (calc-stack-size))

  ;; A compound sub-expression is isolated whole: point on the product
  ;; 30 x (its multiplication gap, just after 30) isolates 30 x, not x.
  ;; This is the case that separates the command from `mafcmd-auto-solve',
  ;; which solves the same entry for x wherever point sits.
  (maf-push "y = 30 x + 12")
  (progn (calc-cursor-stack-index 1) (beginning-of-line) (search-forward "30"))
  (call-interactively 'mafcmd-isolate)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "30 x = y - 12"))
  ;; Point keeps its spot within the product — the gap just after 30.
  (cl-assert (and (eq (char-before) ?0) (eq (char-after) ?\s)))
  (calc-clear-selections) (calc-pop (calc-stack-size))

  ;; Point follows into a parenthesized sub-expression: on the + inside
  ;; (a + b) it lands on the + of the isolated, now unparenthesized a + b.
  (maf-push "y = (a + b) c")
  (progn (calc-cursor-stack-index 1) (beginning-of-line)
         (search-forward "+") (backward-char 1))
  (call-interactively 'mafcmd-isolate)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "a + b = y / c"))
  (cl-assert (eq (char-after) ?+))
  (calc-clear-selections) (calc-pop (calc-stack-size))

  ;; A compound target nested under a nonlinear operator is isolated by
  ;; substitution — calc cannot solve for it directly through the sqrt.
  (maf-push "sqrt(x + 1) = 3 y")
  (progn (calc-cursor-stack-index 1) (beginning-of-line)
         (search-forward "+") (backward-char 1))
  (call-interactively 'mafcmd-isolate)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "x + 1 = 9 y^2"))
  (cl-assert (eq (char-after) ?+))
  (calc-clear-selections) (calc-pop (calc-stack-size))

  ;; Isolating a fraction stays exact too.
  (maf-push "5 x = 1")
  (progn (calc-cursor-stack-index 1) (beginning-of-line)
         (search-forward "x") (backward-char 1))
  (call-interactively 'mafcmd-isolate)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "x = 1:5"))
  (calc-clear-selections) (calc-pop (calc-stack-size))

  ;; A bare constant is isolated too, consistent with subexpr targeting;
  ;; point follows it.
  (maf-push "x + 3 = 7")
  (progn (calc-cursor-stack-index 1) (beginning-of-line)
         (search-forward "3") (backward-char 1))
  (call-interactively 'mafcmd-isolate)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "3 = -x + 7"))
  (cl-assert (eq (char-after) ?3))
  (calc-clear-selections) (calc-pop (calc-stack-size))

  ;; Isolate a power: point on the ^ isolates the whole x^2, not the base
  ;; x, and point follows onto the operator.
  (maf-push "x^2 + 1 = 5")
  (progn (calc-cursor-stack-index 1) (beginning-of-line)
         (search-forward "^") (backward-char 1))
  (call-interactively 'mafcmd-isolate)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "x^2 = 4"))
  (cl-assert (eq (char-after) ?^))
  (calc-clear-selections) (calc-pop (calc-stack-size))

  ;; Isolating a multi-term sum lifts it whole to the left.
  (maf-push "y = a + b + c")
  (progn (calc-cursor-stack-index 1) (beginning-of-line)
         (search-forward "a") (backward-char 1))
  (call-interactively 'mafcmd-isolate)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "a = y - c - b"))
  (cl-assert (eq (char-after) ?a))
  (calc-clear-selections) (calc-pop (calc-stack-size))

  ;; --- Falling back to the variable solve ---

  ;; Point on the = itself has no sub-formula to isolate, so it solves
  ;; the whole relation for a variable.
  (maf-push "x + 3 = 7")
  (progn (calc-cursor-stack-index 1) (beginning-of-line)
         (search-forward "=") (backward-char 1))
  (call-interactively 'mafcmd-isolate)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "x = 4"))
  (calc-clear-selections) (calc-pop (calc-stack-size))

  ;; The line's end names no sub-formula either: the fallback solves and
  ;; cycles exactly as `mafcmd-auto-solve' does.
  (maf-push "x + y = 5")
  (goto-char (point-max))
  (call-interactively 'mafcmd-isolate)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "x = -y + 5"))
  (call-interactively 'mafcmd-isolate)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "y = -x + 5"))
  (calc-pop (calc-stack-size))

  ;; If compound isolation fails, the documented variable fallback still
  ;; runs, and point lands on what that solve isolated — the variable x,
  ;; not the + it was invoked from and not the relation operator, which
  ;; would read as if the target had been lifted to the left.
  (maf-push "2 x = f(y + z)")
  (progn (calc-cursor-stack-index 1) (beginning-of-line)
         (search-forward "+") (backward-char 1))
  (call-interactively 'mafcmd-isolate)
  (cl-assert (string= (math-format-value (calc-top 1 'full))
                      "x = f(y + z) / 2"))
  (cl-assert (eq (char-after) ?x))
  (calc-pop (calc-stack-size))

  ;; --- Substitution mechanics ---

  ;; Structural substitution intentionally replaces equal occurrences of a
  ;; compound target, so two equal factors isolate as one shared expression.
  (maf-push "y = (a + b) (a + b)")
  (progn (calc-cursor-stack-index 1) (beginning-of-line)
         (search-forward "+") (backward-char 1))
  (call-interactively 'mafcmd-isolate)
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
          (call-interactively 'mafcmd-isolate)
          (cl-assert (string= (math-format-value (calc-top 1 'full))
                              "a + b = u0 / 2")))
      (calc-pop (calc-stack-size))))

  ;; --- Selections and stack positions ---

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
        (execute-kbd-macro (kbd "j i")))))
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
  (call-interactively 'mafcmd-isolate)
  (cl-assert (string= (math-format-value (calc-top 2 'full)) "b = a / c"))
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "777"))
  (cl-assert (null (nth 2 (calc-top 2 'entry))))
  (cl-assert (null calc-any-selections))
  (calc-pop (calc-stack-size))

  ;; Sub-expression isolation on a lower entry: the isolate happens in
  ;; place at index 2, point follows onto the lifted factor, and the top
  ;; entry is left intact.
  (maf-push "a = b c")       ; index 2
  (maf-push "111")           ; index 1 (top)
  (progn (calc-cursor-stack-index 2) (beginning-of-line)
         (search-forward "b") (backward-char 1))
  (call-interactively 'mafcmd-isolate)
  (cl-assert (string= (math-format-value (calc-top 2 'full)) "b = a / c"))
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "111"))
  (cl-assert (eq (char-after) ?b))
  (calc-clear-selections) (calc-pop (calc-stack-size))

  ;; --- Point bookkeeping ---

  ;; Undo and redo restore both the entry and the original spot within the
  ;; isolated compound; this covers the command's custom point handling.
  (maf-push "y = 30 x + 12")
  (progn (calc-cursor-stack-index 1) (beginning-of-line) (search-forward "30"))
  (call-interactively 'mafcmd-isolate)
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

  ;; --- The binding ---

  ;; j i isolates the sub-expression under point, on a key calc leaves
  ;; unbound; calc's own j I (calc-sel-isolate) stays reachable.
  (maf-push "y = 30 x + 12")
  (let* ((buf (get-buffer "*Calculator*"))
         (win (get-buffer-window buf t)))
    (cl-assert win)
    (with-selected-window win
      (with-current-buffer buf
        (calc-cursor-stack-index 1) (beginning-of-line)
        (search-forward ":  ") (search-forward "12") (backward-char 2)
        (execute-kbd-macro (kbd "j i")))))
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "12 = y - 30 x"))
  (calc-clear-selections) (calc-pop (calc-stack-size))
  (cl-assert (eq (lookup-key calc-mode-map (kbd "j I")) 'calc-sel-isolate)))
