;;; Tests for maf-go-home -- the round trip between an entry and the . line.

(defvar maf-test--origin nil
  "Buffer position a `maf-go-home' press left, for the mark checks.")

(defvar maf-test--mark nil
  "The mark as it stood before a trip home, for the ring checks.")

(defvar maf-test--ring nil
  "Length of `mark-ring' before a trip home, for the ring checks.")

(maf-step
  ;; calc-wrapper's epilogue renumbers the display; raw pushes would
  ;; leave both entries rendered as level 1.
  (calc-wrapper (maf-push "6 x + 12") (maf-push "a + b"))

  ;; --- The trip out ---

  ;; From inside an entry's formula: point lands on the dot, past the
  ;; margin, and resolve now sees home.
  (progn (goto-char (point-min)) (search-forward "6 x"))
  (cl-assert (not (maf--at-home-p)))
  (setq maf-test--origin (point))
  (call-interactively 'maf-go-home)
  (cl-assert (looking-at "\\.$"))
  (cl-assert (maf--at-home-p))
  ;; The same spot calc parks point at after a command.
  (cl-assert (= (point) (progn (calc-wrapper nil) (point))))
  ;; The place point left is marked, so C-u C-SPC reaches it too.
  (cl-assert (= (mark t) maf-test--origin))

  ;; --- The trip back ---

  ;; Pressed at home, the same key returns to that mark — a stack
  ;; rewrite in between and all, since a mark is a marker.
  (calc-wrapper (calc-push (math-read-expr "7")) (calc-pop 1))
  (call-interactively 'maf-go-home)
  (cl-assert (= (point) maf-test--origin))
  (cl-assert (looking-back "6 x" (line-beginning-position)))
  ;; The mark is spent: it does not stay where point now is.
  (cl-assert (not (and (mark t) (= (mark t) maf-test--origin))))
  ;; And home is marked in neither direction.
  (cl-assert (not (and (mark t) (save-excursion (goto-char (mark t))
                                                (maf--at-home-p)))))

  ;; Either end, as many times as it is pressed.
  (call-interactively 'maf-go-home)
  (cl-assert (maf--at-home-p))
  (call-interactively 'maf-go-home)
  (cl-assert (= (point) maf-test--origin))

  ;; --- The ring is left as deep as it was found ---

  ;; A mark the user set before the trip is back afterwards, with the
  ;; ring no deeper than it started: the trip's own mark is gone, not
  ;; rotated to the tail as `pop-mark' would leave it.
  (progn (goto-char (point-min)) (push-mark (point) t) (deactivate-mark)
         (setq maf-test--mark (mark t)
               maf-test--ring (length mark-ring))
         nil)
  (progn (goto-char (point-min)) (search-forward "6 x")
         (setq maf-test--origin (point)) nil)
  (call-interactively 'maf-go-home)
  (cl-assert (= (mark t) maf-test--origin))
  (cl-assert (= (length mark-ring) (1+ maf-test--ring)))
  (call-interactively 'maf-go-home)
  (cl-assert (= (mark t) maf-test--mark))
  (cl-assert (= (length mark-ring) maf-test--ring))

  ;; The older mark came through the round trip intact: C-u C-SPC still
  ;; walks to it. (The trip itself always returns to where it last left,
  ;; never further back.)
  (call-interactively 'pop-to-mark-command)
  (cl-assert (= (point) maf-test--mark))

  ;; --- The bounce fires from the dot alone ---

  ;; At home but off the dot, a press with a live mark does not bounce:
  ;; it only tidies point onto the dot. The next press, from the dot,
  ;; makes the return trip.
  (progn (goto-char (point-min)) (search-forward "6 x")
         (setq maf-test--origin (point)) nil)
  (call-interactively 'maf-go-home)
  (progn (end-of-line) nil)
  (cl-assert (maf--at-home-p))
  (cl-assert (/= (point) (maf--home-dot-position)))
  (call-interactively 'maf-go-home)
  (cl-assert (looking-at "\\.$"))
  (cl-assert (= (mark t) maf-test--origin))
  (call-interactively 'maf-go-home)
  (cl-assert (= (point) maf-test--origin))

  ;; Same from below the home line, which also counts as home.
  (call-interactively 'maf-go-home)
  (progn (goto-char (point-max)) nil)
  (cl-assert (maf--at-home-p))
  (call-interactively 'maf-go-home)
  (cl-assert (looking-at "\\.$"))
  (call-interactively 'maf-go-home)
  (cl-assert (= (point) maf-test--origin))

  ;; --- Nothing to bounce to ---

  ;; A mark at home is no destination — the trip never leaves one there
  ;; — so the press only tidies point onto the dot.
  (progn (goto-char (point-max)) (push-mark (point) t) (deactivate-mark)
         (forward-line 0) nil)
  (cl-assert (maf--at-home-p))
  (call-interactively 'maf-go-home)
  (cl-assert (looking-at "\\.$"))
  (cl-assert (maf--at-home-p))

  ;; --- Landings ---

  ;; From the line-number margin, and from end of line: same dot.
  (progn (goto-char (point-min)) (forward-char 1))
  (call-interactively 'maf-go-home)
  (cl-assert (looking-at "\\.$"))
  (progn (goto-char (point-min)) (end-of-line))
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

  ;; --- Regions ---

  ;; A region is left standing on the way out: its anchor stays where
  ;; the user set it, so the selection survives the trip. Setting the
  ;; region and making the trip go in one form — the cockpit runs each
  ;; form as a command, and the mark would be deactivated between two.
  (progn (goto-char (point-min)) (search-forward "6 x")
         (push-mark (point) t t) (end-of-line)
         (setq maf-test--mark (mark t))
         (cl-assert (use-region-p))
         (call-interactively 'maf-go-home)
         (cl-assert (= (mark t) maf-test--mark))
         (cl-assert (maf--at-home-p))
         (deactivate-mark)
         nil)

  ;; And on the way back: a region up at home is not consumed for the
  ;; bounce — point stays home and the anchor keeps its place.
  (progn (goto-char (point-min)) (search-forward "6 x")
         (push-mark (point) t t)
         (goto-char (point-max))
         (setq maf-test--mark (mark t))
         (cl-assert (use-region-p))
         (cl-assert (maf--at-home-p))
         (call-interactively 'maf-go-home)
         (cl-assert (maf--at-home-p))
         (cl-assert (= (mark t) maf-test--mark))
         (deactivate-mark)
         nil)

  ;; An empty active mark is not a region — `calc-refresh' leaves one on
  ;; every redraw — so the trip out marks as usual, from where point was.
  (progn (goto-char (point-min)) (search-forward "6 x")
         (setq maf-test--origin (point))
         (push-mark (point) t t)
         (cl-assert (not (use-region-p)))
         (call-interactively 'maf-go-home)
         (cl-assert (= (mark t) maf-test--origin))
         (deactivate-mark)
         nil)

  ;; --- The empty stack ---

  ;; All home, and the marks left in it point at nothing else: the press
  ;; stays on the dot.
  (progn (calc-pop (calc-stack-size)) (goto-char (point-min)) nil)
  (call-interactively 'maf-go-home)
  (cl-assert (looking-at "\\.$"))
  (cl-assert (maf--at-home-p))
  (setq maf-test--origin (point))
  (call-interactively 'maf-go-home)
  (cl-assert (= (point) maf-test--origin)))
