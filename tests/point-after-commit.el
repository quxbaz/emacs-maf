(maf-defcmd maf-square (expr arg commit)
  "Square command."
  :arity unary
  :prefix "sqr"
  (commit (calcFunc-mul expr expr)))

(maf-defcmd maf-mult (expr arg commit)
  "Multiplication command."
  :arity binary
  :prefix "mult"
  (commit (calcFunc-mul expr arg)))

(maf-step
  ;; target=home, point at home: point stays at home.
  (maf-push "8 x + 4")
  (calc-push 2)
  (goto-char (point-max))
  (call-interactively 'maf-mult)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "16 x + 8"))
  (cl-assert (maf--at-home-p))
  (calc-pop (calc-stack-size))

  ;; target=subexpr, point on the sub-formula: point stays on it.
  (maf-push "6 x + 12")
  (progn (goto-char (point-min)) (search-forward "x") (backward-char 1))
  (call-interactively 'maf-square)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "6 x^2 + 12"))
  (cl-assert (eq (char-after) ?x))
  (calc-pop (calc-stack-size))

  ;; target=entry from the line prefix: BOL affinity is kept on the line.
  (maf-push "8 x + 4")
  (maf-push "sin(y)")
  (progn (goto-char (point-min)) (forward-char 1))
  (call-interactively 'maf-square)
  (cl-assert (string= (math-format-value (calc-top 2 'full)) "(8 x + 4)^2"))
  (cl-assert (bolp))
  (cl-assert (= (line-number-at-pos) 1))
  (calc-pop (calc-stack-size))

  ;; target=equation from EOL of a relation entry: point stays at that
  ;; entry's EOL instead of jumping home.
  (maf-push "sin(y) = k")
  (calc-push 1)
  (calc-push 2)
  (progn (goto-char (point-min)) (end-of-line))
  (call-interactively 'maf-square)
  (cl-assert (string= (math-format-value (calc-top 3 'full)) "sin(y)^2 = k^2"))
  (cl-assert (eolp))
  (cl-assert (= (line-number-at-pos) 1))
  (calc-pop (calc-stack-size))

  ;; target=entry, binary with the arg below consumed: the entry's line is
  ;; stable across the pop, so EOL is restored on the same line.
  (maf-push "8 x + 4")
  (calc-push 2)
  (progn (goto-char (point-min)) (end-of-line))
  (call-interactively 'maf-mult)
  (cl-assert (= (calc-stack-size) 1))
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "16 x + 8"))
  (cl-assert (eolp))
  (cl-assert (= (line-number-at-pos) 1)))
