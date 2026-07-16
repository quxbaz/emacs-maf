(maf-step
  ;; One undoable mul at home: q + 2 times 3 gives 3 q + 6.
  (calc-push (math-read-expr "q + 2"))
  (calc-push 3)
  (call-interactively 'mafcmd-mul)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "3 q + 6"))

  ;; Undo with point on the result's "3 q". The undo snapshots this
  ;; position for the chain.
  (progn (goto-char (point-min)) (search-forward "3 q") (backward-char 3))
  (progn (setq last-command nil) (call-interactively 'maf-undo))
  (cl-assert (= (calc-stack-size) 2))

  ;; Move away, then redo as a chained command (last-command is
  ;; maf-undo): point restores to the undo's snapshot — back on "3 q" —
  ;; not to where we moved.
  (goto-char (point-max))
  (progn (setq last-command 'maf-undo) (call-interactively 'maf-redo))
  (cl-assert (= (calc-stack-size) 1))
  (cl-assert (looking-at "3 q"))

  ;; Broken chain: an intermediary command ran (last-command is not
  ;; undo/redo), so undo keeps point in place instead of restoring the
  ;; chain snapshot (which is at home and would park point there).
  (progn (goto-char (point-min)) (search-forward "+ 6") (backward-char 1))
  (progn (setq last-command 'previous-line) (call-interactively 'maf-undo))
  (cl-assert (= (calc-stack-size) 2))
  (cl-assert (not (maf--at-home-p))))
