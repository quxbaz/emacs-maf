;; mafcmd-let: the top entry is a temporary assignment (or a vector of
;; them) and the entry point names is evaluated under it. Unbound for
;; now, so every case calls the command directly.

(maf-step
  ;; Home: the top entry is the argument, level 2 the subject. The value
  ;; is evaluated in, so the formula folds around it.
  (maf-push "2 x + 1")
  (maf-push "x := 3")
  (goto-char (point-max))
  (call-interactively 'mafcmd-let)
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

  ;; Sub-formula at point: only the term point names takes the value,
  ;; the other x stands.
  (maf-push "x^2 + x")
  (maf-push "x := 3")
  (progn (calc-cursor-stack-index 2) (end-of-line) (backward-char 1))
  (call-interactively 'mafcmd-let)
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

  ;; A vector naming the same variable twice: the later assignment is
  ;; the one that stands.
  (maf-push "x")
  (maf-push "[x := 1, x := 2]")
  (goto-char (point-max))
  (call-interactively 'mafcmd-let)
  (cl-assert (equal (calc-top 1 'full) 2))
  (calc-pop (calc-stack-size))

  ;; An assignment whose value is itself symbolic: the expression goes
  ;; in and evaluation continues through it.
  (maf-push "2 x")
  (maf-push "x := y + 1")
  (goto-char (point-max))
  (call-interactively 'mafcmd-let)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "2 y + 2"))
  (calc-pop (calc-stack-size)))
