;; P inside a maf-edit session types the constant pi
;; (`maf-editplus-insert-pi', the editplus module's pi key). A step
;; passes when it raises no error.
;;
;; The contract: two characters for one keypress, a space in front of
;; them wherever the name would otherwise run into what precedes it,
;; and — the part that is not cosmetic — the name quoted for the
;; maf-editvars dialect, under which a bare pi is the product p i.
;; Either way what commits is calc's pi.

(maf-step
  (cl-assert (eq (lookup-key maf-edit-mode-map (kbd "P"))
                 'maf-editplus-insert-pi))
  ;; The dialect is on by default, and is what the first half of this
  ;; file is about.
  (cl-assert maf-use-editvars-mode)
  (cl-assert (null calc-language))

  ;; The name goes in quoted, and reads back as the constant rather
  ;; than as the product of two variables.
  (call-interactively 'maf-edit-add-entry-below)
  (progn (execute-kbd-macro "2") nil)
  (progn (execute-kbd-macro "P") nil)
  (cl-assert (equal (maf-edit--entry-text (maf-editplus--entry-at-point))
                    "2 \\pi"))
  (call-interactively 'maf-edit-commit)
  (cl-assert (equal (calc-top 1) '(* 2 (var pi var-pi))))
  (calc-pop (calc-stack-size))

  ;; The mark is the dialect's to choose, not this command's.
  (setq maf-editvars-quote-char ?@)
  (call-interactively 'maf-edit-add-entry-below)
  (progn (execute-kbd-macro "P") nil)
  (cl-assert (equal (maf-edit--entry-text (maf-editplus--entry-at-point))
                    "@pi"))
  (call-interactively 'maf-edit-commit)
  (cl-assert (equal (calc-top 1) '(var pi var-pi)))
  (calc-pop (calc-stack-size))
  (setq maf-editvars-quote-char ?\\)

  ;; The prefix argument repeats it, and the space rule keeps the
  ;; copies apart — a name character before the mark is still a name
  ;; character.
  (call-interactively 'maf-edit-add-entry-below)
  (progn (execute-kbd-macro (kbd "C-u 3 P")) nil)
  (cl-assert (equal (maf-edit--entry-text (maf-editplus--entry-at-point))
                    "\\pi \\pi \\pi"))
  (call-interactively 'maf-edit-commit)
  ;; A product of three, standing as written — maf commits without
  ;; working anything out.
  (cl-assert (equal (calc-top 1)
                    '(* (var pi var-pi)
                        (* (var pi var-pi) (var pi var-pi)))))
  (calc-pop (calc-stack-size))

  ;; With the dialect standing down the plain name goes in, which is
  ;; what calc reads on its own.
  (maf-use-editvars-mode -1)
  (call-interactively 'maf-edit-add-entry-below)
  (progn (execute-kbd-macro "2") nil)
  (progn (execute-kbd-macro "P") nil)
  (cl-assert (equal (maf-edit--entry-text (maf-editplus--entry-at-point))
                    "2 pi"))
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

  ;; And the quoting is asked for by name, so it follows the dialect
  ;; rather than being spelled out here twice.
  (cl-assert (equal (maf-editvars-quote-name "pi") "\\pi"))
  ;; A single letter is already one factor, and a name with a digit in
  ;; it is spelled the same either way — neither is quoted.
  (cl-assert (equal (maf-editvars-quote-name "x") "x"))
  (cl-assert (equal (maf-editvars-quote-name "x1") "x1"))
  (maf-use-editvars-mode -1)
  (cl-assert (equal (maf-editvars-quote-name "pi") "pi"))
  (maf-use-editvars-mode 1))
