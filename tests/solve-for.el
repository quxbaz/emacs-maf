;;; Tests for mafcmd-solve-for -- the prompted contextual solve.
;;
;; The command reads its variable from the minibuffer. `maf-with-input'
;; stands in for the typing, reproducing `read-string's contract: the
;; text given is what was typed, and nil is a bare RET, which read-string
;; answers with the default the prompt offered.

(defmacro maf-with-input (input &rest body)
  "Run BODY with the solve-for prompt answered by INPUT (nil = bare RET)."
  (declare (indent 1))
  `(cl-letf (((symbol-function 'read-string)
              (lambda (_prompt &optional _init _hist default &rest _)
                (or ,input default ""))))
     ,@body))

(maf-step
  ;; --- The default variable: a bare RET solves for the priority one ---

  (maf-push "x + 3 = 7")
  (goto-char (point-max))
  ;; The prompt's default is the subject's priority variable.
  (cl-assert (string= (maf--solve-for-default-var) "x"))
  (maf-with-input nil (call-interactively 'mafcmd-solve-for))
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "x = 4"))
  (cl-assert (= (calc-stack-size) 1))
  (calc-pop (calc-stack-size))

  ;; x, y, z, t come before other names, so y outranks a here.
  (maf-push "a + y = 5")
  (goto-char (point-max))
  (cl-assert (string= (maf--solve-for-default-var) "y"))
  (maf-with-input nil (call-interactively 'mafcmd-solve-for))
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "y = -a + 5"))
  (calc-pop (calc-stack-size))

  ;; --- A named variable ---

  (maf-push "x + y = 5")
  (goto-char (point-max))
  (maf-with-input "y" (call-interactively 'mafcmd-solve-for))
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "y = -x + 5"))
  (calc-pop (calc-stack-size))

  ;; Solving for a variable the equation does not contain leaves it
  ;; alone: calc returns an unevaluated solve call, which commits as the
  ;; original entry rather than landing a solve(...) on the stack.
  (maf-push "x + 3 = 7")
  (goto-char (point-max))
  (maf-with-input "z" (call-interactively 'mafcmd-solve-for))
  (cl-assert (equal (calc-top 1 'full)
                    (math-read-expr "x + 3 = 7")))
  (cl-assert (= (calc-stack-size) 1))
  (calc-pop (calc-stack-size))

  ;; An expression calc cannot solve at all is likewise unchanged.
  (maf-push "x + sin(x) = 1")
  (goto-char (point-max))
  (maf-with-input "x" (call-interactively 'mafcmd-solve-for))
  (cl-assert (equal (calc-top 1 'full) (math-read-expr "x + sin(x) = 1")))
  (calc-pop (calc-stack-size))

  ;; --- Reciprocal trig: solved over the base call ---

  ;; cot, sec and csc carry no `math-inverse' for calc to strip, so the
  ;; direct solve punts and the entry used to come back unchanged.
  ;; Written as 1 over tan, cos and sin, the same equation solves.
  ;; Asserted against the base call's own answer rather than a written
  ;; form: what the arc function evaluates to is the session's business
  ;; — symbolic mode and the angle mode both move it — and the claim
  ;; here is only that the rewrite hands calc the same equation.
  (progn
    (maf-push "tan(x) = 2")
    (goto-char (point-max))
    (maf-with-input "x" (call-interactively 'mafcmd-solve-for))
    (setq sf--base-answer (calc-top 1 'full))
    (calc-pop (calc-stack-size))
    nil)
  (maf-push "cot(x) = 1:2")
  (goto-char (point-max))
  (maf-with-input "x" (call-interactively 'mafcmd-solve-for))
  (cl-assert (equal (calc-top 1 'full) sf--base-answer))
  (cl-assert (maf--relation-p (calc-top 1 'full)))
  (calc-pop (calc-stack-size))

  (maf-push "csc(x) = 2")
  (goto-char (point-max))
  (maf-with-input "x" (call-interactively 'mafcmd-solve-for))
  (cl-assert (string= (math-format-flat-expr (calc-top 1 'full) 0)
                      "x = arcsin(1:2)"))
  (calc-pop (calc-stack-size))

  ;; The argument need not be the bare variable, and a layer over the
  ;; call still peels once the rewrite has given calc its hold.
  (progn
    (maf-push "tan(2 x + 1) = 2")
    (goto-char (point-max))
    (maf-with-input "x" (call-interactively 'mafcmd-solve-for))
    (setq sf--base-answer (calc-top 1 'full))
    (calc-pop (calc-stack-size))
    nil)
  (maf-push "cot(2 x + 1) = 1:2")
  (goto-char (point-max))
  (maf-with-input "x" (call-interactively 'mafcmd-solve-for))
  (cl-assert (equal (calc-top 1 'full) sf--base-answer))
  (calc-pop (calc-stack-size))

  ;; The rewrite is a fallback, not a pass: coth solves directly,
  ;; through the exponential form it simplifies to, and keeps the
  ;; answer calc gives rather than being turned into an arctanh.
  (maf-push "coth(x) = 1:2")
  (goto-char (point-max))
  (maf-with-input "x" (call-interactively 'mafcmd-solve-for))
  (cl-assert (not (string-match-p
                   "arctanh" (math-format-flat-expr (calc-top 1 'full) 0))))
  (cl-assert (maf--relation-p (calc-top 1 'full)))
  (calc-pop (calc-stack-size))

  ;; Only calls holding the variable are rewritten: a sec elsewhere in
  ;; the relation comes back spelled the way it was typed.
  (maf-push "sec(a) + x = 1")
  (goto-char (point-max))
  (maf-with-input "x" (call-interactively 'mafcmd-solve-for))
  (cl-assert (string= (math-format-flat-expr (calc-top 1 'full) 0)
                      "x = 1 - sec(a)"))
  (calc-pop (calc-stack-size))

  ;; --- Several variables: a system solved for all of them ---

  ;; Commas separate the names.
  (maf-push "[x + y = 3, x - y = 1]")
  (goto-char (point-max))
  (maf-with-input "x,y" (call-interactively 'mafcmd-solve-for))
  (cl-assert (string= (math-format-value (calc-top 1 'full))
                      "[x = 2, y = 1]"))
  (calc-pop (calc-stack-size))

  ;; Spaces separate them too — the names are bracketed into a vector, so
  ;; "x y" is two variables and not the product x y.
  (maf-push "[x + y = 3, x - y = 1]")
  (goto-char (point-max))
  (maf-with-input "x y" (call-interactively 'mafcmd-solve-for))
  (cl-assert (string= (math-format-value (calc-top 1 'full))
                      "[x = 2, y = 1]"))
  (calc-pop (calc-stack-size))

  ;; A list the user brackets themselves is passed through as written.
  (maf-push "[x + y = 3, x - y = 1]")
  (goto-char (point-max))
  (maf-with-input "[x, y]" (call-interactively 'mafcmd-solve-for))
  (cl-assert (string= (math-format-value (calc-top 1 'full))
                      "[x = 2, y = 1]"))
  (calc-pop (calc-stack-size))

  ;; --- Input shapes of the subject ---

  ;; A bare expression is solved as = 0.
  (maf-push "x + 3")
  (goto-char (point-max))
  (maf-with-input nil (call-interactively 'mafcmd-solve-for))
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "x = -3"))
  (calc-pop (calc-stack-size))

  ;; An inequality keeps its relation; calc flips the sense when it must.
  (maf-push "2 x - 3 < 7")
  (goto-char (point-max))
  (maf-with-input nil (call-interactively 'mafcmd-solve-for))
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "x < 5"))
  (calc-pop (calc-stack-size))

  ;; Dividing through by a negative does not flip the operator: calc
  ;; swaps the sides instead, leaving the solved variable on the right
  ;; (-2 < x). The solution is turned back so the variable leads, the
  ;; direction turning with it, which says the same thing.
  (maf-push "-2 x < 4")
  (goto-char (point-max))
  (maf-with-input nil (call-interactively 'mafcmd-solve-for))
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "x > -2"))
  (calc-pop (calc-stack-size))

  ;; Same the other way round: a > whose sides calc swaps comes back a <.
  (maf-push "4 > 2 x")
  (goto-char (point-max))
  (maf-with-input nil (call-interactively 'mafcmd-solve-for))
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "x < 2"))
  (calc-pop (calc-stack-size))

  ;; >= turns to <= with its sides.
  (maf-push "-x >= 3")
  (goto-char (point-max))
  (maf-with-input nil (call-interactively 'mafcmd-solve-for))
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "x <= -3"))
  (calc-pop (calc-stack-size))

  ;; A direction hinging on a sign calc cannot see splits as calc's if;
  ;; substituting a value for k later collapses it to the holding branch.
  (maf-push "k x < 1")
  (goto-char (point-max))
  (maf-with-input nil (call-interactively 'mafcmd-solve-for))
  (cl-assert (string= (math-format-value (calc-top 1 'full))
                      "k > 0 ? x < 1 / k : k < 0 ? x > 1 / k : -1 < 0"))
  (calc-pop (calc-stack-size))

  ;; Past linear the direction cannot be kept: unchanged, not x != 2.
  (maf-push "x^2 < 4")
  (goto-char (point-max))
  (maf-with-input nil (call-interactively 'mafcmd-solve-for))
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "x^2 < 4"))
  (calc-pop (calc-stack-size))

  ;; An unsolvable entry commits as written — "unchanged" means unchanged,
  ;; so nothing is turned round on the way out.
  (maf-push "5 = y")
  (goto-char (point-max))
  (maf-with-input "x" (call-interactively 'mafcmd-solve-for))
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "5 = y"))
  (calc-pop (calc-stack-size))

  ;; != is kept as well.
  (maf-push "x + 3 != 7")
  (goto-char (point-max))
  (maf-with-input nil (call-interactively 'mafcmd-solve-for))
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "x != 4"))
  (calc-pop (calc-stack-size))

  ;; --- Solutions stay exact: symbolic and prefer-frac, as
  ;; mafcmd-auto-solve does, whatever the ambient modes ---

  (maf-push "2 x = 1")
  (goto-char (point-max))
  (let ((calc-symbolic-mode nil) (calc-prefer-frac nil))
    (maf-with-input nil (call-interactively 'mafcmd-solve-for)))
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "x = 1:2"))
  (calc-pop (calc-stack-size))

  (maf-push "x^2 = 2")
  (goto-char (point-max))
  (let ((calc-symbolic-mode nil) (calc-prefer-frac nil))
    (maf-with-input nil (call-interactively 'mafcmd-solve-for)))
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "x = sqrt(2)"))
  (calc-pop (calc-stack-size))

  (maf-push "x^2 + y^2 = r^2")
  (goto-char (point-max))
  (maf-with-input "y" (call-interactively 'mafcmd-solve-for))
  (cl-assert (string= (math-format-value (calc-top 1 'full))
                      "y = sqrt(r^2 - x^2)"))
  (calc-pop (calc-stack-size))

  ;; --- Whole-entry scope: point never narrows the subject ---

  ;; Point on the 3 inside the formula. With subexpr targeting this would
  ;; act on the 3; here the whole relation is solved, and point stays put.
  (maf-push "x + 3 = 7")
  (progn (calc-cursor-stack-index 1) (beginning-of-line)
         (search-forward "3") (backward-char 1))
  (maf-with-input nil (call-interactively 'mafcmd-solve-for))
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "x = 4"))
  (calc-pop (calc-stack-size))

  ;; An explicit calc selection is ignored for the same reason.
  (maf-push "x + 3 = 7")
  (progn (calc-cursor-stack-index 1) (beginning-of-line)
         (search-forward "3") (backward-char 1)
         (calc-select-here nil))
  (maf-with-input nil (call-interactively 'mafcmd-solve-for))
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "x = 4"))
  (calc-clear-selections)
  (calc-pop (calc-stack-size))

  ;; Point at an entry's margin picks that entry, not the top: the
  ;; equation at level 2 is solved and the 99 above it is untouched.
  (maf-push "x + 3 = 7")
  (maf-push "99")
  (progn (calc-cursor-stack-index 2) (end-of-line))
  (maf-with-input nil (call-interactively 'mafcmd-solve-for))
  (cl-assert (= (calc-stack-size) 2))
  (cl-assert (string= (math-format-value (calc-top 2 'full)) "x = 4"))
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "99"))
  (calc-pop (calc-stack-size))

  ;; At home the top entry is the subject.
  (maf-push "5 x = 20")
  (maf-push "x + 3 = 7")
  (goto-char (point-max))
  (maf-with-input nil (call-interactively 'mafcmd-solve-for))
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "x = 4"))
  (cl-assert (string= (math-format-value (calc-top 2 'full)) "5 x = 20"))
  (calc-pop (calc-stack-size))

  ;; --- Keep-args pushes the solution and leaves the original ---

  (maf-push "x + 3 = 7")
  (goto-char (point-max))
  (let ((calc-keep-args-flag t))
    (maf-with-input nil (call-interactively 'mafcmd-solve-for)))
  (cl-assert (= (calc-stack-size) 2))
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "x = 4"))
  (cl-assert (string= (math-format-value (calc-top 2 'full)) "x + 3 = 7"))
  (calc-pop (calc-stack-size))

  ;; --- Calc's Inverse and Hyperbolic flags pick the other solvers ---

  ;; Inverse: the inverse function, as an expression rather than a
  ;; relation.
  (maf-push "x^2")
  (goto-char (point-max))
  (let ((calc-inverse-flag t))
    (maf-with-input nil (call-interactively 'mafcmd-solve-for)))
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "sqrt(x)"))
  ;; The flags are consumed, so the next command starts clean.
  (cl-assert (null calc-inverse-flag))
  (calc-pop (calc-stack-size))

  ;; A non-invertible expression commits unchanged, the same degenerate
  ;; policy as an unsolvable equation.
  (maf-push "x + sin(x)")
  (goto-char (point-max))
  (let ((calc-inverse-flag t))
    (maf-with-input nil (call-interactively 'mafcmd-solve-for)))
  (cl-assert (equal (calc-top 1 'full) (math-read-expr "x + sin(x)")))
  (calc-pop (calc-stack-size))

  ;; Hyperbolic: the full solve, naming the sign freedom with a dummy.
  (maf-push "x^2 = 4")
  (goto-char (point-max))
  (let ((calc-hyperbolic-flag t))
    (maf-with-input nil (call-interactively 'mafcmd-solve-for)))
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "x = 2 s1"))
  (cl-assert (null calc-hyperbolic-flag))
  (calc-pop (calc-stack-size))

  ;; Inverse Hyperbolic: the full inverse.
  (maf-push "x^2")
  (goto-char (point-max))
  (let ((calc-inverse-flag t) (calc-hyperbolic-flag t))
    (maf-with-input nil (call-interactively 'mafcmd-solve-for)))
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "s1 sqrt(x)"))
  (cl-assert (and (null calc-inverse-flag) (null calc-hyperbolic-flag)))
  (calc-pop (calc-stack-size))

  ;; --- Invalid input is rejected before any calc state changes ---

  ;; A subject with no variable offers no default, so a bare RET has
  ;; nothing to solve for.
  (maf-push "3 = 3")
  (goto-char (point-max))
  (cl-assert (null (maf--solve-for-default-var)))
  (cl-assert (equal (maf-with-input nil
                      (condition-case e
                          (progn (call-interactively 'mafcmd-solve-for) 'no-error)
                        (error (error-message-string e))))
                    "No variable to solve for"))
  ;; The entry is untouched.
  (cl-assert (and (= (calc-stack-size) 1)
                  (string= (math-format-value (calc-top 1 'full)) "3 = 3")))
  (calc-pop (calc-stack-size))

  ;; Input calc cannot parse reports the parse failure, not its position.
  (maf-push "x + 3 = 7")
  (goto-char (point-max))
  (cl-assert (equal (maf-with-input "("
                      (condition-case e
                          (progn (call-interactively 'mafcmd-solve-for) 'no-error)
                        (error (error-message-string e))))
                    "Bad format in expression: Expected a number"))
  (cl-assert (and (= (calc-stack-size) 1)
                  (string= (math-format-value (calc-top 1 'full))
                           "x + 3 = 7")))
  (calc-pop (calc-stack-size))

  ;; A power of a compound base is past calc's whole-equation reach —
  ;; degree 8 once expanded, and the linear-in-x^8 trick needs a bare
  ;; variable — so the solve peels instead: the base stands in as a
  ;; fresh unknown, its own equation solving onward (`maf--solve-peel').
  (maf-push "(x - 8)^8 = 256")
  (goto-char (point-max))
  (maf-with-input "x" (call-interactively 'mafcmd-solve-for))
  (cl-assert (string= (math-format-flat-expr
                       (maf--strip-encasing (calc-top 1 'full)) 0)
                      "x = 10"))
  (calc-pop (calc-stack-size))

  ;; Layers unwind recursively, the inner quadratic finishing exact.
  (maf-push "((x + 1)^2 - 3)^8 = 256")
  (goto-char (point-max))
  (maf-with-input "x" (call-interactively 'mafcmd-solve-for))
  (cl-assert (string= (math-format-flat-expr
                       (maf--strip-encasing (calc-top 1 'full)) 0)
                      "x = sqrt(5) - 1"))
  (calc-pop (calc-stack-size))

  ;; An inequality does not peel — its direction through an even power
  ;; is nothing to guess at — and commits unchanged as before.
  (maf-push "(x - 8)^8 < 256")
  (goto-char (point-max))
  (maf-with-input "x" (call-interactively 'mafcmd-solve-for))
  (cl-assert (string= (math-format-flat-expr
                       (maf--strip-encasing (calc-top 1 'full)) 0)
                      "(x - 8)^8 < 256"))
  (calc-pop (calc-stack-size))

  ;; An empty stack has nothing to resolve, and nothing is created.
  (cl-assert (equal (maf-with-input "x"
                      (condition-case e
                          (progn (call-interactively 'mafcmd-solve-for) 'no-error)
                        (error (error-message-string e))))
                    "Too few elements on stack"))
  (cl-assert (zerop (calc-stack-size))))
