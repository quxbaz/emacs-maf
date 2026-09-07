;; The words or and and, typed inside a maf-edit session, are the
;; operators calc spells || and &&, and commit trades them
;; (`maf-editplus--commit-words', on
;; `maf-edit-transform-text-functions'), the same trade the union U
;; gets (tests/edit-union.el). A step passes when it raises no error.
;;
;; The contract: a word with whitespace on both sides and an operand
;; on each side is the operator, and every other or and and is the
;; name or the factor the text spells — order, sand and or_1 all keep
;; their letters. The session goes on showing the word that was
;; typed; only the committed value carries the bar or the ampersand.

(maf-step
  (cl-assert (memq 'maf-editplus--commit-words
                   maf-edit-transform-text-functions))
  (calc-pop (calc-stack-size))

  ;; A solution set spelled in words. The text keeps its or while it
  ;; is still editable, and commits as the || calc reads.
  (call-interactively 'maf-edit-add-entry-below)
  (progn (execute-kbd-macro "x<-1 or x>1") nil)
  (cl-assert (equal (maf-edit--entry-text (maf-editplus--entry-at-point))
                    "x<-1 or x>1"))
  (call-interactively 'maf-edit-commit)
  (cl-assert (equal (calc-top 1)
                    '(calcFunc-lor (calcFunc-lt (var x var-x) -1)
                                   (calcFunc-gt (var x var-x) 1))))
  (cl-assert (string= (math-format-value (calc-top 1) 1000)
                      "x < -1 || x > 1"))
  (calc-pop (calc-stack-size))

  ;; And the conjunction: an interval spelled as two bounds.
  (call-interactively 'maf-edit-add-entry-below)
  (progn (execute-kbd-macro "x>0 and x<1") nil)
  (call-interactively 'maf-edit-commit)
  (cl-assert (equal (calc-top 1)
                    '(calcFunc-land (calcFunc-gt (var x var-x) 0)
                                    (calcFunc-lt (var x var-x) 1))))
  (cl-assert (string= (math-format-value (calc-top 1) 1000)
                      "x > 0 && x < 1"))
  (calc-pop (calc-stack-size))

  ;; The two words mix, with each other and with the U, and every one
  ;; of a chain is traded. Precedence is calc's: && binds tighter
  ;; than ||.
  (call-interactively 'maf-edit-add-entry-below)
  (progn (insert "a or b and c U d") nil)
  (call-interactively 'maf-edit-commit)
  (cl-assert (equal (calc-top 1)
                    '(calcFunc-lor
                      (calcFunc-lor (var a var-a)
                                    (calcFunc-land (var b var-b) (var c var-c)))
                      (var d var-d))))
  (calc-pop (calc-stack-size))

  ;; A group or a signed term counts as an operand the same way an
  ;; atom does.
  (call-interactively 'maf-edit-add-entry-below)
  (progn (insert "(a) and -b") nil)
  (call-interactively 'maf-edit-commit)
  (cl-assert (equal (calc-top 1)
                    '(calcFunc-land (var a var-a) (neg (var b var-b)))))
  (calc-pop (calc-stack-size))

  ;; A word with an operator rather than an operand beside it is the
  ;; name it looks like: no bar or ampersand reaches calc. What name —
  ;; one variable or, under the editvars dialect, a product of
  ;; letters — is the input syntax's business, not the rewrite's.
  (call-interactively 'maf-edit-add-entry-below)
  (progn (insert "E = or + and") nil)
  (call-interactively 'maf-edit-commit)
  (cl-assert (not (string-match-p "||\\|&&"
                                  (math-format-value (calc-top 1) 1000))))
  (calc-pop (calc-stack-size))

  ;; The discriminations, on the rewrite itself. A word inside a name
  ;; belongs to the name — the whole of it, not the letters that
  ;; happen to spell or — and one written tight against a neighbour
  ;; is a factor: only whitespace on both sides makes it the operator.
  (cl-assert (equal (maf-editplus--commit-words "order and sand")
                    "order && sand"))
  (cl-assert (equal (maf-editplus--commit-words "for x") "for x"))
  (cl-assert (equal (maf-editplus--commit-words "x or_1 y") "x or_1 y"))
  (cl-assert (equal (maf-editplus--commit-words "a  or  b") "a  ||  b"))
  (cl-assert (equal (maf-editplus--commit-words "a  and  b") "a  &&  b"))
  ;; Case is part of the spelling: OR and And are names.
  (cl-assert (equal (maf-editplus--commit-words "a OR b") "a OR b"))
  (cl-assert (equal (maf-editplus--commit-words "a And b") "a And b"))
  ;; A word at either end of the text has no second operand.
  (cl-assert (equal (maf-editplus--commit-words "or") "or"))
  (cl-assert (equal (maf-editplus--commit-words "a or") "a or"))
  (cl-assert (equal (maf-editplus--commit-words "and b") "and b"))
  ;; And a word inside a string literal is text, like every other
  ;; character there.
  (cl-assert (equal (maf-editplus--commit-words "\"a or b\" or c")
                    "\"a or b\" || c")))
