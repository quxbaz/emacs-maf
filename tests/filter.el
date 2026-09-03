;; mafcmd-filter (f f) and mafcmd-filter-stack (f $): keep the elements
;; of a vector a predicate accepts — typed at a prompt that reads as the
;; map prompt does, or taken from the entry above the subject. I keeps
;; the rejected elements instead. The prompt is driven with real keys,
;; so each case queues its input and fires the command in a single
;; form.

(defun maf-test--filter-top ()
  "The top entry in flat notation, the selection encasing gone."
  (math-format-flat-expr (maf--strip-encasing (calc-top 1 'full)) 0))

(defun maf-test--filter (input)
  "Run `mafcmd-filter' with INPUT typed at its prompt."
  (setq unread-command-events (listify-key-sequence (concat input "\r")))
  (call-interactively 'mafcmd-filter))

(defun maf-test--filter-refused (input)
  "Run `mafcmd-filter' with INPUT at its prompt; t if it refused."
  (condition-case nil
      (progn (maf-test--filter input) nil)
    (user-error (setq unread-command-events nil) t)))

(maf-step
  ;; Home: a comparison with $ standing for the element. The vector is
  ;; replaced in place, nothing else on the stack.
  (maf-push "[0, 1, 2, 3, 4]")
  (goto-char (point-max))
  (maf-test--filter "$ > 2")
  (cl-assert (string= (maf-test--filter-top) "[3, 4]"))
  (cl-assert (= (calc-stack-size) 1))
  (calc-pop (calc-stack-size))

  ;; The map prompt's shorthand: input naming no element reads as a
  ;; comparison with the element on the open side, so > 2 is $ > 2.
  (maf-push "[0, 1, 2, 3, 4]")
  (goto-char (point-max))
  (maf-test--filter "> 2")
  (cl-assert (string= (maf-test--filter-top) "[3, 4]"))
  (calc-pop (calc-stack-size))

  ;; A free variable names the element, and a bare function name is
  ;; the predicate it names.
  (maf-push "[1, 2, 3, 4, 5, 6]")
  (goto-char (point-max))
  (maf-test--filter "x % 2 == 0")
  (cl-assert (string= (maf-test--filter-top) "[2, 4, 6]"))
  (calc-pop (calc-stack-size))
  (maf-push "[1, 2, 3, 4, 5, 6]")
  (goto-char (point-max))
  (maf-test--filter "prime")
  (cl-assert (string= (maf-test--filter-top) "[2, 3, 5]"))
  (calc-pop (calc-stack-size))

  ;; A bare element decides as a calc condition does: nonzero keeps.
  (maf-push "[0, 1, 0, 2]")
  (goto-char (point-max))
  (maf-test--filter "x")
  (cl-assert (string= (maf-test--filter-top) "[1, 2]"))
  (calc-pop (calc-stack-size))

  ;; I keeps the rejected elements instead, and is spent by the run.
  (maf-push "[0, 1, 2, 3, 4]")
  (goto-char (point-max))
  (progn (setq calc-inverse-flag t)
         (maf-test--filter "> 2"))
  (cl-assert (string= (maf-test--filter-top) "[0, 1, 2]"))
  (cl-assert (null calc-inverse-flag))
  (calc-pop (calc-stack-size))

  ;; A predicate that stays symbolic for an element decides nothing:
  ;; the command refuses rather than guess, and the entry stands.
  (maf-push "[a, 3]")
  (goto-char (point-max))
  (cl-assert (maf-test--filter-refused "> 2"))
  (cl-assert (string= (maf-test--filter-top) "[a, 3]"))
  (calc-pop (calc-stack-size))

  ;; Not a vector: nothing to choose among.
  (maf-push "7")
  (goto-char (point-max))
  (cl-assert (maf-test--filter-refused "> 2"))
  (cl-assert (string= (maf-test--filter-top) "7"))
  (calc-pop (calc-stack-size))

  ;; The pair form has no reading as a predicate over one element.
  (maf-push "[1, 2]")
  (maf-push "[3, 4]")
  (goto-char (point-max))
  (cl-assert (maf-test--filter-refused "$$ > $"))
  (cl-assert (= (calc-stack-size) 2))
  (calc-pop (calc-stack-size))

  ;; A matrix filters its rows: the elements of a vector are what a
  ;; filter chooses among, whatever their shape.
  (maf-push "[[1, 2], [3, 4]]")
  (goto-char (point-max))
  (maf-test--filter "$_1 > 2")
  (cl-assert (string= (maf-test--filter-top) "[[3, 4]]"))
  (calc-pop (calc-stack-size))

  ;; An equation filters side by side, as any command does.
  (maf-push "[1, 2, 3] = [2, 3, 4]")
  (goto-char (point-max))
  (maf-test--filter "> 2")
  (cl-assert (string= (maf-test--filter-top) "[3] = [3, 4]"))
  (calc-pop (calc-stack-size))

  ;; A calc selection narrows: the selected vector filters in place,
  ;; what surrounds it left alone.
  (maf-push "[1, 2, 3] + k")
  (progn (calc-cursor-stack-index 1)
         (search-forward "2" (line-end-position))
         (backward-char 1)
         (execute-kbd-macro (kbd "j 1"))
         (calc-cursor-stack-index 1))
  (maf-test--filter "> 1")
  (cl-assert (string= (maf-test--filter-top) "[2, 3] + k"))
  ;; The selection rides the result, and a pop under one deletes the
  ;; selected part rather than the entry: clear it first.
  (progn (maf-clear-selections))
  (calc-pop (calc-stack-size))

  ;; The stack form: the entry above the subject is the predicate and
  ;; is consumed. A lone $ at the prompt is the same gesture.
  (maf-push "[0, 1, 2, 3, 4]")
  (maf-push "x > 2")
  (goto-char (point-max))
  (call-interactively 'mafcmd-filter-stack)
  (cl-assert (string= (maf-test--filter-top) "[3, 4]"))
  (cl-assert (= (calc-stack-size) 1))
  (calc-pop (calc-stack-size))
  (maf-push "[0, 1, 2, 3, 4]")
  (maf-push "x > 2")
  (goto-char (point-max))
  (maf-test--filter "$")
  (cl-assert (string= (maf-test--filter-top) "[3, 4]"))
  (cl-assert (= (calc-stack-size) 1))
  (calc-pop (calc-stack-size))
  (maf-push "[0, 1, 2, 3, 4]")
  (maf-push "x > 2")
  (goto-char (point-max))
  (progn (setq calc-inverse-flag t)
         (call-interactively 'mafcmd-filter-stack))
  (cl-assert (string= (maf-test--filter-top) "[0, 1, 2]"))
  (cl-assert (null calc-inverse-flag))
  (calc-pop (calc-stack-size))

  ;; The keys, driven for real: f f prompts, f $ takes the stack, and
  ;; I in front of either keeps the rejected elements.
  (maf-push "[0, 1, 2, 3, 4]")
  (goto-char (point-max))
  (execute-kbd-macro (kbd "f f > 2 RET"))
  (cl-assert (string= (maf-test--filter-top) "[3, 4]"))
  (calc-pop (calc-stack-size))
  (maf-push "[0, 1, 2, 3, 4]")
  (goto-char (point-max))
  (execute-kbd-macro (kbd "I f f > 2 RET"))
  (cl-assert (string= (maf-test--filter-top) "[0, 1, 2]"))
  (calc-pop (calc-stack-size))
  (maf-push "[0, 1, 2, 3, 4]")
  (maf-push "x > 2")
  (goto-char (point-max))
  (execute-kbd-macro (kbd "f $"))
  (cl-assert (string= (maf-test--filter-top) "[3, 4]"))
  (cl-assert (= (calc-stack-size) 1))
  (calc-pop (calc-stack-size))

  ;; No hyperbolic variant: H refuses and the flag is spent.
  (maf-push "[0, 1, 2]")
  (goto-char (point-max))
  (cl-assert (eq :error (condition-case nil
                            (progn (setq calc-hyperbolic-flag t)
                                   (maf-test--filter "> 1")
                                   :ok)
                          (user-error :error))))
  (cl-assert (null calc-hyperbolic-flag))
  (cl-assert (string= (maf-test--filter-top) "[0, 1, 2]"))
  (calc-pop (calc-stack-size)))
