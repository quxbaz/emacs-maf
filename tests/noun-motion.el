(maf-step
  ;; Two entries, so the motion has a line boundary to cross.
  ;; calc-wrapper's epilogue renumbers the display; raw pushes would
  ;; leave both entries rendered as level 1.
  (calc-wrapper (maf-push "sqrt(x) + 12") (maf-push "6 x + 12"))

  ;; A function name is a noun of its own — point on it names the call —
  ;; and its argument is the stop after it. The operators between them
  ;; are what the motion crosses.
  (progn (goto-char (point-min)) (call-interactively 'maf-beginning-of-entry))
  (cl-assert (looking-at "sqrt"))
  (call-interactively 'maf-forward-noun)
  (cl-assert (looking-at "x) \\+ 12"))
  (call-interactively 'maf-forward-noun)
  (cl-assert (looking-at "12$"))

  ;; Crossing into the entry below steps over the line-number prefix:
  ;; the level number is the margin, not a term.
  (call-interactively 'maf-forward-noun)
  (cl-assert (looking-at "6 x"))
  (cl-assert (looking-back "1:  " (line-beginning-position)))

  ;; Past the last noun there is nowhere to go — the home line holds no
  ;; term — and the motion signals rather than moving.
  (progn (call-interactively 'maf-forward-noun) (call-interactively 'maf-forward-noun))
  (cl-assert (looking-at "12$"))
  (cl-assert (eq 'signalled
                 (condition-case nil
                     (progn (call-interactively 'maf-forward-noun) 'moved)
                   (user-error 'signalled))))

  ;; Backward retraces the same stops, prefix and function name alike.
  (call-interactively 'maf-backward-noun)
  (cl-assert (looking-at "x \\+ 12"))
  (call-interactively 'maf-backward-noun)
  (cl-assert (looking-at "6 x"))
  (call-interactively 'maf-backward-noun)
  (cl-assert (looking-at "12$"))
  (cl-assert (= (calc-locate-cursor-element (point)) 2))

  ;; From inside a noun the step back lands on its own start, as
  ;; `backward-word' does, rather than skipping to the noun before it.
  (progn (goto-char (point-min)) (search-forward "12") (backward-char 1))
  (call-interactively 'maf-backward-noun)
  (cl-assert (looking-at "12$"))

  ;; A numeric prefix moves that many nouns at once; a negative one
  ;; turns the motion around.
  (progn (goto-char (point-min)) (call-interactively 'maf-beginning-of-entry))
  (let ((current-prefix-arg 3)) (call-interactively 'maf-forward-noun))
  (cl-assert (looking-at "6 x"))
  (let ((current-prefix-arg -2)) (call-interactively 'maf-forward-noun))
  (cl-assert (looking-at "x) \\+ 12"))

  ;; Before the first noun the backward motion signals in turn.
  (progn (goto-char (point-min)) (call-interactively 'maf-beginning-of-entry))
  (cl-assert (eq 'signalled
                 (condition-case nil
                     (progn (call-interactively 'maf-backward-noun) 'moved)
                   (user-error 'signalled))))
  (calc-pop (calc-stack-size))

  ;; Approaching a function from before it, the name is where the press
  ;; lands, and its argument is the press after — so the walk reaches
  ;; the call and its parts both, and retraces the same way back.
  (maf-push "1 + sqrt(x)")
  (progn (goto-char (point-min)) (call-interactively 'maf-beginning-of-entry))
  (cl-assert (looking-at "1 \\+ sqrt"))
  (call-interactively 'maf-forward-noun)
  (cl-assert (looking-at "sqrt"))
  (call-interactively 'maf-forward-noun)
  (cl-assert (looking-at "x)$"))
  (call-interactively 'maf-backward-noun)
  (cl-assert (looking-at "sqrt"))
  (calc-pop (calc-stack-size))

  ;; A number calc prints in several pieces is one noun: the fraction
  ;; 3:4 (whose : is not the prefix's), the subscripted b_1, the float
  ;; 1. (whose trailing point has no digits after it).
  (maf-push "[3:4, b_1, 1.0]")
  (cl-assert (save-excursion (goto-char (point-min))
                             (looking-at "1:  \\[3:4, b_1, 1\\.\\]$")))
  (progn (goto-char (point-min)) (call-interactively 'maf-beginning-of-entry))
  (call-interactively 'maf-forward-noun)
  (cl-assert (looking-at "3:4,"))
  (call-interactively 'maf-forward-noun)
  (cl-assert (looking-at "b_1,"))
  (call-interactively 'maf-forward-noun)
  (cl-assert (looking-at "1\\.\\]"))
  (calc-pop (calc-stack-size))

  ;; Big language: the motion reads whatever calc printed, so it walks
  ;; an entry drawn over four lines the same way. Here the sqrt is drawn
  ;; rather than named, so there is no name to stop on — and its overbar,
  ;; a run of underscores, is passed over like any other glyph, no noun
  ;; starting with one.
  (maf-push "(a + 1) / sqrt(b 2)")
  (call-interactively 'maf-toggle-big-language)
  (cl-assert (eq calc-language 'big))
  (goto-char (point-min))
  (call-interactively 'maf-forward-noun)
  (cl-assert (looking-at "a \\+ 1"))
  (call-interactively 'maf-forward-noun)
  (cl-assert (looking-at "1$"))
  (call-interactively 'maf-forward-noun)
  (cl-assert (looking-at "b 2"))
  (call-interactively 'maf-forward-noun)
  (cl-assert (looking-at "2$"))
  (cl-assert (eq 'signalled
                 (condition-case nil
                     (progn (call-interactively 'maf-forward-noun) 'moved)
                   (user-error 'signalled))))
  (call-interactively 'maf-toggle-big-language)
  (calc-pop (calc-stack-size)))
