(maf-step
  ;; Empty stack: signals instead of guessing.
  (cl-assert (condition-case nil
                 (progn (call-interactively 'maf-kill) nil)
               (error t)))

  ;; Mid-formula point: the whole entry is killed anyway — killing is
  ;; line-based, unlike maf-del.
  (maf-push "q1 + q2")
  (maf-push "q3")
  (progn (calc-cursor-stack-index 2)
         (search-forward "q1" (line-end-position)) (backward-char 1) nil)
  (call-interactively 'maf-kill)
  (cl-assert (= (calc-stack-size) 1))
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "q3"))
  (cl-assert (string= (current-kill 0) "q1 + q2"))
  (calc-pop (calc-stack-size))

  ;; Entry margin: same thing.
  (maf-push "a b")
  (maf-push "q3")
  (progn (calc-cursor-stack-index 2) (end-of-line) nil)
  (call-interactively 'maf-kill)
  (cl-assert (= (calc-stack-size) 1))
  (cl-assert (string= (current-kill 0) "a b"))
  (calc-pop (calc-stack-size))

  ;; Home: the top pops onto the kill ring.
  (maf-push "q4")
  (maf-push "q5 r")
  (progn (goto-char (point-max)) nil)
  (call-interactively 'maf-kill)
  (cl-assert (= (calc-stack-size) 1))
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "q4"))
  (cl-assert (string= (current-kill 0) "q5 r"))
  (calc-pop (calc-stack-size))

  ;; A single undo restores the entry and point together.
  (maf-push "[a, b, c]")
  (progn (calc-cursor-stack-index 1)
         (search-forward "c" (line-end-position)) (backward-char 1) nil)
  (setq maf--test-point (point))
  (call-interactively 'maf-kill)
  (call-interactively 'maf-undo)
  (cl-assert (= (point) maf--test-point))
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "[a, b, c]")))
