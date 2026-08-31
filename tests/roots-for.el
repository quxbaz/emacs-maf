;; mafcmd-roots-for (a l): all roots of the entry as a vector, the
;; variable read from the minibuffer as i reads it — the subject's
;; priority variable offered as the default.

(maf-step
  ;; RET takes the default: the subject's priority variable.
  (maf-push "x^2 - 4")
  (goto-char (point-max))
  (progn (execute-kbd-macro (kbd "a l RET"))
         (cl-assert (string= (math-format-value
                              (maf--strip-encasing (calc-top 1 'full)))
                             "[2, -2]")))
  (calc-pop (calc-stack-size))

  ;; An equation works, and multiplicity is kept through a factored
  ;; form.
  (maf-push "(x - 1)^2 (x + 2)")
  (goto-char (point-max))
  (progn (execute-kbd-macro (kbd "a l RET"))
         (cl-assert (string= (math-format-value
                              (maf--strip-encasing (calc-top 1 'full)))
                             "[-2, 1, 1]")))
  (calc-pop (calc-stack-size))

  ;; Exactness whatever the ambient mode: a non-integer root is a
  ;; fraction.
  (maf-push "2 x = 1")
  (goto-char (point-max))
  (progn (execute-kbd-macro (kbd "a l RET"))
         (cl-assert (string= (math-format-value
                              (maf--strip-encasing (calc-top 1 'full)))
                             "[1:2]")))
  (calc-pop (calc-stack-size))

  ;; A typed variable overrides the default.
  (maf-push "x^2 + y^2 = 4")
  (goto-char (point-max))
  (progn (execute-kbd-macro (kbd "a l y RET"))
         (cl-assert (string= (math-format-value
                              (maf--strip-encasing (calc-top 1 'full)))
                             "[sqrt(-x^2 + 4), -sqrt(-x^2 + 4)]")))
  (calc-pop (calc-stack-size))

  ;; A variable the subject does not contain commits the entry
  ;; unchanged.
  (maf-push "y + 3")
  (goto-char (point-max))
  (progn (execute-kbd-macro (kbd "a l x RET"))
         (cl-assert (string= (math-format-value
                              (maf--strip-encasing (calc-top 1 'full)))
                             "y + 3")))
  (cl-assert (= (calc-stack-size) 1))
  (calc-pop (calc-stack-size))

  ;; A power of a compound base peels with every branch followed
  ;; (`maf--roots-peel'): the base's equation yields all eight roots,
  ;; and each carries the layer home — the reals first as calc orders
  ;; them.
  (maf-push "(x - 8)^8 = 256")
  (goto-char (point-max))
  (progn (execute-kbd-macro (kbd "a l x RET")) nil)
  (let ((roots (maf--strip-encasing (calc-top 1 'full))))
    (cl-assert (eq (car-safe roots) 'vec))
    (cl-assert (= (length (cdr roots)) 8))
    (cl-assert (equal (seq-take (cdr roots) 2) '(10 6))))
  (calc-pop (calc-stack-size))

  ;; The flags refuse rather than dropping silently: roots already
  ;; finds every root.
  (maf-push "x^2 - 4")
  (goto-char (point-max))
  (cl-assert (string-match-p
              "No inverse variant"
              (condition-case err
                  (progn (execute-kbd-macro (kbd "I a l")) "")
                (error (error-message-string err)))))
  (cl-assert (null calc-inverse-flag))
  (cl-assert (string= (math-format-value
                       (maf--strip-encasing (calc-top 1 'full)))
                      "x^2 - 4"))
  (calc-pop (calc-stack-size)))
