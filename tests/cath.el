;; Port verification for mafcmd-cath (f l) and mafcmd-unit-cath (f L):
;; the remaining leg of a right triangle, from the hypotenuse and one
;; leg, or from one leg with the hypotenuse fixed at 1.

(maf-step
  ;; Basic: hypotenuse at level 2, known leg at level 1.
  (maf-push "5")
  (maf-push "3")
  (call-interactively 'mafcmd-cath)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "4"))
  (cl-assert (= (calc-stack-size) 1))
  (calc-pop (calc-stack-size))

  ;; Another Pythagorean triple.
  (maf-push "17")
  (maf-push "8")
  (call-interactively 'mafcmd-cath)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "15"))
  (calc-pop (calc-stack-size))

  ;; Irrational leg: the radical stays exact rather than floating.
  (maf-push "2")
  (maf-push "1")
  (call-interactively 'mafcmd-cath)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "sqrt(3)"))
  (calc-pop (calc-stack-size))

  ;; A radical hypotenuse: sqrt(2)^2 reduces to 2, so the answer is 1
  ;; and not an unevaluated sqrt(sqrt(2)^2 - 1).
  (maf-push "sqrt(2)")
  (maf-push "1")
  (call-interactively 'mafcmd-cath)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "1"))
  (calc-pop (calc-stack-size))

  ;; Floats stay floats.
  (maf-push "2.5")
  (maf-push "1.5")
  (call-interactively 'mafcmd-cath)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "2."))
  (calc-pop (calc-stack-size))

  ;; A float operand forfeits exactness: the root evaluates rather than
  ;; standing as sqrt(0.75).
  (maf-push "1")
  (maf-push "0.5")
  (call-interactively 'mafcmd-cath)
  (cl-assert (string= (math-format-value (calc-top 1 'full))
                      "0.866025403784"))
  (calc-pop (calc-stack-size))

  ;; Exactness does not depend on calc's own symbolic mode being on:
  ;; the radical stands either way.
  (cl-assert (null calc-symbolic-mode))
  (maf-push "3")
  (maf-push "1")
  (call-interactively 'mafcmd-cath)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "sqrt(8)"))
  (calc-pop (calc-stack-size))

  ;; Symbolic operands: the form stands.
  (maf-push "h")
  (maf-push "a")
  (call-interactively 'mafcmd-cath)
  (cl-assert (string= (math-format-value (calc-top 1 'full))
                      "sqrt(h^2 - a^2)"))
  (calc-pop (calc-stack-size))

  ;; A leg longer than the hypotenuse: calc's own sqrt of a negative
  ;; radicand, an imaginary leg rather than an error.
  (maf-push "1")
  (maf-push "2")
  (call-interactively 'mafcmd-cath)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "sqrt(3) i"))
  (calc-pop (calc-stack-size))

  ;; Equal operands: a degenerate triangle, leg 0.
  (maf-push "5")
  (maf-push "5")
  (call-interactively 'mafcmd-cath)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "0"))
  (calc-pop (calc-stack-size))

  ;; Sub-formula at point: only the term under point is the hypotenuse,
  ;; and the argument still comes off the stack top.
  (maf-push "z + 13")
  (maf-push "5")
  (progn (calc-cursor-stack-index 2) (end-of-line) (backward-char 1))
  (call-interactively 'mafcmd-cath)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "z + 12"))
  (cl-assert (= (calc-stack-size) 1))
  (calc-pop (calc-stack-size))

  ;; Equation subject: each side is a hypotenuse against the same leg.
  (maf-push "5 = 13")
  (maf-push "5")
  (call-interactively 'mafcmd-cath)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "0 = 12"))
  (cl-assert (= (calc-stack-size) 1))
  (calc-pop (calc-stack-size))

  ;; Keep-args leaves both operands below the result.
  (maf-push "13")
  (maf-push "5")
  (call-interactively 'calc-keep-args)
  (call-interactively 'mafcmd-cath)
  (cl-assert (= (calc-stack-size) 3))
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "12"))
  (cl-assert (string= (math-format-value (calc-top 3 'full)) "13"))
  (calc-pop (calc-stack-size))

  ;;; mafcmd-unit-cath: the hypotenuse is 1, nothing comes off the stack.

  ;; The unit-circle companion of a 3:5 sine.
  (maf-push "3:5")
  (call-interactively 'mafcmd-unit-cath)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "4:5"))
  (cl-assert (= (calc-stack-size) 1))
  (calc-pop (calc-stack-size))

  ;; The two ends of the quarter turn.
  (maf-push "0")
  (call-interactively 'mafcmd-unit-cath)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "1"))
  (calc-pop (calc-stack-size))

  (maf-push "1")
  (call-interactively 'mafcmd-unit-cath)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "0"))
  (calc-pop (calc-stack-size))

  ;; A half leg: the exact sqrt(3) / 2, not a float.
  (maf-push "1:2")
  (call-interactively 'mafcmd-unit-cath)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "sqrt(3) / 2"))
  (calc-pop (calc-stack-size))

  ;; Symbolic: the Pythagorean identity written out.
  (maf-push "x")
  (call-interactively 'mafcmd-unit-cath)
  (cl-assert (string= (math-format-value (calc-top 1 'full))
                      "sqrt(-x^2 + 1)"))
  (calc-pop (calc-stack-size))

  ;; sin -> cos, up to sign: the shape the command exists for.
  (maf-push "sin(t)")
  (call-interactively 'mafcmd-unit-cath)
  (cl-assert (string= (math-format-value (calc-top 1 'full))
                      "sqrt(1 - sin(t)^2)"))
  (calc-pop (calc-stack-size))

  ;; A float leg: numeric, as in mafcmd-cath.
  (maf-push "0.6")
  (call-interactively 'mafcmd-unit-cath)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "0.8"))
  (calc-pop (calc-stack-size))

  ;; Past the unit hypotenuse: imaginary, as in mafcmd-cath.
  (maf-push "2")
  (call-interactively 'mafcmd-unit-cath)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "sqrt(3) i"))
  (calc-pop (calc-stack-size))

  ;; Sub-formula at point: only the term under point is the leg.
  (maf-push "y + 3:5")
  (progn (calc-cursor-stack-index 1) (end-of-line) (backward-char 1))
  (call-interactively 'mafcmd-unit-cath)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "y + 4:5"))
  (calc-pop (calc-stack-size))

  ;; Equation subject: each side independently.
  (maf-push "3:5 = 1:2")
  (call-interactively 'mafcmd-unit-cath)
  (cl-assert (string= (math-format-value (calc-top 1 'full))
                      "4:5 = sqrt(3) / 2"))
  (calc-pop (calc-stack-size))

  ;;; The real bindings, through the keymap.

  ;; f l on the hypotenuse/leg pair.
  (maf-push "5")
  (maf-push "3")
  (progn (calc-cursor-stack-index 0)
         (execute-kbd-macro (kbd "f l")) nil)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "4"))
  (cl-assert (= (calc-stack-size) 1))
  (calc-pop (calc-stack-size))

  ;; f L on a single leg.
  (maf-push "3:5")
  (progn (calc-cursor-stack-index 0)
         (execute-kbd-macro (kbd "f L")) nil)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "4:5"))
  (calc-pop (calc-stack-size))

  ;; I f l routes to mafcmd-hypot: the two legs make the hypotenuse.
  (maf-push "3")
  (maf-push "4")
  (progn (calc-cursor-stack-index 0)
         (execute-kbd-macro (kbd "I f l")) nil)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "5"))
  (calc-pop (calc-stack-size))

  ;; And back the other way: I f h routes to mafcmd-cath.
  (maf-push "5")
  (maf-push "3")
  (progn (calc-cursor-stack-index 0)
         (execute-kbd-macro (kbd "I f h")) nil)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "4"))
  (calc-pop (calc-stack-size))

  ;; lnp1 ceded f L but keeps its Inverse route off expm1 (I f E).
  (maf-push "0")
  (progn (calc-cursor-stack-index 0)
         (execute-kbd-macro (kbd "I f E")) nil)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "0"))
  (cl-assert (eq (key-binding (kbd "f L")) 'mafcmd-unit-cath))
  (calc-pop (calc-stack-size)))
