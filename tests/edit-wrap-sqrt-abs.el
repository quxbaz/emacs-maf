;; Q and | inside a maf-edit session make the term before point the
;; argument of a sqrt or an abs call (`maf-editplus-wrap-sqrt' and
;; `maf-editplus-wrap-abs'). A step passes when it raises no error.
;;
;; Both are `maf-editplus--apply-function' with a different name, and
;; `edit-wrap-ln.el' already covers what that scan takes hold of. What
;; is checked here is what the two keys add: the binding, the name
;; written in front of the pair, and the fact that Q and | no longer
;; type themselves during a session.

(maf-step
  (cl-assert (eq (lookup-key maf-edit-mode-map (kbd "Q"))
                 'maf-editplus-wrap-sqrt))
  (cl-assert (eq (lookup-key maf-edit-mode-map (kbd "|"))
                 'maf-editplus-wrap-abs))

  ;; The gesture as it is used: type a term, then apply the root to it.
  ;; Driven by the real key, so a capital Q reaching self-insert would
  ;; show up here as a stray letter in the entry.
  (call-interactively 'maf-edit-add-entry-below)
  (progn (execute-kbd-macro "x+2") nil)
  (progn (execute-kbd-macro "Q") nil)
  (cl-assert (equal (maf-edit--entry-text (maf-editplus--entry-at-point))
                    "x+sqrt(2)"))
  (cl-assert (eolp))
  (call-interactively 'maf-edit-discard)

  ;; Same for the modulus, and on the term the scan calls one unit —
  ;; the product, not the factor at its end.
  (call-interactively 'maf-edit-add-entry-below)
  (progn (execute-kbd-macro "a+b*c") nil)
  (progn (execute-kbd-macro "|") nil)
  (cl-assert (equal (maf-edit--entry-text (maf-editplus--entry-at-point))
                    "a+abs(b*c)"))
  (call-interactively 'maf-edit-discard)

  ;; The two compose, each taking the call the other left as one unit.
  (call-interactively 'maf-edit-add-entry-below)
  (progn (execute-kbd-macro "x") nil)
  (progn (execute-kbd-macro "Q") nil)
  (progn (execute-kbd-macro "|") nil)
  (cl-assert (equal (maf-edit--entry-text (maf-editplus--entry-at-point))
                    "abs(sqrt(x))"))
  (call-interactively 'maf-edit-discard)

  ;; An active region becomes the argument exactly as marked.
  (call-interactively 'maf-edit-add-entry-below)
  (progn (execute-kbd-macro "pi+2") nil)
  (progn (maf-edit-move-beginning-of-line 1)
         (set-mark (point))
         (forward-char 2)
         (activate-mark) nil)
  (call-interactively 'maf-editplus-wrap-sqrt)
  (cl-assert (equal (maf-edit--entry-text (maf-editplus--entry-at-point))
                    "sqrt(pi)+2"))
  (call-interactively 'maf-edit-discard)

  ;; With nothing behind point an empty call is opened, point inside
  ;; it, as with ln — a call waiting for its argument.
  (call-interactively 'maf-edit-add-entry-below)
  (progn (execute-kbd-macro "x = ") nil)
  (progn (execute-kbd-macro "Q") nil)
  (cl-assert (equal (maf-edit--entry-text (maf-editplus--entry-at-point))
                    "x = sqrt()"))
  (cl-assert (eq (char-after) ?\)))
  (progn (execute-kbd-macro "3") nil)
  (cl-assert (equal (maf-edit--entry-text (maf-editplus--entry-at-point))
                    "x = sqrt(3)"))
  (call-interactively 'maf-edit-discard)

  ;; And what the key writes is a call to calc, not just a name and a
  ;; pair of parens in the text.
  (call-interactively 'maf-edit-add-entry-below)
  (progn (execute-kbd-macro "9") nil)
  (progn (execute-kbd-macro "Q") nil)
  (call-interactively 'maf-edit-commit)
  (cl-assert (equal (calc-top 1) '(calcFunc-sqrt 9)))
  (calc-pop (calc-stack-size))

  ;; Outside a session both refuse rather than editing calc's rendered
  ;; stack. The keys never reach here — they are bound in
  ;; `maf-edit-mode-map' alone — so M-x is the only route.
  (maf-push "a+b")
  (progn (calc-cursor-stack-index 1)
         (goto-char (line-end-position)) nil)
  (cl-assert (string-match-p
              "not active"
              (condition-case e
                  (progn (call-interactively 'maf-editplus-wrap-sqrt) "")
                (error (error-message-string e)))))
  (cl-assert (string-match-p
              "not active"
              (condition-case e
                  (progn (call-interactively 'maf-editplus-wrap-abs) "")
                (error (error-message-string e)))))
  (cl-assert (equal (calc-top 1) '(+ (var a var-a) (var b var-b))))
  (calc-pop (calc-stack-size)))
