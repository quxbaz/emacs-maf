(maf-step
  ;; Undo inside maf-edit: repairs are deferred while primitive-undo
  ;; replays records (repairing half-restored states misreads them as
  ;; gestures), then structure is re-derived from the text.
  (setq calc-break-vectors t)
  (maf-push "a + b")
  (maf-push "[2, 3]")
  (maf-push "c + d")
  (execute-kbd-macro (kbd "SPC"))

  ;; Edit a line, undo: back to the canonical enter state, dirty flag
  ;; and all.
  (progn (goto-char (point-min)) (end-of-line)
         (execute-kbd-macro (kbd "z C-/")))
  (cl-assert (string= (buffer-substring-no-properties (point-min) (point-max))
                      "3:  a + b\n2:  [ 2,\n      3 ]\n1:  c + d\n    .\n"))

  ;; Edit another line, undo: same (this pairing used to conjure
  ;; phantom entries out of half-restored dot lines).
  (progn (goto-char (point-min)) (forward-line 3) (end-of-line)
         (execute-kbd-macro (kbd "y"))
         (execute-kbd-macro (kbd "C-/")))
  (cl-assert (string= (buffer-substring-no-properties (point-min) (point-max))
                      "3:  a + b\n2:  [ 2,\n      3 ]\n1:  c + d\n    .\n"))

  ;; Undo a split: the entries re-merge and the buffer is canonical
  ;; again (structure re-derived post-undo, not replayed).
  (progn (goto-char (point-min)) (search-forward "c +")
         (execute-kbd-macro (kbd "S-<return>")))
  (cl-assert (= (length (maf-edit--overlays)) 4))
  (execute-kbd-macro (kbd "C-/"))
  (cl-assert (= (length (maf-edit--overlays)) 3))
  (cl-assert (string= (buffer-substring-no-properties (point-min) (point-max))
                      "3:  a + b\n2:  [ 2,\n      3 ]\n1:  c + d\n    .\n"))

  (execute-kbd-macro (kbd "C-c C-k"))
  (setq calc-break-vectors nil))
