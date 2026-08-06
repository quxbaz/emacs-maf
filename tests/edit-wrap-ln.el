;; L inside a maf-edit session makes a sub-expression the argument of an
;; ln call (`maf-editplus-wrap-ln', the editplus module's third key). A
;; step passes when it raises no error.
;;
;; The contract has two halves, and this file covers the second. At the
;; end of the entry the argument is the term behind point — the one
;; `maf-editplus-wrap-parens' would have wrapped, so a call or a
;; bracketed group comes along whole and an atom is never split — and a
;; press with no term behind point opens an empty ln() to type into.
;; Inside the text the argument is the sub-expression point names, as on
;; the stack; that half is `edit-subexpr-target.el'. Either way the scan
;; never leaves the entry it started in.

(maf-step
  ;; The module owns the key, and it lives in maf-edit's own map — so
  ;; it means nothing until a session is running.
  (cl-assert (eq (lookup-key maf-edit-mode-map (kbd "L"))
                 'maf-editplus-wrap-ln))

  ;; The gesture as it is actually used: type a term, then apply ln to
  ;; it. Driven by the real key, so the binding is exercised too — and
  ;; so is the fact that a capital L no longer types itself here.
  (call-interactively 'maf-edit-add-entry-below)
  (progn (execute-kbd-macro "x+2") nil)
  (progn (execute-kbd-macro "L") nil)
  (cl-assert (equal (maf-edit--entry-text (maf-editplus--entry-at-point))
                    "x+ln(2)"))
  (cl-assert (eolp))
  ;; Point lands after the closer, so a second press applies ln again
  ;; rather than nesting parens: the call is one unit to the scan.
  (call-interactively 'maf-editplus-wrap-ln)
  (cl-assert (equal (maf-edit--entry-text (maf-editplus--entry-at-point))
                    "x+ln(ln(2))"))
  (call-interactively 'maf-edit-discard)

  ;; A product is the innermost term worth taking, exactly as with M-o.
  (call-interactively 'maf-edit-add-entry-below)
  (progn (execute-kbd-macro "a+b*c") nil)
  (call-interactively 'maf-editplus-wrap-ln)
  (cl-assert (equal (maf-edit--entry-text (maf-editplus--entry-at-point))
                    "a+ln(b*c)"))
  (call-interactively 'maf-edit-discard)

  ;; A function call comes with its name, and a denominator is a term
  ;; of its own.
  (call-interactively 'maf-edit-add-entry-below)
  (progn (execute-kbd-macro "27/sqrt(3)") nil)
  (call-interactively 'maf-editplus-wrap-ln)
  (cl-assert (equal (maf-edit--entry-text (maf-editplus--entry-at-point))
                    "27/ln(sqrt(3))"))
  (call-interactively 'maf-edit-discard)

  ;; So does a bracketed group.
  (call-interactively 'maf-edit-add-entry-below)
  (progn (execute-kbd-macro "[1,2") nil)
  (call-interactively 'maf-editplus-escape-group)
  (call-interactively 'maf-editplus-wrap-ln)
  (cl-assert (equal (maf-edit--entry-text (maf-editplus--entry-at-point))
                    "ln([1,2])"))
  (call-interactively 'maf-edit-discard)

  ;; A number written with an exponent is one atom at the end of the
  ;; entry too: the scan crosses the sign rather than stopping at it,
  ;; so the three does not come away on its own.
  (call-interactively 'maf-edit-add-entry-below)
  (progn (execute-kbd-macro "2+1e-3") nil)
  (call-interactively 'maf-editplus-wrap-ln)
  (cl-assert (equal (maf-edit--entry-text (maf-editplus--entry-at-point))
                    "2+ln(1e-3)"))
  (call-interactively 'maf-edit-discard)

  ;; An atom is never split: point inside a decimal takes the number
  ;; whole, not the half behind point.
  (call-interactively 'maf-edit-add-entry-below)
  (progn (execute-kbd-macro "1+2.5") nil)
  (progn (backward-char 2) nil)
  (call-interactively 'maf-editplus-wrap-ln)
  (cl-assert (equal (maf-edit--entry-text (maf-editplus--entry-at-point))
                    "1+ln(2.5)"))
  (call-interactively 'maf-edit-discard)

  ;; Point back inside the text is no longer the end of the entry, and
  ;; the term behind point stops being the question: the character
  ;; under point names the argument, as it does on the stack. Here that
  ;; is the `*', so the product it heads is what ln takes —
  ;; `edit-subexpr-target.el' works through the rest.
  (call-interactively 'maf-edit-add-entry-below)
  (progn (execute-kbd-macro "a+b*c") nil)
  (progn (backward-char 2) nil)
  (call-interactively 'maf-editplus-wrap-ln)
  (cl-assert (equal (maf-edit--entry-text (maf-editplus--entry-at-point))
                    "a+ln(b*c)"))
  (call-interactively 'maf-edit-discard)

  ;; A leading sign belongs to the term it signs.
  (call-interactively 'maf-edit-add-entry-below)
  (progn (execute-kbd-macro "2*-3") nil)
  (call-interactively 'maf-editplus-wrap-ln)
  (cl-assert (equal (maf-edit--entry-text (maf-editplus--entry-at-point))
                    "2*ln(-3)"))
  (call-interactively 'maf-edit-discard)

  ;; With no term behind point an empty call is opened instead of the
  ;; command refusing — where M-o would have made a meaningless empty
  ;; pair, ln() is a call waiting for its argument. Point is inside it,
  ;; and the space the operator was typed with is kept.
  (call-interactively 'maf-edit-add-entry-below)
  (progn (execute-kbd-macro "x = ") nil)
  (call-interactively 'maf-editplus-wrap-ln)
  (cl-assert (equal (maf-edit--entry-text (maf-editplus--entry-at-point))
                    "x = ln()"))
  (cl-assert (eq (char-after) ?\)))
  ;; And typing carries straight on into it.
  (progn (execute-kbd-macro "3") nil)
  (cl-assert (equal (maf-edit--entry-text (maf-editplus--entry-at-point))
                    "x = ln(3)"))
  (call-interactively 'maf-edit-discard)

  ;; The head of an entry is the same case: nothing behind point.
  (call-interactively 'maf-edit-add-entry-below)
  (call-interactively 'maf-editplus-wrap-ln)
  (cl-assert (equal (maf-edit--entry-text (maf-editplus--entry-at-point))
                    "ln()"))
  (cl-assert (eq (char-after) ?\)))
  (call-interactively 'maf-edit-discard)

  ;; The machine-owned prefix is not text, and a press at the start of
  ;; a typed entry never reaches into the entry above for an argument.
  ;; The first character of the entry is the one under point, so it is
  ;; the head of the formula that ln takes.
  (call-interactively 'maf-edit-add-entry-below)
  (progn (execute-kbd-macro "a+b") nil)
  (maf-edit-move-beginning-of-line 1)
  (call-interactively 'maf-editplus-wrap-ln)
  (cl-assert (equal (maf-edit--entry-text (maf-editplus--entry-at-point))
                    "ln(a)+b"))
  (call-interactively 'maf-edit-discard)

  ;; An active region becomes the argument exactly as marked, and point
  ;; again ends after the closer. Marked and pressed in the one step:
  ;; the stepper deactivates the mark around every form it runs
  ;; (`maf--step-run'), so a region set in a step of its own is gone
  ;; before the command sees it.
  (call-interactively 'maf-edit-add-entry-below)
  (progn (execute-kbd-macro "pi+2") nil)
  (progn (maf-edit-move-beginning-of-line 1)
         (set-mark (point))
         (forward-char 2)
         (activate-mark)
         (call-interactively 'maf-editplus-wrap-ln)
         nil)
  (cl-assert (equal (maf-edit--entry-text (maf-editplus--entry-at-point))
                    "ln(pi)+2"))
  (cl-assert (eq (char-before) ?\)))
  (call-interactively 'maf-edit-discard)

  ;; An entry continued on a second line is still one expression: the
  ;; pad and the line break are whitespace to the scan.
  (call-interactively 'maf-edit-add-entry-below)
  (progn (insert "(a+b") nil)
  (call-interactively 'maf-edit-newline)
  (progn (insert "+c") nil)
  (call-interactively 'maf-editplus-wrap-ln)
  (cl-assert (equal (maf-edit--entry-text (maf-editplus--entry-at-point))
                    "(a+b +ln(c)"))
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
                  (progn (call-interactively 'maf-editplus-wrap-ln) "")
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
                  (progn (call-interactively 'maf-editplus-wrap-ln) "")
                (error (error-message-string e)))))
  (cl-assert (equal (calc-top 1) '(+ (var a var-a) (var b var-b))))
  (calc-pop (calc-stack-size)))
