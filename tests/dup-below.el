;; `maf-dup-below' is a real command (src/stack.el), so these steps drive
;; it directly. A step passes when it raises no error. The contract: the
;; whole entry at point is copied into the slot directly below it, the
;; copy is verbatim, point travels to the copy keeping its place inside
;; the entry, and the push and the roll are one undoable gesture.

(maf-step
  ;; mid-stack: the copy takes the level point was on and the original
  ;; bumps up one, so the two sit adjacent on screen. Entries below the
  ;; insertion keep their levels.
  (maf-push "w") (maf-push "x") (maf-push "y") (maf-push "z")  ; 4:w 3:x 2:y 1:z
  (progn (goto-char (point-min)) (forward-line 1) (end-of-line))   ; on 3: x
  (call-interactively 'maf-dup-below)
  (cl-assert (equal (mapcar (lambda (i) (math-format-value (calc-top i 'full)))
                            (number-sequence 1 5))
                    '("z" "y" "x" "x" "w")))   ; copy at level 3, original at 4
  (cl-assert (= (calc-stack-size) 5))
  ;; point travelled to the copy, not the original (now at level 4)
  (cl-assert (= (calc-locate-cursor-element (point)) 3))
  (calc-pop (calc-stack-size))

  ;; The copy is structurally identical to the source, not a re-read.
  (maf-push "a + b c") (maf-push "z")
  (progn (goto-char (point-min)) (end-of-line))
  (call-interactively 'maf-dup-below)
  (cl-assert (equal (calc-top 2 'full) (calc-top 3 'full)))
  (calc-pop (calc-stack-size))

  ;; --- the whole entry is the subject, whatever point sits on ---

  ;; subexpr: point inside the formula still copies the entry, unlike
  ;; `maf-dup', which would lift the sub-formula out.
  (maf-push "(a + b) c") (maf-push "z")
  (progn (goto-char (point-min)) (beginning-of-line)
         (search-forward "a") (backward-char 1))
  (call-interactively 'maf-dup-below)
  (cl-assert (equal (mapcar (lambda (i) (math-format-value (calc-top i 'full)))
                            (number-sequence 1 3))
                    '("z" "(a + b) c" "(a + b) c")))
  ;; point rode along to the copy, keeping its place inside the entry:
  ;; the two render alike, so it sits on the copy's own "a"
  (cl-assert (= (calc-locate-cursor-element (point)) 2))
  (cl-assert (= (current-column) 5))
  (cl-assert (looking-at "a"))
  (calc-pop (calc-stack-size))

  ;; a calc selection is likewise not the subject
  (maf-push "(a + b) c") (maf-push "z")
  (progn (goto-char (point-min)) (beginning-of-line)
         (search-forward "a") (backward-char 1) (calc-select-here nil))
  (call-interactively 'maf-dup-below)
  (cl-assert (string= (math-format-value (maf--strip-encasing (calc-top 2 'full)))
                      "(a + b) c"))
  (calc-clear-selections)
  (calc-pop (calc-stack-size))

  ;; a relation copies whole, not once per side
  (maf-push "x = y") (maf-push "z")
  (progn (goto-char (point-min)) (end-of-line))
  (call-interactively 'maf-dup-below)
  (cl-assert (equal (mapcar (lambda (i) (math-format-value (calc-top i 'full)))
                            (number-sequence 1 3))
                    '("z" "x = y" "x = y")))
  (calc-pop (calc-stack-size))

  ;; A multi-line rendering: point keeps its row within the entry, so it
  ;; lands on the copy's fraction bar, not the copy's first line.
  (calc-big-language)
  (maf-push "(a + b) / (c + d)") (maf-push "z")
  (progn (goto-char (point-min)) (forward-line 1)
         (beginning-of-line) (forward-char 4))
  (cl-assert (looking-at "-"))                  ; the fraction bar, row 1
  (call-interactively 'maf-dup-below)
  (cl-assert (= (calc-locate-cursor-element (point)) 2))   ; the copy
  (cl-assert (looking-at "-"))                  ; same row within it
  (cl-assert (= (current-column) 4))
  (calc-normal-language)
  (calc-pop (calc-stack-size))

  ;; --- degenerate placements: nothing below, so the copy lands on top ---

  ;; on the top entry there is only the home line beneath it
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
                    '("b" "a" "a")))
  (calc-pop (calc-stack-size))

  ;; --- the push and the roll are one undoable gesture ---
  (maf-push "w") (maf-push "x") (maf-push "y") (maf-push "z")
  (progn (goto-char (point-min)) (forward-line 1) (end-of-line))
  (call-interactively 'maf-dup-below)
  (cl-assert (= (calc-stack-size) 5))
  ;; last-command is set as the command loop would (the harness can't),
  ;; so the undo takes the pre-command-point path rather than the chained
  ;; one a leftover `maf-undo' from an earlier test would select.
  (progn (setq last-command nil) (call-interactively 'maf-undo))
  (cl-assert (= (calc-stack-size) 4))           ; a single undo, not two
  (cl-assert (equal (mapcar (lambda (i) (math-format-value (calc-top i 'full)))
                            (number-sequence 1 4))
                    '("z" "y" "x" "w")))
  ;; undo restores point along with the stack
  (cl-assert (= (calc-locate-cursor-element (point)) 3))
  (calc-pop (calc-stack-size)))
