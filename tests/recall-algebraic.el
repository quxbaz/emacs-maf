;; What feeds the recall ring on the algebraic-entry path
;; (modules/maf-recall.el). The ' key is calc's own command, and it
;; takes the same rule as digit entry: an expression left on the stack
;; as an entry of its own is recorded, one built out of what was
;; already there is not.
;;
;; The entries here avoid spaces between factors on purpose — calc's '
;; entry drops spaces, so ' a b RET enters the variable ab, not a
;; product, and an assertion written the other way would be testing
;; calc's parser rather than the ring.

(maf-step
  (progn (maf-use-recall-mode 1) (setq maf-recall--ring nil) nil)

  ;; An expression typed from nothing is an entry of its own: recorded.
  (progn (goto-char (point-max)) nil)
  (execute-kbd-macro (kbd "' z + 1 RET"))
  (cl-assert (= (calc-stack-size) 1))
  (cl-assert (equal (mapcar #'car maf-recall--ring) '("z + 1")))

  ;; Recorded from a sub-formula too — ' pushes wherever point is, so
  ;; what it leaves behind is an entry either way.
  (progn (goto-char (point-min)) (search-forward "z") (backward-char 1))
  (execute-kbd-macro (kbd "' q^2 RET"))
  (cl-assert (= (calc-stack-size) 2))
  (cl-assert (equal (mapcar #'car maf-recall--ring) '("q^2" "z + 1")))

  ;; An entry that consumes the stack top ($) modifies what was already
  ;; there instead of adding to it: nothing inserted, nothing recorded.
  (progn (goto-char (point-max)) nil)
  (execute-kbd-macro (kbd "' 2 + $ RET"))
  (cl-assert (= (calc-stack-size) 2))
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "q^2 + 2"))
  (cl-assert (equal (mapcar #'car maf-recall--ring) '("q^2" "z + 1")))

  ;; The item carries the value the entry produced, so recalling it out
  ;; on the stack pushes that expression back whole.
  (progn (calc-pop (calc-stack-size)) (goto-char (point-max)) nil)
  (execute-kbd-macro (kbd "M-p"))
  (cl-assert (= (calc-stack-size) 1))
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "q^2")))
