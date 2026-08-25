;; A union typed inside a maf-edit session is the letter U, and commit
;; trades it for the || calc reads (`maf-editplus--commit-union', on
;; `maf-edit-transform-text-functions'). A step passes when it raises
;; no error.
;;
;; The contract: a U with whitespace on both sides and an operand on
;; each side is the union operator, and every other U is the name or
;; the factor the text spells. The trade is confined to commit — the
;; session goes on showing the U that was typed, as B's log(x, 10)
;; goes on showing its base — and it happens before the editvars
;; dialect reads the text, so the bar reaches calc under either input
;; syntax.

(maf-step
  (cl-assert (memq 'maf-editplus--commit-union
                   maf-edit-transform-text-functions))
  (calc-pop (calc-stack-size))

  ;; The shape asked for: a solution set, typed with the letter drawn
  ;; like the sign. The text keeps its U while it is still editable.
  (call-interactively 'maf-edit-add-entry-below)
  (progn (execute-kbd-macro "x<-1 U x>1") nil)
  (cl-assert (equal (maf-edit--entry-text (maf-editplus--entry-at-point))
                    "x<-1 U x>1"))
  (call-interactively 'maf-edit-commit)
  (cl-assert (equal (calc-top 1)
                    '(calcFunc-lor (calcFunc-lt (var x var-x) -1)
                                   (calcFunc-gt (var x var-x) 1))))
  (cl-assert (string= (math-format-value (calc-top 1) 1000)
                      "x < -1 || x > 1"))
  (calc-pop (calc-stack-size))

  ;; Whatever the operands are: vectors on both sides, and a group or
  ;; a signed term counts as an operand the same way an atom does.
  (call-interactively 'maf-edit-add-entry-below)
  (progn (insert "[1,2] U [3]") nil)
  (call-interactively 'maf-edit-commit)
  (cl-assert (equal (calc-top 1) '(calcFunc-lor (vec 1 2) (vec 3))))
  (calc-pop (calc-stack-size))

  (call-interactively 'maf-edit-add-entry-below)
  (progn (insert "(a) U -b") nil)
  (call-interactively 'maf-edit-commit)
  (cl-assert (equal (calc-top 1)
                    '(calcFunc-lor (var a var-a) (neg (var b var-b)))))
  (calc-pop (calc-stack-size))

  ;; Every U of a chain is traded, not just the first.
  (call-interactively 'maf-edit-add-entry-below)
  (progn (insert "x>1 U x<-1 U x=0") nil)
  (call-interactively 'maf-edit-commit)
  (cl-assert (string= (math-format-value (calc-top 1) 1000)
                      "x > 1 || x < -1 || x = 0"))
  (calc-pop (calc-stack-size))

  ;; A U with an operator rather than an operand beside it is the
  ;; variable it looks like: the union takes two operands, and this U
  ;; has one.
  (call-interactively 'maf-edit-add-entry-below)
  (progn (insert "E = U + K") nil)
  (call-interactively 'maf-edit-commit)
  (cl-assert (equal (calc-top 1)
                    '(calcFunc-eq (var E var-E)
                                  (+ (var U var-U) (var K var-K)))))
  (calc-pop (calc-stack-size))

  ;; What the || commits as is what an edit session started on it
  ;; hands back, so a committed union survives a second round trip —
  ;; unchanged text keeps its value object, and changed text parses
  ;; the bar calc itself wrote.
  (call-interactively 'maf-edit-add-entry-below)
  (progn (insert "a U b") nil)
  (call-interactively 'maf-edit-commit)
  (call-interactively 'maf-edit)
  (cl-assert (equal (maf-edit--entry-text (maf-editplus--entry-at-point))
                    "a || b"))
  (progn (end-of-line) (insert "+1") nil)
  (call-interactively 'maf-edit-commit)
  (cl-assert (equal (calc-top 1)
                    '(calcFunc-lor (var a var-a) (+ (var b var-b) 1))))
  (calc-pop (calc-stack-size))

  ;; The discriminations, on the rewrite itself. A U inside a name
  ;; belongs to the name, and one written tight against a neighbour is
  ;; a factor: only whitespace on both sides makes it the operator.
  (cl-assert (equal (maf-editplus--commit-union "aUb") "aUb"))
  (cl-assert (equal (maf-editplus--commit-union "x^2 U_1") "x^2 U_1"))
  (cl-assert (equal (maf-editplus--commit-union "a U b") "a || b"))
  (cl-assert (equal (maf-editplus--commit-union "a  U  b") "a  ||  b"))
  ;; A U at either end of the text has no second operand.
  (cl-assert (equal (maf-editplus--commit-union "U") "U"))
  (cl-assert (equal (maf-editplus--commit-union "U + 1") "U + 1"))
  (cl-assert (equal (maf-editplus--commit-union "x = U") "x = U"))
  ;; And a U inside a string literal is text, like every other
  ;; character there.
  (cl-assert (equal (maf-editplus--commit-union "\"a U b\"") "\"a U b\""))
  (cl-assert (equal (maf-editplus--commit-union "x + \"U\" U y")
                    "x + \"U\" || y")))
