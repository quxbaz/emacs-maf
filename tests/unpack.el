(maf-step
  ;; The command holds M-u and v u (calc-unpack, whose whole-entry
  ;; behavior it matches at home). j U and j M-U -- calc's own
  ;; calc-sel-unpack keys -- take mafcmd-unwrap, the same reading kept
  ;; as its own command on the selection prefix; that command has its
  ;; own file, unwrap.el. Assert on resolution rather
  ;; than driving the keys: calc's fancy prefixes do not survive
  ;; execute-kbd-macro, which is why the j-prefix commands are called
  ;; directly throughout these tests.
  (cl-assert (eq (key-binding (kbd "M-u")) 'mafcmd-unpack))
  (cl-assert (eq (key-binding (kbd "v u")) 'mafcmd-unpack))
  (cl-assert (eq (key-binding (kbd "j U")) 'mafcmd-unwrap))
  (cl-assert (eq (key-binding (kbd "j M-U")) 'mafcmd-unwrap))
  ;; The j prefix still falls through to calc's own selection commands.
  (cl-assert (eq (key-binding (kbd "j s")) 'calc-select-here))

  ;; Home: a vector spreads one element per stack entry, and point
  ;; stays at home as it does for any command.
  (maf-push "[x, y]")
  (goto-char (point-max))
  (call-interactively 'mafcmd-unpack)
  (cl-assert (= (calc-stack-size) 2))
  (cl-assert (string= (math-format-value (calc-top 2 'full)) "x"))
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "y"))
  (cl-assert (maf--at-home-p))
  (calc-pop 2)

  ;; At the entry, point lands at the end of the last part -- the end
  ;; of what the entry became -- not on the first part's line, where
  ;; the entry used to be.
  (maf-push "[x, y]")
  (progn (goto-char (point-min)) (end-of-line))
  (call-interactively 'mafcmd-unpack)
  (cl-assert (= (calc-stack-size) 2))
  (cl-assert (= (calc-locate-cursor-element (point)) 1))
  (cl-assert (eolp))
  (cl-assert (looking-back "1:  y" (line-beginning-position)))
  (calc-pop 2)

  ;; Point on the opening bracket names the vector itself -- a
  ;; sub-formula that is the entry's whole formula, whose slot is the
  ;; entry. The parts spread as from the entry, point at the end of the
  ;; last one.
  (maf-push "[x, y]")
  (progn (goto-char (point-min)) (search-forward "[") (backward-char 1))
  (call-interactively 'mafcmd-unpack)
  (cl-assert (= (calc-stack-size) 2))
  (cl-assert (string= (math-format-value (calc-top 2 'full)) "x"))
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "y"))
  (cl-assert (= (calc-locate-cursor-element (point)) 1))
  (cl-assert (eolp))
  (calc-pop 2)

  ;; Same from the comma and the closing bracket, the vector's own
  ;; glyphs.
  (maf-push "[x, y]")
  (progn (goto-char (point-min)) (search-forward ","))
  (call-interactively 'mafcmd-unpack)
  (cl-assert (= (calc-stack-size) 2))
  (cl-assert (= (calc-locate-cursor-element (point)) 1))
  (calc-pop 2)

  ;; A selection of the whole formula is the root too: the parts spread
  ;; and no selection survives on them.
  (maf-push "[x, y]")
  (progn (goto-char (point-min)) (search-forward "[") (backward-char 1))
  (call-interactively 'calc-select-here)
  (cl-assert (string= (math-format-value (nth 2 (nth 1 calc-stack))) "[x, y]"))
  (call-interactively 'mafcmd-unpack)
  (cl-assert (= (calc-stack-size) 2))
  (cl-assert (string= (math-format-value (calc-top 2 'full)) "x"))
  (cl-assert (null (nth 2 (nth 1 calc-stack))))
  (cl-assert (null (nth 2 (nth 2 calc-stack))))
  (cl-assert (null calc-any-selections))
  (calc-pop 2)

  ;; In the line-number margin point keeps to the margin, on the last
  ;; part's line.
  (maf-push "[x, y]")
  (progn (goto-char (point-min)) (forward-char 1))
  (call-interactively 'mafcmd-unpack)
  (cl-assert (= (calc-stack-size) 2))
  (cl-assert (= (calc-locate-cursor-element (point)) 1))
  (cl-assert (= (current-column) 1))
  (calc-pop 2)

  ;; A one-argument function call unwraps to just its argument.
  (maf-push "sqrt(x)")
  (goto-char (point-max))
  (call-interactively 'mafcmd-unpack)
  (cl-assert (= (calc-stack-size) 1))
  (cl-assert (equal (calc-top 1 'full) '(var x var-x)))
  (calc-pop 1)

  ;; An operator gives its operands, one level only.
  (maf-push "a + b")
  (goto-char (point-max))
  (call-interactively 'mafcmd-unpack)
  (cl-assert (= (calc-stack-size) 2))
  (cl-assert (string= (math-format-value (calc-top 2 'full)) "a"))
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "b"))
  (calc-pop 2)

  ;; A function call gives every argument.
  (maf-push "f(a,b,c)")
  (goto-char (point-max))
  (call-interactively 'mafcmd-unpack)
  (cl-assert (= (calc-stack-size) 3))
  (cl-assert (string= (math-format-value (calc-top 3 'full)) "a"))
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "c"))
  (calc-pop 3)

  ;; A fraction is a composite too; a float gives mantissa and exponent.
  (maf-push "3:4")
  (goto-char (point-max))
  (call-interactively 'mafcmd-unpack)
  (cl-assert (equal (list (calc-top 2 'full) (calc-top 1 'full)) '(3 4)))
  (calc-pop 2)

  (maf-push "1.5")
  (goto-char (point-max))
  (call-interactively 'mafcmd-unpack)
  (cl-assert (equal (list (calc-top 2 'full) (calc-top 1 'full)) '(15 -1)))
  (calc-pop 2)

  ;; Degenerate: a bare variable has nothing to give and commits
  ;; unchanged rather than signaling. Assert on the raw structure --
  ;; non-alteration is the contract, so it must not be re-wrapped.
  (maf-push "x")
  (goto-char (point-max))
  (call-interactively 'mafcmd-unpack)
  (cl-assert (= (calc-stack-size) 1))
  (cl-assert (equal (calc-top 1 'full) '(var x var-x)))
  (calc-pop 1)

  ;; Likewise a plain number.
  (maf-push "17")
  (goto-char (point-max))
  (call-interactively 'mafcmd-unpack)
  (cl-assert (equal (calc-top 1 'full) 17))
  (calc-pop 1)

  ;; An empty vector has no parts to give, so the entry survives. Calc's
  ;; own unpack would pop it and push nothing, emptying the stack.
  (maf-push "[]")
  (goto-char (point-max))
  (call-interactively 'mafcmd-unpack)
  (cl-assert (= (calc-stack-size) 1))
  (cl-assert (equal (calc-top 1 'full) '(vec)))
  (calc-pop 1)

  ;; Point inside a formula names the node it sits on, not the entry:
  ;; on sin here, the call unwraps in place and the sum around it
  ;; survives. The entry count does not change -- nothing spreads
  ;; onto the stack.
  (maf-push "y + sin(x)")
  (progn (goto-char (point-min)) (search-forward "sin") (backward-char 2))
  (call-interactively 'mafcmd-unpack)
  (cl-assert (= (calc-stack-size) 1))
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "y + x"))
  (calc-pop 1)

  ;; Landing: the part that took the wrapper's place is a different
  ;; node from the one point was on, so point goes to the glyph that
  ;; names it whole -- the + of the sum, not its first character (the
  ;; atom 2). Pressing the key again there would take the sum apart.
  (maf-push "sin(2 x + 1)")
  (progn (goto-char (point-min)) (search-forward "sin") (backward-char 3))
  (call-interactively 'mafcmd-unpack)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "2 x + 1"))
  (cl-assert (eq (char-after) ?+))
  (cl-assert (equal (alist-get :expr (maf--resolve-context '((:arity . unary))))
                    '(+ (* 2 (var x var-x)) 1)))
  (calc-pop 1)

  ;; A function's name, a vector's opening bracket, an atom itself.
  (maf-push "sin(cos(x))")
  (progn (goto-char (point-min)) (search-forward "sin") (backward-char 3))
  (call-interactively 'mafcmd-unpack)
  (cl-assert (looking-at "cos(x)"))
  (calc-pop 1)

  (maf-push "sin([a, b])")
  (progn (goto-char (point-min)) (search-forward "sin") (backward-char 3))
  (call-interactively 'mafcmd-unpack)
  (cl-assert (looking-at "\\[a, b\\]"))
  (calc-pop 1)

  (maf-push "y + sin(x)")
  (progn (goto-char (point-min)) (search-forward "sin") (backward-char 3))
  (call-interactively 'mafcmd-unpack)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "y + x"))
  (cl-assert (eq (char-after) ?x))
  (calc-pop 1)

  ;; A juxtaposed product renders its multiplication as a bare space,
  ;; and that space is the glyph naming it: point lands there, and
  ;; resolves to the product.
  (maf-push "sin(2 x)")
  (progn (goto-char (point-min)) (search-forward "sin") (backward-char 3))
  (call-interactively 'mafcmd-unpack)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "2 x"))
  (cl-assert (eq (char-after) ?\s))
  (cl-assert (equal (alist-get :expr (maf--resolve-context '((:arity . unary))))
                    '(* 2 (var x var-x))))
  (calc-pop 1)

  ;; Nesting follows point: on cos it peels cos, on sin it peels sin.
  (maf-push "sin(cos(x))")
  (progn (goto-char (point-min)) (search-forward "cos") (backward-char 2))
  (call-interactively 'mafcmd-unpack)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "sin(x)"))
  (calc-pop 1)

  (maf-push "sin(cos(x))")
  (progn (goto-char (point-min)) (search-forward "sin") (backward-char 2))
  (call-interactively 'mafcmd-unpack)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "cos(x)"))
  (calc-pop 1)

  ;; Widening: on x the variable has nothing to give, so the target
  ;; becomes the innermost node around it that gives exactly one part
  ;; -- the cos, which comes off. Point lands on what came out.
  (maf-push "sin(cos(x))")
  (progn (goto-char (point-min)) (search-forward "(x)") (backward-char 2))
  (call-interactively 'mafcmd-unpack)
  (cl-assert (= (calc-stack-size) 1))
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "sin(x)"))
  (cl-assert (eq (char-after) ?x))
  (calc-pop 1)

  ;; From inside a multi-part operand the walk goes out past it: on
  ;; the product 2 x, two parts and no room, the sin around it is the
  ;; wrapper that fits. The sum it held stays whole, point on its +.
  (maf-push "sin(2 x + 1)")
  (progn (goto-char (point-min)) (search-forward "2 x") (backward-char 2))
  (call-interactively 'mafcmd-unpack)
  (cl-assert (= (calc-stack-size) 1))
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "2 x + 1"))
  (cl-assert (eq (char-after) ?+))
  (calc-pop 1)

  ;; A multi-part node in a formula slot has no room for its parts:
  ;; f(a,b) gives two, and a slot fits one, and here nothing encloses
  ;; it that would fit either -- the sum gives two as well. Unchanged,
  ;; with nothing spilling onto the stack.
  (maf-push "y + f(a,b)")
  (progn (goto-char (point-min)) (search-forward "f(a") (backward-char 3))
  (call-interactively 'mafcmd-unpack)
  (cl-assert (= (calc-stack-size) 1))
  (cl-assert (equal (calc-top 1 'full)
                    '(+ (var y var-y) (calcFunc-f (var a var-a) (var b var-b)))))
  (calc-pop 1)

  ;; Likewise an operator inside a product: point on the + names the
  ;; two-part sum, and the product around it has two parts too, so the
  ;; walk finds nothing to peel and the entry stays where it is.
  (maf-push "(a + b) (2 c - d)")
  (progn (goto-char (point-min)) (search-forward "+") (backward-char 1))
  (call-interactively 'mafcmd-unpack)
  (cl-assert (= (calc-stack-size) 1))
  (cl-assert (string= (math-format-value (calc-top 1 'full))
                      "(a + b) (2 c - d)"))
  (calc-pop 1)

  ;; The entry at point, not the top: point at the end of a lower entry
  ;; names it whole, and its parts spread in place, beneath the entries
  ;; above it. Point lands at the end of the last part, the line below
  ;; where the entry was.
  (maf-push "[1, 2]")
  (maf-push "z")
  (progn (calc-cursor-stack-index 2) (end-of-line))
  (call-interactively 'mafcmd-unpack)
  (cl-assert (= (calc-stack-size) 3))
  (cl-assert (equal (calc-top 3 'full) 1))
  (cl-assert (equal (calc-top 2 'full) 2))
  (cl-assert (equal (calc-top 1 'full) '(var z var-z)))
  (cl-assert (= (calc-locate-cursor-element (point)) 2))
  (cl-assert (eolp))
  (calc-pop 3)

  ;; Big language spaces its entries with a blank line; the end of the
  ;; last part is still the end of its formula line, not the blank
  ;; line below it.
  (maf-push "[a + b, c]")
  (call-interactively 'maf-toggle-big-language)
  (progn (goto-char (point-min)) (end-of-line))
  (call-interactively 'mafcmd-unpack)
  (cl-assert (= (calc-stack-size) 2))
  (cl-assert (= (calc-locate-cursor-element (point)) 1))
  (cl-assert (looking-back "1:  c" (line-beginning-position)))
  (call-interactively 'maf-toggle-big-language)
  (calc-pop 2)

  ;; An explicit calc selection names its node: a one-part selection
  ;; unwraps in place, and the unwrapped result stays selected.
  (maf-push "y + sin(x)")
  (progn (goto-char (point-min)) (search-forward "sin") (backward-char 2))
  (call-interactively 'calc-select-here)
  (cl-assert (string= (math-format-value (nth 2 (nth 1 calc-stack))) "sin(x)"))
  (call-interactively 'mafcmd-unpack)
  (cl-assert (= (calc-stack-size) 1))
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "y + x"))
  (cl-assert (string= (math-format-value (nth 2 (nth 1 calc-stack))) "x"))
  (calc-clear-selections)
  (calc-pop 1)

  ;; A two-part selection has no room for its parts and stands.
  (maf-push "sin(2 x)")
  (progn (goto-char (point-min)) (search-forward "2 x") (backward-char 2))
  (call-interactively 'calc-select-here)
  (cl-assert (string= (math-format-value (nth 2 (nth 1 calc-stack))) "2 x"))
  (call-interactively 'mafcmd-unpack)
  (cl-assert (= (calc-stack-size) 1))
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "sin(2 x)"))
  (calc-clear-selections)
  (calc-pop 1)

  ;; Equation at the entry: a relation is a function call like any
  ;; other, so it comes apart into its two sides rather than mapping
  ;; per side.
  (maf-push "x = sin(y)")
  (progn (goto-char (point-min)) (end-of-line))
  (call-interactively 'mafcmd-unpack)
  (cl-assert (= (calc-stack-size) 2))
  (cl-assert (string= (math-format-value (calc-top 2 'full)) "x"))
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "sin(y)"))
  (calc-pop 2)

  ;; An inequality splits the same way.
  (maf-push "a < b")
  (progn (goto-char (point-min)) (end-of-line))
  (call-interactively 'mafcmd-unpack)
  (cl-assert (= (calc-stack-size) 2))
  (calc-pop 2)

  ;; Point on a sub-formula inside a relation names that sub-formula,
  ;; so the relation survives rather than coming apart into its sides.
  (maf-push "x = sin(y)")
  (progn (goto-char (point-min)) (search-forward "sin") (backward-char 2))
  (call-interactively 'mafcmd-unpack)
  (cl-assert (= (calc-stack-size) 1))
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "x = y"))
  (calc-pop 1)

  ;; A region covering exactly one node resolves as a sub-formula, and
  ;; unwraps as one.
  (maf-push "a + sin(2 x) + c")
  (progn (calc-cursor-stack-index 1)
         (search-forward "sin(2 x)" (line-end-position))
         (goto-char (match-beginning 0))
         (push-mark (match-end 0) t t)
         (call-interactively 'mafcmd-unpack))
  (cl-assert (= (calc-stack-size) 1))
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "a + 2 x + c"))
  (calc-pop 1)

  ;; A region covering a chain run is carved from the chain: two parts,
  ;; and a slot fits one, so the entry stands.
  (maf-push "a + sin(2 x) + c")
  (progn (calc-cursor-stack-index 1)
         (search-forward "sin(2 x) + c" (line-end-position))
         (goto-char (match-beginning 0))
         (push-mark (match-end 0) t t)
         (call-interactively 'mafcmd-unpack))
  (cl-assert (= (calc-stack-size) 1))
  (cl-assert (string= (math-format-value (calc-top 1 'full))
                      "a + sin(2 x) + c"))
  (calc-pop 1)

  ;; Keep-args with point inside the formula: the unwrapped entry goes
  ;; on top, the original stays beneath it.
  (maf-push "y + sin(2 x)")
  (progn (goto-char (point-min)) (search-forward "sin") (backward-char 2))
  (call-interactively 'calc-keep-args)
  (call-interactively 'mafcmd-unpack)
  (cl-assert (= (calc-stack-size) 2))
  (cl-assert (string= (math-format-value (calc-top 2 'full)) "y + sin(2 x)"))
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "y + 2 x"))
  (calc-pop 2)

  ;; Big-language display resolves the same node, so the same peel.
  (maf-push "y + sin(2 x)")
  (call-interactively 'maf-toggle-big-language)
  (progn (goto-char (point-min)) (search-forward "sin") (backward-char 2))
  (call-interactively 'mafcmd-unpack)
  (cl-assert (= (calc-stack-size) 1))
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "y + 2 x"))
  (call-interactively 'maf-toggle-big-language)
  (calc-pop 1)

  ;; A positive prefix argument unwraps that many levels deep.
  (maf-push "[(1,2),(3,4)]")
  (goto-char (point-max))
  (let ((current-prefix-arg 2)) (call-interactively 'mafcmd-unpack))
  (cl-assert (= (calc-stack-size) 4))
  (cl-assert (equal (mapcar (lambda (i) (calc-top i 'full)) '(4 3 2 1))
                    '(1 2 3 4)))
  (calc-pop 4)

  ;; The mode applies at a sub-formula too: two levels off a nested
  ;; one-element vector give the element, which fits the slot.
  (maf-push "y + [[x]]")
  (progn (goto-char (point-min)) (search-forward "[[") (backward-char 2))
  (let ((current-prefix-arg 2)) (call-interactively 'mafcmd-unpack))
  (cl-assert (= (calc-stack-size) 1))
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "y + x"))
  (calc-pop 1)

  ;; A negative prefix argument splits a vector by component type: the
  ;; real parts, then the imaginary parts.
  (maf-push "[(1,2),(3,4)]")
  (goto-char (point-max))
  (let ((current-prefix-arg -1)) (call-interactively 'mafcmd-unpack))
  (cl-assert (= (calc-stack-size) 2))
  (cl-assert (equal (calc-top 2 'full) '(vec 1 3)))
  (cl-assert (equal (calc-top 1 'full) '(vec 2 4)))
  (calc-pop 2)

  ;; A mode the expression does not fit is a no-op, not an error: -3
  ;; wants an HMS form. The entry must survive untouched.
  (maf-push "(2,3)")
  (goto-char (point-max))
  (let ((current-prefix-arg -3)) (call-interactively 'mafcmd-unpack))
  (cl-assert (= (calc-stack-size) 1))
  (cl-assert (equal (calc-top 1 'full) '(cplx 2 3)))
  (calc-pop 1)

  ;; Under the map flag each element is unpacked in place: a vector of
  ;; calls comes back as a vector of their arguments, where unpacking
  ;; the vector itself would have spread the calls over the stack. The
  ;; parts are a value list — what commit spreads over entries — and an
  ;; element's slot holds one expression, so the single part stands in
  ;; (`maf--defcmd-map-slot').
  (maf-push "[cos(1), cos(2), cos(3)]")
  (goto-char (point-max))
  (execute-kbd-macro (kbd "M M-u"))
  (cl-assert (= (calc-stack-size) 1))
  (cl-assert (equal (maf--strip-encasing (calc-top 1 'full)) '(vec 1 2 3)))
  (calc-pop 1)

  ;; An element with several parts has nowhere to put them, so it is
  ;; left as it stands rather than losing all but one — the reading the
  ;; equation target already gave such a list.
  (maf-push "[x + y, sin(a)]")
  (goto-char (point-max))
  (execute-kbd-macro (kbd "M M-u"))
  (cl-assert (string= (math-format-value
                       (maf--strip-encasing (calc-top 1 'full)))
                      "[x + y, a]"))
  (calc-pop 1)

  ;; A matrix unpacks element by element, the shape kept.
  (maf-push "[[cos(1), cos(2)]]")
  (goto-char (point-max))
  (execute-kbd-macro (kbd "M M-u"))
  (cl-assert (equal (maf--strip-encasing (calc-top 1 'full))
                    '(vec (vec 1 2))))
  (calc-pop 1)

  ;; Keep-args leaves the original beneath the parts.
  (maf-push "a + b")
  (goto-char (point-max))
  (call-interactively 'calc-keep-args)
  (call-interactively 'mafcmd-unpack)
  (cl-assert (= (calc-stack-size) 3))
  (cl-assert (string= (math-format-value (calc-top 3 'full)) "a + b"))
  (cl-assert (string= (math-format-value (calc-top 2 'full)) "a"))
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "b"))
  (calc-pop 3)

  ;; Keep-args from the entry: the parts go on top and point follows
  ;; them to the end of the last one.
  (maf-push "a + b")
  (progn (goto-char (point-min)) (end-of-line))
  (call-interactively 'calc-keep-args)
  (call-interactively 'mafcmd-unpack)
  (cl-assert (= (calc-stack-size) 3))
  (cl-assert (string= (math-format-value (calc-top 3 'full)) "a + b"))
  (cl-assert (= (calc-locate-cursor-element (point)) 1))
  (cl-assert (looking-back "1:  b" (line-beginning-position)))
  (calc-pop 3))
