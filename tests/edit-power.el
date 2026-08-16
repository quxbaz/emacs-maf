;; Raising to a power inside a maf-edit session: M-2 through M-9 write
;; the exponent named by the key (`maf-editplus-insert-power'), and `:'
;; writes ^2 and then counts it up, one press per power
;; (`maf-editplus-raise-power'). A step passes when it raises no error.
;;
;; The contract: the meta-digits never look at anything, so an exponent
;; already there stacks into a tower; `:' raises the sub-expression
;; point names, as L and Q wrap the one point names
;; (`edit-subexpr-target.el'), and counts an exponent up in place when
;; the node it named is already a power written in digits. At the end of
;; the entry — where there is no character under point — that comes to
;; the old rule: a run of digits with the caret directly in front of it
;; is the exponent, and the two keys compose there, both leaving point
;; after the digits.

(maf-step
  ;; Eight keys, one command — the digit comes off the key itself.
  (cl-assert (eq (lookup-key maf-edit-mode-map (kbd "M-2"))
                 'maf-editplus-insert-power))
  (cl-assert (eq (lookup-key maf-edit-mode-map (kbd "M-9"))
                 'maf-editplus-insert-power))
  (cl-assert (eq (lookup-key maf-edit-mode-map (kbd ":"))
                 'maf-editplus-raise-power))
  ;; `;' still types the character `:' gave up, so nothing is lost.
  (cl-assert (eq (lookup-key maf-edit-mode-map (kbd ";"))
                 'maf-edit-insert-colon))

  ;; The digit pressed is the digit written. Driven by the real key, so
  ;; the reading of `last-command-event' is exercised too.
  (call-interactively 'maf-edit-add-entry-below)
  (progn (execute-kbd-macro "x") nil)
  (progn (execute-kbd-macro (kbd "M-3")) nil)
  (cl-assert (equal (maf-edit--entry-text (maf-editplus--entry-at-point))
                    "x^3"))
  (cl-assert (eolp))
  ;; Nothing is examined behind point, so a second one stacks: the
  ;; tower is what was asked for, not a correction of the first.
  (progn (execute-kbd-macro (kbd "M-9")) nil)
  (cl-assert (equal (maf-edit--entry-text (maf-editplus--entry-at-point))
                    "x^3^9"))
  (call-interactively 'maf-edit-discard)

  ;; `:' opens at the square and counts up from there, a press a power.
  (call-interactively 'maf-edit-add-entry-below)
  (progn (execute-kbd-macro "x") nil)
  (progn (execute-kbd-macro ":") nil)
  (cl-assert (equal (maf-edit--entry-text (maf-editplus--entry-at-point))
                    "x^2"))
  (progn (execute-kbd-macro ":") nil)
  (progn (execute-kbd-macro ":") nil)
  (cl-assert (equal (maf-edit--entry-text (maf-editplus--entry-at-point))
                    "x^4"))
  ;; Past a single digit as well — the whole run is the exponent.
  (progn (execute-kbd-macro (kbd "C-u 6 :")) nil)
  (cl-assert (equal (maf-edit--entry-text (maf-editplus--entry-at-point))
                    "x^10"))
  (call-interactively 'maf-edit-discard)

  ;; The two keys compose: M-9 leaves point after the digit, which is
  ;; where `:' looks for one to count up.
  (call-interactively 'maf-edit-add-entry-below)
  (progn (execute-kbd-macro "x") nil)
  (progn (execute-kbd-macro (kbd "M-9")) nil)
  (progn (execute-kbd-macro ":") nil)
  (cl-assert (equal (maf-edit--entry-text (maf-editplus--entry-at-point))
                    "x^10"))
  (call-interactively 'maf-edit-discard)

  ;; Digits with no caret in front of them are a number, not an
  ;; exponent: they are squared, not counted up.
  (call-interactively 'maf-edit-add-entry-below)
  (progn (execute-kbd-macro "12") nil)
  (progn (execute-kbd-macro ":") nil)
  (cl-assert (equal (maf-edit--entry-text (maf-editplus--entry-at-point))
                    "12^2"))
  (call-interactively 'maf-edit-discard)

  ;; Neither is an exponent point has since typed past.
  (call-interactively 'maf-edit-add-entry-below)
  (progn (execute-kbd-macro "x^2*y") nil)
  (progn (execute-kbd-macro ":") nil)
  (cl-assert (equal (maf-edit--entry-text (maf-editplus--entry-at-point))
                    "x^2*y^2"))
  (call-interactively 'maf-edit-discard)

  ;; Back inside the text the key names what it raises the way L does:
  ;; the character under point picks the node, and an operand is raised
  ;; where it stands.
  (call-interactively 'maf-edit-add-entry-below)
  (progn (execute-kbd-macro "a+b*c") nil)
  (progn (maf-edit-move-beginning-of-line 1) (forward-char 2) nil)
  (progn (execute-kbd-macro ":") nil)
  (cl-assert (equal (maf-edit--entry-text (maf-editplus--entry-at-point))
                    "a+b^2*c"))
  ;; Point is left on the caret, so the next press counts the power up
  ;; instead of squaring the exponent it just wrote.
  (progn (execute-kbd-macro ":") nil)
  (cl-assert (equal (maf-edit--entry-text (maf-editplus--entry-at-point))
                    "a+b^3*c"))
  (call-interactively 'maf-edit-discard)

  ;; One character to the left names the product, and there the text
  ;; needs the parentheses to mean it — a+b*c^2 is a different formula.
  (call-interactively 'maf-edit-add-entry-below)
  (progn (execute-kbd-macro "a+b*c") nil)
  (progn (maf-edit-move-beginning-of-line 1) (forward-char 3) nil)
  (progn (execute-kbd-macro ":") nil)
  (cl-assert (equal (maf-edit--entry-text (maf-editplus--entry-at-point))
                    "a+(b*c)^2"))
  (progn (execute-kbd-macro ":") nil)
  (cl-assert (equal (maf-edit--entry-text (maf-editplus--entry-at-point))
                    "a+(b*c)^3"))
  (call-interactively 'maf-edit-discard)

  ;; An active region is raised as one unit, in parens whatever it
  ;; holds — even a single name, which the marks say to treat whole.
  ;; Marked and pressed in the one step: the stepper deactivates the
  ;; mark around every form it runs.
  (call-interactively 'maf-edit-add-entry-below)
  (progn (execute-kbd-macro "ln(xy)") nil)
  (progn (maf-edit-move-beginning-of-line 1)
         (forward-char 3)
         (set-mark (point))
         (forward-char 2)
         (activate-mark)
         (execute-kbd-macro ":")
         nil)
  (cl-assert (equal (maf-edit--entry-text (maf-editplus--entry-at-point))
                    "ln((xy)^2)"))
  ;; Point lands on the caret, the region spent, so the next press
  ;; counts the power up.
  (progn (execute-kbd-macro ":") nil)
  (cl-assert (equal (maf-edit--entry-text (maf-editplus--entry-at-point))
                    "ln((xy)^3)"))
  (call-interactively 'maf-edit-discard)

  ;; Under the input dialect a bare run of letters is a run of
  ;; factors, so raising it whole needs the parens — a bare ^2 would
  ;; take only the last factor. Wanting just the y squared is what
  ;; spacing the run apart is for.
  (call-interactively 'maf-edit-add-entry-below)
  (progn (execute-kbd-macro "ln(xy)") nil)
  (progn (backward-char 1) nil)
  (progn (execute-kbd-macro ":") nil)
  (cl-assert (equal (maf-edit--entry-text (maf-editplus--entry-at-point))
                    "ln((xy)^2)"))
  ;; Point on the caret, so the next press counts the power up.
  (progn (execute-kbd-macro ":") nil)
  (cl-assert (equal (maf-edit--entry-text (maf-editplus--entry-at-point))
                    "ln((xy)^3)"))
  (call-interactively 'maf-edit-discard)

  ;; On the run itself the node is that same run, and the parens go
  ;; in the same way.
  (call-interactively 'maf-edit-add-entry-below)
  (progn (execute-kbd-macro "xy+1") nil)
  (progn (maf-edit-move-beginning-of-line 1) nil)
  (progn (execute-kbd-macro ":") nil)
  (cl-assert (equal (maf-edit--entry-text (maf-editplus--entry-at-point))
                    "(xy)^2+1"))
  (call-interactively 'maf-edit-discard)

  ;; A quoted run is one name — the mark exists to say so — an exempt
  ;; run (pi, bare) is one name without it, and a number is one
  ;; number: each takes the caret as it stands.
  (call-interactively 'maf-edit-add-entry-below)
  (progn (execute-kbd-macro "\\foo") nil)
  (progn (execute-kbd-macro ":") nil)
  (cl-assert (equal (maf-edit--entry-text (maf-editplus--entry-at-point))
                    "\\foo^2"))
  (call-interactively 'maf-edit-discard)

  (call-interactively 'maf-edit-add-entry-below)
  (progn (execute-kbd-macro "P") nil)
  (progn (execute-kbd-macro ":") nil)
  (cl-assert (equal (maf-edit--entry-text (maf-editplus--entry-at-point))
                    "pi^2"))
  (call-interactively 'maf-edit-discard)

  (call-interactively 'maf-edit-add-entry-below)
  (progn (execute-kbd-macro "2.5") nil)
  (progn (execute-kbd-macro ":") nil)
  (cl-assert (equal (maf-edit--entry-text (maf-editplus--entry-at-point))
                    "2.5^2"))
  (call-interactively 'maf-edit-discard)

  ;; The closer of a call names nothing: electric parens leave point
  ;; in front of it for the whole time the argument is typed, so a
  ;; press there raises the term just typed, not the call around it.
  (call-interactively 'maf-edit-add-entry-below)
  (progn (execute-kbd-macro "ln(x y)") nil)
  (progn (backward-char 1) nil)
  (progn (execute-kbd-macro ":") nil)
  (cl-assert (equal (maf-edit--entry-text (maf-editplus--entry-at-point))
                    "ln(x y^2)"))
  ;; And the next press still counts that power up.
  (progn (execute-kbd-macro ":") nil)
  (cl-assert (equal (maf-edit--entry-text (maf-editplus--entry-at-point))
                    "ln(x y^3)"))
  (call-interactively 'maf-edit-discard)

  ;; A call, a vector and a node already in a pair of parentheses each
  ;; read as one unit, so the caret goes straight on the end of them.
  (call-interactively 'maf-edit-add-entry-below)
  (progn (execute-kbd-macro "sqrt(3)+1") nil)
  (progn (maf-edit-move-beginning-of-line 1) nil)
  (progn (execute-kbd-macro ":") nil)
  (cl-assert (equal (maf-edit--entry-text (maf-editplus--entry-at-point))
                    "sqrt(3)^2+1"))
  (call-interactively 'maf-edit-discard)

  (call-interactively 'maf-edit-add-entry-below)
  (progn (execute-kbd-macro "(a+b)*c") nil)
  (progn (maf-edit-move-beginning-of-line 1) nil)
  (progn (execute-kbd-macro ":") nil)
  (cl-assert (equal (maf-edit--entry-text (maf-editplus--entry-at-point))
                    "(a+b)^2*c"))
  (call-interactively 'maf-edit-discard)

  ;; A power point names is counted up in place, wherever point stands
  ;; on it — but only when its exponent is written in digits. x^y is a
  ;; power all the same, and there the key squares it.
  (call-interactively 'maf-edit-add-entry-below)
  (progn (execute-kbd-macro "x^2*y") nil)
  (progn (maf-edit-move-beginning-of-line 1) (forward-char 1) nil)
  (progn (execute-kbd-macro ":") nil)
  (cl-assert (equal (maf-edit--entry-text (maf-editplus--entry-at-point))
                    "x^3*y"))
  (call-interactively 'maf-edit-discard)

  (call-interactively 'maf-edit-add-entry-below)
  (progn (execute-kbd-macro "x^y*z") nil)
  (progn (maf-edit-move-beginning-of-line 1) (forward-char 1) nil)
  (progn (execute-kbd-macro ":") nil)
  (cl-assert (equal (maf-edit--entry-text (maf-editplus--entry-at-point))
                    "(x^y)^2*z"))
  (call-interactively 'maf-edit-discard)

  ;; A sign belongs to the term it signs, and squaring it must not
  ;; quietly negate the square: (-a)^2 is not -a^2.
  (call-interactively 'maf-edit-add-entry-below)
  (progn (execute-kbd-macro "-a*b") nil)
  (progn (maf-edit-move-beginning-of-line 1) nil)
  (progn (execute-kbd-macro ":") nil)
  (cl-assert (equal (maf-edit--entry-text (maf-editplus--entry-at-point))
                    "(-a)^2*b"))
  (call-interactively 'maf-edit-discard)

  ;; The parentheses are the formula's, not just the text's: what
  ;; commits is the square of the sum.
  (call-interactively 'maf-edit-add-entry-below)
  (progn (execute-kbd-macro "a+b") nil)
  (progn (maf-edit-move-beginning-of-line 1) (forward-char 1) nil)
  (progn (execute-kbd-macro ":") nil)
  (call-interactively 'maf-edit-commit)
  (cl-assert (equal (calc-top 1)
                    '(^ (+ (var a var-a) (var b var-b)) 2)))
  (calc-pop (calc-stack-size))

  ;; What the keys write is a power to calc, not just a caret and a
  ;; digit in the text. Committed as maf commits, so the power stands
  ;; rather than being worked out.
  (call-interactively 'maf-edit-add-entry-below)
  (progn (execute-kbd-macro "3") nil)
  (progn (execute-kbd-macro (kbd "M-4")) nil)
  (call-interactively 'maf-edit-commit)
  (cl-assert (equal (calc-top 1) '(^ 3 4)))
  (calc-pop (calc-stack-size))

  (call-interactively 'maf-edit-add-entry-below)
  (progn (execute-kbd-macro "2") nil)
  (progn (execute-kbd-macro ":") nil)
  (progn (execute-kbd-macro ":") nil)
  (call-interactively 'maf-edit-commit)
  (cl-assert (equal (calc-top 1) '(^ 2 3)))
  (calc-pop (calc-stack-size))

  ;; The command behind the meta-digits is theirs alone: reached any
  ;; other way there is no digit to read, and it says so rather than
  ;; writing a caret and whatever key ran it.
  (call-interactively 'maf-edit-add-entry-below)
  (cl-assert (string-match-p
              "Not a power key"
              (condition-case e
                  (progn (call-interactively 'maf-editplus-insert-power) "")
                (error (error-message-string e)))))
  (call-interactively 'maf-edit-discard))
