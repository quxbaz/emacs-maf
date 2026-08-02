(maf-step
  ;; --- Digit entry: ; is the fraction colon ---

  ;; The plain case: 3 ; 4 enters the fraction 3:4.
  (goto-char (point-max))
  (execute-kbd-macro (kbd "3 ; 4 RET"))
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "3:4"))
  (calc-pop (calc-stack-size))

  ;; It is calc's own colon, not a bare insertion, so calc's mixed-number
  ;; form still parses: 1:2:3 is 1 + 2/3.
  (goto-char (point-max))
  (execute-kbd-macro (kbd "1 ; 2 ; 3 RET"))
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "5:3"))
  (calc-pop (calc-stack-size))

  ;; And calc's leading-1 rule applies: with only a sign typed, the
  ;; colon supplies the numerator itself.
  (goto-char (point-max))
  (execute-kbd-macro (kbd "_ ; 2 RET"))
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "-1:2"))
  (calc-pop (calc-stack-size))

  ;; A contextual entry commits the fraction the same way : does: on a
  ;; numeric leaf, SPC replaces it.
  (maf-push "2.5 x")
  (progn (goto-char (point-min)) (search-forward "2.5") (backward-char 1))
  (execute-kbd-macro (kbd "1 ; 3 SPC"))
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "1:3 x"))
  (calc-pop (calc-stack-size))

  ;; The stack keeps its own ; (calc's incomplete-object separator): the
  ;; alias lives in the entry minibuffer, not in calc-mode-map.
  (progn (goto-char (point-max)) nil)
  (cl-assert (eq (key-binding (kbd ";")) 'calc-semi))

  ;; And the alias steps aside for it: with an incomplete object on the
  ;; stack, the ; typed from inside digit entry is the matrix row
  ;; separator it is in calc, not a colon inserted into the number.
  (execute-kbd-macro (kbd "[ 1 ; 2 ] ]"))
  (cl-assert (string= (math-format-value (calc-top 1 'full))
                      "[ [ 1 ]\n  [ 2 ] ]"))
  (calc-pop (calc-stack-size))

  ;; --- maf-edit: ; is the fraction colon there too ---

  (maf-push "a")
  (progn (calc-cursor-stack-index 1) (end-of-line) nil)
  (call-interactively 'maf-edit)
  (progn (execute-kbd-macro "+3;4") nil)
  (cl-assert (string= (buffer-substring-no-properties
                       (line-beginning-position) (line-end-position))
                      "1*  a+3:4"))
  (call-interactively 'maf-edit-commit)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "a + 3:4"))
  (calc-pop (calc-stack-size))

  ;; The displaced semicolon is on M-; — matrix notation stays typeable.
  (call-interactively 'maf-edit-add-entry-below)
  (progn (execute-kbd-macro (kbd "[ 1 , 2 M-; 3 , 4 ]")) nil)
  (call-interactively 'maf-edit-commit)
  (cl-assert (string= (math-format-value (calc-top 1 'full))
                      "[ [ 1, 2 ]\n  [ 3, 4 ] ]"))
  (calc-pop (calc-stack-size)))
