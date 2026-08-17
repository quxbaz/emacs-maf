;; maf-index (v RET): prompt for a size, push the index vector
;; [1, 2, .., n]. Never reads the stack or point — the ported reading
;; of the legacy config's v RET (calc-index there). The contextual
;; sibling mafcmd-index stays on v x, untouched.

(defun maf-test-index-refused (keys)
  "Run `maf-index' with KEYS at its prompt; the message if it refused."
  (condition-case err
      (progn (setq unread-command-events (listify-key-sequence keys))
             (call-interactively 'maf-index)
             nil)
    (user-error (error-message-string err))))

(maf-step
  ;; The prompt is the whole input; nothing on the stack is consumed.
  (maf-push "7")
  (progn (setq unread-command-events (listify-key-sequence "5\r"))
         (call-interactively 'maf-index))
  (cl-assert (string= (math-format-value (calc-top 1 'full))
                      "[1, 2, 3, 4, 5]"))
  (cl-assert (= (calc-stack-size) 2))
  (cl-assert (string= (math-format-value (calc-top 2 'full)) "7"))
  (calc-pop (calc-stack-size))

  ;; The prompt takes a formula for the size.
  (progn (setq unread-command-events (listify-key-sequence "2^3\r"))
         (call-interactively 'maf-index))
  (cl-assert (string= (math-format-value (calc-top 1 'full))
                      "[1, 2, 3, 4, 5, 6, 7, 8]"))
  (calc-pop (calc-stack-size))

  ;; A symbolic size pushes the call unevaluated.
  (progn (setq unread-command-events (listify-key-sequence "n\r"))
         (call-interactively 'maf-index))
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "index(n)"))
  (calc-pop (calc-stack-size))

  ;; Zero is a size: the empty vector.
  (progn (setq unread-command-events (listify-key-sequence "0\r"))
         (call-interactively 'maf-index))
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "[]"))
  (calc-pop (calc-stack-size))

  ;; A numeric prefix is the size outright — no prompt.
  (let ((current-prefix-arg 4))
    (call-interactively 'maf-index))
  (cl-assert (string= (math-format-value (calc-top 1 'full))
                      "[1, 2, 3, 4]"))
  (calc-pop (calc-stack-size))

  ;; A number that is not a whole size refuses, as does empty input.
  (cl-assert (string-match-p "non-negative integer"
                             (maf-test-index-refused "2.5\r")))
  (cl-assert (string-match-p "non-negative integer"
                             (maf-test-index-refused "-3\r")))
  (cl-assert (string-match-p "No size" (maf-test-index-refused "\r")))
  (cl-assert (= (calc-stack-size) 0)))
