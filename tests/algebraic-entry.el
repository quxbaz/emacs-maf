;; ' starts calc's own algebraic entry, which maf does not shadow: it
;; pushes the result and parks point home. maf advises it to leave a mark
;; on the origin first, so a single pop returns there. Run in a live Emacs
;; (see tests/README.md).
(maf-step
  ;; From a sub-formula: ' pushes the entered expression, point homes, and
  ;; a mark is left on the origin entry — popping it returns there.
  (let ((calc-simplify-mode 'none)) (calc-push '(* 12 (var x var-x))))
  (progn (goto-char (point-min)) (search-forward "12") (backward-char 1)
         (setq mark-ring nil) (set-mark nil))
  (execute-kbd-macro (kbd "' z + 1 RET"))
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "z + 1"))
  (cl-assert (maf--at-home-p))              ; homed
  (cl-assert (integerp (mark t)))           ; mark left behind
  (progn (setq this-command 'set-mark-command last-command nil)
         (pop-to-mark-command))
  (cl-assert (not (maf--at-home-p)))        ; popped back off home
  (calc-pop (calc-stack-size))

  ;; From an entry margin: same breadcrumb.
  (maf-push "a + b")
  (progn (goto-char (point-min)) (end-of-line)
         (setq mark-ring nil) (set-mark nil))
  (execute-kbd-macro (kbd "' w RET"))
  (cl-assert (maf--at-home-p))
  (cl-assert (integerp (mark t)))
  (calc-pop (calc-stack-size))

  ;; At home there is nowhere to return from, so no mark is left.
  (maf-push "a")
  (progn (goto-char (point-max)) (setq mark-ring nil) (set-mark nil))
  (execute-kbd-macro (kbd "' w RET"))
  (cl-assert (maf--at-home-p))
  (cl-assert (null (mark t)))
  (calc-pop (calc-stack-size)))
