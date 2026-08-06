;; Port verification for mafcmd-hypot (f h): the hypotenuse of a right
;; triangle from its two legs. The command applies maf's own
;; `maf--hypot' rather than `calcFunc-hypot', which only answers when
;; both legs pass `Math-scalarp' and otherwise hands back an inert
;; hypot(sqrt(3), 1) — the gap the legacy calcFunc-hypot advice patched
;; with abssqr. Squaring under a structural normalize covers it, the
;; same way `maf--cath' already worked in the other direction, so the
;; radical and symbolic cases below are the point of the file.

(maf-step
  ;; Basic: the legs at levels 2 and 1, the hypotenuse back.
  (maf-push "3")
  (maf-push "4")
  (call-interactively 'mafcmd-hypot)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "5"))
  (cl-assert (= (calc-stack-size) 1))
  (calc-pop (calc-stack-size))

  ;; Another Pythagorean triple, and the operand order that reads the
  ;; same as `mafcmd-cath'.
  (maf-push "5")
  (maf-push "12")
  (call-interactively 'mafcmd-hypot)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "13"))
  (calc-pop (calc-stack-size))

  ;; No triple: the radical stays exact rather than floating.
  (maf-push "2")
  (maf-push "1")
  (call-interactively 'mafcmd-hypot)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "sqrt(5)"))
  (calc-pop (calc-stack-size))

  ;; A radical leg — what calc's own hypot refuses. sqrt(3)^2 reduces to
  ;; 3 under the normalize, so this is 2 and not an unevaluated
  ;; hypot(sqrt(3), 1).
  (maf-push "sqrt(3)")
  (maf-push "1")
  (call-interactively 'mafcmd-hypot)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "2"))
  (calc-pop (calc-stack-size))

  ;; Both legs radical: the diagonal of a sqrt(2) square, exactly 2. The
  ;; arg side stays exact because `maf--resolve-context' takes :arg raw
  ;; off the stack — a renormalize there would float the sqrt(2) before
  ;; the command is entered, which is how every binary command once
  ;; answered this with 2. instead.
  (maf-push "sqrt(2)")
  (maf-push "sqrt(2)")
  (call-interactively 'mafcmd-hypot)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "2"))
  (calc-pop (calc-stack-size))

  ;; Symbolic legs: the form stands as a formula that still composes,
  ;; where calc's own answers hypot(a, b) with itself.
  (maf-push "a")
  (maf-push "b")
  (call-interactively 'mafcmd-hypot)
  (cl-assert (string= (math-format-value (calc-top 1 'full))
                      "sqrt(a^2 + b^2)"))
  (calc-pop (calc-stack-size))

  ;; The identity is not applied — math-normalize squares and adds, it
  ;; does not simplify — so this stays written out, as sqrt(1 - sin(t)^2)
  ;; does in `mafcmd-unit-cath'.
  (maf-push "sin(t)")
  (maf-push "cos(t)")
  (call-interactively 'mafcmd-hypot)
  (cl-assert (string= (math-format-value (calc-top 1 'full))
                      "sqrt(sin(t)^2 + cos(t)^2)"))
  (calc-pop (calc-stack-size))

  ;; Floats stay floats.
  (maf-push "1.5")
  (maf-push "2")
  (call-interactively 'mafcmd-hypot)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "2.5"))
  (calc-pop (calc-stack-size))

  ;; A float operand forfeits exactness: the root evaluates rather than
  ;; standing as sqrt(1), matching `mafcmd-cath'.
  (maf-push "0.6")
  (maf-push "0.8")
  (call-interactively 'mafcmd-hypot)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "1."))
  (calc-pop (calc-stack-size))

  ;; Exactness does not depend on calc's own symbolic mode being on:
  ;; the radical stands either way.
  (cl-assert (null calc-symbolic-mode))
  (maf-push "3")
  (maf-push "1")
  (call-interactively 'mafcmd-hypot)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "sqrt(10)"))
  (calc-pop (calc-stack-size))

  ;; A zero leg: the degenerate triangle is the other leg itself.
  (maf-push "5")
  (maf-push "0")
  (call-interactively 'mafcmd-hypot)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "5"))
  (calc-pop (calc-stack-size))

  ;; Sub-formula at point: only the term under point is a leg, and the
  ;; argument still comes off the stack top.
  (maf-push "z + 3")
  (maf-push "4")
  (progn (calc-cursor-stack-index 2) (end-of-line) (backward-char 1))
  (call-interactively 'mafcmd-hypot)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "z + 5"))
  (cl-assert (= (calc-stack-size) 1))
  (calc-pop (calc-stack-size))

  ;; Equation subject: each side is a leg against the same other leg.
  (maf-push "3 = 5")
  (maf-push "4")
  (call-interactively 'mafcmd-hypot)
  (cl-assert (string= (math-format-value (calc-top 1 'full))
                      "5 = sqrt(41)"))
  (cl-assert (= (calc-stack-size) 1))
  (calc-pop (calc-stack-size))

  ;; Keep-args leaves both legs below the result.
  (maf-push "3")
  (maf-push "4")
  (call-interactively 'calc-keep-args)
  (call-interactively 'mafcmd-hypot)
  (cl-assert (= (calc-stack-size) 3))
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "5"))
  (cl-assert (string= (math-format-value (calc-top 3 'full)) "3"))
  (calc-pop (calc-stack-size))

  ;; The Inverse flag routes to `mafcmd-cath', which calc leaves unbound
  ;; on I f h: hypot goes legs -> hypotenuse, cath comes back.
  (maf-push "5")
  (maf-push "4")
  (progn (calc-inverse nil) (call-interactively 'mafcmd-hypot))
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "3"))
  (cl-assert (not calc-inverse-flag))
  (calc-pop (calc-stack-size)))
