;; TAB inside a maf-edit session jumps point past the delimiter that
;; closes the group it stands in (`maf-editplus-escape-group', the
;; editplus module's first key). A step passes when it raises no error.
;; The contract: one level per press, any closer matches any opener,
;; nothing left to escape lands point at the end of the entry, and the
;; scan never leaves the entry point started in.

(maf-step
  ;; The module owns the key, and it lives in maf-edit's own map — so
  ;; it means nothing until a session is running.
  (cl-assert (eq (lookup-key maf-edit-mode-map (kbd "TAB"))
                 'maf-editplus-escape-group))

  ;; The gesture as it is actually used: type up to the closer
  ;; electric-pair already placed, then TAB past it. Driven by the real
  ;; key, so the binding is exercised and not just the command.
  (call-interactively 'maf-edit-add-entry)
  (progn (execute-kbd-macro "sqrt(x^2+1") nil)
  (cl-assert (looking-at-p ")$"))
  (progn (execute-kbd-macro "\t") nil)
  (cl-assert (eolp))
  (call-interactively 'maf-edit-discard)

  ;; Nested groups peel off one level per press, and a press with
  ;; nothing left to escape leaves point where it is.
  (call-interactively 'maf-edit-add-entry)
  (progn (execute-kbd-macro "f(g(x") nil)
  (cl-assert (looking-at-p "))$"))
  (call-interactively 'maf-editplus-escape-group)
  (cl-assert (looking-at-p ")$"))
  (call-interactively 'maf-editplus-escape-group)
  (cl-assert (eolp))
  (call-interactively 'maf-editplus-escape-group)
  (cl-assert (eolp))
  (call-interactively 'maf-edit-discard)

  ;; Brackets are groups too.
  (call-interactively 'maf-edit-add-entry)
  (progn (execute-kbd-macro "[1,2") nil)
  (cl-assert (looking-at-p "\\]$"))
  (call-interactively 'maf-editplus-escape-group)
  (cl-assert (eolp))
  (call-interactively 'maf-edit-discard)

  ;; Any closer matches any opener, as it does everywhere else in
  ;; maf-edit: calc's half-open interval notation mixes them, and the
  ;; `]' closes the group the `(' opened. Inserted rather than typed —
  ;; electric-pair would answer the `(' with its own `)'.
  (call-interactively 'maf-edit-add-entry)
  (progn (insert "(1 .. 2]") (backward-char 2) nil)
  (call-interactively 'maf-editplus-escape-group)
  (cl-assert (eolp))
  (call-interactively 'maf-edit-discard)

  ;; A group whose closer has not been typed yet has no far side to
  ;; reach, so point goes to the end of the entry instead — the same
  ;; answer as escaping from the entry's top level.
  (call-interactively 'maf-edit-add-entry)
  (progn (insert "sin(x") nil)
  (call-interactively 'maf-editplus-escape-group)
  (cl-assert (eolp))
  (call-interactively 'maf-edit-discard)

  (call-interactively 'maf-edit-add-entry)
  (progn (execute-kbd-macro "a+b") nil)
  (maf-edit-move-beginning-of-line 1)
  (cl-assert (looking-at-p "a"))
  (call-interactively 'maf-editplus-escape-group)
  (cl-assert (eolp))
  (call-interactively 'maf-edit-discard)

  ;; The scan stops at the entry point is in: the `)' one entry further
  ;; down the buffer is not this entry's, and must not be escaped to.
  (maf-push "x+y")
  (maf-push "(c)")
  (maf-edit-mode 1)
  (progn (goto-char (point-min))
         (maf-edit-move-beginning-of-line 1) nil)
  (cl-assert (looking-at-p "x"))
  (call-interactively 'maf-editplus-escape-group)
  (cl-assert (eolp))
  (cl-assert (save-excursion (beginning-of-line) (looking-at-p " *2:")))
  (call-interactively 'maf-edit-discard)
  (calc-pop (calc-stack-size))

  ;; Outside a session the command refuses rather than falling back to
  ;; line bounds and walking point across calc's rendered stack. The key
  ;; never reaches here — it is bound in `maf-edit-mode-map' alone — so
  ;; M-x is the only route, and it is the one guarded.
  (maf-push "f(g(x))")
  (progn (calc-cursor-stack-index 1)
         (search-forward "x" (line-end-position))
         (backward-char 1) nil)
  (cl-assert (string-match-p "not active"
                             (condition-case e
                                 (progn (call-interactively
                                         'maf-editplus-escape-group) "")
                               (error (error-message-string e)))))
  (cl-assert (looking-at-p "x"))        ; point never moved
  (calc-pop (calc-stack-size)))
