;; mafcmd-sort orders a vector by numeric value, not by expression shape.
;;
;; Calc's own calcFunc-sort orders with `math-beforep', a canonical
;; ordering of expressions rather than of magnitudes. Reaching two
;; non-real operands it compares their head symbols with `string-lessp',
;; and negation wraps its operand in a `neg' node — so -sqrt(10) sorts
;; under the letter n and lands after sqrt(10) whatever its sign, and
;; v S leaves [sqrt(10), -sqrt(10)] untouched. The same is true of
;; [x, -x]. It only looks intermittent because elements sharing a head
;; recurse into their arguments, so [sqrt(2), sqrt(10), sqrt(5)] already
;; came out right.
;;
;; maf sorts by numeric value when every element has one, keeping the
;; elements in the exact form they came in with, and hands the vector
;; back to calc's ordering when any element has no place on the number
;; line. See `maf--sort-vector' in src/math.el.

(maf-step
  ;; The reported bug: a vector of a root and its negation. The order
  ;; changes; the elements keep their exact symbolic form rather than
  ;; decaying to decimals.
  (let ((calc-symbolic-mode t))
    (maf-push "[sqrt(10), -sqrt(10)]")
    (goto-char (point-max))
    (call-interactively 'mafcmd-sort)
    (cl-assert (string= (math-format-value (calc-top 1 'full))
                        "[-sqrt(10), sqrt(10)]"))
    (calc-pop (calc-stack-size)))

  ;; Same through the real keypress: v o is maf's sort key.
  (let ((calc-symbolic-mode t))
    (maf-push "[sqrt(10), -sqrt(10)]")
    (goto-char (point-max))
    (execute-kbd-macro (kbd "v o"))
    (cl-assert (string= (math-format-value (calc-top 1 'full))
                        "[-sqrt(10), sqrt(10)]"))
    (calc-pop (calc-stack-size)))

  ;; And through v S, calc's own sort key, which the mafcmd table binds
  ;; to the same command.
  (let ((calc-symbolic-mode t))
    (maf-push "[sqrt(10), -sqrt(10)]")
    (goto-char (point-max))
    (execute-kbd-macro (kbd "v S"))
    (cl-assert (string= (math-format-value (calc-top 1 'full))
                        "[-sqrt(10), sqrt(10)]"))
    (calc-pop (calc-stack-size)))

  ;; A plain number sorts among the symbolic elements by its value, so
  ;; the root's negation crosses it rather than trailing the vector.
  (let ((calc-symbolic-mode t))
    (maf-push "[sqrt(10), 1, -sqrt(10)]")
    (goto-char (point-max))
    (call-interactively 'mafcmd-sort)
    (cl-assert (string= (math-format-value (calc-top 1 'full))
                        "[-sqrt(10), 1, sqrt(10)]"))
    (calc-pop (calc-stack-size)))

  ;; Ordinary numbers sort as they always did.
  (maf-push "[3, 1, 2]")
  (goto-char (point-max))
  (call-interactively 'mafcmd-sort)
  (cl-assert (equal (calc-top 1 'full) '(vec 1 2 3)))
  (calc-pop (calc-stack-size))

  (maf-push "[-1, -5, 3]")
  (goto-char (point-max))
  (call-interactively 'mafcmd-sort)
  (cl-assert (equal (calc-top 1 'full) '(vec -5 -1 3)))
  (calc-pop (calc-stack-size))

  ;; Named constants sort by value too, where calc would sort e and pi
  ;; by their variable names.
  (let ((calc-symbolic-mode t))
    (maf-push "[pi, 3, e]")
    (goto-char (point-max))
    (call-interactively 'mafcmd-sort)
    (cl-assert (string= (math-format-value (calc-top 1 'full)) "[e, 3, pi]"))
    (calc-pop (calc-stack-size)))

  ;; Fractions and floats interleave by value, each keeping its own form.
  (maf-push "[1:2, 1:3, 0.4]")
  (goto-char (point-max))
  (call-interactively 'mafcmd-sort)
  (cl-assert (string= (math-format-value (calc-top 1 'full))
                      "[1:3, 0.4, 1:2]"))
  (calc-pop (calc-stack-size))

  ;; Exact operands are compared exactly rather than through a float:
  ;; these three agree well past `calc-internal-prec' digits, so a float
  ;; comparison would tie them and leave them as they were.
  (maf-push "[10^20 + 1, 10^20, 10^20 + 2]")
  (goto-char (point-max))
  (call-interactively 'mafcmd-sort)
  (cl-assert (equal (calc-top 1 'full)
                    '(vec 100000000000000000000
                          100000000000000000001
                          100000000000000000002)))
  (calc-pop (calc-stack-size))

  ;; I v o is the descending sort — the same ordering, reversed.
  (let ((calc-symbolic-mode t))
    (maf-push "[sqrt(10), -sqrt(10)]")
    (goto-char (point-max))
    (call-interactively 'calc-inverse)
    (call-interactively 'mafcmd-sort)
    (cl-assert (string= (math-format-value (calc-top 1 'full))
                        "[sqrt(10), -sqrt(10)]"))
    (calc-pop (calc-stack-size)))

  (maf-push "[3, 1, 2]")
  (goto-char (point-max))
  (call-interactively 'calc-inverse)
  (call-interactively 'mafcmd-sort)
  (cl-assert (equal (calc-top 1 'full) '(vec 3 2 1)))
  (calc-pop (calc-stack-size))

  ;; A free variable has no place on the number line, so the whole
  ;; vector falls back to calc's ordering: [x, -x] stays as it is,
  ;; exactly as calc's own v S leaves it.
  (maf-push "[x, -x]")
  (goto-char (point-max))
  (call-interactively 'mafcmd-sort)
  (cl-assert (equal (calc-top 1 'full)
                    '(vec (var x var-x) (neg (var x var-x)))))
  (calc-pop (calc-stack-size))

  ;; The fallback is all-or-nothing: one unorderable element gives the
  ;; whole vector to calc, so nothing comes back half sorted by value
  ;; and half by shape.
  (maf-push "[3, 1, x]")
  (goto-char (point-max))
  (call-interactively 'mafcmd-sort)
  (cl-assert (equal (calc-top 1 'full) '(vec 1 3 (var x var-x))))
  (calc-pop (calc-stack-size))

  ;; A complex element is unorderable in the same way.
  (maf-push "[3, 1 + 2i]")
  (goto-char (point-max))
  (call-interactively 'mafcmd-sort)
  (cl-assert (string= (math-format-value (calc-top 1 'full))
                      "[3, 2 i + 1]"))
  (calc-pop (calc-stack-size))

  ;; A matrix sorts by rows, calc's behavior, since a row is not a real.
  (maf-push "[[3, 4], [1, 2]]")
  (goto-char (point-max))
  (call-interactively 'mafcmd-sort)
  (cl-assert (equal (calc-top 1 'full) '(vec (vec 1 2) (vec 3 4))))
  (calc-pop (calc-stack-size))

  ;; Degenerate vectors are left alone rather than erroring.
  (maf-push "[]")
  (goto-char (point-max))
  (call-interactively 'mafcmd-sort)
  (cl-assert (equal (calc-top 1 'full) '(vec)))
  (calc-pop (calc-stack-size))

  (maf-push "[5]")
  (goto-char (point-max))
  (call-interactively 'mafcmd-sort)
  (cl-assert (equal (calc-top 1 'full) '(vec 5)))
  (calc-pop (calc-stack-size))

  ;; Sorting something that is not a vector leaves the call inert, as
  ;; calc leaves sort(5): the entry is not silently mangled.
  (maf-push "5")
  (goto-char (point-max))
  (call-interactively 'mafcmd-sort)
  (cl-assert (equal (calc-top 1 'full) '(maf-sort 5)))
  (calc-pop (calc-stack-size))

  ;; End to end, the way the bug was met: poly-roots hands back the pair
  ;; of roots, and sorting puts them in ascending order.
  (let ((calc-symbolic-mode t))
    (maf-push "x^2 - 10")
    (goto-char (point-max))
    (call-interactively 'mafcmd-poly-roots)
    (cl-assert (string= (math-format-value (calc-top 1 'full))
                        "[sqrt(10), -sqrt(10)]"))
    (goto-char (point-max))
    (call-interactively 'mafcmd-sort)
    (cl-assert (string= (math-format-value (calc-top 1 'full))
                        "[-sqrt(10), sqrt(10)]"))
    (calc-pop (calc-stack-size))))
