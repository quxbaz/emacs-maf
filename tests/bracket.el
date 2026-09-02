;; mafcmd-bracket surrounds the resolved target with vector brackets.
;;
;; The one-operand counterpart of the concatenation on |: what point
;; names comes back as the single element of a new vector, unchanged and
;; unsimplified.

(maf-step
  ;; Home: the top entry goes inside the brackets.
  (maf-push "x")
  (call-interactively 'mafcmd-bracket)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "[x]"))
  (cl-assert (equal (calc-top 1 'full) '(vec (var x var-x))))
  (calc-pop (calc-stack-size))

  ;; The entry's own line, margin included: the whole entry is the
  ;; target, not the node the end of the line sits beside.
  (maf-push "x + 1")
  (progn (calc-cursor-stack-index 1) (end-of-line)
         (call-interactively 'mafcmd-bracket))
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "[x + 1]"))
  (calc-pop (calc-stack-size))

  ;; Sub-formula: only the node at point is bracketed, in place. The
  ;; ":  " search steps past the stack-level label, whose own digit
  ;; would otherwise be what the search finds.
  (maf-push "x + 1")
  (progn (calc-cursor-stack-index 1)
         (search-forward ":  ") (search-forward "1") (backward-char 1)
         (call-interactively 'mafcmd-bracket))
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "x + [1]"))
  (calc-pop (calc-stack-size))

  ;; Nothing is computed on the way in: two numbers that would fold
  ;; together stay as they stood, the bracketed one included.
  (maf-push "2 + 3")
  (progn (calc-cursor-stack-index 1)
         (search-forward ":  ") (search-forward "3") (backward-char 1)
         (call-interactively 'mafcmd-bracket))
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "2 + [3]"))
  (calc-pop (calc-stack-size))

  ;; A vector nests inside the new one rather than splicing into it —
  ;; the brackets go around what was there, whatever it was.
  (maf-push "[a, b]")
  (call-interactively 'mafcmd-bracket)
  (cl-assert (equal (calc-top 1 'full)
                    '(vec (vec (var a var-a) (var b var-b)))))
  (calc-pop (calc-stack-size))

  ;; A relation is one element, not a subject to bracket side by side:
  ;; the command takes :map -1, as the | family does, so an equation
  ;; comes back whole within the brackets rather than as [x] = [1].
  (maf-push "x = 1")
  (call-interactively 'mafcmd-bracket)
  (cl-assert (equal (calc-top 1 'full)
                    '(vec (calcFunc-eq (var x var-x) 1))))
  (calc-pop (calc-stack-size))

  ;; Point inside a relation still names its sub-formula, so only that
  ;; part is bracketed.
  (maf-push "x = y + 1")
  (progn (calc-cursor-stack-index 1)
         (search-forward ":  ") (search-forward "y") (backward-char 1)
         (call-interactively 'mafcmd-bracket))
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "x = [y] + 1"))
  (calc-pop (calc-stack-size))

  ;; A calc selection is the target as it stands, and the bracketed
  ;; result stays selected.
  (maf-push "a + b c")
  (progn (calc-cursor-stack-index 1)
         (search-forward ":  ") (search-forward "b") (backward-char 1)
         (call-interactively 'calc-select-here)
         (call-interactively 'mafcmd-bracket))
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "a + [b] c"))
  (cl-assert (equal (calc-top-selected 1) '(vec (var b var-b))))
  (progn (call-interactively 'calc-clear-selections)
         (calc-pop (calc-stack-size)))

  ;; A region brackets the run it covers, which need not be a node calc
  ;; could select on its own.
  (maf-push "a + b + c")
  (progn (calc-cursor-stack-index 1)
         (search-forward "b + c" (line-end-position))
         (goto-char (match-beginning 0))
         (push-mark (match-end 0) t t)
         (call-interactively 'mafcmd-bracket))
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "a + [b + c]"))
  (calc-pop (calc-stack-size))

  ;; An entry below the top is bracketed where it sits.
  (maf-push "u + v")
  (maf-push "w")
  (progn (calc-cursor-stack-index 2) (end-of-line)
         (call-interactively 'mafcmd-bracket))
  (cl-assert (string= (math-format-value (calc-top 2 'full)) "[u + v]"))
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "w"))
  (calc-pop (calc-stack-size))

  ;; Keep-args leaves the original standing and pushes the bracketed
  ;; copy above it.
  (maf-push "x")
  (progn (call-interactively 'calc-keep-args)
         (call-interactively 'mafcmd-bracket))
  (cl-assert (= (calc-stack-size) 2))
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "[x]"))
  (cl-assert (string= (math-format-value (calc-top 2 'full)) "x"))
  (calc-pop (calc-stack-size))

  ;; The binding: C-M-o on the top entry at home.
  (maf-push "x + 1")
  (progn (calc-cursor-stack-index 0)
         (execute-kbd-macro (kbd "C-M-o")) nil)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "[x + 1]"))
  (calc-pop (calc-stack-size))

  ;; And the same key on a sub-formula.
  (maf-push "x + 1")
  (progn (calc-cursor-stack-index 1)
         (search-forward ":  ") (search-forward "1") (backward-char 1)
         (execute-kbd-macro (kbd "C-M-o")) nil)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "x + [1]"))
  (calc-pop (calc-stack-size))

  ;; Unpacking is the way back out: the one-element vector peels to its
  ;; element, so the pair round-trips.
  (maf-push "x + 1")
  (call-interactively 'mafcmd-bracket)
  (call-interactively 'mafcmd-unpack)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "x + 1"))
  (cl-assert (= (calc-stack-size) 1))
  (calc-pop (calc-stack-size))

  ;; With nothing on the stack there is no target, and the command
  ;; signals rather than pushing an empty vector.
  (cl-assert (eq 'caught
                 (condition-case nil
                     (call-interactively 'mafcmd-bracket)
                   (error 'caught)))))
