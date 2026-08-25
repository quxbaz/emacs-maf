(maf-step
  ;; --- Digit entry: e ends the entry and equates with the number ---

  ;; From a margin, the entry at point equates with the number just
  ;; typed: x with 5 typed on its line gives x = 5, in place.
  (maf-push "x")
  (progn (goto-char (point-min)) (end-of-line))
  (execute-kbd-macro (kbd "5 e"))
  (cl-assert (= (calc-stack-size) 1))
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "x = 5"))
  (calc-pop (calc-stack-size))

  ;; = is the same command from a digit entry. Calc's normal
  ;; command-key handoff ends the number and dispatches the stack alias.
  (maf-push "x")
  (progn (goto-char (point-min)) (end-of-line))
  (execute-kbd-macro (kbd "5 ="))
  (cl-assert (= (calc-stack-size) 1))
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "x = 5"))
  (calc-pop (calc-stack-size))

  ;; It is a command-key termination like the + of 1 +, so the arg push
  ;; folds into the command's undo group: one undo reverts both.
  (maf-push "x")
  (progn (goto-char (point-min)) (end-of-line))
  (execute-kbd-macro (kbd "5 e"))
  (execute-kbd-macro (kbd "U"))
  (cl-assert (= (calc-stack-size) 1))
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "x"))
  (calc-pop (calc-stack-size))

  ;; At home the top two join, the number as the right side.
  (maf-push "y")
  (goto-char (point-max))
  (execute-kbd-macro (kbd "5 e"))
  (cl-assert (= (calc-stack-size) 1))
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "y = 5"))
  (calc-pop (calc-stack-size))

  ;; Depth is no obstacle: the entry point is on equates with the
  ;; number, the entries between it and the top untouched.
  (maf-push "a") (maf-push "b") (maf-push "c")
  (progn (calc-cursor-stack-index 3) (end-of-line))
  (execute-kbd-macro (kbd "7 e"))
  (cl-assert (equal (mapcar (lambda (i) (math-format-value (calc-top i 'full)))
                            (number-sequence 1 3))
                    '("c" "b" "a = 7")))
  (calc-pop (calc-stack-size))

  ;; The subject is the whole entry, as `mafcmd-equal-to' takes it —
  ;; point inside the formula does not narrow it to a sub-formula.
  (maf-push "2 x + 1")
  (progn (goto-char (point-min)) (search-forward "x") (backward-char 1))
  (execute-kbd-macro (kbd "7 e"))
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "2 x + 1 = 7"))
  (calc-pop (calc-stack-size))

  ;; The Inverse route needs the number pushed first — calc's I flag
  ;; does not survive a digit entry (I 5 e fails as I 5 + does).
  (maf-push "x")
  (goto-char (point-max))
  (execute-kbd-macro (kbd "5 RET I e"))
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "x != 5"))
  (calc-pop (calc-stack-size))

  ;; --- Where e is still calc's own, e-notation is untouched ---

  ;; In a radix-prefixed entry it is that radix's digit: 16#3e is 62.
  (goto-char (point-max))
  (execute-kbd-macro (kbd "1 6 # 3 e RET"))
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "62"))
  (calc-pop (calc-stack-size))

  ;; And for a radix that has no E digit, the exponent marker: 8#1e2 is
  ;; 1 x 8^2.
  (goto-char (point-max))
  (execute-kbd-macro (kbd "8 # 1 e 2 RET"))
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "64."))
  (calc-pop (calc-stack-size))

  ;; While an incomplete object is being entered there is nothing to
  ;; equate, so the element keeps its exponent: 2e3 is 2000.
  (goto-char (point-max))
  (execute-kbd-macro (kbd "[ 1 ; 2 e 3 ] ]"))
  (cl-assert (equal (calc-top 1 'full) '(vec (vec 1) (vec (float 2 3)))))
  (calc-pop (calc-stack-size))

  ;; And with maf-mode off: `calc-digit-map' is calc's own map, so the
  ;; key fires in every calc digit entry, but with no maf-mode there is
  ;; no command to equate with — e is the exponent it is in plain calc,
  ;; so 1 e 6 RET is the single entry 1e6, not 1 and 1e6.
  (unwind-protect
      (progn (maf-mode -1)
             (goto-char (point-max))
             (execute-kbd-macro (kbd "1 e 6 RET")))
    (maf-mode 1))
  (cl-assert maf-mode)
  (cl-assert (= (calc-stack-size) 1))
  (cl-assert (equal (calc-top 1 'full) '(float 1 6)))
  (calc-pop (calc-stack-size)))
