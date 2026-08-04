;; M-o inside a maf-edit session puts parentheses around the term before
;; point (`maf-editplus-wrap-parens', the editplus module's second key),
;; and pressing it again widens that pair one operator at a time instead
;; of nesting a new one. A step passes when it raises no error.
;;
;; The contract: the scan crosses `*' but stops at anything looser, a
;; function call or bracketed group is one unit, only a bare paren pair
;; widens, the first press never changes what the entry means, and the
;; scan never leaves the entry point started in.

(maf-step
  ;; The module owns the key, and it lives in maf-edit's own map — so
  ;; it means nothing until a session is running.
  (cl-assert (eq (lookup-key maf-edit-mode-map (kbd "M-o"))
                 'maf-editplus-wrap-parens))

  ;; The gesture as it is actually used: type a term, then wrap it.
  ;; Driven by the real key, so the binding is exercised too. Point
  ;; lands after the closer, which is where the next press expects it.
  (call-interactively 'maf-edit-add-entry-below)
  (progn (execute-kbd-macro "pi+2") nil)
  (progn (execute-kbd-macro (kbd "M-o")) nil)
  (cl-assert (equal (maf-edit--entry-text (maf-editplus--entry-at-point))
                    "pi+(2)"))
  (cl-assert (eolp))
  ;; A second press widens the pair rather than nesting another inside.
  (call-interactively 'maf-editplus-wrap-parens)
  (cl-assert (equal (maf-edit--entry-text (maf-editplus--entry-at-point))
                    "(pi+2)"))
  ;; With nothing left to take in, the pair it placed stays as it is.
  (cl-assert (string-match-p
              "Nothing left"
              (condition-case e
                  (progn (call-interactively 'maf-editplus-wrap-parens) "")
                (error (error-message-string e)))))
  (cl-assert (equal (maf-edit--entry-text (maf-editplus--entry-at-point))
                    "(pi+2)"))
  (call-interactively 'maf-edit-discard)

  ;; A product is the innermost term worth wrapping: the scan crosses
  ;; `*' and stops at the `+'.
  (call-interactively 'maf-edit-add-entry-below)
  (progn (execute-kbd-macro "a+b*c") nil)
  (call-interactively 'maf-editplus-wrap-parens)
  (cl-assert (equal (maf-edit--entry-text (maf-editplus--entry-at-point))
                    "a+(b*c)"))
  (call-interactively 'maf-edit-discard)

  ;; But not when a `/' is what stops it: a/(b*c) is not a/b*c, and a
  ;; first press must never change what the entry means. The term is
  ;; cut back to the `*'; the press after that regroups deliberately.
  (call-interactively 'maf-edit-add-entry-below)
  (progn (execute-kbd-macro "a/b*c") nil)
  (call-interactively 'maf-editplus-wrap-parens)
  (cl-assert (equal (maf-edit--entry-text (maf-editplus--entry-at-point))
                    "a/b*(c)"))
  (call-interactively 'maf-editplus-wrap-parens)
  (cl-assert (equal (maf-edit--entry-text (maf-editplus--entry-at-point))
                    "a/(b*c)"))
  (call-interactively 'maf-edit-discard)

  ;; Same for a `^', which binds tighter still.
  (call-interactively 'maf-edit-add-entry-below)
  (progn (execute-kbd-macro "a^b*c") nil)
  (call-interactively 'maf-editplus-wrap-parens)
  (cl-assert (equal (maf-edit--entry-text (maf-editplus--entry-at-point))
                    "a^b*(c)"))
  (call-interactively 'maf-edit-discard)

  ;; An atom is never split. Point between two digits stands inside
  ;; one number, not between two terms, so both digits go in.
  (call-interactively 'maf-edit-add-entry-below)
  (progn (execute-kbd-macro "6 x + 12 = 18 y") nil)
  (progn (goto-char (line-beginning-position))
         (search-forward "12" (line-end-position))
         (backward-char 1) nil)
  (call-interactively 'maf-editplus-wrap-parens)
  (cl-assert (equal (maf-edit--entry-text (maf-editplus--entry-at-point))
                    "6 x + (12) = 18 y"))
  (call-interactively 'maf-edit-discard)

  ;; The dot of a decimal and the colon of a fraction are inside the
  ;; number too, from either side of them.
  (call-interactively 'maf-edit-add-entry-below)
  (progn (execute-kbd-macro "1+2.5") nil)
  (progn (backward-char 2) nil)
  (call-interactively 'maf-editplus-wrap-parens)
  (cl-assert (equal (maf-edit--entry-text (maf-editplus--entry-at-point))
                    "1+(2.5)"))
  (call-interactively 'maf-edit-discard)

  (call-interactively 'maf-edit-add-entry-below)
  ;; Typed as a fraction actually is: `;' is the colon key here, `:'
  ;; itself having gone to `maf-editplus-raise-power'.
  (progn (execute-kbd-macro "1+3;4") nil)
  (progn (backward-char 1) nil)
  (call-interactively 'maf-editplus-wrap-parens)
  (cl-assert (equal (maf-edit--entry-text (maf-editplus--entry-at-point))
                    "1+(3:4)"))
  (call-interactively 'maf-edit-discard)

  ;; A name is an atom as well, and its argument list comes with it —
  ;; a press inside sqrt must not cut the head off the call.
  (call-interactively 'maf-edit-add-entry-below)
  (progn (execute-kbd-macro "27/sqrt(3") nil)
  (progn (goto-char (line-beginning-position))
         (search-forward "sq" (line-end-position)) nil)
  (call-interactively 'maf-editplus-wrap-parens)
  (cl-assert (equal (maf-edit--entry-text (maf-editplus--entry-at-point))
                    "27/(sqrt(3))"))
  (call-interactively 'maf-edit-discard)

  ;; Standing just before an atom is standing just after whatever
  ;; precedes it: that is not inside anything, and the operator there
  ;; has no term behind it.
  (call-interactively 'maf-edit-add-entry-below)
  (progn (execute-kbd-macro "a+12") nil)
  (progn (backward-char 2) nil)
  (cl-assert (string-match-p
              "Nothing to wrap"
              (condition-case e
                  (progn (call-interactively 'maf-editplus-wrap-parens) "")
                (error (error-message-string e)))))
  (call-interactively 'maf-edit-discard)

  ;; Point beside an operator is not inside an atom either: the term
  ;; behind it is wrapped and nothing ahead is drawn in.
  (call-interactively 'maf-edit-add-entry-below)
  (progn (execute-kbd-macro "a+b*c") nil)
  (progn (backward-char 2) nil)
  (call-interactively 'maf-editplus-wrap-parens)
  (cl-assert (equal (maf-edit--entry-text (maf-editplus--entry-at-point))
                    "a+(b)*c"))
  (call-interactively 'maf-edit-discard)

  ;; A leading sign belongs to the term it signs — nothing to its left
  ;; can join that term — so it comes inside the parens, not outside.
  (call-interactively 'maf-edit-add-entry-below)
  (progn (execute-kbd-macro "2*-3") nil)
  (call-interactively 'maf-editplus-wrap-parens)
  (cl-assert (equal (maf-edit--entry-text (maf-editplus--entry-at-point))
                    "2*(-3)"))
  (call-interactively 'maf-edit-discard)

  ;; Which is also what keeps widening honest: -(x+y) is not -x+y, so
  ;; the sign at the head of the entry is taken in, not left behind.
  (call-interactively 'maf-edit-add-entry-below)
  (progn (execute-kbd-macro "-x+y") nil)
  (call-interactively 'maf-editplus-wrap-parens)
  (call-interactively 'maf-editplus-wrap-parens)
  (cl-assert (equal (maf-edit--entry-text (maf-editplus--entry-at-point))
                    "(-x+y)"))
  (call-interactively 'maf-edit-discard)

  ;; A binary minus is still a boundary, and the sign rule does not
  ;; blur the two.
  (call-interactively 'maf-edit-add-entry-below)
  (progn (execute-kbd-macro "a-b") nil)
  (call-interactively 'maf-editplus-wrap-parens)
  (cl-assert (equal (maf-edit--entry-text (maf-editplus--entry-at-point))
                    "a-(b)"))
  (call-interactively 'maf-edit-discard)

  ;; A function call is one unit — the name comes along with its
  ;; argument list — and a denominator is a term of its own, so the
  ;; root is what the first press wraps.
  (call-interactively 'maf-edit-add-entry-below)
  (progn (execute-kbd-macro "27/sqrt(3)") nil)
  (cl-assert (eolp))
  (call-interactively 'maf-editplus-wrap-parens)
  (cl-assert (equal (maf-edit--entry-text (maf-editplus--entry-at-point))
                    "27/(sqrt(3))"))
  (call-interactively 'maf-editplus-wrap-parens)
  (cl-assert (equal (maf-edit--entry-text (maf-editplus--entry-at-point))
                    "(27/sqrt(3))"))
  (call-interactively 'maf-edit-discard)

  ;; An argument list is structure, not a pair this command placed:
  ;; beside one, the press wraps the call instead of widening it — the
  ;; parens sqrt needs are never the ones that travel.
  (call-interactively 'maf-edit-add-entry-below)
  (progn (execute-kbd-macro "sqrt(3)") nil)
  (call-interactively 'maf-editplus-wrap-parens)
  (cl-assert (equal (maf-edit--entry-text (maf-editplus--entry-at-point))
                    "(sqrt(3))"))
  (call-interactively 'maf-edit-discard)

  ;; A vector is structure too. Widening it would delete a bracket the
  ;; entry needs, turning [1,2] into the wrong object entirely.
  (call-interactively 'maf-edit-add-entry-below)
  (progn (execute-kbd-macro "[1,2") nil)
  (call-interactively 'maf-editplus-escape-group)
  (cl-assert (eolp))
  (call-interactively 'maf-editplus-wrap-parens)
  (cl-assert (equal (maf-edit--entry-text (maf-editplus--entry-at-point))
                    "([1,2])"))
  (call-interactively 'maf-edit-discard)

  ;; The opener of the group point is inside is the one boundary
  ;; widening never crosses: the pair stays where it is rather than
  ;; taking a bracket the entry needs along with it.
  (call-interactively 'maf-edit-add-entry-below)
  (progn (execute-kbd-macro "[(a+b") nil)
  (call-interactively 'maf-editplus-escape-group)
  (cl-assert (string-match-p
              "Nothing left"
              (condition-case e
                  (progn (call-interactively 'maf-editplus-wrap-parens) "")
                (error (error-message-string e)))))
  (cl-assert (equal (maf-edit--entry-text (maf-editplus--entry-at-point))
                    "[(a+b)]"))
  (call-interactively 'maf-edit-discard)

  ;; A two-character relation is one boundary, crossed in one go: the
  ;; opening paren can never land between its halves.
  (call-interactively 'maf-edit-add-entry-below)
  (progn (execute-kbd-macro "a <= b+c") nil)
  (call-interactively 'maf-editplus-wrap-parens)
  (call-interactively 'maf-editplus-wrap-parens)
  (cl-assert (equal (maf-edit--entry-text (maf-editplus--entry-at-point))
                    "a <= (b+c)"))
  (call-interactively 'maf-editplus-wrap-parens)
  (cl-assert (equal (maf-edit--entry-text (maf-editplus--entry-at-point))
                    "(a <= b+c)"))
  (call-interactively 'maf-edit-discard)

  ;; An equation: the scan stops at the `=' with the space left
  ;; outside the parens, and the press after that takes the whole
  ;; relation in.
  (call-interactively 'maf-edit-add-entry-below)
  (progn (execute-kbd-macro "x = pi+2") nil)
  (call-interactively 'maf-editplus-wrap-parens)
  (call-interactively 'maf-editplus-wrap-parens)
  (cl-assert (equal (maf-edit--entry-text (maf-editplus--entry-at-point))
                    "x = (pi+2)"))
  (call-interactively 'maf-editplus-wrap-parens)
  (cl-assert (equal (maf-edit--entry-text (maf-editplus--entry-at-point))
                    "(x = pi+2)"))
  (call-interactively 'maf-edit-discard)

  ;; An entry continued on a second line is still one expression: the
  ;; machine-owned pad and the line break are whitespace to the scan,
  ;; so widening reaches back across them.
  (call-interactively 'maf-edit-add-entry-below)
  (progn (insert "(a+b") nil)
  (call-interactively 'maf-edit-newline)
  (progn (insert "+c") nil)
  (call-interactively 'maf-editplus-wrap-parens)
  (cl-assert (equal (maf-edit--entry-text (maf-editplus--entry-at-point))
                    "(a+b +(c)"))
  (call-interactively 'maf-editplus-wrap-parens)
  (cl-assert (equal (maf-edit--entry-text (maf-editplus--entry-at-point))
                    "(a+(b +c)"))
  (call-interactively 'maf-edit-discard)

  ;; An active region is wrapped exactly as marked, and point still
  ;; ends after the closer, so widening can carry on from there.
  (call-interactively 'maf-edit-add-entry-below)
  (progn (execute-kbd-macro "pi+2") nil)
  (progn (maf-edit-move-beginning-of-line 1)
         (set-mark (point))
         (forward-char 2)
         (activate-mark) nil)
  (call-interactively 'maf-editplus-wrap-parens)
  (cl-assert (equal (maf-edit--entry-text (maf-editplus--entry-at-point))
                    "(pi)+2"))
  (cl-assert (eq (char-before) ?\)))
  (call-interactively 'maf-edit-discard)

  ;; Nothing before point in the entry is nothing to wrap — the
  ;; machine-owned prefix is not text, and the entry above is not this
  ;; entry.
  (call-interactively 'maf-edit-add-entry-below)
  (progn (execute-kbd-macro "a+b") nil)
  (maf-edit-move-beginning-of-line 1)
  (cl-assert (string-match-p
              "Nothing to wrap"
              (condition-case e
                  (progn (call-interactively 'maf-editplus-wrap-parens) "")
                (error (error-message-string e)))))
  (cl-assert (equal (maf-edit--entry-text (maf-editplus--entry-at-point))
                    "a+b"))
  ;; Nor is a dangling operator, which the legacy version wrapped into
  ;; an empty pair.
  (progn (goto-char (line-end-position)) (insert "*") nil)
  (cl-assert (string-match-p
              "Nothing to wrap"
              (condition-case e
                  (progn (call-interactively 'maf-editplus-wrap-parens) "")
                (error (error-message-string e)))))
  (cl-assert (equal (maf-edit--entry-text (maf-editplus--entry-at-point))
                    "a+b*"))
  (call-interactively 'maf-edit-discard)

  ;; The home line is not an entry: the dot is furniture, and a press
  ;; there must not turn it into one.
  (maf-push "a+b")
  (maf-edit-mode 1)
  (progn (goto-char (point-max)) nil)
  (cl-assert (null (maf-editplus--entry-at-point)))
  (cl-assert (string-match-p
              "not in a stack entry"
              (condition-case e
                  (progn (call-interactively 'maf-editplus-wrap-parens) "")
                (error (error-message-string e)))))
  (call-interactively 'maf-edit-discard)
  (calc-pop (calc-stack-size))

  ;; Outside a session the command refuses rather than editing calc's
  ;; rendered stack. The key never reaches here — it is bound in
  ;; `maf-edit-mode-map' alone — so M-x is the only route, and it is
  ;; the one guarded.
  (maf-push "a+b")
  (progn (calc-cursor-stack-index 1)
         (goto-char (line-end-position)) nil)
  (cl-assert (string-match-p
              "not active"
              (condition-case e
                  (progn (call-interactively 'maf-editplus-wrap-parens) "")
                (error (error-message-string e)))))
  (cl-assert (equal (calc-top 1) '(+ (var a var-a) (var b var-b))))
  (calc-pop (calc-stack-size)))
