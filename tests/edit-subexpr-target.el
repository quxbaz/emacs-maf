;; Inside a maf-edit session, L/Q/| name their argument the way maf's
;; subexpr target names its own on the stack: the character under point
;; picks a sub-expression, and the call is written around that
;; (`maf-editplus--subexpr-node'). A step passes when it raises no error.
;;
;; The rule is the stack's rule. Point on an operand takes that operand;
;; point on an operator — or on a delimiter, or on the space beside one
;; — takes the node the operator heads, so the same keypress reaches a
;; bigger piece by standing one character to the left. The parse is of
;; the text, not of a value: it is calc's precedence, but nothing in it
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

  ;; A pair of bare parentheses is punctuation, not structure. It names
  ;; the expression inside it — from either end — and the call supplies
  ;; the grouping the pair was there for, so the pair goes rather than
  ;; ln((a+b)) being written.
  (call-interactively 'maf-edit-add-entry-below)
  (progn (execute-kbd-macro "(a+b)*c") nil)
  (progn (maf-edit-move-beginning-of-line 1) nil)
  (call-interactively 'maf-editplus-wrap-ln)
  (cl-assert (equal (maf-edit--entry-text (maf-editplus--entry-at-point))
                    "ln(a+b)*c"))
  (call-interactively 'maf-edit-discard)

  (call-interactively 'maf-edit-add-entry-below)
  (progn (execute-kbd-macro "(a+b)*c") nil)
  (progn (maf-edit-move-beginning-of-line 1) (forward-char 4) nil)
  (call-interactively 'maf-editplus-wrap-ln)
  (cl-assert (equal (maf-edit--entry-text (maf-editplus--entry-at-point))
                    "ln(a+b)*c"))
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
  ;; is no character under point, and the term behind it is the
  ;; argument — which is why typing a formula and pressing the key
  ;; still wraps what was just typed.
  (call-interactively 'maf-edit-add-entry-below)
  (progn (execute-kbd-macro "a+b*c") nil)
  (call-interactively 'maf-editplus-wrap-ln)
  (cl-assert (equal (maf-edit--entry-text (maf-editplus--entry-at-point))
                    "a+ln(b*c)"))
  (cl-assert (eolp))
  (call-interactively 'maf-edit-discard)

  ;; Trailing whitespace is not a character under point either: the
  ;; entry still ends there.
  (call-interactively 'maf-edit-add-entry-below)
  (progn (insert "x+2 ") nil)
  (call-interactively 'maf-editplus-wrap-ln)
  (cl-assert (equal (maf-edit--entry-text (maf-editplus--entry-at-point))
                    "x+ln(2)"))
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
