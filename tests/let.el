;; mafcmd-let: the top entry is a temporary assignment (or a vector of
;; them) and the entry point names is evaluated under it. The first case
;; goes through the M-<return> binding, the command's only key; the rest
;; call the command directly to isolate its behavior from key lookup.

(maf-step
  ;; The key is maf's own, not the edit module's: the module is what
  ;; used to hold it, so the lookup has to survive the module being
  ;; toggled off and on.
  (cl-assert (eq (lookup-key maf-mode-map (kbd "M-<return>")) 'mafcmd-let))
  (progn (maf-use-edit-mode -1) (maf-use-edit-mode 1) nil)
  (cl-assert (eq (lookup-key maf-mode-map (kbd "M-<return>")) 'mafcmd-let))

  ;; Home: the top entry is the argument, level 2 the subject. The value
  ;; is evaluated in, so the formula folds around it. Run from the key,
  ;; so the binding itself is covered.
  (maf-push "2 x + 1")
  (maf-push "x := 3")
  (goto-char (point-max))
  (execute-kbd-macro (kbd "M-<return>"))
  (cl-assert (= (calc-stack-size) 1))
  (cl-assert (equal (calc-top 1 'full) 7))
  ;; The binding was temporary: nothing is stored afterwards.
  (cl-assert (not (boundp 'var-x)))
  (calc-pop (calc-stack-size))

  ;; A plain equation is an assignment too — x = 3 binds as x := 3 does.
  (maf-push "2 x + 1")
  (maf-push "x = 3")
  (goto-char (point-max))
  (call-interactively 'mafcmd-let)
  (cl-assert (equal (calc-top 1 'full) 7))
  (calc-pop (calc-stack-size))

  ;; A vector binds every variable in it at once.
  (maf-push "a x")
  (maf-push "[x := 3, a := 2]")
  (goto-char (point-max))
  (call-interactively 'mafcmd-let)
  (cl-assert (equal (calc-top 1 'full) 6))
  (cl-assert (not (boundp 'var-a)))
  (calc-pop (calc-stack-size))

  ;; A variable the assignments do not name, and that has no value
  ;; anywhere, stands.
  (maf-push "x + y")
  (maf-push "x := 3")
  (goto-char (point-max))
  (call-interactively 'mafcmd-let)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "y + 3"))
  (calc-pop (calc-stack-size))

  ;; Equation subject: each side is evaluated and the relation rebuilt.
  (maf-push "y = x^2 + 1")
  (maf-push "x := 3")
  (goto-char (point-max))
  (call-interactively 'mafcmd-let)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "y = 10"))
  (calc-pop (calc-stack-size))

  ;; A plain equation assignment also stays whole when the subject is an
  ;; equation; generic equation arithmetic would pair their sides.
  (maf-push "6 x + 12 = 18 y + 6")
  (maf-push "x = 2")
  (goto-char (point-max))
  (call-interactively 'mafcmd-let)
  (cl-assert (string= (math-format-value (calc-top 1 'full))
                      "24 = 18 y + 6"))
  (calc-pop (calc-stack-size))

  ;; Point inside the subject's formula does not narrow it: the entry is
  ;; evaluated whole, both x's taking the value.
  (maf-push "x^2 + x")
  (maf-push "x := 3")
  (progn (calc-cursor-stack-index 2) (end-of-line) (backward-char 1))
  (call-interactively 'mafcmd-let)
  (cl-assert (equal (calc-top 1 'full) 12))
  (calc-pop (calc-stack-size))

  ;; Point inside the argument itself is the same gesture: the entry
  ;; below is the subject, so the assignment just typed can be used
  ;; without moving back to the formula it binds.
  (maf-push "x^2 + x")
  (maf-push "x := 3")
  (progn (calc-cursor-stack-index 1) (end-of-line) (backward-char 1))
  (call-interactively 'mafcmd-let)
  (cl-assert (equal (calc-top 1 'full) 12))
  (calc-pop (calc-stack-size))

  ;; A region does narrow the subject: only the term it covers takes the
  ;; value, the other x stands. (Set and fired in one form — the harness
  ;; deactivates the mark around every form.)
  (maf-push "x^2 + x")
  (maf-push "x := 3")
  (progn (calc-cursor-stack-index 2)
         (search-forward "x^2 + " (line-end-position))
         (push-mark (line-end-position) t t)
         (call-interactively 'mafcmd-let))
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "x^2 + 3"))
  (calc-pop (calc-stack-size))

  ;; Selection: the evaluation is confined to the selected node, and the
  ;; node folds. (The * is explicit: "y (x + 2)" would parse as a call.)
  (maf-push "y*(x + 2)")
  (maf-push "x := 3")
  (progn (calc-cursor-stack-index 2)
         (search-forward "+ 2" (line-end-position))
         (goto-char (match-beginning 0))
         (call-interactively 'calc-select-here)
         (call-interactively 'mafcmd-let))
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "y 5"))
  (calc-clear-selections)
  (calc-pop (calc-stack-size))

  ;; With only the x selected, what surrounds it stands: the sum holding
  ;; the value is not re-folded.
  (maf-push "y*(x + 2)")
  (maf-push "x := 3")
  (progn (calc-cursor-stack-index 2)
         (search-forward "x + 2" (line-end-position))
         (goto-char (match-beginning 0))
         (call-interactively 'calc-select-here)
         (call-interactively 'mafcmd-let))
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "y*(3 + 2)"))
  (calc-clear-selections)
  (calc-pop (calc-stack-size))

  ;; With simplification off the value lands in place without folding.
  (maf-push "2 x + 1")
  (maf-push "x := 3")
  (goto-char (point-max))
  (let ((calc-simplify-mode 'none))
    (call-interactively 'mafcmd-let))
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "2 3 + 1"))
  (calc-pop (calc-stack-size))

  ;; Being an evaluation, a variable stored for real is substituted too —
  ;; calc's own `s l' behavior.
  (progn (setq var-y 4) nil)
  (maf-push "x + y")
  (maf-push "x := 3")
  (goto-char (point-max))
  (call-interactively 'mafcmd-let)
  (cl-assert (equal (calc-top 1 'full) 7))
  (calc-pop (calc-stack-size))

  ;; A variable that had a value gets it back: the binding shadows it
  ;; for the evaluation only.
  (maf-push "y + 1")
  (maf-push "y := 10")
  (goto-char (point-max))
  (call-interactively 'mafcmd-let)
  (cl-assert (equal (calc-top 1 'full) 11))
  (cl-assert (equal var-y 4))
  (progn (makunbound 'var-y) nil)
  (calc-pop (calc-stack-size))

  ;; Keep-args: both operands stay and the result is pushed on top.
  (maf-push "2 x + 1")
  (maf-push "x := 3")
  (goto-char (point-max))
  (call-interactively 'calc-keep-args)
  (call-interactively 'mafcmd-let)
  (cl-assert (= (calc-stack-size) 3))
  (cl-assert (equal (calc-top 1 'full) 7))
  (cl-assert (string= (math-format-value (calc-top 2 'full)) "x := 3"))
  (cl-assert (string= (math-format-value (calc-top 3 'full)) "2 x + 1"))
  (calc-pop (calc-stack-size))

  ;; A top entry that is not an assignment signals, stack untouched.
  (maf-push "2 x + 1")
  (maf-push "3")
  (goto-char (point-max))
  (cl-assert (eq 'user-error
                 (condition-case err
                     (progn (call-interactively 'mafcmd-let) nil)
                   (user-error (car err)))))
  (cl-assert (= (calc-stack-size) 2))
  (cl-assert (string= (math-format-value (calc-top 2 'full)) "2 x + 1"))
  (calc-pop (calc-stack-size))

  ;; A vector with a non-assignment in it is not an assignment list.
  (maf-push "2 x + 1")
  (maf-push "[x := 3, 5]")
  (goto-char (point-max))
  (cl-assert (eq 'user-error
                 (condition-case err
                     (progn (call-interactively 'mafcmd-let) nil)
                   (user-error (car err)))))
  (cl-assert (= (calc-stack-size) 2))
  (cl-assert (not (boundp 'var-x)))
  (calc-pop (calc-stack-size))

  ;; A vector naming one variable throughout branches on its own — a
  ;; joint set would silently keep only the last value, so each
  ;; assignment evaluates separately, as under H.
  (maf-push "x")
  (maf-push "[x := 1, x := 2]")
  (goto-char (point-max))
  (call-interactively 'mafcmd-let)
  (cl-assert (equal (calc-top 1 'full) '(vec 1 2)))
  (calc-pop (calc-stack-size))

  ;; The same auto-branching over a relation subject: each branch's
  ;; result is a whole relation.
  (maf-push "y = x - 2")
  (maf-push "[x = 1, x = 2]")
  (goto-char (point-max))
  (call-interactively 'mafcmd-let)
  (cl-assert (string= (math-format-value
                       (maf--strip-encasing (calc-top 1 'full)))
                      "[y = -1, y = 0]"))
  (cl-assert (= (calc-stack-size) 1))
  (calc-pop (calc-stack-size))

  ;; Joint over distinct variables and a relation subject: both values
  ;; go in at once, and the scalar answer is the truth of the point —
  ;; here (1, 2) is not on the line.
  (maf-push "y = 2 x + 1")
  (maf-push "[x = 1, y = 2]")
  (goto-char (point-max))
  (call-interactively 'mafcmd-let)
  (cl-assert (string= (math-format-value
                       (maf--strip-encasing (calc-top 1 'full)))
                      "2 = 3"))
  (cl-assert (= (calc-stack-size) 1))
  (calc-pop (calc-stack-size))

  ;; H (mafcmd-let-each): each assignment is a branch of its own, the
  ;; subject evaluated under it alone, results in a vector. The flag
  ;; gesture lives in a single form — the cockpit presses keys of its
  ;; own between forms, and a pending prefix must not be exposed to
  ;; them.
  (maf-push "y = 2 x + 1")
  (maf-push "[x = 1, y = 2]")
  (progn (goto-char (point-max))
         (execute-kbd-macro (kbd "H M-RET"))
         (cl-assert (string= (math-format-value
                              (maf--strip-encasing (calc-top 1 'full)))
                             "[y = 3, 2 = 2 x + 1]")))
  (cl-assert (= (calc-stack-size) 1))

  ;; A mapped auto-solve carries the branches on to the solved form —
  ;; the pipeline the branch variant exists for.
  (progn (setq maf-map-flag t)
         (call-interactively 'mafcmd-auto-solve))
  (cl-assert (string= (math-format-value
                       (maf--strip-encasing (calc-top 1 'full)))
                      "[y = 3, x = 1:2]"))
  (calc-pop (calc-stack-size))

  ;; The motivating shape: a solution vector feeds back whole, one
  ;; result per solution — the relations landing as substitution
  ;; leaves them, like any let over a relation.
  (maf-push "x = 2 y - 1")
  (maf-push "[x = 6, x = 0]")
  (progn (goto-char (point-max))
         (execute-kbd-macro (kbd "H M-RET"))
         (cl-assert (string= (math-format-value
                              (maf--strip-encasing (calc-top 1 'full)))
                             "[6 = 2 y - 1, 0 = 2 y - 1]")))
  (cl-assert (= (calc-stack-size) 1))
  (calc-pop (calc-stack-size))

  ;; A lone assignment under H is one branch: still a vector, of one.
  (maf-push "2 x + 1")
  (maf-push "x := 3")
  (progn (goto-char (point-max))
         (execute-kbd-macro (kbd "H M-RET"))
         (cl-assert (equal (maf--strip-encasing (calc-top 1 'full))
                           '(vec 7))))
  (cl-assert (= (calc-stack-size) 1))
  (calc-pop (calc-stack-size))

  ;; An assignment whose value is itself symbolic: the expression goes
  ;; in and evaluation continues through it.
  (maf-push "2 x")
  (maf-push "x := y + 1")
  (goto-char (point-max))
  (call-interactively 'mafcmd-let)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "2 y + 2"))
  (calc-pop (calc-stack-size)))
