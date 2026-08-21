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

(defun dm-value (expr)
  "Evaluate EXPR at a=2, b=4, x=4, y=2 and format the result.
For the power-merge rules, where the fault is in the value rather than
the shape: the merged form has to agree with the entry it came from.
Both sides are forced to float, so an exact 1 and a computed 1. read
the same."
  (math-format-value
   (math-normalize
    (list 'calcFunc-float
          (math-evaluate-expr
           (seq-reduce (lambda (e pair)
                         (math-expr-subst e (car pair) (cdr pair)))
                       '(((var a var-a) . 2) ((var b var-b) . 4)
                         ((var x var-x) . 4) ((var y var-y) . 2))
                       expr))))))

(defvar dm-quotient (car (math-read-exprs "a^x / b^x")))
(defvar dm-quotient2 (car (math-read-exprs "a^x / b^y")))
(defvar dm-product (car (math-read-exprs "a^x * b^y")))

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

  ;; The helper is finished off whatever mode is in effect outside the
  ;; command. With simplification turned off — maf binds a key for it —
  ;; evaluating it under the ambient mode would leave calc's internal
  ;; expandpow( ) sitting on the stack instead of the polynomial.
  (maf-push "(x + y)^2")
  (dm-at "x" 1)
  (let ((calc-simplify-mode 'none))
    (call-interactively 'maf-distribute))
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

  ;; The merged exp lands as e^(a + b) — the maf-e-power module
  ;; rewrites the committed result into the power form.
  (maf-push "exp(a) exp(b)")
  (dm-at "exp(b" 1)
  (call-interactively 'maf-merge)
  (cl-assert (string= (dm-top) "e^(a + b)"))
  (calc-pop (calc-stack-size))

  ;; The gathered coefficients stay as the rules built them: the rule
  ;; marks its result, and calc does not simplify across the mark.
  (maf-push "2 x + 3 x")
  (dm-at "3" 1)
  (call-interactively 'maf-merge)
  (cl-assert (string= (dm-top) "x*(2 + 3)"))
  (calc-pop (calc-stack-size))

  ;; --- merge: calc's wrong-base division rules --------------------

  ;; Two of calc's MergeRules read the numerator's base as b where
  ;; every sibling reads a, so with the denominator marked the answer
  ;; comes out b/b = 1 — the value gone. maf corrects the two, and both
  ;; ends of the quotient now agree.
  (maf-push "a^x / b^x")
  (dm-at "b" 1)
  (call-interactively 'maf-merge)
  (cl-assert (string= (dm-top) "(a / b)^x"))
  (calc-pop (calc-stack-size))

  (maf-push "a^x / b^x")
  (dm-at "a" 1)
  (call-interactively 'maf-merge)
  (cl-assert (string= (dm-top) "(a / b)^x"))
  (calc-pop (calc-stack-size))

  ;; The value is the point, so check it rather than the shape: put
  ;; numbers through the merged form and the original and compare.
  ;; Numeric bases cannot be used directly — the rewriter normalizes
  ;; its input, folding 2^3 to 8 before any rule sees a power.
  (maf-push "a^x / b^x")
  (dm-at "b" 1)
  (call-interactively 'maf-merge)
  (cl-assert (string= (dm-value (calc-top 1 'full)) (dm-value dm-quotient)))
  (calc-pop (calc-stack-size))

  ;; The differing-exponent rules carry a second upstream fault, in the
  ;; exponent arithmetic rather than the base: gathering a^x and b^y
  ;; under one power of x needs b^(y/x), and calc subtracts where it
  ;; must divide. At a=2 b=4 x=4 y=2 the entry is 1 and calc answers
  ;; 1048576. maf corrects these alongside the wrong-base pair.
  (maf-push "a^x / b^y")
  (dm-at "b^y" 1)
  (call-interactively 'maf-merge)
  (cl-assert (string= (dm-value (calc-top 1 'full)) (dm-value dm-quotient2)))
  (calc-pop (calc-stack-size))

  (maf-push "a^x / b^y")
  (dm-at "a^x" 1)
  (call-interactively 'maf-merge)
  (cl-assert (string= (dm-value (calc-top 1 'full)) (dm-value dm-quotient2)))
  (calc-pop (calc-stack-size))

  ;; The product rule of the same family.
  (maf-push "a^x * b^y")
  (dm-at "b^y" 1)
  (call-interactively 'maf-merge)
  (cl-assert (string= (dm-value (calc-top 1 'full)) (dm-value dm-product)))
  (calc-pop (calc-stack-size))

  ;; --- only the targeted site changes -----------------------------

  ;; The rewrite is scoped to the formula the rule matches, and the
  ;; rest of the entry is carried over untouched. Merging the two
  ;; logarithms must not also collapse the unrelated powers, which
  ;; normalizing the whole entry would do — stock calc-sel-merge
  ;; answers ln(a b) + x^(p + q) here.
  (maf-push "ln(a) + ln(b) + x^p x^q")
  (dm-at "ln(b" 1)
  (call-interactively 'maf-merge)
  (cl-assert (string= (dm-top) "ln(a b) + x^p x^q"))
  (calc-pop (calc-stack-size))

  ;; Likewise the coefficient ordering: it applies to the product the
  ;; rules built, named by the marker they carried into it, not to a
  ;; product the user wrote and the command never touched.
  (maf-push "ln(x^2) + y*3")
  (dm-at "x" 1)
  (call-interactively 'maf-distribute)
  (cl-assert (string= (dm-top) "2 ln(x) + y 3"))
  (calc-pop (calc-stack-size))

  ;; --- targets ----------------------------------------------------

  ;; At home, where point names no part, the top entry is the subject
  ;; and the rules fire at the first site they reach — one rule per
  ;; invocation, so the second logarithm is left for the next press.
  ;; Point stays home rather than following the marked part into the
  ;; entry, as after any other command run from there.
  (maf-push "ln(a b) + ln(c d)")
  (goto-char (point-max))
  (call-interactively 'maf-distribute)
  (cl-assert (string= (dm-top) "ln(b) + ln(a) + ln(c d)"))
  (cl-assert (maf--at-home-p))
  (calc-pop (calc-stack-size))

  ;; Home walks marked candidates like everywhere else, rather than
  ;; handing calc a bare entry to match where it can. That reading
  ;; cannot be used: the sign rules match every expression there is, so
  ;; an unmarked sqrt(x) comes back as sqrt(-1) sqrt(-x). Nothing to
  ;; distribute means the entry stands.
  (maf-push "sqrt(x)")
  (goto-char (point-max))
  (call-interactively 'maf-distribute)
  (cl-assert (string= (dm-top) "sqrt(x)"))
  (cl-assert (= (calc-stack-size) 1))
  (calc-pop (calc-stack-size))

  (maf-push "sqrt(9)")
  (goto-char (point-max))
  (call-interactively 'maf-distribute)
  (cl-assert (string= (dm-top) "sqrt(9)"))
  (calc-pop (calc-stack-size))

  (maf-push "exp(x)^2")
  (goto-char (point-max))
  (call-interactively 'maf-distribute)
  (cl-assert (string= (dm-top) "exp(x)^2"))
  (calc-pop (calc-stack-size))

  ;; The walk also reaches what a bare entry misses: normalizing on the
  ;; way into the rewriter folds x^a x^b to x^(a + b) before MergeRules
  ;; ever sees it, so the unmarked reading found nothing to do here.
  (maf-push "x^a x^b")
  (goto-char (point-max))
  (call-interactively 'maf-merge)
  (cl-assert (string= (dm-top) "x^(b + a)"))
  (cl-assert (maf--at-home-p))
  (calc-pop (calc-stack-size))

  ;; Merged at home the exp product lands in the power form too (see
  ;; the maf-e-power note above).
  (maf-push "exp(a) exp(b)")
  (goto-char (point-max))
  (call-interactively 'maf-merge)
  (cl-assert (string= (dm-top) "e^(b + a)"))
  (calc-pop (calc-stack-size))

  ;; A fraction distributes at home too, on the same substitution the
  ;; on-entry path uses. Point stays home, so nothing has run calc's
  ;; selection machinery over the entry, and its atoms are still bare:
  ;; the division formats tight, as the stack line has it. (On the
  ;; entry, anchoring point encases the atoms, and the same value reads
  ;; back as "1 / 4".)
  (maf-push "sqrt(3:4)")
  (goto-char (point-max))
  (call-interactively 'maf-distribute)
  (cl-assert (string= (dm-top) "sqrt(1/4) sqrt(3)"))
  (cl-assert (maf--at-home-p))
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

  ;; A selection standing anywhere outranks point, as it does in
  ;; `maf--resolve-context' — it is the more deliberate gesture. With
  ;; the product of entry 2 selected and point away on entry 1, the
  ;; rewrite goes to the selection and leaves the entry point sits on
  ;; alone. Taking point instead would both rewrite the wrong entry and
  ;; leave the selection standing.
  (maf-push "ln(a b)")
  (maf-push "ln(c d)")
  (progn (dm-at "a" 1) (calc-select-here nil) (calc-select-more nil)
         (dm-at "c" 1))
  (call-interactively 'maf-distribute)
  (cl-assert (string= (dm-top 2) "ln(b) + ln(a)"))
  (cl-assert (string= (dm-top 1) "ln(c d)"))
  (cl-assert (null (calc-top 2 'sel)))
  (calc-pop (calc-stack-size))

  ;; --- targets: anywhere on the entry -----------------------------

  ;; A marker is always a part of the formula being rewritten, never
  ;; that formula itself, so point standing on a function name or an
  ;; operator names the site and the marker is one level in. Every
  ;; position on the entry reaches the same rewrite.
  (maf-push "ln(x^2)")
  (dm-at "l" 1)
  (call-interactively 'maf-distribute)
  (cl-assert (string= (dm-top) "2 ln(x)"))
  (calc-pop (calc-stack-size))

  (maf-push "ln(x^2)")
  (progn (goto-char (point-min)) (search-forward ")") (backward-char 1))
  (call-interactively 'maf-distribute)
  (cl-assert (string= (dm-top) "2 ln(x)"))
  (calc-pop (calc-stack-size))

  ;; The other way round: the node under point is a part, but not the
  ;; part the rule marks. On the x of x*(a + b) it is the sum that the
  ;; product rule marks, so the walk tries the siblings at that site.
  (maf-push "x*(a + b)")
  (dm-at "x" 1)
  (call-interactively 'maf-distribute)
  (cl-assert (string= (dm-top) "x b + x a"))
  (calc-pop (calc-stack-size))

  (maf-push "x*(a + b)")
  (dm-at "*" 1)
  (call-interactively 'maf-distribute)
  (cl-assert (string= (dm-top) "x b + x a"))
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
