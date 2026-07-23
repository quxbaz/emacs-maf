;; maf-del point-landing: deleting a whole entry lands point on the entry
;; that was just above it (next up the stack), keeping eol/bol; a
;; sub-formula deletion or a home pop keeps point in place. Run in a live
;; Emacs (see tests/README.md).
(maf-step
  ;; --- Whole entry: land on the entry above ---

  ;; Mid-stack, at eol: the entry above drops into place and point rests
  ;; on it, still at eol.
  (maf-push "w") (maf-push "x") (maf-push "y") (maf-push "z")  ; 4:w 3:x 2:y 1:z
  (progn (calc-cursor-stack-index 3) (end-of-line))            ; on 3: x
  (call-interactively 'maf-del)
  (cl-assert (= (calc-stack-size) 3))
  (cl-assert (string= (math-format-value
                       (calc-top (calc-locate-cursor-element (point)) 'full)) "w"))
  (cl-assert (eolp))
  (calc-pop (calc-stack-size))

  ;; Same from the line prefix: point lands on the entry above at bol.
  (maf-push "w") (maf-push "x") (maf-push "y") (maf-push "z")
  (progn (calc-cursor-stack-index 3) (beginning-of-line))
  (call-interactively 'maf-del)
  (cl-assert (string= (math-format-value
                       (calc-top (calc-locate-cursor-element (point)) 'full)) "w"))
  (cl-assert (bolp))
  (calc-pop (calc-stack-size))

  ;; The topmost entry has nothing above it, so point rests at home.
  (maf-push "w") (maf-push "x") (maf-push "y") (maf-push "z")
  (progn (calc-cursor-stack-index 4) (end-of-line))            ; top (w)
  (call-interactively 'maf-del)
  (cl-assert (maf--at-home-p))
  (cl-assert (= (calc-stack-size) 3))
  (calc-pop (calc-stack-size))

  ;; The bottom entry (level 1) lands on the entry that was above it.
  (maf-push "w") (maf-push "x") (maf-push "y") (maf-push "z")
  (progn (calc-cursor-stack-index 1) (end-of-line))            ; bottom (z)
  (call-interactively 'maf-del)
  (cl-assert (string= (math-format-value
                       (calc-top (calc-locate-cursor-element (point)) 'full)) "y"))
  (calc-pop (calc-stack-size))

  ;; --- Point stays put when no whole entry is removed ---

  ;; A sub-formula deletion leaves the entry standing; point keeps it.
  (let ((calc-simplify-mode 'none)) (maf-push "a b"))
  (maf-push "z")                                               ; 2: a b   1: z
  (progn (calc-cursor-stack-index 2) (beginning-of-line)
         (search-forward "b") (backward-char 1))
  (call-interactively 'maf-del)
  (cl-assert (= (calc-stack-size) 2))
  (cl-assert (string= (math-format-value (calc-top 2 'full)) "a"))
  (cl-assert (= (calc-locate-cursor-element (point)) 2))
  (calc-pop (calc-stack-size))

  ;; A home pop keeps point at home.
  (maf-push "p") (maf-push "q")
  (goto-char (point-max))
  (call-interactively 'maf-del)
  (cl-assert (maf--at-home-p))
  (cl-assert (= (calc-stack-size) 1))
  (calc-pop (calc-stack-size))

  ;; --- One undo reverts point and stack together ---

  (maf-push "w") (maf-push "x") (maf-push "y") (maf-push "z")
  (progn (calc-cursor-stack-index 3) (end-of-line))
  (call-interactively 'maf-del)
  (execute-kbd-macro (kbd "U"))
  (cl-assert (= (calc-stack-size) 4))
  (cl-assert (string= (math-format-value
                       (calc-top (calc-locate-cursor-element (point)) 'full)) "x"))
  (calc-pop (calc-stack-size)))
