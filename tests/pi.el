(maf-step
  ;; --- P: contextual pi (maf-pi) ---

  ;; At home with no selection: stays calc-pi — the constant is pushed
  ;; as a new entry, symbolic under Symbolic mode.
  (maf-push "7")
  (goto-char (point-max))
  (let ((calc-symbolic-mode t)) (execute-kbd-macro (kbd "P")))
  (cl-assert (= (calc-stack-size) 2))
  (cl-assert (equal (calc-top 1 'full) '(var pi var-pi)))
  (calc-pop (calc-stack-size))

  ;; ... and a float under the current precision otherwise.
  (goto-char (point-max))
  (let ((calc-symbolic-mode nil)) (execute-kbd-macro (kbd "P")))
  (cl-assert (math-floatp (calc-top 1 'full)))
  (calc-pop (calc-stack-size))

  ;; Subexpr on a variable: multiplied, constant on the right — unlike
  ;; `maf-quick-variable', a variable target is never replaced.
  (maf-push "x + 2")
  (progn (goto-char (point-min)) (search-forward "x") (backward-char 1))
  (execute-kbd-macro (kbd "P"))
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "x pi + 2"))
  (calc-pop (calc-stack-size))

  ;; On a numeric leaf the product goes in literally, as one factor —
  ;; the same commit maf-digit-pi's 2 n makes.
  (maf-push "2 x")
  (progn (goto-char (point-min)) (search-forward "2") (backward-char 1))
  (execute-kbd-macro (kbd "P"))
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "(2 pi) x"))
  (calc-pop (calc-stack-size))

  ;; Entry margin: the whole formula is multiplied, undistributed.
  (maf-push "y + 1")
  (progn (goto-char (point-min)) (end-of-line))
  (execute-kbd-macro (kbd "P"))
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "(y + 1) pi"))
  (calc-pop (calc-stack-size))

  ;; Equation from its margin: the body runs once per side.
  (maf-push "x = 3 y")
  (progn (goto-char (point-min)) (end-of-line))
  (execute-kbd-macro (kbd "P"))
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "x pi = 3 y pi"))
  (calc-pop (calc-stack-size))

  ;; A sub-formula inside one side: only that slot changes.
  (maf-push "x = 3 y")
  (progn (goto-char (point-min)) (search-forward "3") (backward-char 1))
  (execute-kbd-macro (kbd "P"))
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "x = (3 pi) y"))
  (calc-pop (calc-stack-size))

  ;; A calc selection narrows the target, even pressed from home.
  (maf-push "a + b")
  (progn (goto-char (point-min)) (search-forward "a") (backward-char 1))
  (call-interactively 'calc-select-here)
  (goto-char (point-max))
  (execute-kbd-macro (kbd "P"))
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "a pi + b"))
  (calc-clear-selections)
  (calc-pop (calc-stack-size))

  ;; The flags pick the sibling constants, as in calc: H is e, I is
  ;; gamma, I H is phi.
  (maf-push "x + 2")
  (progn (goto-char (point-min)) (search-forward "x") (backward-char 1))
  (execute-kbd-macro (kbd "H P"))
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "x e + 2"))
  (calc-pop (calc-stack-size))

  (maf-push "x + 2")
  (progn (goto-char (point-min)) (search-forward "x") (backward-char 1))
  (execute-kbd-macro (kbd "I P"))
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "x gamma + 2"))
  (calc-pop (calc-stack-size))

  (maf-push "x + 2")
  (progn (goto-char (point-min)) (search-forward "x") (backward-char 1))
  (execute-kbd-macro (kbd "I H P"))
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "x phi + 2"))
  (calc-pop (calc-stack-size))

  ;; Keep-args: the original entry stays below the result.
  (maf-push "x + 2")
  (progn (goto-char (point-min)) (search-forward "x") (backward-char 1))
  (execute-kbd-macro (kbd "K P"))
  (cl-assert (= (calc-stack-size) 2))
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "x pi + 2"))
  (cl-assert (string= (math-format-value (calc-top 2 'full)) "x + 2"))
  (calc-pop (calc-stack-size))

  ;; The map flag maps over a vector's elements, and outranks the home
  ;; push: M P at home multiplies each element, not a new pi entry.
  (maf-push "[1, x]")
  (goto-char (point-max))
  (execute-kbd-macro (kbd "M P"))
  (cl-assert (= (calc-stack-size) 1))
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "[pi, x pi]"))
  (calc-pop (calc-stack-size)))
