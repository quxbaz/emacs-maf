;; mafcmd-sum (a +): calc's `a +' made contextual. It prompts for the
;; index variable — the subject's priority variable the default — and
;; for the lower and upper bounds, and sums the entry at point over that
;; range: the whole entry, never a narrowed part (:scope entry). A
;; prefix argument sets the step, as calc's does. The first case goes
;; through the a + binding; the rest queue the prompts and call the
;; command directly.

(defun sm-top ()
  (math-format-value (maf--strip-encasing (calc-top 1 'full))))

(defun sm-run (input &optional prefix)
  "Call `mafcmd-sum' with INPUT queued at its prompts, under PREFIX."
  (setq unread-command-events (listify-key-sequence input))
  (let ((current-prefix-arg prefix))
    (call-interactively 'mafcmd-sum)))

(maf-step
  ;; The binding, through real keys: variable, from, to.
  (cl-assert (eq (key-binding (kbd "a +")) 'mafcmd-sum))
  (maf-push "k^2")
  (goto-char (point-max))
  (execute-kbd-macro (kbd "a + k RET 1 RET 5 RET"))
  (cl-assert (string= (sm-top) "55"))
  (cl-assert (= (calc-stack-size) 1))
  (calc-pop (calc-stack-size))

  ;; RET at the first prompt takes the subject's priority variable.
  (maf-push "k^2")
  (goto-char (point-max))
  (sm-run "\r1\r5\r")
  (cl-assert (string= (sm-top) "55"))
  (calc-pop (calc-stack-size))

  ;; The priority order is calc's: x before k, so RET on k x sums
  ;; over x.
  (maf-push "k x")
  (goto-char (point-max))
  (sm-run "\r1\r3\r")
  (cl-assert (string= (sm-top) "6 k"))
  (calc-pop (calc-stack-size))

  ;; A typed variable overrides the default.
  (maf-push "k x")
  (goto-char (point-max))
  (sm-run "k\r1\r3\r")
  (cl-assert (string= (sm-top) "6 x"))
  (calc-pop (calc-stack-size))

  ;; A symbolic bound gets a closed form when calc knows one.
  (maf-push "6 k^2")
  (goto-char (point-max))
  (sm-run "k\r1\rn\r")
  (cl-assert (string= (sm-top) "2 n^3 + 3 n^2 + n"))
  (calc-pop (calc-stack-size))

  ;; A sum calc cannot do stays written as a sum.
  (maf-push "1 / k")
  (goto-char (point-max))
  (sm-run "k\r1\rinf\r")
  (cl-assert (string= (sm-top) "sum(1 / k, k, 1, inf)"))
  (calc-pop (calc-stack-size))

  ;; --- the step, from the prefix argument ---

  ;; A numeric prefix steps the index by that amount.
  (maf-push "k")
  (goto-char (point-max))
  (sm-run "k\r1\r9\r" 2)
  (cl-assert (string= (sm-top) "25"))
  (calc-pop (calc-stack-size))

  ;; A negative step counts down from the lower bound.
  (maf-push "a_k")
  (goto-char (point-max))
  (sm-run "k\r10\r0\r" -2)
  (cl-assert (string= (sm-top) "a_0 + a_2 + a_4 + a_6 + a_8 + a_10"))
  (calc-pop (calc-stack-size))

  ;; A plain C-u asks for the step as a fourth input.
  (maf-push "k")
  (goto-char (point-max))
  (sm-run "k\r1\r9\r2\r" '(4))
  (cl-assert (string= (sm-top) "25"))
  (calc-pop (calc-stack-size))

  ;; --- a relation subject sums each side in turn ---

  (maf-push "x = k")
  (goto-char (point-max))
  (sm-run "k\r1\r3\r")
  (cl-assert (string= (sm-top) "3 x = 6"))
  (calc-pop (calc-stack-size))

  ;; --- subexpr targeting is disabled ---

  ;; Point within a sub-formula does not narrow: the whole entry sums.
  (maf-push "k^2 + k")
  (progn (calc-cursor-stack-index 1) (end-of-line) (backward-char 1))
  (sm-run "k\r1\r3\r")
  (cl-assert (string= (sm-top) "20"))
  (calc-pop (calc-stack-size))

  ;; Nor does a calc selection: the entry is taken whole and the
  ;; selection cleared.
  (maf-push "k^2 + k")
  (progn (calc-cursor-stack-index 1) (end-of-line) (backward-char 1)
         (execute-kbd-macro (kbd "j s")))
  (sm-run "k\r1\r3\r")
  (cl-assert (string= (sm-top) "20"))
  (cl-assert (null (calc-top 1 'sel)))
  (calc-pop (calc-stack-size))

  ;; --- targets, keep-args, and errors ---

  ;; Below the top, the entry at point is the subject and the rest of
  ;; the stack is untouched.
  (maf-push "k^2")
  (maf-push "99")
  (progn (calc-cursor-stack-index 2) (end-of-line))
  (sm-run "k\r1\r5\r")
  (cl-assert (= (calc-stack-size) 2))
  (cl-assert (string= (math-format-value (calc-top 2 'full)) "55"))
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "99"))
  (calc-pop (calc-stack-size))

  ;; With keep-args the entry stays and the sum is pushed on top.
  (maf-push "k^2")
  (goto-char (point-max))
  (progn (setq unread-command-events (listify-key-sequence "k\r1\r5\r"))
         (call-interactively 'calc-keep-args)
         (call-interactively 'mafcmd-sum))
  (cl-assert (= (calc-stack-size) 2))
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "55"))
  (cl-assert (string= (math-format-value (calc-top 2 'full)) "k^2"))
  (calc-pop (calc-stack-size))

  ;; Anything but a single variable at the first prompt refuses, before
  ;; touching the stack.
  (maf-push "k^2")
  (goto-char (point-max))
  (cl-assert (string-match-p
              "not a variable"
              (downcase
               (condition-case e (progn (sm-run "k + 1\r") "")
                 (user-error (error-message-string e))))))
  (cl-assert (string= (sm-top) "k^2"))
  (calc-pop (calc-stack-size))

  ;; An empty bound refuses the same way.
  (maf-push "k^2")
  (goto-char (point-max))
  (cl-assert (string-match-p
              "no expression"
              (downcase
               (condition-case e (progn (sm-run "k\r\r") "")
                 (user-error (error-message-string e))))))
  (cl-assert (string= (sm-top) "k^2"))
  (calc-pop (calc-stack-size))

  ;; A single undo reverts the sum.
  (maf-push "k^2")
  (goto-char (point-max))
  (sm-run "k\r1\r5\r")
  (call-interactively 'maf-undo)
  (cl-assert (string= (sm-top) "k^2"))
  (calc-pop (calc-stack-size)))
