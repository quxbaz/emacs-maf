;; B inside a maf-edit session makes a sub-expression the argument of a
;; log call, an inherited base written out (`maf-editplus-wrap-log',
;; the family's one binary member). A step passes when it raises no error.
;;
;; The wrap itself is `maf-editplus-wrap-ln's — the same target, the
;; same point placement — so this file is about the base: the bare
;; log(x) a first press writes, inheritance from the entry's nearest
;; log at or before the target, the numeric prefix, and the
;; commit-time trade of log(x) and log(x, 10) for calc's log10(x).

(maf-step
  ;; The module owns the key, and it lives in maf-edit's own map.
  (cl-assert (eq (lookup-key maf-edit-mode-map (kbd "B"))
                 'maf-editplus-wrap-log))
  (cl-assert (memq 'maf-editplus--commit-log10
                   maf-edit-transform-value-functions))

  ;; The gesture as it is actually used: type a term, apply log. The
  ;; first log of an entry has nothing to inherit and writes no base;
  ;; point lands after the closer, as it does for ln.
  (call-interactively 'maf-edit-add-entry-below)
  (progn (execute-kbd-macro "x+2") nil)
  (progn (execute-kbd-macro "B") nil)
  (cl-assert (equal (maf-edit--entry-text (maf-editplus--entry-at-point))
                    "x+log(2)"))
  (cl-assert (eolp))
  (call-interactively 'maf-edit-discard)

  ;; A log already in the entry says what base the work is in: the
  ;; nearest one at or before the target lends its base.
  (call-interactively 'maf-edit-add-entry-below)
  (progn (execute-kbd-macro "log(a,2)") nil)
  (call-interactively 'maf-editplus-escape-group)
  (progn (execute-kbd-macro "+x") nil)
  (call-interactively 'maf-editplus-wrap-log)
  (cl-assert (equal (maf-edit--entry-text (maf-editplus--entry-at-point))
                    "log(a,2)+log(x, 2)"))
  (call-interactively 'maf-edit-discard)

  ;; The base is text, not a number: whatever expression is spelled
  ;; there carries forward.
  (call-interactively 'maf-edit-add-entry-below)
  (progn (execute-kbd-macro "log(a,n+1)") nil)
  (call-interactively 'maf-editplus-escape-group)
  (progn (execute-kbd-macro "+x") nil)
  (call-interactively 'maf-editplus-wrap-log)
  (cl-assert (equal (maf-edit--entry-text (maf-editplus--entry-at-point))
                    "log(a,n+1)+log(x, n+1)"))
  (call-interactively 'maf-edit-discard)

  ;; A one-argument log has no base written and lends nothing.
  (call-interactively 'maf-edit-add-entry-below)
  (progn (execute-kbd-macro "log(a)") nil)
  (call-interactively 'maf-editplus-escape-group)
  (progn (execute-kbd-macro "+x") nil)
  (call-interactively 'maf-editplus-wrap-log)
  (cl-assert (equal (maf-edit--entry-text (maf-editplus--entry-at-point))
                    "log(a)+log(x)"))
  (call-interactively 'maf-edit-discard)

  ;; At-or-before rather than strictly before: a log being wrapped in
  ;; another log lends its own base to the wrap.
  (call-interactively 'maf-edit-add-entry-below)
  (progn (execute-kbd-macro "log(a,2)") nil)
  (call-interactively 'maf-editplus-escape-group)
  (call-interactively 'maf-editplus-wrap-log)
  (cl-assert (equal (maf-edit--entry-text (maf-editplus--entry-at-point))
                    "log(log(a,2), 2)"))
  (call-interactively 'maf-edit-discard)

  ;; Wrapping inside an existing log's argument inherits the enclosing
  ;; base: the enclosing call starts before the target does. Point on
  ;; the `a' names the atom, and stays on the call it becomes.
  (call-interactively 'maf-edit-add-entry-below)
  (progn (execute-kbd-macro "log(a+b,2)") nil)
  (progn (search-backward "a") nil)
  (call-interactively 'maf-editplus-wrap-log)
  (cl-assert (equal (maf-edit--entry-text (maf-editplus--entry-at-point))
                    "log(log(a, 2)+b,2)"))
  (cl-assert (eq (char-after) ?l))
  (call-interactively 'maf-edit-discard)

  ;; A numeric prefix names the base outright — C-u 2 B — and outranks
  ;; anything the entry would have lent.
  (call-interactively 'maf-edit-add-entry-below)
  (progn (execute-kbd-macro "x") nil)
  (progn (let ((current-prefix-arg 2))
           (call-interactively 'maf-editplus-wrap-log))
         nil)
  (cl-assert (equal (maf-edit--entry-text (maf-editplus--entry-at-point))
                    "log(x, 2)"))
  (call-interactively 'maf-edit-discard)

  ;; With nothing behind point the empty call opens, point on the
  ;; argument slot.
  (call-interactively 'maf-edit-add-entry-below)
  (progn (execute-kbd-macro "x = ") nil)
  (call-interactively 'maf-editplus-wrap-log)
  (cl-assert (equal (maf-edit--entry-text (maf-editplus--entry-at-point))
                    "x = log()"))
  (cl-assert (eq (char-after) ?\)))
  ;; And typing carries straight on into it.
  (progn (execute-kbd-macro "3") nil)
  (cl-assert (equal (maf-edit--entry-text (maf-editplus--entry-at-point))
                    "x = log(3)"))
  (call-interactively 'maf-edit-discard)

  ;; Commit trades the module's spelling for calc's: the bare log(x)
  ;; — and a log(x, 10) typed by hand — lands as log10(x), while a
  ;; base the text means — the 2 here — stays a two-argument log.
  (call-interactively 'maf-edit-add-entry-below)
  (progn (execute-kbd-macro "x") nil)
  (call-interactively 'maf-editplus-wrap-log)
  (call-interactively 'maf-edit-commit)
  (cl-assert (equal (calc-top 1) '(calcFunc-log10 (var x var-x))))
  (calc-pop (calc-stack-size))

  (call-interactively 'maf-edit-add-entry-below)
  (progn (execute-kbd-macro "log(log(y,10),2") nil)
  (call-interactively 'maf-edit-commit)
  (cl-assert (equal (calc-top 1)
                    '(calcFunc-log (calcFunc-log10 (var y var-y)) 2)))
  (calc-pop (calc-stack-size))

  ;; A float 10. means what it says and passes through untouched.
  (call-interactively 'maf-edit-add-entry-below)
  (progn (execute-kbd-macro "log(y,10.") nil)
  (call-interactively 'maf-edit-commit)
  (cl-assert (equal (calc-top 1)
                    '(calcFunc-log (var y var-y) (float 1 1))))
  (calc-pop (calc-stack-size))

  ;; Outside a session the command refuses, as the whole family does.
  (cl-assert (string-match-p
              "not active"
              (condition-case e
                  (progn (call-interactively 'maf-editplus-wrap-log) "")
                (error (error-message-string e))))))
