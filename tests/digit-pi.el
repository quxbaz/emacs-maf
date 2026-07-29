(maf-step
  ;; --- Digit entry: n and P commit the entry times pi ---

  ;; The plain case: 2 n pushes 2 pi, symbolic — the constant is not
  ;; evaluated to a float.
  (goto-char (point-max))
  (execute-kbd-macro (kbd "2 n"))
  (cl-assert (equal (calc-top 1 'full) '(* 2 (var pi var-pi))))
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "2 pi"))
  (calc-pop (calc-stack-size))

  ;; P is the same key, for the hand that reaches for calc's own pi.
  (goto-char (point-max))
  (execute-kbd-macro (kbd "4 P"))
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "4 pi"))
  (calc-pop (calc-stack-size))

  ;; Any number the entry can read is a multiple: a typed fraction gives
  ;; the fraction of pi.
  (goto-char (point-max))
  (execute-kbd-macro (kbd "1 : 3 n"))
  (cl-assert (equal (calc-top 1 'full) '(/ (var pi var-pi) 3)))
  (calc-pop (calc-stack-size))

  ;; A multiple of 1 is pi alone, not 1 pi.
  (goto-char (point-max))
  (execute-kbd-macro (kbd "1 n"))
  (cl-assert (equal (calc-top 1 'full) '(var pi var-pi)))
  (calc-pop (calc-stack-size))

  ;; And calc's leading-1 rule applies, as it does to `:' and `e': with
  ;; only a sign typed, the multiple is supplied.
  (goto-char (point-max))
  (execute-kbd-macro (kbd "_ n"))
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "-pi"))
  (calc-pop (calc-stack-size))

  ;; The commit is the contextual one: on a numeric leaf the product
  ;; replaces it, and it goes in literally, as one factor.
  (maf-push "3 x")
  (progn (goto-char (point-min)) (search-forward "3") (backward-char 1))
  (execute-kbd-macro (kbd "2 n"))
  (cl-assert (= (calc-stack-size) 1))
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "(2 pi) x"))
  (cl-assert (not (maf--at-home-p)))
  (calc-pop (calc-stack-size))

  ;; On any other sub-formula it multiplies, product on the left.
  (maf-push "x + 3")
  (progn (goto-char (point-min)) (search-forward "x") (backward-char 1))
  (execute-kbd-macro (kbd "2 n"))
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "(2 pi) x + 3"))
  (calc-pop (calc-stack-size))

  ;; A contextual commit is one undo group, as a plain entry is.
  (maf-push "3 x")
  (progn (goto-char (point-min)) (search-forward "3") (backward-char 1))
  (execute-kbd-macro (kbd "2 n"))
  (execute-kbd-macro (kbd "U"))
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "3 x"))
  (calc-pop (calc-stack-size))

  ;; At a margin the completion is a RET: the product is pushed, point
  ;; homes, and a mark is left to pop back to.
  (maf-push "x + 3")
  (progn (goto-char (point-min)) (end-of-line) (setq mark-ring nil) (set-mark nil))
  (execute-kbd-macro (kbd "2 n"))
  (cl-assert (= (calc-stack-size) 2))
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "2 pi"))
  (cl-assert (string= (math-format-value (calc-top 2 'full)) "x + 3"))
  (cl-assert (maf--at-home-p))
  (cl-assert (integerp (mark t)))
  (calc-pop (calc-stack-size))

  ;; Inside an incomplete object the element being typed is the
  ;; multiple; the object closes as it always did.
  (goto-char (point-max))
  (execute-kbd-macro (kbd "[ 1 ; 2 n ] ]"))
  (cl-assert (equal (calc-top 1 'full)
                    '(vec (vec 1) (vec (* 2 (var pi var-pi))))))
  (calc-pop (calc-stack-size))

  ;; --- Inside a radix-prefixed entry both keys are calc's own ---

  ;; n is the sign flip for a radix with no N digit (base 16 stops at F).
  (goto-char (point-max))
  (execute-kbd-macro (kbd "1 6 # f f n RET"))
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "-255"))
  (calc-pop (calc-stack-size))

  ;; P is a digit where the radix has one (P is 25, so base 30 does).
  (goto-char (point-max))
  (execute-kbd-macro (kbd "3 0 # 1 P RET"))
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "55"))
  (calc-pop (calc-stack-size))

  ;; --- With maf-mode off, so are the shortcuts ---

  ;; `calc-digit-map' is calc's own map, so a key installed there fires
  ;; in every calc digit entry; with the mode off both keys must behave
  ;; as they do in plain calc. n is the entry's sign flip.
  (unwind-protect
      (progn (maf-mode -1)
             (goto-char (point-max))
             (execute-kbd-macro (kbd "2 n RET")))
    (maf-mode 1))
  (cl-assert maf-mode)
  (cl-assert (= (calc-stack-size) 1))
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "-2"))
  (calc-pop (calc-stack-size))

  ;; And P is a nondigit that ends the entry and re-dispatches, reaching
  ;; calc's own `calc-pi': the number pushed, pi's float on top of it.
  (unwind-protect
      (progn (maf-mode -1)
             (goto-char (point-max))
             (execute-kbd-macro (kbd "4 P")))
    (maf-mode 1))
  (cl-assert (= (calc-stack-size) 2))
  (cl-assert (eq (car-safe (calc-top 1 'full)) 'float))
  (cl-assert (= (calc-top 2 'full) 4))
  (calc-pop (calc-stack-size)))
