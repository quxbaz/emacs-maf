;; mafcmd-map (M :) and mafcmd-map-stack (M $): apply a formula to the
;; target — each element of a vector, both sides of an equation. The
;; subject is the whole entry wherever point sits on it; a region or a
;; calc selection still narrows. M :'s prompt is driven with real keys,
;; so each case queues its input and fires the command in a single
;; form.

(defun maf-test-map-refused (keys)
  "Run `mafcmd-map' with KEYS at its prompt; t if it refused."
  (condition-case nil
      (progn (setq unread-command-events (listify-key-sequence keys))
             (call-interactively 'mafcmd-map)
             nil)
    (user-error t)))

(maf-step
  ;; Home: a formula with one free variable, mapped over a vector.
  (maf-push "[1, 2, 3]")
  (goto-char (point-max))
  (progn (setq unread-command-events (listify-key-sequence "x^2\r"))
         (call-interactively 'mafcmd-map))
  (cl-assert (string= (math-format-value
                       (maf--strip-encasing (calc-top 1 'full)))
                      "[1, 4, 9]"))
  (cl-assert (= (calc-stack-size) 1))
  (calc-pop (calc-stack-size))

  ;; $ inside the formula names the element, so the variable need not
  ;; be invented. Same reading as calc's own operator prompt.
  (maf-push "[1, 2, 3]")
  (goto-char (point-max))
  (progn (setq unread-command-events (listify-key-sequence "2 $ + 1\r"))
         (call-interactively 'mafcmd-map))
  (cl-assert (string= (math-format-value
                       (maf--strip-encasing (calc-top 1 'full)))
                      "[3, 5, 7]"))
  (calc-pop (calc-stack-size))

  ;; Input that names no element reads as an operation on it: a
  ;; leading operator applies with the element on the left, a bare
  ;; constant multiplies.
  (maf-push "[1, 2, 3]")
  (goto-char (point-max))
  (progn (setq unread-command-events (listify-key-sequence "+2\r"))
         (call-interactively 'mafcmd-map))
  (cl-assert (string= (math-format-value
                       (maf--strip-encasing (calc-top 1 'full)))
                      "[3, 4, 5]"))
  (calc-pop (calc-stack-size))

  ;; A leading minus subtracts — the scale-by-negative reading stays
  ;; spelled -2 x or -2 $.
  (maf-push "[1, 2, 3]")
  (goto-char (point-max))
  (progn (setq unread-command-events (listify-key-sequence "-2\r"))
         (call-interactively 'mafcmd-map))
  (cl-assert (string= (math-format-value
                       (maf--strip-encasing (calc-top 1 'full)))
                      "[-1, 0, 1]"))
  (calc-pop (calc-stack-size))

  ;; The operators that cannot even parse alone read the same way.
  (maf-push "[1, 2, 3]")
  (goto-char (point-max))
  (progn (setq unread-command-events (listify-key-sequence "^2\r"))
         (call-interactively 'mafcmd-map))
  (cl-assert (string= (math-format-value
                       (maf--strip-encasing (calc-top 1 'full)))
                      "[1, 4, 9]"))
  (calc-pop (calc-stack-size))

  (maf-push "[2, 4, 6]")
  (goto-char (point-max))
  (progn (setq unread-command-events (listify-key-sequence "/2\r"))
         (call-interactively 'mafcmd-map))
  (cl-assert (string= (math-format-value
                       (maf--strip-encasing (calc-top 1 'full)))
                      "[1, 2, 3]"))
  (calc-pop (calc-stack-size))

  ;; A bare constant multiplies.
  (maf-push "[1, 2, 3]")
  (goto-char (point-max))
  (progn (setq unread-command-events (listify-key-sequence "2\r"))
         (call-interactively 'mafcmd-map))
  (cl-assert (string= (math-format-value
                       (maf--strip-encasing (calc-top 1 'full)))
                      "[2, 4, 6]"))
  (calc-pop (calc-stack-size))

  ;; A trailing operator takes the element on the right: 2+ adds like
  ;; +2, but 2- subtracts the element from 2, and 2^ raises 2 to it.
  (maf-push "[1, 2, 3]")
  (goto-char (point-max))
  (progn (setq unread-command-events (listify-key-sequence "2+\r"))
         (call-interactively 'mafcmd-map))
  (cl-assert (string= (math-format-value
                       (maf--strip-encasing (calc-top 1 'full)))
                      "[3, 4, 5]"))
  (calc-pop (calc-stack-size))

  (maf-push "[1, 2, 3]")
  (goto-char (point-max))
  (progn (setq unread-command-events (listify-key-sequence "2-\r"))
         (call-interactively 'mafcmd-map))
  (cl-assert (string= (math-format-value
                       (maf--strip-encasing (calc-top 1 'full)))
                      "[1, 0, -1]"))
  (calc-pop (calc-stack-size))

  (maf-push "[1, 2, 3]")
  (goto-char (point-max))
  (progn (setq unread-command-events (listify-key-sequence "2^\r"))
         (call-interactively 'mafcmd-map))
  (cl-assert (string= (math-format-value
                       (maf--strip-encasing (calc-top 1 'full)))
                      "[2, 4, 8]"))
  (calc-pop (calc-stack-size))

  ;; A leading relation builds the comparison, element on the open
  ;; side. < is also how calc spells dates and lambdas, so the typed
  ;; operator must win over the reader's date guess...
  (maf-push "[1, -2, 3]")
  (goto-char (point-max))
  (progn (setq unread-command-events (listify-key-sequence "< 0\r"))
         (call-interactively 'mafcmd-map))
  (cl-assert (string= (math-format-value
                       (maf--strip-encasing (calc-top 1 'full)))
                      "[0, 1, 0]"))
  (calc-pop (calc-stack-size))

  (maf-push "[1, -2, 3]")
  (goto-char (point-max))
  (progn (setq unread-command-events (listify-key-sequence "== 0\r"))
         (call-interactively 'mafcmd-map))
  (cl-assert (string= (math-format-value
                       (maf--strip-encasing (calc-top 1 'full)))
                      "[0, 0, 0]"))
  (calc-pop (calc-stack-size))

  ;; ...while a typed nameless function still reads as itself.
  (maf-push "[1, -2, 3]")
  (goto-char (point-max))
  (progn (setq unread-command-events (listify-key-sequence "<x : x^3>\r"))
         (call-interactively 'mafcmd-map))
  (cl-assert (string= (math-format-value
                       (maf--strip-encasing (calc-top 1 'full)))
                      "[1, -8, 27]"))
  (calc-pop (calc-stack-size))

  ;; A lone - negates.
  (maf-push "[1, 2, 3]")
  (goto-char (point-max))
  (progn (setq unread-command-events (listify-key-sequence "-\r"))
         (call-interactively 'mafcmd-map))
  (cl-assert (string= (math-format-value
                       (maf--strip-encasing (calc-top 1 'full)))
                      "[-1, -2, -3]"))
  (calc-pop (calc-stack-size))

  ;; -x names the element, so it keeps its old reading — negation, not
  ;; $ - x. The sugar only claims input that would otherwise refuse.
  (maf-push "[1, 2, 3]")
  (goto-char (point-max))
  (progn (setq unread-command-events (listify-key-sequence "-x\r"))
         (call-interactively 'mafcmd-map))
  (cl-assert (string= (math-format-value
                       (maf--strip-encasing (calc-top 1 'full)))
                      "[-1, -2, -3]"))
  (calc-pop (calc-stack-size))

  ;; A bare name calc knows as a function is the call it names.
  (maf-push "[-1, 2, -3]")
  (goto-char (point-max))
  (progn (setq unread-command-events (listify-key-sequence "abs\r"))
         (call-interactively 'mafcmd-map))
  (cl-assert (string= (math-format-value
                       (maf--strip-encasing (calc-top 1 'full)))
                      "[1, 2, 3]"))
  (calc-pop (calc-stack-size))

  ;; A known function must be callable with one argument. Merely having
  ;; a calcFunc definition is not enough: gcd requires two operands and
  ;; must not leave malformed unary calls in the mapped vector.
  (maf-push "[6, 9]")
  (goto-char (point-max))
  (let ((message
         (condition-case err
             (progn
               (setq unread-command-events (listify-key-sequence "gcd\r"))
               (call-interactively 'mafcmd-map)
               nil)
           (user-error (error-message-string err)))))
    (cl-assert (string-match-p "does not take one argument" message)))
  (cl-assert (string= (math-format-value
                       (maf--strip-encasing (calc-top 1 'full)))
                      "[6, 9]"))
  (cl-assert (= (calc-stack-size) 1))
  (calc-pop (calc-stack-size))

  ;; A plain expression is one element: the formula takes it whole.
  (maf-push "a + b")
  (goto-char (point-max))
  (progn (setq unread-command-events (listify-key-sequence "x^2\r"))
         (call-interactively 'mafcmd-map))
  (cl-assert (string= (math-format-value
                       (maf--strip-encasing (calc-top 1 'full)))
                      "(a + b)^2"))
  (calc-pop (calc-stack-size))

  ;; A matrix maps over its individual elements, not its rows.
  (maf-push "[[1, 2], [3, 4]]")
  (goto-char (point-max))
  (progn (setq unread-command-events (listify-key-sequence "x^2\r"))
         (call-interactively 'mafcmd-map))
  ;; Compared structurally: a matrix's own rendering is multi-line.
  (cl-assert (equal (maf--strip-encasing (calc-top 1 'full))
                    '(vec (vec 1 4) (vec 9 16))))
  (calc-pop (calc-stack-size))

  ;; An equation maps side by side. The formula's variable is its own
  ;; parameter, not a name shared with the subject: the x in the
  ;; subject is part of the element, not a second thing substituted.
  (maf-push "y = x + 1")
  (goto-char (point-max))
  (progn (setq unread-command-events (listify-key-sequence "x^2\r"))
         (call-interactively 'mafcmd-map))
  (cl-assert (string= (math-format-value
                       (maf--strip-encasing (calc-top 1 'full)))
                      "y^2 = (x + 1)^2"))
  (calc-pop (calc-stack-size))

  ;; An inequality is refused: nothing here can tell whether the typed
  ;; formula increases or decreases, and the direction turns on it.
  (maf-push "a < b")
  (goto-char (point-max))
  (cl-assert (maf-test-map-refused "-2 x\r"))
  (cl-assert (string= (math-format-value
                       (maf--strip-encasing (calc-top 1 'full)))
                      "a < b"))
  (cl-assert (= (calc-stack-size) 1))
  (calc-pop (calc-stack-size))

  ;; I maps it and reverses the direction — the way to say the formula
  ;; decreases. Calc's own a M would return the false -2 a < -2 b here.
  (maf-push "a < b")
  (goto-char (point-max))
  (progn (setq calc-inverse-flag t)
         (setq unread-command-events (listify-key-sequence "-2 x\r"))
         (call-interactively 'mafcmd-map))
  (cl-assert (string= (math-format-value
                       (maf--strip-encasing (calc-top 1 'full)))
                      "-2 a > -2 b"))
  (cl-assert (not calc-inverse-flag))
  (calc-pop (calc-stack-size))

  ;; An = under I maps as it does without: there is no direction to turn.
  (maf-push "y = x")
  (goto-char (point-max))
  (progn (setq calc-inverse-flag t)
         (setq unread-command-events (listify-key-sequence "x^2\r"))
         (call-interactively 'mafcmd-map))
  (cl-assert (string= (math-format-value
                       (maf--strip-encasing (calc-top 1 'full)))
                      "y^2 = x^2"))
  (calc-pop (calc-stack-size))

  ;; A != is refused either way: it survives only a one-to-one formula.
  (maf-push "a != b")
  (goto-char (point-max))
  (cl-assert (maf-test-map-refused "x^2\r"))
  (cl-assert (string= (math-format-value
                       (maf--strip-encasing (calc-top 1 'full)))
                      "a != b"))
  (calc-pop (calc-stack-size))

  ;; Point inside the formula does not narrow (:scope explicit): the
  ;; whole entry is the subject wherever point sits on its line, and a
  ;; non-vector entry takes the formula whole.
  (maf-push "[1, 2] + k")
  (progn (calc-cursor-stack-index 1) (end-of-line) (search-backward "["))
  (progn (setq unread-command-events (listify-key-sequence "x^2\r"))
         (call-interactively 'mafcmd-map))
  (cl-assert (string= (math-format-value
                       (maf--strip-encasing (calc-top 1 'full)))
                      "(k + [1, 2])^2"))
  (calc-pop (calc-stack-size))

  ;; A calc selection is a deliberate gesture and still narrows: the
  ;; selected vector maps in place, what surrounds it untouched.
  (maf-push "[1, 2] + k")
  (progn (calc-cursor-stack-index 1) (end-of-line) (search-backward "[")
         (execute-kbd-macro (kbd "j s")))
  (progn (setq unread-command-events (listify-key-sequence "x^2\r"))
         (call-interactively 'mafcmd-map))
  (cl-assert (string= (math-format-value
                       (maf--strip-encasing (calc-top 1 'full)))
                      "[1, 4] + k"))
  (progn (maf-clear-selections))
  (calc-pop (calc-stack-size))

  ;; Several variables do not say which one is the element.
  (maf-push "[1, 2]")
  (goto-char (point-max))
  (cl-assert (maf-test-map-refused "a x + b\r"))
  (cl-assert (string= (math-format-value
                       (maf--strip-encasing (calc-top 1 'full)))
                      "[1, 2]"))
  (calc-pop (calc-stack-size))

  ;; A constant with no variable used to refuse; it now multiplies at
  ;; the prompt (the sugar above). The stack form still refuses one —
  ;; a stack entry has no typed spelling to read an operator off.
  (maf-push "[1, 2]")
  (maf-push "7")
  (goto-char (point-max))
  (let ((message
         (condition-case err
             (progn (call-interactively 'mafcmd-map-stack) nil)
           (user-error (error-message-string err)))))
    (cl-assert (string-match-p "no variable" message)))
  (calc-pop (calc-stack-size))

  ;; $ (mafcmd-map-stack): the entry above the subject is the formula,
  ;; consumed on commit.
  (maf-push "[1, 2, 3]")
  (maf-push "x^2")
  (goto-char (point-max))
  (call-interactively 'mafcmd-map-stack)
  (cl-assert (string= (math-format-value
                       (maf--strip-encasing (calc-top 1 'full)))
                      "[1, 4, 9]"))
  (cl-assert (= (calc-stack-size) 1))
  (calc-pop (calc-stack-size))

  ;; A lone $ at $'s prompt is the same gesture, reached from the
  ;; prompt instead of the key.
  (maf-push "[1, 2, 3]")
  (maf-push "2 x")
  (goto-char (point-max))
  (progn (setq unread-command-events (listify-key-sequence "$\r"))
         (call-interactively 'mafcmd-map))
  (cl-assert (string= (math-format-value
                       (maf--strip-encasing (calc-top 1 'full)))
                      "[2, 4, 6]"))
  (cl-assert (= (calc-stack-size) 1))
  (calc-pop (calc-stack-size))

  ;; A nameless function on the stack carries its own parameter.
  (maf-push "[1, 2, 3]")
  (maf-push "<x : x + 10>")
  (goto-char (point-max))
  (call-interactively 'mafcmd-map-stack)
  (cl-assert (string= (math-format-value
                       (maf--strip-encasing (calc-top 1 'full)))
                      "[11, 12, 13]"))
  (calc-pop (calc-stack-size))

  ;; Applying a nameless function respects parameters bound by a nested
  ;; one. The inner x shadows the mapper's x and stays a variable rather
  ;; than being replaced with the mapped element.
  (maf-push "2")
  (maf-push "<x : <x : x + 1>>")
  (goto-char (point-max))
  (call-interactively 'mafcmd-map-stack)
  (cl-assert (string= (math-format-value
                       (maf--strip-encasing (calc-top 1 'full)))
                      "<x : x + 1>"))
  (cl-assert (= (calc-stack-size) 1))
  (calc-pop (calc-stack-size))

  ;; The stack form keeps the subject's own resolution: point on the
  ;; formula (the top) shifts the subject down to the entry below, as
  ;; it does for any binary command.
  (maf-push "[1, 2]")
  (maf-push "x^3")
  (progn (calc-cursor-stack-index 1) (end-of-line))
  (call-interactively 'mafcmd-map-stack)
  (cl-assert (string= (math-format-value
                       (maf--strip-encasing (calc-top 1 'full)))
                      "[1, 8]"))
  (cl-assert (= (calc-stack-size) 1))
  (calc-pop (calc-stack-size))

  ;; With keep-args both operands stay and the result lands on top.
  (maf-push "[1, 2]")
  (maf-push "x^2")
  (goto-char (point-max))
  (progn (setq calc-keep-args-flag t)
         (call-interactively 'mafcmd-map-stack))
  (cl-assert (string= (math-format-value
                       (maf--strip-encasing (calc-top 1 'full)))
                      "[1, 4]"))
  (cl-assert (= (calc-stack-size) 3))
  (calc-pop (calc-stack-size)))
