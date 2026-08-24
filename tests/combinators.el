;; The combinators — v R reduce, v U accumulate, v A apply, v O outer,
;; v I inner — read their operation from the keyboard rather than
;; taking it as an operand. As mafcmd table rows they applied their
;; calcFunc to the resolved expression, building a call one argument
;; short that calc-normalize handed back inert: v O on two vectors
;; gave outer([1, 3, 9], [1, 2, 3, 6]).
;;
;; These drive real keys throughout: the operation is read with
;; read-key-sequence off the keymap, so call-interactively would skip
;; the whole mechanism.

(maf-step
  ;; The reported case: every quotient of two vectors, exactly.
  (progn (calc-pop (calc-stack-size))
         (maf-push "[1, 3, 9]") (maf-push "[1, 2, 3, 6]"))
  (progn (goto-char (point-max))
         (let ((calc-prefer-frac t)) (execute-kbd-macro (kbd "v O /"))) nil)
  (cl-assert (equal (calc-top 1 'full)
                    (math-read-expr "[[1, 1:2, 1:3, 1:6], [3, 3:2, 1, 1:2],
                                      [9, 9:2, 3, 3:2]]")))
  (calc-pop 1)

  ;; Reduce folds from the left; the operation is any two-argument
  ;; command on its own key.
  (progn (maf-push "[1, 2, 3, 4]") (goto-char (point-max))
         (execute-kbd-macro (kbd "v R +")) nil)
  (cl-assert (= (calc-top 1 'full) 10))
  (calc-pop 1)

  ;; A multi-key command answers too — the whole sequence is read, so
  ;; the operation space is every stamped command, not a fixed table.
  (progn (maf-push "[3, 9, 2]") (goto-char (point-max))
         (execute-kbd-macro (kbd "v R f x")) nil)
  (cl-assert (= (calc-top 1 'full) 9))
  (calc-pop 1)

  ;; Inverse folds from the right: 1 - (2 - (3 - 4)).
  (progn (maf-push "[1, 2, 3, 4]") (goto-char (point-max))
         (execute-kbd-macro (kbd "I v R -")) nil)
  (cl-assert (= (calc-top 1 'full) -2))
  (calc-pop 1)

  ;; Symbolic operands stay symbolic.
  (progn (maf-push "[a, b, c]") (goto-char (point-max))
         (execute-kbd-macro (kbd "v R +")) nil)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "a + b + c"))
  (calc-pop 1)

  ;; Accumulate keeps the running results, and reverses under I.
  (progn (maf-push "[1, 2, 3, 4]") (goto-char (point-max))
         (execute-kbd-macro (kbd "v U +")) nil)
  (cl-assert (equal (calc-top 1 'full) (math-read-expr "[1, 3, 6, 10]")))
  (calc-pop 1)
  (progn (maf-push "[1, 2, 3, 4]") (goto-char (point-max))
         (execute-kbd-macro (kbd "I v U -")) nil)
  (cl-assert (equal (calc-top 1 'full) (math-read-expr "[-2, 3, -1, 4]")))
  (calc-pop 1)

  ;; Apply spreads the elements as the operation's arguments.
  (progn (maf-push "[3, 5]") (goto-char (point-max))
         (execute-kbd-macro (kbd "v A +")) nil)
  (cl-assert (= (calc-top 1 'full) 8))
  (calc-pop 1)

  ;; Inner reads two operations: the pairwise one, then the reducer.
  (progn (maf-push "[1, 2, 3]") (maf-push "[4, 5, 6]") (goto-char (point-max))
         (execute-kbd-macro (kbd "v I * +")) nil)
  (cl-assert (= (calc-top 1 'full) 32))
  (calc-pop 1)

  ;; : types the operation as a formula instead; its free variables name
  ;; the arguments in alphabetical order.
  (progn (maf-push "[1, 2, 3, 4]") (goto-char (point-max))
         (execute-kbd-macro (kbd "v R : a + 2 b RET")) nil)
  (cl-assert (= (calc-top 1 'full) 19))
  (calc-pop 1)

  ;; A key that is not an operation, or one of the wrong size, is
  ;; refused and the read tries again rather than signalling: Q is
  ;; unary, G is no operation at all, and the + after each is taken.
  (progn (maf-push "[1, 2, 3]") (goto-char (point-max))
         (execute-kbd-macro (kbd "v R Q +")) nil)
  (cl-assert (= (calc-top 1 'full) 6))
  (calc-pop 1)
  (progn (maf-push "[1, 2, 3]") (goto-char (point-max))
         (execute-kbd-macro (kbd "v R G +")) nil)
  (cl-assert (= (calc-top 1 'full) 6))
  (calc-pop 1)

  ;; The three rows that were only misdeclared, not combinators: their
  ;; calcFunc takes two operands and the row said unary.
  (progn (maf-push "[1, 2, 3]") (maf-push "[4, 5, 6]") (goto-char (point-max))
         (execute-kbd-macro (kbd "v C")) nil)
  (cl-assert (equal (calc-top 1 'full) (math-read-expr "[-3, 6, -3]")))
  (calc-pop 1)
  (progn (maf-push "5") (maf-push "3") (goto-char (point-max))
         (execute-kbd-macro (kbd "f S")) nil)
  (cl-assert (= (calc-top 1 'full) 5000))
  (calc-pop 1)

  ;; Every table row carries its operation, which is what widens the
  ;; space past calc's blessed list.
  (cl-assert (equal (get 'mafcmd-add 'maf-operation) '(calcFunc-add . 2)))
  (cl-assert (equal (get 'mafcmd-sqrt 'maf-operation) '(calcFunc-sqrt . 1)))
  (cl-assert (equal (get 'mafcmd-cross 'maf-operation) '(calcFunc-cross . 2))))
