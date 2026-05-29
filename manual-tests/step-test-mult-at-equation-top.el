;; Edge case: a binary command on a relation that IS the top entry. The arg
;; would have to come from the relation itself, so resolve must reject it —
;; the test passes only if maf-mult signals an error.

(maf-defcmd maf-mult (expr arg commit)
  "Multiplication command."
  :arity binary
  :prefix "mult"
  (commit (calcFunc-mul expr arg)))

(maf-step
  (calc-push '(calcFunc-eq (var x var-x) 5))
  (goto-char 0)
  (cl-assert (condition-case nil
                 (progn (call-interactively 'maf-mult) nil)
               (error t))))
