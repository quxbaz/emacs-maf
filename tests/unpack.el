(maf-step
  ;; The entry-scoped command holds M-u and v u (calc-unpack, whose
  ;; whole-entry behavior it matches). j U and j M-U -- calc's own
  ;; calc-sel-unpack keys -- take the narrowing sibling instead; that
  ;; command has its own file, unwrap.el. Assert on resolution rather
  ;; than driving the keys: calc's fancy prefixes do not survive
  ;; execute-kbd-macro, which is why the j-prefix commands are called
  ;; directly throughout these tests.
  (cl-assert (eq (key-binding (kbd "M-u")) 'mafcmd-unpack))
  (cl-assert (eq (key-binding (kbd "v u")) 'mafcmd-unpack))
  (cl-assert (eq (key-binding (kbd "j U")) 'mafcmd-unwrap))
  (cl-assert (eq (key-binding (kbd "j M-U")) 'mafcmd-unwrap))
  ;; The j prefix still falls through to calc's own selection commands.
  (cl-assert (eq (key-binding (kbd "j s")) 'calc-select-here))

  ;; Home: a vector spreads one element per stack entry.
  (maf-push "[x, y]")
  (goto-char (point-max))
  (call-interactively 'mafcmd-unpack)
  (cl-assert (= (calc-stack-size) 2))
  (cl-assert (string= (math-format-value (calc-top 2 'full)) "x"))
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "y"))
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

  ;; The subject is always the whole entry: point inside a formula does
  ;; not narrow to the node it sits on. On sin here, the entry's sum
  ;; comes apart, not the sin call.
  (maf-push "y + sin(x)")
  (progn (goto-char (point-min)) (search-forward "sin") (backward-char 2))
  (call-interactively 'mafcmd-unpack)
  (cl-assert (= (calc-stack-size) 2))
  (cl-assert (string= (math-format-value (calc-top 2 'full)) "y"))
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "sin(x)"))
  (calc-pop 2)

  ;; Same from deep inside a nested call: whatever the position, one
  ;; level of the entry comes off. A single wrapper gives a single
  ;; part, so the entry count does not change.
  (maf-push "sin(cos(x))")
  (progn (goto-char (point-min)) (search-forward "(x)") (backward-char 2))
  (call-interactively 'mafcmd-unpack)
  (cl-assert (= (calc-stack-size) 1))
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "cos(x)"))
  (calc-pop 1)

  ;; A product entry splits into its factors from anywhere inside it.
  (maf-push "(a + b) (2 c - d)")
  (progn (goto-char (point-min)) (search-forward "a") (backward-char 1))
  (call-interactively 'mafcmd-unpack)
  (cl-assert (= (calc-stack-size) 2))
  (cl-assert (string= (math-format-value (calc-top 2 'full)) "a + b"))
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "2 c - d"))
  (calc-pop 2)

  ;; The entry at point, not the top: unpacking a lower entry spreads
  ;; its parts in place, beneath the entries above it.
  (maf-push "[1, 2]")
  (maf-push "z")
  (progn (calc-cursor-stack-index 2) (end-of-line))
  (call-interactively 'mafcmd-unpack)
  (cl-assert (= (calc-stack-size) 3))
  (cl-assert (equal (calc-top 3 'full) 1))
  (cl-assert (equal (calc-top 2 'full) 2))
  (cl-assert (equal (calc-top 1 'full) '(var z var-z)))
  (calc-pop 3)

  ;; An explicit calc selection does not narrow the subject either --
  ;; parts spread over the stack, and a formula slot has no room for
  ;; that -- so the selection's entry comes apart whole, the selection
  ;; gone with it.
  (maf-push "y + sin(x)")
  (progn (goto-char (point-min)) (search-forward "sin") (backward-char 2))
  (call-interactively 'calc-select-here)
  (cl-assert (string= (math-format-value (nth 2 (nth 1 calc-stack))) "sin(x)"))
  (call-interactively 'mafcmd-unpack)
  (cl-assert (= (calc-stack-size) 2))
  (cl-assert (string= (math-format-value (calc-top 2 'full)) "y"))
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "sin(x)"))
  (cl-assert (null (nth 2 (nth 1 calc-stack))))
  (calc-pop 2)

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

  ;; Point on a sub-formula inside a relation is the same gesture as
  ;; anywhere else on the entry: the relation comes apart.
  (maf-push "x = sin(y)")
  (progn (goto-char (point-min)) (search-forward "sin") (backward-char 2))
  (call-interactively 'mafcmd-unpack)
  (cl-assert (= (calc-stack-size) 2))
  (cl-assert (string= (math-format-value (calc-top 2 'full)) "x"))
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "sin(y)"))
  (calc-pop 2)

  ;; A region is bypassed like the other narrowing gestures: the entry
  ;; it lies on comes apart, one level.
  (maf-push "a + sin(2 x) + c")
  (progn (calc-cursor-stack-index 1)
         (search-forward "sin(2 x)" (line-end-position))
         (goto-char (match-beginning 0))
         (push-mark (match-end 0) t t)
         (call-interactively 'mafcmd-unpack))
  (cl-assert (= (calc-stack-size) 2))
  (cl-assert (string= (math-format-value (calc-top 2 'full)) "a + sin(2 x)"))
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "c"))
  (calc-pop 2)

  ;; Keep-args with point inside the formula: the parts go on top, the
  ;; original entry stays beneath them.
  (maf-push "y + sin(2 x)")
  (progn (goto-char (point-min)) (search-forward "2 x") (backward-char 1))
  (call-interactively 'calc-keep-args)
  (call-interactively 'mafcmd-unpack)
  (cl-assert (= (calc-stack-size) 3))
  (cl-assert (string= (math-format-value (calc-top 3 'full)) "y + sin(2 x)"))
  (cl-assert (string= (math-format-value (calc-top 2 'full)) "y"))
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "sin(2 x)"))
  (calc-pop 3)

  ;; Big-language display resolves the same entry, so the same split.
  (maf-push "y + sin(2 x)")
  (call-interactively 'maf-toggle-big-language)
  (progn (goto-char (point-min)) (search-forward "2 x") (backward-char 1))
  (call-interactively 'mafcmd-unpack)
  (cl-assert (= (calc-stack-size) 2))
  (cl-assert (string= (math-format-value (calc-top 2 'full)) "y"))
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "sin(2 x)"))
  (call-interactively 'maf-toggle-big-language)
  (calc-pop 2)

  ;; A positive prefix argument unwraps that many levels deep.
  (maf-push "[(1,2),(3,4)]")
  (goto-char (point-max))
  (let ((current-prefix-arg 2)) (call-interactively 'mafcmd-unpack))
  (cl-assert (= (calc-stack-size) 4))
  (cl-assert (equal (mapcar (lambda (i) (calc-top i 'full)) '(4 3 2 1))
                    '(1 2 3 4)))
  (calc-pop 4)

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

  ;; Keep-args leaves the original beneath the parts.
  (maf-push "a + b")
  (goto-char (point-max))
  (call-interactively 'calc-keep-args)
  (call-interactively 'mafcmd-unpack)
  (cl-assert (= (calc-stack-size) 3))
  (cl-assert (string= (math-format-value (calc-top 3 'full)) "a + b"))
  (cl-assert (string= (math-format-value (calc-top 2 'full)) "a"))
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "b"))
  (calc-pop 3))
