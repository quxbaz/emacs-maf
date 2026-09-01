(maf-step
  ;; The sub-formula under point becomes the whole entry: the addition
  ;; that held the sin call is gone, not simplified away. The ":  "
  ;; search steps past the stack-level label, which
  ;; `calc-cursor-stack-index' leaves point on — without it the searches
  ;; below match the label's own digits and the target resolves at home
  ;; rather than as a sub-formula.
  (maf-push "x + sin(2 y)")
  (progn (calc-cursor-stack-index 1)
         (search-forward ":  ") (search-forward "sin")
         (call-interactively 'mafcmd-raise))
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "sin(2 y)"))
  (cl-assert (= (calc-stack-size) 1))
  (calc-pop (calc-stack-size))

  ;; A term out of a chain, the rest of the chain discarded.
  (maf-push "a + b + c")
  (progn (calc-cursor-stack-index 1)
         (search-forward ":  ") (search-forward "b") (backward-char 1)
         (call-interactively 'mafcmd-raise))
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "b"))
  (calc-pop (calc-stack-size))

  ;; A sum groups leftward, so point at the head of the chain names
  ;; a + b — the sub-sum, not the term and not the whole entry.
  (maf-push "a + b + c")
  (progn (calc-cursor-stack-index 1)
         (search-forward ":  ") (search-forward "a")
         (call-interactively 'mafcmd-raise))
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "a + b"))
  (calc-pop (calc-stack-size))

  ;; A relation's side raises like any other sub-formula: point at the
  ;; product's multiplication gap names 3 y, and the relation goes.
  (maf-push "x = 3 y")
  (progn (calc-cursor-stack-index 1)
         (search-forward ":  ") (search-forward "3")
         (call-interactively 'mafcmd-raise))
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "3 y"))
  (calc-pop (calc-stack-size))

  ;; The relation itself is raised whole — no per-side mapping, and the
  ;; entry comes back untouched rather than rebuilt.
  (maf-push "x = 3 y")
  (progn (calc-cursor-stack-index 1)
         (search-forward ":  ") (search-forward "=") (backward-char 1)
         (call-interactively 'mafcmd-raise))
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "x = 3 y"))
  (calc-pop (calc-stack-size))

  ;; A vector element, the vector around it discarded.
  (maf-push "[1, 2, 3]")
  (progn (calc-cursor-stack-index 1)
         (search-forward ":  ") (search-forward "2") (backward-char 1)
         (call-interactively 'mafcmd-raise))
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "2"))
  (calc-pop (calc-stack-size))

  ;; At home the target already is the whole entry: nothing to discard,
  ;; and the entry commits unchanged on one stack level.
  (maf-push "x + y")
  (progn (calc-cursor-stack-index 0)
         (call-interactively 'mafcmd-raise))
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "x + y"))
  (cl-assert (= (calc-stack-size) 1))
  (calc-pop (calc-stack-size))

  ;; Likewise at the entry's margin.
  (maf-push "x + sin(2 y)")
  (progn (calc-cursor-stack-index 1) (end-of-line)
         (call-interactively 'mafcmd-raise))
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "x + sin(2 y)"))
  (cl-assert (= (calc-stack-size) 1))
  (calc-pop (calc-stack-size))

  ;; A lower entry is raised in place, the entries above it untouched.
  (maf-push "x + sin(2 y)")
  (maf-push "777")
  (progn (calc-cursor-stack-index 2)
         (search-forward ":  ") (search-forward "sin")
         (call-interactively 'mafcmd-raise))
  (cl-assert (string= (math-format-value (calc-top 2 'full)) "sin(2 y)"))
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "777"))
  (cl-assert (= (calc-stack-size) 2))
  (calc-pop (calc-stack-size))

  ;; An explicit calc selection is the target, and the entry it sits in
  ;; is replaced rather than the selection spliced back into it — the
  ;; commit bypasses calc's redirection of a selectionless push. The
  ;; replacement entry carries no selection of its own.
  (maf-push "x + sin(2 y)")
  (progn (calc-cursor-stack-index 1)
         (search-forward ":  ") (search-forward "sin")
         (call-interactively 'calc-select-here))
  (cl-assert (nth 2 (calc-top 1 'entry)))
  (call-interactively 'mafcmd-raise)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "sin(2 y)"))
  (cl-assert (null (nth 2 (calc-top 1 'entry))))
  (cl-assert (null calc-any-selections))
  (calc-pop (calc-stack-size))

  ;; A region names the run of chain terms it covers, and that run
  ;; becomes the entry.
  (maf-push "a + b + c")
  (progn (calc-cursor-stack-index 1)
         (search-forward ":  ") (search-forward "b" (line-end-position))
         (push-mark (- (point) 5) t t)   ; over "a + b"
         (call-interactively 'mafcmd-raise))
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "a + b"))
  (calc-pop (calc-stack-size))

  ;; Keep-args leaves the entry as it stands and pushes the raised part
  ;; on top of it.
  (maf-push "x + sin(2 y)")
  (progn (calc-cursor-stack-index 1)
         (search-forward ":  ") (search-forward "sin")
         (call-interactively 'calc-keep-args)
         (call-interactively 'mafcmd-raise))
  (cl-assert (= (calc-stack-size) 2))
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "sin(2 y)"))
  (cl-assert (string= (math-format-value (calc-top 2 'full)) "x + sin(2 y)"))
  (calc-pop (calc-stack-size))

  ;; Nothing is evaluated on the way: an unsimplified product raised out
  ;; of a sum arrives exactly as it stood.
  (progn (calc-push (let ((calc-simplify-mode 'none))
                      (math-read-expr "x + 2 (3 + 4)")))
         nil)
  (progn (calc-cursor-stack-index 1)
         (search-forward ":  ") (search-forward "2")
         (call-interactively 'mafcmd-raise))
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "2 (3 + 4)"))
  (calc-pop (calc-stack-size))

  ;; Undo puts the discarded formula back.
  (maf-push "x + sin(2 y)")
  (progn (calc-cursor-stack-index 1)
         (search-forward ":  ") (search-forward "sin")
         (call-interactively 'mafcmd-raise))
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "sin(2 y)"))
  (call-interactively 'maf-undo)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "x + sin(2 y)"))
  (calc-pop (calc-stack-size))

  ;; Point rides along on the glyph it was on: raising from the sin's
  ;; name leaves point on that same name in the now-whole entry.
  (maf-push "x + sin(2 y)")
  (progn (calc-cursor-stack-index 1)
         (search-forward ":  ") (search-forward "si") (backward-char 1)
         (call-interactively 'mafcmd-raise))
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "sin(2 y)"))
  (cl-assert (eq (char-after) ?i))
  (calc-pop (calc-stack-size))

  ;; The binding: j k runs it on the sub-formula under point, within
  ;; calc's selection prefix, on a key calc leaves unbound.
  (maf-push "x + sin(2 y)")
  (let* ((buf (get-buffer "*Calculator*"))
         (win (get-buffer-window buf t)))
    (cl-assert win)
    (with-selected-window win
      (with-current-buffer buf
        (calc-cursor-stack-index 1)
        (search-forward ":  ") (search-forward "sin")
        (execute-kbd-macro (kbd "j k"))))
    nil)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "sin(2 y)"))
  (calc-pop (calc-stack-size)))
