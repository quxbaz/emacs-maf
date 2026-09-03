;; mafcmd-let-entry (s l): calc's `s l' made contextual. It prompts for
;; an assignment and evaluates the entry at point under it — the whole
;; entry, never a narrowed part (:scope entry), which is the difference
;; from mafcmd-let (M-RET). An empty prompt takes the assignment from
;; the stack instead. The first case goes through the s l binding; the
;; rest queue the prompt and call the command directly.

(defun le-top ()
  (math-format-value (maf--strip-encasing (calc-top 1 'full))))

(defun le-run (input)
  "Call `mafcmd-let-entry' with INPUT queued at its prompt."
  (setq unread-command-events (listify-key-sequence (concat input "\r")))
  (call-interactively 'mafcmd-let-entry))

(maf-step
  ;; The binding, through real keys: a typed equation binds x for one
  ;; evaluation of the top entry.
  (cl-assert (eq (key-binding (kbd "s l")) 'mafcmd-let-entry))
  (maf-push "2 x + 1")
  (goto-char (point-max))
  (execute-kbd-macro (kbd "s l x = 3 RET"))
  (cl-assert (string= (le-top) "7"))
  (cl-assert (= (calc-stack-size) 1))
  (calc-pop (calc-stack-size))

  ;; := assigns the same way as the plain equation.
  (maf-push "2 x + 1")
  (goto-char (point-max))
  (le-run "x := 3")
  (cl-assert (string= (le-top) "7"))
  (calc-pop (calc-stack-size))

  ;; The value is evaluated in, so it folds; an unbound variable stands.
  (maf-push "x + y")
  (goto-char (point-max))
  (le-run "x = 3")
  (cl-assert (string= (le-top) "y + 3"))
  (calc-pop (calc-stack-size))

  ;; A vector of distinct variables is one joint set.
  (maf-push "a x")
  (goto-char (point-max))
  (le-run "[x = 3, a = 2]")
  (cl-assert (string= (le-top) "6"))
  (calc-pop (calc-stack-size))

  ;; A vector naming one variable throughout branches per assignment.
  (maf-push "y = x - 2")
  (goto-char (point-max))
  (le-run "[x = 1, x = 2]")
  (cl-assert (string= (le-top) "[y = -1, y = 0]"))
  (calc-pop (calc-stack-size))

  ;; Simplification off leaves the value unfolded, simply in place.
  (maf-push "2 x + 1")
  (goto-char (point-max))
  (let ((calc-simplify-mode 'none))
    (le-run "x = 3"))
  (cl-assert (string= (le-top) "2 3 + 1"))
  (calc-pop (calc-stack-size))

  ;; --- the empty prompt takes the assignment from the stack ---

  ;; The top entry is the assignment, the entry below it the subject,
  ;; consumed on commit — the binary reading, as mafcmd-let's.
  (maf-push "2 x + 1")
  (maf-push "x = 3")
  (goto-char (point-max))
  (le-run "")
  (cl-assert (string= (le-top) "7"))
  (cl-assert (= (calc-stack-size) 1))
  (calc-pop (calc-stack-size))

  ;; An empty prompt with a non-assignment on top refuses, stack intact.
  (maf-push "2 x + 1")
  (maf-push "9")
  (goto-char (point-max))
  (cl-assert (string-match-p
              "not an assignment"
              (downcase
               (condition-case e (progn (le-run "") "")
                 (user-error (error-message-string e))))))
  (cl-assert (= (calc-stack-size) 2))
  (calc-pop (calc-stack-size))

  ;; --- a relation subject evaluates each side in turn ---

  (maf-push "y = x^2 + 1")
  (goto-char (point-max))
  (le-run "x = 3")
  (cl-assert (string= (le-top) "y = 10"))
  (calc-pop (calc-stack-size))

  ;; An assignment written as a plain equation stays one argument even
  ;; when the subject is an inequality: each side evaluates under it.
  (maf-push "3 x < 15")
  (goto-char (point-max))
  (le-run "x = 2")
  (cl-assert (string= (le-top) "6 < 15"))
  (calc-pop (calc-stack-size))

  ;; --- subexpr targeting is disabled ---

  ;; Point within a sub-formula does not narrow: the whole entry
  ;; evaluates, both x's taking the value.
  (maf-push "x^2 + x")
  (progn (calc-cursor-stack-index 1) (end-of-line) (backward-char 1))
  (le-run "x = 3")
  (cl-assert (string= (le-top) "12"))
  (calc-pop (calc-stack-size))

  ;; Nor does a calc selection: mafcmd-let would narrow to it, this
  ;; takes the entry whole and clears the selection.
  (maf-push "x^2 + x")
  (progn (calc-cursor-stack-index 1) (end-of-line) (backward-char 1)
         (execute-kbd-macro (kbd "j s")))
  (le-run "x = 3")
  (cl-assert (string= (le-top) "12"))
  (cl-assert (null (calc-top 1 'sel)))
  (calc-pop (calc-stack-size))

  ;; --- targets, keep-args, and errors ---

  ;; Below the top, the entry at point is the subject and the rest of
  ;; the stack is untouched.
  (maf-push "2 x + 1")
  (maf-push "99")
  (progn (calc-cursor-stack-index 2) (end-of-line))
  (le-run "x = 3")
  (cl-assert (= (calc-stack-size) 2))
  (cl-assert (string= (math-format-value (calc-top 2 'full)) "7"))
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "99"))
  (calc-pop (calc-stack-size))

  ;; With keep-args the entry stays and the result is pushed on top.
  (maf-push "2 x + 1")
  (goto-char (point-max))
  (progn (setq unread-command-events (listify-key-sequence "x = 3\r"))
         (call-interactively 'calc-keep-args)
         (call-interactively 'mafcmd-let-entry))
  (cl-assert (= (calc-stack-size) 2))
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "7"))
  (cl-assert (string= (math-format-value (calc-top 2 'full)) "2 x + 1"))
  (calc-pop (calc-stack-size))

  ;; A typed non-assignment refuses, before touching the stack.
  (maf-push "2 x + 1")
  (goto-char (point-max))
  (cl-assert (string-match-p
              "not an assignment"
              (downcase
               (condition-case e (progn (le-run "5") "")
                 (user-error (error-message-string e))))))
  (cl-assert (string= (le-top) "2 x + 1"))
  (calc-pop (calc-stack-size))

  ;; A single undo reverts the evaluation.
  (maf-push "2 x + 1")
  (goto-char (point-max))
  (le-run "x = 3")
  (call-interactively 'maf-undo)
  (cl-assert (string= (le-top) "2 x + 1"))
  (calc-pop (calc-stack-size)))
