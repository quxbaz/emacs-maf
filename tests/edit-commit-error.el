(maf-step
  ;; A blocked commit leaves point alone when point is already inside
  ;; the offending entry — the mid-typing case: the unclosed fraction
  ;; that failed to parse is the one being typed.
  (maf-push "a + 1")
  (progn (calc-cursor-stack-index 1) (end-of-line) nil)
  (call-interactively 'maf-edit)
  (progn (execute-kbd-macro "+3;") nil)       ; a + 1+3: — no denominator
  (let ((before (point)))
    (cl-assert (eq :error (condition-case nil
                              (progn (call-interactively 'maf-edit-commit) :ok)
                            (error :error))))
    (cl-assert (= (point) before)))
  (cl-assert maf-edit-mode)                   ; editing continues
  (cl-assert (= (calc-stack-size) 1))         ; stack untouched
  (call-interactively 'maf-edit-discard)
  (calc-pop (calc-stack-size))

  ;; From anywhere else, point goes to the first offender — onto its
  ;; first content column, never into the machine-owned prefix.
  (maf-push "a")
  (maf-push "b")
  (progn (calc-cursor-stack-index 2) (end-of-line) nil)
  (call-interactively 'maf-edit)
  (progn (execute-kbd-macro ";") nil)         ; level 2 becomes a:
  (progn (goto-char (point-min)) (forward-line 1) (end-of-line) nil)
  (progn (ignore-errors (call-interactively 'maf-edit-commit)) nil)
  (cl-assert (= (line-number-at-pos) 1))
  (cl-assert (= (current-column) maf-edit--prefix-width))
  (call-interactively 'maf-edit-discard)
  (calc-pop (calc-stack-size)))
