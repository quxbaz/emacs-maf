;;; Tests for maf-go-home -- the motion back to the . line.

(defvar maf-test--origin nil
  "Buffer position a `maf-go-home' press left, for the mark-ring checks.")

(maf-step
  ;; calc-wrapper's epilogue renumbers the display; raw pushes would
  ;; leave both entries rendered as level 1.
  (calc-wrapper (maf-push "6 x + 12") (maf-push "a + b"))

  ;; From inside an entry's formula: point lands on the dot, past the
  ;; margin, and resolve now sees home.
  (progn (goto-char (point-min)) (search-forward "6 x"))
  (cl-assert (not (maf--at-home-p)))
  (call-interactively 'maf-go-home)
  (cl-assert (looking-at "\\.$"))
  (cl-assert (maf--at-home-p))
  ;; The same spot calc parks point at after a command.
  (cl-assert (= (point) (progn (calc-wrapper nil) (point))))

  ;; From the line-number margin, and from end of line: same landing.
  (progn (goto-char (point-min)) (forward-char 1))
  (call-interactively 'maf-go-home)
  (cl-assert (looking-at "\\.$"))
  (progn (goto-char (point-min)) (end-of-line))
  (call-interactively 'maf-go-home)
  (cl-assert (looking-at "\\.$"))

  ;; The origin goes on the mark ring: C-u C-SPC comes back to the
  ;; sub-formula point left.
  (progn (goto-char (point-min)) (search-forward "6 x"))
  (setq maf-test--origin (point))
  (call-interactively 'maf-go-home)
  (cl-assert (= (mark t) maf-test--origin))
  (progn (goto-char (mark t)) (looking-back "6 x" (line-beginning-position)))
  (cl-assert (= (point) maf-test--origin))

  ;; Already home: idempotent, dot included, and the ring is left alone —
  ;; the mark still points at the entry, not at home.
  (progn (call-interactively 'maf-go-home) (call-interactively 'maf-go-home))
  (cl-assert (looking-at "\\.$"))
  (cl-assert (maf--at-home-p))
  (cl-assert (= (mark t) maf-test--origin))

  ;; A region is left standing: its anchor stays where the user set it,
  ;; so the selection survives the trip home. Setting the region and
  ;; making the trip go in one form — the cockpit runs each form as a
  ;; command, and the mark would be deactivated between two of them.
  (progn (goto-char (point-min)) (search-forward "6 x")
         (push-mark (point) t t) (end-of-line)
         (setq maf-test--origin (mark t))
         (cl-assert (use-region-p))
         (call-interactively 'maf-go-home)
         (cl-assert (= (mark t) maf-test--origin))
         (deactivate-mark)
         nil)

  ;; An empty active mark is not a region — `calc-refresh' leaves one on
  ;; every redraw — so the push still happens, from where point was.
  (progn (goto-char (point-min)) (search-forward "6 x")
         (setq maf-test--origin (point))
         (push-mark (point) t t)
         (cl-assert (not (use-region-p)))
         (call-interactively 'maf-go-home)
         (cl-assert (= (mark t) maf-test--origin))
         (deactivate-mark)
         nil)

  ;; Below the dot — the blank tail of the buffer — comes home too.
  (goto-char (point-max))
  (call-interactively 'maf-go-home)
  (cl-assert (looking-at "\\.$"))

  ;; With line numbering off there is no margin to skip: the dot sits at
  ;; the start of the line.
  (calc-line-numbering 0)
  (progn (goto-char (point-min)) (end-of-line))
  (call-interactively 'maf-go-home)
  (cl-assert (looking-at "\\.$"))
  (cl-assert (= (current-column) 0))
  (calc-line-numbering 1)

  ;; An empty stack is all home.
  (calc-pop (calc-stack-size))
  (goto-char (point-min))
  (call-interactively 'maf-go-home)
  (cl-assert (looking-at "\\.$"))
  (cl-assert (maf--at-home-p)))
