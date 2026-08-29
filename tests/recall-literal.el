;; maf-recall-quick (r 0-9) and maf-recall-variable (r r): recall a
;; stored variable without simplification — what was stored is what
;; lands. The stored shapes are seeded directly (setq var-q5) because a
;; normal push would already have normalized x + x away to 2 x.

(maf-step
  ;; Quick recall pushes the stored shape verbatim.
  (setq var-q5 (math-read-expr "x + x"))
  (execute-kbd-macro (kbd "r 5"))
  (cl-assert (string= (math-format-value
                       (maf--strip-encasing (calc-top 1 'full)))
                      "x + x"))
  (cl-assert (= (calc-stack-size) 1))
  (calc-pop (calc-stack-size))

  ;; Contrast: calc's own quick recall renormalizes the same variable.
  (progn (setq unread-command-events (listify-key-sequence "5"))
         (call-interactively 'calc-recall-quick))
  (cl-assert (string= (math-format-value
                       (maf--strip-encasing (calc-top 1 'full)))
                      "2 x"))
  (calc-pop (calc-stack-size))

  ;; The prompt form recalls by name, same literal push.
  (setq var-foo (math-read-expr "x + x"))
  (execute-kbd-macro (kbd "r r foo RET"))
  (cl-assert (string= (math-format-value
                       (maf--strip-encasing (calc-top 1 'full)))
                      "x + x"))
  (calc-pop (calc-stack-size))

  ;; Point parks at home after the push, mark left on the way out.
  (maf-push "a + b")
  (maf-push "c + d")
  (progn (calc-cursor-stack-index 2)
         (execute-kbd-macro (kbd "r 5")))
  (cl-assert (maf--at-home-p))
  (calc-pop (calc-stack-size))

  ;; An empty name refuses; the stack stands.
  (maf-push "a")
  (cl-assert (string-match-p
              "No variable"
              (condition-case err
                  (progn (execute-kbd-macro (kbd "r r RET")) "")
                (user-error (error-message-string err)))))
  (cl-assert (= (calc-stack-size) 1))
  (calc-pop (calc-stack-size))

  ;; A quick slot holding nothing signals calc's own error.
  (progn (setq var-q7 nil) t)
  (cl-assert (condition-case nil
                 (progn (execute-kbd-macro (kbd "r 7")) nil)
               (error t)))
  (cl-assert (= (calc-stack-size) 0))

  ;; Cleanup: unseed the test variables.
  (progn (setq var-q5 nil var-foo nil) t))
