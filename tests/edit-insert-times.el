;; J inside a maf-edit session types the multiplication sign
;; (`maf-editplus-insert-times', the editplus module's `*' key). A
;; step passes when it raises no error.
;;
;; The contract: exactly what the `*' key itself does — one `*' per
;; press, N of them under a prefix argument — so multiplication keeps
;; the letter maf gives it on the stack (`mafcmd-mul') on both sides
;; of a session, and shift-8 stays optional. The cost is that a
;; capital J no longer self-inserts.

(maf-step
  (cl-assert (eq (lookup-key maf-edit-mode-map (kbd "J"))
                 'maf-editplus-insert-times))
  (calc-pop (calc-stack-size))

  ;; The gesture: the letter goes in as the operator, mid-formula.
  (call-interactively 'maf-edit-add-entry-below)
  (progn (execute-kbd-macro "2J3") nil)
  (cl-assert (equal (maf-edit--entry-text (maf-editplus--entry-at-point))
                    "2*3"))
  (call-interactively 'maf-edit-commit)
  (cl-assert (equal (calc-top 1) '(* 2 3)))
  (calc-pop (calc-stack-size))

  ;; Ordinary self-insertion, so a prefix argument repeats it — which
  ;; is also how calc's own ** for exponentiation gets typed here.
  (call-interactively 'maf-edit-add-entry-below)
  (progn (execute-kbd-macro "x") nil)
  (progn (let ((current-prefix-arg 2))
           (call-interactively 'maf-editplus-insert-times))
         nil)
  (progn (execute-kbd-macro "3") nil)
  (cl-assert (equal (maf-edit--entry-text (maf-editplus--entry-at-point))
                    "x**3"))
  (call-interactively 'maf-edit-commit)
  (cl-assert (equal (calc-top 1) '(^ (var x var-x) 3)))
  (calc-pop (calc-stack-size))

  ;; The key belongs to the session alone: on the stack J is still
  ;; maf's multiply, and nothing here changed that.
  (cl-assert (eq (lookup-key maf-mode-map (kbd "J")) 'mafcmd-mul)))
