(maf-step
  ;; Home: a symbolic value becomes its float.
  (maf-push "sqrt(2)")
  (goto-char (point-max))
  (call-interactively 'mafcmd-evaluate)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "1.41421356237"))
  (calc-pop 1)

  ;; Fractions float — the legacy k k left them exact.
  (maf-push "1:3")
  (goto-char (point-max))
  (call-interactively 'mafcmd-evaluate)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "0.333333333333"))
  (calc-pop 1)

  ;; Symbolic division by a number goes inexact too.
  (maf-push "x/3")
  (goto-char (point-max))
  (call-interactively 'mafcmd-evaluate)
  (cl-assert (string= (math-format-value (calc-top 1 'full))
                      "0.333333333333 x"))
  (calc-pop 1)

  ;; Numeric division divides directly (no double rounding).
  (maf-push "3 x/6")
  (goto-char (point-max))
  (call-interactively 'mafcmd-evaluate)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "0.5 x"))
  (calc-pop 1)

  ;; Integers that divide nothing stay exact.
  (maf-push "6 x + 8:3")
  (goto-char (point-max))
  (call-interactively 'mafcmd-evaluate)
  (cl-assert (string= (math-format-value (calc-top 1 'full))
                      "6 x + 2.66666666667"))
  (calc-pop 1)

  ;; No numeric value: commits unchanged.
  (maf-push "x^2 + 1")
  (goto-char (point-max))
  (call-interactively 'mafcmd-evaluate)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "x^2 + 1"))
  (calc-pop 1)

  ;; A non-numeric divisor is left alone.
  (maf-push "1/(x+1)")
  (goto-char (point-max))
  (call-interactively 'mafcmd-evaluate)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "1 / (x + 1)"))
  (calc-pop 1)

  ;; Stored variables are substituted.
  (set 'var-a 5)
  (maf-push "a + 1")
  (goto-char (point-max))
  (call-interactively 'mafcmd-evaluate)
  (cl-assert (equal (calc-top 1 'full) 6))
  (progn (calc-pop 1) (makunbound 'var-a))

  ;; Subexpr: only the sub-formula under point evaluates.
  (maf-push "2 + sqrt(2)")
  (progn (goto-char (point-min)) (search-forward "sqrt") (backward-char 2))
  (call-interactively 'mafcmd-evaluate)
  (cl-assert (string= (math-format-value (calc-top 1 'full))
                      "2 + 1.41421356237"))
  (calc-pop 1)

  ;; Equation: each side evaluates on its own.
  (maf-push "x = 2 sqrt(2)")
  (progn (goto-char (point-min)) (end-of-line))
  (call-interactively 'mafcmd-evaluate)
  (cl-assert (string= (math-format-value (calc-top 1 'full))
                      "x = 2.82842712474"))
  (calc-pop 1)

  ;; k k runs it from the keyboard.
  (maf-push "pi/2")
  (progn (calc-cursor-stack-index 0)
         (execute-kbd-macro (kbd "k k")) nil)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "1.5707963268"))
  (calc-pop 1)

  ;;; Identify — the Inverse route.

  ;; I k k identifies a float as a closed form.
  (maf-push "1.41421356237")
  (progn (calc-cursor-stack-index 0)
         (execute-kbd-macro (kbd "I k k")) nil)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "sqrt(2)"))
  (calc-pop 1)

  ;; Fractions, roots with a rational factor, multiples of pi, logs.
  (maf-push "0.333333333333")
  (goto-char (point-max))
  (progn (call-interactively 'calc-inverse)
         (call-interactively 'mafcmd-evaluate))
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "1:3"))
  (calc-pop 1)

  (maf-push "0.288675134595")
  (goto-char (point-max))
  (call-interactively 'mafcmd-identify)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "1:6 sqrt(3)"))
  (calc-pop 1)

  (maf-push "4.71238898038")
  (goto-char (point-max))
  (call-interactively 'mafcmd-identify)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "3:2 pi"))
  (calc-pop 1)

  (maf-push "1.60943791243")
  (goto-char (point-max))
  (call-interactively 'mafcmd-identify)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "ln(5)"))
  (calc-pop 1)

  ;; Negative targets identify by magnitude, then negate.
  (maf-push "-2.44948974278")
  (goto-char (point-max))
  (call-interactively 'mafcmd-identify)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "-sqrt(6)"))
  (calc-pop 1)

  ;; A hand-typed truncation still identifies (absolute 1e-8 tolerance).
  (maf-push "1.41421356")
  (goto-char (point-max))
  (call-interactively 'mafcmd-identify)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "sqrt(2)"))
  (calc-pop 1)

  ;; The result is exact: evaluating it returns the float it came from.
  (maf-push "2.44948974278")
  (goto-char (point-max))
  (progn (call-interactively 'mafcmd-identify)
         (call-interactively 'mafcmd-evaluate))
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "2.44948974278"))
  (calc-pop 1)

  ;; Equation: each side identifies on its own.
  (maf-push "x = 0.333333333333")
  (progn (goto-char (point-min)) (end-of-line))
  (call-interactively 'mafcmd-identify)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "x = 1:3"))
  (calc-pop 1)

  ;; No candidate matches: signals, and the entry is left alone. A large
  ;; value must not be dragged onto a bogus radicand either.
  (maf-push "0.1234567")
  (goto-char (point-max))
  (cl-assert (eq 'caught (condition-case nil
                             (progn (call-interactively 'mafcmd-identify) nil)
                           (error 'caught))))
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "0.1234567"))
  (calc-pop 1)

  (maf-push "12345.6789")
  (goto-char (point-max))
  (cl-assert (eq 'caught (condition-case nil
                             (progn (call-interactively 'mafcmd-identify) nil)
                           (error 'caught))))
  (calc-pop 1)

  ;; No numeric value at all: commits unchanged, no error — that is what
  ;; lets the x side of the equation above pass through.
  (maf-push "x + 1")
  (goto-char (point-max))
  (call-interactively 'mafcmd-identify)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "x + 1"))
  (calc-pop 1))
