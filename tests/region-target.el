;; The maf-step harness deactivates the mark around every form, so each
;; case sets its region and fires the command in a single form — as in
;; real use, where the region exists at the moment the command runs.

(maf-step
  ;; A run calc cannot select: factor the trailing terms of a sum.
  (maf-push "x^2 (x+3) + 4 x + 12")
  (progn (calc-cursor-stack-index 1)
         (search-forward "4 x + 12" (line-end-position))
         (goto-char (match-beginning 0))
         (push-mark (match-end 0) t t)
         (call-interactively 'mafcmd-factor-gcd))
  (cl-assert (string= (math-format-value (calc-top 1 'full))
                      "x^2 (x + 3) + 4 (x + 3)"))
  ;; Resolving consumed the gesture.
  (cl-assert (not (region-active-p)))
  (calc-pop (calc-stack-size))

  ;; Signed run: covered terms keep their chain signs, so the splice
  ;; preserves the entry's value; the display shows the command's
  ;; literal, unnormalized output.
  (maf-push "a - 4 x - 12")
  (progn (calc-cursor-stack-index 1)
         (search-forward "4 x - 12" (line-end-position))
         (goto-char (match-beginning 0))
         (push-mark (match-end 0) t t)
         (call-interactively 'mafcmd-factor-gcd))
  (cl-assert (string= (math-format-value (calc-top 1 'full))
                      "a + -4 (x + 3)"))
  (calc-pop (calc-stack-size))

  ;; Product run: a same-kind result rejoins the chain as terms, not
  ;; as a parenthesized unit.
  (maf-push "a b c")
  (progn (calc-cursor-stack-index 1)
         (search-forward "a b" (line-end-position))
         (goto-char (match-beginning 0))
         (push-mark (match-end 0) t t)
         (call-interactively 'mafcmd-commute))
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "b a c"))
  (calc-pop (calc-stack-size))

  ;; A region covering a whole sub-formula collapses to the subexpr
  ;; target on that node. (The extra parens around the spliced product
  ;; are the subexpr path's own rendering — point on the + gives the
  ;; same — not a region artifact.)
  (maf-push "(6 x + 12) y + 1")
  (progn (calc-cursor-stack-index 1)
         (search-forward "6 x + 12" (line-end-position))
         (goto-char (match-beginning 0))
         (push-mark (match-end 0) t t)
         (call-interactively 'mafcmd-factor-gcd))
  (cl-assert (string= (math-format-value (calc-top 1 'full))
                      "(6 (x + 2)) y + 1"))
  (calc-pop (calc-stack-size))

  ;; A region spanning two entries is rejected, stack untouched.
  (maf-push "a + b")
  (maf-push "c + d")
  (cl-assert (equal (condition-case e
                        (progn (calc-cursor-stack-index 2)
                               (push-mark (point) t t)
                               (calc-cursor-stack-index 1)
                               (end-of-line)
                               (call-interactively 'mafcmd-factor-gcd))
                      (error (cadr e)))
                    "Region spans multiple stack entries"))
  (cl-assert (= (calc-stack-size) 2))
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "c + d"))
  (calc-pop (calc-stack-size)))
