(maf-step
  ;; I S at a subexpr applies arcsin contextually and consumes the flag.
  (calc-push '(* 2 (var x var-x)))
  (progn (goto-char (point-min)) (search-forward "x") (backward-char 1))
  (calc-inverse nil)
  (call-interactively 'mafcmd-sin)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "2 arcsin(x)"))
  (cl-assert (not (or calc-inverse-flag calc-hyperbolic-flag)))
  (calc-pop 1)
  ;; I H S -> arcsinh.
  (calc-push '(* 2 (var x var-x)))
  (progn (goto-char (point-min)) (search-forward "x") (backward-char 1))
  (progn (calc-inverse nil) (calc-hyperbolic nil))
  (call-interactively 'mafcmd-sin)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "2 arcsinh(x)"))
  (calc-pop 1)
  ;; I ^ -> nroot, a binary variant: takes its arg from the stack top.
  (calc-push '(var y var-y))
  (calc-push 3)
  (progn (goto-char (point-min)) (search-forward "y") (backward-char 1))
  (calc-inverse nil)
  (call-interactively 'mafcmd-pow)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "y^1:3"))
  (calc-pop (calc-stack-size))
  ;; I H ^ has no variant: user-error, flags consumed, stack untouched.
  (calc-push '(var y var-y))
  (calc-push 3)
  (progn (calc-inverse nil) (calc-hyperbolic nil))
  (cl-assert (eq 'signaled
                 (condition-case nil
                     (call-interactively 'mafcmd-pow)
                   (user-error 'signaled))))
  (cl-assert (not (or calc-inverse-flag calc-hyperbolic-flag)))
  (cl-assert (= (calc-stack-size) 2)))
