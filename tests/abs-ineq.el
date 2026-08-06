;; Port verification for mafcmd-abs-ineq (a k): split an absolute-value
;; inequality into a compound one — a band (&&) below a bound, two tails
;; (||) above it — each half solved for the body's variable.

(maf-step
  ;; Basic band: a magnitude below a bound, the variable between them.
  (maf-push "abs(x) < 5")
  (goto-char (point-max))
  (call-interactively 'mafcmd-abs-ineq)
  (cl-assert (string= (math-format-value (calc-top 1 'full))
                      "-5 < x && x < 5"))
  (cl-assert (= (calc-stack-size) 1))
  (calc-pop (calc-stack-size))

  ;; Basic tails: a magnitude above a bound, the variable leading each.
  (maf-push "abs(x) > 5")
  (goto-char (point-max))
  (call-interactively 'mafcmd-abs-ineq)
  (cl-assert (string= (math-format-value (calc-top 1 'full))
                      "x < -5 || x > 5"))
  (calc-pop (calc-stack-size))

  ;; A closed bound stays closed on both halves.
  (maf-push "abs(x) <= 5")
  (goto-char (point-max))
  (call-interactively 'mafcmd-abs-ineq)
  (cl-assert (string= (math-format-value (calc-top 1 'full))
                      "-5 <= x && x <= 5"))
  (calc-pop (calc-stack-size))

  (maf-push "abs(x) >= 5")
  (goto-char (point-max))
  (call-interactively 'mafcmd-abs-ineq)
  (cl-assert (string= (math-format-value (calc-top 1 'full))
                      "x <= -5 || x >= 5"))
  (calc-pop (calc-stack-size))

  ;; A symbolic bound negates symbolically.
  (maf-push "abs(x) < b")
  (goto-char (point-max))
  (call-interactively 'mafcmd-abs-ineq)
  (cl-assert (string= (math-format-value (calc-top 1 'full))
                      "-b < x && x < b"))
  (calc-pop (calc-stack-size))

  (maf-push "abs(x) >= b")
  (goto-char (point-max))
  (call-interactively 'mafcmd-abs-ineq)
  (cl-assert (string= (math-format-value (calc-top 1 'full))
                      "x <= -b || x >= b"))
  (calc-pop (calc-stack-size))

  ;; The abs on the right: the same bound read from the other side, so
  ;; the relation is flipped before it is split.
  (maf-push "5 > abs(x)")
  (goto-char (point-max))
  (call-interactively 'mafcmd-abs-ineq)
  (cl-assert (string= (math-format-value (calc-top 1 'full))
                      "-5 < x && x < 5"))
  (calc-pop (calc-stack-size))

  (maf-push "5 <= abs(x)")
  (goto-char (point-max))
  (call-interactively 'mafcmd-abs-ineq)
  (cl-assert (string= (math-format-value (calc-top 1 'full))
                      "x <= -5 || x >= 5"))
  (calc-pop (calc-stack-size))

  ;; A coefficient inside the abs is divided out exactly — 5:2, not 2.5.
  (maf-push "abs(2 x) < 5")
  (goto-char (point-max))
  (call-interactively 'mafcmd-abs-ineq)
  (cl-assert (string= (math-format-value (calc-top 1 'full))
                      "-5:2 < x && x < 5:2"))
  (calc-pop (calc-stack-size))

  ;; A negative coefficient turns both halves; the band still reads
  ;; lower < x && x < upper rather than backwards.
  (maf-push "abs(-2 x) < 5")
  (goto-char (point-max))
  (call-interactively 'mafcmd-abs-ineq)
  (cl-assert (string= (math-format-value (calc-top 1 'full))
                      "-5:2 < x && x < 5:2"))
  (calc-pop (calc-stack-size))

  ;; The same for the tails: x leads both, the upper bound first.
  (maf-push "abs(-2 x) > 5")
  (goto-char (point-max))
  (call-interactively 'mafcmd-abs-ineq)
  (cl-assert (string= (math-format-value (calc-top 1 'full))
                      "x < -5:2 || x > 5:2"))
  (calc-pop (calc-stack-size))

  ;; A shifted body: both bounds move with it.
  (maf-push "abs(x - 1) <= 3")
  (goto-char (point-max))
  (call-interactively 'mafcmd-abs-ineq)
  (cl-assert (string= (math-format-value (calc-top 1 'full))
                      "-2 <= x && x <= 4"))
  (calc-pop (calc-stack-size))

  ;; A parameter beside the variable: x is solved for, y carries through.
  (maf-push "abs(x + y) < 5")
  (goto-char (point-max))
  (call-interactively 'mafcmd-abs-ineq)
  (cl-assert (string= (math-format-value (calc-top 1 'full))
                      "-y - 5 < x && x < -y + 5"))
  (calc-pop (calc-stack-size))

  ;; A constant var is not a variable to solve for: pi is a coefficient,
  ;; x the unknown.
  (maf-push "abs(pi x) < 5")
  (goto-char (point-max))
  (call-interactively 'mafcmd-abs-ineq)
  (cl-assert (string= (math-format-value (calc-top 1 'full))
                      "-5 / pi < x && x < 5 / pi"))
  (calc-pop (calc-stack-size))

  ;; A body calc cannot isolate the variable in: the split still
  ;; happens, each half kept as written rather than turned into the !=
  ;; boundary calc falls back to.
  (maf-push "abs(x^2) < 5")
  (goto-char (point-max))
  (call-interactively 'mafcmd-abs-ineq)
  (cl-assert (string= (math-format-value (calc-top 1 'full))
                      "-5 < x^2 && x^2 < 5"))
  (calc-pop (calc-stack-size))

  ;; No variable at all: the split is still the equivalent statement.
  (maf-push "abs(3) < 5")
  (goto-char (point-max))
  (call-interactively 'mafcmd-abs-ineq)
  (cl-assert (string= (math-format-value (calc-top 1 'full))
                      "-5 < 3 && 3 < 5"))
  (calc-pop (calc-stack-size))

  ;; An abs on both sides: the left one is the body, the right an
  ;; ordinary bound.
  (maf-push "abs(x) < abs(y)")
  (goto-char (point-max))
  (call-interactively 'mafcmd-abs-ineq)
  (cl-assert (string= (math-format-value (calc-top 1 'full))
                      "-abs(y) < x && x < abs(y)"))
  (calc-pop (calc-stack-size))

  ;; Point inside the abs inequality widens out to the relation, rather
  ;; than acting on the body it names.
  (maf-push "abs(x - 1) <= 3")
  (progn (goto-char (point-min))
         (search-forward "x" (line-end-position)))
  (call-interactively 'mafcmd-abs-ineq)
  (cl-assert (string= (math-format-value (calc-top 1 'full))
                      "-2 <= x && x <= 4"))
  (calc-pop (calc-stack-size))

  ;; Nested in a compound: widening stops at the innermost abs
  ;; inequality, so the other conjunct is untouched. The band lands as
  ;; one && node inside the outer one — calc prints the nesting flat,
  ;; so the structure is what the assertion checks.
  (maf-push "abs(x) < 5 && y > 0")
  (progn (goto-char (point-min))
         (search-forward "abs" (line-end-position)))
  (call-interactively 'mafcmd-abs-ineq)
  (cl-assert (string= (math-format-value (calc-top 1 'full))
                      "-5 < x && x < 5 && y > 0"))
  (cl-assert (eq (car-safe (nth 1 (maf--strip-encasing (calc-top 1 'full))))
                 'calcFunc-land))
  (cl-assert (equal (nth 2 (maf--strip-encasing (calc-top 1 'full)))
                    (math-read-expr "y > 0")))
  (calc-pop (calc-stack-size))

  ;; Nothing to split commits unchanged rather than signaling.
  (maf-push "abs(x) = 5")
  (goto-char (point-max))
  (call-interactively 'mafcmd-abs-ineq)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "abs(x) = 5"))
  (calc-pop (calc-stack-size))

  ;; An abs under a coefficient has to be divided out first; this
  ;; command does not do that, so it leaves the entry alone.
  (maf-push "2 abs(x) < 5")
  (goto-char (point-max))
  (call-interactively 'mafcmd-abs-ineq)
  (cl-assert (string= (math-format-value (calc-top 1 'full))
                      "2 abs(x) < 5"))
  (calc-pop (calc-stack-size))

  ;; An ordinary inequality, no abs anywhere: unchanged, and the
  ;; relation is not mapped side by side either.
  (maf-push "x < 5")
  (goto-char (point-max))
  (call-interactively 'mafcmd-abs-ineq)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "x < 5"))
  (cl-assert (= (calc-stack-size) 1))
  (calc-pop (calc-stack-size)))
