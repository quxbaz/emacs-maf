;; maf-digit-sqr (: in digit entry): end the entry and square the
;; number — mafcmd-sqr dispatched off the entry's own terminator, so
;; the square goes in as the number is typed. The fraction colon this
;; key was is on `;' (maf-digit-colon), and the two trade places:
;; wherever one is maf's, the other is calc's.

(maf-step
  ;; The basic gesture: type a number, square it as it lands.
  (goto-char (point-max))
  (execute-kbd-macro (kbd "5 :"))
  (cl-assert (string= (math-format-value
                       (maf--strip-encasing (calc-top 1 'full)))
                      "25"))
  (cl-assert (= (calc-stack-size) 1))
  (calc-pop (calc-stack-size))

  ;; A sign-led entry squares as any other does — the negative goes.
  (goto-char (point-max))
  (execute-kbd-macro (kbd "_ 3 :"))
  (cl-assert (string= (math-format-value
                       (maf--strip-encasing (calc-top 1 'full)))
                      "9"))
  (calc-pop (calc-stack-size))

  ;; A fraction typed on `;' squares whole: both halves, not the
  ;; numerator alone.
  (goto-char (point-max))
  (execute-kbd-macro (kbd "1 ; 2 :"))
  (cl-assert (string= (math-format-value
                       (maf--strip-encasing (calc-top 1 'full)))
                      "1:4"))
  (calc-pop (calc-stack-size))

  ;; One gesture, one undo: the entry's push folds into the square.
  (goto-char (point-max))
  (execute-kbd-macro (kbd "5 :"))
  (maf-undo 1)
  (cl-assert (= (calc-stack-size) 0))

  ;; A deliberate push keeps its own undo group: undoing the manual
  ;; square strands nothing, the 5 stands.
  (goto-char (point-max))
  (execute-kbd-macro (kbd "5 RET :"))
  (maf-undo 1)
  (cl-assert (string= (math-format-value
                       (maf--strip-encasing (calc-top 1 'full)))
                      "5"))
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
  ;; fifteen halves), so nothing is squared.
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
