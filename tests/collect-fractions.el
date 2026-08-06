;; mafcmd-collect-fractions (l t): the resolved expression's additive
;; terms combined over their least common denominator, committed as a
;; single undistributed fraction. Covers the denominator shapes calc
;; produces — literal ratios, divisions, factors of a product,
;; negative powers — and the targets home, equation, selection and a
;; sub-formula at point, widening included.

(maf-step
  ;; Basic: like denominators, numerators added.
  (maf-push "x/3 + 2/3")
  (call-interactively 'mafcmd-collect-fractions)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "(x + 2) / 3"))
  (cl-assert (= (calc-stack-size) 1))
  (calc-pop (calc-stack-size))

  ;; Unlike denominators: the LCD, not the product.
  (maf-push "x/2 + x/3")
  (call-interactively 'mafcmd-collect-fractions)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "5 x / 6"))
  (calc-pop (calc-stack-size))

  ;; Three terms, one subtracted: the sign rides with its numerator.
  (maf-push "a/6 + b/3 - c/2")
  (call-interactively 'mafcmd-collect-fractions)
  (cl-assert (string= (math-format-value (calc-top 1 'full))
                      "(a + 2 b - 3 c) / 6"))
  (calc-pop (calc-stack-size))

  ;; A constant term joins the fraction (calc stores 1:2 as a literal
  ;; fraction, not a division).
  (maf-push "pi/2 - 1:2")
  (call-interactively 'mafcmd-collect-fractions)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "(pi - 1) / 2"))
  (calc-pop (calc-stack-size))

  ;; A term with no denominator at all is scaled up like the rest.
  (maf-push "x/2 + 1")
  (call-interactively 'mafcmd-collect-fractions)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "(x + 2) / 2"))
  (calc-pop (calc-stack-size))

  ;; Unary negation in front of a fraction.
  (maf-push "-(x/2) + 1/3")
  (call-interactively 'mafcmd-collect-fractions)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "(-3 x + 2) / 6"))
  (calc-pop (calc-stack-size))

  ;; A denominator buried in a product.
  (maf-push "2 (x/3) + 1/2")
  (call-interactively 'mafcmd-collect-fractions)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "(4 x + 3) / 6"))
  (calc-pop (calc-stack-size))

  ;;; Stacked division: a single term flattens.

  ;; A literal ratio over a power: the ratio's denominator joins the
  ;; divisor instead of stacking a second division.
  (maf-push "8:3 / x^2")
  (call-interactively 'mafcmd-collect-fractions)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "8 / (3 x^2)"))
  (calc-pop (calc-stack-size))

  ;; The same over a binomial power.
  (maf-push "8:3 / (x + 1)^2")
  (call-interactively 'mafcmd-collect-fractions)
  (cl-assert (string= (math-format-value (calc-top 1 'full))
                      "8 / (3 (x + 1)^2)"))
  (calc-pop (calc-stack-size))

  ;; Division by a fraction flattens from both sides.
  (maf-push "(x/2) / (y/3)")
  (call-interactively 'mafcmd-collect-fractions)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "3 x / (2 y)"))
  (calc-pop (calc-stack-size))

  ;;; Symbolic denominators.

  ;; Distinct variables: the LCD is their product.
  (maf-push "1/x + 1/y")
  (call-interactively 'mafcmd-collect-fractions)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "(y + x) / (x y)"))
  (calc-pop (calc-stack-size))

  ;; Mixed numeric and symbolic denominators.
  (maf-push "x/2 + 3/a^3")
  (call-interactively 'mafcmd-collect-fractions)
  (cl-assert (string= (math-format-value (calc-top 1 'full))
                      "(x a^3 + 6) / (2 a^3)"))
  (calc-pop (calc-stack-size))

  ;; Polynomial denominators sharing a factor: x^2 - 1 contributes only
  ;; the x - 1 that x + 1 does not, so the LCD stays degree 2.
  (maf-push "1/(x + 1) + 1/(x^2 - 1)")
  (call-interactively 'mafcmd-collect-fractions)
  (cl-assert (string= (math-format-value (calc-top 1 'full))
                      "x / ((x + 1) (x - 1))"))
  (calc-pop (calc-stack-size))

  ;; Fully symbolic denominators.
  (maf-push "a/b + c/d")
  (call-interactively 'mafcmd-collect-fractions)
  (cl-assert (string= (math-format-value (calc-top 1 'full))
                      "(a d + b c) / (b d)"))
  (calc-pop (calc-stack-size))

  ;; Calc folds a reciprocal power into a negative exponent, so the
  ;; terms of 1/x^2 + 1/x^3 arrive as x^-2 and x^-3: still denominators.
  (maf-push "1/x^2 + 1/x^3")
  (call-interactively 'mafcmd-collect-fractions)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "(x + 1) / x^3"))
  (calc-pop (calc-stack-size))

  ;; Repeated factor: the LCD takes the higher power, not the product.
  (maf-push "1/(x + 1)^2 + 1/(x + 1)")
  (call-interactively 'mafcmd-collect-fractions)
  (cl-assert (string= (math-format-value (calc-top 1 'full))
                      "(x + 2) / (x + 1)^2"))
  (calc-pop (calc-stack-size))

  ;; An opaque denominator is a factor like any other.
  (maf-push "3/sqrt(2) + 1/2")
  (call-interactively 'mafcmd-collect-fractions)
  (cl-assert (string= (math-format-value (calc-top 1 'full))
                      "(sqrt(2) + 6) / (2 sqrt(2))"))
  (calc-pop (calc-stack-size))

  ;; Floats do not become exact: the LCD floats with them.
  (maf-push "x/2.0 + 1/3")
  (call-interactively 'mafcmd-collect-fractions)
  (cl-assert (string= (math-format-value (calc-top 1 'full))
                      "(3. x + 2.) / 6."))
  (calc-pop (calc-stack-size))

  ;; Terms that cancel give 0, not 0 over the LCD.
  (maf-push "x/2 - x/3 - x/6")
  (call-interactively 'mafcmd-collect-fractions)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "0"))
  (calc-pop (calc-stack-size))

  ;;; Nothing to collect.

  ;; No denominator anywhere: unchanged, and not wrapped over 1.
  (maf-push "x + 1")
  (call-interactively 'mafcmd-collect-fractions)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "x + 1"))
  (calc-pop (calc-stack-size))

  ;; Already a single fraction: unchanged, and a literal ratio is not
  ;; turned into a division.
  (maf-push "3 / a^3")
  (call-interactively 'mafcmd-collect-fractions)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "3 / a^3"))
  (calc-pop (calc-stack-size))

  (maf-push "1:3")
  (call-interactively 'mafcmd-collect-fractions)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "1:3"))
  (calc-pop (calc-stack-size))

  ;; A sum wrapped in a product is not the entry's own sum: nothing to
  ;; collect at home, while point inside picks the sum out.
  (maf-push "2 (1/x + 1/y)")
  (call-interactively 'mafcmd-collect-fractions)
  (cl-assert (string= (math-format-value (calc-top 1 'full))
                      "2 (1 / x + 1 / y)"))
  (progn (calc-cursor-stack-index 1)
         (search-forward "x" (line-end-position))
         (backward-char 1)
         (call-interactively 'mafcmd-collect-fractions))
  (cl-assert (string= (math-format-value (calc-top 1 'full))
                      "2 ((y + x) / (x y))"))
  (calc-pop (calc-stack-size))

  ;;; Targets.

  ;; Equation: each side collects on its own, and a side with nothing
  ;; to collect passes through.
  (maf-push "x/2 + x/3 = y + 1")
  (call-interactively 'mafcmd-collect-fractions)
  (cl-assert (string= (math-format-value (calc-top 1 'full))
                      "5 x / 6 = y + 1"))
  (calc-pop (calc-stack-size))

  ;; Both sides fractional.
  (maf-push "1/x + 1/y = a/2 - b/4")
  (call-interactively 'mafcmd-collect-fractions)
  (cl-assert (string= (math-format-value (calc-top 1 'full))
                      "(y + x) / (x y) = (2 a - b) / 4"))
  (calc-pop (calc-stack-size))

  ;; Selection: only the selected sub-expression is collected. The
  ;; exponent is its own composition, so selecting its - selects it and
  ;; nothing more.
  (maf-push "2^(y/3 - 1:3)")
  (progn (calc-cursor-stack-index 1)
         (search-forward "-" (line-end-position))
         (backward-char 1)
         (call-interactively 'calc-select-here)
         (call-interactively 'mafcmd-collect-fractions))
  (calc-clear-selections)
  (cl-assert (string= (math-format-value (calc-top 1 'full))
                      "2^((y - 1) / 3)"))
  (calc-pop (calc-stack-size))

  ;; Calc resolves an operator inside an associative chain to the whole
  ;; chain (stock `j s' does the same), so selecting the first + of
  ;; x / 2 + y / 3 + 1 takes the trailing 1 in with it.
  (maf-push "(x/2 + y/3) + 1")
  (progn (calc-cursor-stack-index 1)
         (search-forward "+" (line-end-position))
         (backward-char 1)
         (call-interactively 'calc-select-here)
         (call-interactively 'mafcmd-collect-fractions))
  (calc-clear-selections)
  (cl-assert (string= (math-format-value (calc-top 1 'full))
                      "(3 x + 2 y + 6) / 6"))
  (calc-pop (calc-stack-size))

  ;; Sub-formula at point, with no selection: the exponent collects and
  ;; the rest of the entry stands.
  (maf-push "2^(y/3 - 1:3)")
  (progn (calc-cursor-stack-index 1)
         (search-forward "-" (line-end-position))
         (backward-char 1)
         (call-interactively 'mafcmd-collect-fractions))
  (cl-assert (string= (math-format-value (calc-top 1 'full))
                      "2^((y - 1) / 3)"))
  (calc-pop (calc-stack-size))

  ;; The node under point has nothing to collect: it widens outward to
  ;; the innermost one that has, rather than doing nothing.
  (maf-push "2^(y/3 - 1:3)")
  (progn (calc-cursor-stack-index 1)
         (search-forward "y" (line-end-position))
         (backward-char 1)
         (call-interactively 'mafcmd-collect-fractions))
  (cl-assert (string= (math-format-value (calc-top 1 'full))
                      "2^((y - 1) / 3)"))
  (calc-pop (calc-stack-size))

  ;; Widening stops at the sum, not the whole entry: the 1 outside it
  ;; stays out of the fraction.
  (maf-push "(x/2 + y/3) + 1")
  (progn (calc-cursor-stack-index 1)
         (search-forward "y" (line-end-position))
         (backward-char 1)
         (call-interactively 'mafcmd-collect-fractions))
  (cl-assert (string= (math-format-value (calc-top 1 'full))
                      "(3 x + 2 y) / 6 + 1"))
  (calc-pop (calc-stack-size))

  ;; An explicit selection is never widened: a selected leaf with
  ;; nothing to collect leaves the entry alone.
  (maf-push "x/2 + y/3")
  (progn (calc-cursor-stack-index 1)
         (search-forward "x" (line-end-position))
         (backward-char 1)
         (call-interactively 'calc-select-here)
         (call-interactively 'mafcmd-collect-fractions))
  (calc-clear-selections)
  (cl-assert (string= (math-format-value (calc-top 1 'full))
                      "x / 2 + y / 3"))
  (calc-pop (calc-stack-size)))
