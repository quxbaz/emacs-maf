;; mafcmd-vint: set intersection of the resolved entry with the top of
;; stack, on both spellings calc gives a set — a vector of members and
;; an interval — and on the two mixed.
(maf-step
  ;; Vectors: members in both, in the resolved one's order.
  (maf-push "[1, 2, 3, 4, 5]")
  (maf-push "[4, 5, 6]")
  (goto-char (point-max))
  (call-interactively 'mafcmd-vint)
  (cl-assert (= (calc-stack-size) 1))
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "[4, 5]"))
  (calc-pop (calc-stack-size))

  ;; Nothing shared is the empty set, not an error.
  (maf-push "[1, 2]")
  (maf-push "[3, 4]")
  (goto-char (point-max))
  (call-interactively 'mafcmd-vint)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "[]"))
  (calc-pop (calc-stack-size))

  ;; Sets, not lists: repeats collapse and the answer comes sorted.
  (maf-push "[3, 1, 2, 2]")
  (maf-push "[2, 3, 3]")
  (goto-char (point-max))
  (call-interactively 'mafcmd-vint)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "[2, 3]"))
  (calc-pop (calc-stack-size))

  ;; A bare number is the one-member set.
  (maf-push "[1, 2, 3, 4, 5]")
  (maf-push "5")
  (goto-char (point-max))
  (call-interactively 'mafcmd-vint)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "[5]"))
  (calc-pop (calc-stack-size))

  ;; Intervals: the overlap, keeping each end's closedness.
  (maf-push "[1 .. 5]")
  (maf-push "[3 .. 8]")
  (goto-char (point-max))
  (call-interactively 'mafcmd-vint)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "[3 .. 5]"))
  (calc-pop (calc-stack-size))

  (maf-push "(1 .. 5)")
  (maf-push "(3 .. 8)")
  (goto-char (point-max))
  (call-interactively 'mafcmd-vint)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "(3 .. 5)"))
  (calc-pop (calc-stack-size))

  ;; Meeting only at an open end shares no point.
  (maf-push "(1 .. 5)")
  (maf-push "[5 .. 8]")
  (goto-char (point-max))
  (call-interactively 'mafcmd-vint)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "[]"))
  (calc-pop (calc-stack-size))

  (maf-push "(1 .. 3)")
  (maf-push "(5 .. 8)")
  (goto-char (point-max))
  (call-interactively 'mafcmd-vint)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "[]"))
  (calc-pop (calc-stack-size))

  ;; A set of intervals meets one interval piecewise.
  (maf-push "[(1 .. 3), (5 .. 9)]")
  (maf-push "[2 .. 6]")
  (goto-char (point-max))
  (call-interactively 'mafcmd-vint)
  (cl-assert (string= (math-format-value (calc-top 1 'full))
                      "[[2 .. 3), (5 .. 6]]"))
  (calc-pop (calc-stack-size))

  ;; Mixed: the members of the vector that fall inside the interval,
  ;; whichever side each is on. Open ends exclude the endpoints.
  (maf-push "(1 .. 5)")
  (maf-push "[1, 2, 3, 4, 5]")
  (goto-char (point-max))
  (call-interactively 'mafcmd-vint)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "[2, 3, 4]"))
  (calc-pop (calc-stack-size))

  (maf-push "[1, 2, 3, 4, 5]")
  (maf-push "(1 .. 5)")
  (goto-char (point-max))
  (call-interactively 'mafcmd-vint)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "[2, 3, 4]"))
  (calc-pop (calc-stack-size))

  ;; Closed ends keep them.
  (maf-push "[1, 2, 3, 4, 5]")
  (maf-push "[1 .. 5]")
  (goto-char (point-max))
  (call-interactively 'mafcmd-vint)
  (cl-assert (string= (math-format-value (calc-top 1 'full))
                      "[1, 2, 3, 4, 5]"))
  (calc-pop (calc-stack-size))

  ;; A member outside the interval drops; the rest stay.
  (maf-push "(1 .. 5)")
  (maf-push "[3, 7]")
  (goto-char (point-max))
  (call-interactively 'mafcmd-vint)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "[3]"))
  (calc-pop (calc-stack-size))

  ;; Non-integer members are tested against the interval like any other.
  (maf-push "[1.5, 2, 3]")
  (maf-push "(1 .. 2]")
  (goto-char (point-max))
  (call-interactively 'mafcmd-vint)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "[1.5, 2]"))
  (calc-pop (calc-stack-size))

  ;; Upstream: an infinite endpoint is not a constant calc's set code
  ;; accepts, so the call is left standing rather than evaluated.
  (maf-push "[1 .. inf)")
  (maf-push "(-inf .. 5]")
  (goto-char (point-max))
  (call-interactively 'mafcmd-vint)
  (cl-assert (string= (math-format-value (calc-top 1 'full))
                      "vint([1 .. inf), (-inf .. 5])"))
  (calc-pop (calc-stack-size))

  ;; The binding: v ^ at home, on each spelling.
  (cl-assert (eq (key-binding (kbd "v ^")) 'mafcmd-vint))
  (maf-push "[1, 2, 3, 4, 5]")
  (maf-push "[4, 5, 6]")
  (goto-char (point-max))
  (execute-kbd-macro (kbd "v ^"))
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "[4, 5]"))
  (calc-pop (calc-stack-size))

  (maf-push "(1 .. 5)")
  (maf-push "[3 .. 8]")
  (goto-char (point-max))
  (execute-kbd-macro (kbd "v ^"))
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "[3 .. 5)"))
  (calc-pop (calc-stack-size))

  ;; Contextual: from a deeper entry's line, that entry is the resolved
  ;; set and the top of stack the argument. The result lands where the
  ;; entry was, the argument is consumed, and the entry between is
  ;; untouched.
  (maf-push "(1 .. 5)")
  (maf-push "x")
  (maf-push "[3, 4, 5, 6]")
  (progn (calc-cursor-stack-index 3) (end-of-line)
         (call-interactively 'mafcmd-vint))
  (cl-assert (= (calc-stack-size) 2))
  (cl-assert (string= (math-format-value (calc-top 2 'full)) "[3, 4]"))
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "x"))
  (calc-pop (calc-stack-size))

  ;; And the same with the interval on top.
  (maf-push "[1, 2, 3, 4, 5]")
  (maf-push "x")
  (maf-push "[2 .. 4]")
  (progn (calc-cursor-stack-index 3) (end-of-line)
         (call-interactively 'mafcmd-vint))
  (cl-assert (= (calc-stack-size) 2))
  (cl-assert (string= (math-format-value (calc-top 2 'full)) "[2, 3, 4]"))
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "x"))
  (calc-pop (calc-stack-size)))
