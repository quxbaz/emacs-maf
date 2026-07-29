;; Equation arithmetic: when both the target and the arg are equations, the
;; two pair up side by side — the arg's LHS joins the target's LHS, its RHS
;; the RHS. Without the split each side would take the whole relation as a
;; term (a + (c = d) = b + (c = d)), which calc's algebraic simplification
;; then cancels back to the original, silently swallowing the arg.
;;
;; The pairing lives in resolve, not in the commands, so every binary
;; contextual command gets it — the four arithmetic keys below are just the
;; ones with an obvious reading.

(maf-step
  (calc-push (math-read-expr "a = b"))
  (calc-push (math-read-expr "c = d"))
  (call-interactively 'mafcmd-add)
  (cl-assert (= (calc-stack-size) 1))
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "a + c = b + d"))
  (calc-pop 1)

  ;; Target minus arg, matching the operand order everywhere else: the entry
  ;; below the top is the target, the top is the arg.
  (calc-push (math-read-expr "a = b"))
  (calc-push (math-read-expr "c = d"))
  (call-interactively 'mafcmd-sub)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "a - c = b - d"))
  (calc-pop 1)

  (calc-push (math-read-expr "a = b"))
  (calc-push (math-read-expr "c = d"))
  (call-interactively 'mafcmd-mul)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "a c = b d"))
  (calc-pop 1)

  (calc-push (math-read-expr "a = b"))
  (calc-push (math-read-expr "c = d"))
  (call-interactively 'mafcmd-div)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "a / c = b / d"))
  (calc-pop 1)

  ;; A scalar arg is still shared across both sides, unsplit.
  (calc-push (math-read-expr "x = 5"))
  (calc-push 2)
  (call-interactively 'mafcmd-mul)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "2 x = 10")))
