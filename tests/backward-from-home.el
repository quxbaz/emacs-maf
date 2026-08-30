;; C-b in the native layout is `maf-backward-char': plain
;; backward-char everywhere but home, where one press puts point at
;; the end of the entry on level 1 — back into the stack without
;; walking the dot line a column at a time. A step passes when it
;; raises no error.

(maf-step
  (cl-assert (eq (key-binding (kbd "C-b")) 'maf-backward-char))

  ;; From home — the dot, its leading indentation — one press lands at
  ;; the end of the newest entry.
  (maf-push "x = y")
  (progn (calc-cursor-stack-index 0) (skip-chars-forward " "))
  (call-interactively 'maf-backward-char)
  (cl-assert (eolp))
  (cl-assert (eq (char-before) ?y))

  ;; Everywhere else it is backward-char exactly...
  (call-interactively 'maf-backward-char)
  (cl-assert (eq (char-after) ?y))
  ;; ...prefix argument included: 1:  x = y, four back from the y is
  ;; the x.
  (progn (let ((current-prefix-arg 4))
           (call-interactively 'maf-backward-char))
         nil)
  (cl-assert (eq (char-after) ?x))
  (calc-pop (calc-stack-size))

  ;; On an empty stack there is no entry to land in, and home keeps
  ;; plain backward-char: one character, not a jump.
  (progn (calc-cursor-stack-index 0) (skip-chars-forward " "))
  (setq backward-home-pos (point))
  (call-interactively 'maf-backward-char)
  (cl-assert (= (point) (1- backward-home-pos))))
