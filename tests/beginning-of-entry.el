(maf-step
  ;; Stack entry: from EOL, point lands on the formula, right after
  ;; the line-number prefix.
  ;; calc-wrapper's epilogue renumbers the display; raw pushes would
  ;; leave both entries rendered as level 1.
  (calc-wrapper (maf-push "6 x + 12") (maf-push "a + b"))
  (progn (goto-char (point-min)) (search-forward "6 x + 12") (end-of-line))
  (call-interactively 'maf-beginning-of-entry)
  (cl-assert (looking-at "6 x \\+ 12"))
  (cl-assert (looking-back "2:  " (line-beginning-position)))

  ;; From inside the prefix, same landing spot.
  (progn (beginning-of-line) (forward-char 1))
  (call-interactively 'maf-beginning-of-entry)
  (cl-assert (looking-at "6 x \\+ 12"))

  ;; Home line: after the leading indentation, on the dot.
  (progn (goto-char (point-max)) (forward-line -1))
  (call-interactively 'maf-beginning-of-entry)
  (cl-assert (looking-at "\\.$"))
  (calc-pop (calc-stack-size)))
