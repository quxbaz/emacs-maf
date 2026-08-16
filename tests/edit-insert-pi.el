;; P inside a maf-edit session types the constant pi
;; (`maf-editplus-insert-pi', the editplus module's pi key). A step
;; passes when it raises no error.
;;
;; The contract: two characters for one keypress, the name spelled the
;; way the editvars dialect spells it — bare while pi is exempt, which
;; is the default; quoted where the exemption is withdrawn — and a
;; space in front wherever the name would otherwise run into an
;; identifier. A bare number takes the name directly: 44pi, the way it
;; is written by hand. Either way what commits is calc's pi.

(maf-step
  (cl-assert (eq (lookup-key maf-edit-mode-map (kbd "P"))
                 'maf-editplus-insert-pi))
  ;; The dialect is on by default and pi is exempt within it; that
  ;; pair is what the first half of this file exercises.
  (cl-assert maf-use-editvars-mode)
  (cl-assert (equal maf-editvars-exempt-names '("pi")))
  (cl-assert (null calc-language))

  ;; Exempt, the name goes in bare, directly after a number, and reads
  ;; back as the constant rather than as the product p i.
  (call-interactively 'maf-edit-add-entry-below)
  (progn (execute-kbd-macro "44") nil)
  (progn (execute-kbd-macro "P") nil)
  (cl-assert (equal (maf-edit--entry-text (maf-editplus--entry-at-point))
                    "44pi"))
  (call-interactively 'maf-edit-commit)
  (cl-assert (equal (calc-top 1) '(* 44 (var pi var-pi))))
  (calc-pop (calc-stack-size))

  ;; After a name character the space still goes in: xpi would be a
  ;; run of three factors under the dialect.
  (call-interactively 'maf-edit-add-entry-below)
  (progn (execute-kbd-macro "x") nil)
  (progn (execute-kbd-macro "P") nil)
  (cl-assert (equal (maf-edit--entry-text (maf-editplus--entry-at-point))
                    "x pi"))
  (call-interactively 'maf-edit-commit)
  (cl-assert (equal (calc-top 1) '(* (var x var-x) (var pi var-pi))))
  (calc-pop (calc-stack-size))

  ;; A digit that is the tail of an identifier is not a number's, and
  ;; keeps the space too: x2pi would be one name calc has never heard
  ;; of, where x2 pi is the product meant.
  (call-interactively 'maf-edit-add-entry-below)
  (progn (execute-kbd-macro "x2") nil)
  (progn (execute-kbd-macro "P") nil)
  (cl-assert (equal (maf-edit--entry-text (maf-editplus--entry-at-point))
                    "x2 pi"))
  (call-interactively 'maf-edit-commit)
  (cl-assert (equal (calc-top 1) '(* (var x2 var-x2) (var pi var-pi))))
  (calc-pop (calc-stack-size))

  ;; Withdrawn from the exempt list, the name goes in quoted — there a
  ;; bare pi is the product p i again — still directly after a number.
  (progn (setq maf-step--exempt-was maf-editvars-exempt-names
               maf-editvars-exempt-names nil)
         nil)
  (call-interactively 'maf-edit-add-entry-below)
  (progn (execute-kbd-macro "2") nil)
  (progn (execute-kbd-macro "P") nil)
  (cl-assert (equal (maf-edit--entry-text (maf-editplus--entry-at-point))
                    "2{pi}"))
  (call-interactively 'maf-edit-commit)
  (cl-assert (equal (calc-top 1) '(* 2 (var pi var-pi))))
  (calc-pop (calc-stack-size))

  ;; The prefix argument repeats it. The braces keep the copies apart
  ;; on their own — a closing brace is no name character, so the space
  ;; rule has nothing to add.
  (call-interactively 'maf-edit-add-entry-below)
  (progn (execute-kbd-macro (kbd "C-u 3 P")) nil)
  (cl-assert (equal (maf-edit--entry-text (maf-editplus--entry-at-point))
                    "{pi}{pi}{pi}"))
  (call-interactively 'maf-edit-commit)
  ;; A product of three, standing as written — maf commits without
  ;; working anything out.
  (cl-assert (equal (calc-top 1)
                    '(* (var pi var-pi)
                        (* (var pi var-pi) (var pi var-pi)))))
  (calc-pop (calc-stack-size))
  (progn (setq maf-editvars-exempt-names maf-step--exempt-was) nil)

  ;; With the dialect standing down the plain name goes in, and the
  ;; number still takes it directly: calc reads 44pi as the product on
  ;; its own.
  (maf-use-editvars-mode -1)
  (call-interactively 'maf-edit-add-entry-below)
  (progn (execute-kbd-macro "2") nil)
  (progn (execute-kbd-macro "P") nil)
  (cl-assert (equal (maf-edit--entry-text (maf-editplus--entry-at-point))
                    "2pi"))
  (call-interactively 'maf-edit-commit)
  (cl-assert (equal (calc-top 1) '(* 2 (var pi var-pi))))
  (calc-pop (calc-stack-size))

  ;; The space is what keeps a product a product: without it the two
  ;; names would run together into one calc has never heard of.
  (call-interactively 'maf-edit-add-entry-below)
  (progn (execute-kbd-macro "x") nil)
  (progn (execute-kbd-macro "P") nil)
  (cl-assert (equal (maf-edit--entry-text (maf-editplus--entry-at-point))
                    "x pi"))
  (call-interactively 'maf-edit-commit)
  (cl-assert (equal (calc-top 1) '(* (var x var-x) (var pi var-pi))))
  (calc-pop (calc-stack-size))
  (maf-use-editvars-mode 1)

  ;; And the spelling is asked for by name, so it follows the dialect
  ;; and its exempt list rather than being spelled out here twice.
  (cl-assert (equal (maf-editvars-quote-name "pi") "pi"))
  (cl-assert (equal (maf-editvars-quote-name "foo") "{foo}"))
  (cl-assert (equal (let ((maf-editvars-exempt-names nil))
                      (maf-editvars-quote-name "pi"))
                    "{pi}"))
  ;; A single letter is already one factor, and a name with a digit in
  ;; it is spelled the same either way — neither is quoted.
  (cl-assert (equal (maf-editvars-quote-name "x") "x"))
  (cl-assert (equal (maf-editvars-quote-name "x1") "x1"))
  (maf-use-editvars-mode -1)
  (cl-assert (equal (maf-editvars-quote-name "pi") "pi"))
  (maf-use-editvars-mode 1))
