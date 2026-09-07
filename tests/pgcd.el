;;; Tests for `a g' (mafcmd-pgcd) -- polynomials that share no variable.
;;
;; Calc's `math-poly-gcd' has a typo in its fallback branch for two
;; polynomials with no variable in common: it takes gcd(pcont(u),
;; pcont(u)) instead of gcd(pcont(u), pcont(v)), so the answer is the
;; first operand's own numeric content and depends on stack order --
;; 7 y over 5 x gave 7, 5 x over 7 y gave 5. `maf--poly-gcd-disjoint'
;; (src/math.el) advises that branch away. These cases pin the
;; corrected answers for pgcd itself, the branches the advice must
;; leave alone, and the commands that build on the GCD (nrat, poly-lcm,
;; factor-gcd).

(maf-step
  ;; Regression: coprime contents give 1, whichever operand is on top.
  ;; Before the fix these gave 7 and 5 respectively.
  (maf-push "7 y")
  (maf-push "5 x")
  (call-interactively 'mafcmd-pgcd)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "1"))
  (calc-pop (calc-stack-size))

  (maf-push "5 x")
  (maf-push "7 y")
  (call-interactively 'mafcmd-pgcd)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "1"))
  (calc-pop (calc-stack-size))

  ;; Shared numeric content across different variables: the gcd of
  ;; the two contents, not the first one's (was 6).
  (maf-push "6 y")
  (maf-push "4 x")
  (call-interactively 'mafcmd-pgcd)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "2"))
  (calc-pop (calc-stack-size))

  ;; Same with polynomials rather than monomials: the contents are 6
  ;; and 4 (was 6), and 3 and 3.
  (maf-push "6 y + 12")
  (maf-push "4 x - 8")
  (call-interactively 'mafcmd-pgcd)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "2"))
  (calc-pop (calc-stack-size))

  (maf-push "3 x + 6")
  (maf-push "3 y + 9")
  (call-interactively 'mafcmd-pgcd)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "3"))
  (calc-pop (calc-stack-size))

  ;; Regression: the multivariate overshoot was the same typo one
  ;; level down -- the coefficients 10 y and 15 z share no variable.
  ;; pgcd(10 x y, 15 x z) gave 10 x; the true GCD is 5 x.
  (maf-push "10 x y")
  (maf-push "15 x z")
  (call-interactively 'mafcmd-pgcd)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "5 x"))
  (calc-pop (calc-stack-size))

  (maf-push "6 x y")
  (maf-push "4 y z")
  (call-interactively 'mafcmd-pgcd)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "2 y"))
  (calc-pop (calc-stack-size))

  ;; Untouched branches: a constant operand goes through calc's own
  ;; content path, and a shared variable runs the polynomial
  ;; algorithm.
  (maf-push "5 x")
  (maf-push "7")
  (call-interactively 'mafcmd-pgcd)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "1"))
  (calc-pop (calc-stack-size))

  (maf-push "6 x")
  (maf-push "4")
  (call-interactively 'mafcmd-pgcd)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "2"))
  (calc-pop (calc-stack-size))

  (maf-push "x^2 - 1")
  (maf-push "x - 1")
  (call-interactively 'mafcmd-pgcd)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "x - 1"))
  (calc-pop (calc-stack-size))

  (maf-push "x^2 - y^2")
  (maf-push "x - y")
  (call-interactively 'mafcmd-pgcd)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "x - y"))
  (calc-pop (calc-stack-size))

  ;; nrat builds on the same GCD: a ratio of disjoint monomials keeps
  ;; its coefficients (as the fraction 7:5 out front, nrat's form)
  ;; instead of cancelling a phantom 7 into y / (5:7 x).
  (maf-push "7 y / (5 x)")
  (call-interactively 'mafcmd-nrat)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "7:5 y / x"))
  (calc-pop (calc-stack-size))

  ;; poly-lcm's yardstick is a b / pgcd(a, b): with the GCD right, the
  ;; LCM of disjoint monomials is their product over the content gcd.
  (maf-push "7 y")
  (maf-push "5 x")
  (call-interactively 'mafcmd-poly-lcm)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "35 y x"))
  (calc-pop (calc-stack-size))

  (maf-push "6 y")
  (maf-push "4 x")
  (call-interactively 'mafcmd-poly-lcm)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "12 y x"))
  (calc-pop (calc-stack-size))

  ;; factor-gcd on disjoint terms: nothing to pull out, and it says so.
  (maf-push "5 x + 7 y")
  (let ((inhibit-message nil))
    (call-interactively 'mafcmd-factor-gcd)
    (cl-assert (equal (current-message) "No common factor to pull out")))
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "5 x + 7 y"))
  (calc-pop (calc-stack-size))

  (maf-push "6 y + 4 x")
  (call-interactively 'mafcmd-factor-gcd)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "2 (3 y + 2 x)"))
  (calc-pop (calc-stack-size)))
