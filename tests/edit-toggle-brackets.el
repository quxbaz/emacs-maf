;; S-up and S-down inside a maf-edit session retype the delimiters of
;; the group at point (`maf-editplus-toggle-brackets', the editplus
;; module's third delimiter gesture). A step passes when it raises no
;; error.
;;
;; The contract: both ends move together, so the pair is never left
;; mismatched by the gesture; the group is the one point stands on or
;; inside; braces fold into parens, calc reading {1,2} as the vector
;; [1,2]; and a group with only one half typed is left alone.

(maf-step
  ;; A toggle is its own inverse, so both arrows run it — as they do
  ;; for `mafcmd-toggle-op' on the stack.
  (cl-assert (eq (lookup-key maf-edit-mode-map (kbd "S-<up>"))
                 'maf-editplus-toggle-brackets))
  (cl-assert (eq (lookup-key maf-edit-mode-map (kbd "S-<down>"))
                 'maf-editplus-toggle-brackets))

  ;; The gesture as it is used: parens typed, brackets meant. Point is
  ;; inside the group, where the typing left it, and the real key is
  ;; what drives it.
  (call-interactively 'maf-edit-add-entry-below)
  (progn (execute-kbd-macro "(1,2") nil)
  (progn (execute-kbd-macro (kbd "S-<up>")) nil)
  (cl-assert (equal (maf-edit--entry-text (maf-editplus--entry-at-point))
                    "[1,2]"))
  ;; And it commits as the vector it now spells.
  (call-interactively 'maf-edit-commit)
  (cl-assert (equal (calc-top 1) '(vec 1 2)))
  (calc-pop (calc-stack-size))

  ;; Its own inverse, on the other arrow as much as the first.
  (call-interactively 'maf-edit-add-entry-below)
  (progn (execute-kbd-macro "[1,2") nil)
  (call-interactively 'maf-editplus-escape-group)
  (progn (execute-kbd-macro (kbd "S-<down>")) nil)
  (cl-assert (equal (maf-edit--entry-text (maf-editplus--entry-at-point))
                    "(1,2)"))
  (progn (execute-kbd-macro (kbd "S-<down>")) nil)
  (cl-assert (equal (maf-edit--entry-text (maf-editplus--entry-at-point))
                    "[1,2]"))
  (call-interactively 'maf-edit-discard)

  ;; Point on the opener reads forward, as the eye does.
  (call-interactively 'maf-edit-add-entry-below)
  (progn (execute-kbd-macro "(a+b)") nil)
  (maf-edit-move-beginning-of-line 1)
  (cl-assert (eq (char-after) ?\())
  (call-interactively 'maf-editplus-toggle-brackets)
  (cl-assert (equal (maf-edit--entry-text (maf-editplus--entry-at-point))
                    "[a+b]"))
  ;; Point has not moved: the characters are replaced where they sit.
  (cl-assert (eq (char-after) ?\[))
  (call-interactively 'maf-edit-discard)

  ;; A closer just behind point takes the group that ends there, which
  ;; is where `maf-editplus-escape-group' and M-o leave point.
  (call-interactively 'maf-edit-add-entry-below)
  (progn (execute-kbd-macro "1+(a+b)") nil)
  (call-interactively 'maf-editplus-toggle-brackets)
  (cl-assert (equal (maf-edit--entry-text (maf-editplus--entry-at-point))
                    "1+[a+b]"))
  (cl-assert (eolp))
  (call-interactively 'maf-edit-discard)

  ;; The innermost group point stands in is the one that moves, and
  ;; the group around it is left as it was.
  (call-interactively 'maf-edit-add-entry-below)
  (progn (execute-kbd-macro "(1+(a+b))") nil)
  (progn (backward-char 2) nil)
  (call-interactively 'maf-editplus-toggle-brackets)
  (cl-assert (equal (maf-edit--entry-text (maf-editplus--entry-at-point))
                    "(1+[a+b])"))
  ;; Stepping out of it reaches the outer one. Twice: one press leaves
  ;; point just past the inner closer, which by the rule above is still
  ;; the inner group — the second press clears the outer closer too.
  (call-interactively 'maf-editplus-escape-group)
  (call-interactively 'maf-editplus-escape-group)
  (call-interactively 'maf-editplus-toggle-brackets)
  (cl-assert (equal (maf-edit--entry-text (maf-editplus--entry-at-point))
                    "[1+[a+b]]"))
  (call-interactively 'maf-edit-discard)

  ;; An argument list is a group like any other — this is a gesture
  ;; about delimiters, not about what they enclose.
  (call-interactively 'maf-edit-add-entry-below)
  (progn (execute-kbd-macro "sqrt(3)") nil)
  (call-interactively 'maf-editplus-toggle-brackets)
  (cl-assert (equal (maf-edit--entry-text (maf-editplus--entry-at-point))
                    "sqrt[3]"))
  (call-interactively 'maf-edit-discard)

  ;; Braces have no state of their own to hold: calc reads {1,2} as
  ;; the vector [1,2] denotes, so they fold into parens and toggle
  ;; between the two thereafter.
  (call-interactively 'maf-edit-add-entry-below)
  (progn (insert "{1,2}") nil)
  (progn (backward-char 1) nil)
  (call-interactively 'maf-editplus-toggle-brackets)
  (cl-assert (equal (maf-edit--entry-text (maf-editplus--entry-at-point))
                    "(1,2)"))
  (call-interactively 'maf-editplus-toggle-brackets)
  (cl-assert (equal (maf-edit--entry-text (maf-editplus--entry-at-point))
                    "[1,2]"))
  (call-interactively 'maf-edit-discard)

  ;; An interval is the exception: there a delimiter is a value, `['
  ;; saying the bound is included and `(' that it is not, so the ends
  ;; are independent and only the one point is at moves. Point after
  ;; the `..' is at the upper end.
  (call-interactively 'maf-edit-add-entry-below)
  (progn (insert "[1 .. 2)") nil)
  (progn (backward-char 1) nil)
  (call-interactively 'maf-editplus-toggle-brackets)
  (cl-assert (equal (maf-edit--entry-text (maf-editplus--entry-at-point))
                    "[1 .. 2]"))
  ;; Both bounds included: calc's mask counts 2 for the lower end and
  ;; 1 for the upper.
  (call-interactively 'maf-edit-commit)
  (cl-assert (equal (calc-top 1) '(intv 3 1 2)))
  (calc-pop (calc-stack-size))

  ;; Before the `..' it is the lower end, and each press moves that
  ;; end alone — pressing on both sides is how a whole interval turns
  ;; over.
  (call-interactively 'maf-edit-add-entry-below)
  (progn (insert "[1 .. 2]") nil)
  (progn (goto-char (- (line-end-position) 6)) nil)
  (cl-assert (eq (char-before) ?1))
  (call-interactively 'maf-editplus-toggle-brackets)
  (cl-assert (equal (maf-edit--entry-text (maf-editplus--entry-at-point))
                    "(1 .. 2]"))
  (progn (goto-char (line-end-position)) nil)
  (call-interactively 'maf-editplus-toggle-brackets)
  (cl-assert (equal (maf-edit--entry-text (maf-editplus--entry-at-point))
                    "(1 .. 2)"))
  (call-interactively 'maf-edit-commit)
  (cl-assert (equal (calc-top 1) '(intv 0 1 2)))
  (calc-pop (calc-stack-size))

  ;; Standing on an end is the same rule, not a second one: the opener
  ;; is before the dots and the closer past them.
  (call-interactively 'maf-edit-add-entry-below)
  (progn (insert "[1 .. 2)") nil)
  (maf-edit-move-beginning-of-line 1)
  (call-interactively 'maf-editplus-toggle-brackets)
  (cl-assert (equal (maf-edit--entry-text (maf-editplus--entry-at-point))
                    "(1 .. 2)"))
  (call-interactively 'maf-edit-discard)

  ;; A decimal point is not a `..', so a plain group full of them
  ;; still moves as a pair.
  (call-interactively 'maf-edit-add-entry-below)
  (progn (insert "(1.5,2.5)") nil)
  (progn (backward-char 1) nil)
  (call-interactively 'maf-editplus-toggle-brackets)
  (cl-assert (equal (maf-edit--entry-text (maf-editplus--entry-at-point))
                    "[1.5,2.5]"))
  (call-interactively 'maf-edit-discard)

  ;; Nor do a nested interval's dots make the group around it one: they
  ;; belong to the group they are in.
  (call-interactively 'maf-edit-add-entry-below)
  (progn (insert "([1 .. 2],3)") nil)
  (progn (goto-char (line-end-position)) nil)
  (call-interactively 'maf-editplus-toggle-brackets)
  (cl-assert (equal (maf-edit--entry-text (maf-editplus--entry-at-point))
                    "[[1 .. 2],3]"))
  (call-interactively 'maf-edit-discard)

  ;; A group whose other half has not been typed yet has no pair to
  ;; toggle, and the entry is left exactly as it stands.
  (call-interactively 'maf-edit-add-entry-below)
  (progn (insert "(1,2") nil)
  (progn (goto-char (line-end-position)) nil)
  (cl-assert (string-match-p
              "No complete group"
              (condition-case e
                  (progn (call-interactively 'maf-editplus-toggle-brackets) "")
                (error (error-message-string e)))))
  (cl-assert (equal (maf-edit--entry-text (maf-editplus--entry-at-point))
                    "(1,2"))
  (call-interactively 'maf-edit-discard)

  ;; Neither is there anything to toggle where no group reaches point.
  (call-interactively 'maf-edit-add-entry-below)
  (progn (execute-kbd-macro "a+b") nil)
  (cl-assert (string-match-p
              "No complete group"
              (condition-case e
                  (progn (call-interactively 'maf-editplus-toggle-brackets) "")
                (error (error-message-string e)))))
  (call-interactively 'maf-edit-discard)

  ;; The scan never leaves the entry point is in: a neighbour's
  ;; delimiters are not this entry's to retype.
  (call-interactively 'maf-edit-add-entry-below)
  (progn (execute-kbd-macro "(a+b)") nil)
  (call-interactively 'maf-edit-newline)
  (progn (execute-kbd-macro "c") nil)
  (cl-assert (string-match-p
              "No complete group"
              (condition-case e
                  (progn (call-interactively 'maf-editplus-toggle-brackets) "")
                (error (error-message-string e)))))
  (call-interactively 'maf-edit-discard)

  ;; The home line is not an entry, and the dot there is not a group.
  (maf-push "[1,2]")
  (maf-edit-mode 1)
  (progn (goto-char (point-max)) nil)
  (cl-assert (null (maf-editplus--entry-at-point)))
  (cl-assert (string-match-p
              "not in a stack entry"
              (condition-case e
                  (progn (call-interactively 'maf-editplus-toggle-brackets) "")
                (error (error-message-string e)))))
  (call-interactively 'maf-edit-discard)
  (calc-pop (calc-stack-size))

  ;; Outside a session it refuses rather than editing calc's rendered
  ;; stack, which is full of delimiters it has no business retyping.
  (maf-push "[1,2]")
  (progn (calc-cursor-stack-index 1)
         (goto-char (line-end-position)) nil)
  (cl-assert (string-match-p
              "not active"
              (condition-case e
                  (progn (call-interactively 'maf-editplus-toggle-brackets) "")
                (error (error-message-string e)))))
  (cl-assert (equal (calc-top 1) '(vec 1 2)))
  (calc-pop (calc-stack-size)))
