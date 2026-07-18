(maf-step
  ;; Home: the top two entries join, upper line as lhs.
  (calc-push (math-read-expr "x"))
  (calc-push (math-read-expr "y"))
  (progn (goto-char (point-max)) nil)
  (call-interactively 'maf-equal-to)
  (cl-assert (= (calc-stack-size) 1))
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "x = y"))
  (calc-pop (calc-stack-size))

  ;; Structure survives: no side is simplified or evaluated.
  (calc-push (math-read-expr "2 (3 + x)"))
  (calc-push (math-read-expr "y"))
  (call-interactively 'maf-equal-to)
  (cl-assert (eq (car-safe (nth 1 (calc-top 1 'full))) '*))
  (calc-pop (calc-stack-size))
  (calc-push 3)
  (calc-push 3)
  (call-interactively 'maf-equal-to)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "3 = 3"))
  (calc-pop (calc-stack-size))

  ;; Entry: point on an entry pairs it with the one above on screen,
  ;; entry at point as the right side; the rest of the stack is
  ;; untouched and point follows the equation.
  (calc-push (math-read-expr "a"))
  (calc-push (math-read-expr "b"))
  (calc-push (math-read-expr "c"))
  (calc-push (math-read-expr "d"))
  (progn (calc-cursor-stack-index 2) nil)
  (call-interactively 'maf-equal-to)
  (cl-assert (= (calc-stack-size) 3))
  (cl-assert (string= (math-format-value (calc-top 3 'full)) "a"))
  (cl-assert (string= (math-format-value (calc-top 2 'full)) "b = c"))
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "d"))
  (cl-assert (string-match-p "b = c" (buffer-substring (line-beginning-position)
                                                       (line-end-position))))
  (cl-assert (eolp))
  (calc-pop (calc-stack-size))

  ;; Point on the top entry (level 1) pairs it with the line above.
  (calc-push (math-read-expr "a"))
  (calc-push (math-read-expr "b"))
  (progn (calc-cursor-stack-index 1) nil)
  (call-interactively 'maf-equal-to)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "a = b"))
  (calc-pop (calc-stack-size))

  ;; Point on the deepest entry has no upper neighbor: the pair shifts
  ;; down to the entry below, same equation as from the other side.
  (calc-push (math-read-expr "a"))
  (calc-push (math-read-expr "b"))
  (progn (calc-cursor-stack-index 2) nil)
  (call-interactively 'maf-equal-to)
  (cl-assert (= (calc-stack-size) 1))
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "a = b"))
  (calc-pop (calc-stack-size))

  ;; Inverse flag builds != instead.
  (calc-push (math-read-expr "x"))
  (calc-push (math-read-expr "y"))
  (call-interactively 'calc-inverse)
  (call-interactively 'maf-equal-to)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "x != y"))
  (calc-pop (calc-stack-size))

  ;; Keep-args: originals stay put, the equation lands on top.
  (calc-push (math-read-expr "x"))
  (calc-push (math-read-expr "y"))
  (call-interactively 'calc-keep-args)
  (call-interactively 'maf-equal-to)
  (cl-assert (= (calc-stack-size) 3))
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "x = y"))
  (cl-assert (string= (math-format-value (calc-top 2 'full)) "y"))
  (calc-pop (calc-stack-size))

  ;; Fewer than two entries: signals instead of guessing.
  (calc-push 1)
  (cl-assert (condition-case nil
                 (progn (call-interactively 'maf-equal-to) nil)
               (error t))))
