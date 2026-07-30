;;; Tests for mafcmd-swap-vars -- the prompted variable swap.
;;
;; The command reads its pair from the minibuffer. `maf-with-input'
;; stands in for the typing, reproducing `read-string's contract: the
;; text given is what was typed, and nil is a bare RET, which
;; read-string answers with the default the prompt offered.

(defmacro maf-with-input (input &rest body)
  "Run BODY with the swap prompt answered by INPUT (nil = bare RET)."
  (declare (indent 1))
  `(cl-letf (((symbol-function 'read-string)
              (lambda (_prompt &optional _init _hist default &rest _)
                (or ,input default ""))))
     ,@body))

(maf-step
  ;; --- The default pair: a bare RET swaps the first two variables ---

  (maf-push "x^2 + y")
  (goto-char (point-max))
  (cl-assert (string= (maf--swap-vars-default) "x y"))
  (maf-with-input nil (call-interactively 'mafcmd-swap-vars))
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "y^2 + x"))
  (cl-assert (= (calc-stack-size) 1))
  (calc-pop (calc-stack-size))

  ;; x, y, z, t come before other names, so y outranks a here.
  (maf-push "a + y")
  (goto-char (point-max))
  (cl-assert (string= (maf--swap-vars-default) "y a"))
  (maf-with-input nil (call-interactively 'mafcmd-swap-vars))
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "y + a"))
  (calc-pop (calc-stack-size))

  ;; Fewer than two variables: the prompt has no default to offer.
  (maf-push "x + 1")
  (goto-char (point-max))
  (cl-assert (null (maf--swap-vars-default)))
  (calc-pop (calc-stack-size))

  ;; --- Relations: taken whole, shape preserved ---

  (maf-push "2 y = x + 2")
  (goto-char (point-max))
  (maf-with-input "x y" (call-interactively 'mafcmd-swap-vars))
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "2 x = y + 2"))
  (calc-pop (calc-stack-size))

  ;; The order the pair is typed in is immaterial.
  (maf-push "2 y = x + 2")
  (goto-char (point-max))
  (maf-with-input "y x" (call-interactively 'mafcmd-swap-vars))
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "2 x = y + 2"))
  (calc-pop (calc-stack-size))

  ;; The swap is simultaneous: a sequential substitution would collapse
  ;; both terms onto one name here.
  (maf-push "x + y")
  (goto-char (point-max))
  (maf-with-input "x y" (call-interactively 'mafcmd-swap-vars))
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "y + x"))
  (calc-pop (calc-stack-size))

  ;; Variables outside the pair are left alone.
  (maf-push "a x + b y")
  (goto-char (point-max))
  (maf-with-input "x y" (call-interactively 'mafcmd-swap-vars))
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "a y + b x"))
  (calc-pop (calc-stack-size))

  ;; Nothing simplifies or reorders: an unsorted sum stays as written.
  (maf-push "y^3 + x^7")
  (goto-char (point-max))
  (maf-with-input "x y" (call-interactively 'mafcmd-swap-vars))
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "x^3 + y^7"))
  (calc-pop (calc-stack-size))

  ;; Non-commutative operators keep their operand order too.
  (maf-push "x / y - y^2")
  (goto-char (point-max))
  (maf-with-input "x y" (call-interactively 'mafcmd-swap-vars))
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "y / x - x^2"))
  (calc-pop (calc-stack-size))

  ;; Inside a function call, and under a vector.
  (maf-push "[sin(x), cos(y)]")
  (goto-char (point-max))
  (maf-with-input "x y" (call-interactively 'mafcmd-swap-vars))
  (cl-assert (string= (math-format-value (calc-top 1 'full))
                      "[sin(y), cos(x)]"))
  (calc-pop (calc-stack-size))

  ;; --- Renaming: only one of the two names occurs ---

  (maf-push "u + 1")
  (goto-char (point-max))
  (maf-with-input "u x" (call-interactively 'mafcmd-swap-vars))
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "x + 1"))
  (calc-pop (calc-stack-size))

  ;; --- Input formats ---

  (maf-push "x + y")
  (goto-char (point-max))
  (maf-with-input "x,y" (call-interactively 'mafcmd-swap-vars))
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "y + x"))
  (calc-pop (calc-stack-size))

  (maf-push "x + y")
  (goto-char (point-max))
  (maf-with-input "[x,y]" (call-interactively 'mafcmd-swap-vars))
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "y + x"))
  (calc-pop (calc-stack-size))

  (maf-push "x + y")
  (goto-char (point-max))
  (maf-with-input "[x y]" (call-interactively 'mafcmd-swap-vars))
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "y + x"))
  (calc-pop (calc-stack-size))

  ;; Extra whitespace around and between the names is immaterial.
  (maf-push "x + y")
  (goto-char (point-max))
  (maf-with-input "  x   y  " (call-interactively 'mafcmd-swap-vars))
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "y + x"))
  (calc-pop (calc-stack-size))

  ;; --- Bad input leaves the stack untouched ---

  ;; One name only.
  (maf-push "x + y")
  (goto-char (point-max))
  (cl-assert (eq 'user-error
                 (condition-case err
                     (progn (maf-with-input "x"
                              (call-interactively 'mafcmd-swap-vars))
                            nil)
                   (user-error (car err)))))
  (cl-assert (equal (calc-top 1 'full) (math-read-expr "x + y")))
  (cl-assert (= (calc-stack-size) 1))
  (calc-pop (calc-stack-size))

  ;; Three names.
  (maf-push "x + y")
  (goto-char (point-max))
  (cl-assert (eq 'user-error
                 (condition-case err
                     (progn (maf-with-input "x y z"
                              (call-interactively 'mafcmd-swap-vars))
                            nil)
                   (user-error (car err)))))
  (cl-assert (equal (calc-top 1 'full) (math-read-expr "x + y")))
  (calc-pop (calc-stack-size))

  ;; Something that is not a variable name.
  (maf-push "x + y")
  (goto-char (point-max))
  (cl-assert (eq 'user-error
                 (condition-case err
                     (progn (maf-with-input "2 y"
                              (call-interactively 'mafcmd-swap-vars))
                            nil)
                   (user-error (car err)))))
  (cl-assert (equal (calc-top 1 'full) (math-read-expr "x + y")))
  (calc-pop (calc-stack-size))

  ;; Unparseable input is no more a variable than a number is.
  (maf-push "x + y")
  (goto-char (point-max))
  (cl-assert (eq 'user-error
                 (condition-case err
                     (progn (maf-with-input "x )("
                              (call-interactively 'mafcmd-swap-vars))
                            nil)
                   (user-error (car err)))))
  (cl-assert (equal (calc-top 1 'full) (math-read-expr "x + y")))
  (calc-pop (calc-stack-size))

  ;; Neither name occurs: a miss, not a silent no-op.
  (maf-push "a + b")
  (goto-char (point-max))
  (cl-assert (eq 'user-error
                 (condition-case err
                     (progn (maf-with-input "x y"
                              (call-interactively 'mafcmd-swap-vars))
                            nil)
                   (user-error (car err)))))
  (cl-assert (equal (calc-top 1 'full) (math-read-expr "a + b")))
  (cl-assert (= (calc-stack-size) 1))
  (calc-pop (calc-stack-size))

  ;; --- At home: the top entry, with the entries below untouched ---

  (maf-push "a + b")
  (maf-push "x + y")
  (goto-char (point-max))
  (maf-with-input "x y" (call-interactively 'mafcmd-swap-vars))
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "y + x"))
  (cl-assert (equal (calc-top 2 'full) (math-read-expr "a + b")))
  (cl-assert (= (calc-stack-size) 2))
  (calc-pop (calc-stack-size))

  ;; --- Point within a formula does not narrow the subject ---

  ;; Point on the x of a (x + y): the whole entry swaps, not the sum
  ;; point sits in. Written a*(x + y): calc's reader takes a (x + y) as
  ;; a call to a.
  (maf-push "a*(x + y)")
  (progn (goto-char (point-min)) (search-forward "x") (backward-char 1))
  (maf-with-input "x y" (call-interactively 'mafcmd-swap-vars))
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "a*(y + x)"))
  (calc-pop (calc-stack-size))

  ;; Both factors swap, not just the one holding point. The prompt has
  ;; its default here too, since it reads the same whole entry.
  (maf-push "(x - y) (x + y)")
  (progn (goto-char (point-min)) (search-forward "x") (backward-char 1))
  (cl-assert (string= (maf--swap-vars-default) "x y"))
  (maf-with-input nil (call-interactively 'mafcmd-swap-vars))
  (cl-assert (string= (math-format-value (calc-top 1 'full))
                      "(y - x) (y + x)"))
  (calc-pop (calc-stack-size))

  ;; A pair split across a relation's sides, with point on one of them:
  ;; the relation is taken whole rather than a side at a time.
  (maf-push "2 y = x + 2")
  (progn (goto-char (point-min)) (search-forward "x") (backward-char 1))
  (maf-with-input "x y" (call-interactively 'mafcmd-swap-vars))
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "2 x = y + 2"))
  (calc-pop (calc-stack-size))

  ;; A rename likewise covers the entry, not the occurrence under point.
  (maf-push "a u + b u")
  (progn (goto-char (point-min)) (search-forward "u") (backward-char 1))
  (maf-with-input "u x" (call-interactively 'mafcmd-swap-vars))
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "a x + b x"))
  (calc-pop (calc-stack-size))

  ;; An explicit calc selection is bypassed as well: the entry swaps
  ;; whole, and the selection is not what gets replaced.
  (maf-push "(x - y) (x + y)")
  (progn (goto-char (point-min)) (search-forward "x") (backward-char 1)
         (call-interactively 'calc-select-here))
  (cl-assert (calc-top 1 'sel))
  (maf-with-input "x y" (call-interactively 'mafcmd-swap-vars))
  (cl-assert (string= (math-format-value (calc-top 1 'full))
                      "(y - x) (y + x)"))
  (calc-pop (calc-stack-size))

  ;; Point on a sub-formula holding neither name is no longer a miss:
  ;; the entry is the subject, and it holds both.
  (maf-push "2 y = x + 2")
  (progn (goto-char (point-min)) (search-forward "2") (backward-char 1))
  (maf-with-input "x y" (call-interactively 'mafcmd-swap-vars))
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "2 x = y + 2"))
  (calc-pop (calc-stack-size))

  ;; --- The binding ---

  (cl-assert (eq (lookup-key maf-mode-map (kbd "l x")) 'mafcmd-swap-vars)))
