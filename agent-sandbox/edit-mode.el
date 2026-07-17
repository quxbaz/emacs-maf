(maf-step
  ;; Enter maf-edit on a stack whose middle entry is a multi-line
  ;; vector. calc-break-vectors gives the one-element-per-line layout
  ;; the toggle must preserve; set explicitly, restored at the end.
  (setq calc-break-vectors t)
  ;; Track the mode hooks: on fires at enter, off at every exit
  ;; (commit and discard alike). Cleared again at the end.
  (progn (setq maf-edit-test--hooks nil)
         (add-hook 'maf-edit-mode-on-hook
                   (lambda () (push 'on maf-edit-test--hooks)))
         (add-hook 'maf-edit-mode-off-hook
                   (lambda () (push 'off maf-edit-test--hooks))))
  (maf-push "a + b")
  (maf-push "[2, 3]")
  (maf-push "c + d")
  (execute-kbd-macro (kbd "C-c C-c"))
  (cl-assert maf-edit-mode)
  (cl-assert (not buffer-read-only))
  (cl-assert (equal maf-edit-test--hooks '(on)))
  (cl-assert (assq 'maf-edit-mode minor-mode-alist))
  (cl-assert (string= (buffer-substring-no-properties (point-min) (point-max))
                      "3:  a + b\n2:  [ 2,\n      3 ]\n1:  c + d\n    .\n"))

  ;; Edit an entry's text in place.
  (progn (goto-char (point-min)) (end-of-line)
         (execute-kbd-macro (kbd "SPC + SPC 1")))

  ;; New entry: RET at a balanced EOL opens a pending line; typing on
  ;; it adopts it, stamps a prefix, and renumbers everything live.
  (execute-kbd-macro (kbd "RET x * y"))
  (cl-assert (string-prefix-p "4:  a + b + 1\n3:  x*y\n"
                              (buffer-substring-no-properties (point-min)
                                                              (point-max))))

  ;; Continuation: RET inside the vector's open bracket grows the
  ;; entry by a line instead of splitting it.
  (progn (goto-char (point-min)) (search-forward "[ 2,")
         (execute-kbd-macro (kbd "RET 9 9 ,")))
  (cl-assert (= (length (maf-edit--overlays)) 4))

  ;; Split: RET at a balanced point inside c + d cuts it in two.
  (progn (goto-char (point-min)) (search-forward "c +")
         (execute-kbd-macro (kbd "RET")))
  (cl-assert (= (length (maf-edit--overlays)) 5))

  ;; The invalid "c +" half blocks the commit; editing continues.
  (cl-assert
   (string-match-p "cannot commit"
                   (condition-case err
                       (progn (execute-kbd-macro (kbd "C-c C-c")) "")
                     (error (error-message-string err)))))
  (cl-assert maf-edit-mode)

  ;; Join the halves back: DEL at the line boundary merges the entries.
  ;; (Logical motion via lisp — C-a would be beginning-of-visual-line
  ;; under visual-line-mode, which stalls in a non-visible pgtk frame.)
  (progn (goto-char (point-min)) (search-forward "c +")
         (forward-line 1)
         (execute-kbd-macro (kbd "DEL")))
  (cl-assert (= (length (maf-edit--overlays)) 4))

  ;; Commit: parsed and reused entries land as one stack replacement.
  (execute-kbd-macro (kbd "C-c C-c"))
  (cl-assert (not maf-edit-mode))
  (cl-assert buffer-read-only)
  (cl-assert (equal maf-edit-test--hooks '(off on)))
  (cl-assert (= (calc-stack-size) 4))
  (cl-assert (string= (math-format-value (calc-top 4 'full)) "a + b + 1"))
  (cl-assert (string= (math-format-value (calc-top 3 'full)) "x y"))
  (cl-assert (string= (math-format-value (calc-top 2 'full))
                      "[ 2,\n  99,\n  3 ]"))
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "c + d"))

  ;; The whole commit is one undo group.
  (execute-kbd-macro (kbd "U"))
  (cl-assert (= (calc-stack-size) 3))
  (cl-assert (string= (math-format-value (calc-top 3 'full)) "a + b"))

  ;; Discard: edits vanish, the stack is untouched.
  (execute-kbd-macro (kbd "C-c C-c"))
  (progn (goto-char (point-min)) (end-of-line)
         (execute-kbd-macro (kbd "SPC + SPC 9 9 9")))
  (execute-kbd-macro (kbd "C-c C-k"))
  (cl-assert (not maf-edit-mode))
  (cl-assert (string= (math-format-value (calc-top 3 'full)) "a + b"))

  ;; Empty stack: typing at the dot line becomes the first entry.
  (calc-pop (calc-stack-size))
  (execute-kbd-macro (kbd "C-c C-c"))
  (progn (goto-char (point-min))
         (execute-kbd-macro (kbd "4 2 C-c C-c")))
  (cl-assert (= (calc-stack-size) 1))
  (cl-assert (equal (calc-top 1 'full) 42))
  ;; Three full enter/exit cycles ran: commit, discard, commit.
  (cl-assert (equal maf-edit-test--hooks '(off on off on off on)))
  (progn (setq maf-edit-mode-on-hook nil
               maf-edit-mode-off-hook nil
               calc-break-vectors nil)))
