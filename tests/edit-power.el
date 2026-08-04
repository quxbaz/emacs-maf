;; Raising to a power inside a maf-edit session: M-2 through M-9 write
;; the exponent named by the key (`maf-editplus-insert-power'), and `:'
;; writes ^2 and then counts it up, one press per power
;; (`maf-editplus-raise-power'). A step passes when it raises no error.
;;
;; The contract: the meta-digits never look behind point, so an
;; exponent already there stacks into a tower; `:' edits one in place,
;; but only a run of digits with the caret directly in front of it; and
;; the two keys compose, since both leave point after the digits.

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
  (call-interactively 'maf-edit-add-entry)
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
  (call-interactively 'maf-edit-add-entry)
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
  (call-interactively 'maf-edit-add-entry)
  (progn (execute-kbd-macro "x") nil)
  (progn (execute-kbd-macro (kbd "M-9")) nil)
  (progn (execute-kbd-macro ":") nil)
  (cl-assert (equal (maf-edit--entry-text (maf-editplus--entry-at-point))
                    "x^10"))
  (call-interactively 'maf-edit-discard)

  ;; Digits with no caret in front of them are a number, not an
  ;; exponent: they are squared, not counted up.
  (call-interactively 'maf-edit-add-entry)
  (progn (execute-kbd-macro "12") nil)
  (progn (execute-kbd-macro ":") nil)
  (cl-assert (equal (maf-edit--entry-text (maf-editplus--entry-at-point))
                    "12^2"))
  (call-interactively 'maf-edit-discard)

  ;; Neither is an exponent point has since typed past.
  (call-interactively 'maf-edit-add-entry)
  (progn (execute-kbd-macro "x^2*y") nil)
  (progn (execute-kbd-macro ":") nil)
  (cl-assert (equal (maf-edit--entry-text (maf-editplus--entry-at-point))
                    "x^2*y^2"))
  (call-interactively 'maf-edit-discard)

  ;; What the keys write is a power to calc, not just a caret and a
  ;; digit in the text. Committed as maf commits, so the power stands
  ;; rather than being worked out.
  (call-interactively 'maf-edit-add-entry)
  (progn (execute-kbd-macro "3") nil)
  (progn (execute-kbd-macro (kbd "M-4")) nil)
  (call-interactively 'maf-edit-commit)
  (cl-assert (equal (calc-top 1) '(^ 3 4)))
  (calc-pop (calc-stack-size))

  (call-interactively 'maf-edit-add-entry)
  (progn (execute-kbd-macro "2") nil)
  (progn (execute-kbd-macro ":") nil)
  (progn (execute-kbd-macro ":") nil)
  (call-interactively 'maf-edit-commit)
  (cl-assert (equal (calc-top 1) '(^ 2 3)))
  (calc-pop (calc-stack-size))

  ;; The command behind the meta-digits is theirs alone: reached any
  ;; other way there is no digit to read, and it says so rather than
  ;; writing a caret and whatever key ran it.
  (call-interactively 'maf-edit-add-entry)
  (cl-assert (string-match-p
              "Not a power key"
              (condition-case e
                  (progn (call-interactively 'maf-editplus-insert-power) "")
                (error (error-message-string e)))))
  (call-interactively 'maf-edit-discard))
