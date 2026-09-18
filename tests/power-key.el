;; The power has two keys on the stack: ^, and : beside it. What is
;; checked here is that both reach the same command and do the same
;; thing to the same target, driven by the real keys; W stays the
;; square. The colon's other half — maf-digit-pow, the same key inside
;; digit entry, and the fraction colon that moved to `;' to make room
;; — is digit-pow.el's. A step passes when it raises no error.

(maf-step
  (cl-assert (eq (key-binding (kbd ":")) 'mafcmd-pow))
  (cl-assert (eq (key-binding (kbd "^")) 'mafcmd-pow))
  (cl-assert (eq (key-binding (kbd "W")) 'mafcmd-sqr))

  ;; The same pair, raised by either key. Driven by the real keys, so
  ;; a colon reaching calc-fdiv would show up here as a quotient
  ;; rather than a power.
  (calc-wrapper (maf-push "x + 1"))
  (calc-wrapper (maf-push "2"))
  (progn (goto-char (point-max)) nil)
  (progn (execute-kbd-macro ":") nil)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "(x + 1)^2"))
  (cl-assert (= (calc-stack-size) 1))
  (calc-pop 1)

  (calc-wrapper (maf-push "x + 1"))
  (calc-wrapper (maf-push "2"))
  (progn (goto-char (point-max)) nil)
  (progn (execute-kbd-macro "^") nil)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "(x + 1)^2"))
  (calc-pop 1)

  ;; Contextual through the colon as through ^: point on a sub-formula
  ;; raises that, not the entry around it, with the top as exponent.
  (calc-wrapper (maf-push "y + sin(x)"))
  (calc-wrapper (maf-push "2"))
  (progn (calc-cursor-stack-index 2) (beginning-of-line)
         (search-forward "sin") (backward-char 2) nil)
  (progn (execute-kbd-macro ":") nil)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "y + sin(x)^2"))
  (calc-pop 1)

  (calc-wrapper (maf-push "y + sin(x)"))
  (calc-wrapper (maf-push "2"))
  (progn (calc-cursor-stack-index 2) (beginning-of-line)
         (search-forward "sin") (backward-char 2) nil)
  (progn (execute-kbd-macro "^") nil)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "y + sin(x)^2"))
  (calc-pop 1))
