;; Step test for maf-commute-left / maf-commute-right: shifting the term
;; under point through its associative chain, with point following the
;; moved term.  Run in a live Emacs (see tests/README.md).
(maf-step
  ;; --- Basic shift, point follows the moved term ---

  ;; Left: the term under point moves one place left; point stays on it.
  (maf-push "a + b + c")
  (progn (goto-char (point-min)) (search-forward "c") (backward-char 1))
  (call-interactively 'maf-commute-left)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "a + c + b"))
  (cl-assert (eq (char-after) ?c))
  (calc-pop 1)

  ;; Right: mirror direction.
  (maf-push "a + b + c")
  (progn (goto-char (point-min)) (search-forward "a") (backward-char 1))
  (call-interactively 'maf-commute-right)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "b + a + c"))
  (cl-assert (eq (char-after) ?a))
  (calc-pop 1)

  ;; Repeat walks the term all the way to the front, point riding along.
  (maf-push "a + b + c")
  (progn (goto-char (point-min)) (search-forward "c") (backward-char 1))
  (call-interactively 'maf-commute-left)
  (call-interactively 'maf-commute-left)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "c + a + b"))
  (cl-assert (eq (char-after) ?c))
  ;; Already leftmost: a further shift is a quiet no-op, point unmoved.
  (call-interactively 'maf-commute-left)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "c + a + b"))
  (cl-assert (eq (char-after) ?c))
  (calc-pop 1)

  ;; Products commute too (juxtaposition is the operator).
  (maf-push "a b c")
  (progn (goto-char (point-min)) (search-forward "c") (backward-char 1))
  (call-interactively 'maf-commute-left)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "a c b"))
  (cl-assert (eq (char-after) ?c))
  (calc-pop 1)

  ;; --- Sign handling: value preserved across - and / ---

  ;; A term crossing a minus becomes an addition of its negation.
  (maf-push "a - b")
  (progn (goto-char (point-min)) (search-forward "b") (backward-char 1))
  (call-interactively 'maf-commute-left)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "-b + a"))
  (calc-pop 1)

  ;; A term crossing a division becomes multiplication by its reciprocal.
  (maf-push "a / b")
  (progn (goto-char (point-min)) (search-forward "b") (backward-char 1))
  (call-interactively 'maf-commute-left)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "(1 / b) a"))
  (calc-pop 1)

  ;; --- Prefix argument ---

  ;; N shifts N places at once.
  (maf-push "a + b + c + d")
  (progn (goto-char (point-min)) (search-forward "d") (backward-char 1))
  (let ((current-prefix-arg 2)) (call-interactively 'maf-commute-left))
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "a + d + b + c"))
  (cl-assert (eq (char-after) ?d))
  (calc-pop 1)

  ;; A negative N reverses direction.
  (maf-push "a + b + c")
  (progn (goto-char (point-min)) (search-forward "a") (backward-char 1))
  (let ((current-prefix-arg -1)) (call-interactively 'maf-commute-left))
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "b + a + c"))
  (calc-pop 1)

  ;; --- No commutable term: do nothing, never signal ---

  ;; At home, point on the . line — no term under point.
  (maf-push "a + b + c")
  (goto-char (point-max))
  (call-interactively 'maf-commute-left)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "a + b + c"))
  (calc-pop 1)

  ;; A lone term with no associative chain around it.
  (maf-push "sin(x)")
  (progn (goto-char (point-min)) (search-forward "x") (backward-char 1))
  (call-interactively 'maf-commute-left)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "sin(x)"))
  (calc-pop 1)

  ;; --- Stack position: a lower entry is acted on in place ---

  (maf-push "x + y + z")     ; index 2 after the next push
  (maf-push "99")            ; top decoy (index 1)
  (progn (calc-cursor-stack-index 2) (beginning-of-line)
         (search-forward "z") (backward-char 1))
  (call-interactively 'maf-commute-left)
  (cl-assert (string= (math-format-value (calc-top 2 'full)) "x + z + y"))
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "99"))
  (cl-assert (eq (char-after) ?z))
  ;; index 2 renders on buffer line 1; point stayed on its entry, not home.
  (cl-assert (= (line-number-at-pos) 1))
  (calc-pop (calc-stack-size)))
