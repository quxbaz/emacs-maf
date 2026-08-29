;; mafcmd-collect-terms (j c): collect every term of a variable on the side of
;; the relation at point, every other term moving to the other side.
;; Both moves are additions and subtractions on both sides, so every
;; relation keeps its direction. The variable is read from the
;; minibuffer as mafcmd-solve-for reads it; `maf-with-input' stands in
;; for the typing, as in tests/solve-for.el.

(defmacro maf-with-input (input &rest body)
  "Run BODY with the collect prompt answered by INPUT (nil = bare RET)."
  (declare (indent 1))
  `(cl-letf (((symbol-function 'read-string)
              (lambda (_prompt &optional _init _hist default &rest _)
                (or ,input default ""))))
     ,@body))

(defun collect-at (needle &optional back)
  "Put point on NEEDLE in the stack buffer, BACK chars before its end."
  (goto-char (point-min))
  (search-forward needle)
  (backward-char (or back 1)))

(maf-step
  ;; The key is claimed.
  (cl-assert (eq (key-binding (kbd "j c")) 'mafcmd-collect-terms))

  ;; Point in the left side: the x terms collect there — x from the
  ;; right crosses in, 2 k crosses out — and like terms fold.
  (maf-push "x + 2 k = x^2 - x + 3")
  (collect-at "x +" 3)
  (maf-with-input nil (call-interactively 'mafcmd-collect-terms))
  (cl-assert (string= (math-format-value (calc-top 1 'full))
                      "-x^2 + 2 x = -2 k + 3"))
  (calc-pop (calc-stack-size))

  ;; Point in the right side: the same terms collect there instead,
  ;; the relation's sides kept in place.
  (maf-push "x + 2 k = x^2 - x + 3")
  (collect-at "x^2" 3)
  (maf-with-input nil (call-interactively 'mafcmd-collect-terms))
  (cl-assert (string= (math-format-value (calc-top 1 'full))
                      "2 k - 3 = x^2 - 2 x"))
  (calc-pop (calc-stack-size))

  ;; Home reads as the left side.
  (maf-push "x + 2 k = x^2 - x + 3")
  (goto-char (point-max))
  (maf-with-input nil (call-interactively 'mafcmd-collect-terms))
  (cl-assert (string= (math-format-value (calc-top 1 'full))
                      "-x^2 + 2 x = -2 k + 3"))
  (calc-pop (calc-stack-size))

  ;; An inequality keeps its direction: the moves are additive.
  (maf-push "a x <= b - x")
  (collect-at "a x" 3)
  (maf-with-input nil (call-interactively 'mafcmd-collect-terms))
  (cl-assert (string= (math-format-value (calc-top 1 'full))
                      "a x + x <= b"))
  (calc-pop (calc-stack-size))

  ;; Several names collect the terms of them all.
  (maf-push "x + y + k = 3 - y")
  (collect-at "x +" 3)
  (maf-with-input "x y" (call-interactively 'mafcmd-collect-terms))
  (cl-assert (string= (math-format-value (calc-top 1 'full))
                      "x + 2 y = -k + 3"))
  (calc-pop (calc-stack-size))

  ;; Every term containing the variable: the emptied side becomes 0.
  (maf-push "x y = k y")
  (collect-at "k y" 3)
  (maf-with-input "y" (call-interactively 'mafcmd-collect-terms))
  (cl-assert (string= (math-format-value (calc-top 1 'full))
                      "0 = k y - x y"))
  (calc-pop (calc-stack-size))

  ;; No term contains the variable: unchanged.
  (maf-push "x + 2 k = 3")
  (collect-at "2 k" 3)
  (maf-with-input "z" (call-interactively 'mafcmd-collect-terms))
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "x + 2 k = 3"))
  (calc-pop (calc-stack-size))

  ;; A bare expression has no sides: unchanged.
  (maf-push "x + 2 k")
  (collect-at "2 k" 3)
  (maf-with-input nil (call-interactively 'mafcmd-collect-terms))
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "x + 2 k"))
  (calc-pop (calc-stack-size))

  ;; The sums are rebuilt under default simplifications whatever the
  ;; session's simplify mode: under none the like terms still fold.
  (maf-push "x + 2 k = x^2 - x + 3")
  (collect-at "x +" 3)
  (let ((calc-simplify-mode 'none))
    (maf-with-input nil (call-interactively 'mafcmd-collect-terms)))
  (cl-assert (string= (math-format-value (calc-top 1 'full))
                      "-x^2 + 2 x = -2 k + 3"))
  (calc-pop (calc-stack-size))

  ;; The key route, real keys through the prompt.
  (maf-push "x + 2 k = x^2 - x + 3")
  (collect-at "x +" 3)
  (let* ((buf (get-buffer "*Calculator*"))
         (win (get-buffer-window buf t)))
    (cl-assert win)
    (with-selected-window win
      (with-current-buffer buf
        (execute-kbd-macro (kbd "j c RET"))))
    nil)
  (cl-assert (string= (math-format-value (calc-top 1 'full))
                      "-x^2 + 2 x = -2 k + 3"))
  (calc-pop (calc-stack-size)))
