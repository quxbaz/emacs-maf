;; mafcmd-increment (>) and mafcmd-decrement (<): step the target by
;; one, contextually — plain arithmetic, not calc's ulp-stepping f ] /
;; f [, which keep their own keys. A numeric prefix gives the step.

(maf-step
  ;; A constant under the cursor nudges in place.
  (maf-push "x + 5")
  (progn (goto-char (point-max)) (search-backward "5"))
  (execute-kbd-macro (kbd ">"))
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "x + 6"))
  (execute-kbd-macro (kbd "<"))
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "x + 5"))
  ;; M-> and M-< once doubled the step under a modifier; they went back
  ;; to the stock buffer motions, the natural binding winning. Pin the
  ;; release: the keys move point, not the value.
  (cl-assert (not (eq (key-binding (kbd "M->")) 'mafcmd-increment)))
  (cl-assert (not (eq (key-binding (kbd "M-<")) 'mafcmd-decrement)))
  (execute-kbd-macro (kbd "M->"))
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "x + 5"))
  (cl-assert (derived-mode-p 'calc-mode))
  (calc-pop (calc-stack-size))

  ;; At home the whole entry steps; a vector elementwise.
  (maf-push "[1, 2, 3]")
  (maf-go-home)
  (execute-kbd-macro (kbd ">"))
  (cl-assert (string= (math-format-value
                       (maf--strip-encasing (calc-top 1 'full)))
                      "[2, 3, 4]"))
  (calc-pop (calc-stack-size))

  ;; An equation steps side by side.
  (maf-push "y = x + 1")
  (goto-char (point-max))
  (execute-kbd-macro (kbd ">"))
  (cl-assert (string= (math-format-value
                       (maf--strip-encasing (calc-top 1 'full)))
                      "y + 1 = x + 2"))
  (calc-pop (calc-stack-size))

  ;; A numeric prefix is the step; a negative one walks the other way.
  (maf-push "7")
  (maf-go-home)
  (execute-kbd-macro (kbd "C-u 5 >"))
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "12"))
  (execute-kbd-macro (kbd "C-u - 2 <"))
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "14"))
  (calc-pop (calc-stack-size))

  ;; A float steps by one, not by its last representable digit.
  (maf-push "2.5")
  (maf-go-home)
  (execute-kbd-macro (kbd ">"))
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "3.5"))
  (calc-pop (calc-stack-size)))
