;; S, C and T inside a maf-edit session make a sub-expression the
;; argument of a sin, cos or tan call (`maf-editplus-wrap-sin' and its
;; siblings). A step passes when it raises no error.
;;
;; All three are `maf-editplus--apply-function' with a different name,
;; and `edit-wrap-ln.el' already covers what that scan takes hold of.
;; What is checked here is what the keys add: the binding, the name
;; written in front of the pair, and the fact that the capitals no
;; longer type themselves during a session.

(maf-step
  (cl-assert (eq (lookup-key maf-edit-mode-map (kbd "S"))
                 'maf-editplus-wrap-sin))
  (cl-assert (eq (lookup-key maf-edit-mode-map (kbd "C"))
                 'maf-editplus-wrap-cos))
  (cl-assert (eq (lookup-key maf-edit-mode-map (kbd "T"))
                 'maf-editplus-wrap-tan))

  ;; The gesture as it is used: type a term, then apply the sine to
  ;; it. Driven by the real key, so a capital S reaching self-insert
  ;; would show up here as a stray letter in the entry.
  (call-interactively 'maf-edit-add-entry-below)
  (progn (execute-kbd-macro "x+2") nil)
  (progn (execute-kbd-macro "S") nil)
  (cl-assert (equal (maf-edit--entry-text (maf-editplus--entry-at-point))
                    "x+sin(2)"))
  (cl-assert (eolp))
  (call-interactively 'maf-edit-discard)

  ;; Same for the cosine, and on the term the scan calls one unit —
  ;; the product, not the factor at its end.
  (call-interactively 'maf-edit-add-entry-below)
  (progn (execute-kbd-macro "a+b*c") nil)
  (progn (execute-kbd-macro "C") nil)
  (cl-assert (equal (maf-edit--entry-text (maf-editplus--entry-at-point))
                    "a+cos(b*c)"))
  (call-interactively 'maf-edit-discard)

  ;; And the tangent with nothing behind point: an empty call opens,
  ;; point inside it, waiting for the argument.
  (call-interactively 'maf-edit-add-entry-below)
  (progn (execute-kbd-macro "x = ") nil)
  (progn (execute-kbd-macro "T") nil)
  (cl-assert (equal (maf-edit--entry-text (maf-editplus--entry-at-point))
                    "x = tan()"))
  (cl-assert (eq (char-after) ?\)))
  (progn (execute-kbd-macro "3") nil)
  (cl-assert (equal (maf-edit--entry-text (maf-editplus--entry-at-point))
                    "x = tan(3)"))
  (call-interactively 'maf-edit-discard)

  ;; The trio compose with the older wraps, each taking the call the
  ;; last one left as one unit.
  (call-interactively 'maf-edit-add-entry-below)
  (progn (execute-kbd-macro "x") nil)
  (progn (execute-kbd-macro "S") nil)
  (progn (execute-kbd-macro "Q") nil)
  (cl-assert (equal (maf-edit--entry-text (maf-editplus--entry-at-point))
                    "sqrt(sin(x))"))
  (call-interactively 'maf-edit-discard)

  ;; And what the keys write is a call to calc, not just a name and a
  ;; pair of parens in the text.
  (call-interactively 'maf-edit-add-entry-below)
  (progn (execute-kbd-macro "9") nil)
  (progn (execute-kbd-macro "S") nil)
  (call-interactively 'maf-edit-commit)
  (cl-assert (equal (calc-top 1) '(calcFunc-sin 9)))
  (calc-pop (calc-stack-size))

  ;; Outside a session the trio refuse rather than editing calc's
  ;; rendered stack. The keys never reach here — they are bound in
  ;; `maf-edit-mode-map' alone — so M-x is the only route.
  (maf-push "a+b")
  (progn (calc-cursor-stack-index 1)
         (goto-char (line-end-position)) nil)
  (cl-assert (string-match-p
              "not active"
              (condition-case e
                  (progn (call-interactively 'maf-editplus-wrap-sin) "")
                (error (error-message-string e)))))
  (cl-assert (equal (calc-top 1) '(+ (var a var-a) (var b var-b))))
  (calc-pop (calc-stack-size)))
