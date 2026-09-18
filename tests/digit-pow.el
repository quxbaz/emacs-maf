;; maf-digit-pow (: in digit entry): end the entry and raise the entry
;; at point to the number — mafcmd-pow dispatched off the entry's own
;; terminator, so the power goes in as its exponent is typed. The
;; fraction colon this key was is on `;' (maf-digit-colon), and the
;; two trade places: wherever one is maf's, the other is calc's.

(maf-step
  ;; The basic gesture: at home, type the exponent and the top entry
  ;; is raised to it as it lands.
  (maf-push "x")
  (goto-char (point-max))
  (execute-kbd-macro (kbd "2 :"))
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "x^2"))
  (cl-assert (= (calc-stack-size) 1))
  (calc-pop (calc-stack-size))

  ;; On an entry line it is that entry raised, whatever its depth, and
  ;; point stays on its line.
  (maf-push "x")
  (maf-push "y")
  (progn (calc-cursor-stack-index 2) (end-of-line))
  (execute-kbd-macro (kbd "3 :"))
  (cl-assert (string= (math-format-value (calc-top 2 'full)) "x^3"))
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "y"))
  (cl-assert (= (line-number-at-pos) 1))
  (calc-pop (calc-stack-size))

  ;; A sign-led entry is a negative exponent.
  (maf-push "x")
  (goto-char (point-max))
  (execute-kbd-macro (kbd "_ 1 :"))
  (cl-assert (equal (calc-top 1 'full) '(^ (var x var-x) -1)))
  (calc-pop (calc-stack-size))

  ;; A fraction typed on `;' is the exponent whole: both halves, not
  ;; the numerator alone.
  (maf-push "x")
  (goto-char (point-max))
  (execute-kbd-macro (kbd "1 ; 2 :"))
  (cl-assert (equal (calc-top 1 'full) '(^ (var x var-x) (frac 1 2))))
  (calc-pop (calc-stack-size))

  ;; One gesture, one undo: the exponent's push folds into the power.
  (maf-push "x")
  (goto-char (point-max))
  (execute-kbd-macro (kbd "2 :"))
  (maf-undo 1)
  (cl-assert (= (calc-stack-size) 1))
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "x"))
  (calc-pop (calc-stack-size))

  ;; A deliberate push keeps its own undo group: undoing the manual
  ;; power strands nothing, the 2 stands.
  (maf-push "x")
  (goto-char (point-max))
  (execute-kbd-macro (kbd "2 RET :"))
  (maf-undo 1)
  (cl-assert (= (calc-stack-size) 2))
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "2"))
  (calc-pop (calc-stack-size))

  ;; Inside an incomplete object the key is calc's own: `;' is the row
  ;; separator of matrix entry there, so the fraction goes in on the
  ;; colon as it always did.
  (goto-char (point-max))
  (execute-kbd-macro (kbd "[ 1 : 2 ]"))
  (cl-assert (string= (math-format-value
                       (maf--strip-encasing (calc-top 1 'full)))
                      "[1:2]"))
  (calc-pop (calc-stack-size))

  ;; Inside a radix-prefixed entry the key is calc's own too: only calc
  ;; reads the colon that follows a digit of that base (16#f:2 is
  ;; fifteen halves), so nothing is raised.
  (goto-char (point-max))
  (execute-kbd-macro (kbd "1 6 # f : 2 RET"))
  (cl-assert (string= (math-format-value
                       (maf--strip-encasing (calc-top 1 'full)))
                      "15:2"))
  (calc-pop (calc-stack-size))

  ;; And `;' still types the fraction where it is maf's: the key the
  ;; colon's old job moved to.
  (goto-char (point-max))
  (execute-kbd-macro (kbd "3 ; 4 RET"))
  (cl-assert (string= (math-format-value
                       (maf--strip-encasing (calc-top 1 'full)))
                      "3:4"))
  (calc-pop (calc-stack-size)))
