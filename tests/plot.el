;; maf-plot below the render: key claims, ranges, sampling, relation
;; handling, and the desmos URL contract. The renders themselves are
;; verified by eye (the pixels have no oracle here); everything the
;; backends consume is asserted. Run in a live Emacs (tests/README.md).
(maf-step
  ;; Global state the test flips; restored at the end.
  (progn (setq maf-plot-test--mode maf-use-plot-mode
               maf-plot-test--backend maf-plot-backend)
         nil)

  ;; On, the module claims its g keys; the rest of the prefix still
  ;; reaches stock calc-graph. Off restores stock wholly.
  (maf-use-plot-mode 1)
  (cl-assert (eq (key-binding (kbd "g g")) 'maf-plot-all))
  (cl-assert (eq (key-binding (kbd "g l")) 'maf-plot-entry))
  (cl-assert (eq (key-binding (kbd "g i")) 'maf-plot-entry-with-range))
  (cl-assert (eq (key-binding (kbd "g I")) 'maf-plot-all-with-range))
  (cl-assert (eq (key-binding (kbd "g o")) 'maf-plot-entry-desmos))
  (cl-assert (eq (key-binding (kbd "g f")) 'calc-graph-fast))
  (maf-use-plot-mode -1)
  (cl-assert (eq (key-binding (kbd "g g")) 'calc-graph-grid))
  (cl-assert (eq (key-binding (kbd "g l")) 'calc-graph-log-x))
  (maf-use-plot-mode 1)

  ;; Auto-range: trig widens to one period in the current angle mode —
  ;; a fresh calc is in degrees — and anything else gets the default.
  (cl-assert (eq calc-angle-mode 'deg))
  (cl-assert (equal (maf-plot--auto-range (list (math-read-expr "2 sin(x)")))
                    '(-360.0 . 360.0)))
  (cl-assert (equal (maf-plot--auto-range (list (math-read-expr "x^2")))
                    '(-10.0 . 10.0)))
  ;; One trig curve widens a whole overlay.
  (cl-assert (equal (maf-plot--auto-range
                     (list (math-read-expr "x^2") (math-read-expr "cos(x)")))
                    '(-360.0 . 360.0)))
  ;; Radians: one period is 2 pi.
  (calc-radians-mode)
  (cl-assert (< (abs (- (car (maf-plot--auto-range
                              (list (math-read-expr "sin(x)"))))
                        (- (* 2 float-pi))))
                1e-9))
  (calc-degrees-mode 1)

  ;; Sampling: sin over one degree period, every point real, the grid
  ;; hitting 90 exactly. Symbolic mode is deliberately on — sampling
  ;; must bind it off or trig samples all die (the calc-settings-file
  ;; leak made this a live failure, not a hypothetical).
  (progn (setq maf-plot-test--file (make-temp-file "maf-plot-test")) nil)
  (let ((calc-symbolic-mode t))
    (maf-plot--sample (math-read-expr "sin(x)") '(-360.0 . 360.0)
                      maf-plot-test--file))
  (progn (setq maf-plot-test--lines
               (with-temp-buffer
                 (insert-file-contents maf-plot-test--file)
                 (split-string (buffer-string) "\n" t)))
         nil)
  (cl-assert (= (length maf-plot-test--lines) 241))
  (cl-assert (string-prefix-p "-360.0 " (car maf-plot-test--lines)))
  (cl-assert (member "90.0 1." maf-plot-test--lines))

  ;; A pole is a gap, not a failure: 1/x over the default range skips
  ;; exactly the sample at 0.
  (maf-plot--sample (math-read-expr "1/x") '(-10.0 . 10.0)
                    maf-plot-test--file)
  (cl-assert (= (with-temp-buffer
                  (insert-file-contents maf-plot-test--file)
                  (length (split-string (buffer-string) "\n" t)))
                240))

  ;; A constant still plots — a horizontal line, no variable to bind.
  (maf-plot--sample (math-read-expr "5") '(-1.0 . 1.0) maf-plot-test--file)
  (cl-assert (member "0.0 5." (with-temp-buffer
                                (insert-file-contents maf-plot-test--file)
                                (split-string (buffer-string) "\n" t))))

  ;; A vector of numbers is data, not a curve set: one curve of
  ;; index→value points, values floated so a fraction is gnuplot-readable.
  (cl-assert (maf-plot--data-vector-p (math-read-expr "[1, 3, 2, 5]")))
  (cl-assert (not (maf-plot--data-vector-p (math-read-expr "[sin(x), 1]"))))
  (cl-assert (not (maf-plot--data-vector-p (math-read-expr "[]"))))
  (cl-assert (equal (maf-plot--curve-exprs (math-read-expr "[1, 3, 2, 5]"))
                    (list (cons (math-read-expr "[1, 3, 2, 5]")
                                "[1, 3, 2, 5]"))))
  (maf-plot--write-data (math-read-expr "[1, 3:2]") maf-plot-test--file)
  (cl-assert (equal (with-temp-buffer
                      (insert-file-contents maf-plot-test--file)
                      (split-string (buffer-string) "\n" t))
                    '("1 1." "2 1.5")))

  ;; The range grammar: lo:hi, :hi from 0, a single n symmetric.
  (cl-assert (equal (maf-plot--parse-range "2:8") '(2 . 8)))
  (cl-assert (equal (maf-plot--parse-range ":5") '(0 . 5)))
  (cl-assert (equal (maf-plot--parse-range "5") '(-5 . 5)))
  (cl-assert (let ((err (condition-case e
                            (progn (maf-plot--parse-range "8:2") nil)
                          (error t))))
                err))

  ;; The quadrant view centers on the origin: x the sampling span's
  ;; larger side, y the data's largest magnitude padded a twentieth —
  ;; both symmetric. Data hugging zero takes the floor instead of a
  ;; sliver of a frame.
  (cl-assert (let ((file (maf-plot--work-file "quad-test.dat")))
               (with-temp-file file (insert "-10 2\n4 -1.5\n"))
               (equal (maf-plot--quadrant-view
                       (list (list file "t" nil)) '(-10.0 . 10.0))
                      "set xrange [-10:10]\nset yrange [-2.1:2.1]\n")))
  (cl-assert (let ((file (maf-plot--work-file "quad-test.dat")))
               (with-temp-file file (insert "1 0.2\n"))
               (equal (maf-plot--quadrant-view
                       (list (list file "t" nil)) '(-10.0 . 10.0))
                      "set xrange [-10:10]\nset yrange [-1.05:1.05]\n")))

  ;; Two variables have no axis to share; the sampler refuses.
  (cl-assert (let ((err (condition-case e
                            (progn (maf-plot--variable
                                    (math-read-expr "x + y"))
                                   nil)
                          (error (error-message-string e)))))
                (and err (string-match-p "2 variables" err))))

  ;; A vector entry is a curve set: one curve per element, labeled by
  ;; element; a relation element keeps its shape here — its rhs is
  ;; taken at sampling, where a refusal can be skipped per curve.
  ;; Empty vectors refuse. Desmos gets the elements whole, one
  ;; expression each.
  (cl-assert (equal (maf-plot--curve-exprs
                     (math-read-expr "[2 sin(x), cos(x)]"))
                    (list (cons (math-read-expr "2 sin(x)") "2 sin(x)")
                          (cons (math-read-expr "cos(x)") "cos(x)"))))
  (cl-assert (equal (maf-plot--curve-exprs (math-read-expr "x^2"))
                    (list (cons (math-read-expr "x^2") "x^2"))))
  (cl-assert (condition-case nil
                 (progn (maf-plot--curve-exprs (math-read-expr "[]")) nil)
               (error t)))
  (cl-assert (equal (maf-plot--desmos-expressions
                     (list (math-read-expr "[sin(x), cos(x)]")
                           (math-read-expr "x^2")))
                    (list (math-read-expr "sin(x)")
                          (math-read-expr "cos(x)")
                          (math-read-expr "x^2"))))

  ;; Only y = f(x) plots its right side on the gnuplot backends. An
  ;; implicit equation, an equation between two expressions, or an
  ;; inequality would draw a lying curve; each refuses toward g o
  ;; (Desmos graphs relations whole).
  (cl-assert (equal (maf-plot--function-of (math-read-expr "y = x^2"))
                    (math-read-expr "x^2")))
  (cl-assert (equal (maf-plot--function-of (math-read-expr "x^2 + 1"))
                    (math-read-expr "x^2 + 1")))
  (cl-assert (let ((err (condition-case e
                            (progn (maf-plot--function-of
                                    (math-read-expr "x^2 + y^2 = 4"))
                                   nil)
                          (error (error-message-string e)))))
                (and err (string-match-p "Desmos" err))))
  (cl-assert (condition-case nil
                 (progn (maf-plot--function-of (math-read-expr "sin(x) = x/2"))
                        nil)
               (error t)))
  (cl-assert (condition-case nil
                 (progn (maf-plot--function-of (math-read-expr "x < 3")) nil)
               (error t)))

  ;; Desmos reads a stricter LaTeX than calc writes: brace arguments
  ;; become parens (arcsin and its kin — the six trig calls of
  ;; `maf--latex-paren-calls' already arrive parenthesized from maf's
  ;; own composer, which Desmos reads as written), bare-pipe abs
  ;; becomes \left|...\right| (lifted at the tree, since nested pipes
  ;; cannot be re-paired in the string), and exp goes to e^x.
  ;; Desmos-native forms pass through untouched.
  (cl-assert (equal (maf-plot--desmos-latex (math-read-expr "cos(x)"))
                    "\\cos(x)"))
  (cl-assert (equal (maf-plot--desmos-latex (math-read-expr "sin(2 x)"))
                    "\\sin(2 x)"))
  (cl-assert (equal (maf-plot--desmos-latex (math-read-expr "arcsin(x)"))
                    "\\arcsin\\left(x\\right)"))
  (cl-assert (equal (maf-plot--desmos-latex
                     (math-read-expr "abs(abs(x) + 1)"))
                    "\\left|\\left|x\\right| + 1\\right|"))
  (cl-assert (equal (maf-plot--desmos-latex (math-read-expr "abs(sin(x))"))
                    "\\left|\\sin(x)\\right|"))
  (cl-assert (equal (maf-plot--desmos-latex (math-read-expr "exp(x)"))
                    "e^x"))
  (cl-assert (equal (maf-plot--desmos-latex (math-read-expr "sqrt(x)"))
                    "\\sqrt{x}"))
  ;; The 10 the bare \log assumes stays unwritten, as in pretty.
  (cl-assert (equal (maf-plot--desmos-latex (math-read-expr "log10(x)"))
                    "\\log\\left( x \\right)"))

  ;; Desmos graphs in x and y: a lone foreign variable is renamed to x
  ;; (sin(t) as sent would offer a slider, not a curve). Constants
  ;; Desmos knows don't count as foreign; x present, or two foreign
  ;; variables, leave the expression alone.
  (cl-assert (equal (maf-plot--desmos-normalize (math-read-expr "sin(t)"))
                    (math-read-expr "sin(x)")))
  (cl-assert (equal (maf-plot--desmos-normalize (math-read-expr "y = 2 t"))
                    (math-read-expr "y = 2 x")))
  (cl-assert (equal (maf-plot--desmos-normalize (math-read-expr "pi t"))
                    (math-read-expr "pi x")))
  (cl-assert (equal (maf-plot--desmos-normalize (math-read-expr "sin(x) + t"))
                    (math-read-expr "sin(x) + t")))
  (cl-assert (equal (maf-plot--desmos-normalize (math-read-expr "a t"))
                    (math-read-expr "a t")))

  ;; A data vector goes to Desmos as points, preformatted.
  (cl-assert (equal (maf-plot--desmos-expressions
                     (list (math-read-expr "[1, 3]")))
                    (list "\\left(1,1\\right)" "\\left(2,3\\right)")))

  ;; The desmos URL: the fragment alone carries the graph — latex per
  ;; entry (relations whole), the angle mode, and the API key.
  (progn
    (setq maf-plot-test--spec
          (let* ((url (maf-plot--desmos-url
                       (list (math-read-expr "y = 2 sin(x + 1)"))))
                 (json (url-unhex-string
                        (substring url (1+ (string-match "#" url))))))
            (json-parse-string json :object-type 'alist)))
    nil)
  (cl-assert (equal (aref (alist-get 'e maf-plot-test--spec) 0)
                    "y = 2 \\sin(x + 1)"))
  (cl-assert (eq (alist-get 'd maf-plot-test--spec) t))
  (cl-assert (equal (alist-get 'k maf-plot-test--spec)
                    maf-plot-desmos-api-key))
  ;; No range given, no bounds sent — Desmos keeps its own viewport.
  (cl-assert (null (alist-get 'b maf-plot-test--spec)))
  ;; A range becomes the b pair: the viewport's opening x bounds.
  (cl-assert (equal (let* ((url (maf-plot--desmos-url
                                 (list (math-read-expr "sin(x)"))
                                 '(-5.0 . 5.0)))
                           (json (url-unhex-string
                                  (substring url (1+ (string-match "#" url))))))
                      (alist-get 'b (json-parse-string
                                     json :object-type 'alist)))
                    [-5.0 5.0]))
  ;; Radians mode turns degreeMode off.
  (calc-radians-mode)
  (cl-assert (eq (let* ((url (maf-plot--desmos-url
                              (list (math-read-expr "sin(x)"))))
                        (json (url-unhex-string
                               (substring url (1+ (string-match "#" url))))))
                   (alist-get 'd (json-parse-string json :object-type 'alist)))
                 :false))
  (calc-degrees-mode 1)

  ;; The page the URL opens ships beside the module.
  (cl-assert (file-exists-p
              (expand-file-name "maf-plot.html" maf-plot--load-directory)))

  ;; Restore what the test flipped.
  (progn (delete-file maf-plot-test--file)
         (setq maf-plot-backend maf-plot-test--backend)
         (maf-use-plot-mode (if maf-plot-test--mode 1 -1))
         nil))
