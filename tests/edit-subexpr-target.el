;; Inside a maf-edit session, L/Q/| name their argument the way maf's
;; subexpr target names its own on the stack: the character under point
;; picks a sub-expression, and the call is written around that
;; (`maf-editplus--subexpr-node'). A step passes when it raises no error.
;;
;; The rule is the stack's rule. Point on an operand takes that operand;
;; point on an operator — or on a delimiter — takes the node the
;; operator heads, so the same keypress reaches a bigger piece by
;; standing one character to the left. An operator's padding space is
;; not the operator: with a complete unit ending at point it means that
;; unit, exactly as the end of the entry does. The parse is of the
;; text, not of a value: it is calc's precedence, but nothing in it
;; can fail, since the text is being typed.
;;
;; The end of the entry is the one place the old rule still holds —
;; there is no character under point there, and the term behind point is
;; the argument. That half lives in `edit-wrap-ln.el'.

(maf-step
  ;; An operand takes itself, and the entry around it is untouched.
  (call-interactively 'maf-edit-add-entry-below)
  (progn (execute-kbd-macro "a+b*c") nil)
  (progn (maf-edit-move-beginning-of-line 1) (forward-char 2) nil)
  (call-interactively 'maf-editplus-wrap-ln)
  (cl-assert (equal (maf-edit--entry-text (maf-editplus--entry-at-point))
                    "a+ln(b)*c"))
  ;; Point is left on the call it just wrote — the node under point is
  ;; now that call — so pressing again nests rather than reaching past
  ;; it to the product.
  (call-interactively 'maf-editplus-wrap-sqrt)
  (cl-assert (equal (maf-edit--entry-text (maf-editplus--entry-at-point))
                    "a+sqrt(ln(b))*c"))
  (call-interactively 'maf-edit-discard)

  ;; One character to the left is the `*', and the product it heads is
  ;; the argument: the operator is how a bigger piece is named.
  (call-interactively 'maf-edit-add-entry-below)
  (progn (execute-kbd-macro "a+b*c") nil)
  (progn (maf-edit-move-beginning-of-line 1) (forward-char 3) nil)
  (call-interactively 'maf-editplus-wrap-ln)
  (cl-assert (equal (maf-edit--entry-text (maf-editplus--entry-at-point))
                    "a+ln(b*c)"))
  (call-interactively 'maf-edit-discard)

  ;; And the `+' heads the whole sum, the product being the tighter of
  ;; the two — calc's precedence, read off the text.
  (call-interactively 'maf-edit-add-entry-below)
  (progn (execute-kbd-macro "a+b*c") nil)
  (progn (maf-edit-move-beginning-of-line 1) (forward-char 1) nil)
  (call-interactively 'maf-editplus-wrap-ln)
  (cl-assert (equal (maf-edit--entry-text (maf-editplus--entry-at-point))
                    "ln(a+b*c)"))
  (call-interactively 'maf-edit-discard)

  ;; A power binds tighter than the sum and looser than its own base:
  ;; the `^' names 2^x, and the exponent names itself.
  (call-interactively 'maf-edit-add-entry-below)
  (progn (execute-kbd-macro "2^x+1") nil)
  (progn (maf-edit-move-beginning-of-line 1) (forward-char 1) nil)
  (call-interactively 'maf-editplus-wrap-ln)
  (cl-assert (equal (maf-edit--entry-text (maf-editplus--entry-at-point))
                    "ln(2^x)+1"))
  (call-interactively 'maf-edit-discard)

  (call-interactively 'maf-edit-add-entry-below)
  (progn (execute-kbd-macro "2^x+1") nil)
  (progn (maf-edit-move-beginning-of-line 1) (forward-char 2) nil)
  (call-interactively 'maf-editplus-wrap-ln)
  (cl-assert (equal (maf-edit--entry-text (maf-editplus--entry-at-point))
                    "2^ln(x)+1"))
  (call-interactively 'maf-edit-discard)

  ;; A call is one node with its argument inside it: the name takes the
  ;; call, and the argument takes itself.
  (call-interactively 'maf-edit-add-entry-below)
  (progn (execute-kbd-macro "27/sqrt(3)") nil)
  (progn (maf-edit-move-beginning-of-line 1) (forward-char 3) nil)
  (call-interactively 'maf-editplus-wrap-ln)
  (cl-assert (equal (maf-edit--entry-text (maf-editplus--entry-at-point))
                    "27/ln(sqrt(3))"))
  (call-interactively 'maf-edit-discard)

  (call-interactively 'maf-edit-add-entry-below)
  (progn (execute-kbd-macro "f(x,y)+1") nil)
  (progn (maf-edit-move-beginning-of-line 1) (forward-char 4) nil)
  (call-interactively 'maf-editplus-wrap-ln)
  (cl-assert (equal (maf-edit--entry-text (maf-editplus--entry-at-point))
                    "f(x,ln(y))+1"))
  (call-interactively 'maf-edit-discard)

  ;; The call's closer is the one character that names nothing: point
  ;; in front of it is the tail of the argument being typed — electric
  ;; parens hold it there — so the term behind point is the subject,
  ;; exactly as at the end of the entry.
  (call-interactively 'maf-edit-add-entry-below)
  (progn (execute-kbd-macro "27/sqrt(3)") nil)
  (progn (maf-edit-move-beginning-of-line 1) (forward-char 9) nil)
  (call-interactively 'maf-editplus-wrap-ln)
  (cl-assert (equal (maf-edit--entry-text (maf-editplus--entry-at-point))
                    "27/sqrt(ln(3))"))
  (call-interactively 'maf-edit-discard)

  ;; A vector is structure: its bracket names the whole thing, an
  ;; element names itself, and neither press disturbs the other.
  (call-interactively 'maf-edit-add-entry-below)
  (progn (execute-kbd-macro "[1,2]+x") nil)
  (progn (maf-edit-move-beginning-of-line 1) nil)
  (call-interactively 'maf-editplus-wrap-ln)
  (cl-assert (equal (maf-edit--entry-text (maf-editplus--entry-at-point))
                    "ln([1,2])+x"))
  (call-interactively 'maf-edit-discard)

  (call-interactively 'maf-edit-add-entry-below)
  (progn (execute-kbd-macro "[1,2]+x") nil)
  (progn (maf-edit-move-beginning-of-line 1) (forward-char 1) nil)
  (call-interactively 'maf-editplus-wrap-ln)
  (cl-assert (equal (maf-edit--entry-text (maf-editplus--entry-at-point))
                    "[ln(1),2]+x"))
  (call-interactively 'maf-edit-discard)

  ;; A pair of bare parentheses is punctuation, not structure. Its
  ;; opener names the expression inside it, and the call supplies the
  ;; grouping the pair was there for, so the pair goes rather than
  ;; ln((a+b)) being written.
  (call-interactively 'maf-edit-add-entry-below)
  (progn (execute-kbd-macro "(a+b)*c") nil)
  (progn (maf-edit-move-beginning-of-line 1) nil)
  (call-interactively 'maf-editplus-wrap-ln)
  (cl-assert (equal (maf-edit--entry-text (maf-editplus--entry-at-point))
                    "ln(a+b)*c"))
  (call-interactively 'maf-edit-discard)

  ;; On the closer the unit just typed wins, as at a call's closer —
  ;; electric parens hold point there for the whole time the group's
  ;; tail is being typed, so (a+b|) means b, the smallest complete
  ;; expression behind point. The group keeps its opener.
  (call-interactively 'maf-edit-add-entry-below)
  (progn (execute-kbd-macro "(a+b)*c") nil)
  (progn (maf-edit-move-beginning-of-line 1) (forward-char 4) nil)
  (call-interactively 'maf-editplus-wrap-ln)
  (cl-assert (equal (maf-edit--entry-text (maf-editplus--entry-at-point))
                    "(a+ln(b))*c"))
  (call-interactively 'maf-edit-discard)

  ;; A group still being typed keeps both of its own characters: the
  ;; closer that would make the pair redundant is not there yet, and
  ;; deleting the opener alone would restructure the entry.
  (call-interactively 'maf-edit-add-entry-below)
  (progn (insert "(a+b") nil)
  (progn (maf-edit-move-beginning-of-line 1) nil)
  (call-interactively 'maf-editplus-wrap-ln)
  (cl-assert (equal (maf-edit--entry-text (maf-editplus--entry-at-point))
                    "(ln(a+b)"))
  (call-interactively 'maf-edit-discard)

  ;; Juxtaposition is multiplication, so the space between two factors
  ;; is an operator glyph like any other and names the product.
  (call-interactively 'maf-edit-add-entry-below)
  (progn (execute-kbd-macro "2 x+1") nil)
  (progn (maf-edit-move-beginning-of-line 1) (forward-char 1) nil)
  (call-interactively 'maf-editplus-wrap-ln)
  (cl-assert (equal (maf-edit--entry-text (maf-editplus--entry-at-point))
                    "ln(2 x)+1"))
  (call-interactively 'maf-edit-discard)

  ;; A character the scan has no reading for is an atom of its own
  ;; (`maf-editplus--op-strings'), so the space in front of it is a
  ;; juxtaposed product's space too — the tokenizer's classification
  ;; tells operand from operator, not a list of operand spellings.
  (call-interactively 'maf-edit-add-entry-below)
  (progn (insert "x @y") nil)
  (progn (maf-edit-move-beginning-of-line 1) (forward-char 1) nil)
  (call-interactively 'maf-editplus-wrap-ln)
  (cl-assert (equal (maf-edit--entry-text (maf-editplus--entry-at-point))
                    "ln(x @y)"))
  (call-interactively 'maf-edit-discard)

  ;; An operator's padding space is no operator of its own: a complete
  ;; unit ending at point is the argument there, exactly as at the end
  ;; of the entry. The sum stays reachable from the `+' itself.
  (call-interactively 'maf-edit-add-entry-below)
  (progn (execute-kbd-macro "2 x + 1") nil)
  (progn (maf-edit-move-beginning-of-line 1) (forward-char 3) nil)
  (call-interactively 'maf-editplus-wrap-ln)
  (cl-assert (equal (maf-edit--entry-text (maf-editplus--entry-at-point))
                    "2 ln(x) + 1"))
  (call-interactively 'maf-edit-discard)

  ;; From the space after the operator nothing complete ends at point
  ;; — the operator is what is behind it — and the node holds.
  (call-interactively 'maf-edit-add-entry-below)
  (progn (execute-kbd-macro "2 x + 1") nil)
  (progn (maf-edit-move-beginning-of-line 1) (forward-char 5) nil)
  (call-interactively 'maf-editplus-wrap-ln)
  (cl-assert (equal (maf-edit--entry-text (maf-editplus--entry-at-point))
                    "ln(2 x + 1)"))
  (call-interactively 'maf-edit-discard)

  ;; The scene that asked for the rule: a re-edited formula, padded the
  ;; way the stack renders it, point parked just after a factor.
  (call-interactively 'maf-edit-add-entry-below)
  (progn (execute-kbd-macro "6 x + 12 = 18 y + 6") nil)
  (progn (maf-edit-move-beginning-of-line 1) (forward-char 15) nil)
  (call-interactively 'maf-editplus-wrap-ln)
  (cl-assert (equal (maf-edit--entry-text (maf-editplus--entry-at-point))
                    "6 x + 12 = 18 ln(y) + 6"))
  (call-interactively 'maf-edit-discard)

  ;; A relation binds loosest of all: its own sign names both sides.
  (call-interactively 'maf-edit-add-entry-below)
  (progn (execute-kbd-macro "a=b+1") nil)
  (progn (maf-edit-move-beginning-of-line 1) (forward-char 1) nil)
  (call-interactively 'maf-editplus-wrap-ln)
  (cl-assert (equal (maf-edit--entry-text (maf-editplus--entry-at-point))
                    "ln(a=b+1)"))
  (call-interactively 'maf-edit-discard)

  ;; An interval's delimiters are values, not punctuation: `[' says the
  ;; bound is included and `(' that it is not, and calc reads `..' only
  ;; between them — it is not an operator at all. So the pair stays
  ;; whichever way it was written, from either end and from the dots,
  ;; and what would otherwise be written — ln(1 .. 2) — does not parse.
  (call-interactively 'maf-edit-add-entry-below)
  (progn (insert "(1 .. 2)+x") nil)
  (progn (maf-edit-move-beginning-of-line 1) nil)
  (call-interactively 'maf-editplus-wrap-ln)
  (cl-assert (equal (maf-edit--entry-text (maf-editplus--entry-at-point))
                    "ln((1 .. 2))+x"))
  (call-interactively 'maf-edit-discard)

  (call-interactively 'maf-edit-add-entry-below)
  (progn (insert "(1 .. 2)+x") nil)
  (progn (maf-edit-move-beginning-of-line 1) (forward-char 3) nil)
  (call-interactively 'maf-editplus-wrap-ln)
  (cl-assert (equal (maf-edit--entry-text (maf-editplus--entry-at-point))
                    "ln((1 .. 2))+x"))
  (call-interactively 'maf-edit-discard)

  ;; A mixed pair is the notation working, not a group left broken, so
  ;; both halves are kept exactly as they stand.
  (call-interactively 'maf-edit-add-entry-below)
  (progn (insert "(1 .. 2]+x") nil)
  (progn (maf-edit-move-beginning-of-line 1) nil)
  (call-interactively 'maf-editplus-wrap-ln)
  (cl-assert (equal (maf-edit--entry-text (maf-editplus--entry-at-point))
                    "ln((1 .. 2])+x"))
  (call-interactively 'maf-edit-discard)

  ;; An endpoint is still a node of its own inside the interval.
  (call-interactively 'maf-edit-add-entry-below)
  (progn (insert "(1 .. 2)+x") nil)
  (progn (maf-edit-move-beginning-of-line 1) (forward-char 1) nil)
  (call-interactively 'maf-editplus-wrap-ln)
  (cl-assert (equal (maf-edit--entry-text (maf-editplus--entry-at-point))
                    "(ln(1) .. 2)+x"))
  (call-interactively 'maf-edit-discard)

  ;; And what commits is the interval calc reads, bounds and all.
  (call-interactively 'maf-edit-add-entry-below)
  (progn (insert "(1 .. 2]") nil)
  (progn (maf-edit-move-beginning-of-line 1) nil)
  (call-interactively 'maf-editplus-wrap-ln)
  (call-interactively 'maf-edit-commit)
  (cl-assert (equal (calc-top 1) '(calcFunc-ln (intv 1 1 2))))
  (calc-pop (calc-stack-size))

  ;; A number is one atom however calc spells it. The `-' of an
  ;; exponent is not the operator it looks like, and neither the radix
  ;; mark nor a missing leading zero breaks the number in half.
  (call-interactively 'maf-edit-add-entry-below)
  (progn (insert "1e-3+2") nil)
  (progn (maf-edit-move-beginning-of-line 1) (forward-char 1) nil)
  (call-interactively 'maf-editplus-wrap-ln)
  (cl-assert (equal (maf-edit--entry-text (maf-editplus--entry-at-point))
                    "ln(1e-3)+2"))
  (call-interactively 'maf-edit-discard)

  (call-interactively 'maf-edit-add-entry-below)
  (progn (insert "16#ff+2") nil)
  (progn (maf-edit-move-beginning-of-line 1) (forward-char 1) nil)
  (call-interactively 'maf-editplus-wrap-ln)
  (cl-assert (equal (maf-edit--entry-text (maf-editplus--entry-at-point))
                    "ln(16#ff)+2"))
  (call-interactively 'maf-edit-discard)

  (call-interactively 'maf-edit-add-entry-below)
  (progn (insert "1+.5") nil)
  (progn (maf-edit-move-beginning-of-line 1) (forward-char 2) nil)
  (call-interactively 'maf-editplus-wrap-ln)
  (cl-assert (equal (maf-edit--entry-text (maf-editplus--entry-at-point))
                    "1+ln(.5)"))
  (call-interactively 'maf-edit-discard)

  ;; The exponent rule is a number's alone: a marker inside a name is
  ;; part of that name, and the subtraction after it is a subtraction.
  (call-interactively 'maf-edit-add-entry-below)
  (progn (insert "ae-3+2") nil)
  (progn (maf-edit-move-beginning-of-line 1) nil)
  (call-interactively 'maf-editplus-wrap-ln)
  (cl-assert (equal (maf-edit--entry-text (maf-editplus--entry-at-point))
                    "ln(ae)-3+2"))
  (call-interactively 'maf-edit-discard)

  ;; And the value that commits is the number that was written, which
  ;; is the whole point of not splitting it.
  (call-interactively 'maf-edit-add-entry-below)
  (progn (insert "1e-3") nil)
  (progn (maf-edit-move-beginning-of-line 1) nil)
  (call-interactively 'maf-editplus-wrap-sqrt)
  (call-interactively 'maf-edit-commit)
  (cl-assert (equal (calc-top 1) '(calcFunc-sqrt (float 1 -3))))
  (calc-pop (calc-stack-size))

  ;; The operators calc spells with two characters are one boundary,
  ;; not two: `==' is its second spelling of `=', and `**' is the power.
  (call-interactively 'maf-edit-add-entry-below)
  (progn (insert "a == b+1") nil)
  (progn (maf-edit-move-beginning-of-line 1) (forward-char 2) nil)
  (call-interactively 'maf-editplus-wrap-ln)
  (cl-assert (equal (maf-edit--entry-text (maf-editplus--entry-at-point))
                    "ln(a == b+1)"))
  (call-interactively 'maf-edit-discard)

  (call-interactively 'maf-edit-add-entry-below)
  (progn (insert "2 ** 3 + 1") nil)
  (progn (maf-edit-move-beginning-of-line 1) (forward-char 2) nil)
  (call-interactively 'maf-editplus-wrap-ln)
  (cl-assert (equal (maf-edit--entry-text (maf-editplus--entry-at-point))
                    "ln(2 ** 3) + 1"))
  (call-interactively 'maf-edit-discard)

  ;; The logical pair binds looser than the relations and `&&' tighter
  ;; than `||', as calc reads them: a || b && c is a or (b and c).
  (call-interactively 'maf-edit-add-entry-below)
  (progn (insert "a || b && c") nil)
  (progn (maf-edit-move-beginning-of-line 1) (forward-char 7) nil)
  (call-interactively 'maf-editplus-wrap-ln)
  (cl-assert (equal (maf-edit--entry-text (maf-editplus--entry-at-point))
                    "a || ln(b && c)"))
  (call-interactively 'maf-edit-discard)

  ;; `mod' is calc's one word operator — an identifier to read, an
  ;; operator to parse — and it binds tighter than the power around
  ;; it: 2^3 mod 5 raises 2 to (3 mod 5), so that is the node the word
  ;; names. Only where the text is calc's own syntax, which is what
  ;; the binding says: under an input dialect the letters may be
  ;; something else entirely, and the press is made inside the let so
  ;; the command sees it.
  (call-interactively 'maf-edit-add-entry-below)
  (progn (insert "2^3 mod 5")
         (maf-edit-move-beginning-of-line 1)
         (forward-char 4)
         (let ((maf-edit-parse-text-function #'identity))
           (call-interactively 'maf-editplus-wrap-ln))
         nil)
  (cl-assert (equal (maf-edit--entry-text (maf-editplus--entry-at-point))
                    "2^ln(3 mod 5)"))
  (call-interactively 'maf-edit-discard)

  ;; A name that merely begins with the word is the name it looks like.
  (call-interactively 'maf-edit-add-entry-below)
  (progn (insert "modulus+1")
         (maf-edit-move-beginning-of-line 1)
         (let ((maf-edit-parse-text-function #'identity))
           (call-interactively 'maf-editplus-wrap-ln))
         nil)
  (cl-assert (equal (maf-edit--entry-text (maf-editplus--entry-at-point))
                    "ln(modulus)+1"))
  (call-interactively 'maf-edit-discard)

  ;; And the word's padding is padding like any operator's, not the
  ;; start of an operand: the unit ending at point is the argument,
  ;; and the mod node keeps its ground from its own letters.
  (call-interactively 'maf-edit-add-entry-below)
  (progn (insert "2 x mod y")
         (maf-edit-move-beginning-of-line 1)
         (forward-char 3)
         (let ((maf-edit-parse-text-function #'identity))
           (call-interactively 'maf-editplus-wrap-ln))
         nil)
  (cl-assert (equal (maf-edit--entry-text (maf-editplus--entry-at-point))
                    "2 ln(x) mod y"))
  (call-interactively 'maf-edit-discard)

  ;; And under the editvars dialect it is no operator at all: there a
  ;; bare run of letters is a run of factors, so the word commits as
  ;; the product m o d and the scan must not name a node the commit
  ;; does not agree exists. The letters are one atom to the scan,
  ;; which is the grouping the press asks for either way.
  (call-interactively 'maf-edit-add-entry-below)
  (progn (insert "a mod b")
         (maf-edit-move-beginning-of-line 1)
         (forward-char 2)
         (let ((maf-edit-parse-text-function #'maf-editvars-parse-text))
           (call-interactively 'maf-editplus-wrap-ln))
         nil)
  (cl-assert (equal (maf-edit--entry-text (maf-editplus--entry-at-point))
                    "a ln(mod) b"))
  (call-interactively 'maf-edit-discard)

  ;; Integer division is an operator like any other.
  (call-interactively 'maf-edit-add-entry-below)
  (progn (insert "6 \\ 4 + 1") nil)
  (progn (maf-edit-move-beginning-of-line 1) (forward-char 2) nil)
  (call-interactively 'maf-editplus-wrap-ln)
  (cl-assert (equal (maf-edit--entry-text (maf-editplus--entry-at-point))
                    "ln(6 \\ 4) + 1"))
  (call-interactively 'maf-edit-discard)

  ;; A name the editvars dialect quotes, {foo}, is a brace group to
  ;; the scan, and so one unit with its braces.
  (call-interactively 'maf-edit-add-entry-below)
  (progn (insert "{foo}+1") nil)
  (progn (maf-edit-move-beginning-of-line 1) nil)
  (call-interactively 'maf-editplus-wrap-ln)
  (cl-assert (equal (maf-edit--entry-text (maf-editplus--entry-at-point))
                    "ln({foo})+1"))
  (call-interactively 'maf-edit-discard)

  ;; And the pieces they name commit as the operators calc reads. The
  ;; `&&' is looser than the sum, so it names the whole of it — which
  ;; is the precedence being checked as much as the spelling is.
  (call-interactively 'maf-edit-add-entry-below)
  (progn (insert "a && b + 1") nil)
  (progn (maf-edit-move-beginning-of-line 1) (forward-char 2) nil)
  (call-interactively 'maf-editplus-wrap-ln)
  (call-interactively 'maf-edit-commit)
  (cl-assert (equal (calc-top 1)
                    '(calcFunc-ln (calcFunc-land (var a var-a)
                                                 (+ (var b var-b) 1)))))
  (calc-pop (calc-stack-size))

  ;; `calc-multiplication-has-precedence' is on by default, and there
  ;; `*' binds tighter than `/': a/b*c is a/(b*c), so the `/' names
  ;; the whole quotient and the `*' names the product inside it. The
  ;; two answers are different formulas, not two spellings of one.
  (call-interactively 'maf-edit-add-entry-below)
  (progn (execute-kbd-macro "a/b*c") nil)
  (progn (maf-edit-move-beginning-of-line 1) (forward-char 1) nil)
  (call-interactively 'maf-editplus-wrap-ln)
  (cl-assert (equal (maf-edit--entry-text (maf-editplus--entry-at-point))
                    "ln(a/b*c)"))
  (call-interactively 'maf-edit-discard)

  (call-interactively 'maf-edit-add-entry-below)
  (progn (execute-kbd-macro "a/b*c") nil)
  (progn (maf-edit-move-beginning-of-line 1) (forward-char 3) nil)
  (call-interactively 'maf-editplus-wrap-ln)
  (cl-assert (equal (maf-edit--entry-text (maf-editplus--entry-at-point))
                    "a/ln(b*c)"))
  (call-interactively 'maf-edit-discard)

  ;; Which also makes `*' fold right, while `/' still folds left.
  (call-interactively 'maf-edit-add-entry-below)
  (progn (execute-kbd-macro "a*b*c") nil)
  (progn (maf-edit-move-beginning-of-line 1) (forward-char 1) nil)
  (call-interactively 'maf-editplus-wrap-ln)
  (cl-assert (equal (maf-edit--entry-text (maf-editplus--entry-at-point))
                    "ln(a*b*c)"))
  (call-interactively 'maf-edit-discard)

  (call-interactively 'maf-edit-add-entry-below)
  (progn (execute-kbd-macro "a/b/c") nil)
  (progn (maf-edit-move-beginning-of-line 1) (forward-char 1) nil)
  (call-interactively 'maf-editplus-wrap-ln)
  (cl-assert (equal (maf-edit--entry-text (maf-editplus--entry-at-point))
                    "ln(a/b)/c"))
  (call-interactively 'maf-edit-discard)

  ;; Turned off, the four share one level and fold left, and the scan
  ;; follows — the setting is read at the press, not remembered.
  (call-interactively 'maf-edit-add-entry-below)
  (progn (execute-kbd-macro "a/b*c")
         (maf-edit-move-beginning-of-line 1)
         (forward-char 1)
         (let ((calc-multiplication-has-precedence nil))
           (call-interactively 'maf-editplus-wrap-ln))
         nil)
  (cl-assert (equal (maf-edit--entry-text (maf-editplus--entry-at-point))
                    "ln(a/b)*c"))
  (call-interactively 'maf-edit-discard)

  ;; A run of the operators calc folds right is named whole from its
  ;; first one: a mod b mod c is a mod (b mod c), and := likewise.
  (call-interactively 'maf-edit-add-entry-below)
  (progn (insert "a mod b mod c")
         (maf-edit-move-beginning-of-line 1)
         (forward-char 2)
         (let ((maf-edit-parse-text-function #'identity))
           (call-interactively 'maf-editplus-wrap-ln))
         nil)
  (cl-assert (equal (maf-edit--entry-text (maf-editplus--entry-at-point))
                    "ln(a mod b mod c)"))
  (call-interactively 'maf-edit-discard)

  (call-interactively 'maf-edit-add-entry-below)
  (progn (insert "a := b := c") nil)
  (progn (maf-edit-move-beginning-of-line 1) (forward-char 2) nil)
  (call-interactively 'maf-editplus-wrap-ln)
  (cl-assert (equal (maf-edit--entry-text (maf-editplus--entry-at-point))
                    "ln(a := b := c)"))
  (call-interactively 'maf-edit-discard)

  ;; The rewrite condition folds left, as calc reads it.
  (call-interactively 'maf-edit-add-entry-below)
  (progn (insert "a :: b :: c") nil)
  (progn (maf-edit-move-beginning-of-line 1) (forward-char 2) nil)
  (call-interactively 'maf-editplus-wrap-ln)
  (cl-assert (equal (maf-edit--entry-text (maf-editplus--entry-at-point))
                    "ln(a :: b) :: c"))
  (call-interactively 'maf-edit-discard)

  ;; An error form is one operator, not a sum over a quotient, and it
  ;; binds tighter than both the product and the power beside it.
  (call-interactively 'maf-edit-add-entry-below)
  (progn (insert "a +/- b * c") nil)
  (progn (maf-edit-move-beginning-of-line 1) (forward-char 2) nil)
  (call-interactively 'maf-editplus-wrap-ln)
  (cl-assert (equal (maf-edit--entry-text (maf-editplus--entry-at-point))
                    "ln(a +/- b) * c"))
  (call-interactively 'maf-edit-discard)

  (call-interactively 'maf-edit-add-entry-below)
  (progn (insert "a +/- b^2") nil)
  (progn (maf-edit-move-beginning-of-line 1) (forward-char 2) nil)
  (call-interactively 'maf-editplus-wrap-ln)
  (cl-assert (equal (maf-edit--entry-text (maf-editplus--entry-at-point))
                    "ln(a +/- b)^2"))
  (call-interactively 'maf-edit-discard)

  ;; It folds right as well, as `mod' and `:=' do: a +/- b +/- c is
  ;; a +/- (b +/- c), so the first one names the whole run and the
  ;; second names the pair inside it.
  (call-interactively 'maf-edit-add-entry-below)
  (progn (insert "a +/- b +/- c") nil)
  (progn (maf-edit-move-beginning-of-line 1) (forward-char 2) nil)
  (call-interactively 'maf-editplus-wrap-ln)
  (cl-assert (equal (maf-edit--entry-text (maf-editplus--entry-at-point))
                    "ln(a +/- b +/- c)"))
  (call-interactively 'maf-edit-discard)

  (call-interactively 'maf-edit-add-entry-below)
  (progn (insert "a +/- b +/- c") nil)
  (progn (maf-edit-move-beginning-of-line 1) (forward-char 8) nil)
  (call-interactively 'maf-editplus-wrap-ln)
  (cl-assert (equal (maf-edit--entry-text (maf-editplus--entry-at-point))
                    "a +/- ln(b +/- c)"))
  (call-interactively 'maf-edit-discard)

  ;; And what commits is the quotient calc reads, not the one the old
  ;; left-folding scan would have named.
  (call-interactively 'maf-edit-add-entry-below)
  (progn (execute-kbd-macro "a/b*c") nil)
  (progn (maf-edit-move-beginning-of-line 1) (forward-char 1) nil)
  (call-interactively 'maf-editplus-wrap-ln)
  (call-interactively 'maf-edit-commit)
  (cl-assert (equal (calc-top 1)
                    '(calcFunc-ln (/ (var a var-a)
                                     (* (var b var-b) (var c var-c))))))
  (calc-pop (calc-stack-size))

  ;; An atom is never split, and a sign belongs to the term it signs.
  (call-interactively 'maf-edit-add-entry-below)
  (progn (execute-kbd-macro "1+2.5") nil)
  (progn (backward-char 2) nil)
  (call-interactively 'maf-editplus-wrap-ln)
  (cl-assert (equal (maf-edit--entry-text (maf-editplus--entry-at-point))
                    "1+ln(2.5)"))
  (call-interactively 'maf-edit-discard)

  (call-interactively 'maf-edit-add-entry-below)
  (progn (execute-kbd-macro "-a*b") nil)
  (progn (maf-edit-move-beginning-of-line 1) nil)
  (call-interactively 'maf-editplus-wrap-ln)
  (cl-assert (equal (maf-edit--entry-text (maf-editplus--entry-at-point))
                    "ln(-a)*b"))
  (call-interactively 'maf-edit-discard)

  ;; An entry continued on a second line is one expression: the pad and
  ;; the line break are furniture to the parse, as they are to the
  ;; scan. The `+' opening the second line heads the whole sum, break
  ;; and all, and the pair around it goes as any other bare pair does.
  (call-interactively 'maf-edit-add-entry-below)
  (progn (insert "(a+b") nil)
  (call-interactively 'maf-edit-newline)
  (progn (insert "+c)*d") nil)
  (maf-edit-move-beginning-of-line 1)
  (call-interactively 'maf-editplus-wrap-ln)
  (cl-assert (equal (maf-edit--entry-text (maf-editplus--entry-at-point))
                    "ln(a+b +c)*d"))
  (call-interactively 'maf-edit-discard)

  ;; And a node on the far side of the break is named from there, the
  ;; line the entry happens to be broken across meaning nothing.
  (call-interactively 'maf-edit-add-entry-below)
  (progn (insert "(a+b") nil)
  (call-interactively 'maf-edit-newline)
  (progn (insert "+c)*d") nil)
  (progn (maf-edit-move-beginning-of-line 1) (forward-char 1) nil)
  (call-interactively 'maf-editplus-wrap-ln)
  (cl-assert (equal (maf-edit--entry-text (maf-editplus--entry-at-point))
                    "(a+b +ln(c))*d"))
  (call-interactively 'maf-edit-discard)

  ;; The end of the entry is the boundary between the two rules: there
  ;; is no character under point, and the smallest complete unit
  ;; ending at point is the argument — the last factor, exactly what a
  ;; power typed here would take, so the wraps and `:' read the
  ;; position as one.
  (call-interactively 'maf-edit-add-entry-below)
  (progn (execute-kbd-macro "a+b*c") nil)
  (call-interactively 'maf-editplus-wrap-ln)
  (cl-assert (equal (maf-edit--entry-text (maf-editplus--entry-at-point))
                    "a+b*ln(c)"))
  (cl-assert (eolp))
  (call-interactively 'maf-edit-discard)

  ;; Trailing whitespace severs the unit: a power does not reach back
  ;; across a space, so nothing is behind point and an empty call
  ;; opens — under the dialect the space is the product, and x+2 ln()
  ;; is 2 times the call being typed.
  (call-interactively 'maf-edit-add-entry-below)
  (progn (insert "x+2 ") nil)
  (call-interactively 'maf-editplus-wrap-ln)
  (cl-assert (equal (maf-edit--entry-text (maf-editplus--entry-at-point))
                    "x+2 ln()"))
  (cl-assert (eq (char-after) ?\)))
  (call-interactively 'maf-edit-discard)

  ;; A quoted name in front of a paren group is not a call — the
  ;; dialect reads {foo}(3) as the product — and the two groups are
  ;; two units, so the key takes the one before point, and a bare
  ;; pair becomes the call's own.
  (call-interactively 'maf-edit-add-entry-below)
  (progn (insert "{foo}(3)") nil)
  (call-interactively 'maf-editplus-wrap-ln)
  (cl-assert (equal (maf-edit--entry-text (maf-editplus--entry-at-point))
                    "{foo}ln(3)"))
  (call-interactively 'maf-edit-discard)

  ;; Nor is a name in front of a brace group: x{foo} is x times foo,
  ;; and only the group is the unit before point. Only a paren group
  ;; can be headed by a name — x[1, 2] is a product to calc as well.
  ;; The written call is spaced off the x: xln({foo}) would fuse into
  ;; a call to xln, and the space keeps the product the text means.
  (call-interactively 'maf-edit-add-entry-below)
  (progn (insert "x{foo}") nil)
  (call-interactively 'maf-editplus-wrap-ln)
  (cl-assert (equal (maf-edit--entry-text (maf-editplus--entry-at-point))
                    "x ln({foo})"))
  (call-interactively 'maf-edit-discard)

  (call-interactively 'maf-edit-add-entry-below)
  (progn (insert "x[1,2]") nil)
  (call-interactively 'maf-editplus-wrap-ln)
  (cl-assert (equal (maf-edit--entry-text (maf-editplus--entry-at-point))
                    "x ln([1,2])"))
  (call-interactively 'maf-edit-discard)

  ;; A string literal's closing quote completes the whole literal.
  (call-interactively 'maf-edit-add-entry-below)
  (progn (insert "\"abc\"") nil)
  (call-interactively 'maf-editplus-wrap-ln)
  (cl-assert (equal (maf-edit--entry-text (maf-editplus--entry-at-point))
                    "ln(\"abc\")"))
  (call-interactively 'maf-edit-discard)

  ;; The opener of a string still being typed completes nothing: the
  ;; quotes must pair forward, or the closer of \"a\" would pair with
  ;; the unfinished quote and name the \"+\" between them. No unit, so
  ;; the empty call opens where typing left off.
  (call-interactively 'maf-edit-add-entry-below)
  (progn (insert "\"a\"+\"") nil)
  (call-interactively 'maf-editplus-wrap-ln)
  (cl-assert (equal (maf-edit--entry-text (maf-editplus--entry-at-point))
                    "\"a\"+\"ln()"))
  (call-interactively 'maf-edit-discard)

  ;; An interval's parens are notation, not grouping: they survive the
  ;; wrap, where a bare pair's would go.
  (call-interactively 'maf-edit-add-entry-below)
  (progn (insert "(1 .. 2)") nil)
  (call-interactively 'maf-editplus-wrap-ln)
  (cl-assert (equal (maf-edit--entry-text (maf-editplus--entry-at-point))
                    "ln((1 .. 2))"))
  (call-interactively 'maf-edit-discard)

  ;; What the gesture writes is a call to calc, not just a name and a
  ;; pair of parens in the text: the entry commits as the formula the
  ;; nesting says it is.
  (call-interactively 'maf-edit-add-entry-below)
  (progn (execute-kbd-macro "9+4") nil)
  (progn (maf-edit-move-beginning-of-line 1) nil)
  (call-interactively 'maf-editplus-wrap-sqrt)
  (call-interactively 'maf-edit-commit)
  (cl-assert (equal (calc-top 1) '(+ (calcFunc-sqrt 9) 4)))
  (calc-pop (calc-stack-size)))
