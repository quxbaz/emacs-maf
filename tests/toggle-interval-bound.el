;; S-up and S-down on the stack retype the interval delimiter at point
;; (`mafcmd-toggle-op', its second reading). A step passes when it
;; raises no error.
;;
;; The contract: an interval's two delimiters are independent values,
;; so the bound point is at flips and the other stands — the mixed pair
;; this leaves is the notation working, not a pair left broken. Which
;; bound moves is read off point: either delimiter, or the side of the
;; `..' point is on. Point elsewhere names an operand or the entry, and
;; the interval commits unchanged. The operator reading is untouched:
;; a `+' inside an interval still toggles to `-'.

(maf-step
  ;; The keys the gesture is reached by, the same pair the editplus
  ;; module uses inside an edit session (tests/edit-toggle-brackets.el).
  (cl-assert (eq (lookup-key maf-mode-map (kbd "S-<up>")) 'mafcmd-toggle-op))
  (cl-assert (eq (lookup-key maf-mode-map (kbd "S-<down>")) 'mafcmd-toggle-op))

  ;; The motivating case: point before the closing delimiter closes
  ;; that end, the open lower end left as it was.
  (maf-push "(-inf .. 3)")
  (progn (goto-char (point-min)) (search-forward ")") (backward-char 1))
  (execute-kbd-macro (kbd "S-<up>"))
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "(-inf .. 3]"))
  ;; Point keeps the delimiter as it changes, so the gesture repeats
  ;; from where it left off and undoes itself.
  (cl-assert (eq (char-after) ?\]))
  (execute-kbd-macro (kbd "S-<down>"))
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "(-inf .. 3)"))
  (cl-assert (eq (char-after) ?\)))
  (calc-pop (calc-stack-size))

  ;; The opening delimiter moves the lower bound alone.
  (maf-push "[2 .. 3)")
  (progn (goto-char (point-min)) (search-forward "[") (backward-char 1))
  (execute-kbd-macro (kbd "S-<up>"))
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "(2 .. 3)"))
  (calc-pop (calc-stack-size))

  ;; The dots divide the two: up to their first character point is at
  ;; the lower bound, from there on at the upper.
  (maf-push "[2 .. 3)")
  (progn (goto-char (point-min)) (search-forward " ..") (backward-char 3))
  (execute-kbd-macro (kbd "S-<up>"))
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "(2 .. 3)"))
  (calc-pop (calc-stack-size))

  (maf-push "[2 .. 3)")
  (progn (goto-char (point-min)) (search-forward "..") (backward-char 1))
  (execute-kbd-macro (kbd "S-<up>"))
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "[2 .. 3]"))
  (calc-pop (calc-stack-size))

  ;; An operand names no bound: the interval commits unchanged, as any
  ;; atom does under this command.
  (maf-push "[2 .. 3)")
  (progn (goto-char (point-min)) (search-forward "3") (backward-char 1))
  (execute-kbd-macro (kbd "S-<up>"))
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "[2 .. 3)"))
  ;; And neither does the entry taken whole — at its margin or at home,
  ;; point is outside the rendering with no delimiter to have meant.
  (progn (goto-char (point-min)))
  (execute-kbd-macro (kbd "S-<up>"))
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "[2 .. 3)"))
  (progn (goto-char (point-max)))
  (execute-kbd-macro (kbd "S-<up>"))
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "[2 .. 3)"))
  (calc-pop (calc-stack-size))

  ;; The innermost interval is the one point is in: a set of intervals
  ;; flips the one whose delimiter point is on, the outer vector's own
  ;; brackets untouched.
  (maf-push "[[1 .. 2), [3 .. 4]]")
  (progn (goto-char (point-min)) (search-forward ")") (backward-char 1))
  (execute-kbd-macro (kbd "S-<up>"))
  (cl-assert (string= (math-format-value (calc-top 1 'full))
                      "[[1 .. 2], [3 .. 4]]"))
  (calc-pop (calc-stack-size))

  ;; Inside a relation the bound still moves per point, the relation
  ;; itself left alone (the command is :map -1, so no per-side run).
  (maf-push "x = [2 .. 3)")
  (progn (goto-char (point-min)) (search-forward ")") (backward-char 1))
  (execute-kbd-macro (kbd "S-<up>"))
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "x = [2 .. 3]"))
  ;; From the relation operator the operator reading answers instead.
  (progn (goto-char (point-min)) (search-forward "=") (backward-char 1))
  (execute-kbd-macro (kbd "S-<up>"))
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "x != [2 .. 3]"))
  (calc-pop (calc-stack-size))

  ;; The operator reading survives inside an interval: point on the +
  ;; names the sum, not the bound around it.
  (maf-push "[x + 1 .. 3]")
  (progn (goto-char (point-min)) (search-forward "+") (backward-char 1))
  (execute-kbd-macro (kbd "S-<up>"))
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "[x - 1 .. 3]"))
  (calc-pop (calc-stack-size))

  ;; A closed infinite bound is calc's own reading of `[-inf', which it
  ;; both reads and prints, so the toggle offers it rather than
  ;; refusing on the entry's behalf.
  (maf-push "(-inf .. 3)")
  (progn (goto-char (point-min)) (search-forward "(") (backward-char 1))
  (execute-kbd-macro (kbd "S-<up>"))
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "[-inf .. 3)"))
  (calc-pop (calc-stack-size))

  ;; The structural contract of the operator reading holds here too:
  ;; the mask alone changes, the endpoints carried over untouched and
  ;; nothing evaluated. They are compared by value, not by `equal':
  ;; preparing a selection encases an entry's atoms in place, so the 2
  ;; the stack holds afterwards is calc's (cplx 2 0) — upstream's doing
  ;; on any subexpr commit, operator reading included
  ;; (docs/memory/calc-selection-quirks.md).
  (maf-push "[2 .. 3)")
  (progn (goto-char (point-min)) (search-forward ")") (backward-char 1))
  (execute-kbd-macro (kbd "S-<up>"))
  (let ((iv (calc-top 1 'full)))
    (cl-assert (eq (car iv) 'intv))
    (cl-assert (eq (nth 1 iv) 3))
    (cl-assert (math-equal (nth 2 iv) 2))
    (cl-assert (math-equal (nth 3 iv) 3)))
  (calc-pop (calc-stack-size))

  (cl-assert (= (calc-stack-size) 0)))
