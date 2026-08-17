;; Deleting a power whole inside a maf-edit session: DEL runs
;; `maf-editplus-delete-backward' and C-d its forward twin
;; `maf-editplus-delete-forward', and deleting a power's operator from
;; either side — the caret, or a star of `**' — deletes the exponent
;; with it, plus the parentheses the base then no longer needs. A step
;; passes when it raises no error.
;;
;; The contract: what the operator heads is the parse's answer, so the
;; exponent goes whole whatever its shape — digits, a call, a signed
;; number, a tower folded to the right — while a caret the entry does
;; not read as a power deletes as a plain character. The base's bare
;; pair goes only where it stands alone as one element of the entry
;; (`maf-editplus--whole-element-p'); beside an operator it still
;; groups, and stays. Everywhere else each key is the plain deletion
;; it always was.

(maf-step
  ;; The keys and the commands.
  (cl-assert (eq (lookup-key maf-edit-mode-map (kbd "DEL"))
                 'maf-editplus-delete-backward))
  (cl-assert (eq (lookup-key maf-edit-mode-map (kbd "C-d"))
                 'maf-editplus-delete-forward))

  ;; The caret takes its exponent with it: x^3 minus the caret is not
  ;; the name x3.
  (call-interactively 'maf-edit-add-entry-below)
  (progn (execute-kbd-macro "x^3") nil)
  (progn (backward-char 1) nil)
  (progn (execute-kbd-macro (kbd "DEL")) nil)
  (cl-assert (equal (maf-edit--entry-text (maf-editplus--entry-at-point))
                    "x"))
  (call-interactively 'maf-edit-discard)

  ;; An exponent in a group goes whole, and the base's own pair goes
  ;; with it — alone in the entry, the parens carried the power and
  ;; nothing else.
  (call-interactively 'maf-edit-add-entry-below)
  (progn (execute-kbd-macro "(x + 1)^(a + b)") nil)
  (progn (maf-edit-move-beginning-of-line 1) (forward-char 8) nil)
  (progn (execute-kbd-macro (kbd "DEL")) nil)
  (cl-assert (equal (maf-edit--entry-text (maf-editplus--entry-at-point))
                    "x + 1"))
  (call-interactively 'maf-edit-discard)

  ;; Beside an operator the pair still groups, so it stays: 2*x+1 is a
  ;; different formula.
  (call-interactively 'maf-edit-add-entry-below)
  (progn (execute-kbd-macro "2*(x+1)^2") nil)
  (progn (maf-edit-move-beginning-of-line 1) (forward-char 8) nil)
  (progn (execute-kbd-macro (kbd "DEL")) nil)
  (cl-assert (equal (maf-edit--entry-text (maf-editplus--entry-at-point))
                    "2*(x+1)"))
  (call-interactively 'maf-edit-discard)

  ;; Inside a call the argument is one element, so the pair is
  ;; furniture there too.
  (call-interactively 'maf-edit-add-entry-below)
  (progn (execute-kbd-macro "ln((a+b)^2)") nil)
  (progn (maf-edit-move-beginning-of-line 1) (forward-char 9) nil)
  (progn (execute-kbd-macro (kbd "DEL")) nil)
  (cl-assert (equal (maf-edit--entry-text (maf-editplus--entry-at-point))
                    "ln(a+b)"))
  (call-interactively 'maf-edit-discard)

  ;; Powers fold right, so the first caret heads the whole tower and
  ;; the second only its own step.
  (call-interactively 'maf-edit-add-entry-below)
  (progn (execute-kbd-macro "x^2^3") nil)
  (progn (maf-edit-move-beginning-of-line 1) (forward-char 2) nil)
  (progn (execute-kbd-macro (kbd "DEL")) nil)
  (cl-assert (equal (maf-edit--entry-text (maf-editplus--entry-at-point))
                    "x"))
  (call-interactively 'maf-edit-discard)

  (call-interactively 'maf-edit-add-entry-below)
  (progn (execute-kbd-macro "x^2^3") nil)
  (progn (maf-edit-move-beginning-of-line 1) (forward-char 4) nil)
  (progn (execute-kbd-macro (kbd "DEL")) nil)
  (cl-assert (equal (maf-edit--entry-text (maf-editplus--entry-at-point))
                    "x^2"))
  (call-interactively 'maf-edit-discard)

  ;; A call and a signed number are each one exponent.
  (call-interactively 'maf-edit-add-entry-below)
  (progn (execute-kbd-macro "x^sqrt(2)") nil)
  (progn (maf-edit-move-beginning-of-line 1) (forward-char 2) nil)
  (progn (execute-kbd-macro (kbd "DEL")) nil)
  (cl-assert (equal (maf-edit--entry-text (maf-editplus--entry-at-point))
                    "x"))
  (call-interactively 'maf-edit-discard)

  (call-interactively 'maf-edit-add-entry-below)
  (progn (execute-kbd-macro "x^-3") nil)
  (progn (maf-edit-move-beginning-of-line 1) (forward-char 2) nil)
  (progn (execute-kbd-macro (kbd "DEL")) nil)
  (cl-assert (equal (maf-edit--entry-text (maf-editplus--entry-at-point))
                    "x"))
  (call-interactively 'maf-edit-discard)

  ;; `**' is the same power in calc's other spelling: its tail is not
  ;; a `*' to backspace alone. A single `*' is the product it looks
  ;; like, and deletes as a plain character.
  (call-interactively 'maf-edit-add-entry-below)
  (progn (execute-kbd-macro "x**3") nil)
  (progn (backward-char 1) nil)
  (progn (execute-kbd-macro (kbd "DEL")) nil)
  (cl-assert (equal (maf-edit--entry-text (maf-editplus--entry-at-point))
                    "x"))
  (call-interactively 'maf-edit-discard)

  (call-interactively 'maf-edit-add-entry-below)
  (progn (execute-kbd-macro "x*3") nil)
  (progn (backward-char 1) nil)
  (progn (execute-kbd-macro (kbd "DEL")) nil)
  (cl-assert (equal (maf-edit--entry-text (maf-editplus--entry-at-point))
                    "x3"))
  (call-interactively 'maf-edit-discard)

  ;; The keys compose: DEL over the digit is plain deletion, and the
  ;; next press is on the caret — a power with no exponent yet, still
  ;; deleted as the power it is.
  (call-interactively 'maf-edit-add-entry-below)
  (progn (execute-kbd-macro "x^3") nil)
  (progn (execute-kbd-macro (kbd "DEL")) nil)
  (cl-assert (equal (maf-edit--entry-text (maf-editplus--entry-at-point))
                    "x^"))
  (progn (execute-kbd-macro (kbd "DEL")) nil)
  (cl-assert (equal (maf-edit--entry-text (maf-editplus--entry-at-point))
                    "x"))
  (call-interactively 'maf-edit-discard)

  ;; The inverse of the raise: `:' on the operator writes the pair
  ;; that keeps the text honest, and DEL on the caret takes it back
  ;; out, point back where the raise found it.
  (call-interactively 'maf-edit-add-entry-below)
  (progn (execute-kbd-macro "a+b") nil)
  (progn (maf-edit-move-beginning-of-line 1) (forward-char 1) nil)
  (progn (execute-kbd-macro ":") nil)
  (cl-assert (equal (maf-edit--entry-text (maf-editplus--entry-at-point))
                    "(a+b)^2"))
  ;; The raise leaves point on the caret; the backspace is pressed
  ;; from the far side of it.
  (progn (forward-char 1) nil)
  (progn (execute-kbd-macro (kbd "DEL")) nil)
  (cl-assert (equal (maf-edit--entry-text (maf-editplus--entry-at-point))
                    "a+b"))
  (call-interactively 'maf-edit-discard)

  ;; What deletes is a power the entry reads: a caret inside a string
  ;; is a character, and deletes as one.
  (call-interactively 'maf-edit-add-entry-below)
  (progn (execute-kbd-macro "\"a^b\"") nil)
  (progn (maf-edit-move-beginning-of-line 1) (forward-char 3) nil)
  (progn (execute-kbd-macro (kbd "DEL")) nil)
  (cl-assert (equal (maf-edit--entry-text (maf-editplus--entry-at-point))
                    "\"ab\""))
  (call-interactively 'maf-edit-discard)

  ;; C-d is the same gesture from the other side: point on the caret,
  ;; the operator and its exponent go together — here inside a group,
  ;; where the base needs no unwrapping.
  (call-interactively 'maf-edit-add-entry-below)
  (progn (execute-kbd-macro "1 / (x^2 - 1)") nil)
  (progn (maf-edit-move-beginning-of-line 1) (forward-char 6) nil)
  (progn (execute-kbd-macro (kbd "C-d")) nil)
  (cl-assert (equal (maf-edit--entry-text (maf-editplus--entry-at-point))
                    "1 / (x - 1)"))
  (call-interactively 'maf-edit-discard)

  ;; And the base's own pair goes forward as it does backward, where
  ;; it stands alone in the entry.
  (call-interactively 'maf-edit-add-entry-below)
  (progn (execute-kbd-macro "(a+b)^2") nil)
  (progn (maf-edit-move-beginning-of-line 1) (forward-char 5) nil)
  (progn (execute-kbd-macro (kbd "C-d")) nil)
  (cl-assert (equal (maf-edit--entry-text (maf-editplus--entry-at-point))
                    "a+b"))
  (call-interactively 'maf-edit-discard)

  ;; Either star of `**' is the operator: deleting forward into its
  ;; second half must not leave the first behind as a `*'.
  (call-interactively 'maf-edit-add-entry-below)
  (progn (execute-kbd-macro "x**3") nil)
  (progn (maf-edit-move-beginning-of-line 1) (forward-char 1) nil)
  (progn (execute-kbd-macro (kbd "C-d")) nil)
  (cl-assert (equal (maf-edit--entry-text (maf-editplus--entry-at-point))
                    "x"))
  (call-interactively 'maf-edit-discard)

  (call-interactively 'maf-edit-add-entry-below)
  (progn (execute-kbd-macro "x**3") nil)
  (progn (maf-edit-move-beginning-of-line 1) (forward-char 2) nil)
  (progn (execute-kbd-macro (kbd "C-d")) nil)
  (cl-assert (equal (maf-edit--entry-text (maf-editplus--entry-at-point))
                    "x"))
  (call-interactively 'maf-edit-discard)

  ;; On any other character C-d is plain forward deletion — a lone
  ;; `*' is the product it looks like.
  (call-interactively 'maf-edit-add-entry-below)
  (progn (execute-kbd-macro "x*3") nil)
  (progn (maf-edit-move-beginning-of-line 1) (forward-char 1) nil)
  (progn (execute-kbd-macro (kbd "C-d")) nil)
  (cl-assert (equal (maf-edit--entry-text (maf-editplus--entry-at-point))
                    "x3"))
  (call-interactively 'maf-edit-discard)

  (call-interactively 'maf-edit-add-entry-below)
  (progn (execute-kbd-macro "x^3") nil)
  (progn (maf-edit-move-beginning-of-line 1) nil)
  (progn (execute-kbd-macro (kbd "C-d")) nil)
  (cl-assert (equal (maf-edit--entry-text (maf-editplus--entry-at-point))
                    "^3"))
  (call-interactively 'maf-edit-discard)

  ;; What commits after the gesture is the base alone.
  (call-interactively 'maf-edit-add-entry-below)
  (progn (execute-kbd-macro "(x + 1)^(a + b)") nil)
  (progn (maf-edit-move-beginning-of-line 1) (forward-char 8) nil)
  (progn (execute-kbd-macro (kbd "DEL")) nil)
  (call-interactively 'maf-edit-commit)
  (cl-assert (equal (calc-top 1) '(+ (var x var-x) 1)))
  (calc-pop (calc-stack-size)))
