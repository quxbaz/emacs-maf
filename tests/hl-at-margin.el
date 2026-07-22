(defun maf-hl-test--text ()
  "Text under the maf-hl overlay, or nil if no highlight is shown."
  (and maf-hl--overlay (overlay-buffer maf-hl--overlay)
       (buffer-substring-no-properties (overlay-start maf-hl--overlay)
                                       (overlay-end maf-hl--overlay))))

(maf-step
  (calc-push '(+ (var a var-a) (* (var b var-b) (var c var-c))))   ; a + b c
  (maf-hl-mode 1)

  ;; In the line-number prefix zone: the whole entry is highlighted.
  (progn (calc-cursor-stack-index 1) (beginning-of-line) (forward-char 1)
         (maf-hl--update))
  (cl-assert (equal (maf-hl-test--text) "a + b c"))

  ;; At end of line: the whole entry too.
  (progn (calc-cursor-stack-index 1) (end-of-line) (maf-hl--update))
  (cl-assert (equal (maf-hl-test--text) "a + b c"))

  ;; Inside the formula, the sub-formula under point still wins.
  (progn (calc-cursor-stack-index 1) (beginning-of-line)
         (search-forward "b") (backward-char 1) (maf-hl--update))
  (cl-assert (equal (maf-hl-test--text) "b"))

  ;; A multi-line entry (matrix) has no single flat range, so even at the
  ;; margin nothing is highlighted.
  (calc-push '(vec (vec 1 2) (vec 3 4)))
  (progn (calc-cursor-stack-index 1) (end-of-line) (maf-hl--update))
  (cl-assert (null (maf-hl-test--text)))
  (calc-pop 1)

  ;; Home (past the last entry): still nothing.
  (progn (goto-char (point-max)) (maf-hl--update))
  (cl-assert (null (maf-hl-test--text)))

  (maf-hl-mode -1)
  (cl-assert (null (maf-hl-test--text))))
