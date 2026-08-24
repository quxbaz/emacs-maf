;; The square has two keys on the stack: W, and : beside it. The second
;; shadows calc-fdiv, so what is checked here is that both keys reach
;; the same command and do the same thing to the same target, and that
;; the fraction the colon used to divide is still typed the way it is
;; written — inside a number, where digit entry keeps calc's own colon
;; handling. A step passes when it raises no error.

(maf-step
  (cl-assert (eq (key-binding (kbd ":")) 'mafcmd-sqr))
  (cl-assert (eq (key-binding (kbd "W")) 'mafcmd-sqr))

  ;; The same entry, squared by either key. Driven by the real keys, so
  ;; a colon reaching calc-fdiv would show up here as a stack error
  ;; rather than a square.
  (calc-wrapper (maf-push "x + 1"))
  (progn (goto-char (point-max)) nil)
  (progn (execute-kbd-macro ":") nil)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "(x + 1)^2"))
  (calc-pop 1)

  (calc-wrapper (maf-push "x + 1"))
  (progn (goto-char (point-max)) nil)
  (progn (execute-kbd-macro "W") nil)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "(x + 1)^2"))
  (calc-pop 1)

  ;; Contextual through the colon as through W: point on a sub-formula
  ;; squares that, not the entry around it.
  (calc-wrapper (maf-push "y + sin(x)"))
  (progn (goto-char (point-min)) (search-forward "sin") (backward-char 2) nil)
  (progn (execute-kbd-macro ":") nil)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "y + sin(x)^2"))
  (calc-pop 1)

  ;; The fraction is typed inside a number, on ; there
  ;; (`maf-digit-colon'), and the stack key does not reach into that.
  (progn (goto-char (point-max)) nil)
  (progn (execute-kbd-macro "3;4") nil)
  (progn (execute-kbd-macro (kbd "RET")) nil)
  (cl-assert (equal (calc-top 1 'full) '(frac 3 4)))
  (calc-pop 1)

  ;; A literal colon mid-number is calc's own too: the maf binding
  ;; lives in the stack map, not in calc-digit-map, so once a digit has
  ;; started the entry the colon is calc's again.
  (progn (goto-char (point-max)) nil)
  (progn (execute-kbd-macro "5:8") nil)
  (progn (execute-kbd-macro (kbd "RET")) nil)
  (cl-assert (equal (calc-top 1 'full) '(frac 5 8)))
  (calc-pop 1)

  ;; The mixed number keeps both of its colons.
  (progn (goto-char (point-max)) nil)
  (progn (execute-kbd-macro "1:2:3") nil)
  (progn (execute-kbd-macro (kbd "RET")) nil)
  (cl-assert (equal (calc-top 1 'full) '(frac 5 3)))
  (calc-pop 1))
