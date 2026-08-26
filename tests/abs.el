;; mafcmd-abs (A): absolute value, a vector read as its norm. The
;; command applies maf's own `maf--abs' rather than `calcFunc-abs',
;; whose two-element-vector case shortcuts through `math-hypot' and
;; hands back an inert hypot(2, sqrt(3)) — where the same entries one
;; longer answer sqrt(7). The two-element radical cases below are the
;; point of the file; scalars check that everything else still defers
;; to calc's own abs.

(maf-step
  ;; The bug that motivated the command: a two-element vector with a
  ;; radical entry answers the norm, not an inert hypot.
  (maf-push "[2, sqrt(3)]")
  (call-interactively 'mafcmd-abs)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "sqrt(7)"))
  (cl-assert (= (calc-stack-size) 1))
  (calc-pop (calc-stack-size))

  ;; Same entries one longer: the length calc always answered, for
  ;; parity across the two-element special case.
  (maf-push "[2, sqrt(3), 0]")
  (call-interactively 'mafcmd-abs)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "sqrt(7)"))
  (calc-pop (calc-stack-size))

  ;; A Pythagorean pair still lands on the integer.
  (maf-push "[3, 4]")
  (call-interactively 'mafcmd-abs)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "5"))
  (calc-pop (calc-stack-size))

  ;; Exactness does not depend on calc's own symbolic mode being on:
  ;; the radical stands either way, as in `mafcmd-hypot'.
  (cl-assert (null calc-symbolic-mode))
  (maf-push "[2, 1]")
  (call-interactively 'mafcmd-abs)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "sqrt(5)"))
  (calc-pop (calc-stack-size))

  ;; A complex entry contributes its modulus — abssqr's reading, which
  ;; the squaring in `maf--pythagoras' would miss.
  (maf-push "[(3, 4), 0]")
  (call-interactively 'mafcmd-abs)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "5"))
  (calc-pop (calc-stack-size))

  ;; Symbolic entries stay written out as a formula that composes —
  ;; assumed real by default, so the textbook form.
  (cl-assert maf-abs-assume-real)
  (maf-push "[a, b]")
  (call-interactively 'mafcmd-abs)
  (cl-assert (string= (math-format-value (calc-top 1 'full))
                      "sqrt(a^2 + b^2)"))
  (calc-pop (calc-stack-size))

  ;; With the assumption off, the complex-safe form: abssqr keeps the
  ;; modulus reading for entries that might not be real.
  (let ((maf-abs-assume-real nil))
    (maf-push "[a, b]")
    (call-interactively 'mafcmd-abs)
    (cl-assert (string= (math-format-value (calc-top 1 'full))
                        "sqrt(abssqr(a) + abssqr(b))"))
    (calc-pop (calc-stack-size)))

  ;; The assumption touches only entries calc could not decide: a
  ;; literal complex entry still contributes its squared modulus.
  (maf-push "[x, (3, 4)]")
  (call-interactively 'mafcmd-abs)
  (cl-assert (string= (math-format-value (calc-top 1 'full))
                      "sqrt(x^2 + 25)"))
  (calc-pop (calc-stack-size))

  ;; A float entry forfeits exactness: the root evaluates rather than
  ;; standing as sqrt(1), matching `mafcmd-hypot'.
  (maf-push "[0.6, 0.8]")
  (call-interactively 'mafcmd-abs)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "1."))
  (calc-pop (calc-stack-size))

  ;; Scalars are calc's own abs, untouched.
  (maf-push "-5")
  (call-interactively 'mafcmd-abs)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "5"))
  (calc-pop (calc-stack-size))

  ;; A complex scalar is its modulus, also calc's own.
  (maf-push "(3, 4)")
  (call-interactively 'mafcmd-abs)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "5"))
  (calc-pop (calc-stack-size))

  ;; A symbolic scalar stands as the inert call, as calc answers it.
  (maf-push "x")
  (call-interactively 'mafcmd-abs)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "abs(x)"))
  (calc-pop (calc-stack-size))

  ;; Equation subject: each side is taken on its own, so a vector
  ;; equation becomes an equation of norms.
  (maf-push "[3, 4] = [5, 12]")
  (call-interactively 'mafcmd-abs)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "5 = 13"))
  (calc-pop (calc-stack-size)))
