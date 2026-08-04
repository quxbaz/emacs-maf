;; Commit reads an entry's own commas as a vector: 1,2,3 becomes
;; [1, 2, 3]. The brackets are punctuation calc wants and the writer
;; does not, so `maf-edit-commit' supplies them. A step passes when it
;; raises no error.
;;
;; The contract: only a comma at the top level counts — one inside
;; delimiters belongs to whatever encloses it, and one inside a string
;; is text — and whatever the commas separate comes along, so a row of
;; vectors is a matrix. Nothing that already parses is touched, calc
;; having no reading at all for a top-level comma.

(maf-step
  (calc-pop (calc-stack-size))

  ;; The shape asked for.
  (call-interactively 'maf-edit-add-entry-below)
  (progn (execute-kbd-macro "1,2,3") nil)
  (call-interactively 'maf-edit-commit)
  (cl-assert (equal (calc-top 1) '(vec 1 2 3)))
  (calc-pop (calc-stack-size))

  ;; Two elements, and spacing around the commas is the parser's
  ;; business rather than this rule's.
  (call-interactively 'maf-edit-add-entry-below)
  (progn (execute-kbd-macro "1 , 2") nil)
  (call-interactively 'maf-edit-commit)
  (cl-assert (equal (calc-top 1) '(vec 1 2)))
  (calc-pop (calc-stack-size))

  ;; Whatever the commas separate comes along: a row of vectors is the
  ;; matrix, and a row of equations the vector of both.
  (call-interactively 'maf-edit-add-entry-below)
  (progn (insert "[1,2],[3,4]") nil)
  (call-interactively 'maf-edit-commit)
  (cl-assert (equal (calc-top 1) '(vec (vec 1 2) (vec 3 4))))
  (calc-pop (calc-stack-size))

  (call-interactively 'maf-edit-add-entry-below)
  (progn (insert "x=1,y=2") nil)
  (call-interactively 'maf-edit-commit)
  (cl-assert (string= (math-format-value (calc-top 1) 1000) "[x = 1, y = 2]"))
  (calc-pop (calc-stack-size))

  ;; A comma with something around it is that thing's, and none of
  ;; these entries is one the rule may touch. Each already parses —
  ;; which is the whole test, since calc has no reading for a comma at
  ;; the top level and so nothing that parses can have one.
  (call-interactively 'maf-edit-add-entry-below)
  (progn (insert "f(1,2)") nil)
  (call-interactively 'maf-edit-commit)
  (cl-assert (equal (calc-top 1) '(calcFunc-f 1 2)))
  (calc-pop (calc-stack-size))

  (call-interactively 'maf-edit-add-entry-below)
  (progn (insert "[1,2]") nil)
  (call-interactively 'maf-edit-commit)
  (cl-assert (equal (calc-top 1) '(vec 1 2)))
  (calc-pop (calc-stack-size))

  ;; Calc's complex pair, whose comma is the parens'.
  (call-interactively 'maf-edit-add-entry-below)
  (progn (insert "(1,2)") nil)
  (call-interactively 'maf-edit-commit)
  (cl-assert (equal (calc-top 1) '(cplx 1 2)))
  (calc-pop (calc-stack-size))

  ;; A comma inside a string is text, not a separator: the entry is the
  ;; string it was written as, three characters long.
  (call-interactively 'maf-edit-add-entry-below)
  (progn (insert "\"a,b\"") nil)
  (call-interactively 'maf-edit-commit)
  (cl-assert (equal (calc-top 1) '(vec 97 44 98)))
  (calc-pop (calc-stack-size))

  ;; The predicate the rule turns on, at the level of text.
  (cl-assert (maf-edit--top-level-comma-p "1,2,3"))
  (cl-assert (maf-edit--top-level-comma-p "[1,2],[3,4]"))
  (cl-assert (not (maf-edit--top-level-comma-p "f(1,2)")))
  (cl-assert (not (maf-edit--top-level-comma-p "[1,2]")))
  (cl-assert (not (maf-edit--top-level-comma-p "\"a,b\"")))
  (cl-assert (not (maf-edit--top-level-comma-p "1+2")))
  ;; A comma past an unbalanced closer is still top level: depth never
  ;; goes negative, as everywhere else in maf-edit.
  (cl-assert (maf-edit--top-level-comma-p ")1,2"))

  ;; Per entry, not per session: the entry with the commas becomes a
  ;; vector and its neighbour is left as it was.
  (call-interactively 'maf-edit-add-entry-below)
  (progn (execute-kbd-macro "1,2") nil)
  (call-interactively 'maf-edit-newline)
  (progn (execute-kbd-macro "9") nil)
  (call-interactively 'maf-edit-commit)
  (cl-assert (equal (calc-top 1) 9))
  (cl-assert (equal (calc-top 2) '(vec 1 2)))
  (calc-pop (calc-stack-size))

  ;; An entry loaded from the stack and left alone keeps its value
  ;; object and is never reparsed, so a vector edited elsewhere in the
  ;; session cannot be wrapped a second time.
  (maf-push "[1,2]")
  (call-interactively 'maf-edit)
  (call-interactively 'maf-edit-commit)
  (cl-assert (equal (calc-top 1) '(vec 1 2)))
  (calc-pop (calc-stack-size))

  ;; Editing that entry reparses it — and the brackets it already
  ;; carries keep its commas out of the rule's reach.
  (maf-push "[1,2]")
  (progn (calc-cursor-stack-index 1) (end-of-line) nil)
  (call-interactively 'maf-edit)
  (progn (execute-kbd-macro "+[0,0]") nil)
  (call-interactively 'maf-edit-commit)
  (cl-assert (equal (calc-top 1) '(+ (vec 1 2) (vec 0 0))))
  (calc-pop (calc-stack-size))

  ;; Text that is broken for some other reason is still refused: the
  ;; rule completes a shape, it does not rescue a parse.
  (call-interactively 'maf-edit-add-entry-below)
  (progn (insert "1,2,(") nil)
  (cl-assert (string-match-p "cannot commit"
                             (condition-case e
                                 (progn (call-interactively 'maf-edit-commit) "")
                               (error (error-message-string e)))))
  (cl-assert maf-edit-mode)             ; still editing, as a block means
  (call-interactively 'maf-edit-discard)
  (calc-pop (calc-stack-size)))
