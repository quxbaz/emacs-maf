;; C-RET inside a maf-edit session writes the group at point again
;; just after itself, point landing at the matching place in the copy
;; (`maf-editplus-duplicate-group', ported from
;; my/calc-duplicate-paren-expr). A step passes when it raises no
;; error. The contract: the group is the one point stands on or
;; inside, a call comes along with its name and a bare number does
;; not, nothing goes between the two copies, and the scan never leaves
;; the entry point started in.

(maf-step
  ;; The module owns the key, and it lives in maf-edit's own map — so
  ;; it means nothing until a session is running.
  (cl-assert (eq (lookup-key maf-edit-mode-map (kbd "C-<return>"))
                 'maf-editplus-duplicate-group))

  ;; The gesture as it is actually used, driven by the real key: type
  ;; the group, duplicate it, change one character in the copy. Point
  ;; lands where the change is wanted, which is the whole point of it.
  (call-interactively 'maf-edit-add-entry-below)
  (progn (execute-kbd-macro "(x+1") nil)
  (progn (execute-kbd-macro (kbd "C-<return>")) nil)
  (cl-assert (equal (maf-edit--entry-text (maf-editplus--entry-at-point))
                    "(x+1)(x+1)"))
  (cl-assert (looking-at-p ")$"))       ; inside the copy, not after it
  (progn (execute-kbd-macro (kbd "C-b DEL -")) nil)
  (cl-assert (equal (maf-edit--entry-text (maf-editplus--entry-at-point))
                    "(x+1)(x-1)"))
  ;; Nothing is written between the two: calc reads juxtaposition as
  ;; multiplication, so the entry commits as the product it looks like.
  (call-interactively 'maf-edit-commit)
  (cl-assert (equal (math-format-flat-expr (calc-top-n 1) 0)
                    "(x + 1) * (x - 1)"))
  (calc-pop (calc-stack-size))

  ;; A press just after the closer takes the group that ends there, and
  ;; point stays just after a closer — the copy's.
  (call-interactively 'maf-edit-add-entry-below)
  (progn (insert "(a+b)") nil)
  (call-interactively 'maf-editplus-duplicate-group)
  (cl-assert (equal (maf-edit--entry-text (maf-editplus--entry-at-point))
                    "(a+b)(a+b)"))
  (cl-assert (eolp))
  (call-interactively 'maf-edit-discard)

  ;; A press with point before the opener takes the group that opens
  ;; there, as `maf-editplus-toggle-brackets' does, and point stays on
  ;; an opener — the copy's.
  (call-interactively 'maf-edit-add-entry-below)
  (progn (insert "(a+b)") (maf-edit-move-beginning-of-line 1) nil)
  (call-interactively 'maf-editplus-duplicate-group)
  (cl-assert (equal (maf-edit--entry-text (maf-editplus--entry-at-point))
                    "(a+b)(a+b)"))
  (cl-assert (looking-at-p "(a\\+b)$"))
  (call-interactively 'maf-edit-discard)

  ;; A call is copied whole, name and all: the legacy version left the
  ;; head behind and wrote sqrt(3)(3).
  (call-interactively 'maf-edit-add-entry-below)
  (progn (insert "sqrt(3)") nil)
  (call-interactively 'maf-editplus-duplicate-group)
  (cl-assert (equal (maf-edit--entry-text (maf-editplus--entry-at-point))
                    "sqrt(3)sqrt(3)"))
  (cl-assert (eolp))
  (call-interactively 'maf-edit-discard)

  ;; A number in that place is a factor and not a name, so 2(a+b) is a
  ;; product of two things: the group alone is copied.
  (call-interactively 'maf-edit-add-entry-below)
  (progn (insert "2(a+b)") (backward-char 1) nil)
  (call-interactively 'maf-editplus-duplicate-group)
  (cl-assert (equal (maf-edit--entry-text (maf-editplus--entry-at-point))
                    "2(a+b)(a+b)"))
  (call-interactively 'maf-edit-discard)

  ;; The group point is inside is the innermost one, and the name it
  ;; belongs to comes with it.
  (call-interactively 'maf-edit-add-entry-below)
  (progn (insert "f(g(x))") (backward-char 2) nil)
  (cl-assert (looking-at-p "))$"))
  (call-interactively 'maf-editplus-duplicate-group)
  (cl-assert (equal (maf-edit--entry-text (maf-editplus--entry-at-point))
                    "f(g(x)g(x))"))
  (cl-assert (looking-at-p "))$"))      ; matching place in the copy
  (call-interactively 'maf-edit-discard)

  ;; Brackets are groups too, and juxtaposition means multiplication
  ;; there as well — which for two vectors is their dot product.
  (call-interactively 'maf-edit-add-entry-below)
  (progn (insert "[1,2]") nil)
  (call-interactively 'maf-editplus-duplicate-group)
  (cl-assert (equal (maf-edit--entry-text (maf-editplus--entry-at-point))
                    "[1,2][1,2]"))
  (call-interactively 'maf-edit-commit)
  (cl-assert (equal (math-format-flat-expr (calc-top-n 1) 0) "5"))
  (calc-pop (calc-stack-size))

  ;; A group spanning lines is copied as one line: the pad stamped on
  ;; the continuation is furniture, and the break is whitespace to the
  ;; parser either way.
  (call-interactively 'maf-edit-add-entry-below)
  (progn (insert "(a+") nil)
  (call-interactively 'maf-edit-newline)
  (progn (insert "b)") (backward-char 1) nil)
  (call-interactively 'maf-editplus-duplicate-group)
  (cl-assert (equal (maf-edit--entry-text (maf-editplus--entry-at-point))
                    "(a+ b)(a+ b)"))
  (call-interactively 'maf-edit-discard)

  ;; No group in the entry, and nothing is changed.
  (call-interactively 'maf-edit-add-entry-below)
  (progn (execute-kbd-macro "a+b") nil)
  (cl-assert (string-match-p "No complete group"
                             (condition-case e
                                 (progn (call-interactively
                                         'maf-editplus-duplicate-group) "")
                               (error (error-message-string e)))))
  (cl-assert (equal (maf-edit--entry-text (maf-editplus--entry-at-point))
                    "a+b"))
  (call-interactively 'maf-edit-discard)

  ;; A group whose closer has not been typed yet is not a pair to
  ;; copy — half of one is not a group.
  (call-interactively 'maf-edit-add-entry-below)
  (progn (insert "sin(x") nil)
  (cl-assert (string-match-p "No complete group"
                             (condition-case e
                                 (progn (call-interactively
                                         'maf-editplus-duplicate-group) "")
                               (error (error-message-string e)))))
  (call-interactively 'maf-edit-discard)

  ;; The scan stops at the entry point is in: the `)' one entry further
  ;; down the buffer is not this entry's, and cannot be copied into it.
  (maf-push "x+y")
  (maf-push "(c)")
  (maf-edit-mode 1)
  (progn (goto-char (point-min))
         (maf-edit-move-beginning-of-line 1) nil)
  (cl-assert (looking-at-p "x"))
  (cl-assert (string-match-p "No complete group"
                             (condition-case e
                                 (progn (call-interactively
                                         'maf-editplus-duplicate-group) "")
                               (error (error-message-string e)))))
  (call-interactively 'maf-edit-discard)
  (calc-pop (calc-stack-size))

  ;; Outside a session the command refuses rather than reaching for
  ;; entry overlays that are not there. The key never arrives here — it
  ;; is bound in `maf-edit-mode-map' alone — so M-x is the only route,
  ;; and it is the one guarded.
  (maf-push "f(g(x))")
  (progn (calc-cursor-stack-index 1)
         (search-forward "x" (line-end-position))
         (backward-char 1) nil)
  (cl-assert (string-match-p "not active"
                             (condition-case e
                                 (progn (call-interactively
                                         'maf-editplus-duplicate-group) "")
                               (error (error-message-string e)))))
  (cl-assert (looking-at-p "x"))        ; nothing inserted, point unmoved
  (calc-pop (calc-stack-size)))
