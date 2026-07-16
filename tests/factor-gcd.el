(maf-step
  ;; Basic: pull the GCD out of a sum.
  (maf-push "6 x + 12")
  (call-interactively 'mafcmd-factor-gcd)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "6 (x + 2)"))
  (calc-pop (calc-stack-size))

  ;; Subtraction node: 6 x - 12 is a (- ...) formula, not a (+ ...);
  ;; the term walk must flatten it too.
  (maf-push "6 x - 12")
  (call-interactively 'mafcmd-factor-gcd)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "6 (x - 2)"))
  (calc-pop (calc-stack-size))

  ;; Negative leading term: the negated GCD is pulled out.
  (maf-push "-3 x + 3")
  (call-interactively 'mafcmd-factor-gcd)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "-3 (x - 1)"))
  (calc-pop (calc-stack-size))

  ;; Nothing to pull out: coprime terms and single terms pass through.
  (maf-push "3 x + 7")
  (call-interactively 'mafcmd-factor-gcd)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "3 x + 7"))
  (maf-push "6 x")
  (call-interactively 'mafcmd-factor-gcd)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "6 x"))
  (calc-pop (calc-stack-size))

  ;; Multivariate: calc's pgcd overshoots pairwise (pgcd(10xy, 15xz)
  ;; gives 10x); the fixpoint reduce must converge on 5x.
  (maf-push "10 x y + 15 x z")
  (call-interactively 'mafcmd-factor-gcd)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "(5 x)*(3 z + 2 y)"))
  (calc-pop (calc-stack-size))

  ;; Exact ratios: computing with fractions preferred keeps the
  ;; quotient exact instead of detouring through float noise.
  (maf-push "(3/4) x + (3/2)")
  (call-interactively 'mafcmd-factor-gcd)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "3:4 (x + 2)"))
  (calc-pop (calc-stack-size))

  ;; Float coefficients: pgcd rejects them; pass through unchanged
  ;; instead of erroring (matters for equation sides).
  (maf-push "2.5 x + 5.0")
  (call-interactively 'mafcmd-factor-gcd)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "2.5 x + 5."))
  (calc-pop (calc-stack-size))

  ;; Equation: each side factors independently.
  (maf-push "6 x + 12 = 18 y + 6")
  (call-interactively 'mafcmd-factor-gcd)
  (cl-assert (string= (math-format-value (calc-top 1 'full))
                      "6 (x + 2) = 6 (3 y + 1)"))
  (calc-pop (calc-stack-size))

  ;; Subexpr: only the sub-formula under point factors. Point was on
  ;; the sum's operator, so it anchors to the operator of the node that
  ;; replaced it — the factored product's juxtaposition space.
  (maf-push "5 (6 x - 12)")
  (calc-push 9)
  (progn (goto-char (point-min)) (search-forward "x -") (backward-char 1))
  (call-interactively 'mafcmd-factor-gcd)
  (cl-assert (string= (math-format-value (calc-top 2 'full)) "5 6 (x - 2)"))
  (cl-assert (looking-at-p " (x - 2)"))
  (cl-assert (= (calc-stack-size) 2)))
