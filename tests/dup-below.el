;; `maf-dup-below' is a real command (src/stack.el), so these steps drive
;; it directly. A step passes when it raises no error. The contract: the
;; subject point names — sub-formula, selection, region run, whole entry
;; — is copied verbatim onto the top of the stack, and point travels to
;; the copy, leaving a mark at the origin.

(maf-step
  ;; mid-stack: the copy lands on top, the originals keep their order
  ;; (each one level up), and point travels to the copy.
  (maf-push "w") (maf-push "x") (maf-push "y") (maf-push "z")  ; 4:w 3:x 2:y 1:z
  (progn (goto-char (point-min)) (forward-line 1) (end-of-line))   ; on 3: x
  (call-interactively 'maf-dup-below)
  (cl-assert (equal (mapcar (lambda (i) (math-format-value (calc-top i 'full)))
                            (number-sequence 1 5))
                    '("x" "z" "y" "x" "w")))   ; copy on top, original at 4
  (cl-assert (= (calc-stack-size) 5))
  ;; point travelled to the copy on top, not the original (now at level 4)
  (cl-assert (= (calc-locate-cursor-element (point)) 1))
  ;; the mark holds the origin: a single pop returns to the original
  (progn (pop-to-mark-command)
         (cl-assert (= (calc-locate-cursor-element (point)) 4)))
  (calc-pop (calc-stack-size))

  ;; The copy is structurally identical to the source, not a re-read.
  (maf-push "a + b c") (maf-push "z")
  (progn (goto-char (point-min)) (end-of-line))
  (call-interactively 'maf-dup-below)
  (cl-assert (equal (calc-top 1 'full) (calc-top 3 'full)))
  (calc-pop (calc-stack-size))

  ;; --- point picks the subject, as it does everywhere else in maf ---

  ;; subexpr: the sub-formula under point is lifted out onto the top,
  ;; as `maf-dup' would lift it.
  (maf-push "(a + b) c") (maf-push "z")
  (progn (goto-char (point-min)) (beginning-of-line)
         (search-forward "a") (backward-char 1))
  (call-interactively 'maf-dup-below)
  (cl-assert (equal (mapcar (lambda (i) (math-format-value (calc-top i 'full)))
                            (number-sequence 1 3))
                    '("a" "z" "(a + b) c")))
  ;; the copy stands on its own, so there is no place within the entry
  ;; to keep: point lands at the start of the copy's formula text
  (cl-assert (= (calc-locate-cursor-element (point)) 1))
  (cl-assert (= (current-column) 4))
  (cl-assert (looking-at "a"))
  (calc-pop (calc-stack-size))

  ;; a sub-formula that spans its whole entry renders exactly like it,
  ;; so point keeps its place rather than dropping to the start
  (maf-push "a + b") (maf-push "z")
  (progn (goto-char (point-min)) (beginning-of-line)
         (search-forward "+") (backward-char 1))
  (call-interactively 'maf-dup-below)
  (cl-assert (equal (mapcar (lambda (i) (math-format-value (calc-top i 'full)))
                            (number-sequence 1 3))
                    '("a + b" "z" "a + b")))
  (cl-assert (= (calc-locate-cursor-element (point)) 1))
  (cl-assert (looking-at "\\+"))
  (calc-pop (calc-stack-size))

  ;; a calc selection is the subject when there is one
  (maf-push "(a + b) c") (maf-push "z")
  (progn (goto-char (point-min)) (beginning-of-line)
         (search-forward "+") (backward-char 1) (calc-select-here nil))
  (call-interactively 'maf-dup-below)
  (cl-assert (string= (math-format-value (maf--strip-encasing (calc-top 1 'full)))
                      "a + b"))
  (cl-assert (= (calc-locate-cursor-element (point)) 1))
  (calc-clear-selections)
  (calc-pop (calc-stack-size))

  ;; a region's run of chain terms, copied as one entry. The harness
  ;; deactivates the mark around every form, so the region is set and
  ;; the command fired in a single form, as in real use.
  (maf-push "a + b + c") (maf-push "z")
  (progn (calc-cursor-stack-index 2)
         (search-forward "b + c" (line-end-position))
         (goto-char (match-beginning 0))
         (push-mark (match-end 0) t t)
         (call-interactively 'maf-dup-below))
  (cl-assert (equal (mapcar (lambda (i) (math-format-value (calc-top i 'full)))
                            (number-sequence 1 3))
                    '("b + c" "z" "a + b + c")))
  (cl-assert (= (calc-locate-cursor-element (point)) 1))
  (calc-pop (calc-stack-size))

  ;; a selection names its own entry, wherever point rests: the subject
  ;; comes from the selected entry, the copy still lands on top
  (maf-push "(a + b) c") (maf-push "z")
  (progn (goto-char (point-min)) (beginning-of-line)
         (search-forward "+") (backward-char 1) (calc-select-here nil)
         (goto-char (point-max)) (forward-line 0))
  (call-interactively 'maf-dup-below)
  (cl-assert (equal (mapcar (lambda (i) (math-format-value
                                         (maf--strip-encasing (calc-top i 'full))))
                            (number-sequence 1 3))
                    '("a + b" "z" "(a + b) c")))
  ;; point was at home, never on the entry that was copied, so it stays
  (cl-assert (maf--at-home-p))
  (calc-clear-selections)
  (calc-pop (calc-stack-size))

  ;; a relation copies whole, not once per side
  (maf-push "x = y") (maf-push "z")
  (progn (goto-char (point-min)) (end-of-line))
  (call-interactively 'maf-dup-below)
  (cl-assert (equal (mapcar (lambda (i) (math-format-value (calc-top i 'full)))
                            (number-sequence 1 3))
                    '("x = y" "z" "x = y")))
  (calc-pop (calc-stack-size))

  ;; A multi-line rendering: the fraction bar is the whole entry's own
  ;; glyph, so the copy renders alike and point keeps its row within it,
  ;; landing on the copy's fraction bar rather than its first line.
  (calc-big-language)
  (maf-push "(a + b) / (c + d)") (maf-push "z")
  (progn (goto-char (point-min)) (forward-line 1)
         (beginning-of-line) (forward-char 4))
  (cl-assert (looking-at "-"))                  ; the fraction bar, row 1
  (call-interactively 'maf-dup-below)
  (cl-assert (= (calc-locate-cursor-element (point)) 1))   ; the copy
  (cl-assert (looking-at "-"))                  ; same row within it
  (cl-assert (= (current-column) 4))
  (calc-normal-language)
  (calc-pop (calc-stack-size))

  ;; on the top entry the copy stacks right on it, and point steps down
  (maf-push "p") (maf-push "q")                 ; 2:p 1:q
  (progn (calc-cursor-stack-index 1) (end-of-line))
  (call-interactively 'maf-dup-below)
  (cl-assert (equal (mapcar (lambda (i) (math-format-value (calc-top i 'full)))
                            (number-sequence 1 3))
                    '("q" "q" "p")))
  ;; the copy landed on top and point followed it there
  (cl-assert (= (calc-locate-cursor-element (point)) 1))
  (calc-pop (calc-stack-size))

  ;; at home the top entry is the subject, as `maf-dup' does there
  (maf-push "p") (maf-push "q")
  (progn (goto-char (point-max)) (forward-line 0))
  (call-interactively 'maf-dup-below)
  (cl-assert (equal (mapcar (lambda (i) (math-format-value (calc-top i 'full)))
                            (number-sequence 1 3))
                    '("q" "q" "p")))
  (cl-assert (maf--at-home-p))
  (calc-pop (calc-stack-size))

  ;; an empty stack has nothing to duplicate
  (cl-assert (string-match-p "Stack is empty"
                             (condition-case e
                                 (progn (call-interactively 'maf-dup-below) "")
                               (error (error-message-string e)))))

  ;; --- keep-args makes no difference: the copy is verbatim either way ---
  (maf-push "a") (maf-push "b")                 ; 2:a 1:b
  (progn (goto-char (point-min)) (end-of-line))
  (let ((calc-keep-args-flag t))
    (call-interactively 'maf-dup-below))
  (cl-assert (equal (mapcar (lambda (i) (math-format-value (calc-top i 'full)))
                            (number-sequence 1 3))
                    '("a" "b" "a")))
  (calc-pop (calc-stack-size))

  ;; --- a single undo reverts the copy and restores point ---
  (maf-push "w") (maf-push "x") (maf-push "y") (maf-push "z")
  (progn (goto-char (point-min)) (forward-line 1) (end-of-line))
  (call-interactively 'maf-dup-below)
  (cl-assert (= (calc-stack-size) 5))
  ;; last-command is set as the command loop would (the harness can't),
  ;; so the undo takes the pre-command-point path rather than the chained
  ;; one a leftover `maf-undo' from an earlier test would select.
  (progn (setq last-command nil) (call-interactively 'maf-undo))
  (cl-assert (= (calc-stack-size) 4))
  (cl-assert (equal (mapcar (lambda (i) (math-format-value (calc-top i 'full)))
                            (number-sequence 1 4))
                    '("z" "y" "x" "w")))
  ;; undo restores point along with the stack
  (cl-assert (= (calc-locate-cursor-element (point)) 3))
  (calc-pop (calc-stack-size)))
