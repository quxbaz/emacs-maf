;; Point on the top equation, with another equation below it. The equation
;; target cannot take its arg from the relation it is targeting, so resolve
;; falls through to the entry target, which shifts down to the entry below;
;; that entry is a relation too, so it maps back to an equation and the two
;; pair up — the same result as pressing the key at home.

(maf-step
  (calc-push (math-read-expr "a = b"))
  (calc-push (math-read-expr "c = d"))
  (calc-cursor-stack-index 1)
  (call-interactively 'mafcmd-add)
  (cl-assert (= (calc-stack-size) 1))
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "a + c = b + d"))
  (calc-pop 1)

  ;; With a non-relation below there is no coherent shift — the arg would
  ;; have to be the relation under point — so it is still rejected.
  (calc-push 2)
  (calc-push (math-read-expr "x = 5"))
  (calc-cursor-stack-index 1)
  (cl-assert (condition-case nil
                 (progn (call-interactively 'mafcmd-mul) nil)
               (error t)))
  (cl-assert (= (calc-stack-size) 2)))
