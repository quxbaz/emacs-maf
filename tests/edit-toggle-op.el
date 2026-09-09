;; S-up and S-down inside a maf-edit session toggle what point is on
;; (`maf-editplus-toggle-op', the editplus module's counterpart of
;; `mafcmd-toggle-op' on the stack): an operator flips to its partner,
;; a term becomes its reciprocal, and a delimiter retypes its group —
;; the delimiter half is tests/edit-toggle-brackets.el's. A step passes
;; when it raises no error.
;;
;; The contract: + and -, * and / trade where they stand, and so does
;; a leading sign; a term turns over as text — a whole number to calc's
;; fraction 1:N, a fraction upside down, anything else under 1 — with
;; the parentheses its place needs; each press undoes the last, so the
;; key is its own inverse everywhere; point stays on the character it
;; named, or at the end after a unit behind point; and a term is named
;; the way the wrap keys name their argument.

(maf-step
  (cl-assert (eq (lookup-key maf-edit-mode-map (kbd "S-<up>"))
                 'maf-editplus-toggle-op))
  (cl-assert (eq (lookup-key maf-edit-mode-map (kbd "S-<down>"))
                 'maf-editplus-toggle-op))

  ;; The gesture as it is used: a sum typed, a difference meant. The
  ;; real key drives it, and the other arrow turns it back.
  (call-interactively 'maf-edit-add-entry-below)
  (progn (execute-kbd-macro "a + b") nil)
  (progn (goto-char (- (line-end-position) 3)) nil)
  (cl-assert (eq (char-after) ?+))
  (progn (execute-kbd-macro (kbd "S-<up>")) nil)
  (cl-assert (equal (maf-edit--entry-text (maf-editplus--entry-at-point))
                    "a - b"))
  ;; Point has not moved: the character is replaced where it sits.
  (cl-assert (eq (char-after) ?-))
  (progn (execute-kbd-macro (kbd "S-<down>")) nil)
  (cl-assert (equal (maf-edit--entry-text (maf-editplus--entry-at-point))
                    "a + b"))
  ;; And it commits as the difference it now spells.
  (progn (execute-kbd-macro (kbd "S-<up>")) nil)
  (call-interactively 'maf-edit-commit)
  (cl-assert (equal (calc-top 1) '(- (var a var-a) (var b var-b))))
  (calc-pop (calc-stack-size))

  ;; A product and a quotient trade the same way.
  (call-interactively 'maf-edit-add-entry-below)
  (progn (execute-kbd-macro "a*b") nil)
  (progn (backward-char 2) nil)
  (call-interactively 'maf-editplus-toggle-op)
  (cl-assert (equal (maf-edit--entry-text (maf-editplus--entry-at-point))
                    "a/b"))
  (call-interactively 'maf-editplus-toggle-op)
  (cl-assert (equal (maf-edit--entry-text (maf-editplus--entry-at-point))
                    "a*b"))
  (call-interactively 'maf-edit-discard)

  ;; The sign in front of a term is an operator too.
  (call-interactively 'maf-edit-add-entry-below)
  (progn (execute-kbd-macro "-x") nil)
  (maf-edit-move-beginning-of-line 1)
  (call-interactively 'maf-editplus-toggle-op)
  (cl-assert (equal (maf-edit--entry-text (maf-editplus--entry-at-point))
                    "+x"))
  (call-interactively 'maf-edit-discard)

  ;; Point reads the padding the way the wrap keys read it: the space
  ;; after an operator names the operator, a +| b flipping the plus,
  ;; while the space after a term names the term behind it, so
  ;; a| + b turns the a over.
  (call-interactively 'maf-edit-add-entry-below)
  (progn (execute-kbd-macro "a + b") nil)
  (progn (goto-char (- (line-end-position) 2)) nil)
  (cl-assert (eq (char-after) ?\s))
  (call-interactively 'maf-editplus-toggle-op)
  (cl-assert (equal (maf-edit--entry-text (maf-editplus--entry-at-point))
                    "a - b"))
  (progn (goto-char (- (line-end-position) 4)) nil)
  (cl-assert (eq (char-after) ?\s))
  (call-interactively 'maf-editplus-toggle-op)
  (cl-assert (equal (maf-edit--entry-text (maf-editplus--entry-at-point))
                    "1/a - b"))
  (call-interactively 'maf-edit-discard)

  ;; A name turns over under 1, and the same press takes the 1/ away
  ;; again. Point stays on the name both times.
  (call-interactively 'maf-edit-add-entry-below)
  (progn (execute-kbd-macro "x") nil)
  (maf-edit-move-beginning-of-line 1)
  (call-interactively 'maf-editplus-toggle-op)
  (cl-assert (equal (maf-edit--entry-text (maf-editplus--entry-at-point))
                    "1/x"))
  (cl-assert (eq (char-after) ?x))
  (call-interactively 'maf-editplus-toggle-op)
  (cl-assert (equal (maf-edit--entry-text (maf-editplus--entry-at-point))
                    "x"))
  (cl-assert (eq (char-after) ?x))
  (call-interactively 'maf-edit-discard)

  ;; A whole number becomes calc's fraction, which commits as one.
  (call-interactively 'maf-edit-add-entry-below)
  (progn (execute-kbd-macro "5") nil)
  (maf-edit-move-beginning-of-line 1)
  (call-interactively 'maf-editplus-toggle-op)
  (cl-assert (equal (maf-edit--entry-text (maf-editplus--entry-at-point))
                    "1:5"))
  (cl-assert (eq (char-after) ?5))
  (call-interactively 'maf-editplus-toggle-op)
  (cl-assert (equal (maf-edit--entry-text (maf-editplus--entry-at-point))
                    "5"))
  (call-interactively 'maf-editplus-toggle-op)
  (call-interactively 'maf-edit-commit)
  (cl-assert (equal (calc-top 1) '(frac 1 5)))
  (calc-pop (calc-stack-size))

  ;; A fraction turns upside down, and 1 is its own reciprocal.
  (call-interactively 'maf-edit-add-entry-below)
  (progn (insert "2:3") nil)
  (maf-edit-move-beginning-of-line 1)
  (call-interactively 'maf-editplus-toggle-op)
  (cl-assert (equal (maf-edit--entry-text (maf-editplus--entry-at-point))
                    "3:2"))
  (call-interactively 'maf-edit-discard)
  (call-interactively 'maf-edit-add-entry-below)
  (progn (execute-kbd-macro "1") nil)
  (maf-edit-move-beginning-of-line 1)
  (call-interactively 'maf-editplus-toggle-op)
  (cl-assert (equal (maf-edit--entry-text (maf-editplus--entry-at-point))
                    "1"))
  (call-interactively 'maf-edit-discard)

  ;; A number in a product stays one atom: 2*5 becomes 2*1:5, no
  ;; parentheses needed.
  (call-interactively 'maf-edit-add-entry-below)
  (progn (execute-kbd-macro "2*5") nil)
  (progn (backward-char 1) nil)
  (call-interactively 'maf-editplus-toggle-op)
  (cl-assert (equal (maf-edit--entry-text (maf-editplus--entry-at-point))
                    "2*1:5"))
  (call-interactively 'maf-edit-discard)

  ;; Under an operator tighter than /, the quotient is parenthesized:
  ;; a/1/x would be (a/1)/x. The inverse takes the pair away with the
  ;; 1/.
  (call-interactively 'maf-edit-add-entry-below)
  (progn (execute-kbd-macro "a/x") nil)
  (progn (backward-char 1) nil)
  (call-interactively 'maf-editplus-toggle-op)
  (cl-assert (equal (maf-edit--entry-text (maf-editplus--entry-at-point))
                    "a/(1/x)"))
  (cl-assert (eq (char-after) ?x))
  (call-interactively 'maf-editplus-toggle-op)
  (cl-assert (equal (maf-edit--entry-text (maf-editplus--entry-at-point))
                    "a/x"))
  (call-interactively 'maf-edit-discard)

  ;; A power's base and the power itself: point on the operand names
  ;; the operand, point on the caret names the node it heads.
  (call-interactively 'maf-edit-add-entry-below)
  (progn (execute-kbd-macro "x^2") nil)
  (maf-edit-move-beginning-of-line 1)
  (call-interactively 'maf-editplus-toggle-op)
  (cl-assert (equal (maf-edit--entry-text (maf-editplus--entry-at-point))
                    "(1/x)^2"))
  (call-interactively 'maf-editplus-toggle-op)
  (cl-assert (equal (maf-edit--entry-text (maf-editplus--entry-at-point))
                    "x^2"))
  (progn (forward-char 1) nil)
  (cl-assert (eq (char-after) ?^))
  (call-interactively 'maf-editplus-toggle-op)
  (cl-assert (equal (maf-edit--entry-text (maf-editplus--entry-at-point))
                    "1/x^2"))
  (cl-assert (eq (char-after) ?^))
  (call-interactively 'maf-editplus-toggle-op)
  (cl-assert (equal (maf-edit--entry-text (maf-editplus--entry-at-point))
                    "x^2"))
  (call-interactively 'maf-edit-discard)

  ;; Under a sum the quotient stands bare: a plus the reciprocal.
  (call-interactively 'maf-edit-add-entry-below)
  (progn (execute-kbd-macro "a+b*c") nil)
  (progn (backward-char 3) nil)
  (cl-assert (eq (char-after) ?b))
  (call-interactively 'maf-editplus-toggle-op)
  (cl-assert (equal (maf-edit--entry-text (maf-editplus--entry-at-point))
                    "a+(1/b)*c"))
  (call-interactively 'maf-editplus-toggle-op)
  (cl-assert (equal (maf-edit--entry-text (maf-editplus--entry-at-point))
                    "a+b*c"))
  (call-interactively 'maf-edit-discard)

  ;; A juxtaposed factor takes a * in front of its quotient: y (1/x)
  ;; would read as a call.
  (call-interactively 'maf-edit-add-entry-below)
  (progn (execute-kbd-macro "y x") nil)
  (progn (backward-char 1) nil)
  (call-interactively 'maf-editplus-toggle-op)
  (cl-assert (equal (maf-edit--entry-text (maf-editplus--entry-at-point))
                    "y*(1/x)"))
  (call-interactively 'maf-edit-discard)

  ;; A call is one unit, named from its head.
  (call-interactively 'maf-edit-add-entry-below)
  (progn (execute-kbd-macro "sin(x)") nil)
  (maf-edit-move-beginning-of-line 1)
  (call-interactively 'maf-editplus-toggle-op)
  (cl-assert (equal (maf-edit--entry-text (maf-editplus--entry-at-point))
                    "1/sin(x)"))
  (call-interactively 'maf-editplus-toggle-op)
  (cl-assert (equal (maf-edit--entry-text (maf-editplus--entry-at-point))
                    "sin(x)"))
  (call-interactively 'maf-edit-discard)

  ;; A sum that is not one unit is parenthesized under the 1. A bare
  ;; pair already there is kept, so 1/(a+b) turns back to (a+b).
  (call-interactively 'maf-edit-add-entry-below)
  (progn (execute-kbd-macro "a+b") nil)
  (progn (backward-char 2) nil)
  (cl-assert (eq (char-after) ?+))
  ;; The plus flips before anything else is asked of it.
  (call-interactively 'maf-editplus-toggle-op)
  (cl-assert (equal (maf-edit--entry-text (maf-editplus--entry-at-point))
                    "a-b"))
  (call-interactively 'maf-editplus-toggle-op)
  (call-interactively 'maf-edit-discard)
  (call-interactively 'maf-edit-add-entry-below)
  (progn (insert "1/(a+b)") nil)
  (progn (backward-char 3) nil)
  (cl-assert (eq (char-after) ?+))
  (call-interactively 'maf-editplus-toggle-op)
  (cl-assert (equal (maf-edit--entry-text (maf-editplus--entry-at-point))
                    "1/(a-b)"))
  (call-interactively 'maf-edit-discard)

  ;; At the end of the entry the unit behind point turns over, and
  ;; point stays at the end, where typing carries on.
  (call-interactively 'maf-edit-add-entry-below)
  (progn (execute-kbd-macro "a+b") nil)
  (call-interactively 'maf-editplus-toggle-op)
  (cl-assert (equal (maf-edit--entry-text (maf-editplus--entry-at-point))
                    "a+1/b"))
  (cl-assert (eolp))
  (call-interactively 'maf-editplus-toggle-op)
  (cl-assert (equal (maf-edit--entry-text (maf-editplus--entry-at-point))
                    "a+b"))
  (call-interactively 'maf-edit-discard)

  ;; 24x is 24 times x, and the x alone is the unit — spelled with the
  ;; * the fused run needs, as 241/x would be another number.
  (call-interactively 'maf-edit-add-entry-below)
  (progn (execute-kbd-macro "24x") nil)
  (call-interactively 'maf-editplus-toggle-op)
  (cl-assert (equal (maf-edit--entry-text (maf-editplus--entry-at-point))
                    "24*(1/x)"))
  (call-interactively 'maf-edit-discard)

  ;; Inside a vector on nothing in particular, the group is what
  ;; point names, and its delimiters trade as they always did.
  (call-interactively 'maf-edit-add-entry-below)
  (progn (insert "[1, 2]") nil)
  (progn (backward-char 3) nil)
  (cl-assert (eq (char-after) ?\s))
  (call-interactively 'maf-editplus-toggle-op)
  (cl-assert (equal (maf-edit--entry-text (maf-editplus--entry-at-point))
                    "(1, 2)"))
  (call-interactively 'maf-edit-discard)

  ;; And an interval's dots name the interval, split as the stack
  ;; splits them: the first dot is the lower end, the second the upper.
  (call-interactively 'maf-edit-add-entry-below)
  (progn (insert "[1 .. 2]") nil)
  (progn (backward-char 5) nil)
  (cl-assert (eq (char-after) ?.))
  (call-interactively 'maf-editplus-toggle-op)
  (cl-assert (equal (maf-edit--entry-text (maf-editplus--entry-at-point))
                    "(1 .. 2]"))
  (progn (forward-char 1) nil)
  (call-interactively 'maf-editplus-toggle-op)
  (cl-assert (equal (maf-edit--entry-text (maf-editplus--entry-at-point))
                    "(1 .. 2)"))
  (call-interactively 'maf-edit-discard)

  ;; An active region is written under 1 exactly as marked, in the
  ;; parentheses that keep it one unit. Marked and pressed in the one
  ;; step: the stepper deactivates the mark around every form it runs.
  (call-interactively 'maf-edit-add-entry-below)
  (progn (execute-kbd-macro "x+y") nil)
  (progn (set-mark (point))
         (maf-edit-move-beginning-of-line 1)
         (activate-mark)
         (call-interactively 'maf-editplus-toggle-op)
         nil)
  (cl-assert (equal (maf-edit--entry-text (maf-editplus--entry-at-point))
                    "1/(x+y)"))
  (cl-assert (not (use-region-p)))
  (call-interactively 'maf-edit-discard)

  ;; Just after an operator there is nothing to name, and the entry
  ;; is left exactly as it stands.
  (call-interactively 'maf-edit-add-entry-below)
  (progn (execute-kbd-macro "a+") nil)
  (cl-assert (string-match-p
              "Nothing to toggle"
              (condition-case e
                  (progn (call-interactively 'maf-editplus-toggle-op) "")
                (error (error-message-string e)))))
  (cl-assert (equal (maf-edit--entry-text (maf-editplus--entry-at-point))
                    "a+"))
  (call-interactively 'maf-edit-discard)

  ;; Outside a session it refuses rather than editing calc's rendered
  ;; stack.
  (maf-push "a + b")
  (progn (calc-cursor-stack-index 1)
         (goto-char (line-end-position)) nil)
  (cl-assert (string-match-p
              "not active"
              (condition-case e
                  (progn (call-interactively 'maf-editplus-toggle-op) "")
                (error (error-message-string e)))))
  (cl-assert (equal (calc-top 1) '(+ (var a var-a) (var b var-b))))
  (calc-pop (calc-stack-size)))
