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

  ;; --- Only value-preserving arithmetic parents (+ - * /) ---

  ;; A term under ^ must not be reordered: x^2 -> 2^x changes the value.
  ;; No-op even nested inside an arithmetic expression.
  (maf-push "1 / (x^2 - 1)")
  (progn (goto-char (point-min)) (search-forward "x^"))  ; point on the exponent 2
  (call-interactively 'maf-commute-left)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "1 / (x^2 - 1)"))
  (calc-pop 1)

  ;; The base of a power is likewise not commutable out of the ^.
  (maf-push "x^2 + 1")
  (progn (goto-char (point-min)) (search-forward "x") (backward-char 1))
  (call-interactively 'maf-commute-left)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "x^2 + 1"))
  (calc-pop 1)

  ;; --- Relations stay balanced ---

  ;; A term directly under a relation is NOT reordered: shuffling a < b
  ;; to b < a would reverse the inequality (that is mafcmd-commute's job,
  ;; which flips the direction).  So this is a no-op.
  (maf-push "a < b")
  (progn (goto-char (point-min)) (search-forward "b") (backward-char 1))
  (call-interactively 'maf-commute-left)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "a < b"))
  (calc-pop 1)

  ;; Symmetric relations are left alone too, for consistency.
  (maf-push "a = b")
  (progn (goto-char (point-min)) (search-forward "b") (backward-char 1))
  (call-interactively 'maf-commute-left)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "a = b"))
  (calc-pop 1)

  ;; But a term INSIDE one side commutes freely — the side keeps its
  ;; value, so the relation stays balanced.
  (maf-push "p + q + r < s")
  (progn (goto-char (point-min)) (search-forward "r") (backward-char 1))
  (call-interactively 'maf-commute-left)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "p + r + q < s"))
  (cl-assert (eq (char-after) ?r))
  (calc-pop 1)

  ;; Sign flip inside a side of an equation is value-preserving.
  (maf-push "x - y = z")
  (progn (goto-char (point-min)) (search-forward "y") (backward-char 1))
  (call-interactively 'maf-commute-left)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "-y + x = z"))
  (calc-pop 1)

  ;; --- Vector elements shift position ---

  ;; An element moves through its neighbors, point riding along.
  (maf-push "[a, b, c]")
  (progn (goto-char (point-min)) (search-forward "b") (backward-char 1))
  (call-interactively 'maf-commute-right)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "[a, c, b]"))
  (cl-assert (eq (char-after) ?b))
  ;; Already rightmost: clamped, a quiet no-op.
  (call-interactively 'maf-commute-right)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "[a, c, b]"))
  ;; A prefix walks several places at once.
  (let ((current-prefix-arg 2)) (call-interactively 'maf-commute-left))
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "[b, a, c]"))
  (cl-assert (eq (char-after) ?b))
  ;; One undo takes back exactly one shift.
  (maf-undo 1)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "[a, c, b]"))
  (calc-pop 1)

  ;; Inside a composite element the arithmetic chain still wins: the
  ;; term commutes within its sum, the element stays put.
  (maf-push "[a, b + c, d]")
  (progn (goto-char (point-min)) (search-forward "b") (backward-char 1))
  (call-interactively 'maf-commute-right)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "[a, c + b, d]"))
  (calc-pop 1)

  ;; A composite element moves whole from its comma (calc's selection
  ;; maps an inner vector's comma to the vector).
  (maf-push "[[1, 2], [3, 4, 9], [5]]")
  (progn (goto-char (point-min)) (search-forward "3,") (backward-char 1))
  (call-interactively 'maf-commute-left)
  (cl-assert (string= (math-format-value (calc-top 1 'full))
                      "[[3, 4, 9], [1, 2], [5]]"))
  (calc-pop 1)

  ;; --- Point keeps its place in the term, not the term's first character ---

  ;; On the = of an element, point is on that = again once the element
  ;; has moved -- not pulled back to the element's leading p.
  (maf-push "[h = 0, p = -4, k = 0]")
  (progn (goto-char (point-min)) (search-forward "p ="))
  (call-interactively 'maf-commute-left)
  (cl-assert (string= (math-format-value (calc-top 1 'full))
                      "[p = -4, h = 0, k = 0]"))
  (cl-assert (string= (buffer-substring (- (point) 3) (point)) "p ="))
  ;; And back the other way, from the same grip.
  (call-interactively 'maf-commute-right)
  (cl-assert (string= (math-format-value (calc-top 1 'full))
                      "[h = 0, p = -4, k = 0]"))
  (cl-assert (string= (buffer-substring (- (point) 3) (point)) "p ="))
  (calc-pop 1)

  ;; The same for a composite element gripped by its comma: point is on
  ;; the moved element's own comma, not on its opening bracket.
  (maf-push "[[1, 2], [3, 4, 9], [5]]")
  (progn (goto-char (point-min)) (search-forward "3,") (backward-char 1))
  (call-interactively 'maf-commute-left)
  (cl-assert (string= (math-format-value (calc-top 1 'full))
                      "[[3, 4, 9], [1, 2], [5]]"))
  (cl-assert (eq (char-after) ?,))
  (cl-assert (eq (char-before) ?3))
  (calc-pop 1)

  ;; The term travels whole, so a grip inside one of its own operands
  ;; is kept too: from the last digit of a multi-character name, point
  ;; is on that digit again, not on the name's first letter.
  (maf-push "[a, b, c12]")
  (progn (goto-char (point-min)) (search-forward "c12") (backward-char 1))
  (call-interactively 'maf-commute-left)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "[a, c12, b]"))
  (cl-assert (eq (char-after) ?2))
  (cl-assert (string= (buffer-substring (- (point) 2) (1+ (point))) "c12"))
  (calc-pop 1)

  ;; The same inside a composite element, where the inner term is what
  ;; commutes: point holds its digit through the shift.
  (maf-push "[a, b + c12, d]")
  (progn (goto-char (point-min)) (search-forward "c12") (backward-char 1))
  (call-interactively 'maf-commute-left)
  (cl-assert (string= (math-format-value (calc-top 1 'full))
                      "[a, c12 + b, d]"))
  (cl-assert (eq (char-after) ?2))
  (calc-pop 1)

  ;; A single-character term has one place to be, and keeps it.
  (maf-push "[a, b, c]")
  (progn (goto-char (point-min)) (search-forward "b") (backward-char 1))
  (call-interactively 'maf-commute-left)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "[b, a, c]"))
  (cl-assert (eq (char-after) ?b))
  (calc-pop 1)

  ;; A vector nested in a larger expression shifts in place.
  (maf-push "x + [a, b, c]")
  (progn (goto-char (point-min)) (search-forward "b") (backward-char 1))
  (call-interactively 'maf-commute-left)
  (cl-assert (string= (math-format-value (calc-top 1 'full))
                      "x + [b, a, c]"))
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
