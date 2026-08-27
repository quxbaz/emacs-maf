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

  ;; The range grammar: lo:hi, :hi from 0, a single n symmetric.
  (cl-assert (equal (maf-plot--parse-range "2:8") '(2 . 8)))
  (cl-assert (equal (maf-plot--parse-range ":5") '(0 . 5)))
  (cl-assert (equal (maf-plot--parse-range "5") '(-5 . 5)))
  (cl-assert (let ((err (condition-case e
                            (progn (maf-plot--parse-range "8:2") nil)
                          (error t))))
                err))

  ;; Two variables have no axis to share; the sampler refuses.
  (cl-assert (let ((err (condition-case e
                            (progn (maf-plot--variable
                                    (math-read-expr "x + y"))
                                   nil)
                          (error (error-message-string e)))))
                (and err (string-match-p "2 variables" err))))

  ;; A vector entry is a curve set: one curve per element, labeled by
  ;; element; a relation element still contributes its rhs. Empty
  ;; vectors refuse. Desmos gets the elements whole, one expression
  ;; each.
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

  ;; A relation plots its right side on the gnuplot backends.
  (cl-assert (equal (maf-plot--function-of (math-read-expr "y = x^2"))
                    (math-read-expr "x^2")))
  (cl-assert (equal (maf-plot--function-of (math-read-expr "x^2 + 1"))
                    (math-read-expr "x^2 + 1")))

  ;; Desmos reads a stricter LaTeX than calc writes: brace arguments
  ;; become parens, bare-pipe abs becomes \left|...\right| (lifted at
  ;; the tree, since nested pipes cannot be re-paired in the string),
  ;; and exp goes to e^x. Desmos-native forms pass through untouched.
  (cl-assert (equal (maf-plot--desmos-latex (math-read-expr "cos(x)"))
                    "\\cos\\left(x\\right)"))
  (cl-assert (equal (maf-plot--desmos-latex (math-read-expr "sin(2 x)"))
                    "\\sin\\left(2 x\\right)"))
  (cl-assert (equal (maf-plot--desmos-latex
                     (math-read-expr "abs(abs(x) + 1)"))
                    "\\left|\\left|x\\right| + 1\\right|"))
  (cl-assert (equal (maf-plot--desmos-latex (math-read-expr "abs(sin(x))"))
                    "\\left|\\sin\\left(x\\right)\\right|"))
  (cl-assert (equal (maf-plot--desmos-latex (math-read-expr "exp(x)"))
                    "e^x"))
  (cl-assert (equal (maf-plot--desmos-latex (math-read-expr "sqrt(x)"))
                    "\\sqrt{x}"))
  (cl-assert (equal (maf-plot--desmos-latex (math-read-expr "log10(x)"))
                    "\\log_{10}\\left( x \\right)"))

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
