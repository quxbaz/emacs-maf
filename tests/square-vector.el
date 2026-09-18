;; mafcmd-sqr on a vector: W squares element by element, a matrix each
;; of its elements, as commands act on vectors generally. Calc's own
;; square — the vector's product with itself — is mafcmd-sqr-whole,
;; kept as the Inverse route of Q. Driven by the real keys where the
;; keys are the point. A step passes when it raises no error.

(maf-step
  (cl-assert (eq (key-binding (kbd "W")) 'mafcmd-sqr))
  ;; Both carry the operation stamp the combinators read.
  (cl-assert (equal (get 'mafcmd-sqr 'maf-operation) '(calcFunc-sqr . 1)))
  (cl-assert (equal (get 'mafcmd-sqr-whole 'maf-operation) '(calcFunc-sqr . 1)))
  ;; The square is no table row any more; its Inverse link from sqrt
  ;; names the whole square.
  (cl-assert (null (assq 'mafcmd-sqr maf-cmds--table)))
  (cl-assert (eq (nth 4 (assq 'mafcmd-sqrt maf-cmds--table)) 'mafcmd-sqr-whole))

  ;; --- W: element by element ---

  (maf-push "[x, y]")
  (goto-char (point-max))
  (execute-kbd-macro "W")
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "[x^2, y^2]"))
  (calc-pop (calc-stack-size))

  ;; A matrix squares its elements, not itself.
  (maf-push "[[1, 2], [3, 4]]")
  (goto-char (point-max))
  (execute-kbd-macro "W")
  (cl-assert (equal (calc-top 1 'full) '(vec (vec 1 4) (vec 9 16))))
  (calc-pop (calc-stack-size))

  ;; A scalar is squared as before.
  (maf-push "2 x + 1")
  (goto-char (point-max))
  (execute-kbd-macro "W")
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "(2 x + 1)^2"))
  (calc-pop (calc-stack-size))

  ;; A vector at a sub-formula target squares in place, elementwise.
  (maf-push "f([x, y]) + 1")
  (progn (goto-char (point-min)) (search-forward "[") (backward-char 1))
  (execute-kbd-macro "W")
  (cl-assert (string= (math-format-value (calc-top 1 'full))
                      "f([x^2, y^2]) + 1"))
  (calc-pop (calc-stack-size))

  ;; Each side of an equation, as usual.
  (maf-push "[a, b] = [c, d]")
  (goto-char (point-max))
  (execute-kbd-macro "W")
  (cl-assert (string= (math-format-value (calc-top 1 'full))
                      "[a^2, b^2] = [c^2, d^2]"))
  (calc-pop (calc-stack-size))

  ;; The map flag agrees: M W is the same elementwise square.
  (maf-push "[x, y]")
  (goto-char (point-max))
  (execute-kbd-macro (kbd "M W"))
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "[x^2, y^2]"))
  (calc-pop (calc-stack-size))

  ;; --- I Q: the vector times itself ---

  (maf-push "[x, y]")
  (goto-char (point-max))
  (execute-kbd-macro (kbd "I Q"))
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "x^2 + y^2"))
  (calc-pop (calc-stack-size))

  ;; A matrix is its matrix square.
  (maf-push "[[1, 2], [3, 4]]")
  (goto-char (point-max))
  (execute-kbd-macro (kbd "I Q"))
  (cl-assert (equal (calc-top 1 'full) '(vec (vec 7 10) (vec 15 22))))
  (calc-pop (calc-stack-size))

  ;; On a scalar the two are one square.
  (maf-push "2 x + 1")
  (goto-char (point-max))
  (execute-kbd-macro (kbd "I Q"))
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "(2 x + 1)^2"))
  (calc-pop (calc-stack-size))

  ;; The command by name does the same.
  (maf-push "[x, y]")
  (goto-char (point-max))
  (call-interactively 'mafcmd-sqr-whole)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "x^2 + y^2"))
  (calc-pop (calc-stack-size)))
