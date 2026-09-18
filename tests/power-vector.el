;; mafcmd-pow on a vector: ^ and : raise element by element, a matrix
;; at each of its elements, as commands act on vectors generally. Calc's
;; own power — the vector or matrix multiplied by itself — is
;; mafcmd-pow-whole on the Hyperbolic flag; the Inverse flag is still
;; the root. The three keys that square are checked side by side at
;; the end: : and W element by element, I Q the sum of the squares.
;; Driven by the real keys. A step passes when it raises no error.

(maf-step
  (cl-assert (eq (key-binding (kbd "^")) 'mafcmd-pow))
  (cl-assert (eq (key-binding (kbd ":")) 'mafcmd-pow))
  ;; Both carry the operation stamp the combinators read, and the power
  ;; is no table row any more.
  (cl-assert (equal (get 'mafcmd-pow 'maf-operation) '(calcFunc-pow . 2)))
  (cl-assert (equal (get 'mafcmd-pow-whole 'maf-operation) '(calcFunc-pow . 2)))
  (cl-assert (null (assq 'mafcmd-pow maf-cmds--table)))

  ;; --- The example: a vector base, a scalar exponent ---

  (maf-push "[a, b, c]")
  (maf-push "2")
  (goto-char (point-max))
  (execute-kbd-macro ":")
  (cl-assert (string= (math-format-value (calc-top 1 'full))
                      "[a^2, b^2, c^2]"))
  (cl-assert (= (calc-stack-size) 1))
  (calc-pop (calc-stack-size))

  (maf-push "[a, b, c]")
  (maf-push "2")
  (goto-char (point-max))
  (execute-kbd-macro "^")
  (cl-assert (string= (math-format-value (calc-top 1 'full))
                      "[a^2, b^2, c^2]"))
  (calc-pop (calc-stack-size))

  ;; A symbolic exponent goes to each element whole.
  (maf-push "[a, b]")
  (maf-push "x")
  (goto-char (point-max))
  (execute-kbd-macro "^")
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "[a^x, b^x]"))
  (calc-pop (calc-stack-size))

  ;; A matrix is raised at each of its elements, not multiplied by
  ;; itself.
  (maf-push "[[1, 2], [3, 4]]")
  (maf-push "2")
  (goto-char (point-max))
  (execute-kbd-macro "^")
  (cl-assert (equal (calc-top 1 'full) '(vec (vec 1 4) (vec 9 16))))
  (calc-pop (calc-stack-size))

  ;; --- The other vector shapes ---

  ;; A vector exponent raises the base at each of its elements.
  (maf-push "2")
  (maf-push "[a, b]")
  (goto-char (point-max))
  (execute-kbd-macro "^")
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "[2^a, 2^b]"))
  (calc-pop (calc-stack-size))

  ;; Two vectors of one length pair off, position by position.
  (maf-push "[a, b]")
  (maf-push "[2, 3]")
  (goto-char (point-max))
  (execute-kbd-macro "^")
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "[a^2, b^3]"))
  (calc-pop (calc-stack-size))

  ;; Of different lengths they are calc's dimension error, and the
  ;; stack is left as it was.
  (maf-push "[a, b]")
  (maf-push "[1, 2, 3]")
  (goto-char (point-max))
  (cl-assert (not (ignore-errors (execute-kbd-macro "^") t)))
  (cl-assert (= (calc-stack-size) 2))
  (calc-pop (calc-stack-size))

  ;; A scalar is raised as before.
  (maf-push "2 x + 1")
  (maf-push "2")
  (goto-char (point-max))
  (execute-kbd-macro "^")
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "(2 x + 1)^2"))
  (calc-pop (calc-stack-size))

  ;; --- Targets and flags ---

  ;; A vector at a sub-formula target is raised in place, elementwise.
  (maf-push "f([a, b]) + 1")
  (maf-push "2")
  (progn (calc-cursor-stack-index 2) (beginning-of-line)
         (search-forward "[") (backward-char 1))
  (execute-kbd-macro "^")
  (cl-assert (string= (math-format-value (calc-top 1 'full))
                      "f([a^2, b^2]) + 1"))
  (calc-pop (calc-stack-size))

  ;; Each side of an equation, as usual.
  (maf-push "[a, b] = [c, d]")
  (maf-push "2")
  (goto-char (point-max))
  (execute-kbd-macro "^")
  (cl-assert (string= (math-format-value (calc-top 1 'full))
                      "[a^2, b^2] = [c^2, d^2]"))
  (calc-pop (calc-stack-size))

  ;; The map flag agrees: M ^ is the same elementwise power.
  (maf-push "[a, b]")
  (maf-push "2")
  (goto-char (point-max))
  (execute-kbd-macro (kbd "M ^"))
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "[a^2, b^2]"))
  (calc-pop (calc-stack-size))

  ;; From digit entry the colon is the same command, the number typed
  ;; the exponent.
  (maf-push "[a, b]")
  (goto-char (point-max))
  (execute-kbd-macro (kbd "2 :"))
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "[a^2, b^2]"))
  (calc-pop (calc-stack-size))

  ;; H ^ is calc's own power: the vector times itself, a matrix its
  ;; matrix power.
  (maf-push "[a, b]")
  (maf-push "2")
  (goto-char (point-max))
  (execute-kbd-macro (kbd "H ^"))
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "a^2 + b^2"))
  (calc-pop (calc-stack-size))

  (maf-push "[[1, 2], [3, 4]]")
  (maf-push "2")
  (goto-char (point-max))
  (execute-kbd-macro (kbd "H ^"))
  (cl-assert (equal (calc-top 1 'full) '(vec (vec 7 10) (vec 15 22))))
  (calc-pop (calc-stack-size))

  ;; I ^ is still the root.
  (maf-push "y")
  (maf-push "3")
  (goto-char (point-max))
  (execute-kbd-macro (kbd "I ^"))
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "y^1:3"))
  (calc-pop (calc-stack-size))

  ;; --- The three squares side by side ---

  ;; : with 2 and W square element by element; I Q squares the
  ;; elements and adds them.
  (maf-push "[a, b, c]")
  (maf-push "2")
  (goto-char (point-max))
  (execute-kbd-macro ":")
  (cl-assert (string= (math-format-value (calc-top 1 'full))
                      "[a^2, b^2, c^2]"))
  (calc-pop (calc-stack-size))

  (maf-push "[a, b, c]")
  (goto-char (point-max))
  (execute-kbd-macro "W")
  (cl-assert (string= (math-format-value (calc-top 1 'full))
                      "[a^2, b^2, c^2]"))
  (calc-pop (calc-stack-size))

  (maf-push "[a, b, c]")
  (goto-char (point-max))
  (execute-kbd-macro (kbd "I Q"))
  (cl-assert (string= (math-format-value (calc-top 1 'full))
                      "a^2 + b^2 + c^2"))
  (calc-pop (calc-stack-size)))
