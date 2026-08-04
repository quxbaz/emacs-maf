;; maf-jump-equals (j e): move the term under point across the relation
;; it sits in, unselecting after and sending point along with it. An
;; ordered relation (<, <=, >, >=) takes added and subtracted terms
;; only — see the ordered block below.
;;
;; Expected results are calc's own, unsimplified: JumpRules produce
;; -a + y and y x, and maf commits what the rewrite gives rather than
;; tidying it (verified against stock calc-sel-jump-equals).

(defun jump-at (needle &optional back)
  "Put point on NEEDLE in the stack buffer, BACK chars before its end."
  (goto-char (point-min))
  (search-forward needle)
  (backward-char (or back 1)))

(maf-step
  ;; Additive, left to right: the term crosses as a negation.
  (maf-push "x + a = y")
  (jump-at "+ a")
  (call-interactively 'maf-jump-equals)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "x = -a + y"))
  ;; Nothing stays selected: the next command resolves from point.
  (cl-assert (null (calc-top 1 'sel)))
  ;; Point followed the term to the far side — onto the - it grew.
  (cl-assert (eq (char-after) ?-))
  (calc-pop (calc-stack-size))

  ;; Multiplicative: the factor crosses as a division.
  (maf-push "a x = y")
  (jump-at " x =" 3)
  (call-interactively 'maf-jump-equals)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "a = y / x"))
  (cl-assert (eq (char-after) ?x))
  (calc-pop (calc-stack-size))

  ;; Right to left: the same move in the other direction.
  (maf-push "y = a + b")
  (jump-at "+ b")
  (call-interactively 'maf-jump-equals)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "y - b = a"))
  (calc-pop (calc-stack-size))

  ;; Power: a selected exponent 2 crosses as a square root.
  (maf-push "a^2 = y")
  (jump-at "2 =" 3)
  (call-interactively 'maf-jump-equals)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "a = sqrt(y)"))
  (calc-pop (calc-stack-size))

  ;; Division: the divisor crosses as a multiplication.
  (maf-push "a / x = y")
  (jump-at "/ x" 1)
  (call-interactively 'maf-jump-equals)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "a = y x"))
  (calc-pop (calc-stack-size))

  ;; != additive: maf's derived twin of the additive = rule. Stock
  ;; calc-sel-jump-equals leaves this entry untouched.
  (maf-push "x + a != y")
  (jump-at "+ a")
  (call-interactively 'maf-jump-equals)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "x != -a + y"))
  (calc-pop (calc-stack-size))

  ;; != multiplicative, and right to left: the twins cover every rule,
  ;; not just the additive ones.
  (maf-push "y != a x")
  (jump-at " x" 1)
  (call-interactively 'maf-jump-equals)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "y / x != a"))
  (calc-pop (calc-stack-size))

  ;; Ordered relations, additive: an added term crosses without
  ;; disturbing the direction, so all four relations take the move and
  ;; each keeps its own sense.
  (dolist (case '(("x + a < y"  . "x < -a + y")
                  ("x + a <= y" . "x <= -a + y")
                  ("x + a > y"  . "x > -a + y")
                  ("x + a >= y" . "x >= -a + y")))
    (maf-push (car case))
    (jump-at "+ a")
    (call-interactively 'maf-jump-equals)
    (cl-assert (string= (math-format-value (calc-top 1 'full)) (cdr case)))
    (cl-assert (null (calc-top 1 'sel)))
    (calc-pop (calc-stack-size)))

  ;; Subtraction crosses the other way, and right to left.
  (maf-push "y > a - b")
  (jump-at "- b")
  (call-interactively 'maf-jump-equals)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "y + b > a"))
  (calc-pop (calc-stack-size))

  ;; A whole side under an ordered relation is additive too: it crosses,
  ;; leaving 0 behind.
  (maf-push "x <= y")
  (jump-at "x " 2)
  (call-interactively 'maf-jump-equals)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "0 <= -x + y"))
  (calc-pop (calc-stack-size))

  ;; A factor under an ordered relation stays put: crossing it flips the
  ;; direction on the factor's sign, which no rewrite rule can decide.
  ;; Nothing is pushed or popped — the entry is not even re-normalized.
  (maf-push "a x <= y")
  (jump-at " x <" 3)
  (call-interactively 'maf-jump-equals)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "a x <= y"))
  (cl-assert (= (calc-stack-size) 1))
  (calc-pop (calc-stack-size))

  ;; Nor an exponent: a^2 <= y says nothing about a <= sqrt(y).
  (maf-push "a^2 <= y")
  (jump-at "2 <" 3)
  (call-interactively 'maf-jump-equals)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "a^2 <= y"))
  (calc-pop (calc-stack-size))

  ;; The additive test is on the path to the relation, not the whole
  ;; entry: a x is a factor even though the sum above it is additive.
  (maf-push "b + a x <= y")
  (jump-at " x <" 3)
  (call-interactively 'maf-jump-equals)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "b + a x <= y"))
  (calc-pop (calc-stack-size))

  ;; A multiplicative jump under = is untouched by that restriction.
  (maf-push "a x = y")
  (jump-at " x =" 3)
  (call-interactively 'maf-jump-equals)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "a = y / x"))
  (calc-pop (calc-stack-size))

  ;; No relation at all: nothing to move, and nothing pushed or popped.
  (maf-push "x + a")
  (jump-at "+ a")
  (call-interactively 'maf-jump-equals)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "x + a"))
  (cl-assert (= (calc-stack-size) 1))
  (calc-pop (calc-stack-size))

  ;; A whole side is a term like any other: it crosses over, leaving 0
  ;; behind.
  (maf-push "x + a = y")
  (progn (jump-at "+ a") (calc-select-here nil) (calc-select-more nil))
  (call-interactively 'maf-jump-equals)
  (cl-assert (string= (math-format-value (calc-top 1 'full))
                      "0 = -x - a + y"))
  (calc-pop (calc-stack-size))

  ;; The whole entry is not a term to move: it has no side to move to,
  ;; so the relation is left standing.
  (maf-push "x + a = y")
  (progn (jump-at "+ a") (calc-select-here nil)
         (calc-select-more nil) (calc-select-more nil))
  (call-interactively 'maf-jump-equals)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "x + a = y"))
  (calc-pop (calc-stack-size))

  ;; At home with nothing selected the entry is untouched.
  (maf-push "x + a = y")
  (goto-char (point-max))
  (call-interactively 'maf-jump-equals)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "x + a = y"))
  (calc-pop (calc-stack-size))

  ;; At home with a selection standing, the jump goes to it and clears
  ;; it — the legacy version acted on stack level 1 regardless.
  (maf-push "x + a = y")
  (maf-push "1 + 2")
  (progn (jump-at "+ a") (calc-select-here nil) (goto-char (point-max)))
  (call-interactively 'maf-jump-equals)
  (cl-assert (string= (math-format-value (calc-top 2 'full)) "x = -a + y"))
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "1 + 2"))
  (cl-assert (null (calc-top 2 'sel)))
  (calc-pop (calc-stack-size))

  ;; Below the top of the stack: the entry at point is the one acted on.
  (maf-push "x + a = y")
  (maf-push "1 + 2")
  (jump-at "+ a")
  (call-interactively 'maf-jump-equals)
  (cl-assert (string= (math-format-value (calc-top 2 'full)) "x = -a + y"))
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "1 + 2"))
  (calc-pop (calc-stack-size))

  ;; A selection outranks point wherever point happens to be, not only
  ;; at home: it is the deliberate gesture, and the rest of maf takes
  ;; its subject the same way (`maf--resolve-context'). With a term
  ;; selected on entry 2 and point resting on entry 1, the jump goes to
  ;; the selection and clears it. Taking point instead found no
  ;; relation on entry 1 and did nothing at all, leaving the selection
  ;; standing — the same gesture worked or not by where point sat.
  (maf-push "x + a = y")
  (maf-push "1 + 2")
  (progn (jump-at "+ a") (calc-select-here nil) (jump-at "1 + 2" 3))
  (call-interactively 'maf-jump-equals)
  (cl-assert (string= (math-format-value (calc-top 2 'full)) "x = -a + y"))
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "1 + 2"))
  (cl-assert (null (calc-top 2 'sel)))
  (calc-pop (calc-stack-size))

  ;; A single undo reverts the jump, stack and point together.
  (maf-push "x + a = y")
  (jump-at "+ a")
  (call-interactively 'maf-jump-equals)
  (call-interactively 'maf-undo)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "x + a = y"))
  (cl-assert (eq (char-after) ?a))
  (calc-pop (calc-stack-size)))
