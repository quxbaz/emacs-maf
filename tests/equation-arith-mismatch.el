;; Only = pairs with =. Whether a relation survives an operation applied to
;; both sides is operator-specific — a + b respects < on both operands,
;; a - b does not, and multiplication depends on sign — and the command
;; table has no spelling for which operators are monotone in a relation.
;; Rather than produce an unsound relation, or silently swallow the arg the
;; way the unsplit shared-arg path does, those combinations signal and leave
;; the stack untouched.

(maf-step
  (calc-push (math-read-expr "a = b"))
  (calc-push (math-read-expr "c < d"))
  (cl-assert (condition-case nil
                 (progn (call-interactively 'mafcmd-add) nil)
               (error t)))
  (cl-assert (= (calc-stack-size) 2))
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "c < d"))
  (cl-assert (string= (math-format-value (calc-top 2 'full)) "a = b"))
  (calc-pop 2)

  ;; Mismatch the other way round: an = arg against an inequality target.
  (calc-push (math-read-expr "a < b"))
  (calc-push (math-read-expr "c = d"))
  (cl-assert (condition-case nil
                 (progn (call-interactively 'mafcmd-add) nil)
               (error t)))
  (cl-assert (= (calc-stack-size) 2))
  (calc-pop 2)

  ;; Commands that consume a relation whole (:map -1) never reach the
  ;; pairing at all: a = on two equations still nests them.
  (calc-push (math-read-expr "a = b"))
  (calc-push (math-read-expr "c = d"))
  (call-interactively 'mafcmd-eq)
  (cl-assert (= (calc-stack-size) 1))
  ;; Calc prints the nesting left-associatively; the structure is
  ;; (a = b) = (c = d).
  (cl-assert (string= (math-format-value (calc-top 1 'full))
                      "a = b = (c = d)")))
