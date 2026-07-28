;; mafcmd-inverse-function: invert the function at point.

(maf-step
  ;; Linear: the plain variable on the left names the output.
  (maf-push "y = x + 1")
  (goto-char (point-max))
  (call-interactively 'mafcmd-inverse-function)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "y = x - 1"))
  (calc-pop (calc-stack-size))

  ;; A scale factor inverts exactly — a fraction, not a float.
  (maf-push "y = 2 x + 3")
  (goto-char (point-max))
  (call-interactively 'mafcmd-inverse-function)
  (cl-assert (string= (math-format-value (calc-top 1 'full))
                      "y = x / 2 - 3:2"))
  (calc-pop (calc-stack-size))

  ;; Square and root invert into each other (one branch, as calc solves).
  (maf-push "y = x^2")
  (goto-char (point-max))
  (call-interactively 'mafcmd-inverse-function)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "y = sqrt(x)"))
  (call-interactively 'mafcmd-inverse-function)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "y = x^2"))
  (calc-pop (calc-stack-size))

  ;; Parameters beside the input carry through: x is the input, k stays.
  (maf-push "y = e^(x + k) + 3")
  (goto-char (point-max))
  (call-interactively 'mafcmd-inverse-function)
  (cl-assert (string= (math-format-value (calc-top 1 'full))
                      "y = ln(x - 3) - k"))
  (calc-pop (calc-stack-size))

  ;; The output variable may stand on either side.
  (maf-push "x + 1 = y")
  (goto-char (point-max))
  (call-interactively 'mafcmd-inverse-function)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "y = x - 1"))
  (calc-pop (calc-stack-size))

  ;; Any names work: u is the output, v the input.
  (maf-push "u = 3 v - 6")
  (goto-char (point-max))
  (call-interactively 'mafcmd-inverse-function)
  (cl-assert (string= (math-format-value (calc-top 1 'full))
                      "u = v / 3 + 2"))
  (calc-pop (calc-stack-size))

  ;; An f(x) is kept as written; the body inverts under it.
  (maf-push "f(x) = x^2")
  (goto-char (point-max))
  (call-interactively 'mafcmd-inverse-function)
  (cl-assert (string= (math-format-value (calc-top 1 'full))
                      "f(x) = sqrt(x)"))
  (calc-pop (calc-stack-size))

  ;; The call's argument is the input variable, not the priority x —
  ;; f(k) inverts in k, with x carried through as a parameter.
  (maf-push "f(k) = k^2 + x")
  (goto-char (point-max))
  (call-interactively 'mafcmd-inverse-function)
  (cl-assert (string= (math-format-value (calc-top 1 'full))
                      "f(k) = sqrt(k - x)"))
  (calc-pop (calc-stack-size))

  ;; A known calc function is not a function-name slot: sqrt(y) = x + 1
  ;; is solved for its output first, then inverted.
  (maf-push "sqrt(y) = x + 1")
  (goto-char (point-max))
  (call-interactively 'mafcmd-inverse-function)
  (cl-assert (string= (math-format-value (calc-top 1 'full))
                      "y = sqrt(x) - 1"))
  (calc-pop (calc-stack-size))

  ;; Neither side alone: the equation is solved for y, then inverted.
  (maf-push "2 y = x + 1")
  (goto-char (point-max))
  (call-interactively 'mafcmd-inverse-function)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "y = 2 x - 1"))
  (calc-pop (calc-stack-size))

  ;; An implicit relation likewise; this one is its own inverse.
  (maf-push "x^2 + y^2 = 1")
  (goto-char (point-max))
  (call-interactively 'mafcmd-inverse-function)
  (cl-assert (string= (math-format-value (calc-top 1 'full))
                      "y = sqrt(1 - x^2)"))
  (calc-pop (calc-stack-size))

  ;; With no y, the second of two variables is the output: a = 2 b - 1
  ;; inverts as a function of b.
  (maf-push "2 b = a + 1")
  (goto-char (point-max))
  (call-interactively 'mafcmd-inverse-function)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "b = 2 a - 1"))
  (calc-pop (calc-stack-size))

  ;; A bare expression is the body alone; the inverse is named y.
  (maf-push "x + 1")
  (goto-char (point-max))
  (call-interactively 'mafcmd-inverse-function)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "y = x - 1"))
  (calc-pop (calc-stack-size))

  ;; A bare body that already uses y cannot be named y: y1 takes over,
  ;; and the y in the body stays a parameter.
  (maf-push "x + y")
  (goto-char (point-max))
  (call-interactively 'mafcmd-inverse-function)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "y1 = x - y"))
  (calc-pop (calc-stack-size))

  ;; The body's own variable is the input even when it is y.
  (maf-push "y^2")
  (goto-char (point-max))
  (call-interactively 'mafcmd-inverse-function)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "y1 = sqrt(y)"))
  (calc-pop (calc-stack-size))

  ;; --- Unchanged pass-throughs ---

  ;; An inequality states no function.
  (maf-push "2 x - 3 < 7")
  (goto-char (point-max))
  (call-interactively 'mafcmd-inverse-function)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "2 x - 3 < 7"))
  (calc-pop (calc-stack-size))

  ;; An equation with no variable in its body.
  (maf-push "y = 5")
  (goto-char (point-max))
  (call-interactively 'mafcmd-inverse-function)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "y = 5"))
  (calc-pop (calc-stack-size))

  ;; The output variable also occurring in the body: an implicit
  ;; relation, not a function of x.
  (maf-push "y = x + y")
  (goto-char (point-max))
  (call-interactively 'mafcmd-inverse-function)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "y = x + y"))
  (calc-pop (calc-stack-size))

  ;; A body calc cannot solve.
  (maf-push "y = x^6 + x + 1")
  (goto-char (point-max))
  (call-interactively 'mafcmd-inverse-function)
  (cl-assert (string= (math-format-value (calc-top 1 'full))
                      "y = x^6 + x + 1"))
  (calc-pop (calc-stack-size))

  ;; A number alone.
  (maf-push "5")
  (goto-char (point-max))
  (call-interactively 'mafcmd-inverse-function)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "5"))
  (calc-pop (calc-stack-size))

  ;; --- Targeting and modes ---

  ;; The whole entry is the subject: point on a sub-formula does not
  ;; narrow it, and no selection is left behind.
  (maf-push "y = 2 x + 3")
  (progn (calc-cursor-stack-index 1) (beginning-of-line)
         (search-forward "2"))
  (call-interactively 'mafcmd-inverse-function)
  (cl-assert (string= (math-format-value (calc-top 1 'full))
                      "y = x / 2 - 3:2"))
  (cl-assert (null (nth 2 (calc-top 1 'entry))))
  (calc-clear-selections) (calc-pop (calc-stack-size))

  ;; Point on a lower entry inverts that entry, leaving the top alone.
  (maf-push "y = x^2")            ; index 2 after the next push
  (maf-push "111")                ; the top decoy
  (progn (calc-cursor-stack-index 2) (goto-char (line-end-position)))
  (call-interactively 'mafcmd-inverse-function)
  (cl-assert (string= (math-format-value (calc-top 2 'full)) "y = sqrt(x)"))
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "111"))
  (calc-pop (calc-stack-size))

  ;; Exact whatever the global modes: symbolic and prefer-frac are
  ;; forced internally, so no float creeps in.
  (let ((calc-symbolic-mode nil) (calc-prefer-frac nil))
    (maf-push "y = 2 x + 3")
    (goto-char (point-max))
    (call-interactively 'mafcmd-inverse-function)
    (cl-assert (string= (math-format-value (calc-top 1 'full))
                        "y = x / 2 - 3:2"))
    (calc-pop (calc-stack-size)))

  ;; The real binding, pressed at home.
  (maf-push "y = x + 1")
  (let* ((buf (get-buffer "*Calculator*"))
         (win (get-buffer-window buf t)))
    (cl-assert win)
    (with-selected-window win
      (with-current-buffer buf
        (execute-kbd-macro (kbd "l v")))))
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "y = x - 1"))
  (calc-pop (calc-stack-size))

  ;; Empty stack: fails cleanly without creating an entry.
  (let (message)
    (condition-case err
        (call-interactively 'mafcmd-inverse-function)
      (error (setq message (error-message-string err))))
    (cl-assert (string= message "Too few elements on stack"))
    (cl-assert (zerop (calc-stack-size)))))
