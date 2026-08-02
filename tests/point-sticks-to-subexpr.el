;; Point is maf's target selector, so on the part targets it follows the
;; node the command rewrote: after 2 / on the 14 of 6 x + 14, point is on
;; the 7 that took the slot, not on the column the 14's last digit
;; happened to occupy. Without it a chained command (2 / then 1 +)
;; silently resolves a different node.
;;
;; The whole-entry targets keep their positional restore, as do the two
;; part-target cases that opt out (keep-args, :widen) — see
;; `maf--point-stick-p'. Point on a structural glyph of the target still
;; anchors there first (tests/point-anchor-at-operator.el).

(maf-defcmd maf-square (expr _arg commit)
  "Square command."
  :arity unary
  :prefix "sqr"
  (commit (calcFunc-mul expr expr)))

(maf-defcmd maf-div (expr arg commit)
  "Division command."
  :arity binary
  :prefix "div"
  (commit (math-normalize (calcFunc-div expr arg))))

(defun maf-test--sum-p (expr)
  "Return t when EXPR is a sum. The `:widen' predicate below."
  (eq (car-safe expr) '+))

(maf-defcmd maf-widen-square (expr _arg commit)
  "Square the innermost sum around point."
  :arity unary
  :prefix "wsqr"
  :widen maf-test--sum-p
  (commit (calcFunc-mul expr expr)))

(maf-step
  ;; The motivating case: binary on an operand of the target. The arg
  ;; entry is consumed and the node narrows, so the old column lands one
  ;; past the result; point is on the result instead.
  (maf-push "6 x + 14")
  (calc-push 2)
  (progn (calc-cursor-stack-index 2)
         (search-forward "14" (line-end-position))
         (backward-char 1))
  (call-interactively 'maf-div)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "6 x + 7"))
  (cl-assert (looking-at "7$"))
  (calc-pop (calc-stack-size))

  ;; Unary, with the node growing under point: the column that held the
  ;; 4 of 14 now holds the 9 of 196, and point is on the 1.
  (maf-push "6 x + 14")
  (progn (calc-cursor-stack-index 1)
         (search-forward "14" (line-end-position))
         (backward-char 1))
  (call-interactively 'maf-square)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "6 x + 196"))
  (cl-assert (looking-at "196$"))
  (calc-pop (calc-stack-size))

  ;; An atom replaced by a compound: point lands on the start of what
  ;; arrived, not inside it.
  (maf-push "6 x + 12")
  (progn (calc-cursor-stack-index 1)
         (search-forward "x" (line-end-position))
         (backward-char 1))
  (call-interactively 'maf-square)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "6 x^2 + 12"))
  (cl-assert (looking-at "x\\^2"))
  (calc-pop (calc-stack-size))

  ;; Selection target: the same, with the slot named by a calc selection
  ;; rather than by point. The result stays selected and point sits on
  ;; it.
  (maf-push "6 x + 14")
  (calc-push 2)
  (progn (calc-cursor-stack-index 2)
         (search-forward "14" (line-end-position))
         (backward-char 1)
         (call-interactively 'calc-select-here))
  (call-interactively 'maf-div)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "6 x + 7"))
  (cl-assert (looking-at "7$"))
  (calc-clear-selections)
  (calc-pop (calc-stack-size))

  ;; Region target: point follows the run's replacement, wherever the
  ;; rebuilt chain puts it.
  (maf-push "x^2 (x+3) + 4 x + 12")
  (progn (calc-cursor-stack-index 1)
         (search-forward "4 x + 12" (line-end-position))
         (goto-char (match-beginning 0))
         (push-mark (match-end 0) t t)
         (call-interactively 'mafcmd-factor-gcd))
  (cl-assert (string= (math-format-value (calc-top 1 'full))
                      "x^2 (x + 3) + 4 (x + 3)"))
  (cl-assert (looking-at (concat (regexp-quote "4 (x + 3)") "$")))
  (calc-pop (calc-stack-size))

  ;; A structural glyph of the target still wins over the node's start:
  ;; commuting from the + of 6 x + 12 keeps point on the +, where
  ;; sticking would have moved it to the 1 of the leading 12.
  (maf-push "6 x + 12")
  (progn (calc-cursor-stack-index 1)
         (search-forward "+" (line-end-position))
         (backward-char 1))
  (call-interactively 'mafcmd-commute)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "12 + 6 x"))
  (cl-assert (eq (char-after) ?+))
  (calc-pop (calc-stack-size))

  ;; keep-args opts out: the originals are untouched and the result is a
  ;; new entry, so the entry under point is still the one the user was
  ;; reading — point stays on its 4.
  (maf-push "6 x + 14")
  (calc-push 2)
  (progn (calc-cursor-stack-index 2)
         (search-forward "14" (line-end-position))
         (backward-char 1))
  (call-interactively 'calc-keep-args)
  (call-interactively 'maf-div)
  (cl-assert (= (calc-stack-size) 3))
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "6 x + 7"))
  (cl-assert (string= (math-format-value (calc-top 3 'full)) "6 x + 14"))
  (cl-assert (eq (char-after) ?4))
  (cl-assert (eq (char-before) ?1))
  (calc-pop (calc-stack-size))

  ;; :widen opts out: the command acted on the sum around point, not on
  ;; the x point was in, so its start says nothing about where the user
  ;; was — the column stands.
  (maf-push "6 x + 12")
  (progn (calc-cursor-stack-index 1)
         (search-forward "x" (line-end-position))
         (backward-char 1))
  (call-interactively 'maf-widen-square)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "(6 x + 12)^2"))
  ;; The column the x stood in, not the ( the widened node starts at.
  (cl-assert (= (current-column) 6))
  (calc-pop (calc-stack-size))

  ;; Whole-entry targets are not selected by point this way and keep
  ;; their affinity: EOL on a relation stays at EOL rather than jumping
  ;; to the rebuilt relation's start.
  (maf-push "6 x + 12 = 18 y + 6")
  (progn (calc-cursor-stack-index 1) (end-of-line))
  (call-interactively 'maf-square)
  (cl-assert (string= (math-format-value (calc-top 1 'full))
                      "(6 x + 12)^2 = (18 y + 6)^2"))
  (cl-assert (eolp))
  (calc-pop (calc-stack-size)))
