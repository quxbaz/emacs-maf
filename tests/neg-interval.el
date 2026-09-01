;; n (mafcmd-neg) negates the resolved expression, and an interval
;; complements instead: the rays beyond its ends, open where the
;; interval was closed, and open at every infinity — no set closes at
;; one (`maf--interval-complement', `maf--open-infinite-ends'). A step
;; passes when it raises no error.

(maf-step
  (cl-assert (eq (key-binding "n") 'mafcmd-neg))

  ;; The complement, with its inf rays — and pressed again, the key
  ;; undoes itself: the two-ray set is a vector of intervals, the
  ;; same set in pieces, and complements back.
  (maf-push "[-5 .. 5]")
  (progn (calc-cursor-stack-index 1)
         (execute-kbd-macro "n")
         nil)
  (cl-assert (string= (math-format-value (calc-top 1 'full))
                      "[(-inf .. -5), (5 .. inf)]"))
  (progn (calc-cursor-stack-index 1)
         (execute-kbd-macro "n")
         nil)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "[-5 .. 5]"))
  (calc-pop (calc-stack-size))

  ;; Open where the interval was closed, closed where it was open.
  (maf-push "[2 .. 3)")
  (progn (calc-cursor-stack-index 1)
         (execute-kbd-macro "n")
         nil)
  (cl-assert (string= (math-format-value (calc-top 1 'full))
                      "[(-inf .. 2), [3 .. inf)]"))
  (calc-pop (calc-stack-size))

  ;; A symbolic endpoint complements as readily as a constant one —
  ;; the rays are built from the interval's own shape, where calc's
  ;; vcompl would demand constp — and comes home the same way.
  (maf-push "[-x .. x]")
  (progn (calc-cursor-stack-index 1)
         (execute-kbd-macro "n")
         nil)
  (cl-assert (string= (math-format-value (calc-top 1 'full))
                      "[(-inf .. -x), (x .. inf)]"))
  (progn (calc-cursor-stack-index 1)
         (execute-kbd-macro "n")
         nil)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "[-x .. x]"))
  (calc-pop (calc-stack-size))

  ;; An end already at its infinity leaves a single bare ray; the
  ;; whole line leaves the empty set.
  (maf-push "[-inf .. 5]")
  (progn (calc-cursor-stack-index 1)
         (execute-kbd-macro "n")
         nil)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "(5 .. inf)"))
  (calc-pop (calc-stack-size))

  ;; A constant set of many pieces still goes through calc's own
  ;; complement.
  (maf-push "[[1 .. 2], [4 .. 5]]")
  (progn (calc-cursor-stack-index 1)
         (execute-kbd-macro "n")
         nil)
  (cl-assert (string= (math-format-value (calc-top 1 'full))
                      "[(-inf .. 1), (2 .. 4), (5 .. inf)]"))
  (calc-pop (calc-stack-size))

  ;; A numeric vector is not a set: elementwise, as it always was.
  (maf-push "[1, 2, 3]")
  (progn (calc-cursor-stack-index 1)
         (execute-kbd-macro "n")
         nil)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "[-1, -2, -3]"))
  (calc-pop (calc-stack-size))

  ;; And everything else negates arithmetically, untouched.
  (maf-push "2 x - 3")
  (progn (calc-cursor-stack-index 1)
         (execute-kbd-macro "n")
         nil)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "3 - 2 x"))
  (calc-pop (calc-stack-size)))
