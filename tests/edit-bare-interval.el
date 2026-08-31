;; An interval typed without its brackets in a maf-edit session gets
;; them filled in at commit (`maf-editplus--commit-interval', on
;; `maf-edit-transform-text-functions'): open at an infinite end,
;; closed at a finite one — -inf..-1 commits as (-inf .. -1], 1..5 as
;; [1 .. 5]. A step passes when it raises no error.
;;
;; The contract: only the entry that is one bare interval whole —
;; exactly one top-level .., no top-level comma. A delimited interval
;; has its .. at depth one and commits with the spelling it was given;
;; anything more composite is left to say what it says.

(maf-step
  (cl-assert (memq 'maf-editplus--commit-interval
                   maf-edit-transform-text-functions))
  (calc-pop (calc-stack-size))

  ;; The shape asked for: a ray to minus infinity, open where it must
  ;; be and closed where it can be.
  (call-interactively 'maf-edit-add-entry-below)
  (progn (insert "-inf..-1") (deactivate-mark) nil)
  (call-interactively 'maf-edit-commit)
  (cl-assert (string= (math-format-flat-expr (calc-top 1) 0)
                      "(-inf .. -1]"))
  (calc-pop (calc-stack-size))

  ;; Finite ends both close; an infinite right end opens; both
  ;; infinities give the fully open line.
  (call-interactively 'maf-edit-add-entry-below)
  (progn (insert "1..5") (deactivate-mark) nil)
  (call-interactively 'maf-edit-commit)
  (cl-assert (string= (math-format-flat-expr (calc-top 1) 0) "[1 .. 5]"))
  (calc-pop (calc-stack-size))

  (call-interactively 'maf-edit-add-entry-below)
  (progn (insert "1..inf") (deactivate-mark) nil)
  (call-interactively 'maf-edit-commit)
  (cl-assert (string= (math-format-flat-expr (calc-top 1) 0) "[1 .. inf)"))
  (calc-pop (calc-stack-size))

  (call-interactively 'maf-edit-add-entry-below)
  (progn (insert "-inf..inf") (deactivate-mark) nil)
  (call-interactively 'maf-edit-commit)
  (cl-assert (string= (math-format-flat-expr (calc-top 1) 0)
                      "(-inf .. inf)"))
  (calc-pop (calc-stack-size))

  ;; Typed delimiters are the user's own choice and pass through:
  ;; the .. sits at depth one, so the transform never sees it.
  (call-interactively 'maf-edit-add-entry-below)
  (progn (insert "[1..5)") (deactivate-mark) nil)
  (call-interactively 'maf-edit-commit)
  (cl-assert (string= (math-format-flat-expr (calc-top 1) 0) "[1 .. 5)"))
  (calc-pop (calc-stack-size))

  ;; Float endpoints: the decimal points do not read as the token.
  (call-interactively 'maf-edit-add-entry-below)
  (progn (insert "1.5..2.5") (deactivate-mark) nil)
  (call-interactively 'maf-edit-commit)
  (cl-assert (string= (math-format-flat-expr (calc-top 1) 0)
                      "[1.5 .. 2.5]"))
  (calc-pop (calc-stack-size))

  ;; With the module off the bare spelling refuses as it always did,
  ;; and the session stands for the discard.
  (progn (maf-use-editplus-mode -1) nil)
  (call-interactively 'maf-edit-add-entry-below)
  (progn (insert "-inf..-1") (deactivate-mark) nil)
  (cl-assert (string-match-p
              "cannot commit"
              (condition-case err
                  (progn (call-interactively 'maf-edit-commit) "")
                (error (error-message-string err)))))
  (call-interactively 'maf-edit-discard)
  (progn (maf-use-editplus-mode 1) nil)
  (cl-assert (= (calc-stack-size) 0)))
