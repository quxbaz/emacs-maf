;; The vector-access prefix: h h takes the head of the vector at
;; point (mafcmd-head), h l its last element (mafcmd-rtail), and h 1-9 the
;; element the digit names (mafcmd-nth-element), read off the key the
;; way quick recall reads its digits. A step passes when it raises no
;; error.

(maf-step
  ;; The prefix owns its keys, shadowing calc's help commands.
  (cl-assert (eq (key-binding (kbd "h h")) 'mafcmd-head))
  (cl-assert (eq (key-binding (kbd "h l")) 'mafcmd-rtail))
  (cl-assert (eq (key-binding (kbd "h 1")) 'mafcmd-nth-element))
  (cl-assert (eq (key-binding (kbd "h 9")) 'mafcmd-nth-element))

  ;; Head and last, through the keymap.
  (maf-push "[a, b, c, d]")
  (progn (calc-cursor-stack-index 1)
         (execute-kbd-macro (kbd "h h"))
         nil)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "a"))
  (calc-pop (calc-stack-size))
  (maf-push "[a, b, c, d]")
  (progn (calc-cursor-stack-index 1)
         (execute-kbd-macro (kbd "h l"))
         nil)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "d"))
  (calc-pop (calc-stack-size))

  ;; The digit names the element, 1-indexed, lifted out literally.
  (maf-push "[10, 20, 30]")
  (progn (calc-cursor-stack-index 1)
         (execute-kbd-macro (kbd "h 2"))
         nil)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "20"))
  (calc-pop (calc-stack-size))

  ;; Equation sides map separately: the vector side gives up its
  ;; element, a side without one passes through quietly.
  (maf-push "[a, b] = v")
  (progn (calc-cursor-stack-index 1)
         (execute-kbd-macro (kbd "h 2"))
         nil)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "b = v"))
  (calc-pop (calc-stack-size))

  ;; A non-vector commits unchanged; a digit past the end signals and
  ;; leaves the entry standing.
  (maf-push "x + y")
  (progn (calc-cursor-stack-index 1)
         (execute-kbd-macro (kbd "h 1"))
         nil)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "x + y"))
  (calc-pop (calc-stack-size))
  (maf-push "[a, b]")
  (progn (calc-cursor-stack-index 1) nil)
  (cl-assert (string-match-p
              "No element 5"
              (condition-case e
                  (progn (execute-kbd-macro (kbd "h 5")) "")
                (error (error-message-string e)))))
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "[a, b]"))
  (calc-pop (calc-stack-size)))
