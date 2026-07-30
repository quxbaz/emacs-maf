(maf-step
  ;; C-g aborting digit entry at EOL of an entry: point must survive
  ;; (previously calc-do's epilogue aligned the stack and parked it at
  ;; home).
  (maf-push "a + b")
  (maf-push "c + d")
  (progn (calc-cursor-stack-index 2) (end-of-line))
  (let ((before (point)))
    (condition-case nil (execute-kbd-macro (kbd "5 C-g")) (quit nil))
    (cl-assert (= (point) before)))

  ;; C-g mid-subexpr (maf-digit-start's own read path): same.
  (progn (calc-cursor-stack-index 1) (forward-char 4))
  (let ((before (point)))
    (condition-case nil (execute-kbd-macro (kbd "5 C-g")) (quit nil))
    (cl-assert (= (point) before)))

  ;; C-g at home: plain calc behavior — the align still runs and parks
  ;; point on the dot.
  (goto-char (point-max))
  (progn
    (condition-case nil (execute-kbd-macro (kbd "5 C-g")) (quit nil))
    (cl-assert (looking-at "\\.")))

  ;; None of the aborted entries pushed anything.
  (cl-assert (= (calc-stack-size) 2)))
