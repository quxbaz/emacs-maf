;; A colon calc refuses commits as a quotient. The fraction colon
;; takes nothing but integers — 1:x is a syntax error where the writer
;; plainly meant 1/x — so `maf-edit-commit' retries a failed entry
;; with each such colon rewritten as a parenthesized slash
;; (`maf-edit--colon-quotient'). A step passes when it raises no
;; error.
;;
;; The contract: only text calc already refused is reread, so 1:2
;; stays the exact fraction and 1:2:3 the mixed number; half of `::'
;; or `:=' is punctuation and stays; a colon inside a string literal
;; is just text; and the parentheses keep the fraction's tight grip,
;; so x^2:y commits as x^(2/y) and not (x^2)/y.

(maf-step
  ;; The rewrite itself, on text alone. Nil is "nothing to rewrite" —
  ;; the retry never runs — and covers everything a fraction, an
  ;; assignment or a string can rightly claim.
  (cl-assert (equal (maf-edit--colon-quotient "1:x") "(1/x)"))
  (cl-assert (null (maf-edit--colon-quotient "1:2")))
  (cl-assert (null (maf-edit--colon-quotient "1:2:3")))
  (cl-assert (null (maf-edit--colon-quotient "a::b")))
  (cl-assert (null (maf-edit--colon-quotient "\"a:b\"")))
  (cl-assert (equal (maf-edit--colon-quotient "a:=1:x") "a:=(1/x)"))
  (cl-assert (equal (maf-edit--colon-quotient "x^2:y") "x^(2/y)"))
  (cl-assert (equal (maf-edit--colon-quotient "1.5:2") "(1.5/2)"))
  ;; An operand is taken whole: a call with its head, a group with its
  ;; contents — and a colon inside one gets its own rewrite in turn.
  (cl-assert (equal (maf-edit--colon-quotient "f(2):x") "(f(2)/x)"))
  (cl-assert (equal (maf-edit--colon-quotient "1:sqrt(2)") "(1/sqrt(2))"))
  (cl-assert (equal (maf-edit--colon-quotient "(a+b):x") "((a+b)/x)"))
  (cl-assert (equal (maf-edit--colon-quotient "f(a:b):x") "(f((a/b))/x)"))
  ;; A signed denominator was never a fraction — calc refuses 1:-2 —
  ;; so the quotient reading is the only one there is.
  (cl-assert (equal (maf-edit--colon-quotient "1:-2") "(1/-2)"))

  ;; Committed through a live session, typed as the fingers would:
  ;; `;' is the colon key while editing (`maf-edit-insert-colon').
  (call-interactively 'maf-edit-add-entry-below)
  (progn (execute-kbd-macro "1;x") nil)
  (cl-assert (equal (maf-edit--entry-text (maf-edit--entry-at-point))
                    "1:x"))
  (call-interactively 'maf-edit-commit)
  (cl-assert (equal (calc-top 1) '(/ 1 (var x var-x))))
  (calc-pop (calc-stack-size))

  ;; The fraction is untouched: 1:2 parses, so the retry never runs.
  (call-interactively 'maf-edit-add-entry-below)
  (progn (execute-kbd-macro "1;2") nil)
  (call-interactively 'maf-edit-commit)
  (cl-assert (equal (calc-top 1) '(frac 1 2)))
  (calc-pop (calc-stack-size))

  ;; And so is the mixed number, every colon of it between digits.
  (call-interactively 'maf-edit-add-entry-below)
  (progn (execute-kbd-macro "1;2;3") nil)
  (call-interactively 'maf-edit-commit)
  (cl-assert (equal (calc-top 1) '(frac 5 3)))
  (calc-pop (calc-stack-size))

  ;; Embedded, the parentheses keep the colon's tight binding: the
  ;; quotient stays in the exponent, where the fraction would have been.
  (call-interactively 'maf-edit-add-entry-below)
  (progn (execute-kbd-macro "x^2;y") nil)
  (call-interactively 'maf-edit-commit)
  (cl-assert (equal (calc-top 1)
                    '(^ (var x var-x) (/ 2 (var y var-y)))))
  (calc-pop (calc-stack-size)))
