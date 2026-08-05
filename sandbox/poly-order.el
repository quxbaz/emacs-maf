;; maf-poly-order module: sums that are polynomials in one variable
;; come out of normalization in descending degree. The sorting rides
;; the normalize funnels, so it is exercised here through
;; `calc-enter-result' — the commit path every command and entry uses —
;; and through computed results (expand, simplify). A raw `calc-push'
;; bypasses normalization by design and is not covered.

(maf-step
  (cl-assert maf-use-poly-order-mode)

  ;; Ascending entry commits descending.
  (calc-wrapper (calc-enter-result 0 "test" (math-read-expr "1 + x + x^2")))
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "x^2 + x + 1"))
  (calc-pop (calc-stack-size))

  ;; Negative terms fold in as subtractions, a negated leading term
  ;; included.
  (calc-wrapper (calc-enter-result 0 "test" (math-read-expr "1 - x - x^2")))
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "-x^2 - x + 1"))
  (calc-pop (calc-stack-size))

  ;; Fractional coefficients arrive as / forms; their degree is the
  ;; numerator's.
  (calc-wrapper (calc-enter-result 0 "test" (math-read-expr "x/2 + 1 + x^2/3")))
  (cl-assert (string= (math-format-value (calc-top 1 'full))
                      "x^2 / 3 + x / 2 + 1"))
  (calc-pop (calc-stack-size))

  ;; A reciprocal is negative degree: it sorts below the constant.
  (calc-wrapper (calc-enter-result 0 "test" (math-read-expr "1/x + x + 2")))
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "x + 2 + 1 / x"))
  (calc-pop (calc-stack-size))

  ;; Several variables: no one right order, so hands off.
  (calc-wrapper (calc-enter-result 0 "test" (math-read-expr "y + x*y + 1")))
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "y + x y + 1"))
  (calc-pop (calc-stack-size))

  ;; An equation is not itself a sum; each side sorts on its own.
  (calc-wrapper (calc-enter-result 0 "test" (math-read-expr "1 + x^2 = x")))
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "x^2 + 1 = x"))
  (calc-pop (calc-stack-size))

  ;; A computed result sorts too: expansion produces the terms in
  ;; descending order however the rewrite emits them.
  (maf-push "(x + 1)^2")
  (call-interactively 'calc-expand)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "x^2 + 2 x + 1"))
  (calc-pop (calc-stack-size))

  ;; Simplifying a raw (unnormalized) push runs the result through the
  ;; funnel and sorts it.
  (maf-push "1 + x + x^2")
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "1 + x + x^2"))
  (call-interactively 'calc-simplify)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "x^2 + x + 1"))
  (calc-pop (calc-stack-size))

  ;; Under 'none simplification the module stands aside — the escape
  ;; hatch for code that binds it to protect a structure.
  (let ((calc-simplify-mode 'none))
    (calc-wrapper (calc-enter-result 0 "test" (math-read-expr "1 + x"))))
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "1 + x"))
  (calc-pop (calc-stack-size))

  ;; Module off: calc's own order passes through — its alg
  ;; simplification leaves this sum ascending, constant last.
  (maf-use-poly-order-mode -1)
  (calc-wrapper (calc-enter-result 0 "test" (math-read-expr "1 + x + x^2")))
  (maf-use-poly-order-mode 1)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "x + x^2 + 1"))
  (calc-pop (calc-stack-size)))
