;; maf-copy: region / entry / top, and the LaTeX repeat.
;;
;; Each interaction is one form: a real M-w is a single command, and
;; under `maf-step' the command loop resets `last-command' and the mark
;; between forms. A repeat press is spelled as a `last-command'
;; binding around the call, exactly what a second M-w would see.

(maf-step
  ;; Empty stack with no region: signals instead of guessing.
  (cl-assert (condition-case nil
                 (progn (call-interactively 'maf-copy) nil)
               (error t)))

  ;; Mid-formula point: the whole entry is copied anyway — copying is
  ;; line-based, like maf-kill. The stack is untouched.
  (maf-push "q1 + q2")
  (maf-push "q3")
  (progn (calc-cursor-stack-index 2)
         (search-forward "q1" (line-end-position))
         (backward-char 1)
         (call-interactively 'maf-copy))
  (cl-assert (= (calc-stack-size) 2))
  (cl-assert (string= (current-kill 0) "q1 + q2"))
  (setq maf--test-kills (length kill-ring))

  ;; Second press: the same entry as LaTeX, replacing the plain copy
  ;; rather than pushing a second kill. Plain sums of plain variables
  ;; are already LaTeX, so only the kill count moves here.
  (let ((last-command 'maf-copy)) (call-interactively 'maf-copy))
  (cl-assert (string= (current-kill 0) "q1 + q2"))
  (cl-assert (= (length kill-ring) maf--test-kills))

  ;; Third press toggles back to the plain form, still one kill.
  (let ((last-command 'maf-copy)) (call-interactively 'maf-copy))
  (cl-assert (string= (current-kill 0) "q1 + q2"))
  (cl-assert (= (length kill-ring) maf--test-kills))

  ;; A press that is not a repeat starts over: no LaTeX, and the copy
  ;; follows point to the other entry.
  (progn (calc-cursor-stack-index 1)
         (end-of-line)
         (call-interactively 'maf-copy))
  (cl-assert (string= (current-kill 0) "q3"))
  (calc-pop (calc-stack-size))

  ;; Home: the top entry is copied, formatted as calc renders it — no
  ;; level-number prefix.
  (maf-push "sqrt(x)/3")
  (progn (goto-char (point-max)) (call-interactively 'maf-copy))
  (cl-assert (string= (current-kill 0) "sqrt(x) / 3"))
  (let ((last-command 'maf-copy)) (call-interactively 'maf-copy))
  (cl-assert (string= (current-kill 0) "\\frac{\\sqrt{x}}{3}"))
  ;; Formatting in latex left the display language alone.
  (cl-assert (null calc-language))
  (calc-pop (calc-stack-size))

  ;; The trig calls typeset with their argument in parens — sin(x),
  ;; not the sin x calc's brace spelling draws — and a tall argument
  ;; keeps its \left( sizing (`maf--latex-compose-paren-call').
  (maf-push "sin(2 x) + csc(a/b)")
  (progn (goto-char (point-max)) (call-interactively 'maf-copy))
  (let ((last-command 'maf-copy)) (call-interactively 'maf-copy))
  (cl-assert (string= (current-kill 0)
                      "\\sin(2 x) + \\csc\\left( \\frac{a}{b} \\right)"))
  ;; The override lived only for the call: the table is calc's own
  ;; again.
  (cl-assert (null (assq 'calcFunc-sin
                         (get 'latex 'math-special-function-table))))
  (calc-pop (calc-stack-size))

  ;; A script sheds the parens flat notation needed around it — the
  ;; raised position already groups — while a base's real parens stay
  ;; (`maf--latex-strip-script-parens').
  (maf-push "(x^(-n))^(m+1) + a_(i+1)")
  (progn (goto-char (point-max)) (call-interactively 'maf-copy))
  (let ((last-command 'maf-copy)) (call-interactively 'maf-copy))
  (cl-assert (string= (current-kill 0)
                      "(x^{-n})^{m + 1} + a_{i + 1}"))
  (calc-pop (calc-stack-size))

  ;; A juxtaposed factor opening on a digit gets its sign written
  ;; out — TeX throws the space away and 4 2^x would typeset as 42^x
  ;; — while 4 x keeps the juxtaposition; every surviving sign is the
  ;; dot (`maf--latex-separate-digit-product').
  (maf-push "3 x^2 + 4 2^x")
  (progn (goto-char (point-max)) (call-interactively 'maf-copy))
  (let ((last-command 'maf-copy)) (call-interactively 'maf-copy))
  (cl-assert (string= (current-kill 0)
                      "3 x^2 + 4\\cdot 2^x"))
  (calc-pop (calc-stack-size))

  ;; Between a variable and a plain paren group the sign goes the way
  ;; of the \left( one: 4 p (x - h) is what anyone writes, and the
  ;; typeset spacing carries it.
  (maf-push "(y - k)^2 = 4 p*(x - h)")
  (progn (goto-char (point-max)) (call-interactively 'maf-copy))
  (let ((last-command 'maf-copy)) (call-interactively 'maf-copy))
  (cl-assert (string= (current-kill 0)
                      "(y - k)^2 = 4 p (x - h)"))
  (calc-pop (calc-stack-size))

  ;; The degree unit is notation, not a name: the raised circle rides
  ;; the factor before it, 180 deg drawing as 180 with the circle on
  ;; its shoulder.
  (maf-push "180 deg*(n-2)")
  (progn (goto-char (point-max)) (call-interactively 'maf-copy))
  (let ((last-command 'maf-copy)) (call-interactively 'maf-copy))
  (cl-assert (string= (current-kill 0)
                      "180 {}^{\\circ} (n - 2)"))
  (calc-pop (calc-stack-size))

  ;; The sets read with their signs: a vector of intervals joins its
  ;; pieces with the cup, brackets dropped, and vint draws the cap —
  ;; while a numeric vector keeps its brackets
  ;; (`maf--latex-compose-set-op', the vec branch beside it).
  (maf-push "vint([[-inf .. -5), (5 .. inf]], [0 .. 9])")
  (progn (goto-char (point-max)) (call-interactively 'maf-copy))
  (let ((last-command 'maf-copy)) (call-interactively 'maf-copy))
  (cl-assert (string= (current-kill 0)
                      "([-\\infty \\ldots -5) \\cup (5 \\ldots \\infty]) \\cap [0 \\ldots 9]"))
  (calc-pop (calc-stack-size))

  ;; A region is copied verbatim — not rounded out to whole entry lines
  ;; the way calc's own M-w does it.
  (maf-push "a + b + c")
  (progn (calc-cursor-stack-index 1)
         (search-forward "b" (line-end-position))
         (push-mark (- (point) 5) t t)   ; over "a + b"
         (call-interactively 'maf-copy))
  (cl-assert (string= (current-kill 0) "a + b"))
  (cl-assert (= (calc-stack-size) 1))

  ;; The repeat converts what was copied, even though the region is
  ;; gone by then.
  (progn (deactivate-mark)
         (let ((last-command 'maf-copy)) (call-interactively 'maf-copy)))
  (cl-assert (string= (current-kill 0) "a + b"))
  (calc-pop (calc-stack-size))

  ;; A region that swept up the level prefix still converts: the prefix
  ;; is dropped before parsing, though the plain copy keeps it.
  (maf-push "2 x")
  (progn (calc-cursor-stack-index 1)
         (beginning-of-line)
         (push-mark (line-end-position) t t)
         (call-interactively 'maf-copy))
  (cl-assert (string-match-p "\\`1: +2 x\\'" (current-kill 0)))
  (progn (deactivate-mark)
         (let ((last-command 'maf-copy)) (call-interactively 'maf-copy)))
  (cl-assert (string= (current-kill 0) "2 x"))
  (calc-pop (calc-stack-size))

  ;; Region text that is not a formula has no LaTeX form: the repeat
  ;; says so and leaves the plain copy on the kill ring.
  (maf-push "u")
  (maf-push "v")
  (progn (calc-cursor-stack-index 2)
         (beginning-of-line)
         (push-mark (point-max) t t)
         (call-interactively 'maf-copy))
  (setq maf--test-plain (current-kill 0))
  (cl-assert (string-match-p "u" maf--test-plain))
  (progn (deactivate-mark)
         (cl-assert (condition-case nil
                        (progn (let ((last-command 'maf-copy))
                                 (call-interactively 'maf-copy))
                               nil)
                      (error t))))
  (cl-assert (string= (current-kill 0) maf--test-plain))
  (calc-pop (calc-stack-size))

  ;; A region cut off mid-formula has no LaTeX either: calc's reader
  ;; would happily read "a + sqrt(" as a zero-argument sqrt, so the
  ;; parse is checked by formatting it back.
  (maf-push "a + sqrt(b) + c")
  (progn (calc-cursor-stack-index 1)
         (search-forward "a" (line-end-position))
         (backward-char 1)
         (push-mark (+ (point) 9) t t)   ; over "a + sqrt("
         (call-interactively 'maf-copy))
  (cl-assert (string= (substring-no-properties (current-kill 0)) "a + sqrt("))
  (progn (deactivate-mark)
         (cl-assert (condition-case nil
                        (progn (let ((last-command 'maf-copy))
                                 (call-interactively 'maf-copy))
                               nil)
                      (error t))))
  (cl-assert (string= (substring-no-properties (current-kill 0)) "a + sqrt("))
  (calc-pop (calc-stack-size))

  ;; A region over a fraction: 1:2 is calc's fraction notation, not a
  ;; level prefix, and only the level prefix is stripped.
  (maf-push "1/2")
  (progn (calc-cursor-stack-index 1)
         (beginning-of-line)
         (push-mark (line-end-position) t t)
         (call-interactively 'maf-copy))
  (progn (deactivate-mark)
         (let ((last-command 'maf-copy)) (call-interactively 'maf-copy)))
  (cl-assert (string= (current-kill 0) "\\frac{1}{2}"))
  (calc-pop (calc-stack-size))

  ;; A product whose right factor is a \left( group: calc would write
  ;; \times there, but juxtaposition is unambiguous and reads better,
  ;; so the LaTeX copy drops it.
  (maf-push "(a+b) (c/d+e)")
  (progn (goto-char (point-max)) (call-interactively 'maf-copy))
  (let ((last-command 'maf-copy)) (call-interactively 'maf-copy))
  (cl-assert (string= (current-kill 0)
                      "(a + b) \\left( \\frac{c}{d} + e \\right)"))
  (calc-pop (calc-stack-size))

  ;; Logarithms: calc renders log(x, b) unTeXed and log10 as \log{x};
  ;; maf's compose forms subscript the base — except 10, which the
  ;; bare \log assumes.
  (maf-push "log(x, 3) + log10(y)")
  (progn (goto-char (point-max)) (call-interactively 'maf-copy))
  (let ((last-command 'maf-copy)) (call-interactively 'maf-copy))
  (cl-assert (string= (current-kill 0)
                      "\\log_{3}\\left( x \\right) + \\log\\left( y \\right)"))
  (calc-pop (calc-stack-size)))
