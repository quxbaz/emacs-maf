;; The square has two keys on the stack: W, and : beside it. What is
;; checked here is that both reach the same command and do the same
;; thing to the same target, driven by the real keys. The colon's other
;; half — maf-digit-sqr, the same key inside digit entry, and the
;; fraction colon that moved to `;' to make room — is digit-sqr.el's.
;; A step passes when it raises no error.

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

  (calc-wrapper (maf-push "y + sin(x)"))
  (progn (goto-char (point-min)) (search-forward "sin") (backward-char 2) nil)
  (progn (execute-kbd-macro "W") nil)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "y + sin(x)^2"))
  (calc-pop 1))
