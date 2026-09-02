;; maf-yank: LaTeX on the kill ring yanks as the formula it typesets
;; (`maf-latex-to-calc'); everything else is maf-yank as before.
;;
;; The command reads the kill ring, so each case seeds it with
;; `kill-new' and yanks onto an empty stack. The converter is a pure
;; function of the text, so the cases that only concern its rewriting
;; call it directly.

(maf-step
  ;; The motivating case: a MathJax copy, \frac with undelimited
  ;; arguments and the product written with \cdot, which calc's own
  ;; LaTeX reader knows nothing of.
  (progn (kill-new "\\frac32 \\cdot x")
         (call-interactively 'maf-yank))
  (cl-assert (= (calc-stack-size) 1))
  (cl-assert (string= (math-format-value (calc-top 1)) "3:2 x"))
  (calc-pop (calc-stack-size))

  ;; Braced arguments read the same; a fraction of integers is exact.
  (progn (kill-new "\\frac{3}{2} \\cdot x")
         (call-interactively 'maf-yank))
  (cl-assert (string= (math-format-value (calc-top 1)) "3:2 x"))
  (calc-pop (calc-stack-size))

  ;; Math delimiters go: inline dollars, \( \), and a display block
  ;; whose line breaks are joined into the one entry.
  (progn (kill-new "$\\frac{3}{2}$")
         (call-interactively 'maf-yank))
  (cl-assert (string= (math-format-value (calc-top 1)) "3:2"))
  (calc-pop (calc-stack-size))
  (progn (kill-new "\\[\n x +\n 1\n\\]")
         (call-interactively 'maf-yank))
  (cl-assert (= (calc-stack-size) 1))
  (cl-assert (string= (math-format-value (calc-top 1)) "x + 1"))
  (calc-pop (calc-stack-size))

  ;; An align block yanks one entry per row: the ampersands and the
  ;; row breaks are LaTeX layout, not formula.
  (progn (kill-new "\\begin{align*}\n a &= b + c \\\\\n d &= e \\nonumber\n\\end{align*}")
         (call-interactively 'maf-yank))
  (cl-assert (= (calc-stack-size) 2))
  (cl-assert (string= (math-format-value (calc-top 2)) "a = b + c"))
  (cl-assert (string= (math-format-value (calc-top 1)) "d = e"))
  (calc-pop (calc-stack-size))

  ;; A matrix environment is one entry, whatever its bracket variant
  ;; and however its rows are broken across lines.
  (progn (kill-new "\\begin{bmatrix}\n 1 & 2 \\\\\n 3 & 4\n\\end{bmatrix}")
         (call-interactively 'maf-yank))
  (cl-assert (= (calc-stack-size) 1))
  (cl-assert (string= (math-format-flat-expr (calc-top 1 'full) 0)
                      "[[1, 2], [3, 4]]"))
  (calc-pop (calc-stack-size))

  ;; A comma list is several entries, as it is in calc's own yank.
  (progn (kill-new "\\frac{1}{2}, \\alpha")
         (call-interactively 'maf-yank))
  (cl-assert (= (calc-stack-size) 2))
  (cl-assert (string= (math-format-value (calc-top 2)) "1:2"))
  (cl-assert (string= (math-format-value (calc-top 1)) "alpha"))
  (calc-pop (calc-stack-size))

  ;; The rewrites calc's reader needs, checked on the converter
  ;; itself: the nth root, font and operator wrappers, the degree
  ;; circle as `maf--latex-string' writes it, TeX digit grouping,
  ;; spacing commands and style switches.
  (cl-assert (string= (maf-latex-to-calc "\\sqrt[3]{x + 1} + 2")
                      "nroot(x + 1, 3) + 2"))
  (cl-assert (string= (maf-latex-to-calc "\\mathrm{e}^{x} \\operatorname{sin}(x)")
                      "e^x sin(x)"))
  (cl-assert (string= (maf-latex-to-calc "180{}^{\\circ}") "180 deg"))
  (cl-assert (string= (maf-latex-to-calc "180^\\circ") "180 deg"))
  (cl-assert (string= (maf-latex-to-calc "1\\,234\\,567") "1234567"))
  (cl-assert (string= (maf-latex-to-calc "\\displaystyle a \\quad b") "a b"))
  (cl-assert (string= (maf-latex-to-calc "\\frac\\alpha\\beta") "alpha / beta"))

  ;; What calc reads natively passes through it: roots, delimiters,
  ;; relations, the plus-or-minus, Greek and the quadratic formula.
  (cl-assert (string= (maf-latex-to-calc "\\left( x + 1 \\right)^2") "(x + 1)^2"))
  (cl-assert (string= (maf-latex-to-calc "x \\le y") "x <= y"))
  (cl-assert (string= (maf-latex-to-calc "x = \\frac{-b \\pm \\sqrt{b^2 - 4ac}}{2a}")
                      "x = -(b +/- sqrt(b^2 - 4 ac)) / (2 a)"))

  ;; Text that is not LaTeX is returned as the same string object:
  ;; calc's yank recognizes its own last kill by identity, and that
  ;; path must survive the converter.
  (let ((s "3:2 x")) (cl-assert (eq (maf-latex-to-calc s) s)))
  (let ((s "[1, 2]")) (cl-assert (eq (maf-latex-to-calc s) s)))
  (let ((s "1,234,567")) (cl-assert (eq (maf-latex-to-calc s) s)))
  (let ((s "x^2 + x_1")) (cl-assert (eq (maf-latex-to-calc s) s)))

  ;; LaTeX the reader cannot make sense of is returned unchanged too,
  ;; and the yank then fails as it would have without the converter.
  (let ((s "\\frac{")) (cl-assert (eq (maf-latex-to-calc s) s)))
  (cl-assert (condition-case nil
                 (progn (kill-new "\\frac{")
                        (call-interactively 'maf-yank)
                        nil)
               (error t)))
  (cl-assert (zerop (calc-stack-size)))

  ;; Round trip: an entry copied as LaTeX by the repeat press of
  ;; maf-copy — 4\cdot 2^x + \frac{1}{2} — yanks back as itself.
  (maf-push "4 2^x + 1:2")
  (progn (call-interactively 'maf-copy)
         (let ((last-command 'maf-copy)) (call-interactively 'maf-copy)))
  (cl-assert (string= (current-kill 0) "4\\cdot 2^x + \\frac{1}{2}"))
  (call-interactively 'maf-yank)
  (cl-assert (= (calc-stack-size) 2))
  (cl-assert (equal (calc-top 1 'full) (calc-top 2 'full)))
  (calc-pop (calc-stack-size))

  ;; The plain yank cases still hold: digit-grouped numbers and level
  ;; prefixes are handled before the converter looks.
  (progn (kill-new "2:  1,234,567\n1:  \\frac12\n")
         (call-interactively 'maf-yank))
  (cl-assert (= (calc-stack-size) 2))
  (cl-assert (string= (math-format-value (calc-top 2)) "1234567"))
  (cl-assert (string= (math-format-value (calc-top 1)) "1:2"))
  (calc-pop (calc-stack-size)))
