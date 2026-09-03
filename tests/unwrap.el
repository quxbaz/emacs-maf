(maf-step
  ;; The widening sibling of mafcmd-unpack holds calc's own
  ;; calc-sel-unpack keys, j U and its j M-U alias. The command that
  ;; takes the node at point as it stands keeps M-u and v u -- see
  ;; unpack.el. Assert on resolution
  ;; rather than driving the keys: calc's fancy prefixes do not survive
  ;; execute-kbd-macro, which is why the j-prefix commands are called
  ;; directly throughout these tests.
  (cl-assert (eq (key-binding (kbd "j U")) 'mafcmd-unwrap))
  (cl-assert (eq (key-binding (kbd "j M-U")) 'mafcmd-unwrap))
  (cl-assert (eq (key-binding (kbd "M-u")) 'mafcmd-unpack))
  (cl-assert (eq (key-binding (kbd "v u")) 'mafcmd-unpack))
  ;; The j prefix still falls through to calc's own selection commands.
  (cl-assert (eq (key-binding (kbd "j s")) 'calc-select-here))

  ;; The reported case: point inside a one-argument call within a
  ;; relation takes off the wrapper in place, leaving what it held.
  ;; The entry count does not change -- nothing spreads onto the stack.
  (maf-push "2 x - 3 < sin(7)")
  (progn (goto-char (point-min)) (search-forward "sin") (backward-char 2))
  (call-interactively 'mafcmd-unwrap)
  (cl-assert (= (calc-stack-size) 1))
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "2 x - 3 < 7"))
  (calc-pop 1)

  ;; Sub-formula: a slot holds one expression, so a single-part
  ;; sub-formula unwraps in place.
  (maf-push "y + sin(x)")
  (progn (goto-char (point-min)) (search-forward "sin") (backward-char 2))
  (call-interactively 'mafcmd-unwrap)
  (cl-assert (= (calc-stack-size) 1))
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "y + x"))
  (calc-pop 1)

  ;; A multi-part sub-formula does not fit the slot, and here nothing
  ;; encloses it that would: f(a,b) gives two parts, and so does the sum
  ;; around it. Unchanged, with nothing spilling onto the stack.
  (maf-push "y + f(a,b)")
  (progn (goto-char (point-min)) (search-forward "f(a") (backward-char 3))
  (call-interactively 'mafcmd-unwrap)
  (cl-assert (= (calc-stack-size) 1))
  (cl-assert (equal (calc-top 1 'full)
                    '(+ (var y var-y) (calcFunc-f (var a var-a) (var b var-b)))))
  (calc-pop 1)

  ;; Widening: point on an operand peels the wrapper enclosing it. The
  ;; node under point (x) has nothing to give, so the target becomes the
  ;; innermost node that does -- sin(2 x).
  (maf-push "y + sin(2 x)")
  (progn (goto-char (point-min)) (search-forward "2 x") (backward-char 1))
  (call-interactively 'mafcmd-unwrap)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "y + 2 x"))
  (calc-pop 1)

  ;; Same from the implicit multiplication operator between 2 and x,
  ;; whose own node (2 x) has two parts and does not fit either.
  (maf-push "y + sin(2 x)")
  (progn (goto-char (point-min)) (search-forward "2 x") (backward-char 2))
  (call-interactively 'mafcmd-unwrap)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "y + 2 x"))
  (calc-pop 1)

  ;; Widening stops at the innermost wrapper, so nesting still follows
  ;; point: on x it peels cos, on sin it peels sin.
  (maf-push "sin(cos(x))")
  (progn (goto-char (point-min)) (search-forward "(x)") (backward-char 2))
  (call-interactively 'mafcmd-unwrap)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "sin(x)"))
  (calc-pop 1)

  (maf-push "sin(cos(x))")
  (progn (goto-char (point-min)) (search-forward "sin") (backward-char 2))
  (call-interactively 'mafcmd-unwrap)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "cos(x)"))
  (calc-pop 1)

  ;; Nothing peelable anywhere out to the entry: unchanged. Bounding the
  ;; walk at the entry is what keeps widening from reaching past what
  ;; point is looking at.
  (maf-push "(a + b) (2 c - d)")
  (progn (goto-char (point-min)) (search-forward "a") (backward-char 1))
  (call-interactively 'mafcmd-unwrap)
  (cl-assert (string= (math-format-value (calc-top 1 'full))
                      "(a + b) (2 c - d)"))
  (calc-pop 1)

  ;; An explicit calc selection is a deliberate gesture and is never
  ;; widened: selecting the two-part 2 x leaves the entry alone rather
  ;; than peeling the sin around it.
  (maf-push "sin(2 x)")
  (progn (goto-char (point-min)) (search-forward "2 x") (backward-char 2))
  (call-interactively 'calc-select-here)
  (cl-assert (string= (math-format-value (nth 2 (nth 1 calc-stack))) "2 x"))
  (call-interactively 'mafcmd-unwrap)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "sin(2 x)"))
  (calc-clear-selections)
  (calc-pop 1)

  ;; A selection that does fit still unwraps in place, and the
  ;; unwrapped result stays selected.
  (maf-push "y + sin(x)")
  (progn (goto-char (point-min)) (search-forward "sin") (backward-char 2))
  (call-interactively 'calc-select-here)
  (call-interactively 'mafcmd-unwrap)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "y + x"))
  (cl-assert (string= (math-format-value (nth 2 (nth 1 calc-stack))) "x"))
  (calc-clear-selections)
  (calc-pop 1)

  ;; A region covering a chain run has no node to peel -- the run is
  ;; carved from the chain, not a sub-formula -- so the entry stands.
  (maf-push "a + sin(2 x) + c")
  (progn (calc-cursor-stack-index 1)
         (search-forward "sin(2 x) + c" (line-end-position))
         (goto-char (match-beginning 0))
         (push-mark (match-end 0) t t)
         (call-interactively 'mafcmd-unwrap))
  (cl-assert (= (calc-stack-size) 1))
  (cl-assert (string= (math-format-value (calc-top 1 'full))
                      "a + sin(2 x) + c"))
  (calc-pop 1)

  ;; A region covering exactly one node resolves as a sub-formula, and
  ;; peels as one.
  (maf-push "a + sin(2 x)")
  (progn (calc-cursor-stack-index 1)
         (search-forward "sin(2 x)" (line-end-position))
         (goto-char (match-beginning 0))
         (push-mark (match-end 0) t t)
         (call-interactively 'mafcmd-unwrap))
  (cl-assert (= (calc-stack-size) 1))
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "a + 2 x"))
  (calc-pop 1)

  ;; Point on a sub-formula inside a relation targets that sub-formula,
  ;; so the relation survives rather than coming apart into its sides.
  (maf-push "x = sin(y)")
  (progn (goto-char (point-min)) (search-forward "sin") (backward-char 2))
  (call-interactively 'mafcmd-unwrap)
  (cl-assert (= (calc-stack-size) 1))
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "x = y"))
  (calc-pop 1)

  ;; Keep-args at a widened sub-formula: the peeled entry goes on top,
  ;; the original stays beneath it.
  (maf-push "y + sin(2 x)")
  (progn (goto-char (point-min)) (search-forward "2 x") (backward-char 1))
  (call-interactively 'calc-keep-args)
  (call-interactively 'mafcmd-unwrap)
  (cl-assert (= (calc-stack-size) 2))
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "y + 2 x"))
  (cl-assert (string= (math-format-value (calc-top 2 'full)) "y + sin(2 x)"))
  (calc-pop 2)

  ;; Widening walks the formula, not the glyphs, so big-language display
  ;; peels the same wrapper.
  (maf-push "y + sin(2 x)")
  (call-interactively 'maf-toggle-big-language)
  (progn (goto-char (point-min)) (search-forward "2 x") (backward-char 1))
  (call-interactively 'mafcmd-unwrap)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "y + 2 x"))
  (call-interactively 'maf-toggle-big-language)
  (calc-pop 1)

  ;; A whole entry has room for every part, and there the command reads
  ;; as mafcmd-unpack does: one stack entry per part.
  (maf-push "[x, y]")
  (goto-char (point-max))
  (call-interactively 'mafcmd-unwrap)
  (cl-assert (= (calc-stack-size) 2))
  (cl-assert (string= (math-format-value (calc-top 2 'full)) "x"))
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "y"))
  (calc-pop 2)

  ;; A relation at the entry is a function call like any other, so it
  ;; comes apart into its two sides rather than mapping per side.
  (maf-push "x = sin(y)")
  (progn (goto-char (point-min)) (end-of-line))
  (call-interactively 'mafcmd-unwrap)
  (cl-assert (= (calc-stack-size) 2))
  (cl-assert (string= (math-format-value (calc-top 2 'full)) "x"))
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "sin(y)"))
  (calc-pop 2)

  ;; Degenerate: a bare variable has nothing to give and commits
  ;; unchanged rather than signaling. Assert on the raw structure --
  ;; non-alteration is the contract, so it must not be re-wrapped.
  (maf-push "x")
  (goto-char (point-max))
  (call-interactively 'mafcmd-unwrap)
  (cl-assert (= (calc-stack-size) 1))
  (cl-assert (equal (calc-top 1 'full) '(var x var-x)))
  (calc-pop 1)

  ;; A positive prefix argument unwraps that many levels deep.
  (maf-push "[(1,2),(3,4)]")
  (goto-char (point-max))
  (let ((current-prefix-arg 2)) (call-interactively 'mafcmd-unwrap))
  (cl-assert (= (calc-stack-size) 4))
  (cl-assert (equal (mapcar (lambda (i) (calc-top i 'full)) '(4 3 2 1))
                    '(1 2 3 4)))
  (calc-pop 4)

  ;; The prefix argument reaches the widening predicate too, not just
  ;; the body: at -1 a complex splits by component type into two parts,
  ;; which no formula slot holds, so the sub-formula stands unchanged
  ;; instead of resolve widening to a node the body would decline.
  (maf-push "y + (2,3)")
  (progn (goto-char (point-min)) (search-forward "(2,") (backward-char 2))
  (let ((current-prefix-arg -1)) (call-interactively 'mafcmd-unwrap))
  (cl-assert (= (calc-stack-size) 1))
  (cl-assert (equal (calc-top 1 'full) '(+ (var y var-y) (cplx 2 3))))
  (calc-pop 1)

  ;; A mode the expression does not fit is a no-op, not an error: -3
  ;; wants an HMS form. The entry must survive untouched.
  (maf-push "(2,3)")
  (goto-char (point-max))
  (let ((current-prefix-arg -3)) (call-interactively 'mafcmd-unwrap))
  (cl-assert (= (calc-stack-size) 1))
  (cl-assert (equal (calc-top 1 'full) '(cplx 2 3)))
  (calc-pop 1))
