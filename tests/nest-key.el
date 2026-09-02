;; M-| runs mafcmd-vnest, the H | variant of the concatenation on |,
;; from its own key.
;;
;; | splices vector operands into one flat vector; the nest keeps each
;; operand whole, brackets and all, as one element of a two-element
;; vector. Both keys are the meta pair on |: the join that merges and
;; the join that preserves.

(maf-step
  (cl-assert (eq (key-binding (kbd "M-|")) 'mafcmd-vnest))
  (cl-assert (eq (key-binding (kbd "|")) 'mafcmd-vconcat))

  ;; Two vectors: | flattens them, M-| nests them.
  (maf-push "[x, y]")
  (maf-push "[a, b]")
  (progn (execute-kbd-macro (kbd "|")) nil)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "[x, y, a, b]"))
  (calc-pop (calc-stack-size))

  (maf-push "[x, y]")
  (maf-push "[a, b]")
  (progn (execute-kbd-macro (kbd "M-|")) nil)
  (cl-assert (equal (calc-top 1 'full)
                    '(vec (vec (var x var-x) (var y var-y))
                          (vec (var a var-a) (var b var-b)))))
  (cl-assert (= (calc-stack-size) 1))
  (calc-pop (calc-stack-size))

  ;; The key and the flag route agree.
  (maf-push "[x, y]")
  (maf-push "[a, b]")
  (progn (execute-kbd-macro (kbd "H |")) nil)
  (cl-assert (equal (calc-top 1 'full)
                    '(vec (vec (var x var-x) (var y var-y))
                          (vec (var a var-a) (var b var-b)))))
  (calc-pop (calc-stack-size))

  ;; Scalars nest the same as they concatenate: one element each.
  (maf-push "x")
  (maf-push "1")
  (progn (execute-kbd-macro (kbd "M-|")) nil)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "[x, 1]"))
  (calc-pop (calc-stack-size)))
