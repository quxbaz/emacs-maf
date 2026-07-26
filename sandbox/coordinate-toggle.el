;; -*- lexical-binding: t; -*-
;;
;; mafcmd-coordinate-toggle: the naming cycle, the graph-point entry,
;; and the shapes that have no coordinate reading.

(defun maf-sandbox--crd-refused ()
  "Run `mafcmd-coordinate-toggle', returning t if it refused with a user-error."
  (condition-case nil
      (progn (call-interactively 'mafcmd-coordinate-toggle) nil)
    (user-error t)))

(maf-step
  ;; Plain vector enters the cycle at x, y, z, w — 2, 3, and 4 wide.
  (maf-push "[2, 4]")
  (call-interactively 'mafcmd-coordinate-toggle)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "[x = 2, y = 4]"))
  (calc-pop (calc-stack-size))

  (maf-push "[1, 2, 3]")
  (call-interactively 'mafcmd-coordinate-toggle)
  (cl-assert (string= (math-format-value (calc-top 1 'full))
                      "[x = 1, y = 2, z = 3]"))
  (calc-pop (calc-stack-size))

  (maf-push "[1, 2, 3, 4]")
  (call-interactively 'mafcmd-coordinate-toggle)
  (cl-assert (string= (math-format-value (calc-top 1 'full))
                      "[x = 1, y = 2, z = 3, w = 4]"))
  (calc-pop (calc-stack-size))

  ;; xyzw -> hklm -> pqrs -> xyzw: three presses come back to the start,
  ;; values untouched throughout.
  (maf-push "[x = 2, y = 4]")
  (call-interactively 'mafcmd-coordinate-toggle)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "[h = 2, k = 4]"))
  (call-interactively 'mafcmd-coordinate-toggle)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "[p = 2, q = 4]"))
  (call-interactively 'mafcmd-coordinate-toggle)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "[x = 2, y = 4]"))
  (calc-pop (calc-stack-size))

  ;; The 3-wide sets carry their own third name.
  (maf-push "[h = 1, k = 2, l = 3]")
  (call-interactively 'mafcmd-coordinate-toggle)
  (cl-assert (string= (math-format-value (calc-top 1 'full))
                      "[p = 1, q = 2, r = 3]"))
  (calc-pop (calc-stack-size))

  ;; Named with variables from no set: re-enters the cycle at x, y, z, w
  ;; rather than wrapping the equations in more equations.
  (maf-push "[a = 1, b = 2]")
  (call-interactively 'mafcmd-coordinate-toggle)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "[x = 1, y = 2]"))
  (calc-pop (calc-stack-size))

  ;; Named only in part: same, the values survive intact.
  (maf-push "[x = 1, 2]")
  (call-interactively 'mafcmd-coordinate-toggle)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "[x = 1, y = 2]"))
  (calc-pop (calc-stack-size))

  ;; Out of order counts as unnamed: positions win, so the values are
  ;; renamed in place instead of following their old letters.
  (maf-push "[y = 1, x = 2]")
  (call-interactively 'mafcmd-coordinate-toggle)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "[x = 1, y = 2]"))
  (calc-pop (calc-stack-size))

  ;; Symbolic components are values like any other.
  (maf-push "[a + 1, sin(t)]")
  (call-interactively 'mafcmd-coordinate-toggle)
  (cl-assert (string= (math-format-value (calc-top 1 'full))
                      "[x = a + 1, y = sin(t)]"))
  (calc-pop (calc-stack-size))

  ;; Graph point: an unknown function of one argument unfolds to a pair,
  ;; which the next press names.
  (maf-push "f(2) = 0")
  (call-interactively 'mafcmd-coordinate-toggle)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "[2, 0]"))
  (call-interactively 'mafcmd-coordinate-toggle)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "[x = 2, y = 0]"))
  (calc-pop (calc-stack-size))

  ;; A known function is an equation about a value, not a point, and has
  ;; no vector side to name.
  (maf-push "sin(2) = 0")
  (cl-assert (maf-sandbox--crd-refused))
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "sin(2) = 0"))
  (calc-pop (calc-stack-size))

  ;; A relation names its vector sides in place, leaving the rest alone.
  (maf-push "v = [1, 2]")
  (call-interactively 'mafcmd-coordinate-toggle)
  (cl-assert (string= (math-format-value (calc-top 1 'full))
                      "v = [x = 1, y = 2]"))
  (calc-pop (calc-stack-size))

  (maf-push "[1, 2] = [3, 4]")
  (call-interactively 'mafcmd-coordinate-toggle)
  (cl-assert (string= (math-format-value (calc-top 1 'full))
                      "[x = 1, y = 2] = [x = 3, y = 4]"))
  (calc-pop (calc-stack-size))

  ;; More components than the set has names: refused, not truncated.
  (maf-push "[1, 2, 3, 4, 5]")
  (cl-assert (maf-sandbox--crd-refused))
  (cl-assert (string= (math-format-value (calc-top 1 'full))
                      "[1, 2, 3, 4, 5]"))
  (calc-pop (calc-stack-size))

  ;; Empty vector, a bare scalar, and a numeric equation all refuse
  ;; rather than erroring out or naming nothing.
  (maf-push "[]")
  (cl-assert (maf-sandbox--crd-refused))
  (calc-pop (calc-stack-size))

  (maf-push "5")
  (cl-assert (maf-sandbox--crd-refused))
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "5"))
  (calc-pop (calc-stack-size))

  (maf-push "2 = 0")
  (cl-assert (maf-sandbox--crd-refused))
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "2 = 0"))
  (calc-pop (calc-stack-size))

  ;; Sub-formula target: point inside a vector nested in a larger
  ;; expression names just that vector.
  (calc-push '(calcFunc-g (vec 1 2)))
  (progn (goto-char (point-min)) (search-forward "[") (backward-char 1))
  (call-interactively 'mafcmd-coordinate-toggle)
  (cl-assert (string= (math-format-value (calc-top 1 'full))
                      "g([x = 1, y = 2])"))
  (calc-pop (calc-stack-size))

  ;; The M-k binding, driven as a real keypress from home.
  (maf-push "[7, 8]")
  (progn (calc-cursor-stack-index 0)
         (execute-kbd-macro (kbd "M-k")) nil)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "[x = 7, y = 8]"))
  (calc-pop (calc-stack-size)))
