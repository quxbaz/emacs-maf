;; Recalling out on the stack (modules/maf-recall.el): M-p pushes an
;; entry at home, presses in a row replace it in place, and the whole
;; cycle unwinds as a single undo. A cycle lives inside one run of
;; presses — any other command ends it — so the steps that test cycling
;; deliver their keys in one macro.
;;
;; `last-command' is only meaningful within one `execute-kbd-macro' run
;; — across separate runs the macro machinery decides it, not the
;; steps — so a cycle and whatever is meant to interrupt it are
;; delivered together in one macro, C-b standing in for "the user did
;; something else".

(maf-step
  (progn (maf-use-recall-mode 1)
         (setq maf-recall--ring (list (cons "x + 1" nil)
                                      (cons "42" 42)
                                      (cons "a b" nil)))
         nil)

  ;; M-p at home pushes the newest item as a real entry. The item
  ;; carries no value of its own, so its text is parsed on demand.
  (maf-push "c")
  (progn (goto-char (point-max)) nil)
  (execute-kbd-macro (kbd "M-p"))
  (cl-assert (= (calc-stack-size) 2))
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "x + 1"))
  (progn (calc-pop 1) nil)

  ;; Presses in a row replace that entry rather than pushing another,
  ;; so a cycle of any length leaves exactly one entry behind.
  (progn (goto-char (point-max)) nil)
  (execute-kbd-macro (kbd "M-p M-p M-p"))
  (cl-assert (= (calc-stack-size) 2))
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "a b"))

  ;; One undo removes the whole cycle, not one candidate of it.
  (call-interactively 'calc-undo)
  (cl-assert (= (calc-stack-size) 1))
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "c"))

  ;; The oldest item ends the cycle — no wraparound onto the newest.
  (progn (goto-char (point-max))
         (ignore-errors (execute-kbd-macro (kbd "M-p M-p M-p M-p"))) nil)
  (cl-assert (= (calc-stack-size) 2))
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "a b"))
  (progn (call-interactively 'calc-undo) nil)

  ;; M-n walks back toward the newest item within a cycle.
  (progn (goto-char (point-max)) nil)
  (execute-kbd-macro (kbd "M-p M-p M-n"))
  (cl-assert (= (calc-stack-size) 2))
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "x + 1"))
  (progn (call-interactively 'calc-undo) nil)

  ;; Any other command ends the cycle: the next M-p starts over from
  ;; the newest item, pushing a second entry instead of replacing.
  (execute-kbd-macro (kbd "M-p C-b M-p"))
  (cl-assert (= (calc-stack-size) 3))
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "x + 1"))
  (cl-assert (string= (math-format-value (calc-top 2 'full)) "x + 1"))
  (progn (calc-pop (calc-stack-size)) nil)

  ;; The entry always lands at home, whatever level point was on, and
  ;; the vacated spot is marked so a single pop returns there.
  (maf-push "p")
  (maf-push "q")
  (progn (calc-cursor-stack-index 2) nil)
  (execute-kbd-macro (kbd "M-p"))
  (cl-assert (= (calc-stack-size) 3))
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "x + 1"))
  (cl-assert (maf--at-home-p))
  (progn (call-interactively 'pop-to-mark-command) nil)
  (cl-assert (= (calc-locate-cursor-element (point)) 3)))
