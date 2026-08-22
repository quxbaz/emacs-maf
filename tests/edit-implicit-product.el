;; At the end of an entry a run led by a number is that number times a
;; name — calc reads 24x as 24 x — so the smallest complete unit ending
;; at point is the name alone, and that is what the wrap keys and the
;; power take: exactly what a typed ^2 would have bound to. A step
;; passes when it raises no error.

(maf-step
  ;; The headline case: the x comes away, the 24 stays a factor.
  (call-interactively 'maf-edit-add-entry-below)
  (progn (execute-kbd-macro "24x") nil)
  (call-interactively 'maf-editplus-wrap-ln)
  (cl-assert (equal (maf-edit--entry-text (maf-editplus--entry-at-point))
                    "24ln(x)"))
  (call-interactively 'maf-edit-discard)

  ;; The power reads the position the same way: ^2 goes in behind the
  ;; x it binds to, and a second press counts that power up.
  (call-interactively 'maf-edit-add-entry-below)
  (progn (execute-kbd-macro "24x") nil)
  (call-interactively 'maf-editplus-raise-power)
  (cl-assert (equal (maf-edit--entry-text (maf-editplus--entry-at-point))
                    "24x^2"))
  (call-interactively 'maf-editplus-raise-power)
  (cl-assert (equal (maf-edit--entry-text (maf-editplus--entry-at-point))
                    "24x^3"))
  (call-interactively 'maf-edit-discard)

  ;; The number keeps everything its own syntax reaches: a decimal, a
  ;; float exponent — 24e3x is 24e3 times x, not 24 times e3x.
  (call-interactively 'maf-edit-add-entry-below)
  (progn (execute-kbd-macro "2.5x") nil)
  (call-interactively 'maf-editplus-wrap-ln)
  (cl-assert (equal (maf-edit--entry-text (maf-editplus--entry-at-point))
                    "2.5ln(x)"))
  (call-interactively 'maf-edit-discard)

  (call-interactively 'maf-edit-add-entry-below)
  (progn (execute-kbd-macro "24e3x") nil)
  (call-interactively 'maf-editplus-wrap-ln)
  (cl-assert (equal (maf-edit--entry-text (maf-editplus--entry-at-point))
                    "24e3ln(x)"))
  (call-interactively 'maf-edit-discard)

  ;; A name may hold digits of its own — x3 is one identifier — and it
  ;; still comes away whole from behind its coefficient.
  (call-interactively 'maf-edit-add-entry-below)
  (progn (execute-kbd-macro "24x3") nil)
  (call-interactively 'maf-editplus-wrap-ln)
  (cl-assert (equal (maf-edit--entry-text (maf-editplus--entry-at-point))
                    "24ln(x3)"))
  (call-interactively 'maf-edit-discard)

  ;; A pure number is still one unit however calc spells it.
  (call-interactively 'maf-edit-add-entry-below)
  (progn (execute-kbd-macro "2+1e-3") nil)
  (call-interactively 'maf-editplus-wrap-ln)
  (cl-assert (equal (maf-edit--entry-text (maf-editplus--entry-at-point))
                    "2+ln(1e-3)"))
  (call-interactively 'maf-edit-discard)

  (call-interactively 'maf-edit-add-entry-below)
  (progn (execute-kbd-macro "2+16#ff") nil)
  (call-interactively 'maf-editplus-wrap-ln)
  (cl-assert (equal (maf-edit--entry-text (maf-editplus--entry-at-point))
                    "2+ln(16#ff)"))
  (call-interactively 'maf-edit-discard)

  ;; In front of an electric closer the position reads the same as the
  ;; end of the entry, so the split holds there too.
  (call-interactively 'maf-edit-add-entry-below)
  (progn (execute-kbd-macro "(1+24x") nil)
  (call-interactively 'maf-editplus-wrap-ln)
  (cl-assert (equal (maf-edit--entry-text (maf-editplus--entry-at-point))
                    "(1+24ln(x))"))
  (call-interactively 'maf-edit-discard)

  ;; And what commits is the product calc reads: 24 times ln(x).
  (call-interactively 'maf-edit-add-entry-below)
  (progn (execute-kbd-macro "24x") nil)
  (call-interactively 'maf-editplus-wrap-ln)
  (call-interactively 'maf-edit-commit)
  (cl-assert (equal (calc-top 1)
                    '(* 24 (calcFunc-ln (var x var-x)))))
  (calc-pop (calc-stack-size)))
