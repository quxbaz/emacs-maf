;; maf-digit-mod-360 (o in digit entry): end the entry and reduce the
;; number modulo 360 — mafcmd-mod-360 (M-o) dispatched off the entry's
;; own terminator, so the angle is normalized as it is typed.

(maf-step
  ;; The basic gesture: type an angle, reduce it as it lands.
  (goto-char (point-max))
  (execute-kbd-macro (kbd "4 0 0 o"))
  (cl-assert (string= (math-format-value
                       (maf--strip-encasing (calc-top 1 'full)))
                      "40"))
  (cl-assert (= (calc-stack-size) 1))
  (calc-pop (calc-stack-size))

  ;; A negative angle wraps into [0, 360).
  (goto-char (point-max))
  (execute-kbd-macro (kbd "_ 5 0 o"))
  (cl-assert (string= (math-format-value
                       (maf--strip-encasing (calc-top 1 'full)))
                      "310"))
  (calc-pop (calc-stack-size))

  ;; One gesture, one undo: the entry's push folds into the reduction.
  (goto-char (point-max))
  (execute-kbd-macro (kbd "4 0 0 o"))
  (maf-undo 1)
  (cl-assert (= (calc-stack-size) 0))

  ;; A deliberate push keeps its own undo group: undoing the manual
  ;; reduction strands nothing, the 400 stands.
  (goto-char (point-max))
  (execute-kbd-macro (kbd "4 0 0 RET M-o"))
  (maf-undo 1)
  (cl-assert (string= (math-format-value
                       (maf--strip-encasing (calc-top 1 'full)))
                      "400"))
  (calc-pop (calc-stack-size))

  ;; Inside a radix-prefixed entry the key is calc's own: o is a digit
  ;; where the radix has one (36#o is 24), not a reduction.
  (goto-char (point-max))
  (execute-kbd-macro (kbd "3 6 # o RET"))
  (cl-assert (string= (math-format-value
                       (maf--strip-encasing (calc-top 1 'full)))
                      "24"))
  (calc-pop (calc-stack-size)))
