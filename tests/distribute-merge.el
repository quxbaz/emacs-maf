;; maf-distribute (j D) and maf-merge (j M): spread the formula around
;; the target inward over its parts, and gather it back.
;;
;; Expected results are calc's own DistribRules/MergeRules output.
;; Distribute commits unsimplified — without that, calc's simplifier
;; folds x^b x^a straight back to x^(a + b) — so the parts come out in
;; calc's order, not the order they were written in. Every expected
;; value below was checked against stock calc-sel-distribute /
;; calc-sel-merge driven with the same node selected by hand.

(defun dm-at (needle &optional back)
  "Put point on NEEDLE in the stack buffer, BACK chars before its end."
  (goto-char (point-min))
  (search-forward needle)
  (backward-char (or back 1)))

(defun dm-top (&optional n)
  (math-format-value (calc-top (or n 1) 'full)))

(maf-step
  ;; --- distribute -------------------------------------------------

  ;; A product over a sum. Point is on the bare a: the rule that fires
  ;; reads the product around it, so the target widens one level out.
  (maf-push "x*(a + b)")
  (dm-at "a" 1)
  (call-interactively 'maf-distribute)
  (cl-assert (string= (dm-top) "x b + x a"))
  ;; Nothing stays selected: the next command resolves from point.
  (cl-assert (null (calc-top 1 'sel)))
  ;; Point followed the part the rules marked as the outcome.
  (cl-assert (eq (char-after) ?b))
  (calc-pop (calc-stack-size))

  ;; A sum over a divisor.
  (maf-push "(a + b) / x")
  (dm-at "a" 1)
  (call-interactively 'maf-distribute)
  (cl-assert (string= (dm-top) "b / x + a / x"))
  (calc-pop (calc-stack-size))

  ;; A root over a product, and a logarithm over one.
  (maf-push "sqrt(a b)")
  (dm-at "a" 1)
  (call-interactively 'maf-distribute)
  (cl-assert (string= (dm-top) "sqrt(b) sqrt(a)"))
  (calc-pop (calc-stack-size))

  (maf-push "ln(a b)")
  (dm-at "a" 1)
  (call-interactively 'maf-distribute)
  (cl-assert (string= (dm-top) "ln(b) + ln(a)"))
  (calc-pop (calc-stack-size))

  ;; A power over a sum. This is the case that needs the unsimplified
  ;; commit: calc's simplifier recombines x^b x^a into x^(b + a).
  (maf-push "x^(a + b)")
  (dm-at "a" 1)
  (call-interactively 'maf-distribute)
  (cl-assert (string= (dm-top) "x^b x^a"))
  (calc-pop (calc-stack-size))

  ;; An angle sum through sin.
  (maf-push "sin(a + b)")
  (dm-at "a" 1)
  (call-interactively 'maf-distribute)
  (cl-assert (string= (dm-top) "sin(b) cos(a) + cos(b) sin(a)"))
  (calc-pop (calc-stack-size))

  ;; An integer power of a sum expands. The rule computes this by
  ;; calling calc's expandpow from inside itself; that helper is
  ;; evaluated back out, so the call cannot ride into the entry.
  (maf-push "(x + y)^2")
  (dm-at "x" 1)
  (call-interactively 'maf-distribute)
  (cl-assert (string= (dm-top) "y^2 + 2 x y + x^2"))
  (cl-assert (not (string-match-p "expandpow"
                                  (prin1-to-string (calc-top 1 'full)))))
  (calc-pop (calc-stack-size))

  ;; --- distribute: logarithms of powers ---------------------------

  ;; The exponent comes out in front, whichever end of the power point
  ;; is on: widening reaches the same x^2 from the base and from the
  ;; exponent. The rule writes it second (ln(select(a)) * b); a numeric
  ;; coefficient is moved to the front, calc's own way round, which its
  ;; simplifier would have done had a distribution been able to run
  ;; under it.
  (maf-push "ln(x^2)")
  (dm-at "x" 1)
  (call-interactively 'maf-distribute)
  (cl-assert (string= (dm-top) "2 ln(x)"))
  (calc-pop (calc-stack-size))

  (maf-push "ln(x^2)")
  (dm-at "2" 1)
  (call-interactively 'maf-distribute)
  (cl-assert (string= (dm-top) "2 ln(x)"))
  (calc-pop (calc-stack-size))

  (maf-push "log10(x^3)")
  (dm-at "x" 1)
  (call-interactively 'maf-distribute)
  (cl-assert (string= (dm-top) "3 log10(x)"))
  (calc-pop (calc-stack-size))

  ;; A symbolic exponent is not a number, so it stays where the rule
  ;; put it — only numeric coefficients are moved, that being the part
  ;; of calc's ordering that cannot undo a rewrite. The two-argument
  ;; log keeps its base either way.
  (maf-push "log(x^p, b)")
  (dm-at "x" 1)
  (call-interactively 'maf-distribute)
  (cl-assert (string= (dm-top) "log(x, b) p"))
  (calc-pop (calc-stack-size))

  ;; The reordering leaves alone what calc already had the right way
  ;; round, and does not disturb an all-numeric product: 2 3 is the
  ;; unsimplified 2 * 3, not something to re-front.
  (maf-push "2 * (x + 3)")
  (dm-at "x" 1)
  (call-interactively 'maf-distribute)
  (cl-assert (string= (dm-top) "2 3 + 2 x"))
  (calc-pop (calc-stack-size))

  ;; --- distribute: the sign rules do not hijack the marker --------

  ;; Two DistribRules mark a bare negation, and calc's matcher reads
  ;; any expression as -a. Left alone they claim every marker before
  ;; the rule the gesture meant — ln(x^2) would answer
  ;; ln((-1)^2 (-x)^2) instead of the above. A split of a sign the
  ;; marked node does not have counts as no rule firing.
  (maf-push "sqrt(x)")
  (dm-at "x" 1)
  (call-interactively 'maf-distribute)
  (cl-assert (string= (dm-top) "sqrt(x)"))
  (cl-assert (= (calc-stack-size) 1))
  (calc-pop (calc-stack-size))

  ;; sqrt of a power has no distribute rule at all, at either end.
  (maf-push "sqrt(x^4)")
  (dm-at "x" 1)
  (call-interactively 'maf-distribute)
  (cl-assert (string= (dm-top) "sqrt(x^4)"))
  (calc-pop (calc-stack-size))

  ;; A genuinely negative operand still splits — that is what the two
  ;; rules are for, and the guard must not reach them.
  (maf-push "sqrt(-x)")
  (dm-at "x" 1)
  (call-interactively 'maf-distribute)
  (cl-assert (string= (dm-top) "sqrt(-1) sqrt(x)"))
  (calc-pop (calc-stack-size))

  (maf-push "(-x)^2")
  (dm-at "x" 1)
  (call-interactively 'maf-distribute)
  (cl-assert (string= (dm-top) "(-1)^2 x^2"))
  (calc-pop (calc-stack-size))

  ;; --- distribute: literal fractions ------------------------------

  ;; Calc stores a rational as its own atom, which no `a / b' rule can
  ;; match; read as a division it distributes. Stock calc instead
  ;; matches its negation rule here and answers i sqrt(-3:4), which is
  ;; -sqrt(3)/2 — the wrong sign. Assert the value, not just the form.
  (maf-push "sqrt(3:4)")
  (dm-at "3" 1)
  (call-interactively 'maf-distribute)
  (cl-assert (string= (dm-top) "sqrt(1 / 4) sqrt(3)"))
  ;; sqrt(3)/2 = 0.8660...; stock's answer is the negation of it, so
  ;; the leading digits pin the sign as well as the magnitude.
  (cl-assert (string-prefix-p
              "0.866"
              (math-format-value
               (math-normalize (list 'calcFunc-float (calc-top 1 'full))))))
  (calc-pop (calc-stack-size))

  (maf-push "ln(3:4)")
  (dm-at "3" 1)
  (call-interactively 'maf-distribute)
  (cl-assert (string= (dm-top) "ln(1 / 4) + ln(3)"))
  (calc-pop (calc-stack-size))

  ;; A fraction with no rule around it is left alone — the division
  ;; substitution must not leak a `/' into the entry on its own.
  (maf-push "3:4 + x")
  (dm-at "3" 1)
  (call-interactively 'maf-distribute)
  (cl-assert (string= (dm-top) "3:4 + x"))
  (cl-assert (= (calc-stack-size) 1))
  (calc-pop (calc-stack-size))

  ;; --- merge ------------------------------------------------------

  ;; A common factor out of a sum.
  (maf-push "x a + x b")
  (dm-at "x b" 1)
  (call-interactively 'maf-merge)
  (cl-assert (string= (dm-top) "x*(a + b)"))
  (cl-assert (null (calc-top 1 'sel)))
  (cl-assert (eq (char-after) ?b))
  (calc-pop (calc-stack-size))

  ;; A shared denominator.
  (maf-push "a / x + b / x")
  (dm-at "b" 1)
  (call-interactively 'maf-merge)
  (cl-assert (string= (dm-top) "(a + b) / x"))
  (calc-pop (calc-stack-size))

  ;; Powers of one base add.
  (maf-push "x^a x^b")
  (dm-at "x^b" 1)
  (call-interactively 'maf-merge)
  (cl-assert (string= (dm-top) "x^(a + b)"))
  (calc-pop (calc-stack-size))

  ;; Logarithms, roots and exponentials combine.
  (maf-push "ln(a) + ln(b)")
  (dm-at "ln(b" 1)
  (call-interactively 'maf-merge)
  (cl-assert (string= (dm-top) "ln(a b)"))
  (calc-pop (calc-stack-size))

  (maf-push "sqrt(a) sqrt(b)")
  (dm-at "sqrt(b" 1)
  (call-interactively 'maf-merge)
  (cl-assert (string= (dm-top) "sqrt(a b)"))
  (calc-pop (calc-stack-size))

  (maf-push "exp(a) exp(b)")
  (dm-at "exp(b" 1)
  (call-interactively 'maf-merge)
  (cl-assert (string= (dm-top) "exp(a + b)"))
  (calc-pop (calc-stack-size))

  ;; The gathered coefficients stay as the rules built them: the rule
  ;; marks its result, and calc does not simplify across the mark.
  (maf-push "2 x + 3 x")
  (dm-at "3" 1)
  (call-interactively 'maf-merge)
  (cl-assert (string= (dm-top) "x*(3 + 2)"))
  (calc-pop (calc-stack-size))

  ;; --- targets ----------------------------------------------------

  ;; At home, where point names no part, the top entry is the subject
  ;; and the rules fire at the first site they reach — one rule per
  ;; invocation, so the second logarithm is left for the next press.
  (maf-push "ln(a b) + ln(c d)")
  (goto-char (point-max))
  (call-interactively 'maf-distribute)
  (cl-assert (string= (dm-top) "ln(b) + ln(a) + ln(c d)"))
  (calc-pop (calc-stack-size))

  ;; At home with a selection standing, the rewrite goes to it and
  ;; clears it, rather than acting on stack level 1. The product is
  ;; selected, not one factor: a selection is taken as given, so it has
  ;; to be the node the rule marks.
  (maf-push "ln(a b)")
  (maf-push "1 + 2")
  (progn (dm-at "a" 1) (calc-select-here nil) (calc-select-more nil)
         (goto-char (point-max)))
  (call-interactively 'maf-distribute)
  (cl-assert (string= (dm-top 2) "ln(b) + ln(a)"))
  (cl-assert (string= (dm-top 1) "1 + 2"))
  (cl-assert (null (calc-top 2 'sel)))
  (calc-pop (calc-stack-size))

  ;; Below the top of the stack: the entry at point is the one acted on.
  (maf-push "ln(a b)")
  (maf-push "1 + 2")
  (dm-at "a" 1)
  (call-interactively 'maf-distribute)
  (cl-assert (string= (dm-top 2) "ln(b) + ln(a)"))
  (cl-assert (string= (dm-top 1) "1 + 2"))
  (calc-pop (calc-stack-size))

  ;; Point widens outward to the innermost formula a rule reaches, but
  ;; an active selection does not: the mark stays where it was put. On
  ;; the bare a of x*(a + b) the product distributes; with that same a
  ;; selected by hand, no rule matches it and the entry stands.
  (maf-push "x*(a + b)")
  (progn (dm-at "a" 1) (calc-select-here nil))
  (call-interactively 'maf-distribute)
  (cl-assert (string= (dm-top) "x*(a + b)"))
  (cl-assert (= (calc-stack-size) 1))
  ;; Doing nothing means nothing: the selection is still standing.
  (cl-assert (equal (calc-top 1 'sel) '(var a var-a)))
  (progn (calc-unselect 1) (calc-pop (calc-stack-size)))

  ;; An equation is rewritten on the side point is in; the other side
  ;; is untouched.
  (maf-push "ln(a b) = c")
  (dm-at "a" 1)
  (call-interactively 'maf-distribute)
  (cl-assert (string= (dm-top) "ln(b) + ln(a) = c"))
  (calc-pop (calc-stack-size))

  (maf-push "c = ln(a b)")
  (dm-at "a" 1)
  (call-interactively 'maf-distribute)
  (cl-assert (string= (dm-top) "c = ln(b) + ln(a)"))
  (calc-pop (calc-stack-size))

  ;; --- degenerate cases -------------------------------------------

  ;; Nothing to spread: the entry stands, and nothing is pushed or
  ;; popped for a value only normalization would have changed.
  (maf-push "x + y")
  (dm-at "y" 1)
  (call-interactively 'maf-distribute)
  (cl-assert (string= (dm-top) "x + y"))
  (cl-assert (= (calc-stack-size) 1))
  (calc-pop (calc-stack-size))

  ;; Likewise with nothing to gather — a sum whose terms share no
  ;; factor is left exactly as written, not reordered.
  (maf-push "x + y")
  (dm-at "y" 1)
  (call-interactively 'maf-merge)
  (cl-assert (string= (dm-top) "x + y"))
  (cl-assert (= (calc-stack-size) 1))
  (calc-pop (calc-stack-size))

  ;; An empty stack is not an error.
  (call-interactively 'maf-distribute)
  (call-interactively 'maf-merge)
  (cl-assert (= (calc-stack-size) 0))

  ;; --- undo and keys ----------------------------------------------

  ;; A single undo reverts the rewrite, stack and point together.
  (maf-push "ln(a b)")
  (dm-at "a" 1)
  (call-interactively 'maf-distribute)
  (call-interactively 'maf-undo)
  (cl-assert (string= (dm-top) "ln(a b)"))
  (cl-assert (eq (char-after) ?a))
  (calc-pop (calc-stack-size))

  ;; The bindings reach the commands through the keymap.
  (maf-push "ln(a b)")
  (dm-at "a" 1)
  (execute-kbd-macro (kbd "j D"))
  (cl-assert (string= (dm-top) "ln(b) + ln(a)"))
  (calc-pop (calc-stack-size))

  (maf-push "ln(a) + ln(b)")
  (dm-at "ln(b" 1)
  (execute-kbd-macro (kbd "j M"))
  (cl-assert (string= (dm-top) "ln(a b)"))
  (calc-pop (calc-stack-size)))
