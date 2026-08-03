;; `maf-up-expression' climbs the formula, not the parentheses calc
;; happened to print. Every assertion below is about where point lands,
;; because point is the whole of maf's targeting: a landing is only
;; right if resolve names the node the motion advertised there, which is
;; what `maf-test--part-at-point' reads back.
;;
;; The climb is checked in the renderings that have no flat text to walk
;; — Big language, a matrix — since those are exactly where a
;; parenthesis-reading motion (`backward-up-list', which holds this key
;; globally) does nothing.

(defun maf-test--flat (expr)
  "EXPR in flat notation, with the selection machinery's encasing gone.
Flat rather than `math-format-value' so that one spelling serves every
step below: display notation is what the language renders, which for
the Big-language and matrix entries here runs over several lines."
  (math-format-flat-expr (maf--strip-encasing expr) 0))

(defun maf-test--part-at-point ()
  "The sub-formula point names, in flat notation."
  (let ((m (calc-locate-cursor-element (point))))
    (calc-prepare-selection m)
    (maf-test--flat (calc-find-selected-part))))

(maf-defcmd maf-square (expr _arg commit)
  "Square command."
  :arity unary
  :prefix "sqr"
  (commit (calcFunc-mul expr expr)))

(maf-step
  ;; The whole climb, one level per press. Only two of these five levels
  ;; carry parens: the rest are the ones calc's precedence rules let it
  ;; drop, and they are reached all the same.
  (maf-push "y = 2 (x + 3)^2 - 12")
  (progn (calc-cursor-stack-index 1)
         (search-forward "x" (line-end-position))
         (backward-char 1))
  (cl-assert (string= (maf-test--part-at-point) "x"))

  ;; Out of x: the term it sits in. Calc prints this one's parens, and
  ;; they are its own first glyph, so point lands on the open paren.
  (call-interactively 'maf-up-expression)
  (cl-assert (string= (maf-test--part-at-point) "x + 3"))
  (cl-assert (eq (char-after) ?\())

  ;; The power. Its parens belong to the term inside it, so its own
  ;; first glyph is the ^.
  (call-interactively 'maf-up-expression)
  (cl-assert (string= (maf-test--part-at-point) "(x + 3)^2"))
  (cl-assert (eq (char-after) ?^))

  ;; The product — printed with no operator at all. Its one glyph is the
  ;; space it renders the multiplication as, and point lands there.
  (call-interactively 'maf-up-expression)
  (cl-assert (string= (maf-test--part-at-point) "2 * (x + 3)^2"))
  (cl-assert (eq (char-after) ?\s))

  ;; The difference, then the relation: the whole entry.
  (call-interactively 'maf-up-expression)
  (cl-assert (string= (maf-test--part-at-point) "2 * (x + 3)^2 - 12"))
  (cl-assert (eq (char-after) ?-))
  (call-interactively 'maf-up-expression)
  (cl-assert (string= (maf-test--part-at-point) "y = 2 * (x + 3)^2 - 12"))
  (cl-assert (eq (char-after) ?=))

  ;; At the outermost formula the motion signals and point stands: there
  ;; is nothing above the entry to climb to.
  (setq up-test-pos (point))
  (cl-assert (eq :error (condition-case nil
                            (progn (call-interactively 'maf-up-expression) :ok)
                          (user-error :error))))
  (cl-assert (= (point) up-test-pos))
  (calc-pop (calc-stack-size))

  ;; The promise the motion makes: what point names after the climb is
  ;; what the next command acts on. Two presses out of the x, and the
  ;; square takes the power — not the x, and not the whole entry.
  (maf-push "2 (x + 3)^2 - 12")
  (progn (calc-cursor-stack-index 1)
         (search-forward "x" (line-end-position))
         (backward-char 1))
  (call-interactively 'maf-up-expression)
  (call-interactively 'maf-up-expression)
  (call-interactively 'maf-square)
  ;; The square of the power, simplified into one: the x alone would
  ;; have given 2 (x^2 + 3)^2 - 12, the whole entry (2 (x + 3)^2 - 12)^2.
  (cl-assert (string= (math-format-value (calc-top 1 'full))
                      "2 (x + 3)^4 - 12"))
  (calc-pop (calc-stack-size))

  ;; A numeric prefix climbs that many levels in one press.
  (maf-push "2 (x + 3)^2 - 12")
  (progn (calc-cursor-stack-index 1)
         (search-forward "x" (line-end-position))
         (backward-char 1))
  (let ((current-prefix-arg 3))
    (call-interactively 'maf-up-expression))
  (cl-assert (string= (maf-test--part-at-point) "2 * (x + 3)^2"))
  ;; More levels than the entry has climbs as far as it goes, and stops
  ;; at the whole entry rather than signaling part way.
  (let ((current-prefix-arg 9))
    (call-interactively 'maf-up-expression))
  (cl-assert (string= (maf-test--part-at-point) "2 * (x + 3)^2 - 12"))
  (calc-pop (calc-stack-size))

  ;; Big language: the rendering is two-dimensional and prints no parens
  ;; at all, so there is nothing for a text-scanning motion to walk. The
  ;; climb still finds the levels, and the fraction's own glyph is its
  ;; bar — on another line entirely.
  (call-interactively 'maf-toggle-big-language)
  (cl-assert (eq calc-language 'big))
  (maf-push "(a+b)/(c+d)")
  (progn (calc-cursor-stack-index 1)
         (search-forward "b" (line-end-position))
         (backward-char 1))
  (cl-assert (string= (maf-test--part-at-point) "b"))
  (call-interactively 'maf-up-expression)
  (cl-assert (string= (maf-test--part-at-point) "a + b"))
  (cl-assert (eq (char-after) ?+))
  (setq up-test-line (line-number-at-pos))
  (call-interactively 'maf-up-expression)
  (cl-assert (string= (maf-test--part-at-point) "(a + b) / (c + d)"))
  (cl-assert (eq (char-after) ?-))
  (cl-assert (= (line-number-at-pos) (1+ up-test-line)))
  (calc-pop (calc-stack-size))
  (call-interactively 'maf-toggle-big-language)
  (cl-assert (null calc-language))

  ;; A matrix draws its rows with brackets calc tags to the matrix
  ;; itself, so no position names a row. The climb walks past the level
  ;; it cannot land on rather than landing where resolve would name
  ;; something else: out of an element is the whole matrix.
  (maf-push "[[1,2],[3,4]]")
  (progn (calc-cursor-stack-index 1)
         (search-forward "3" nil t)
         (backward-char 1))
  (cl-assert (string= (maf-test--part-at-point) "3"))
  (call-interactively 'maf-up-expression)
  (cl-assert (string= (maf-test--part-at-point) "[[1, 2], [3, 4]]"))
  (cl-assert (eq (char-after) ?\[))
  (calc-pop (calc-stack-size))

  ;; The margins already name the whole entry, so there is nothing to
  ;; climb from: end of line, the line-number prefix, and home all
  ;; signal and leave point where it was.
  (maf-push "a b + c")
  (progn (calc-cursor-stack-index 1) (end-of-line))
  (cl-assert (eq :error (condition-case nil
                            (progn (call-interactively 'maf-up-expression) :ok)
                          (user-error :error))))
  (cl-assert (eolp))
  (progn (calc-cursor-stack-index 1) (beginning-of-line))
  (cl-assert (eq :error (condition-case nil
                            (progn (call-interactively 'maf-up-expression) :ok)
                          (user-error :error))))
  (cl-assert (bolp))
  (progn (calc-cursor-stack-index 0) (skip-chars-forward " "))
  (setq up-test-pos (point))
  (cl-assert (eq :error (condition-case nil
                            (progn (call-interactively 'maf-up-expression) :ok)
                          (user-error :error))))
  (cl-assert (= (point) up-test-pos))
  (calc-pop (calc-stack-size))

  ;; An entry below the top climbs in place, on its own lines.
  (maf-push "sin(p q + r)")
  (calc-push 99)
  (progn (calc-cursor-stack-index 2)
         (search-forward "q" (line-end-position))
         (backward-char 1))
  (call-interactively 'maf-up-expression)
  (cl-assert (string= (maf-test--part-at-point) "p * q"))
  (call-interactively 'maf-up-expression)
  (call-interactively 'maf-up-expression)
  (cl-assert (string= (maf-test--part-at-point) "sin(p * q + r)"))
  (cl-assert (= (calc-locate-cursor-element (point)) 2))
  (cl-assert (= (calc-stack-size) 2))
  (calc-pop (calc-stack-size))

  ;; With a selection up it is the selection, not point, that a command
  ;; resolves to — so the selection climbs along and stays what the next
  ;; command would act on.
  (maf-push "sin(p q + r)")
  (progn (calc-cursor-stack-index 1)
         (search-forward "q" (line-end-position))
         (backward-char 1)
         (call-interactively 'calc-select-here))
  (cl-assert (string= (maf-test--flat (maf--sel-effective-expr)) "q"))
  (call-interactively 'maf-up-expression)
  (cl-assert (string= (maf-test--flat (maf--sel-effective-expr)) "p * q"))
  ;; Point kept up with it: both name the same node.
  (cl-assert (string= (maf-test--part-at-point) "p * q"))
  (call-interactively 'maf-up-expression)
  (cl-assert (string= (maf-test--flat (maf--sel-effective-expr)) "p * q + r"))
  (calc-clear-selections)
  (calc-pop (calc-stack-size)))
